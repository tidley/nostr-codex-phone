use std::env;
use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use serde_json::Value;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

#[derive(Debug, Clone)]
pub struct CodexConfig {
    pub bin: String,
    pub args: Vec<String>,
    pub working_dir: PathBuf,
    pub timeout: Duration,
    pub persist_sessions: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CodexRunResult {
    pub response: String,
    pub session_id: Option<String>,
}

impl CodexConfig {
    pub fn from_env() -> Result<Self> {
        let bin = env::var("CODEX_BIN").unwrap_or_else(|_| "codex".to_string());
        let args = match env::var("CODEX_ARGS") {
            Ok(raw) if !raw.trim().is_empty() => shell_words::split(&raw)
                .with_context(|| format!("failed to parse CODEX_ARGS `{raw}`"))?,
            _ => vec![
                "--ask-for-approval".to_string(),
                "never".to_string(),
                "--sandbox".to_string(),
                "read-only".to_string(),
                "exec".to_string(),
                "--skip-git-repo-check".to_string(),
            ],
        };
        let working_dir = env::var("CODEX_WORKDIR")
            .map(PathBuf::from)
            .unwrap_or(env::current_dir().context("failed to resolve current directory")?);
        let timeout_secs = env::var("CODEX_TIMEOUT_SECS")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(180);
        let persist_sessions = env::var("CODEX_PERSIST_SESSIONS")
            .ok()
            .map(|value| !is_falsey(&value))
            .unwrap_or(true);

        Ok(Self {
            bin,
            args,
            working_dir,
            timeout: Duration::from_secs(timeout_secs),
            persist_sessions,
        })
    }
}

pub async fn run_codex(prompt: &str, config: &CodexConfig) -> Result<String> {
    let args = codex_stdin_args(config.args.clone());
    let output = run_codex_command(prompt, config, args).await?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !output.status.success() {
        if stderr.is_empty() {
            return Err(anyhow!("Codex exited with status {}", output.status));
        }
        return Err(anyhow!(
            "Codex exited with status {}: {}",
            output.status,
            stderr
        ));
    }

    if stdout.is_empty() {
        return Err(anyhow!("Codex completed but produced no stdout response"));
    }

    Ok(stdout)
}

pub async fn run_codex_session(
    prompt: &str,
    config: &CodexConfig,
    session_id: Option<&str>,
) -> Result<CodexRunResult> {
    if !config.persist_sessions {
        return run_codex(prompt, config)
            .await
            .map(|response| CodexRunResult {
                response,
                session_id: None,
            });
    }

    let args = codex_json_session_args(&config.args, session_id);
    let output = run_codex_command(prompt, config, args).await?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !output.status.success() {
        if stderr.is_empty() {
            return Err(anyhow!("Codex exited with status {}", output.status));
        }
        return Err(anyhow!(
            "Codex exited with status {}: {}",
            output.status,
            stderr
        ));
    }

    parse_codex_json_output(&stdout)
}

async fn run_codex_command(
    prompt: &str,
    config: &CodexConfig,
    args: Vec<String>,
) -> Result<std::process::Output> {
    let mut command = Command::new(&config.bin);
    command
        .args(args)
        .current_dir(&config.working_dir)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);

    let mut child = command.spawn().with_context(|| {
        format!(
            "failed to run `{}`; set CODEX_BIN/CODEX_ARGS if Codex is installed elsewhere",
            config.bin
        )
    })?;

    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| anyhow!("failed to open Codex stdin"))?;
    stdin
        .write_all(prompt.as_bytes())
        .await
        .context("failed to write prompt to Codex stdin")?;
    stdin
        .shutdown()
        .await
        .context("failed to close Codex stdin")?;
    drop(stdin);

    tokio::time::timeout(config.timeout, child.wait_with_output())
        .await
        .map_err(|_| anyhow!("Codex timed out after {}s", config.timeout.as_secs()))?
        .context("failed to wait for Codex output")
}

fn codex_stdin_args(mut args: Vec<String>) -> Vec<String> {
    ensure_exec_subcommand(&mut args);
    args.push("-".to_string());
    args
}

