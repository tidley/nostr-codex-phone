use std::env;
use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use tokio::process::Command;

#[derive(Debug, Clone)]
pub struct CodexConfig {
    pub bin: String,
    pub args: Vec<String>,
    pub working_dir: PathBuf,
    pub timeout: Duration,
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
                "--ephemeral".to_string(),
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

        Ok(Self {
            bin,
            args,
            working_dir,
            timeout: Duration::from_secs(timeout_secs),
        })
    }
}

pub async fn run_codex(prompt: &str, config: &CodexConfig) -> Result<String> {
    let mut command = Command::new(&config.bin);
    command
        .args(&config.args)
        .arg(prompt)
        .current_dir(&config.working_dir)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);

    let output = tokio::time::timeout(config.timeout, command.output())
        .await
        .map_err(|_| anyhow!("Codex timed out after {}s", config.timeout.as_secs()))?
        .with_context(|| {
            format!(
                "failed to run `{}`; set CODEX_BIN/CODEX_ARGS if Codex is installed elsewhere",
                config.bin
            )
        })?;

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
