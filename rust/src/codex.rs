use std::env;
use std::path::PathBuf;
use std::process::{Output, Stdio};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use reqwest::StatusCode;
use serde::{Deserialize, Serialize};
use serde_json::json;
use serde_json::Value;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt};
use tokio::process::Command;
use tokio::sync::mpsc;
use tokio::time::{sleep, timeout};

const OPENCODE_CONTROL_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Debug, Clone)]
pub struct CodexConfig {
    pub backend: AgentBackend,
    pub bin: String,
    pub args: Vec<String>,
    pub working_dir: PathBuf,
    pub timeout: Duration,
    pub persist_sessions: bool,
    pub usage_limit_fallback_model: Option<String>,
    pub opencode: OpenCodeConfig,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentBackend {
    OpenCode,
    Codex,
}

#[derive(Debug, Clone)]
pub struct OpenCodeConfig {
    pub base_url: String,
    pub bin: String,
    pub auto_start: bool,
    pub username: Option<String>,
    pub password: Option<String>,
    pub agent: String,
    pub model: Option<OpenCodeModel>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OpenCodeModel {
    #[serde(rename = "providerID")]
    pub provider_id: String,
    #[serde(rename = "modelID")]
    pub model_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpenCodeSessionInfo {
    pub id: String,
    pub title: String,
    pub directory: Option<String>,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
}

impl OpenCodeSessionInfo {
    fn sort_key(&self) -> &str {
        self.updated_at
            .as_deref()
            .or(self.created_at.as_deref())
            .unwrap_or_default()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CodexRunResult {
    pub response: String,
    pub session_id: Option<String>,
}

pub type CodexJsonEventSender = mpsc::UnboundedSender<Value>;

#[derive(Debug, Clone, Default)]
pub struct CodexCancelToken {
    cancelled: Arc<AtomicBool>,
}

impl CodexCancelToken {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::SeqCst)
    }
}

impl CodexConfig {
    pub fn from_env() -> Result<Self> {
        let backend = agent_backend_from_env();
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
        let working_dir = env::var("AGENT_WORKDIR")
            .or_else(|_| env::var("OPENCODE_WORKDIR"))
            .or_else(|_| env::var("CODEX_WORKDIR"))
            .map(PathBuf::from)
            .unwrap_or(env::current_dir().context("failed to resolve current directory")?);
        let timeout_secs = env::var("AGENT_TIMEOUT_SECS")
            .or_else(|_| env::var("OPENCODE_TIMEOUT_SECS"))
            .or_else(|_| env::var("CODEX_TIMEOUT_SECS"))
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(180);
        let persist_sessions = env::var("AGENT_PERSIST_SESSIONS")
            .or_else(|_| env::var("OPENCODE_PERSIST_SESSIONS"))
            .or_else(|_| env::var("CODEX_PERSIST_SESSIONS"))
            .ok()
            .map(|value| !is_falsey(&value))
            .unwrap_or(true);
        let usage_limit_fallback_model = env::var("CODEX_USAGE_LIMIT_FALLBACK_MODEL")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty() && !is_falsey(value))
            .or_else(|| (backend == AgentBackend::Codex).then(|| "gpt-5.5".to_string()));
        let opencode = OpenCodeConfig::from_env()?;

        Ok(Self {
            backend,
            bin,
            args,
            working_dir,
            timeout: Duration::from_secs(timeout_secs),
            persist_sessions,
            usage_limit_fallback_model,
            opencode,
        })
    }

    pub fn with_model_override(&self, model: &str) -> Self {
        let mut config = self.clone();
        match config.backend {
            AgentBackend::Codex => {
                config.args = codex_args_with_model_override(&config.args, model);
            }
            AgentBackend::OpenCode => {
                config.opencode.model = parse_opencode_model(model).or(config.opencode.model);
            }
        }
        config
    }
}

impl OpenCodeConfig {
    fn from_env() -> Result<Self> {
        let base_url = env::var("OPENCODE_URL")
            .unwrap_or_else(|_| "http://127.0.0.1:4096".to_string())
            .trim_end_matches('/')
            .to_string();
        let bin = env::var("OPENCODE_BIN").unwrap_or_else(|_| default_opencode_bin());
        let auto_start = env::var("OPENCODE_AUTO_START")
            .ok()
            .map(|value| !is_falsey(&value))
            .unwrap_or(true);
        let password = env::var("OPENCODE_PASSWORD")
            .or_else(|_| env::var("OPENCODE_SERVER_PASSWORD"))
            .ok()
            .filter(|value| !value.trim().is_empty());
        let username = env::var("OPENCODE_USERNAME")
            .or_else(|_| env::var("OPENCODE_SERVER_USERNAME"))
            .ok()
            .filter(|value| !value.trim().is_empty())
            .or_else(|| password.as_ref().map(|_| "opencode".to_string()));
        let agent = env::var("OPENCODE_AGENT")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "build".to_string());
        let model = env::var("OPENCODE_MODEL")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .map(|value| {
                parse_opencode_model(&value)
                    .ok_or_else(|| anyhow!("OPENCODE_MODEL must be `provider/model`"))
            })
            .transpose()?;