fn codex_json_session_args(args: &[String], session_id: Option<&str>) -> Vec<String> {
    let mut args = strip_arg(args, "--ephemeral");
    let exec_index = ensure_exec_subcommand(&mut args);

    match session_id.map(str::trim).filter(|value| !value.is_empty()) {
        Some(session_id) => {
            args.insert(exec_index + 1, "resume".to_string());
            ensure_arg_after(&mut args, exec_index + 2, "--json");
            args.push(session_id.to_string());
            args.push("-".to_string());
        }
        None => {
            ensure_arg_after(&mut args, exec_index + 1, "--json");
            args.push("-".to_string());
        }
    }
    args
}

fn ensure_exec_subcommand(args: &mut Vec<String>) -> usize {
    if let Some(index) = args.iter().position(|arg| arg == "exec" || arg == "e") {
        return index;
    }
    args.push("exec".to_string());
    args.len() - 1
}

fn ensure_arg_after(args: &mut Vec<String>, index: usize, arg: &str) {
    if args.iter().any(|existing| existing == arg) {
        return;
    }
    args.insert(index.min(args.len()), arg.to_string());
}

fn strip_arg(args: &[String], arg: &str) -> Vec<String> {
    args.iter()
        .filter(|value| value.as_str() != arg)
        .cloned()
        .collect()
}

fn parse_codex_json_output(stdout: &str) -> Result<CodexRunResult> {
    let mut session_id = None;
    let mut response = None;
    let mut errors = Vec::new();

    for line in stdout
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
    {
        let value: Value = serde_json::from_str(line)
            .with_context(|| format!("Codex emitted invalid JSONL event: {line}"))?;
        match value.get("type").and_then(Value::as_str) {
            Some("thread.started") => {
                if let Some(thread_id) = value.get("thread_id").and_then(Value::as_str) {
                    session_id = Some(thread_id.to_string());
                }
            }
            Some("item.completed") => {
                let Some(item) = value.get("item") else {
                    continue;
                };
                if item.get("type").and_then(Value::as_str) == Some("agent_message") {
                    if let Some(text) = item.get("text").and_then(Value::as_str) {
                        response = Some(text.trim().to_string());
                    }
                }
            }
            Some("turn.failed") | Some("error") => {
                errors.push(value.to_string());
            }
            _ => {}
        }
    }

    if let Some(response) = response.filter(|value| !value.is_empty()) {
        return Ok(CodexRunResult {
            response,
            session_id,
        });
    }

    if !errors.is_empty() {
        return Err(anyhow!("Codex failed: {}", errors.join("\n")));
    }

    Err(anyhow!("Codex completed but produced no agent message"))
}

fn is_falsey(value: &str) -> bool {
    matches!(
        value.trim().to_ascii_lowercase().as_str(),
        "0" | "false" | "no" | "off" | "disabled"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_new_session_args_without_ephemeral() {
        let args = vec![
            "--ask-for-approval".to_string(),
            "never".to_string(),
            "exec".to_string(),
            "--ephemeral".to_string(),
            "--skip-git-repo-check".to_string(),
        ];

        assert_eq!(
            codex_json_session_args(&args, None),
            vec![
                "--ask-for-approval",
                "never",
                "exec",
                "--json",
                "--skip-git-repo-check",
                "-"
            ]
        );
    }

    #[test]
    fn builds_resume_args_without_ephemeral() {
        let args = vec![
            "--sandbox".to_string(),
            "read-only".to_string(),
            "exec".to_string(),
            "--ephemeral".to_string(),
            "--skip-git-repo-check".to_string(),
        ];

        assert_eq!(
            codex_json_session_args(&args, Some("session-1")),
            vec![
                "--sandbox",
                "read-only",
                "exec",
                "resume",
                "--json",
                "--skip-git-repo-check",
                "session-1",
                "-"
            ]
        );
    }

    #[test]
    fn parses_jsonl_response_and_session() {
        let parsed = parse_codex_json_output(
            r#"{"type":"thread.started","thread_id":"0199a213-81c0-7800-8aa1-bbab2a035a53"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":"Done."}}
{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}"#,
        )
        .unwrap();

        assert_eq!(parsed.response, "Done.");
        assert_eq!(
            parsed.session_id.as_deref(),
            Some("0199a213-81c0-7800-8aa1-bbab2a035a53")
        );
    }
}
