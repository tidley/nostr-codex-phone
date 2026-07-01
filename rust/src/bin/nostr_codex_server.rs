use std::any::Any;
use std::collections::{HashMap, HashSet, VecDeque};
use std::env;
use std::fs::{self, File};
use std::io::{BufRead, BufReader};
use std::panic::AssertUnwindSafe;
use std::path::{Path, PathBuf};
use std::process::Command as StdCommand;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{bail, Context, Result};
use futures_util::FutureExt;
use nostr_sdk::prelude::{Keys, PublicKey, ToBech32};
use qrcode::{Color, QrCode};
use rand::{rngs::OsRng, RngCore};
#[path = "nostr_codex_server/memory.rs"]
mod memory;
use memory::{MemoryConfig, MemoryStore, RecordedMessage};
use rust_lib_nostr_codex_phone::codex::{
    is_codex_usage_limit_error, run_codex, run_codex_session_with_cancel, CodexCancelToken,
    CodexConfig, CodexRunResult,
};
use rust_lib_nostr_codex_phone::nostr_client::{
    default_relays, IncomingMessage, NostrConfig, NostrMessenger,
};
use rust_lib_nostr_codex_phone::protocol::{
    parse_media_bundle_query, parse_wire_message, AudioReference, MediaBundle, MediaReference,
    RepoList, RepoListEntry, RepoListRoot, TargetInvite, TargetParent, WireMessage,
};
use rust_lib_nostr_codex_phone::transcribe::{
    download_blossom_attachment, download_blossom_audio, transcribe_audio, AudioConfig,
    DownloadedAudio, TranscribeConfig,
};
use serde::{Deserialize, Serialize};
use tokio::sync::{mpsc, Notify};
use tracing::{error, info, warn};