        Ok(Self {
            base_url,
            bin,
            auto_start,
            username,
            password,
            agent,
            model,
        })
    }
}

pub async fn run_codex(prompt: &str, config: &CodexConfig) -> Result<String> {
    run_codex_with_cancel(prompt, config, None).await
}

pub async fn run_codex_with_cancel(
    prompt: &str,
    config: &CodexConfig,
    cancel_token: Option<&CodexCancelToken>,
) -> Result<String> {
    if config.backend == AgentBackend::OpenCode {
        return run_opencode_session(prompt, config, None, cancel_token)
            .await
            .map(|result| result.response);
    }

    let args = codex_stdin_args(config.args.clone());
    let output = run_codex_command(prompt, config, args, cancel_token, None).await?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !output.status.success() {
        return Err(codex_exit_error(output.status, &stdout, &stderr));
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
    run_codex_session_with_cancel(prompt, config, session_id, None).await
}

pub async fn run_codex_session_with_cancel(
    prompt: &str,
    config: &CodexConfig,
    session_id: Option<&str>,
    cancel_token: Option<&CodexCancelToken>,
) -> Result<CodexRunResult> {
    run_codex_session_with_cancel_and_events(prompt, config, session_id, cancel_token, None).await
}

pub async fn run_codex_session_with_cancel_and_events(
    prompt: &str,
    config: &CodexConfig,
    session_id: Option<&str>,
    cancel_token: Option<&CodexCancelToken>,
    event_sender: Option<CodexJsonEventSender>,
) -> Result<CodexRunResult> {
    if config.backend == AgentBackend::OpenCode {
        return run_opencode_session(prompt, config, session_id, cancel_token).await;
    }

    if !config.persist_sessions {
        return run_codex_with_cancel(prompt, config, cancel_token)
            .await
            .map(|response| CodexRunResult {
                response,
                session_id: None,
            });
    }

    let args = codex_json_session_args(&config.args, session_id);
    let output = run_codex_command(prompt, config, args, cancel_token, event_sender).await?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !output.status.success() {
        return Err(codex_exit_error(output.status, &stdout, &stderr));
    }

    parse_codex_json_output(&stdout)
}

pub async fn list_opencode_sessions(config: &CodexConfig) -> Result<Vec<OpenCodeSessionInfo>> {
    if config.backend != AgentBackend::OpenCode {
        return Err(anyhow!("OpenCode sessions require AGENT_BACKEND=opencode"));
    }

    let client = reqwest::Client::new();
    ensure_opencode_available(&client, config).await?;
    list_opencode_sessions_with_client(&client, config).await
}

pub async fn ensure_opencode_session(config: &CodexConfig) -> Result<String> {
    if config.backend != AgentBackend::OpenCode {
        return Err(anyhow!("OpenCode sessions require AGENT_BACKEND=opencode"));
    }

    let client = reqwest::Client::new();
    ensure_opencode_available(&client, config).await?;
    match latest_opencode_session_id(&client, config).await? {
        Some(session_id) => Ok(session_id),
        None => create_opencode_session(&client, config).await,
    }
}

async fn run_opencode_session(
    prompt: &str,
    config: &CodexConfig,
    session_id: Option<&str>,
    cancel_token: Option<&CodexCancelToken>,
) -> Result<CodexRunResult> {
    let client = reqwest::Client::new();
    ensure_opencode_available(&client, config).await?;
    let session_id = match session_id.map(str::trim).filter(|value| !value.is_empty()) {
        Some(session_id) => session_id.to_string(),
        None => match latest_opencode_session_id(&client, config).await? {
            Some(session_id) => session_id,
            None => create_opencode_session(&client, config).await?,
        },
    };
    let body = opencode_prompt_body(prompt, &config.opencode);
    let request = opencode_request(
        &client,
        config,
        reqwest::Method::POST,
        &format!("/session/{session_id}/message"),
    )
    .json(&body);

    let response = tokio::select! {
        response = request.send() => response.context("failed to send prompt to OpenCode")?,
        _ = wait_for_cancel(cancel_token), if cancel_token.is_some() => {
            let _ = abort_opencode_session(&client, config, &session_id).await;
            return Err(anyhow!("Codex cancelled"));
        }
        _ = sleep(config.timeout) => {
            let _ = abort_opencode_session(&client, config, &session_id).await;
            return Err(anyhow!("OpenCode timed out after {}s", config.timeout.as_secs()));
        }
    };
    let value = opencode_json_response(response).await?;
    Ok(CodexRunResult {
        response: opencode_response_text(&value)?,
        session_id: Some(session_id),
    })
}

async fn latest_opencode_session_id(
    client: &reqwest::Client,
    config: &CodexConfig,
) -> Result<Option<String>> {
    Ok(list_opencode_sessions_with_client(client, config)
        .await?
        .into_iter()
        .next()
        .map(|session| session.id))
}

async fn ensure_opencode_available(client: &reqwest::Client, config: &CodexConfig) -> Result<()> {
    if opencode_health(client, config).await.is_ok() {
        return Ok(());
    }
    if !config.opencode.auto_start || !can_autostart_opencode(&config.opencode.base_url) {
        opencode_health(client, config).await?;
        return Ok(());
    }

    Command::new(&config.opencode.bin)
        .args(["serve", "--hostname", "127.0.0.1", "--port", "4096"])
        .current_dir(&config.working_dir)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(false)
        .spawn()
        .with_context(|| {
            format!(
                "failed to start `{} serve`; install OpenCode or set OPENCODE_URL to a running server",
                config.opencode.bin
            )
        })?;

    for _ in 0..20 {
        sleep(Duration::from_millis(250)).await;
        if opencode_health(client, config).await.is_ok() {
            return Ok(());
        }
    }

    opencode_health(client, config).await
}

async fn opencode_health(client: &reqwest::Client, config: &CodexConfig) -> Result<()> {
    let response = timeout(
        OPENCODE_CONTROL_TIMEOUT,
        opencode_request(client, config, reqwest::Method::GET, "/global/health").send(),
    )
    .await
    .context("timed out checking OpenCode health")?
    .context("OpenCode server is not reachable")?;
    let status = response.status();
    if status.is_success() {
        return Ok(());
    }
    let body = response.text().await.unwrap_or_default();
    Err(anyhow!(
        "OpenCode health check failed with {status}: {body}"
    ))
}

fn can_autostart_opencode(base_url: &str) -> bool {
    matches!(
        base_url.trim_end_matches('/'),
        "http://127.0.0.1:4096" | "http://localhost:4096"
    )
}

async fn list_opencode_sessions_with_client(
    client: &reqwest::Client,
    config: &CodexConfig,
) -> Result<Vec<OpenCodeSessionInfo>> {
    let response = timeout(
        OPENCODE_CONTROL_TIMEOUT,
        opencode_request(client, config, reqwest::Method::GET, "/session")
            .query(&[("limit", "50")])
            .send(),
    )
    .await
    .context("timed out listing OpenCode sessions")?
    .context("failed to list OpenCode sessions")?;
    let value = opencode_json_response(response).await?;
    parse_opencode_session_list(&value)
}

async fn create_opencode_session(client: &reqwest::Client, config: &CodexConfig) -> Result<String> {
    let response = timeout(
        OPENCODE_CONTROL_TIMEOUT,
        opencode_request(client, config, reqwest::Method::POST, "/session")
            .json(&json!({ "title": "OpenCode Remote" }))
            .send(),
    )
    .await
    .context("timed out creating OpenCode session")?
    .context("failed to create OpenCode session")?;
    let value = opencode_json_response(response).await?;
    value
        .get("id")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
        .ok_or_else(|| anyhow!("OpenCode session create response did not include `id`: {value}"))
}

async fn abort_opencode_session(
    client: &reqwest::Client,
    config: &CodexConfig,
    session_id: &str,
) -> Result<()> {
    let response = opencode_request(
        client,
        config,
        reqwest::Method::POST,
        &format!("/session/{session_id}/abort"),
    )
    .send()
    .await
    .context("failed to abort OpenCode session")?;
    let status = response.status();
    if !status.is_success() && status != StatusCode::NOT_FOUND {
        let body = response.text().await.unwrap_or_default();
        return Err(anyhow!("OpenCode abort failed with {status}: {body}"));
    }
    Ok(())
}

fn opencode_request(
    client: &reqwest::Client,
    config: &CodexConfig,
    method: reqwest::Method,
    path: &str,
) -> reqwest::RequestBuilder {
    let url = format!("{}{}", config.opencode.base_url, path);
    let mut request = client
        .request(method, url)
        .query(&[("directory", config.working_dir.to_string_lossy().as_ref())]);
    if let Some(password) = config.opencode.password.as_deref() {
        request = request.basic_auth(
            config.opencode.username.as_deref().unwrap_or("opencode"),
            Some(password),
        );
    }
    request
}

fn parse_opencode_session_list(value: &Value) -> Result<Vec<OpenCodeSessionInfo>> {
    let sessions = value
        .as_array()
        .or_else(|| value.get("sessions").and_then(Value::as_array))
        .or_else(|| value.get("items").and_then(Value::as_array))
        .ok_or_else(|| anyhow!("OpenCode session list response was not an array: {value}"))?;

    let mut sessions = sessions
        .iter()
        .filter_map(opencode_session_info_from_value)
        .collect::<Vec<_>>();
    sessions.sort_by(|left, right| right.sort_key().cmp(left.sort_key()));
    Ok(sessions)
}

fn opencode_session_info_from_value(value: &Value) -> Option<OpenCodeSessionInfo> {
    let id = json_string_at(value, &["id"])
        .or_else(|| json_string_at(value, &["sessionID"]))
        .or_else(|| json_string_at(value, &["sessionId"]))?;
    let title = json_string_at(value, &["title"])
        .or_else(|| json_string_at(value, &["name"]))
        .unwrap_or_else(|| id.clone());
    let directory = json_string_at(value, &["directory"])
        .or_else(|| json_string_at(value, &["workspaceDir"]))
        .or_else(|| json_string_at(value, &["workspace_dir"]))
        .or_else(|| json_string_at(value, &["cwd"]))
        .or_else(|| json_string_at(value, &["path", "cwd"]))
        .or_else(|| json_string_at(value, &["path", "root"]));
    let created_at = json_string_at(value, &["createdAt"])
        .or_else(|| json_string_at(value, &["created_at"]))
        .or_else(|| json_string_at(value, &["time", "created"]));
    let updated_at = json_string_at(value, &["updatedAt"])
        .or_else(|| json_string_at(value, &["updated_at"]))
        .or_else(|| json_string_at(value, &["time", "updated"]))
        .or_else(|| json_string_at(value, &["time", "modified"]));

    Some(OpenCodeSessionInfo {
        id,
        title,
        directory,
        created_at,
        updated_at,
    })
}

fn json_string_at(value: &Value, path: &[&str]) -> Option<String> {
    let mut current = value;
    for key in path {
        current = current.get(*key)?;
    }
    match current {
        Value::String(value) => non_empty_string(value),
        Value::Number(value) => Some(value.to_string()),
        _ => None,
    }
}

fn non_empty_string(value: &str) -> Option<String> {
    let value = value.trim();
    if value.is_empty() {
        None
    } else {
        Some(value.to_string())
    }
}

fn opencode_prompt_body(prompt: &str, opencode: &OpenCodeConfig) -> Value {
    let mut body = json!({
        "agent": &opencode.agent,
        "parts": [{ "type": "text", "text": prompt }],
    });
    if let Some(model) = &opencode.model {
        body["model"] = serde_json::to_value(model).expect("model serializes");
    }
    body
}

async fn opencode_json_response(response: reqwest::Response) -> Result<Value> {
    let status = response.status();
    let body = response
        .text()
        .await
        .context("failed to read OpenCode response")?;
    if !status.is_success() {
        return Err(anyhow!("OpenCode returned {status}: {body}"));
    }
    serde_json::from_str(&body).with_context(|| format!("OpenCode returned invalid JSON: {body}"))
}

fn opencode_response_text(value: &Value) -> Result<String> {
    let text = value
        .get("parts")
        .and_then(Value::as_array)
        .and_then(|parts| {
            parts.iter().rev().find_map(|part| {
                if part.get("type").and_then(Value::as_str) == Some("text") {
                    part.get("text").and_then(Value::as_str)
                } else {
                    None
                }
            })
        })
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned);

    if let Some(text) = text {
        return Ok(text);
    }

    if let Some(error) = value
        .get("info")
        .and_then(|info| info.get("error"))
        .or_else(|| value.get("error"))
    {
        return Err(anyhow!("OpenCode failed: {error}"));
    }

    Err(anyhow!(
        "OpenCode completed but produced no text response: {value}"
    ))
}

async fn run_codex_command(
    prompt: &str,
    config: &CodexConfig,
    args: Vec<String>,
    cancel_token: Option<&CodexCancelToken>,
    event_sender: Option<CodexJsonEventSender>,
) -> Result<Output> {
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

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| anyhow!("failed to open Codex stdout"))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| anyhow!("failed to open Codex stderr"))?;
    let stdout_task = tokio::spawn(read_stdout(stdout, event_sender));
    let stderr_task = tokio::spawn(read_output(stderr));

    let status_result = tokio::select! {
        status = child.wait() => status.context("failed to wait for Codex output"),
        _ = wait_for_cancel(cancel_token), if cancel_token.is_some() => {
            let _ = child.kill().await;
            Err(anyhow!("Codex cancelled"))
        }
        _ = sleep(config.timeout) => {
            let _ = child.kill().await;
            Err(anyhow!("Codex timed out after {}s", config.timeout.as_secs()))
        }
    };

    let status = match status_result {
        Ok(status) => status,
        Err(err) => {
            let _ = stdout_task.await;
            let _ = stderr_task.await;
            return Err(err);
        }
    };

    let stdout = stdout_task
        .await
        .context("failed to join Codex stdout reader")??;
    let stderr = stderr_task
        .await
        .context("failed to join Codex stderr reader")??;

    Ok(Output {
        status,
        stdout,
        stderr,
    })
}

async fn read_stdout<R>(reader: R, event_sender: Option<CodexJsonEventSender>) -> Result<Vec<u8>>
where
    R: AsyncRead + Unpin + Send + 'static,
{
    if event_sender.is_none() {
        return read_output(reader).await;
    }

    let event_sender = event_sender.expect("checked above");
    let mut reader = reader;
    let mut output = Vec::new();
    let mut pending_line = Vec::new();
    let mut buffer = [0_u8; 8192];

    loop {
        let read = reader
            .read(&mut buffer)
            .await
            .context("failed to read Codex stdout")?;
        if read == 0 {
            break;
        }
        output.extend_from_slice(&buffer[..read]);
        pending_line.extend_from_slice(&buffer[..read]);

        while let Some(index) = pending_line.iter().position(|byte| *byte == b'\n') {
            let line = pending_line.drain(..=index).collect::<Vec<_>>();
            emit_codex_json_event(&event_sender, &line);
        }
    }

    if !pending_line.is_empty() {
        emit_codex_json_event(&event_sender, &pending_line);
    }

    Ok(output)
}

async fn read_output<R>(mut reader: R) -> Result<Vec<u8>>
where
    R: AsyncRead + Unpin + Send + 'static,
{
    let mut output = Vec::new();
    reader
        .read_to_end(&mut output)
        .await
        .context("failed to read Codex output")?;
    Ok(output)
}