const WORKER_STATE_DIR: &str = ".nostr-codex";
const WORKER_REGISTRY_FILE: &str = "workers.json";
const WORKER_LOCK_FILE: &str = "worker.lock";
const CODEX_RESUME_TIMEOUT: Duration = Duration::from_secs(45);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RequestClass {
    Command,
    Coding,
    Clarification,
    MemoryLookup,
    NoOp,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct SpawnWorkerRequest {
    workdir: String,
    create: bool,
    silent: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CancelRequest {
    event_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum NonblockingControlRequest {
    Spawn(SpawnWorkerRequest),
    RepoList,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WorkerRegistry {
    #[serde(default)]
    workers: Vec<WorkerRegistryEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WorkerRegistryEntry {
    name: String,
    pubkey: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pubkey_hex: Option<String>,
    workdir: String,
    pid: u32,
    relays: Vec<String>,
}

#[derive(Debug, Clone)]
struct WorkerEnvFile {
    path: PathBuf,
}

struct WorkerProcessLock {
    path: PathBuf,
}

struct RepoTargetContext {
    workdir: PathBuf,
    relays: Vec<String>,
}

struct RepoWorkerContext {
    workdir: PathBuf,
    env_file: WorkerEnvFile,
    secret_key: String,
    public_key: String,
    public_key_hex: String,
    relays: Vec<String>,
    relay_csv: String,
    memory_db: PathBuf,
}

struct WorkerRuntimeConfig {
    messenger: Arc<NostrMessenger>,
    worker_env: WorkerEnvFile,
    owner_peer_hex: Option<String>,
    pairing_secret: Option<String>,
    control: RuntimeControl,
    memory_config: MemoryConfig,
    codex_config: CodexConfig,
    audio_config: AudioConfig,
    transcribe_config: TranscribeConfig,
    relays: Vec<String>,
    manager: RepoRuntimeManager,
}

#[derive(Debug, Clone)]
struct RepoRuntimeManager;

impl RepoRuntimeManager {
    fn new() -> Self {
        Self
    }
}

#[derive(Clone)]
struct RuntimeControl {
    is_root: bool,
    shutdown_requested: Arc<AtomicBool>,
    shutdown_notify: Arc<Notify>,
}

impl RuntimeControl {
    fn new(is_root: bool) -> Self {
        Self {
            is_root,
            shutdown_requested: Arc::new(AtomicBool::new(false)),
            shutdown_notify: Arc::new(Notify::new()),
        }
    }

    fn request_shutdown(&self) {
        self.shutdown_requested.store(true, Ordering::SeqCst);
        self.shutdown_notify.notify_waiters();
    }

    fn is_shutdown_requested(&self) -> bool {
        self.shutdown_requested.load(Ordering::SeqCst)
    }
}

impl Drop for WorkerProcessLock {
    fn drop(&mut self) {
        match fs::read_to_string(&self.path) {
            Ok(raw) if raw.trim() == std::process::id().to_string() => {
                if let Err(err) = fs::remove_file(&self.path) {
                    warn!(
                        "failed to remove worker lock `{}`: {err:#}",
                        self.path.display()
                    );
                }
            }
            Ok(_) => {}
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => warn!(
                "failed to inspect worker lock `{}` during cleanup: {err:#}",
                self.path.display()
            ),
        }
    }
}

impl WorkerEnvFile {
    fn for_workdir(workdir: &Path) -> Self {
        let path = env::var("NOSTR_CODEX_ENV_FILE")
            .map(PathBuf::from)
            .unwrap_or_else(|_| default_worker_env_path(workdir));
        Self { path }
    }

    fn default_for_workdir(workdir: &Path) -> Self {
        Self {
            path: worker_state_path(workdir, ".env.server"),
        }
    }

    fn load_missing(&self) -> Result<()> {
        if !self.path.is_file() {
            return Ok(());
        }

        for (key, value) in self.read_values()? {
            if env::var_os(&key).is_none() {
                env::set_var(key, value);
            }
        }

        Ok(())
    }

    fn read_values(&self) -> Result<HashMap<String, String>> {
        let mut values = HashMap::new();
        if !self.path.is_file() {
            return Ok(values);
        }

        let raw = fs::read_to_string(&self.path)
            .with_context(|| format!("failed to read worker env file `{}`", self.path.display()))?;
        for line in raw.lines() {
            if let Some((key, value)) = parse_env_assignment(line) {
                values.insert(key, value);
            }
        }
        Ok(values)
    }
}

fn worker_state_dir(workdir: &Path) -> PathBuf {
    workdir.join(WORKER_STATE_DIR)
}

fn worker_state_path(workdir: &Path, file_name: &str) -> PathBuf {
    worker_state_dir(workdir).join(file_name)
}

fn default_worker_env_path(workdir: &Path) -> PathBuf {
    let path = worker_state_path(workdir, ".env.server");
    let legacy_path = workdir.join(".env.server");
    if path.is_file() || !legacy_path.is_file() {
        path
    } else {
        legacy_path
    }
}

fn handle_cli_args() -> Result<bool> {
    let mut args = env::args().skip(1);
    let Some(first) = args.next() else {
        return Ok(false);
    };

    match first.as_str() {
        "--generate-key" | "generate-key" => {
            print_generated_key()?;
            Ok(true)
        }
        "--help" | "-h" => {
            println!("nostr-codex-server");
            println!("  --generate-key    print a fresh Nostr nsec/npub pair");
            Ok(true)
        }
        _ => Ok(false),
    }
}

fn print_generated_key() -> Result<()> {
    let keys = Keys::generate();
    println!("NOSTR_SECRET_KEY={}", keys.secret_key().to_bech32()?);
    println!("NOSTR_PUBLIC_KEY={}", keys.public_key().to_bech32()?);
    println!("NOSTR_PUBLIC_KEY_HEX={}", keys.public_key().to_hex());
    Ok(())
}

fn initial_workdir() -> Result<PathBuf> {
    if let Ok(workdir) = env::var("CODEX_WORKDIR") {
        return Ok(PathBuf::from(workdir));
    }
    env::current_dir().context("failed to resolve worker directory")
}

fn ensure_worker_secret(env_file: &WorkerEnvFile) -> Result<String> {
    if let Some(secret_key) = env_nonempty("NOSTR_SECRET_KEY") {
        return Ok(secret_key);
    }

    let keys = Keys::generate();
    let secret_key = keys.secret_key().to_bech32()?;
    let public_key = keys.public_key().to_bech32()?;
    let public_key_hex = keys.public_key().to_hex();
    upsert_env_file_values(
        &env_file.path,
        &[
            ("NOSTR_SECRET_KEY", secret_key.as_str()),
            ("NOSTR_PUBLIC_KEY", public_key.as_str()),
            ("NOSTR_PUBLIC_KEY_HEX", public_key_hex.as_str()),
        ],
    )?;
    env::set_var("NOSTR_SECRET_KEY", &secret_key);
    env::set_var("NOSTR_PUBLIC_KEY", &public_key);
    env::set_var("NOSTR_PUBLIC_KEY_HEX", &public_key_hex);
    info!(
        "generated and saved worker Nostr identity: {}",
        env_file.path.display()
    );

    Ok(secret_key)
}

fn env_nonempty(key: &str) -> Option<String> {
    env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn allow_first_owner_claim() -> bool {
    env::var("NOSTR_ALLOW_FIRST_OWNER_CLAIM")
        .ok()
        .map(|value| !is_falsey_env(&value))
        .unwrap_or(false)
}

fn generate_pairing_secret() -> String {
    let mut bytes = [0_u8; 16];
    OsRng.fill_bytes(&mut bytes);
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn parse_env_assignment(line: &str) -> Option<(String, String)> {
    let line = line.trim();
    if line.is_empty() || line.starts_with('#') {
        return None;
    }
    let line = line.strip_prefix("export ").unwrap_or(line).trim();
    let (key, value) = line.split_once('=')?;
    let key = key.trim();
    if !is_env_key(key) {
        return None;
    }

    Some((key.to_string(), unquote_env_value(value.trim()).to_string()))
}

fn is_env_key(key: &str) -> bool {
    let mut chars = key.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    if !(first == '_' || first.is_ascii_alphabetic()) {
        return false;
    }
    chars.all(|ch| ch == '_' || ch.is_ascii_alphanumeric())
}

fn unquote_env_value(value: &str) -> &str {
    if value.len() >= 2 {
        let bytes = value.as_bytes();
        let first = bytes[0];
        let last = bytes[value.len() - 1];
        if (first == b'\'' && last == b'\'') || (first == b'"' && last == b'"') {
            return &value[1..value.len() - 1];
        }
    }
    value
}

fn upsert_env_file_values(path: &Path, values: &[(&str, &str)]) -> Result<()> {
    let replacements: HashMap<&str, &str> = values.iter().copied().collect();
    let mut seen = HashSet::<String>::new();
    let mut lines = Vec::new();

    if path.is_file() {
        let raw = fs::read_to_string(path)
            .with_context(|| format!("failed to read worker env file `{}`", path.display()))?;
        for line in raw.lines() {
            if let Some((key, _)) = parse_env_assignment(line) {
                if let Some(value) = replacements.get(key.as_str()) {
                    lines.push(format!("{key}={}", format_env_value(value)));
                    seen.insert(key);
                    continue;
                }
            }
            lines.push(line.to_string());
        }
    }

    for (key, value) in values {
        if !seen.contains(*key) {
            lines.push(format!("{key}={}", format_env_value(value)));
        }
    }

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| {
            format!(
                "failed to create worker env directory `{}`",
                parent.display()
            )
        })?;
    }
    fs::write(path, format!("{}\n", lines.join("\n")))
        .with_context(|| format!("failed to write worker env file `{}`", path.display()))?;
    set_private_file_permissions(path);

    Ok(())
}

fn upsert_env_file_owned(path: &Path, values: &[(String, String)]) -> Result<()> {
    let borrowed = values
        .iter()
        .map(|(key, value)| (key.as_str(), value.as_str()))
        .collect::<Vec<_>>();
    upsert_env_file_values(path, &borrowed)
}

fn format_env_value(value: &str) -> String {
    if value.chars().all(|ch| {
        ch.is_ascii_alphanumeric() || matches!(ch, '_' | '-' | '.' | '/' | ':' | ',' | '+')
    }) {
        value.to_string()
    } else {
        format!("'{}'", value.replace('\'', "'\\''"))
    }
}

#[cfg(unix)]
fn set_private_file_permissions(path: &Path) {
    use std::os::unix::fs::PermissionsExt;

    if let Err(err) = fs::set_permissions(path, fs::Permissions::from_mode(0o600)) {
        warn!(
            "failed to set private permissions on `{}`: {err:#}",
            path.display()
        );
    }
}

#[cfg(not(unix))]
fn set_private_file_permissions(_path: &Path) {}

fn pubkey_to_hex(pubkey: &str) -> Result<String> {
    Ok(PublicKey::parse(pubkey.trim())?.to_hex())
}

fn accept_or_claim_owner(
    env_file: &WorkerEnvFile,
    owner_peer_hex: &mut Option<String>,
    pairing_secret: &Option<String>,
    message: &IncomingMessage,
) -> bool {
    match owner_peer_hex.as_deref() {
        Some(owner) if owner != message.sender_pubkey_hex => {
            warn!(
                "ignored DM from non-owner {}; owner is {}",
                message.sender_pubkey_hex, owner
            );
            false
        }
        Some(_) => true,
        None => {
            if !allow_first_owner_claim() && !pairing_secret_matches(pairing_secret, message) {
                warn!(
                    "ignored first-owner claim from {} without matching pairing secret",
                    message.sender_pubkey_hex
                );
                return false;
            }
            info!(
                "claiming first DM sender as worker owner: {}",
                message.sender_pubkey
            );
            if let Err(err) = upsert_env_file_values(
                &env_file.path,
                &[
                    ("NOSTR_PEER_PUBKEY", message.sender_pubkey.as_str()),
                    ("NOSTR_PEER_PUBKEY_HEX", message.sender_pubkey_hex.as_str()),
                ],
            ) {
                warn!(
                    "failed to save worker owner `{}` to `{}`: {err:#}",
                    message.sender_pubkey,
                    env_file.path.display()
                );
            }
            *owner_peer_hex = Some(message.sender_pubkey_hex.clone());
            true
        }
    }
}

fn pairing_secret_matches(pairing_secret: &Option<String>, message: &IncomingMessage) -> bool {
    let Some(expected) = pairing_secret
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    else {
        return false;
    };
    message_pairing_secret(message).as_deref() == Some(expected)
}

fn message_pairing_secret(message: &IncomingMessage) -> Option<String> {
    pairing_secret_from_json(&message.text).or_else(|| pairing_secret_from_json(&message.raw_json))
}

fn pairing_secret_from_json(raw: &str) -> Option<String> {
    let value: serde_json::Value = serde_json::from_str(raw).ok()?;
    let object = value.as_object()?;
    object
        .get("pairing_secret")
        .or_else(|| object.get("pairingSecret"))
        .and_then(|value| value.as_str())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn is_pairing_claim_message(message: &IncomingMessage) -> bool {
    message_pairing_secret(message).is_some()
}

fn routed_codex_config(config: &CodexConfig, message: &IncomingMessage) -> Result<CodexConfig> {
    let Some(workdir) = route_workdir_from_json(&message.raw_json)
        .or_else(|| route_workdir_from_json(&message.text))
    else {
        return Ok(config.clone());
    };

    let workdir = PathBuf::from(workdir);
    let canonical = workdir
        .canonicalize()
        .with_context(|| format!("route workdir `{}` is not accessible", workdir.display()))?;
    if !canonical.is_dir() {
        bail!("route workdir `{}` is not a directory", canonical.display());
    }

    let mut routed = config.clone();
    routed.working_dir = canonical;
    Ok(routed)
}

fn route_workdir_from_json(raw: &str) -> Option<String> {
    let value: serde_json::Value = serde_json::from_str(raw).ok()?;
    value
        .get("workdir")
        .or_else(|| value.get("route")?.as_object()?.get("workdir"))
        .and_then(|value| value.as_str())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn route_session_id_from_json(raw: &str) -> Option<String> {
    let value: serde_json::Value = serde_json::from_str(raw).ok()?;
    value
        .get("session_id")
        .or_else(|| value.get("sessionId"))
        .and_then(|value| value.as_str())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

#[tokio::main]
async fn main() -> Result<()> {
    if handle_cli_args()? {
        return Ok(());
    }

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "nostr_codex_server=info,warn".into()),
        )
        .init();

    let initial_workdir = initial_workdir()?;
    if env::var_os("CODEX_WORKDIR").is_none() {
        env::set_var("CODEX_WORKDIR", &initial_workdir);
    }
    let initial_env = WorkerEnvFile::for_workdir(&initial_workdir);
    initial_env.load_missing()?;
    let codex_config = CodexConfig::from_env()?;
    let worker_env = WorkerEnvFile::for_workdir(&codex_config.working_dir);
    if worker_env.path != initial_env.path {
        worker_env.load_missing()?;
    }
    let _worker_lock = acquire_worker_process_lock(&codex_config.working_dir)?;
    let nostr_config = nostr_config_from_env(&worker_env)?;
    let audio_config = AudioConfig::from_env();
    let transcribe_config = TranscribeConfig::from_env()?;
    let memory_config = MemoryConfig::from_env(&codex_config.working_dir);
    let memory_probe = open_memory_store(memory_config.clone());
    let messenger = Arc::new(NostrMessenger::connect(nostr_config.clone()).await?);
    let owner_peer_hex = nostr_config
        .peer_pubkey
        .as_deref()
        .map(pubkey_to_hex)
        .transpose()?;
    let pairing_secret = owner_peer_hex.is_none().then(generate_pairing_secret);

    let server_pubkey = messenger.public_key_bech32()?;
    info!("server pubkey: {}", server_pubkey);
    info!("server pubkey hex: {}", messenger.public_key_hex());
    match &nostr_config.peer_pubkey {
        Some(peer) => info!("peer pubkey: {peer}"),
        None => warn!(
            "peer pubkey not configured; first DM must include the QR pairing secret to claim ownership"
        ),
    }
    info!("relays: {}", nostr_config.relays.join(", "));
    info!(
        "codex command: {} {}",
        codex_config.bin,
        codex_config.args.join(" ")
    );
    info!(
        "persistent codex sessions: {}",
        codex_config.persist_sessions
    );
    match &codex_config.usage_limit_fallback_model {
        Some(model) => info!("codex usage-limit fallback model: {model}"),
        None => info!("codex usage-limit fallback model: disabled"),
    }
    info!(
        "transcribe command: {} {}",
        transcribe_config.bin,
        transcribe_config.args.join(" ")
    );
    info!("max audio bytes: {}", audio_config.max_bytes);
    match &memory_probe {
        Some(memory) => info!("memory database: {}", memory.db_path().display()),
        None => warn!("SQLite memory is disabled or unavailable"),
    }
    write_worker_target_qr(
        &server_pubkey,
        &messenger.public_key_hex(),
        &codex_config.working_dir,
        &nostr_config.relays,
        pairing_secret.as_deref(),
    );
    drop(memory_probe);

    let manager = RepoRuntimeManager::new();
    run_worker_runtime(WorkerRuntimeConfig {
        messenger,
        worker_env,
        owner_peer_hex,
        pairing_secret,
        control: RuntimeControl::new(true),
        memory_config,
        codex_config,
        audio_config,
        transcribe_config,
        relays: nostr_config.relays,
        manager,
    })
    .await
}

async fn run_worker_runtime(mut config: WorkerRuntimeConfig) -> Result<()> {
    let mut peer_workers = HashMap::<String, mpsc::Sender<IncomingMessage>>::new();

    loop {
        let message = tokio::select! {
            message = config.messenger.next_message(Duration::from_secs(3600)) => message?,
            _ = config.control.shutdown_notify.notified() => {
                if config.control.is_shutdown_requested() {
                    info!("runtime shutdown requested");
                    return Ok(());
                }
                continue;
            }
        };
        let Some(message) = message else { continue };
        if !accept_or_claim_owner(
            &config.worker_env,
            &mut config.owner_peer_hex,
            &config.pairing_secret,
            &message,
        ) {
            continue;
        }

        let worker_key = message.sender_pubkey_hex.clone();
        let sender = peer_workers
            .entry(worker_key.clone())
            .or_insert_with(|| {
                spawn_peer_worker(
                    worker_key.clone(),
                    Arc::clone(&config.messenger),
                    config.memory_config.clone(),
                    config.codex_config.clone(),
                    config.audio_config.clone(),
                    config.transcribe_config.clone(),
                    config.relays.clone(),
                    config.manager.clone(),
                    config.control.clone(),
                )
            })
            .clone();

        if let Err(send_err) = sender.send(message).await {
            warn!("peer worker for {worker_key} stopped; restarting and retrying message");
            peer_workers.remove(&worker_key);
            let message = send_err.0;
            let sender = spawn_peer_worker(
                worker_key.clone(),
                Arc::clone(&config.messenger),
                config.memory_config.clone(),
                config.codex_config.clone(),
                config.audio_config.clone(),
                config.transcribe_config.clone(),
                config.relays.clone(),
                config.manager.clone(),
                config.control.clone(),
            );
            if sender.send(message).await.is_err() {
                error!("restarted peer worker for {worker_key} stopped; dropping incoming message");
            } else {
                peer_workers.insert(worker_key, sender);
            }
        }
    }
}

fn spawn_peer_worker(
    peer_pubkey: String,
    messenger: Arc<NostrMessenger>,
    memory_config: MemoryConfig,
    codex_config: CodexConfig,
    audio_config: AudioConfig,
    transcribe_config: TranscribeConfig,
    relays: Vec<String>,
    manager: RepoRuntimeManager,
    control: RuntimeControl,
) -> mpsc::Sender<IncomingMessage> {
    let (tx, rx) = mpsc::channel(32);
    tokio::spawn(peer_worker(
        peer_pubkey,
        rx,
        messenger,
        memory_config,
        codex_config,
        audio_config,
        transcribe_config,
        relays,
        manager,
        control,
    ));
    tx
}

async fn peer_worker(
    peer_pubkey: String,
    mut receiver: mpsc::Receiver<IncomingMessage>,
    messenger: Arc<NostrMessenger>,
    memory_config: MemoryConfig,
    codex_config: CodexConfig,
    audio_config: AudioConfig,
    transcribe_config: TranscribeConfig,
    relays: Vec<String>,
    manager: RepoRuntimeManager,
    control: RuntimeControl,
) {
    let mut memory = open_memory_store(memory_config);
    info!("started worker for peer {peer_pubkey}");
    let mut backlog = VecDeque::<IncomingMessage>::new();

    loop {
        let message = if let Some(message) = backlog.pop_front() {
            message
        } else {
            let Some(message) = receiver.recv().await else {
                break;
            };
            message
        };
        let event_id = message.event_id.clone();
        let sender_pubkey_hex = message.sender_pubkey_hex.clone();
        let kind = message.kind.clone();
        let cancel_token = CodexCancelToken::new();
        let processing = AssertUnwindSafe(process_message(
            message,
            &messenger,
            &mut memory,
            &codex_config,
            &audio_config,
            &transcribe_config,
            &relays,
            &manager,
            &control,
            &cancel_token,
        ))
        .catch_unwind();
        tokio::pin!(processing);

        let mut receiver_open = true;
        let result = loop {
            tokio::select! {
                result = &mut processing => break result,
                next_message = receiver.recv(), if receiver_open => {
                    match next_message {
                        Some(next_message) => {
                            if let Some(cancel_request) = parse_cancel_message(&next_message) {
                                if !cancel_request_matches(&cancel_request, &event_id) {
                                    send_status(
                                        &messenger,
                                        &next_message.sender_pubkey_hex,
                                        "No matching active task to cancel.",
                                    )
                                    .await;
                                    continue;
                                }
                                cancel_token.cancel();
                                send_status(
                                    &messenger,
                                    &next_message.sender_pubkey_hex,
                                    "Cancelling current task...",
                                )
                                .await;
                            } else if !process_nonblocking_control_message(
                                &next_message,
                                &messenger,
                                &relays,
                                &codex_config,
                                &audio_config,
                                &transcribe_config,
                                &manager,
                            )
                            .await
                            {
                                backlog.push_back(next_message);
                            }
                        }
                        None => {
                            receiver_open = false;
                        }
                    }
                }
            }
        };

        if let Err(payload) = result {
            let details = panic_payload_description(payload.as_ref());
            error!(
                "peer worker recovered from panic while processing {kind} event {event_id} from {sender_pubkey_hex}: {details}"
            );
            if let Err(err) = messenger
                .send_error_to(
                    &sender_pubkey_hex,
                    "Server hit an internal error while processing that message. The worker recovered; please retry the request.",
                )
                .await
            {
                error!("failed to send recovered-panic error DM: {err:#}");
            }
        }
    }
}

fn panic_payload_description(payload: &(dyn Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<&'static str>() {
        return (*message).to_string();
    }
    if let Some(message) = payload.downcast_ref::<String>() {
        return message.clone();
    }
    "non-string panic payload".to_string()
}

async fn process_nonblocking_control_message(
    message: &IncomingMessage,
    messenger: &NostrMessenger,
    relays: &[String],
    codex_config: &CodexConfig,
    audio_config: &AudioConfig,
    transcribe_config: &TranscribeConfig,
    manager: &RepoRuntimeManager,
) -> bool {
    match nonblocking_control_request(&message.kind, &message.text) {
        Some(NonblockingControlRequest::Spawn(spawn_request)) => {
            info!(
                "processing spawn request event {} while codex task is active",
                message.event_id
            );
            process_spawn_worker_request(
                messenger,
                &message.sender_pubkey,
                &message.sender_pubkey_hex,
                &spawn_request,
                relays,
                codex_config,
                audio_config,
                transcribe_config,
                manager,
            )
            .await;
            true
        }
        Some(NonblockingControlRequest::RepoList) => {
            info!(
                "processing repo list request event {} while codex task is active",
                message.event_id
            );
            process_repo_list_request(messenger, &message.sender_pubkey_hex).await;
            true
        }
        None => false,
    }
}

fn nonblocking_control_request(kind: &str, text: &str) -> Option<NonblockingControlRequest> {
    if kind != "query" {
        return None;
    }
    if let Some(spawn_request) = parse_spawn_worker_request(text) {
        return Some(NonblockingControlRequest::Spawn(spawn_request));
    }
    if is_repo_list_request(text) {
        return Some(NonblockingControlRequest::RepoList);
    }
    None
}

async fn process_message(
    message: IncomingMessage,
    messenger: &NostrMessenger,
    memory: &mut Option<MemoryStore>,
    codex_config: &CodexConfig,
    audio_config: &AudioConfig,
    transcribe_config: &TranscribeConfig,
    relays: &[String],
    manager: &RepoRuntimeManager,
    control: &RuntimeControl,
    cancel_token: &CodexCancelToken,
) {
    let codex_config = match routed_codex_config(codex_config, &message) {
        Ok(config) => config,
        Err(err) => {
            send_response(
                messenger,
                &message.sender_pubkey_hex,
                format!("Invalid route: {err:#}"),
            )
            .await;
            return;
        }
    };
    let route_session_id = route_session_id_from_json(&message.raw_json)
        .or_else(|| route_session_id_from_json(&message.text));

    match message.kind.as_str() {
        "query" => {
            info!(
                "received query event {} from {}",
                message.event_id, message.sender_pubkey
            );

            if parse_cancel_message(&message).is_some() {
                send_status(
                    messenger,
                    &message.sender_pubkey_hex,
                    "No active task to cancel.",
                )
                .await;
                return;
            }

            if is_pairing_claim_message(&message) {
                send_status(messenger, &message.sender_pubkey_hex, "Paired.").await;
                return;
            }

            if let Ok(media_bundle) = parse_media_bundle_query(&message.text) {
                process_media_bundle_turn(
                    messenger,
                    memory,
                    &message.sender_pubkey_hex,
                    &message,
                    media_bundle,
                    audio_config,
                    transcribe_config,
                    &codex_config,
                    route_session_id.as_deref(),
                    cancel_token,
                )
                .await;
                return;
            }

            if is_shutdown_request(&message.text) {
                if !is_shutdown_confirm_request(&message.text) {
                    send_response(
                        messenger,
                        &message.sender_pubkey_hex,
                        "Shutdown requires confirmation. Send `/shutdown confirm` to stop this worker.".to_string(),
                    )
                    .await;
                    return;
                }
                if control.is_root {
                    send_response(
                        messenger,
                        &message.sender_pubkey_hex,
                        "Confirmed. Shutting down the root Nostr Codex service.".to_string(),
                    )
                    .await;
                    info!("owner confirmed root worker shutdown");
                    std::process::exit(0);
                }
                send_response(
                    messenger,
                    &message.sender_pubkey_hex,
                    "Confirmed. Stopping this repo worker runtime.".to_string(),
                )
                .await;
                info!("owner confirmed repo worker runtime shutdown");
                control.request_shutdown();
                return;
            }

            if let Some(spawn_request) = parse_spawn_worker_request(&message.text) {
                process_spawn_worker_request(
                    messenger,
                    &message.sender_pubkey,
                    &message.sender_pubkey_hex,
                    &spawn_request,
                    relays,
                    &codex_config,
                    audio_config,
                    transcribe_config,
                    manager,
                )
                .await;
                return;
            }

            if is_repo_list_request(&message.text) {
                process_repo_list_request(messenger, &message.sender_pubkey_hex).await;
                return;
            }

            if let Some(response) = handle_local_request(
                memory,
                &message.sender_pubkey_hex,
                &message.text,
                &codex_config.working_dir,
            ) {
                send_response(messenger, &message.sender_pubkey_hex, response).await;
                return;
            }

            let Some(recorded) = remember_incoming(
                memory,
                &message.sender_pubkey_hex,
                &message.event_id,
                "query",
                &message.text,
            ) else {
                return;
            };
            if !recorded.inserted {
                info!("ignored already-persisted query event {}", message.event_id);
                return;
            }

            process_text_turn(
                messenger,
                memory,
                &message.sender_pubkey_hex,
                recorded.id,
                &message.text,
                &codex_config,
                route_session_id.as_deref(),
                cancel_token,
            )
            .await;
        }
        "media_bundle" => {
            info!(
                "received media_bundle event {} from {}",
                message.event_id, message.sender_pubkey
            );
            let from_json = parse_wire_message(&message.raw_json)
                .ok()
                .and_then(|message| message.media_bundle_ref().cloned());
            if let Some(media_bundle) =
                from_json.or_else(|| parse_media_bundle_query(&message.text).ok())
            {
                process_media_bundle_turn(
                    messenger,
                    memory,
                    &message.sender_pubkey_hex,
                    &message,
                    media_bundle,
                    audio_config,
                    transcribe_config,
                    &codex_config,
                    route_session_id.as_deref(),
                    cancel_token,
                )
                .await;
            } else {
                if let Err(err) = messenger
                    .send_error_to(
                        &message.sender_pubkey_hex,
                        "Malformed media_bundle request".to_string(),
                    )
                    .await
                {
                    error!("failed to send malformed media bundle error DM: {err:#}");
                }
            }
        }
        "audio" => {
            info!(
                "received audio event {} from {}",
                message.event_id, message.sender_pubkey
            );
            let Some(recorded) = remember_incoming(
                memory,
                &message.sender_pubkey_hex,
                &message.event_id,
                "audio",
                &message.text,
            ) else {
                return;
            };
            if !recorded.inserted {
                info!("ignored already-persisted audio event {}", message.event_id);
                return;
            }

            let audio = match parse_wire_message(&message.raw_json) {
                Ok(WireMessage::Audio { audio }) => audio,
                Ok(_) => {
                    warn!("audio event parsed as a different message kind");
                    return;
                }
                Err(err) => {
                    error!("failed to parse audio JSON: {err:#}");
                    if let Err(send_err) = messenger
                        .send_error_to(
                            &message.sender_pubkey_hex,
                            format!("Invalid audio JSON: {err:#}"),
                        )
                        .await
                    {
                        error!("failed to send audio parse error DM: {send_err:#}");
                    }
                    return;
                }
            };

            let transcript = match transcribe_or_load_cached(
                memory,
                recorded.id,
                &message.sender_pubkey_hex,
                &audio,
                audio_config,
                transcribe_config,
                messenger,
            )
            .await
            {
                Some(transcript) => transcript,
                None => return,
            };
            if cancel_token.is_cancelled() {
                report_codex_cancelled(messenger, &message.sender_pubkey_hex)
                    .await
                    .ok();
                return;
            }

            info!(
                "transcribed audio event {}: {}",
                message.event_id,
                transcript_preview(&transcript)
            );
            if let Some(memory) = memory.as_mut() {
                if let Err(err) = memory.update_message(recorded.id, "transcript", &transcript) {
                    warn!("failed to store transcript memory: {err:#}");
                }
            }

            if let Err(err) = messenger
                .send_transcript_for_event_to(
                    &message.sender_pubkey_hex,
                    transcript.clone(),
                    message.event_id.clone(),
                )
                .await
            {
                warn!("failed to send transcript DM: {err:#}");
            }

            if let Some(response) = low_information_transcript_response(&transcript) {
                if let Some(memory) = memory.as_mut() {
                    if let Err(err) =
                        memory.update_message(recorded.id, "ignored_transcript", &transcript)
                    {
                        warn!("failed to mark transcript as ignored in memory: {err:#}");
                    }
                }
                send_response(messenger, &message.sender_pubkey_hex, response).await;
                return;
            }

            if let Some(response) = handle_local_request(
                memory,
                &message.sender_pubkey_hex,
                &transcript,
                &codex_config.working_dir,
            ) {
                send_response(messenger, &message.sender_pubkey_hex, response).await;
                return;
            }

            process_text_turn(
                messenger,
                memory,
                &message.sender_pubkey_hex,
                recorded.id,
                &transcript,
                &codex_config,
                route_session_id.as_deref(),
                cancel_token,
            )
            .await;
        }
        "cancel" => {
            send_status(
                messenger,
                &message.sender_pubkey_hex,
                "No active task to cancel.",
            )
            .await;
        }
        "invalid" => {
            warn!("invalid JSON DM from peer: {}", message.text);
            if let Err(err) = messenger
                .send_error_to(
                    &message.sender_pubkey_hex,
                    format!("Invalid request JSON: {}", message.text),
                )
                .await
            {
                error!("failed to send invalid-json error DM: {err:#}");
            }
        }
        "unsupported" => {
            warn!("unsupported DM payload: {}", message.text);
        }
        other => {
            info!("ignored `{other}` DM event {}", message.event_id);
        }
    }
}

async fn process_media_bundle_turn(
    messenger: &NostrMessenger,
    memory: &mut Option<MemoryStore>,
    peer_pubkey: &str,
    message: &IncomingMessage,
    bundle: MediaBundle,
    audio_config: &AudioConfig,
    transcribe_config: &TranscribeConfig,
    codex_config: &CodexConfig,
    session_id: Option<&str>,
    cancel_token: &CodexCancelToken,
) {
    let user_query = bundle.query.as_deref().map(str::trim).unwrap_or_default();

    if bundle.attachments.is_empty() && user_query.is_empty() {
        if let Err(err) = messenger
            .send_error_to(peer_pubkey, "Media bundle is empty".to_string())
            .await
        {
            error!("failed to send empty media-bundle error DM: {err:#}");
        }
        return;
    }

    let Some(recorded_bundle) = remember_incoming(
        memory,
        peer_pubkey,
        &message.event_id,
        "media_bundle",
        &message.text,
    ) else {
        return;
    };
    if !recorded_bundle.inserted {
        info!(
            "ignored already-persisted media_bundle event {}",
            message.event_id
        );
        return;
    }
    let recorded_bundle_id = recorded_bundle.id;

    let mut request_parts = Vec::new();
    if !user_query.is_empty() {
        request_parts.push(format!("User request: {user_query}"));
    }

    let mut attachment_lines = Vec::new();
    let mut transcripts = Vec::new();
    let mut local_texts = Vec::new();
    let mut local_attachments: Vec<DownloadedAudio> = Vec::new();

    for (index, attachment) in bundle.attachments.iter().enumerate() {
        if cancel_token.is_cancelled() {
            report_codex_cancelled(messenger, peer_pubkey).await.ok();
            return;
        }
        let label = attachment
            .name
            .clone()
            .unwrap_or_else(|| format!("attachment-{}", index + 1));
        attachment_lines.push(format!(
            "- {label} ({}) => {}",
            attachment.media_type, attachment.url
        ));

        if attachment.media_type.starts_with("audio/") {
            let audio = media_reference_to_audio(attachment);
            let transcript = match transcribe_or_load_cached(
                memory,
                recorded_bundle_id,
                peer_pubkey,
                &audio,
                audio_config,
                transcribe_config,
                messenger,
            )
            .await
            {
                Some(transcript) => transcript,
                None => continue,
            };
            if cancel_token.is_cancelled() {
                report_codex_cancelled(messenger, peer_pubkey).await.ok();
                return;
            }

            transcripts.push(format!("{label}:\n{transcript}"));
            local_texts.push(format!("{label}:\n{transcript}"));

            if let Err(err) = messenger
                .send_transcript_for_event_to(
                    peer_pubkey,
                    transcript.clone(),
                    message.event_id.clone(),
                )
                .await
            {
                warn!("failed to send transcript DM: {err:#}");
            }
            continue;
        }

        if is_text_media_type(&attachment.media_type) {
            let extracted_text = match extract_local_text_attachment(
                attachment,
                memory,
                recorded_bundle_id,
                peer_pubkey,
                audio_config,
                messenger,
            )
            .await
            {
                Some(text) => text,
                None => continue,
            };
            if cancel_token.is_cancelled() {
                report_codex_cancelled(messenger, peer_pubkey).await.ok();
                return;
            }

            local_texts.push(format!("{label}:\n{extracted_text}"));
            continue;
        }

        if is_image_media_type(&attachment.media_type) {
            let downloaded = match download_local_attachment(
                attachment,
                audio_config,
                messenger,
                peer_pubkey,
                "image",
            )
            .await
            {
                Some(downloaded) => downloaded,
                None => continue,
            };
            if cancel_token.is_cancelled() {
                report_codex_cancelled(messenger, peer_pubkey).await.ok();
                return;
            }
            let local_path = downloaded.path.display().to_string();
            attachment_lines.push(format!("  local decrypted image: {local_path}"));
            local_texts.push(format!(
                "{label}:\nLocal decrypted image file: {local_path}\nUse this local file when inspecting the image."
            ));
            local_attachments.push(downloaded);
        }
    }

    if !attachment_lines.is_empty() {
        request_parts.push(format!("Attached files:\n{}", attachment_lines.join("\n")));
    }

    if !transcripts.is_empty() {
        request_parts.push(format!(
            "Attachment transcripts:\n{}",
            transcripts.join("\n\n")
        ));
    }

    if !local_texts.is_empty() {
        request_parts.push(format!(
            "Attachment text content:\n{}\n\nUse this content for the request.",
            local_texts.join("\n\n")
        ));
    }

    if request_parts.is_empty() {
        request_parts.push("Process the attached media and answer the user's request.".to_string());
    }
    if cancel_token.is_cancelled() {
        report_codex_cancelled(messenger, peer_pubkey).await.ok();
        return;
    }

    let request_text = request_parts.join("\n\n");

    if let Some(response) = handle_local_request(
        memory,
        peer_pubkey,
        &request_text,
        &codex_config.working_dir,
    ) {
        send_response(messenger, peer_pubkey, response).await;
        return;
    }

    process_text_turn(
        messenger,
        memory,
        peer_pubkey,
        recorded_bundle.id,
        &request_text,
        codex_config,
        session_id,
        cancel_token,
    )
    .await;

    drop(local_attachments);
}

async fn process_spawn_worker_request(
    messenger: &NostrMessenger,
    owner_pubkey: &str,
    owner_pubkey_hex: &str,
    request: &SpawnWorkerRequest,
    relays: &[String],
    codex_config: &CodexConfig,
    audio_config: &AudioConfig,
    transcribe_config: &TranscribeConfig,
    manager: &RepoRuntimeManager,
) {
    let parent_pubkey = match messenger.public_key_bech32() {
        Ok(pubkey) => pubkey,
        Err(err) => {
            send_response(
                messenger,
                owner_pubkey_hex,
                format!("Could not resolve computer service pubkey: {err:#}"),
            )
            .await;
            return;
        }
    };
    match start_repo_worker(
        request,
        owner_pubkey,
        owner_pubkey_hex,
        relays,
        &codex_config.working_dir,
        &parent_pubkey,
        &messenger.public_key_hex(),
        codex_config,
        audio_config,
        transcribe_config,
        manager,
    )
    .await
    {
        Ok((target, pid, reused_existing)) => {
            match messenger
                .send_wire_to_pubkey(owner_pubkey_hex, WireMessage::target_invite(target.clone()))
                .await
            {
                Ok(_) => {
                    let action = if reused_existing {
                        "Attached to the existing"
                    } else {
                        "Started a new"
                    };
                    if !request.silent {
                        send_response(
                            messenger,
                            owner_pubkey_hex,
                            format!(
                                "{action} Nostr Codex session for `{}`.\n\nIt uses this service npub and I sent this phone a target invite DM. Open the session switcher to select `{}`.",
                                target.workdir.as_deref().unwrap_or("unknown"),
                                target.name
                            ),
                        )
                        .await;
                    }
                    if reused_existing {
                        info!(
                            "attached to existing child worker pid {pid} for {} ({})",
                            target.name,
                            target.workdir.as_deref().unwrap_or("unknown")
                        );
                    } else {
                        info!(
                            "started in-process child worker pid {pid} for {} ({})",
                            target.name,
                            target.workdir.as_deref().unwrap_or("unknown")
                        );
                    }
                }
                Err(err) => {
                    let action = if reused_existing {
                        "Found an existing worker"
                    } else {
                        "Started a new worker"
                    };
                    send_response(
                        messenger,
                        owner_pubkey_hex,
                        format!(
                            "{action} for `{}` as `{}`, but sending the phone target invite failed: {err:#}",
                            target.workdir.as_deref().unwrap_or("unknown"),
                            target.pubkey
                        ),
                    )
                    .await;
                }
            }
        }
        Err(err) => {
            send_response(
                messenger,
                owner_pubkey_hex,
                format!(
                    "Could not spawn a worker for `{}`: {err:#}",
                    request.workdir
                ),
            )
            .await;
        }
    }
}

async fn process_repo_list_request(messenger: &NostrMessenger, owner_pubkey_hex: &str) {
    match build_repo_list() {
        Ok(repo_list) => {
            if let Err(err) = messenger
                .send_wire_to_pubkey(owner_pubkey_hex, WireMessage::repo_list(repo_list))
                .await
            {
                error!("failed to send repo list DM: {err:#}");
            }
        }
        Err(err) => {
            send_response(
                messenger,
                owner_pubkey_hex,
                format!("Could not list repo folders: {err:#}"),
            )
            .await;
        }
    }
}

async fn start_repo_worker(
    request: &SpawnWorkerRequest,
    _owner_pubkey: &str,
    _owner_pubkey_hex: &str,
    relays: &[String],
    current_workdir: &Path,
    parent_pubkey: &str,
    parent_pubkey_hex: &str,
    _codex_config: &CodexConfig,
    _audio_config: &AudioConfig,
    _transcribe_config: &TranscribeConfig,
    _manager: &RepoRuntimeManager,
) -> Result<(TargetInvite, u32, bool)> {
    let context = repo_target_context(request, relays, current_workdir)?;

    let target = TargetInvite {
        target_type: "nostr_codex_target".to_string(),
        version: 1,
        name: worker_target_name(&context.workdir),
        pubkey: parent_pubkey.to_string(),
        pubkey_hex: Some(parent_pubkey_hex.to_string()),
        workdir: Some(context.workdir.to_string_lossy().to_string()),
        relays: context.relays.clone(),
        parent: Some(TargetParent {
            name: worker_target_name(current_workdir),
            pubkey: parent_pubkey.to_string(),
            pubkey_hex: Some(parent_pubkey_hex.to_string()),
            workdir: Some(current_workdir.to_string_lossy().to_string()),
            relays: context.relays.clone(),
        }),
    };

    let pid = std::process::id();

    if let Err(err) = upsert_worker_registry(current_workdir, &target, pid) {
        warn!("failed to update worker registry: {err:#}");
    }

    Ok((target, pid, false))
}

fn repo_target_context(
    request: &SpawnWorkerRequest,
    relays: &[String],
    current_workdir: &Path,
) -> Result<RepoTargetContext> {
    let workdir = resolve_spawn_workdir(request, current_workdir)?;
    let relays = if relays.is_empty() {
        default_relays()
    } else {
        relays.to_vec()
    };
    Ok(RepoTargetContext { workdir, relays })
}

fn repo_worker_context(
    request: &SpawnWorkerRequest,
    relays: &[String],
    current_workdir: &Path,
) -> Result<RepoWorkerContext> {
    let workdir = resolve_spawn_workdir(request, current_workdir)?;
    let env_file = WorkerEnvFile::default_for_workdir(&workdir);
    let secret_key = ensure_child_worker_secret(&env_file)?;
    let keys = Keys::parse(secret_key.trim()).context("invalid child worker secret key")?;
    let public_key = keys.public_key().to_bech32()?;
    let public_key_hex = keys.public_key().to_hex();
    let relays = if relays.is_empty() {
        default_relays()
    } else {
        relays.to_vec()
    };
    let relay_csv = relays.join(",");
    let memory_db = worker_state_path(&workdir, "memory.sqlite3");

    Ok(RepoWorkerContext {
        workdir,
        env_file,
        secret_key,
        public_key,
        public_key_hex,
        relays,
        relay_csv,
        memory_db,
    })
}

fn acquire_worker_process_lock(workdir: &Path) -> Result<WorkerProcessLock> {
    let path = worker_state_path(workdir, WORKER_LOCK_FILE);
    let pid = std::process::id().to_string();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| {
            format!(
                "failed to create worker lock directory `{}`",
                parent.display()
            )
        })?;
    }

    loop {
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
        {
            Ok(mut file) => {
                use std::io::Write;
                writeln!(file, "{pid}")
                    .with_context(|| format!("failed to write worker lock `{}`", path.display()))?;
                set_private_file_permissions(&path);
                return Ok(WorkerProcessLock { path });
            }
            Err(err) if err.kind() == std::io::ErrorKind::AlreadyExists => {
                if worker_lock_is_stale(&path)? {
                    fs::remove_file(&path).with_context(|| {
                        format!("failed to remove stale worker lock `{}`", path.display())
                    })?;
                    continue;
                }
                anyhow::bail!(
                    "another Nostr Codex worker is already running in `{}`; attach to that worker instead",
                    workdir.display()
                );
            }
            Err(err) => {
                return Err(err)
                    .with_context(|| format!("failed to create worker lock `{}`", path.display()));
            }
        }
    }
}

fn worker_lock_is_stale(path: &Path) -> Result<bool> {
    let raw = fs::read_to_string(path)
        .with_context(|| format!("failed to read worker lock `{}`", path.display()))?;
    let Some(pid) = raw.trim().parse::<u32>().ok() else {
        return Ok(true);
    };
    if pid == std::process::id() {
        return Ok(true);
    }
    if !process_is_running(pid) {
        return Ok(true);
    }
    Ok(!worker_lock_process_matches(path, pid))
}

#[cfg(test)]
fn running_worker_lock_pid(workdir: &Path) -> Result<Option<u32>> {
    let path = worker_state_path(workdir, WORKER_LOCK_FILE);
    if !path.is_file() {
        return Ok(None);
    }
    if worker_lock_is_stale(&path)? {
        fs::remove_file(&path)
            .with_context(|| format!("failed to remove stale worker lock `{}`", path.display()))?;
        return Ok(None);
    }
    let raw = fs::read_to_string(&path)
        .with_context(|| format!("failed to read worker lock `{}`", path.display()))?;
    Ok(raw.trim().parse::<u32>().ok())
}

#[cfg(unix)]
fn process_is_running(pid: u32) -> bool {
    StdCommand::new("kill")
        .arg("-0")
        .arg(pid.to_string())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

#[cfg(windows)]
fn process_is_running(pid: u32) -> bool {
    let Ok(output) = StdCommand::new("tasklist")
        .args(["/FI", &format!("PID eq {pid}"), "/NH"])
        .output()
    else {
        return false;
    };
    String::from_utf8_lossy(&output.stdout)
        .split_whitespace()
        .any(|part| part == pid.to_string())
}

#[cfg(not(any(unix, windows)))]
fn process_is_running(_pid: u32) -> bool {
    false
}

#[cfg(target_os = "linux")]
fn worker_lock_process_matches(path: &Path, pid: u32) -> bool {
    let Some(workdir) = path.parent() else {
        return false;
    };
    let process_dir = Path::new("/proc").join(pid.to_string());
    let Ok(cwd) = fs::read_link(process_dir.join("cwd")) else {
        return false;
    };
    if canonical_path_key(&cwd) != canonical_path_key(workdir) {
        return false;
    }

    let Ok(exe) = fs::read_link(process_dir.join("exe")) else {
        return false;
    };
    let current_exe_name = env::current_exe()
        .ok()
        .and_then(|path| path.file_name().map(|name| name.to_owned()));
    current_exe_name
        .as_ref()
        .zip(exe.file_name())
        .is_some_and(|(current, candidate)| current == candidate)
}

#[cfg(not(target_os = "linux"))]
fn worker_lock_process_matches(_path: &Path, _pid: u32) -> bool {
    true
}

fn is_repo_list_request(request: &str) -> bool {
    let trimmed = request.trim();
    if matches!(trimmed, "/repos" | "/repositories" | "/folders") {
        return true;
    }
    let Ok(value) = serde_json::from_str::<serde_json::Value>(trimmed) else {
        return false;
    };
    value
        .as_object()
        .is_some_and(|object| object.contains_key("repo_list_request"))
}

fn build_repo_list() -> Result<RepoList> {
    let root = canonical_worker_root_dir()?;
    let roots = [root.clone(), root.join("pave")]
        .into_iter()
        .filter(|root| root.is_dir())
        .map(|repo_root| list_repo_root(&root, &repo_root))
        .collect::<Result<Vec<_>>>()?;
    Ok(RepoList { roots })
}

fn list_repo_root(worker_root: &Path, root: &Path) -> Result<RepoListRoot> {
    let mut repos = Vec::new();
    for entry in fs::read_dir(root)
        .with_context(|| format!("failed to read repo root `{}`", root.display()))?
    {
        let entry =
            entry.with_context(|| format!("failed to read entry in `{}`", root.display()))?;
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
            continue;
        };
        if name.starts_with('.') {
            continue;
        }
        let relative_path = path
            .strip_prefix(worker_root)
            .unwrap_or(&path)
            .to_string_lossy()
            .to_string();
        repos.push(RepoListEntry {
            name: name.to_string(),
            path: path.to_string_lossy().to_string(),
            relative_path,
            is_git_repo: path.join(".git").is_dir(),
        });
    }
    repos.sort_by(|left, right| {
        left.relative_path
            .to_ascii_lowercase()
            .cmp(&right.relative_path.to_ascii_lowercase())
    });
    Ok(RepoListRoot {
        root: root.to_string_lossy().to_string(),
        repos,
    })
}

fn ensure_child_worker_secret(env_file: &WorkerEnvFile) -> Result<String> {
    if let Some(secret_key) = env_file
        .read_values()?
        .get("NOSTR_SECRET_KEY")
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
    {
        return Ok(secret_key);
    }

    let keys = Keys::generate();
    let secret_key = keys.secret_key().to_bech32()?;
    let public_key = keys.public_key().to_bech32()?;
    let public_key_hex = keys.public_key().to_hex();
    upsert_env_file_values(
        &env_file.path,
        &[
            ("NOSTR_SECRET_KEY", secret_key.as_str()),
            ("NOSTR_PUBLIC_KEY", public_key.as_str()),
            ("NOSTR_PUBLIC_KEY_HEX", public_key_hex.as_str()),
        ],
    )?;
    Ok(secret_key)
}

fn resolve_spawn_workdir(request: &SpawnWorkerRequest, current_workdir: &Path) -> Result<PathBuf> {
    let worker_root = canonical_spawn_root_dir(current_workdir)?;
    let requested = expand_home_path(clean_path_argument(&request.workdir));
    let path = if requested.is_absolute() {
        requested
    } else {
        worker_root.join(requested)
    };
    if request.create && !path.exists() {
        ensure_spawn_create_allowed(&path, &worker_root)?;
        fs::create_dir_all(&path)
            .with_context(|| format!("failed to create `{}`", path.display()))?;
    }
    let canonical = path
        .canonicalize()
        .with_context(|| format!("failed to resolve `{}`", path.display()))?;
    if !canonical.is_dir() {
        anyhow::bail!("`{}` is not a directory", canonical.display());
    }
    ensure_spawn_existing_allowed(&canonical, &worker_root)?;
    Ok(canonical)
}

fn ensure_spawn_existing_allowed(path: &Path, worker_root: &Path) -> Result<()> {
    if path == worker_root || path.starts_with(worker_root) {
        return Ok(());
    }
    anyhow::bail!(
        "`{}` is outside the allowed folders (`{}` and folders inside it)",
        path.display(),
        worker_root.display()
    )
}

fn ensure_spawn_create_allowed(path: &Path, worker_root: &Path) -> Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("new folder path must have a parent"))?
        .canonicalize()
        .with_context(|| format!("failed to resolve parent of `{}`", path.display()))?;
    if parent == worker_root || parent.starts_with(worker_root) {
        return Ok(());
    }
    anyhow::bail!(
        "new folders may only be created inside `{}`",
        worker_root.display()
    )
}

fn canonical_worker_root_dir() -> Result<PathBuf> {
    let root = match env::var("CODEX_WORKDIR") {
        Ok(workdir) => PathBuf::from(workdir),
        Err(_) => env::current_dir().context("failed to resolve worker directory")?,
    };
    root.canonicalize()
        .with_context(|| format!("failed to resolve worker root `{}`", root.display()))
}

fn canonical_spawn_root_dir(current_workdir: &Path) -> Result<PathBuf> {
    let root = env::var("CODEX_WORKDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| current_workdir.to_path_buf());
    root.canonicalize()
        .with_context(|| format!("failed to resolve worker root `{}`", root.display()))
}

fn expand_home_path(path: &str) -> PathBuf {
    if path == "~" {
        return env::var("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from(path));
    }
    if let Some(rest) = path.strip_prefix("~/") {
        if let Ok(home) = env::var("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(path)
}

fn parse_spawn_worker_request(request: &str) -> Option<SpawnWorkerRequest> {
    let trimmed = request.trim();
    if let Some(parsed) = parse_spawn_worker_json_request(trimmed) {
        return Some(parsed);
    }
    let lowered = trimmed.to_ascii_lowercase();
    for (prefix, create) in [
        ("/spawn --create", true),
        ("/spawn -c", true),
        ("/spawn-create", true),
        ("/create-session", true),
        ("/create-worker", true),
        ("/spawn", false),
        ("/spawn-session", false),
        ("/spawn-worker", false),
        ("/start-session", false),
        ("/start-worker", false),
        ("/restart-session", false),
    ] {
        if lowered == prefix {
            return None;
        }
        if lowered.starts_with(&format!("{prefix} ")) {
            return parse_spawn_path_argument(&trimmed[prefix.len()..]).map(|workdir| {
                SpawnWorkerRequest {
                    workdir,
                    create,
                    silent: false,
                }
            });
        }
    }
    for (marker, create) in [
        ("create worker in ", true),
        ("create a worker in ", true),
        ("create session in ", true),
        ("create a session in ", true),
        ("spawn new worker in ", true),
        ("spawn new session in ", true),
        ("spawn worker in ", false),
        ("spawn session in ", false),
        ("spawn a session in ", false),
        ("start worker in ", false),
        ("start a worker in ", false),
        ("start session in ", false),
        ("start a session in ", false),
        ("restart session in ", false),
    ] {
        if lowered.starts_with(marker) {
            return parse_spawn_path_argument(&trimmed[marker.len()..]).map(|workdir| {
                SpawnWorkerRequest {
                    workdir,
                    create,
                    silent: false,
                }
            });
        }
    }
    None
}

fn parse_spawn_worker_json_request(request: &str) -> Option<SpawnWorkerRequest> {
    let value: serde_json::Value = serde_json::from_str(request).ok()?;
    let object = value.as_object()?;
    let raw = object
        .get("spawn_session")
        .or_else(|| object.get("spawn_worker"))?;
    let raw_object = raw.as_object()?;
    let workdir = raw_object
        .get("workdir")
        .or_else(|| raw_object.get("path"))
        .and_then(|value| value.as_str())
        .map(str::trim)
        .filter(|value| !value.is_empty())?
        .to_string();
    let create = raw_object
        .get("create")
        .or_else(|| raw_object.get("create_folder"))
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    let silent = raw_object
        .get("silent")
        .or_else(|| raw_object.get("quiet"))
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    Some(SpawnWorkerRequest {
        workdir,
        create,
        silent,
    })
}

fn parse_cancel_message(message: &IncomingMessage) -> Option<CancelRequest> {
    if message.kind == "cancel" {
        return parse_cancel_request(&message.raw_json);
    }
    parse_cancel_request(&message.text)
}

fn parse_cancel_request(request: &str) -> Option<CancelRequest> {
    let trimmed = request.trim();
    let command = trimmed.to_ascii_lowercase();
    if matches!(command.as_str(), "/cancel" | "/stop" | "/abort") {
        return Some(CancelRequest { event_id: None });
    }

    if let Ok(WireMessage::Cancel { cancel_request }) = parse_wire_message(trimmed) {
        return Some(CancelRequest {
            event_id: cancel_request.event_id,
        });
    }

    let value: serde_json::Value = serde_json::from_str(trimmed).ok()?;
    let object = value.as_object()?;
    let raw = object
        .get("cancel_request")
        .or_else(|| object.get("cancel_task"))
        .or_else(|| object.get("cancel"));

    match raw {
        Some(value) if value.as_bool() == Some(true) => Some(CancelRequest { event_id: None }),
        Some(value) if value.as_bool() == Some(false) => None,
        Some(value) if value.as_str().is_some() => Some(CancelRequest {
            event_id: value
                .as_str()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToOwned::to_owned),
        }),
        Some(value) => {
            let event_id = value
                .as_object()
                .and_then(|object| object.get("event_id").or_else(|| object.get("eventId")))
                .and_then(|value| value.as_str())
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToOwned::to_owned);
            Some(CancelRequest { event_id })
        }
        None => None,
    }
}

fn cancel_request_matches(request: &CancelRequest, active_event_id: &str) -> bool {
    match request
        .event_id
        .as_deref()
        .map(str::trim)
        .filter(|event_id| !event_id.is_empty())
    {
        Some(event_id) => event_id == active_event_id,
        None => true,
    }
}

fn is_shutdown_request(request: &str) -> bool {
    let command = request.trim().to_ascii_lowercase();
    if matches!(command.as_str(), "/shutdown" | "/quit" | "/exit")
        || matches!(
            command.as_str(),
            "/shutdown confirm" | "/quit confirm" | "/exit confirm"
        )
    {
        return true;
    }
    matches!(
        normalize_transcript(request).as_str(),
        "shutdown" | "quit" | "exit"
    )
}

fn is_shutdown_confirm_request(request: &str) -> bool {
    matches!(
        request.trim().to_ascii_lowercase().as_str(),
        "/shutdown confirm" | "/quit confirm" | "/exit confirm"
    )
}

fn parse_spawn_path_argument(raw: &str) -> Option<String> {
    let cleaned = raw.trim();
    if cleaned.is_empty() {
        return None;
    }
    if let Ok(parts) = shell_words::split(cleaned) {
        if parts.len() == 1 && !parts[0].trim().is_empty() {
            return Some(parts[0].trim().to_string());
        }
    }
    Some(clean_path_argument(cleaned).to_string())
}

fn clean_path_argument(raw: &str) -> &str {
    raw.trim()
        .trim_matches(|ch| ch == '"' || ch == '\'' || ch == '`')
        .trim()
}

fn media_reference_to_audio(reference: &MediaReference) -> AudioReference {
    AudioReference {
        url: reference.url.clone(),
        sha256: reference.sha256.clone(),
        size: reference.size,
        media_type: reference.media_type.clone(),
        name: reference.name.clone(),
        encryption: reference.encryption.clone(),
    }
}

async fn extract_local_text_attachment(
    attachment: &MediaReference,
    memory: &mut Option<MemoryStore>,
    recorded_id: i64,
    receiver_pubkey: &str,
    audio_config: &AudioConfig,
    messenger: &NostrMessenger,
) -> Option<String> {
    let cache_key = text_attachment_cache_key(attachment);
    if let Some(cached) = cached_text_attachment(memory, &cache_key) {
        info!("used cached text attachment for blob hash {cache_key}");
        return Some(cached);
    }

    let extension = text_attachment_extension(&attachment.media_type, attachment.name.as_deref());
    let reference = media_reference_to_audio(attachment);
    let downloaded = match download_blossom_attachment(&reference, &extension, audio_config).await {
        Ok(downloaded) => downloaded,
        Err(err) => {
            error!("attachment download failed: {err:#}");
            if let Err(send_err) = messenger
                .send_error_to(
                    receiver_pubkey,
                    format!(
                        "Could not download attachment \"{}\": {err:#}",
                        attachment
                            .name
                            .clone()
                            .unwrap_or_else(|| attachment.url.clone())
                    ),
                )
                .await
            {
                error!("failed to send attachment download error DM: {send_err:#}");
            }
            return None;
        }
    };

    let bytes = match tokio::fs::read(&downloaded.path).await {
        Ok(bytes) => bytes,
        Err(err) => {
            error!(
                "failed to read attachment content `{}`: {err:#}",
                downloaded.path.display()
            );
            if let Err(send_err) = messenger
                .send_error_to(
                    receiver_pubkey,
                    format!(
                        "Failed to read attachment \"{}\": {err:#}",
                        attachment
                            .name
                            .clone()
                            .unwrap_or_else(|| attachment.url.clone())
                    ),
                )
                .await
            {
                error!("failed to send attachment read error DM: {send_err:#}");
            }
            return None;
        }
    };

    let attachment_name = attachment
        .name
        .clone()
        .unwrap_or_else(|| attachment.url.clone());
    let extracted = String::from_utf8_lossy(&bytes).trim().to_string();
    if extracted.is_empty() {
        if let Some(memory) = memory.as_mut() {
            if let Err(err) = memory.update_message(
                recorded_id,
                "text_attachment",
                &format!("Attachment \"{attachment_name}\" was empty or binary."),
            ) {
                warn!("failed to record text attachment note: {err:#}");
            }
        }
        return None;
    }

    let extracted = extracted.replace('\u{0000}', "");
    let extracted = extracted.trim().to_string();
    if extracted.is_empty() {
        return None;
    }

    let extracted = if extracted.chars().count() > 20_000 {
        extracted.chars().take(20_000).collect()
    } else {
        extracted
    };

    save_text_attachment_cache(memory, &cache_key, &extracted);
    Some(extracted)
}

async fn download_local_attachment(
    attachment: &MediaReference,
    audio_config: &AudioConfig,
    messenger: &NostrMessenger,
    receiver_pubkey: &str,
    kind: &str,
) -> Option<DownloadedAudio> {
    let extension = attachment_extension(&attachment.media_type, attachment.name.as_deref());
    let reference = media_reference_to_audio(attachment);
    match download_blossom_attachment(&reference, &extension, audio_config).await {
        Ok(downloaded) => Some(downloaded),
        Err(err) => {
            error!("{kind} attachment download failed: {err:#}");
            if let Err(send_err) = messenger
                .send_error_to(
                    receiver_pubkey,
                    format!(
                        "Could not download {kind} attachment \"{}\": {err:#}",
                        attachment
                            .name
                            .clone()
                            .unwrap_or_else(|| attachment.url.clone())
                    ),
                )
                .await
            {
                error!("failed to send attachment download error DM: {send_err:#}");
            }
            None
        }
    }
}

fn is_text_media_type(media_type: &str) -> bool {
    let normalized = media_type
        .split(';')
        .next()
        .unwrap_or(media_type)
        .trim()
        .to_ascii_lowercase();
    normalized.starts_with("text/")
        || matches!(
            normalized.as_str(),
            "application/json"
                | "application/xml"
                | "text/x-markdown"
                | "application/x-markdown"
                | "text/x-python"
                | "application/x-python-code"
                | "application/javascript"
                | "text/javascript"
                | "text/csv"
                | "text/css"
                | "text/html"
                | "application/yaml"
                | "application/x-yaml"
                | "text/x-yaml"
                | "text/typescript"
                | "application/typescript"
                | "text/tsx"
                | "text/x-go"
                | "text/x-rust"
        )
}

fn is_image_media_type(media_type: &str) -> bool {
    let normalized = media_type
        .split(';')
        .next()
        .unwrap_or(media_type)
        .trim()
        .to_ascii_lowercase();
    normalized.starts_with("image/")
}

fn attachment_extension(media_type: &str, name: Option<&str>) -> String {
    let normalized = media_type
        .split(';')
        .next()
        .unwrap_or(media_type)
        .trim()
        .to_ascii_lowercase();
    match normalized.as_str() {
        "image/jpeg" => "jpg".to_string(),
        "image/png" => "png".to_string(),
        "image/gif" => "gif".to_string(),
        "image/webp" => "webp".to_string(),
        "image/heic" => "heic".to_string(),
        "image/heif" => "heif".to_string(),
        "image/svg+xml" => "svg".to_string(),
        _ => name
            .and_then(|name| name.rsplit_once('.').map(|(_, ext)| ext))
            .filter(|ext| !ext.is_empty() && ext.len() <= 8)
            .unwrap_or("bin")
            .to_string(),
    }
}

fn text_attachment_extension(media_type: &str, name: Option<&str>) -> String {
    let normalized = media_type
        .split(';')
        .next()
        .unwrap_or(media_type)
        .trim()
        .to_ascii_lowercase();
    match normalized.as_str() {
        "text/markdown" | "text/x-markdown" | "application/x-markdown" => "md".to_string(),
        "text/csv" => "csv".to_string(),
        "text/javascript" | "application/javascript" | "text/x-javascript" => "js".to_string(),
        "application/json" => "json".to_string(),
        "application/xml" | "text/xml" => "xml".to_string(),
        "text/html" => "html".to_string(),
        "text/css" => "css".to_string(),
        "text/x-yaml" | "application/yaml" | "application/x-yaml" => "yaml".to_string(),
        "text/x-python" | "application/x-python-code" => "py".to_string(),
        "text/typescript" | "application/typescript" | "text/tsx" => "ts".to_string(),
        "text/x-rust" => "rs".to_string(),
        "text/x-go" => "go".to_string(),
        _ => name
            .and_then(|name| name.rsplit_once('.').map(|(_, ext)| ext))
            .filter(|ext| !ext.is_empty() && ext.len() <= 8)
            .unwrap_or("txt")
            .to_string(),
    }
}

fn text_attachment_cache_key(attachment: &MediaReference) -> String {
    attachment
        .encryption
        .as_ref()
        .map(|encryption| encryption.plaintext_sha256.clone())
        .unwrap_or_else(|| attachment.sha256.clone())
}

fn cached_text_attachment(memory: &Option<MemoryStore>, cache_key: &str) -> Option<String> {
    memory
        .as_ref()
        .and_then(|memory| match memory.cached_transcript(cache_key) {
            Ok(transcript) => transcript,
            Err(err) => {
                warn!("failed to load cached text attachment: {err:#}");
                None
            }
        })
}

fn save_text_attachment_cache(memory: &mut Option<MemoryStore>, cache_key: &str, text: &str) {
    if let Some(memory) = memory.as_mut() {
        if let Err(err) = memory.save_transcript_cache(cache_key, text) {
            warn!("failed to save text attachment cache: {err:#}");
        }
    }
}

async fn process_text_turn(
    messenger: &NostrMessenger,
    memory: &mut Option<MemoryStore>,
    peer_pubkey: &str,
    recorded_id: i64,
    request: &str,
    codex_config: &CodexConfig,
    explicit_session_id: Option<&str>,
    cancel_token: &CodexCancelToken,
) {
    let session_id = if explicit_session_id.is_some() {
        explicit_session_id.map(ToOwned::to_owned)
    } else if codex_config.persist_sessions {
        load_codex_session(memory, peer_pubkey, &codex_config.working_dir, request)
    } else {
        None
    };
    let memory_context = if session_id.is_none() {
        memory_context(memory, peer_pubkey, recorded_id, request)
    } else {
        None
    };
    if cancel_token.is_cancelled() {
        report_codex_cancelled(messenger, peer_pubkey).await.ok();
        return;
    }
    let prompt = codex_phone_prompt(request, memory_context.as_deref());

    let response = match run_codex_and_report(
        messenger,
        memory,
        peer_pubkey,
        &prompt,
        codex_config,
        session_id.as_deref(),
        cancel_token,
    )
    .await
    {
        Ok(response) => response,
        Err(()) => return,
    };

    send_response_and_remember(
        messenger,
        memory,
        peer_pubkey,
        response,
        &codex_config.working_dir,
    )
    .await;
    spawn_compaction_if_needed(memory, peer_pubkey, codex_config);
}

async fn transcribe_or_load_cached(
    memory: &mut Option<MemoryStore>,
    recorded_id: i64,
    receiver_pubkey: &str,
    audio: &AudioReference,
    audio_config: &AudioConfig,
    transcribe_config: &TranscribeConfig,
    messenger: &NostrMessenger,
) -> Option<String> {
    let cache_key = audio_cache_key(audio);
    if let Some(transcript) = cached_transcript(memory, &cache_key) {
        info!("used cached transcript for audio hash {cache_key}");
        return Some(transcript);
    }

    let downloaded = match download_blossom_audio(audio, audio_config).await {
        Ok(downloaded) => downloaded,
        Err(err) => {
            error!("audio download failed: {err:#}");
            if let Err(send_err) = messenger
                .send_error_to(receiver_pubkey, format!("Audio download failed: {err:#}"))
                .await
            {
                error!("failed to send audio download error DM: {send_err:#}");
            }
            return None;
        }
    };

    let transcript = match transcribe_audio(&downloaded.path, transcribe_config).await {
        Ok(transcript) => transcript,
        Err(err) => {
            error!("audio transcription failed: {err:#}");
            if should_request_wav_retry(audio) {
                let reason = wav_retry_reason();
                if let Some(memory) = memory.as_mut() {
                    if let Err(memory_err) = memory.update_message(
                        recorded_id,
                        "audio_retry",
                        &format!("{reason}\n\nTranscription error: {err:#}"),
                    ) {
                        warn!("failed to mark audio retry request in memory: {memory_err:#}");
                    }
                }
                if let Err(send_err) = messenger
                    .send_audio_retry_to(receiver_pubkey, "wav", reason)
                    .await
                {
                    error!("failed to send WAV retry request DM: {send_err:#}");
                }
            } else if let Err(send_err) = messenger
                .send_error_to(
                    receiver_pubkey,
                    format!("Audio transcription failed: {err:#}"),
                )
                .await
            {
                error!("failed to send transcription error DM: {send_err:#}");
            }
            return None;
        }
    };

    save_transcript_cache(memory, &cache_key, &transcript);
    Some(transcript)
}

fn codex_phone_prompt(user_request: &str, memory_context: Option<&str>) -> String {
    let mut prompt = String::from(
        "You are responding to a request sent from a phone over Nostr.\n\
         Answer the user's request directly and concretely.\n\
         If the request is ambiguous, say what you heard and ask one concise clarifying question.\n\
         Do not answer with a generic greeting such as \"I'm here\" unless the user only greeted you.\n"
    );

    if let Some(memory_context) = memory_context.filter(|context| !context.trim().is_empty()) {
        prompt.push('\n');
        prompt.push_str(memory_context.trim());
        prompt.push('\n');
    }

    prompt.push_str("\nCurrent user request:\n");
    prompt.push_str(user_request);
    prompt
}

fn transcript_preview(transcript: &str) -> String {
    let normalized = transcript.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut preview = normalized.chars().take(160).collect::<String>();
    if normalized.chars().count() > 160 {
        preview.push_str("...");
    }
    preview
}

fn low_information_transcript_response(transcript: &str) -> Option<String> {
    let normalized = normalize_transcript(transcript);
    if normalized.is_empty() {
        return Some(
            "I could not hear a request. Start recording, speak the full request, then tap stop."
                .to_string(),
        );
    }

    let words = normalized.split_whitespace().collect::<Vec<_>>();
    if words.len() == 1 && is_low_information_word(words[0]) {
        let heard = transcript.trim();
        return Some(format!(
            "I only heard \"{heard}\".\n\nStart recording, speak the full request, then tap stop. If this keeps happening on GrapheneOS, check the app microphone permission and the system privacy mic toggle."
        ));
    }

    None
}

fn should_request_wav_retry(audio: &AudioReference) -> bool {
    !is_wav_media_type(audio_plaintext_media_type(audio))
}

fn audio_plaintext_media_type(audio: &AudioReference) -> &str {
    audio
        .encryption
        .as_ref()
        .map(|encryption| encryption.plaintext_media_type.as_str())
        .unwrap_or(audio.media_type.as_str())
}

fn is_wav_media_type(media_type: &str) -> bool {
    let normalized = media_type
        .split(';')
        .next()
        .unwrap_or(media_type)
        .trim()
        .to_ascii_lowercase();
    matches!(
        normalized.as_str(),
        "audio/wav" | "audio/wave" | "audio/x-wav" | "audio/vnd.wave"
    )
}

fn wav_retry_reason() -> &'static str {
    "Compressed voice audio could not be decoded or transcribed. Please retry; the phone will send the next recording as WAV."
}

fn normalize_transcript(transcript: &str) -> String {
    transcript
        .chars()
        .map(|ch| {
            if ch.is_alphanumeric() || ch.is_whitespace() {
                ch.to_ascii_lowercase()
            } else {
                ' '
            }
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn is_low_information_word(word: &str) -> bool {
    matches!(
        word,
        "you"
            | "yeah"
            | "yes"
            | "no"
            | "ok"
            | "okay"
            | "uh"
            | "um"
            | "hm"
            | "hmm"
            | "hello"
            | "hi"
            | "hey"
    )
}

fn open_memory_store(config: MemoryConfig) -> Option<MemoryStore> {
    match MemoryStore::open(config) {
        Ok(memory) => memory,
        Err(err) => {
            warn!("failed to initialize SQLite memory; continuing without memory: {err:#}");
            None
        }
    }
}

fn remember_incoming(
    memory: &mut Option<MemoryStore>,
    peer_pubkey: &str,
    event_id: &str,
    kind: &str,
    content: &str,
) -> Option<RecordedMessage> {
    let Some(memory) = memory.as_mut() else {
        return Some(RecordedMessage {
            id: i64::MAX,
            inserted: true,
        });
    };

    match memory.record_incoming(peer_pubkey, event_id, kind, content) {
        Ok(recorded) => Some(recorded),
        Err(err) => {
            warn!("failed to record incoming memory; processing without memory: {err:#}");
            Some(RecordedMessage {
                id: i64::MAX,
                inserted: true,
            })
        }
    }
}

fn memory_context(
    memory: &Option<MemoryStore>,
    peer_pubkey: &str,
    before_message_id: i64,
    request: &str,
) -> Option<String> {
    let memory = memory.as_ref()?;

    match memory.prompt_context(peer_pubkey, before_message_id, request) {
        Ok(context) => context,
        Err(err) => {
            warn!("failed to load memory context; continuing without it: {err:#}");
            None
        }
    }
}

fn handle_local_request(
    memory: &mut Option<MemoryStore>,
    peer_pubkey: &str,
    request: &str,
    workdir: &Path,
) -> Option<String> {
    let command = request.trim().to_ascii_lowercase();
    let normalized = normalize_transcript(request);
    let request_class = classify_request(request);

    match command.as_str() {
        "/memory" | "/summary" => {
            return Some(match memory.as_ref() {
                Some(memory) => memory
                    .status_text(peer_pubkey)
                    .unwrap_or_else(|err| format!("Memory status failed: {err:#}")),
                None => "Memory is disabled.".to_string(),
            });
        }
        "/forget" | "/reset" | "/reset memory" => {
            return Some(match memory.as_mut() {
                Some(memory) => match memory.clear_peer(peer_pubkey) {
                    Ok(()) => "Memory reset for this peer.".to_string(),
                    Err(err) => format!("Memory reset failed: {err:#}"),
                },
                None => "Memory is disabled.".to_string(),
            });
        }
        "/workers" | "/sessions" => {
            return Some(worker_registry_status_text(workdir));
        }
        _ => {}
    }

    match request_class {
        RequestClass::MemoryLookup if is_repeat_request(&normalized) => Some(
            match memory.as_ref().and_then(|memory| {
                memory
                    .last_response(peer_pubkey)
                    .map_err(|err| {
                        warn!("failed to load last response: {err:#}");
                        err
                    })
                    .ok()
                    .flatten()
            }) {
                Some(response) => response,
                None => "No previous response is available for this peer.".to_string(),
            },
        ),
        RequestClass::MemoryLookup if matches!(normalized.as_str(), "status" | "server status") => {
            Some(local_status_text(memory, peer_pubkey, workdir))
        }
        RequestClass::MemoryLookup if is_repo_lookup_request(&normalized) => {
            Some(repo_status_text(workdir))
        }
        RequestClass::NoOp => Some("Noted.".to_string()),
        RequestClass::Clarification if is_repeat_request(&normalized) => Some(
            match memory
                .as_ref()
                .and_then(|memory| memory.last_response(peer_pubkey).ok().flatten())
            {
                Some(response) => response,
                None => "I do not have a previous response to repeat yet.".to_string(),
            },
        ),
        RequestClass::Command
        | RequestClass::Coding
        | RequestClass::Clarification
        | RequestClass::MemoryLookup => None,
    }
}

fn classify_request(request: &str) -> RequestClass {
    let trimmed = request.trim();
    if trimmed.starts_with('/') {
        return RequestClass::Command;
    }

    let normalized = normalize_transcript(trimmed);
    if normalized.is_empty() || is_no_op_request(&normalized) {
        return RequestClass::NoOp;
    }
    if is_repeat_request(&normalized)
        || is_repo_lookup_request(&normalized)
        || matches!(normalized.as_str(), "status" | "server status")
        || normalized.contains("summary")
        || normalized.contains("memory")
    {
        return RequestClass::MemoryLookup;
    }
    if matches!(
        normalized.as_str(),
        "what" | "why" | "how" | "can you clarify" | "what do you mean"
    ) {
        return RequestClass::Clarification;
    }
    RequestClass::Coding
}

fn is_repeat_request(normalized: &str) -> bool {
    matches!(
        normalized,
        "repeat last"
            | "repeat the last response"
            | "say that again"
            | "say it again"
            | "replay last"
            | "read that again"
    )
}

fn is_repo_lookup_request(normalized: &str) -> bool {
    matches!(
        normalized,
        "what repo am i in"
            | "what repository am i in"
            | "what repo are we in"
            | "what repository are we in"
    )
}

fn local_status_text(memory: &Option<MemoryStore>, peer_pubkey: &str, workdir: &Path) -> String {
    let mut status = format!("Server is running.\n{}", repo_status_text(workdir));
    match memory.as_ref() {
        Some(memory) => {
            let session = memory
                .codex_session(peer_pubkey, workdir)
                .ok()
                .flatten()
                .unwrap_or_else(|| "none".to_string());
            status.push_str(&format!("\nCodex session: {session}"));
        }
        None => status.push_str("\nMemory is disabled."),
    }
    status
}

fn repo_status_text(workdir: &Path) -> String {
    let repo = workdir
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("unknown");
    format!("Repo/workdir: {repo}\nPath: {}", workdir.display())
}

fn registry_path(workdir: &Path) -> PathBuf {
    worker_state_path(workdir, WORKER_REGISTRY_FILE)
}

fn read_worker_registry(workdir: &Path) -> Result<WorkerRegistry> {
    let path = registry_path(workdir);
    if !path.is_file() {
        return Ok(WorkerRegistry { workers: vec![] });
    }
    let raw = fs::read_to_string(&path)
        .with_context(|| format!("failed to read worker registry `{}`", path.display()))?;
    serde_json::from_str(&raw)
        .with_context(|| format!("failed to parse worker registry `{}`", path.display()))
}

fn write_worker_registry(workdir: &Path, registry: &WorkerRegistry) -> Result<()> {
    let path = registry_path(workdir);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| {
            format!(
                "failed to create worker registry directory `{}`",
                parent.display()
            )
        })?;
    }
    let tmp_path = worker_state_dir(workdir).join(format!(
        ".{}.{}.tmp",
        WORKER_REGISTRY_FILE,
        std::process::id()
    ));
    let raw = serde_json::to_string_pretty(registry)?;
    fs::write(&tmp_path, format!("{raw}\n")).with_context(|| {
        format!(
            "failed to write temporary worker registry `{}`",
            tmp_path.display()
        )
    })?;
    fs::rename(&tmp_path, &path).with_context(|| {
        format!(
            "failed to replace worker registry `{}` with `{}`",
            path.display(),
            tmp_path.display()
        )
    })?;
    Ok(())
}

fn upsert_worker_registry(workdir: &Path, target: &TargetInvite, pid: u32) -> Result<()> {
    let mut registry = read_worker_registry(workdir)?;
    let entry = WorkerRegistryEntry {
        name: target.name.clone(),
        pubkey: target.pubkey.clone(),
        pubkey_hex: target.pubkey_hex.clone(),
        workdir: target.workdir.clone().unwrap_or_default(),
        pid,
        relays: target.relays.clone(),
    };
    if let Some(existing) = registry
        .workers
        .iter_mut()
        .find(|item| item.workdir == entry.workdir || item.pubkey == entry.pubkey)
    {
        *existing = entry;
    } else {
        registry.workers.push(entry);
    }
    write_worker_registry(workdir, &registry)
}

fn worker_registry_status_text(workdir: &Path) -> String {
    let registry = match read_worker_registry(workdir) {
        Ok(registry) => registry,
        Err(err) => return format!("Worker registry failed: {err:#}"),
    };
    if registry.workers.is_empty() {
        return "No spawned workers are registered.".to_string();
    }
    let mut lines = vec!["Spawned workers:".to_string()];
    for worker in registry.workers {
        lines.push(format!(
            "- {} pid={} pubkey={} path={}",
            worker.name, worker.pid, worker.pubkey, worker.workdir
        ));
    }
    lines.join("\n")
}

fn write_worker_target_qr(
    pubkey: &str,
    pubkey_hex: &str,
    workdir: &Path,
    relays: &[String],
    pairing_secret: Option<&str>,
) {
    let mut payload = serde_json::json!({
        "type": "nostr_codex_target",
        "version": 1,
        "name": worker_target_name(workdir),
        "pubkey": pubkey,
        "pubkey_hex": pubkey_hex,
        "workdir": workdir.to_string_lossy(),
        "relays": relays,
    });
    if let Some(secret) = pairing_secret.filter(|secret| !secret.trim().is_empty()) {
        payload["pairing_secret"] = serde_json::Value::String(secret.to_string());
    }
    let Ok(payload) = serde_json::to_string(&payload) else {
        warn!("failed to serialize worker QR payload");
        return;
    };

    info!("worker target QR payload: {payload}");

    let code = match QrCode::new(payload.as_bytes()) {
        Ok(code) => code,
        Err(err) => {
            warn!("failed to build worker target QR: {err:#}");
            return;
        }
    };

    if env_bool("NOSTR_CODEX_QR_PRINT", true) {
        println!(
            "\nNostr Codex target for {}\n{}\n",
            workdir.display(),
            render_terminal_qr(&code)
        );
    }

    let qr_path = env::var("NOSTR_CODEX_QR_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|_| worker_state_path(workdir, "target.svg"));
    if let Some(parent) = qr_path.parent() {
        if let Err(err) = fs::create_dir_all(parent) {
            warn!(
                "failed to create worker QR directory `{}`: {err:#}",
                parent.display()
            );
            return;
        }
    }
    if let Err(err) = fs::write(&qr_path, render_svg_qr(&code)) {
        warn!(
            "failed to save worker target QR `{}`: {err:#}",
            qr_path.display()
        );
        return;
    }
    info!("worker target QR saved: {}", qr_path.display());

    let payload_path = env::var("NOSTR_CODEX_TARGET_PAYLOAD_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|_| qr_path.with_extension("txt"));
    if let Some(parent) = payload_path.parent() {
        if let Err(err) = fs::create_dir_all(parent) {
            warn!(
                "failed to create worker target payload directory `{}`: {err:#}",
                parent.display()
            );
            return;
        }
    }
    if let Err(err) = fs::write(&payload_path, format!("{payload}\n")) {
        warn!(
            "failed to save worker target payload `{}`: {err:#}",
            payload_path.display()
        );
        return;
    }
    info!("worker target payload saved: {}", payload_path.display());

    if env_bool("NOSTR_CODEX_QR_OPEN", false) {
        if let Err(err) = StdCommand::new("xdg-open").arg(&qr_path).spawn() {
            warn!(
                "failed to open worker target QR `{}`: {err:#}",
                qr_path.display()
            );
        }
    }
}

fn worker_target_name(workdir: &Path) -> String {
    workdir
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.trim().is_empty())
        .unwrap_or("repo")
        .to_string()
}

fn env_bool(name: &str, default: bool) -> bool {
    env::var(name)
        .ok()
        .map(|value| !is_falsey_env(&value))
        .unwrap_or(default)
}

fn is_falsey_env(value: &str) -> bool {
    matches!(
        value.trim().to_ascii_lowercase().as_str(),
        "" | "0" | "false" | "no" | "off"
    )
}

fn render_terminal_qr(code: &QrCode) -> String {
    const QUIET: isize = 2;
    let width = code.width() as isize;
    let mut out = String::new();

    for y in -QUIET..(width + QUIET) {
        for x in -QUIET..(width + QUIET) {
            out.push_str(if qr_dark(code, x, y) { "██" } else { "  " });
        }
        out.push('\n');
    }

    out
}

fn render_svg_qr(code: &QrCode) -> String {
    const QUIET: isize = 4;
    let width = code.width() as isize;
    let size = width + (QUIET * 2);
    let mut path = String::new();

    for y in 0..width {
        for x in 0..width {
            if qr_dark(code, x, y) {
                path.push_str(&format!("M{} {}h1v1h-1z", x + QUIET, y + QUIET));
            }
        }
    }

    format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" shape-rendering="crispEdges"><rect width="{size}" height="{size}" fill="#fff"/><path d="{path}" fill="#000"/></svg>"##
    )
}

fn qr_dark(code: &QrCode, x: isize, y: isize) -> bool {
    if x < 0 || y < 0 || x >= code.width() as isize || y >= code.width() as isize {
        return false;
    }
    code[(x as usize, y as usize)] == Color::Dark
}

fn is_no_op_request(normalized: &str) -> bool {
    matches!(
        normalized,
        "thanks"
            | "thank you"
            | "ok"
            | "okay"
            | "cool"
            | "great"
            | "nice"
            | "done"
            | "never mind"
            | "nevermind"
    )
}

fn load_codex_session(
    memory: &Option<MemoryStore>,
    peer_pubkey: &str,
    workdir: &Path,
    request: &str,
) -> Option<String> {
    let stored =
        memory
            .as_ref()
            .and_then(|memory| match memory.codex_session(peer_pubkey, workdir) {
                Ok(session_id) => session_id,
                Err(err) => {
                    warn!("failed to load Codex session; starting a fresh turn: {err:#}");
                    None
                }
            });

    if !env_bool("CODEX_RESUME_LATEST_BY_WORKDIR", true) {
        return stored;
    }

    if stored.is_some() && !should_refresh_codex_session_for_request(request) {
        return stored;
    }

    match latest_codex_session_for_workdir(workdir) {
        Ok(Some(session_id)) => {
            if stored.as_deref() == Some(session_id.as_str()) {
                return stored;
            }
            info!(
                "adopting latest existing Codex session {session_id} for {}",
                workdir.display()
            );
            Some(session_id)
        }
        Ok(None) => stored,
        Err(err) => {
            warn!("failed to discover latest Codex session for workdir: {err:#}");
            stored
        }
    }
}

fn should_refresh_codex_session_for_request(request: &str) -> bool {
    let normalized = request.to_ascii_lowercase();
    [
        "last issue",
        "latest issue",
        "recent issue",
        "most recent",
        "progress",
        "worked on",
        "last task",
        "latest task",
    ]
    .iter()
    .any(|marker| normalized.contains(marker))
}

fn latest_codex_session_for_workdir(workdir: &Path) -> Result<Option<String>> {
    let sessions_dir = env::var("CODEX_SESSIONS_DIR")
        .map(PathBuf::from)
        .or_else(|_| {
            env::var("HOME").map(|home| PathBuf::from(home).join(".codex").join("sessions"))
        })
        .context("HOME is not set and CODEX_SESSIONS_DIR was not provided")?;
    latest_codex_session_for_workdir_in(&sessions_dir, workdir)
}

fn latest_codex_session_for_workdir_in(
    sessions_dir: &Path,
    workdir: &Path,
) -> Result<Option<String>> {
    if !sessions_dir.exists() {
        return Ok(None);
    }

    let target = workdir.to_string_lossy().to_string();
    let canonical_target = canonical_path_key(workdir);
    let mut best: Option<CodexSessionCandidate> = None;
    collect_latest_codex_session(sessions_dir, &target, &canonical_target, &mut best)?;
    Ok(best.map(|candidate| candidate.session_id))
}

#[derive(Debug)]
struct CodexSessionCandidate {
    started_at: String,
    last_timestamp: String,
    session_id: String,
}

fn collect_latest_codex_session(
    path: &Path,
    target_workdir: &str,
    canonical_target_workdir: &str,
    best: &mut Option<CodexSessionCandidate>,
) -> Result<()> {
    if path.is_dir() {
        for entry in
            fs::read_dir(path).with_context(|| format!("failed to read `{}`", path.display()))?
        {
            let entry = entry?;
            collect_latest_codex_session(
                &entry.path(),
                target_workdir,
                canonical_target_workdir,
                best,
            )?;
        }
        return Ok(());
    }

    if path.extension().and_then(|extension| extension.to_str()) != Some("jsonl") {
        return Ok(());
    }

    let Some(session) = parse_codex_session_file(path, target_workdir, canonical_target_workdir)?
    else {
        return Ok(());
    };
    match best {
        Some(best_session)
            if (
                best_session.started_at.as_str(),
                best_session.last_timestamp.as_str(),
            ) >= (session.started_at.as_str(), session.last_timestamp.as_str()) => {}
        _ => *best = Some(session),
    }
    Ok(())
}

fn parse_codex_session_file(
    path: &Path,
    target_workdir: &str,
    canonical_target_workdir: &str,
) -> Result<Option<CodexSessionCandidate>> {
    let file = File::open(path).with_context(|| format!("failed to open `{}`", path.display()))?;
    let reader = BufReader::new(file);
    let mut first_line = None;
    let mut last_line = None;

    for line in reader.lines() {
        let line = line.with_context(|| format!("failed to read `{}`", path.display()))?;
        if first_line.is_none() {
            first_line = Some(line.clone());
        }
        last_line = Some(line);
    }

    let Some(first_line) = first_line else {
        return Ok(None);
    };
    let first: serde_json::Value = match serde_json::from_str(&first_line) {
        Ok(value) => value,
        Err(_) => return Ok(None),
    };
    if first.get("type").and_then(|value| value.as_str()) != Some("session_meta") {
        return Ok(None);
    }
    let payload = &first["payload"];
    let Some(session_id) = payload.get("id").and_then(|value| value.as_str()) else {
        return Ok(None);
    };
    let Some(cwd) = payload.get("cwd").and_then(|value| value.as_str()) else {
        return Ok(None);
    };
    if !codex_session_cwd_matches(cwd, target_workdir, canonical_target_workdir) {
        return Ok(None);
    }

    let started_at = payload
        .get("timestamp")
        .and_then(|timestamp| timestamp.as_str())
        .or_else(|| {
            first
                .get("timestamp")
                .and_then(|timestamp| timestamp.as_str())
        })
        .unwrap_or_default();
    if started_at.is_empty() {
        return Ok(None);
    }

    let last_timestamp = last_line
        .as_deref()
        .and_then(|line| serde_json::from_str::<serde_json::Value>(line).ok())
        .and_then(|value| {
            value
                .get("timestamp")
                .and_then(|timestamp| timestamp.as_str())
                .map(str::to_string)
        })
        .or_else(|| {
            payload
                .get("timestamp")
                .and_then(|timestamp| timestamp.as_str())
                .map(str::to_string)
        })
        .or_else(|| {
            first
                .get("timestamp")
                .and_then(|timestamp| timestamp.as_str())
                .map(str::to_string)
        })
        .unwrap_or_default();
    if last_timestamp.is_empty() {
        return Ok(None);
    }

    Ok(Some(CodexSessionCandidate {
        started_at: started_at.to_string(),
        last_timestamp,
        session_id: session_id.to_string(),
    }))
}

fn codex_session_cwd_matches(
    cwd: &str,
    target_workdir: &str,
    canonical_target_workdir: &str,
) -> bool {
    cwd == target_workdir || canonical_path_key(Path::new(cwd)) == canonical_target_workdir
}

fn canonical_path_key(path: &Path) -> String {
    path.canonicalize()
        .unwrap_or_else(|_| path.to_path_buf())
        .to_string_lossy()
        .to_string()
}

fn cached_transcript(memory: &Option<MemoryStore>, audio_hash: &str) -> Option<String> {
    memory
        .as_ref()
        .and_then(|memory| match memory.cached_transcript(audio_hash) {
            Ok(transcript) => transcript,
            Err(err) => {
                warn!("failed to load cached transcript: {err:#}");
                None
            }
        })
}

fn save_transcript_cache(memory: &mut Option<MemoryStore>, audio_hash: &str, transcript: &str) {
    if let Some(memory) = memory.as_mut() {
        if let Err(err) = memory.save_transcript_cache(audio_hash, transcript) {
            warn!("failed to save transcript cache: {err:#}");
        }
    }
}

fn audio_cache_key(audio: &AudioReference) -> String {
    audio
        .encryption
        .as_ref()
        .map(|encryption| encryption.plaintext_sha256.clone())
        .unwrap_or_else(|| audio.sha256.clone())
}

async fn send_response(messenger: &NostrMessenger, receiver_pubkey: &str, response: String) {
    if let Err(err) = messenger.send_response_to(receiver_pubkey, response).await {
        error!("failed to send response DM: {err:#}");
    }
}

async fn send_status(messenger: &NostrMessenger, receiver_pubkey: &str, status: &str) {
    let status = status.trim();
    if status.is_empty() {
        return;
    }
    if let Err(err) = messenger
        .send_wire_to_pubkey(receiver_pubkey, WireMessage::status(status))
        .await
    {
        warn!("failed to send status DM: {err:#}");
    }
}

async fn send_response_and_remember(
    messenger: &NostrMessenger,
    memory: &mut Option<MemoryStore>,
    receiver_pubkey: &str,
    response: String,
    workdir: &Path,
) {
    match messenger
        .send_routed_response_to(
            receiver_pubkey,
            response.clone(),
            workdir.to_string_lossy().to_string(),
        )
        .await
    {
        Ok(event_id) => {
            if let Some(memory) = memory.as_mut() {
                if let Err(err) =
                    memory.record_outgoing(receiver_pubkey, &event_id, "response", &response)
                {
                    warn!("failed to record outgoing response memory: {err:#}");
                }
            }
        }
        Err(err) => error!("failed to send response DM: {err:#}"),
    }
}

fn spawn_compaction_if_needed(
    memory: &mut Option<MemoryStore>,
    peer_pubkey: &str,
    codex_config: &CodexConfig,
) {
    let Some(memory_store) = memory.as_ref() else {
        return;
    };
    let memory_config = memory_store.config();
    let peer_pubkey = peer_pubkey.to_string();
    let codex_config = codex_config.clone();

    tokio::spawn(async move {
        let mut memory = open_memory_store(memory_config);
        compact_memory_if_needed(&mut memory, &peer_pubkey, &codex_config).await;
    });
}

async fn compact_memory_if_needed(
    memory: &mut Option<MemoryStore>,
    peer_pubkey: &str,
    codex_config: &CodexConfig,
) {
    let Some(memory_store) = memory.as_ref() else {
        return;
    };
    let job = match memory_store.compaction_job(peer_pubkey) {
        Ok(job) => job,
        Err(err) => {
            warn!("failed to prepare memory compaction: {err:#}");
            return;
        }
    };
    let Some(job) = job else {
        return;
    };

    info!(
        "compacting SQLite memory through message {}",
        job.up_to_message_id
    );
    let summary = match run_codex(&job.prompt, codex_config).await {
        Ok(summary) => summary,
        Err(err) => {
            warn!("memory compaction failed: {err:#}");
            return;
        }
    };

    if let Some(memory_store) = memory.as_mut() {
        if let Err(err) = memory_store.save_summary(peer_pubkey, job.up_to_message_id, &summary) {
            warn!("failed to save compacted memory summary: {err:#}");
        }
    }
}

async fn run_codex_and_report(
    messenger: &NostrMessenger,
    memory: &mut Option<MemoryStore>,
    receiver_pubkey: &str,
    prompt: &str,
    codex_config: &CodexConfig,
    session_id: Option<&str>,
    cancel_token: &CodexCancelToken,
) -> std::result::Result<String, ()> {
    let first_attempt_config = codex_config_for_first_attempt(codex_config, session_id);
    let result = match run_codex_session_with_cancel(
        prompt,
        &first_attempt_config,
        session_id,
        Some(cancel_token),
    )
    .await
    {
        Ok(result) => result,
        Err(err) if is_codex_cancelled_error(&err) => {
            return report_codex_cancelled(messenger, receiver_pubkey).await;
        }
        Err(err) if is_codex_usage_limit_error(&err) => {
            match retry_codex_with_usage_limit_fallback(
                prompt,
                codex_config,
                session_id,
                cancel_token,
                err,
            )
            .await
            {
                Ok(result) => result,
                Err(err) if is_codex_cancelled_error(&err) => {
                    return report_codex_cancelled(messenger, receiver_pubkey).await;
                }
                Err(err) => return report_codex_error(messenger, receiver_pubkey, err).await,
            }
        }
        Err(err) if session_id.is_some() => {
            warn!("Codex resume failed; clearing session and retrying once: {err:#}");
            if let Some(memory) = memory.as_mut() {
                if let Err(clear_err) =
                    memory.clear_codex_session(receiver_pubkey, &codex_config.working_dir)
                {
                    warn!("failed to clear Codex session: {clear_err:#}");
                }
            }
            match run_codex_session_with_cancel(prompt, codex_config, None, Some(cancel_token))
                .await
            {
                Ok(result) => result,
                Err(err) if is_codex_cancelled_error(&err) => {
                    return report_codex_cancelled(messenger, receiver_pubkey).await;
                }
                Err(err) if is_codex_usage_limit_error(&err) => {
                    match retry_codex_with_usage_limit_fallback(
                        prompt,
                        codex_config,
                        None,
                        cancel_token,
                        err,
                    )
                    .await
                    {
                        Ok(result) => result,
                        Err(err) if is_codex_cancelled_error(&err) => {
                            return report_codex_cancelled(messenger, receiver_pubkey).await;
                        }
                        Err(err) => {
                            return report_codex_error(messenger, receiver_pubkey, err).await
                        }
                    }
                }
                Err(err) => return report_codex_error(messenger, receiver_pubkey, err).await,
            }
        }
        Err(err) => {
            return report_codex_error(messenger, receiver_pubkey, err).await;
        }
    };

    if let Some(next_session_id) = result
        .session_id
        .as_deref()
        .or(session_id)
        .filter(|value| !value.trim().is_empty())
    {
        if let Some(memory) = memory.as_mut() {
            if let Err(err) = memory.save_codex_session(
                receiver_pubkey,
                &codex_config.working_dir,
                next_session_id,
            ) {
                warn!("failed to save Codex session: {err:#}");
            }
        }
    }

    Ok(result.response)
}

fn codex_config_for_first_attempt(
    codex_config: &CodexConfig,
    session_id: Option<&str>,
) -> CodexConfig {
    if session_id.is_none() || codex_config.timeout <= CODEX_RESUME_TIMEOUT {
        return codex_config.clone();
    }

    let mut config = codex_config.clone();
    config.timeout = CODEX_RESUME_TIMEOUT;
    config
}

async fn retry_codex_with_usage_limit_fallback(
    prompt: &str,
    codex_config: &CodexConfig,
    session_id: Option<&str>,
    cancel_token: &CodexCancelToken,
    original_err: anyhow::Error,
) -> Result<CodexRunResult> {
    let Some(fallback_model) = codex_config.usage_limit_fallback_model.as_deref() else {
        return Err(original_err);
    };
    let original = format!("{original_err:#}");
    warn!(
        "Codex usage limit hit; retrying turn with fallback model `{}`",
        fallback_model
    );
    let fallback_config = codex_config.with_model_override(fallback_model);

    run_codex_session_with_cancel(prompt, &fallback_config, session_id, Some(cancel_token))
        .await
        .with_context(|| {
            format!(
                "Codex fallback model `{fallback_model}` failed after usage-limit error: {original}"
            )
        })
}

fn is_codex_cancelled_error(err: &anyhow::Error) -> bool {
    format!("{err:#}").contains("Codex cancelled")
}

async fn report_codex_cancelled(
    messenger: &NostrMessenger,
    receiver_pubkey: &str,
) -> std::result::Result<String, ()> {
    info!("codex task cancelled for {receiver_pubkey}");
    send_status(messenger, receiver_pubkey, "Cancelled.").await;
    Err(())
}

async fn report_codex_error(
    messenger: &NostrMessenger,
    receiver_pubkey: &str,
    err: anyhow::Error,
) -> std::result::Result<String, ()> {
    error!("codex failed: {err:#}");
    if let Err(send_err) = messenger
        .send_error_to(receiver_pubkey, format!("Codex failed: {err:#}"))
        .await
    {
        error!("failed to send error DM: {send_err:#}");
    }
    Err(())
}

fn nostr_config_from_env(worker_env: &WorkerEnvFile) -> Result<NostrConfig> {
    let secret_key = ensure_worker_secret(worker_env)?;
    let peer_pubkey = env::var("NOSTR_PEER_PUBKEY")
        .or_else(|_| env::var("NOSTR_MOBILE_PUBKEY"))
        .ok()
        .map(|peer| peer.trim().to_string())
        .filter(|peer| !peer.is_empty());
    let relays = env::var("NOSTR_RELAYS")
        .ok()
        .map(|raw| {
            raw.split(',')
                .map(str::trim)
                .filter(|relay| !relay.is_empty())
                .map(ToOwned::to_owned)
                .collect::<Vec<_>>()
        })
        .filter(|relays| !relays.is_empty())
        .unwrap_or_else(default_relays);

    Ok(NostrConfig {
        secret_key,
        receive_pubkeys: peer_pubkey.iter().cloned().collect(),
        peer_pubkey,
        relays,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    static ENV_LOCK: once_cell::sync::Lazy<std::sync::Mutex<()>> =
        once_cell::sync::Lazy::new(|| std::sync::Mutex::new(()));

    #[test]
    fn rejects_low_information_transcripts() {
        let response = low_information_transcript_response("You").unwrap();
        assert!(response.contains("I only heard \"You\""));
        assert!(low_information_transcript_response("  okay. ").is_some());
    }

    #[test]
    fn allows_meaningful_transcripts() {
        assert!(low_information_transcript_response("status").is_none());
        assert!(low_information_transcript_response("turn the lights off").is_none());
    }

    #[test]
    fn classifies_local_routes_without_codex() {
        assert_eq!(classify_request("/summary"), RequestClass::Command);
        assert_eq!(classify_request("status"), RequestClass::MemoryLookup);
        assert_eq!(
            classify_request("what repo am I in?"),
            RequestClass::MemoryLookup
        );
        assert_eq!(classify_request("thanks"), RequestClass::NoOp);
        assert_eq!(
            classify_request("fix the Android voice recording path"),
            RequestClass::Coding
        );
    }

    #[test]
    fn parses_spawn_worker_requests() {
        assert_eq!(
            parse_spawn_worker_request("/spawn /home/tom/code/repo"),
            Some(SpawnWorkerRequest {
                workdir: "/home/tom/code/repo".to_string(),
                create: false,
                silent: false,
            })
        );
        assert_eq!(
            parse_spawn_worker_request("/spawn '/home/tom/code/repo with spaces'"),
            Some(SpawnWorkerRequest {
                workdir: "/home/tom/code/repo with spaces".to_string(),
                create: false,
                silent: false,
            })
        );
        assert_eq!(
            parse_spawn_worker_request("start worker in ~/code/repo"),
            Some(SpawnWorkerRequest {
                workdir: "~/code/repo".to_string(),
                create: false,
                silent: false,
            })
        );
        assert_eq!(
            parse_spawn_worker_request("Spawn session in /home/tom/code/repo"),
            Some(SpawnWorkerRequest {
                workdir: "/home/tom/code/repo".to_string(),
                create: false,
                silent: false,
            })
        );
        assert_eq!(
            parse_spawn_worker_request("Start session in /home/tom/code/repo"),
            Some(SpawnWorkerRequest {
                workdir: "/home/tom/code/repo".to_string(),
                create: false,
                silent: false,
            })
        );
        assert_eq!(
            parse_spawn_worker_request("Restart session in /home/tom/code/repo"),
            Some(SpawnWorkerRequest {
                workdir: "/home/tom/code/repo".to_string(),
                create: false,
                silent: false,
            })
        );
        assert_eq!(
            parse_spawn_worker_request("Create session in /home/tom/code/new"),
            Some(SpawnWorkerRequest {
                workdir: "/home/tom/code/new".to_string(),
                create: true,
                silent: false,
            })
        );
        assert_eq!(
            parse_spawn_worker_request(
                r#"{"spawn_session":{"workdir":"/home/tom/code/new","create":true,"silent":true}}"#
            ),
            Some(SpawnWorkerRequest {
                workdir: "/home/tom/code/new".to_string(),
                create: true,
                silent: true,
            })
        );
        assert_eq!(
            parse_spawn_worker_request("/spawn --create new-repo"),
            Some(SpawnWorkerRequest {
                workdir: "new-repo".to_string(),
                create: true,
                silent: false,
            })
        );
        assert_eq!(parse_spawn_worker_request("/spawn"), None);
        assert_eq!(parse_spawn_worker_request("spawn a repo"), None);
    }

    #[test]
    fn detects_nonblocking_control_requests() {
        assert_eq!(
            nonblocking_control_request("query", r#"{"repo_list_request":{}}"#),
            Some(NonblockingControlRequest::RepoList)
        );
        assert_eq!(
            nonblocking_control_request(
                "query",
                r#"{"spawn_session":{"workdir":"/home/tom/code/repo"}}"#
            ),
            Some(NonblockingControlRequest::Spawn(SpawnWorkerRequest {
                workdir: "/home/tom/code/repo".to_string(),
                create: false,
                silent: false,
            }))
        );
        assert_eq!(
            nonblocking_control_request("audio", r#"{"repo_list_request":{}}"#),
            None
        );
    }

    #[test]
    fn caps_resume_attempt_timeout_only() {
        let config = CodexConfig {
            bin: "codex".to_string(),
            args: vec!["exec".to_string()],
            working_dir: PathBuf::from("/tmp"),
            timeout: Duration::from_secs(300),
            persist_sessions: true,
            usage_limit_fallback_model: None,
        };

        assert_eq!(
            codex_config_for_first_attempt(&config, Some("session")).timeout,
            CODEX_RESUME_TIMEOUT
        );
        assert_eq!(
            codex_config_for_first_attempt(&config, None).timeout,
            Duration::from_secs(300)
        );
    }

    #[test]
    fn parses_cancel_requests() {
        assert_eq!(
            parse_cancel_request("/cancel"),
            Some(CancelRequest { event_id: None })
        );
        assert_eq!(
            parse_cancel_request(r#"{"cancel_request":{"event_id":"abc123"}}"#),
            Some(CancelRequest {
                event_id: Some("abc123".to_string())
            })
        );
        assert_eq!(
            parse_cancel_request(r#"{"cancel_request":true}"#),
            Some(CancelRequest { event_id: None })
        );
        assert_eq!(parse_cancel_request(r#"{"cancel_request":false}"#), None);
        assert_eq!(parse_cancel_request("cancel this"), None);
    }

    #[test]
    fn requires_confirmed_shutdown_command() {
        assert!(is_shutdown_request("/shutdown"));
        assert!(is_shutdown_request("/shutdown confirm"));
        assert!(!is_shutdown_confirm_request("/shutdown"));
        assert!(is_shutdown_confirm_request("/shutdown confirm"));
    }

    #[test]
    fn defaults_initial_workdir_to_current_directory() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let previous_workdir = env::var_os("CODEX_WORKDIR");
        let previous_dir = env::current_dir().unwrap();

        let temp_dir = tempfile::tempdir().unwrap();
        env::remove_var("CODEX_WORKDIR");
        env::set_current_dir(temp_dir.path()).unwrap();

        let resolved = initial_workdir().unwrap();

        env::set_current_dir(previous_dir).unwrap();
        match previous_workdir {
            Some(value) => env::set_var("CODEX_WORKDIR", value),
            None => env::remove_var("CODEX_WORKDIR"),
        }

        assert_eq!(resolved, temp_dir.path());
    }

    #[test]
    fn extracts_top_level_route_metadata() {
        let raw = r#"{"session_id":"session-1","workdir":"/home/tom/code/phone","message":"hi"}"#;
        assert_eq!(
            route_workdir_from_json(raw).as_deref(),
            Some("/home/tom/code/phone")
        );
        assert_eq!(
            route_session_id_from_json(raw).as_deref(),
            Some("session-1")
        );
    }

    #[test]
    fn matches_targeted_cancel_requests_to_active_event() {
        assert!(cancel_request_matches(
            &CancelRequest { event_id: None },
            "active"
        ));
        assert!(cancel_request_matches(
            &CancelRequest {
                event_id: Some("active".to_string())
            },
            "active"
        ));
        assert!(!cancel_request_matches(
            &CancelRequest {
                event_id: Some("other".to_string())
            },
            "active"
        ));
    }

    #[test]
    fn detects_repo_list_requests() {
        assert!(is_repo_list_request("/repos"));
        assert!(is_repo_list_request(
            r#"{"repo_list_request":{"roots":["/home/tom/code"]}}"#
        ));
        assert!(!is_repo_list_request("/repo"));
        assert!(!is_repo_list_request("list repos"));
    }

    #[test]
    fn parses_worker_env_assignments() {
        assert_eq!(
            parse_env_assignment("NOSTR_SECRET_KEY='nsec123'"),
            Some(("NOSTR_SECRET_KEY".to_string(), "nsec123".to_string()))
        );
        assert_eq!(
            parse_env_assignment("export CODEX_BIN=\"/tmp/codex\""),
            Some(("CODEX_BIN".to_string(), "/tmp/codex".to_string()))
        );
        assert_eq!(parse_env_assignment("# comment"), None);
        assert_eq!(parse_env_assignment("1BAD=value"), None);
    }

    #[test]
    fn upserts_worker_env_values_without_dropping_existing_config() {
        let temp_dir = tempfile::tempdir().unwrap();
        let env_file = temp_dir.path().join(".env.server");
        fs::write(&env_file, "CODEX_BIN='/tmp/codex'\nNOSTR_SECRET_KEY=old\n").unwrap();

        upsert_env_file_values(
            &env_file,
            &[
                ("NOSTR_SECRET_KEY", "new"),
                ("NOSTR_PEER_PUBKEY", "npub123"),
            ],
        )
        .unwrap();

        let raw = fs::read_to_string(env_file).unwrap();
        assert!(raw.contains("CODEX_BIN='/tmp/codex'"));
        assert!(raw.contains("NOSTR_SECRET_KEY=new"));
        assert!(raw.contains("NOSTR_PEER_PUBKEY=npub123"));
        assert!(!raw.contains("NOSTR_SECRET_KEY=old"));
    }

    #[test]
    fn resolves_relative_spawn_workdir_from_worker_root() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let previous_workdir = env::var_os("CODEX_WORKDIR");

        let temp_dir = tempfile::tempdir().unwrap();
        let current_workdir = temp_dir.path().join("worker-root");
        fs::create_dir_all(&current_workdir).unwrap();
        env::remove_var("CODEX_WORKDIR");

        let request = SpawnWorkerRequest {
            workdir: "new-repo".to_string(),
            create: true,
            silent: false,
        };
        let resolved = resolve_spawn_workdir(&request, &current_workdir).unwrap();

        match previous_workdir {
            Some(value) => env::set_var("CODEX_WORKDIR", value),
            None => env::remove_var("CODEX_WORKDIR"),
        }

        assert_eq!(
            resolved,
            current_workdir.join("new-repo").canonicalize().unwrap()
        );
        assert!(resolved.is_dir());
    }

    #[test]
    fn rejects_existing_spawn_outside_worker_root() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let previous_workdir = env::var_os("CODEX_WORKDIR");

        let temp_dir = tempfile::tempdir().unwrap();
        let current_workdir = temp_dir.path().join("worker-root");
        let outside = temp_dir.path().join("other");
        fs::create_dir_all(&current_workdir).unwrap();
        fs::create_dir_all(&outside).unwrap();
        env::remove_var("CODEX_WORKDIR");

        let request = SpawnWorkerRequest {
            workdir: outside.to_string_lossy().to_string(),
            create: false,
            silent: false,
        };
        let error = resolve_spawn_workdir(&request, &current_workdir)
            .expect_err("existing folder outside worker root should fail");

        match previous_workdir {
            Some(value) => env::set_var("CODEX_WORKDIR", value),
            None => env::remove_var("CODEX_WORKDIR"),
        }

        assert!(error.to_string().contains("outside the allowed folders"));
    }

    #[test]
    fn rejects_spawn_create_outside_worker_root() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let previous_workdir = env::var_os("CODEX_WORKDIR");

        let temp_dir = tempfile::tempdir().unwrap();
        let current_workdir = temp_dir.path().join("worker-root");
        fs::create_dir_all(&current_workdir).unwrap();
        fs::create_dir_all(temp_dir.path().join("tmp")).unwrap();
        env::remove_var("CODEX_WORKDIR");

        let request = SpawnWorkerRequest {
            workdir: "../tmp/new-repo".to_string(),
            create: true,
            silent: false,
        };
        let error = resolve_spawn_workdir(&request, &current_workdir)
            .expect_err("create outside worker root should fail");

        match previous_workdir {
            Some(value) => env::set_var("CODEX_WORKDIR", value),
            None => env::remove_var("CODEX_WORKDIR"),
        }

        assert!(error
            .to_string()
            .contains("new folders may only be created"));
    }

    #[test]
    fn removes_stale_worker_lock_before_attach_check() {
        let temp_dir = tempfile::tempdir().unwrap();
        let workdir = temp_dir.path().join("repo");
        fs::create_dir_all(&workdir).unwrap();
        let lock_path = worker_state_path(&workdir, WORKER_LOCK_FILE);
        fs::create_dir_all(lock_path.parent().unwrap()).unwrap();
        fs::write(&lock_path, "not-a-pid\n").unwrap();

        let pid = running_worker_lock_pid(&workdir).unwrap();

        assert_eq!(pid, None);
        assert!(!lock_path.exists());
    }

    #[test]
    fn removes_worker_lock_for_unrelated_live_process() {
        let temp_dir = tempfile::tempdir().unwrap();
        let workdir = temp_dir.path().join("repo");
        fs::create_dir_all(&workdir).unwrap();
        let lock_path = worker_state_path(&workdir, WORKER_LOCK_FILE);
        fs::create_dir_all(lock_path.parent().unwrap()).unwrap();

        let mut child = StdCommand::new("sleep").arg("30").spawn().unwrap();
        fs::write(&lock_path, format!("{}\n", child.id())).unwrap();

        let pid = running_worker_lock_pid(&workdir).unwrap();
        let _ = child.kill();
        let _ = child.wait();

        assert_eq!(pid, None);
        assert!(!lock_path.exists());
    }

    #[test]
    fn requests_wav_retry_for_compressed_audio_only() {
        let mut audio = AudioReference {
            url: "https://example.com/audio.m4a".to_string(),
            sha256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef".to_string(),
            size: 123,
            media_type: "audio/mp4".to_string(),
            name: Some("voice.m4a".to_string()),
            encryption: None,
        };

        assert!(should_request_wav_retry(&audio));

        audio.media_type = "audio/wav; codecs=1".to_string();
        assert!(!should_request_wav_retry(&audio));
    }

    #[test]
    fn discovers_latest_codex_session_for_workdir() {
        let temp_dir = tempfile::tempdir().unwrap();
        let sessions_dir = temp_dir.path().join("sessions");
        let workdir = temp_dir.path().join("repo");
        let other_workdir = temp_dir.path().join("other");
        fs::create_dir_all(sessions_dir.join("2026/06/16")).unwrap();
        fs::create_dir_all(&workdir).unwrap();
        fs::create_dir_all(&other_workdir).unwrap();

        write_session_fixture(
            &sessions_dir.join("2026/06/16/old.jsonl"),
            "old-session",
            &workdir,
            "2026-06-16T10:00:00Z",
            "2026-06-16T10:01:00Z",
        );
        write_session_fixture(
            &sessions_dir.join("2026/06/16/new.jsonl"),
            "new-session",
            &workdir,
            "2026-06-16T10:00:00Z",
            "2026-06-16T10:05:00Z",
        );
        write_session_fixture_without_last_timestamp(
            &sessions_dir.join("2026/06/16/fallback.jsonl"),
            "fallback-session",
            &workdir,
            "2026-06-16T10:06:00Z",
        );
        write_session_fixture(
            &sessions_dir.join("2026/06/16/other.jsonl"),
            "other-session",
            &other_workdir,
            "2026-06-16T10:00:00Z",
            "2026-06-16T10:10:00Z",
        );

        let session = latest_codex_session_for_workdir_in(&sessions_dir, &workdir).unwrap();
        assert_eq!(session.as_deref(), Some("fallback-session"));
    }

    #[test]
    fn returns_no_codex_session_when_workdir_has_no_match() {
        let temp_dir = tempfile::tempdir().unwrap();
        let sessions_dir = temp_dir.path().join("sessions");
        let workdir = temp_dir.path().join("repo");
        let other_workdir = temp_dir.path().join("other");
        fs::create_dir_all(sessions_dir.join("2026/06/16")).unwrap();
        fs::create_dir_all(&workdir).unwrap();
        fs::create_dir_all(&other_workdir).unwrap();

        write_session_fixture(
            &sessions_dir.join("2026/06/16/other.jsonl"),
            "other-session",
            &other_workdir,
            "2026-06-16T10:00:00Z",
            "2026-06-16T10:05:00Z",
        );

        let session = latest_codex_session_for_workdir_in(&sessions_dir, &workdir).unwrap();
        assert_eq!(session, None);
    }

    #[cfg(target_family = "unix")]
    #[test]
    fn discovers_codex_session_for_canonical_workdir_match() {
        let temp_dir = tempfile::tempdir().unwrap();
        let sessions_dir = temp_dir.path().join("sessions");
        let real_workdir = temp_dir.path().join("repo");
        let linked_workdir = temp_dir.path().join("repo-link");
        fs::create_dir_all(sessions_dir.join("2026/06/16")).unwrap();
        fs::create_dir_all(&real_workdir).unwrap();
        std::os::unix::fs::symlink(&real_workdir, &linked_workdir).unwrap();

        write_session_fixture(
            &sessions_dir.join("2026/06/16/session.jsonl"),
            "canonical-session",
            &real_workdir,
            "2026-06-16T10:00:00Z",
            "2026-06-16T10:05:00Z",
        );

        let session = latest_codex_session_for_workdir_in(&sessions_dir, &linked_workdir).unwrap();
        assert_eq!(session.as_deref(), Some("canonical-session"));
    }

    #[test]
    fn loads_saved_codex_session_from_memory_by_peer_and_workdir() {
        let temp_dir = tempfile::tempdir().unwrap();
        let workdir = temp_dir.path().join("repo");
        fs::create_dir_all(&workdir).unwrap();
        let mut memory = MemoryStore::open(MemoryConfig {
            enabled: true,
            db_path: temp_dir.path().join("memory.sqlite3"),
            recent_messages: 12,
            compact_after_messages: 16,
            summary_max_chars: 5000,
            compaction_max_chars: 12000,
        })
        .unwrap()
        .unwrap();
        memory
            .save_codex_session("peer-1", &workdir, "stored-session")
            .unwrap();
        memory
            .save_codex_session("peer-2", &workdir, "other-peer-session")
            .unwrap();

        let session = load_codex_session(&Some(memory), "peer-1", &workdir, "continue");
        assert_eq!(session.as_deref(), Some("stored-session"));
    }

    #[test]
    fn adopts_latest_codex_session_when_memory_has_no_saved_session() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let previous_sessions_dir = env::var_os("CODEX_SESSIONS_DIR");

        let temp_dir = tempfile::tempdir().unwrap();
        let sessions_dir = temp_dir.path().join("sessions");
        let workdir = temp_dir.path().join("repo");
        fs::create_dir_all(sessions_dir.join("2026/06/16")).unwrap();
        fs::create_dir_all(&workdir).unwrap();
        env::set_var("CODEX_SESSIONS_DIR", &sessions_dir);

        write_session_fixture(
            &sessions_dir.join("2026/06/16/session.jsonl"),
            "latest-session",
            &workdir,
            "2026-06-16T10:00:00Z",
            "2026-06-16T10:05:00Z",
        );

        let session = load_codex_session(&None, "peer-1", &workdir, "continue");
        match previous_sessions_dir {
            Some(value) => env::set_var("CODEX_SESSIONS_DIR", value),
            None => env::remove_var("CODEX_SESSIONS_DIR"),
        }

        assert_eq!(session.as_deref(), Some("latest-session"));
    }

    #[test]
    fn latest_issue_request_refreshes_older_saved_codex_session() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let previous_sessions_dir = env::var_os("CODEX_SESSIONS_DIR");

        let temp_dir = tempfile::tempdir().unwrap();
        let sessions_dir = temp_dir.path().join("sessions");
        let workdir = temp_dir.path().join("repo");
        fs::create_dir_all(sessions_dir.join("2026/06/16")).unwrap();
        fs::create_dir_all(&workdir).unwrap();
        env::set_var("CODEX_SESSIONS_DIR", &sessions_dir);

        write_session_fixture(
            &sessions_dir.join("2026/06/16/older.jsonl"),
            "stored-session",
            &workdir,
            "2026-06-16T10:00:00Z",
            "2026-06-16T10:30:00Z",
        );
        write_session_fixture(
            &sessions_dir.join("2026/06/16/newer.jsonl"),
            "newer-session",
            &workdir,
            "2026-06-16T11:00:00Z",
            "2026-06-16T11:05:00Z",
        );

        let mut memory = MemoryStore::open(MemoryConfig {
            enabled: true,
            db_path: temp_dir.path().join("memory.sqlite3"),
            recent_messages: 12,
            compact_after_messages: 16,
            summary_max_chars: 5000,
            compaction_max_chars: 12000,
        })
        .unwrap()
        .unwrap();
        memory
            .save_codex_session("peer-1", &workdir, "stored-session")
            .unwrap();

        let session = load_codex_session(
            &Some(memory),
            "peer-1",
            &workdir,
            "How is progress with the last issue?",
        );
        match previous_sessions_dir {
            Some(value) => env::set_var("CODEX_SESSIONS_DIR", value),
            None => env::remove_var("CODEX_SESSIONS_DIR"),
        }

        assert_eq!(session.as_deref(), Some("newer-session"));
    }

    fn write_session_fixture(
        path: &Path,
        session_id: &str,
        workdir: &Path,
        started_at: &str,
        last_active: &str,
    ) {
        let first = serde_json::json!({
            "timestamp": started_at,
            "type": "session_meta",
            "payload": {
                "id": session_id,
                "timestamp": started_at,
                "cwd": workdir.to_string_lossy(),
            }
        });
        let last = serde_json::json!({
            "timestamp": last_active,
            "type": "event_msg",
            "payload": {"type": "token_count"}
        });
        fs::write(path, format!("{first}\n{last}\n")).unwrap();
    }

    fn write_session_fixture_without_last_timestamp(
        path: &Path,
        session_id: &str,
        workdir: &Path,
        started_at: &str,
    ) {
        let first = serde_json::json!({
            "timestamp": started_at,
            "type": "session_meta",
            "payload": {
                "id": session_id,
                "timestamp": started_at,
                "cwd": workdir.to_string_lossy(),
            }
        });
        let last = serde_json::json!({
            "type": "event_msg",
            "payload": {"type": "token_count"}
        });
        fs::write(path, format!("{first}\n{last}\n")).unwrap();
    }
}