fn emit_codex_json_event(sender: &CodexJsonEventSender, line: &[u8]) {
    let Ok(text) = std::str::from_utf8(line) else {
        return;
    };
    let text = text.trim();
    if text.is_empty() {
        return;
    }
    if let Ok(value) = serde_json::from_str::<Value>(text) {
        let _ = sender.send(value);
    }
}

async fn wait_for_cancel(cancel_token: Option<&CodexCancelToken>) {
    let Some(cancel_token) = cancel_token else {
        std::future::pending::<()>().await;
        return;
    };
    while !cancel_token.is_cancelled() {
        sleep(Duration::from_millis(100)).await;
    }
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

fn codex_args_with_model_override(args: &[String], model: &str) -> Vec<String> {
    let mut output = Vec::with_capacity(args.len() + 2);
    let mut iter = args.iter();

    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "-m" | "--model" => {
                let _ = iter.next();
            }
            "-c" | "--config" => {
                let Some(value) = iter.next() else {
                    output.push(arg.clone());
                    continue;
                };
                if !is_model_config(value) {
                    output.push(arg.clone());
                    output.push(value.clone());
                }
            }
            _ if arg.starts_with("--model=") => {}
            _ if arg.starts_with("--config=") => {
                let value = arg.trim_start_matches("--config=");
                if !is_model_config(value) {
                    output.push(arg.clone());
                }
            }
            _ => output.push(arg.clone()),
        }
    }

    let insert_at = output
        .iter()
        .position(|arg| arg == "exec" || arg == "e")
        .unwrap_or(output.len());
    output.insert(insert_at, "-m".to_string());
    output.insert(insert_at + 1, model.to_string());
    output
}

fn is_model_config(value: &str) -> bool {
    value
        .split_once('=')
        .map(|(key, _)| key.trim() == "model")
        .unwrap_or(false)
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

fn codex_exit_error(status: std::process::ExitStatus, stdout: &str, stderr: &str) -> anyhow::Error {
    let mut details = Vec::new();
    if !stderr.is_empty() {
        details.push(format!("stderr: {stderr}"));
    }
    if !stdout.is_empty() {
        details.push(format!("stdout: {stdout}"));
    }

    if details.is_empty() {
        anyhow!("Codex exited with status {status}")
    } else {
        anyhow!("Codex exited with status {status}: {}", details.join("\n"))
    }
}

pub fn is_codex_usage_limit_error(err: &anyhow::Error) -> bool {
    is_codex_usage_limit_message(&format!("{err:#}"))
}

pub fn is_codex_usage_limit_message(message: &str) -> bool {
    let message = message.to_ascii_lowercase();
    (message.contains("usage limit")
        && (message.contains("hit") || message.contains("reached") || message.contains("exceeded")))
        || message.contains("switch to another model")
}

fn is_falsey(value: &str) -> bool {
    matches!(
        value.trim().to_ascii_lowercase().as_str(),
        "0" | "false" | "no" | "off" | "disabled"
    )
}

fn default_opencode_bin() -> String {
    default_opencode_bin_for_home(env::var_os("HOME").map(PathBuf::from))
}

fn default_opencode_bin_for_home(home: Option<PathBuf>) -> String {
    let Some(home) = home else {
        return "opencode".to_string();
    };
    let candidate = home.join(".opencode").join("bin").join("opencode");
    if candidate.is_file() {
        candidate.to_string_lossy().into_owned()
    } else {
        "opencode".to_string()
    }
}

fn agent_backend_from_env() -> AgentBackend {
    let raw = env::var("AGENT_BACKEND")
        .or_else(|_| env::var("AI_BACKEND"))
        .unwrap_or_else(|_| "opencode".to_string());
    match raw.trim().to_ascii_lowercase().as_str() {
        "codex" => AgentBackend::Codex,
        _ => AgentBackend::OpenCode,
    }
}

fn parse_opencode_model(value: &str) -> Option<OpenCodeModel> {
    let (provider_id, model_id) = value.split_once('/')?;
    let provider_id = provider_id.trim();
    let model_id = model_id.trim();
    if provider_id.is_empty() || model_id.is_empty() {
        return None;
    }
    Some(OpenCodeModel {
        provider_id: provider_id.to_string(),
        model_id: model_id.to_string(),
    })
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
    fn overrides_codex_model_args() {
        let args = vec![
            "--ask-for-approval".to_string(),
            "never".to_string(),
            "-m".to_string(),
            "gpt-5.3-codex-spark".to_string(),
            "-c".to_string(),
            "model=\"gpt-5.4\"".to_string(),
            "-c".to_string(),
            "model_reasoning_effort=medium".to_string(),
            "exec".to_string(),
            "--skip-git-repo-check".to_string(),
        ];

        assert_eq!(
            codex_args_with_model_override(&args, "gpt-5.5"),
            vec![
                "--ask-for-approval",
                "never",
                "-c",
                "model_reasoning_effort=medium",
                "-m",
                "gpt-5.5",
                "exec",
                "--skip-git-repo-check",
            ]
        );
    }

    #[test]
    fn detects_codex_usage_limit_errors() {
        assert!(is_codex_usage_limit_message(
            "Turn error: You've hit your usage limit for GPT-5.3-Codex-Spark. Switch to another model now."
        ));
        assert!(!is_codex_usage_limit_message(
            "Codex exited with status exit status: 1"
        ));
    }

    #[test]
    fn emits_live_json_events() {
        let (tx, mut rx) = mpsc::unbounded_channel();
        emit_codex_json_event(&tx, br#"{"type":"turn.started"}"#);
        emit_codex_json_event(&tx, b"not json");

        let event = rx.try_recv().unwrap();
        assert_eq!(
            event.get("type").and_then(Value::as_str),
            Some("turn.started")
        );
        assert!(rx.try_recv().is_err());
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

    #[test]
    fn parses_opencode_sessions_from_array_or_object() {
        let value = json!({
            "sessions": [
                {
                    "id": "older",
                    "title": "Older",
                    "directory": "/repo",
                    "time": { "updated": 1, "created": 1 }
                },
                {
                    "id": "newer",
                    "title": "Newer",
                    "path": { "cwd": "/repo" },
                    "updatedAt": "2026-07-09T12:00:00Z"
                }
            ]
        });

        let sessions = parse_opencode_session_list(&value).unwrap();

        assert_eq!(sessions[0].id, "newer");
        assert_eq!(sessions[0].directory.as_deref(), Some("/repo"));
        assert_eq!(sessions[1].updated_at.as_deref(), Some("1"));
    }

    #[test]
    fn defaults_to_user_opencode_install_when_present() {
        let temp_dir = tempfile::tempdir().unwrap();
        let bin_dir = temp_dir.path().join(".opencode").join("bin");
        std::fs::create_dir_all(&bin_dir).unwrap();
        let opencode = bin_dir.join("opencode");
        std::fs::write(&opencode, "").unwrap();

        assert_eq!(
            default_opencode_bin_for_home(Some(temp_dir.path().to_path_buf())),
            opencode.to_string_lossy()
        );
        assert_eq!(default_opencode_bin_for_home(None), "opencode");
    }
}
