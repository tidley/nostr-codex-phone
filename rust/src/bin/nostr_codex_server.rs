use std::any::Any;
use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::env;
use std::fs::{self, File};
use std::io::{BufRead, BufReader};
use std::panic::AssertUnwindSafe;
use std::path::{Path, PathBuf};
use std::process::Command as StdCommand;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::sync::Mutex as StdMutex;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, bail, Context, Result};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use fips_client::FipsClientConfig;
use fips_mobile::{
    fips_application_service_frames, FipsApplicationEnvelope, FipsApplicationFrameAssembler,
    FipsMobileClient,
};
use futures_util::FutureExt;
use nostr_sdk::prelude::{Keys, PublicKey, ToBech32};
use qrcode::{Color, QrCode};
use rand::{rngs::OsRng, RngCore};
use sha2::{Digest, Sha256};
#[path = "nostr_codex_server/memory.rs"]
mod memory;
use memory::{MemoryConfig, MemoryStore, RecordedMessage};
use rust_lib_nostr_codex_phone::codex::{
    ensure_opencode_session, is_codex_usage_limit_error, list_opencode_models,
    list_opencode_sessions, new_opencode_session, run_codex,
    run_codex_session_with_cancel_and_events, AgentBackend, CodexCancelToken, CodexConfig,
    CodexRunResult, OpenCodeModel, OpenCodeSessionInfo,
};
use rust_lib_nostr_codex_phone::invite::InviteStore;
use rust_lib_nostr_codex_phone::nostr_client::{
    default_relays, IncomingMessage, NostrConfig, NostrMessenger,
};
use rust_lib_nostr_codex_phone::protocol::{
    parse_media_bundle_query, parse_wire_message, AudioReference, CreateInvite, InviteAccepted,
    InviteCreated, InviteRejected, MediaBundle, MediaReference, OpenCodeSessionList,
    OpenCodeSessionListEntry, RedeemInvite, RepoList, RepoListEntry, RepoListRoot, TargetInvite,
    TargetParent, ToolResult, WireMessage, WorkspaceAgentPayload, WorkspaceChannelMemberPayload,
    WorkspaceChannelPayload, WorkspaceConversationAgentPayload,
    WorkspaceConversationPrepromptPayload, WorkspaceMemberPayload, WorkspaceMentionPayload,
    WorkspaceMessagePayload, WorkspaceRequest, WorkspaceTypingPayload, WorkspaceUpdate,
};
use rust_lib_nostr_codex_phone::transcribe::{
    download_blossom_attachment, download_blossom_audio, transcribe_audio, AudioConfig,
    DownloadedAudio, TranscribeConfig,
};
use rust_lib_nostr_codex_phone::workspace::{
    WorkspaceAgent, WorkspaceAgentOpenCodeProfile, WorkspaceConversationAgent,
    WorkspaceConversationPreprompt, WorkspaceMessage, WorkspaceStore,
};
use serde::{Deserialize, Serialize};
use tokio::sync::{mpsc, oneshot, Mutex, Notify};
use tokio::time::{interval, sleep, MissedTickBehavior};
use tracing::{error, info, warn};

#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct AgentScopeMetrics {
    active_state: String,
    memory_bytes: Option<u64>,
    cpu_usage_nsec: Option<u64>,
    task_count: Option<u64>,
    started_at: Option<i64>,
}

static AGENT_SCOPE_METRICS: once_cell::sync::Lazy<StdMutex<HashMap<String, AgentScopeMetrics>>> =
    once_cell::sync::Lazy::new(|| StdMutex::new(HashMap::new()));

const WORKER_STATE_DIR: &str = ".nostr-codex";
const WORKER_REGISTRY_FILE: &str = "workers.json";
const WORKER_LOCK_FILE: &str = "worker.lock";
const CODEX_RESUME_TIMEOUT: Duration = Duration::from_secs(45);
const CODEX_STATUS_MIN_INTERVAL: Duration = Duration::from_secs(8);
const WORKSPACE_VOICE_DEDUPE_CAPACITY: usize = 256;
const WORKSPACE_HISTORY_REQUEST_STEP: usize = 5;
// Gift-wrapped Nostr messages limit plaintext to 65,535 bytes. Leave room for
// transfer metadata and future payload fields rather than batching by count.
// GiftWrap adds encrypted/base64 envelope overhead, so this must stay well
// below the NIP-44 plaintext ceiling accepted by relays and clients.
const NOSTR_WORKSPACE_TRANSFER_MAX_BYTES: usize = 24 * 1024;
const WORKSPACE_FIPS_TRANSFER_CHUNK_SIZE: usize = 64;
const WORKSPACE_SNAPSHOT_MESSAGE_LIMIT: usize = 20;
const WORKSPACE_HISTORY_REQUEST_MAX: usize = 50;
const WORKSPACE_HISTORY_REQUEST_ATTEMPTS: usize = 3;
const WORKSPACE_AGENT_SESSION_CONTEXT: &str = "workspace-history-protocol-v1";
const WORKSPACE_FIPS_CAPABILITY_BYTES: usize = 32;
const WORKSPACE_FIPS_CAPABILITY_TTL: Duration = Duration::from_secs(90);
const WORKSPACE_FIPS_PROTOCOL_VERSION: u8 = 1;
// FIPS removes idle links after 30 seconds. A 5-second application heartbeat
// leaves room for scheduling and packet delay without making the route stale.
const WORKSPACE_FIPS_HEARTBEAT_INTERVAL: Duration = Duration::from_secs(5);
const WORKSPACE_FIPS_HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(10);
const WORKSPACE_FIPS_SERVICE_PORT: u16 = 49_160;
const WORKSPACE_FIPS_ROUTE_CAPACITY: usize = 128;
const WORKSPACE_FIPS_ASSEMBLER_CAPACITY: usize = 256;
const SYSTEM_STATUS_HISTORY_MAX_BYTES: usize = 10 * 1024 * 1024;
const SYSTEM_STATUS_SAMPLE_INTERVAL: Duration = Duration::from_secs(10 * 60);
const AGENT_SCOPE_SAMPLE_INTERVAL: Duration = Duration::from_secs(5);
const AGENT_SCOPE_STUCK_AFTER: Duration = Duration::from_secs(15 * 60);
// SHA-256 input is the UTF-8 bytes of this domain, a zero byte, then the pairing secret.
const PAIRING_CONFIRMATION_DOMAIN: &str = "nostr-codex/first-owner-confirmation/v1";

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
    new_session: bool,
    silent: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CancelRequest {
    event_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum NonblockingControlRequest {
    Spawn(SpawnWorkerRequest),
    RepoList(Option<String>),
    OpenCodeSessions,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct WorkspaceVoiceKey {
    sender_pubkey: String,
    sha256: String,
}

/// Tracks voice blobs that the workspace route has already transcribed. Some
/// clients/relays replay the same blob through the legacy media route later.
struct WorkspaceVoiceDeduper {
    keys: HashSet<WorkspaceVoiceKey>,
    order: VecDeque<WorkspaceVoiceKey>,
}

impl WorkspaceVoiceDeduper {
    fn new() -> Self {
        Self {
            keys: HashSet::new(),
            order: VecDeque::new(),
        }
    }

    fn contains(&self, key: &WorkspaceVoiceKey) -> bool {
        self.keys.contains(key)
    }

    fn insert(&mut self, key: WorkspaceVoiceKey) {
        if !self.keys.insert(key.clone()) {
            return;
        }
        self.order.push_back(key);
        if self.order.len() > WORKSPACE_VOICE_DEDUPE_CAPACITY {
            if let Some(oldest) = self.order.pop_front() {
                self.keys.remove(&oldest);
            }
        }
    }
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

struct WorkerRuntimeConfig {
    messenger: Arc<NostrMessenger>,
    worker_env: WorkerEnvFile,
    owner_peer_hex: Option<String>,
    allowed_owner_hexes: Vec<String>,
    pairing_secret: Option<String>,
    control: RuntimeControl,
    memory_config: MemoryConfig,
    codex_config: CodexConfig,
    audio_config: AudioConfig,
    transcribe_config: TranscribeConfig,
    relays: Vec<String>,
    fips_secret_key: String,
    public_key: String,
    manager: RepoRuntimeManager,
    invites: InviteStore,
    workspace: WorkspaceStore,
    workspace_path: PathBuf,
}

struct WorkspaceFipsPeer {
    member: String,
    npub: String,
    connection_id: String,
    last_pong: Instant,
    last_message_id: u64,
    next_message_id: u64,
}

#[derive(Clone)]
struct WorkspaceOutbound {
    fips_routes: Arc<Mutex<HashMap<String, String>>>,
    fips_outgoing: mpsc::Sender<WorkspaceFipsOutbound>,
}

struct WorkspaceFipsOutbound {
    member: String,
    wire: WireMessage,
    delivered: oneshot::Sender<Result<()>>,
}

// Peer workers outlive the dispatcher iteration that admitted their FIPS
// frame, so they share this runtime's authenticated FIPS route registry.
static WORKSPACE_OUTBOUND: once_cell::sync::Lazy<StdMutex<Option<WorkspaceOutbound>>> =
    once_cell::sync::Lazy::new(|| StdMutex::new(None));

impl WorkspaceOutbound {
    async fn has_fips_route(&self, member: &str) -> bool {
        self.fips_routes.lock().await.contains_key(member)
    }

    async fn send(
        &self,
        messenger: &NostrMessenger,
        member: &str,
        wire: WireMessage,
    ) -> Result<()> {
        if self.fips_routes.lock().await.contains_key(member) {
            let (delivered, receipt) = oneshot::channel();
            self.fips_outgoing
                .send(WorkspaceFipsOutbound {
                    member: member.to_string(),
                    wire: wire.clone(),
                    delivered,
                })
                .await
                .map_err(|_| anyhow!("shared FIPS workspace outbound queue stopped"))?;
            if receipt
                .await
                .map_err(|_| anyhow!("shared FIPS workspace outbound receipt dropped"))?
                .is_ok()
            {
                return Ok(());
            }
            // A route can disappear between the registry lookup and its send.
            // Deliver this update through Nostr instead of dropping it.
            self.fips_routes.lock().await.remove(member);
        }
        messenger
            .send_wire_to_pubkey(member, wire)
            .await
            .map(|_| ())
    }
}

async fn send_application_wire(
    messenger: &NostrMessenger,
    member: &str,
    wire: WireMessage,
) -> Result<()> {
    let outbound = WORKSPACE_OUTBOUND
        .lock()
        .expect("workspace outbound registry lock poisoned")
        .clone();
    if let Some(outbound) = outbound {
        outbound.send(messenger, member, wire).await
    } else {
        messenger
            .send_wire_to_pubkey(member, wire)
            .await
            .map(|_| ())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
enum WorkspaceConversation {
    Channel(String),
    Direct(String, String),
}

impl WorkspaceConversation {
    fn from_message(message: &WorkspaceMessage) -> Option<Self> {
        match (&message.channel_id, &message.recipient_pubkey) {
            (Some(channel_id), None) => Some(Self::Channel(channel_id.clone())),
            (None, Some(recipient)) => {
                let mut participants = [message.sender_pubkey.clone(), recipient.clone()];
                participants.sort();
                Some(Self::Direct(
                    participants[0].clone(),
                    participants[1].clone(),
                ))
            }
            _ => None,
        }
    }
}

fn workspace_agent_job_matches_trigger(
    message: &WorkspaceMessage,
    conversation: &WorkspaceConversation,
) -> bool {
    !message.sender_pubkey.starts_with("agent:")
        && WorkspaceConversation::from_message(message).as_ref() == Some(conversation)
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct WorkspaceAgentQueueKey {
    agent_id: String,
    conversation: WorkspaceConversation,
}

struct WorkspaceAgentJob {
    trigger_message_id: String,
}

struct WorkspaceAgentQueues {
    senders: HashMap<WorkspaceAgentQueueKey, mpsc::UnboundedSender<WorkspaceAgentJob>>,
    active_turns: Arc<Mutex<HashMap<String, CodexCancelToken>>>,
    workspace_path: PathBuf,
    messenger: Arc<NostrMessenger>,
    outbound: WorkspaceOutbound,
    codex_config: CodexConfig,
}

impl WorkspaceAgentQueues {
    fn new(
        workspace_path: PathBuf,
        messenger: Arc<NostrMessenger>,
        outbound: WorkspaceOutbound,
        codex_config: CodexConfig,
    ) -> Self {
        Self {
            senders: HashMap::new(),
            active_turns: Arc::new(Mutex::new(HashMap::new())),
            workspace_path,
            messenger,
            outbound,
            codex_config,
        }
    }

    fn enqueue(
        &mut self,
        agent_id: String,
        conversation: WorkspaceConversation,
        trigger_message_id: String,
    ) {
        let key = WorkspaceAgentQueueKey {
            agent_id: agent_id.clone(),
            conversation: conversation.clone(),
        };
        let sender = self.senders.entry(key).or_insert_with(|| {
            // A mentioned message is durable in the workspace store. Do not lose its
            // turn merely because an agent is still working through earlier messages.
            let (sender, receiver) = mpsc::unbounded_channel();
            tokio::task::spawn_local(workspace_agent_queue_worker(
                receiver,
                agent_id.clone(),
                conversation,
                Arc::clone(&self.active_turns),
                self.workspace_path.clone(),
                Arc::clone(&self.messenger),
                self.outbound.clone(),
                self.codex_config.clone(),
            ));
            sender
        });
        if let Err(err) = sender.send(WorkspaceAgentJob { trigger_message_id }) {
            warn!(agent = %agent_id, trigger = %err.0.trigger_message_id, "workspace agent queue stopped; dropping turn");
        }
    }
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
    allowed_owner_hexes: &[String],
    pairing_secret: &Option<String>,
    message: &IncomingMessage,
) -> bool {
    match owner_peer_hex.as_deref() {
        Some(owner) if owner != message.sender_pubkey_hex => {
            if allowed_owner_hexes
                .iter()
                .any(|allowed| allowed == &message.sender_pubkey_hex)
            {
                return true;
            }
            warn!(
                "ignored DM from non-owner {}; owner is {}",
                message.sender_pubkey_hex, owner
            );
            false
        }
        Some(_) => true,
        None => {
            if !pairing_credentials_match(pairing_secret, message) {
                warn!(
                    "ignored first-owner claim from {} without matching pairing credentials",
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

fn pairing_credentials_match(pairing_secret: &Option<String>, message: &IncomingMessage) -> bool {
    let Some(expected) = pairing_secret
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    else {
        return false;
    };
    message_pairing_secret(message).as_deref() == Some(expected)
        && message_pairing_confirmation(message).as_deref()
            == Some(pairing_confirmation_code(expected).as_str())
}

fn pairing_confirmation_code(pairing_secret: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(PAIRING_CONFIRMATION_DOMAIN.as_bytes());
    hasher.update([0]);
    hasher.update(pairing_secret.trim().as_bytes());
    let digest = hasher.finalize();
    let number = u32::from_be_bytes(digest[..4].try_into().expect("SHA-256 is 32 bytes"));
    format!("{:06}", number % 1_000_000)
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

fn message_pairing_confirmation(message: &IncomingMessage) -> Option<String> {
    pairing_confirmation_from_json(&message.text)
        .or_else(|| pairing_confirmation_from_json(&message.raw_json))
}

fn pairing_confirmation_from_json(raw: &str) -> Option<String> {
    let value: serde_json::Value = serde_json::from_str(raw).ok()?;
    let object = value.as_object()?;
    object
        .get("pairing_confirmation")
        .or_else(|| object.get("pairingConfirmation"))
        .and_then(|value| value.as_str())
        .map(str::trim)
        .filter(|value| value.len() == 6 && value.bytes().all(|byte| byte.is_ascii_digit()))
        .map(ToOwned::to_owned)
}

fn is_pairing_claim_message(message: &IncomingMessage) -> bool {
    message_pairing_secret(message).is_some()
}

fn routed_codex_config(config: &CodexConfig, message: &IncomingMessage) -> Result<CodexConfig> {
    let mut routed = config.clone();
    if let Some(workdir) = route_workdir_from_json(&message.raw_json)
        .or_else(|| route_workdir_from_json(&message.text))
    {
        let requested = PathBuf::from(workdir);
        let canonical = requested.canonicalize().with_context(|| {
            format!("route workdir `{}` is not accessible", requested.display())
        })?;
        if !canonical.is_dir() {
            bail!("route workdir `{}` is not a directory", canonical.display());
        }
        ensure_spawn_existing_allowed(
            &canonical,
            &canonical_allowed_workdir_roots(&config.working_dir)?,
        )?;
        routed.working_dir = canonical;
    }
    if let Some(model) =
        route_model_from_json(&message.raw_json).or_else(|| route_model_from_json(&message.text))
    {
        routed = routed.with_model_override(&model);
    }
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

fn route_model_from_json(raw: &str) -> Option<String> {
    let value: serde_json::Value = serde_json::from_str(raw).ok()?;
    value
        .get("model")
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
    let memory_config = MemoryConfig::from_env(
        &codex_config.working_dir,
        codex_config.backend == AgentBackend::Codex,
    );
    let memory_probe = open_memory_store(memory_config.clone());
    let messenger = Arc::new(
        NostrMessenger::connect_with_unrestricted_inbox(nostr_config.clone(), true).await?,
    );
    let owner_peer_hex = nostr_config
        .peer_pubkey
        .as_deref()
        .map(pubkey_to_hex)
        .transpose()?;
    let allowed_owner_hexes = nostr_config
        .receive_pubkeys
        .iter()
        .map(|pubkey| pubkey_to_hex(pubkey))
        .collect::<Result<Vec<_>>>()?;
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
    if !nostr_config.receive_pubkeys.is_empty() {
        info!(
            "accepted peer pubkeys: {}",
            nostr_config.receive_pubkeys.join(", ")
        );
    }
    info!("relays: {}", nostr_config.relays.join(", "));
    match codex_config.backend {
        AgentBackend::OpenCode => {
            info!(
                "agent backend: opencode CLI {} agent={}",
                codex_config.opencode.bin, codex_config.opencode.agent
            );
        }
        AgentBackend::Codex => {
            info!(
                "agent backend: codex {} {}",
                codex_config.bin,
                codex_config.args.join(" ")
            );
            match &codex_config.usage_limit_fallback_model {
                Some(model) => info!("codex usage-limit fallback model: {model}"),
                None => info!("codex usage-limit fallback model: disabled"),
            }
        }
    }
    info!(
        "persistent agent sessions: {}",
        codex_config.persist_sessions
    );
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
    let invites = InviteStore::open(&worker_state_path(
        &codex_config.working_dir,
        "invites.sqlite3",
    ))?;
    let workspace_path = worker_state_path(&codex_config.working_dir, "workspace.sqlite3");
    let workspace = WorkspaceStore::open(&workspace_path)?;
    initialize_workspace_members(&workspace, owner_peer_hex.as_deref(), &allowed_owner_hexes)?;
    let config = WorkerRuntimeConfig {
        messenger,
        worker_env,
        owner_peer_hex,
        allowed_owner_hexes,
        pairing_secret,
        control: RuntimeControl::new(true),
        memory_config,
        codex_config,
        audio_config,
        transcribe_config,
        relays: nostr_config.relays,
        fips_secret_key: nostr_config.secret_key,
        public_key: server_pubkey,
        manager,
        invites,
        workspace,
        workspace_path,
    };
    tokio::task::LocalSet::new()
        .run_until(run_worker_runtime(config))
        .await
}

async fn run_worker_runtime(mut config: WorkerRuntimeConfig) -> Result<()> {
    let mut session_workers = HashMap::<String, mpsc::Sender<IncomingMessage>>::new();
    let mut workspace_voice_deduper = WorkspaceVoiceDeduper::new();
    let fips_routes = Arc::new(Mutex::new(HashMap::new()));
    let (fips_outgoing, fips_outbound_messages) = mpsc::channel(128);
    let workspace_outbound = WorkspaceOutbound {
        fips_routes: Arc::clone(&fips_routes),
        fips_outgoing,
    };
    *WORKSPACE_OUTBOUND
        .lock()
        .expect("workspace outbound registry lock poisoned") = Some(workspace_outbound.clone());
    let mut workspace_agent_queues = WorkspaceAgentQueues::new(
        config.workspace_path.clone(),
        Arc::clone(&config.messenger),
        workspace_outbound.clone(),
        config.codex_config.clone(),
    );
    flush_workspace_notification_outbox(
        &config.workspace,
        config.messenger.as_ref(),
        &workspace_outbound,
    )
    .await;
    let capabilities = Arc::new(Mutex::new(HashMap::new()));
    // The FIPS acceptor owns its socket, while this bounded queue feeds proven
    // application envelopes through the same authorization and dispatch path as DMs.
    let (fips_incoming, mut fips_messages) = mpsc::channel(128);
    tokio::task::spawn_local(run_workspace_fips_acceptor(
        config.fips_secret_key.clone(),
        config.relays.clone(),
        Arc::clone(&capabilities),
        config.workspace_path.clone(),
        fips_incoming,
        fips_routes,
        fips_outbound_messages,
    ));
    start_system_status_collector(
        worker_state_path(&config.codex_config.working_dir, "system-status.jsonl"),
        config.control.clone(),
    );
    if env::var("OPENCODE_SYSTEMD_SCOPE")
        .ok()
        .is_some_and(|value| !is_falsey_env(&value))
    {
        start_agent_scope_metrics_collector(config.control.clone());
    }

    loop {
        let message = tokio::select! {
            message = config.messenger.next_message(Duration::from_secs(3600)) => message?,
            message = fips_messages.recv() => message,
            _ = config.control.shutdown_notify.notified() => {
                if config.control.is_shutdown_requested() {
                    info!("runtime shutdown requested");
                    return Ok(());
                }
                continue;
            }
        };
        let Some(message) = message else { continue };
        info!(
            event_id = %message.event_id,
            sender = %message.sender_pubkey,
            kind = %message.kind,
            "received Nostr message"
        );
        // Invite redemption must run before the owner gate because invitees are not
        // members yet and desktop clients wrap the request in a query message.
        if let Some(code) = invite_redemption_code(&message) {
            match config.invites.redeem(&code, &message.sender_pubkey_hex) {
                Ok(true) => {
                    let mut allowed = env_csv("NOSTR_RECEIVE_PUBKEYS").unwrap_or_default();
                    if let Some(owner) = env_nonempty("NOSTR_PEER_PUBKEY") {
                        if !allowed.iter().any(|key| key == &owner) {
                            allowed.push(owner);
                        }
                    }
                    if !allowed.iter().any(|key| key == &message.sender_pubkey) {
                        allowed.push(message.sender_pubkey.clone());
                    }
                    if let Err(err) = upsert_env_file_values(
                        &config.worker_env.path,
                        &[("NOSTR_RECEIVE_PUBKEYS", allowed.join(",").as_str())],
                    ) {
                        warn!("failed to persist redeemed member: {err:#}");
                        let _ = config.messenger.send_wire_to_pubkey(&message.sender_pubkey_hex, WireMessage::invite_rejected(InviteRejected { reason: "Invite could not be saved; ask the owner to create a new code.".to_string() })).await;
                        continue;
                    }
                    config
                        .allowed_owner_hexes
                        .push(message.sender_pubkey_hex.clone());
                    if let Err(err) = config.workspace.add_member(&message.sender_pubkey_hex) {
                        warn!("failed to persist redeemed workspace member: {err:#}");
                        continue;
                    }
                    let _ = config
                        .messenger
                        .send_wire_to_pubkey(
                            &message.sender_pubkey_hex,
                            WireMessage::invite_accepted(InviteAccepted {
                                recipient_pubkey: message.sender_pubkey.clone(),
                            }),
                        )
                        .await;
                    if let Err(err) = send_workspace_snapshot(
                        &config.workspace,
                        config.messenger.as_ref(),
                        &workspace_outbound,
                        &message.sender_pubkey_hex,
                    )
                    .await
                    {
                        warn!("failed to send redeemed member workspace snapshot: {err:#}");
                    }
                }
                Ok(false) => {
                    let _ = config
                        .messenger
                        .send_wire_to_pubkey(
                            &message.sender_pubkey_hex,
                            WireMessage::invite_rejected(InviteRejected {
                                reason: "Invite code is invalid, expired, or already used."
                                    .to_string(),
                            }),
                        )
                        .await;
                }
                Err(err) => {
                    warn!("invite redemption failed: {err:#}");
                    let _ = config
                        .messenger
                        .send_wire_to_pubkey(
                            &message.sender_pubkey_hex,
                            WireMessage::invite_rejected(InviteRejected {
                                reason: "Invite code could not be redeemed.".to_string(),
                            }),
                        )
                        .await;
                }
            }
            continue;
        }

        if !accept_or_claim_owner(
            &config.worker_env,
            &mut config.owner_peer_hex,
            &config.allowed_owner_hexes,
            &config.pairing_secret,
            &message,
        ) {
            continue;
        }

        if config.owner_peer_hex.as_deref() == Some(&message.sender_pubkey_hex) {
            config.workspace.add_member(&message.sender_pubkey_hex)?;
        }

        // Authorization for workspace traffic is the persisted membership list,
        // not the transport allowlist. This keeps revoked/unpersisted peers out.
        if !config.workspace.is_member(&message.sender_pubkey_hex)? {
            warn!(
                "ignored workspace-unenrolled peer {}",
                message.sender_pubkey_hex
            );
            continue;
        }

        if let Some(request) = workspace_request(&message) {
            let action = request.action.clone();
            info!(
                action = %action,
                sender = %message.sender_pubkey,
                "received workspace request"
            );
            let workspace_voice_key = workspace_voice_key(&message.sender_pubkey_hex, &request);
            if workspace_voice_key
                .as_ref()
                .is_some_and(|key| workspace_voice_deduper.contains(key))
            {
                info!(
                    "ignored duplicate workspace voice event {} from {}",
                    message.event_id, message.sender_pubkey
                );
                continue;
            }
            match process_workspace_request(
                &config.workspace,
                config.messenger.as_ref(),
                &workspace_outbound,
                &message.sender_pubkey_hex,
                config.owner_peer_hex.as_deref(),
                &message.event_id,
                request,
                &config.codex_config,
                &config.audio_config,
                &config.transcribe_config,
                &mut workspace_agent_queues,
                &capabilities,
            )
            .await
            {
                Ok(_) => {
                    if let Some(key) = workspace_voice_key {
                        workspace_voice_deduper.insert(key);
                    }
                }
                Err(err) => {
                    warn!(
                        action = %action,
                        sender = %message.sender_pubkey,
                        "workspace request failed: {err:#}"
                    );
                    let _ = config
                        .messenger
                        .send_error_to(&message.sender_pubkey_hex, err.to_string())
                        .await;
                }
            }
            continue;
        }

        if legacy_message_replays_workspace_voice(&message, &workspace_voice_deduper) {
            info!(
                "ignored legacy replay of workspace voice event {} from {}",
                message.event_id, message.sender_pubkey
            );
            continue;
        }

        if let Some(request) = invite_creation_request(&message) {
            if config.owner_peer_hex.as_deref() != Some(&message.sender_pubkey_hex)
                && !config.workspace.is_admin(&message.sender_pubkey_hex)?
            {
                let _ = config
                    .messenger
                    .send_wire_to_pubkey(
                        &message.sender_pubkey_hex,
                        WireMessage::invite_rejected(InviteRejected {
                            reason: "Only workspace owners and admins can create invites."
                                .to_string(),
                        }),
                    )
                    .await;
                continue;
            }
            match config.invites.create(request.expires_in_seconds) {
                Ok(invite) => {
                    let _ = config
                        .messenger
                        .send_wire_to_pubkey(
                            &message.sender_pubkey_hex,
                            WireMessage::invite_created(InviteCreated {
                                code: workspace_invite_code(
                                    &invite.secret,
                                    &config.public_key,
                                    &config.relays,
                                    &config.codex_config.working_dir,
                                )?,
                                expires_at: invite.expires_at,
                            }),
                        )
                        .await;
                }
                Err(err) => {
                    let _ = config
                        .messenger
                        .send_wire_to_pubkey(
                            &message.sender_pubkey_hex,
                            WireMessage::invite_rejected(InviteRejected {
                                reason: err.to_string(),
                            }),
                        )
                        .await;
                }
            }
            continue;
        }

        let worker_key = session_worker_key(&message);
        let sender = session_workers
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
            warn!("session worker for {worker_key} stopped; restarting and retrying message");
            session_workers.remove(&worker_key);
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
                error!(
                    "restarted session worker for {worker_key} stopped; dropping incoming message"
                );
            } else {
                session_workers.insert(worker_key, sender);
            }
        }
    }
}

fn start_system_status_collector(history_path: PathBuf, control: RuntimeControl) {
    tokio::spawn(async move {
        let mut samples = interval(SYSTEM_STATUS_SAMPLE_INTERVAL);
        samples.set_missed_tick_behavior(MissedTickBehavior::Delay);
        loop {
            tokio::select! {
                _ = control.shutdown_notify.notified() => {
                    if control.is_shutdown_requested() {
                        return;
                    }
                }
                _ = samples.tick() => {
                    match tokio::task::spawn_blocking(collect_system_status_sample).await {
                        Ok(sample) => append_system_status_sample(&history_path, &sample),
                        Err(err) => warn!("system status collector stopped: {err}"),
                    }
                }
            }
        }
    });
}

fn start_agent_scope_metrics_collector(control: RuntimeControl) {
    tokio::spawn(async move {
        let mut samples = interval(AGENT_SCOPE_SAMPLE_INTERVAL);
        samples.set_missed_tick_behavior(MissedTickBehavior::Delay);
        loop {
            tokio::select! {
                _ = control.shutdown_notify.notified() => {
                    if control.is_shutdown_requested() {
                        return;
                    }
                }
                _ = samples.tick() => {
                    match tokio::task::spawn_blocking(collect_agent_scope_metrics).await {
                        Ok(metrics) => {
                            if let Ok(mut cached) = AGENT_SCOPE_METRICS.lock() {
                                *cached = metrics;
                            }
                        }
                        Err(err) => warn!("agent scope metrics collector stopped: {err}"),
                    }
                }
            }
        }
    });
}

fn collect_agent_scope_metrics() -> HashMap<String, AgentScopeMetrics> {
    let units = match StdCommand::new("systemctl")
        .args([
            "--user",
            "list-units",
            "--all",
            "--type=scope",
            "--no-legend",
            "--plain",
        ])
        .output()
    {
        Ok(output) if output.status.success() => String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter_map(|line| line.split_whitespace().next())
            .filter(|unit| unit.starts_with("nostr-codex-agent-") && unit.ends_with(".scope"))
            .map(str::to_string)
            .collect::<Vec<_>>(),
        _ => return HashMap::new(),
    };
    if units.is_empty() {
        return HashMap::new();
    }

    let output = match StdCommand::new("systemctl")
        .args(["--user", "show", "--property=Description,ActiveState,MemoryCurrent,CPUUsageNSec,TasksCurrent,ActiveEnterTimestampMonotonic"])
        .args(&units)
        .output()
    {
        Ok(output) if output.status.success() => String::from_utf8_lossy(&output.stdout).into_owned(),
        _ => return HashMap::new(),
    };
    let boot_time = linux_boot_time();
    output
        .split("\n\n")
        .filter_map(|unit| parse_agent_scope_metrics(unit, boot_time))
        .collect()
}

fn parse_agent_scope_metrics(
    unit: &str,
    boot_time: Option<i64>,
) -> Option<(String, AgentScopeMetrics)> {
    let values = unit
        .lines()
        .filter_map(|line| line.split_once('='))
        .collect::<HashMap<_, _>>();
    let session_id = opencode_session_from_description(values.get("Description")?)?;
    let started_at = values
        .get("ActiveEnterTimestampMonotonic")
        .and_then(|value| value.parse::<u64>().ok())
        .and_then(|micros| i64::try_from(micros / 1_000_000).ok())
        .zip(boot_time)
        .map(|(seconds, boot_time)| boot_time.saturating_add(seconds));
    Some((
        session_id.to_string(),
        AgentScopeMetrics {
            active_state: values
                .get("ActiveState")
                .copied()
                .unwrap_or_default()
                .to_string(),
            memory_bytes: values
                .get("MemoryCurrent")
                .and_then(|value| value.parse().ok()),
            cpu_usage_nsec: values
                .get("CPUUsageNSec")
                .and_then(|value| value.parse().ok()),
            task_count: values
                .get("TasksCurrent")
                .and_then(|value| value.parse().ok()),
            started_at,
        },
    ))
}

fn opencode_session_from_description(description: &str) -> Option<&str> {
    let mut words = description.split_whitespace();
    while let Some(word) = words.next() {
        if word == "--session" {
            return words.next().filter(|session| {
                session.starts_with("ses_")
                    && session.len() <= 128
                    && session[4..]
                        .bytes()
                        .all(|byte| byte.is_ascii_alphanumeric())
            });
        }
    }
    None
}

fn linux_boot_time() -> Option<i64> {
    fs::read_to_string("/proc/stat")
        .ok()?
        .lines()
        .find_map(|line| line.strip_prefix("btime "))?
        .parse()
        .ok()
}

async fn queue_workspace_update(
    workspace: &WorkspaceStore,
    recipients: impl IntoIterator<Item = String>,
    update: &WorkspaceUpdate,
) -> Result<()> {
    let payload = WireMessage::workspace_update(update.clone()).to_json()?;
    for recipient in recipients {
        workspace.queue_notification(&recipient, &payload)?;
    }
    Ok(())
}

async fn flush_workspace_notification_outbox(
    workspace: &WorkspaceStore,
    messenger: &NostrMessenger,
    outbound: &WorkspaceOutbound,
) {
    for notification in workspace.pending_notifications().unwrap_or_default() {
        let Ok(wire) = parse_wire_message(&notification.payload) else {
            warn!(
                id = notification.id,
                "discarding malformed workspace notification outbox entry"
            );
            let _ = workspace.delivered_notification(notification.id);
            continue;
        };
        let mut delivered = false;
        for attempt in 0..3 {
            match outbound
                .send(messenger, &notification.recipient, wire.clone())
                .await
            {
                Ok(_) => {
                    delivered = true;
                    break;
                }
                Err(err) if attempt == 2 => {
                    warn!(id = notification.id, recipient = %notification.recipient, "workspace notification remains pending: {err:#}")
                }
                Err(_) => sleep(Duration::from_millis(100 * (1 << attempt))).await,
            }
        }
        if delivered {
            let _ = workspace.delivered_notification(notification.id);
        } else {
            let _ = workspace.failed_notification_attempt(notification.id);
        }
    }
}

#[derive(Serialize)]
struct WorkspaceInvitePayload<'a> {
    v: u8,
    t: &'a str,
    target: WorkspaceInviteTarget<'a>,
}

#[derive(Serialize)]
struct WorkspaceInviteTarget<'a> {
    #[serde(rename = "type")]
    target_type: &'static str,
    version: u8,
    id: String,
    name: String,
    pubkey: &'a str,
    relays: &'a [String],
}

fn workspace_invite_code(
    secret: &str,
    pubkey: &str,
    relays: &[String],
    workdir: &Path,
) -> Result<String> {
    let payload = WorkspaceInvitePayload {
        v: 1,
        t: secret,
        target: WorkspaceInviteTarget {
            target_type: "nostr_codex_target",
            version: 1,
            id: format!("workspace-{}", &pubkey[..pubkey.len().min(16)]),
            name: worker_target_name(workdir),
            pubkey,
            relays,
        },
    };
    Ok(format!(
        "nci1.{}",
        URL_SAFE_NO_PAD.encode(serde_json::to_vec(&payload)?)
    ))
}

fn invite_creation_request(message: &IncomingMessage) -> Option<CreateInvite> {
    let raw = if message.kind == "create_invite" {
        &message.raw_json
    } else {
        &message.text
    };
    match parse_wire_message(raw).ok()? {
        WireMessage::CreateInvite { create_invite } => Some(create_invite),
        _ => None,
    }
}

fn invite_redemption_code(message: &IncomingMessage) -> Option<String> {
    redeem_invitation_from_json(&message.raw_json, 0)
}

fn redeem_invitation_from_json(raw: &str, depth: u8) -> Option<String> {
    if depth > 2 {
        return None;
    }
    let value = serde_json::from_str::<serde_json::Value>(raw).ok()?;
    let object = value.as_object()?;
    if let Some(redeem) = object.get("redeem_invite") {
        return serde_json::from_value::<RedeemInvite>(redeem.clone())
            .ok()
            .map(|redeem| redeem.code);
    }
    for field in ["query", "message"] {
        if let Some(value) = object.get(field).and_then(serde_json::Value::as_str) {
            if let Some(code) = redeem_invitation_from_json(value, depth + 1) {
                return Some(code);
            }
        }
    }
    None
}

fn workspace_request(message: &IncomingMessage) -> Option<WorkspaceRequest> {
    let raw = if message.kind == "workspace_request" {
        &message.raw_json
    } else {
        &message.text
    };
    match parse_wire_message(raw).ok()? {
        WireMessage::WorkspaceRequest { workspace_request } => Some(workspace_request),
        _ => None,
    }
}

fn workspace_voice_key(
    sender_pubkey: &str,
    request: &WorkspaceRequest,
) -> Option<WorkspaceVoiceKey> {
    if request.action != "transcribe_workspace_voice" {
        return None;
    }
    let attachment = request.attachments.first()?;
    attachment
        .media_type
        .starts_with("audio/")
        .then(|| WorkspaceVoiceKey {
            sender_pubkey: sender_pubkey.to_string(),
            sha256: attachment.sha256.to_ascii_lowercase(),
        })
}

fn legacy_message_replays_workspace_voice(
    message: &IncomingMessage,
    deduper: &WorkspaceVoiceDeduper,
) -> bool {
    let parsed = parse_wire_message(&message.raw_json)
        .ok()
        .or_else(|| parse_wire_message(&message.text).ok());
    let attachments = match parsed {
        Some(WireMessage::Audio { audio }) => vec![audio],
        Some(WireMessage::MediaBundle { media_bundle }) => media_bundle
            .attachments
            .into_iter()
            .map(|attachment| media_reference_to_audio(&attachment))
            .collect(),
        _ => return false,
    };

    !attachments.is_empty()
        && attachments
            .iter()
            .all(|attachment| attachment.media_type.starts_with("audio/"))
        && attachments.iter().all(|attachment| {
            deduper.contains(&WorkspaceVoiceKey {
                sender_pubkey: message.sender_pubkey_hex.clone(),
                sha256: attachment.sha256.to_ascii_lowercase(),
            })
        })
}

fn workspace_action_requires_admin(action: &str) -> bool {
    matches!(
        action,
        "create_agent"
            | "create_conversation_agent"
            | "rename_agent"
            | "restart_agent_session"
            | "abort_agent_task"
            | "update_agent_profile"
            | "delete_agent"
            | "add_conversation_agent"
            | "remove_conversation_agent"
    )
}

async fn process_workspace_request(
    workspace: &WorkspaceStore,
    messenger: &NostrMessenger,
    outbound: &WorkspaceOutbound,
    sender: &str,
    owner: Option<&str>,
    event_id: &str,
    request: WorkspaceRequest,
    codex_config: &CodexConfig,
    audio_config: &AudioConfig,
    transcribe_config: &TranscribeConfig,
    agent_queues: &mut WorkspaceAgentQueues,
    fips_capabilities: &Arc<Mutex<HashMap<String, (String, Instant)>>>,
) -> Result<()> {
    if workspace_action_requires_admin(&request.action)
        && owner != Some(sender)
        && !workspace.is_admin(sender)?
    {
        bail!("Only workspace admins can manage agents.");
    }
    if let Some(channel_id) = request.channel_id.as_deref() {
        if matches!(
            request.action.as_str(),
            "add_channel_member" | "remove_channel_member"
        ) {
            if !workspace.is_channel_admin(channel_id, sender)? {
                bail!("Only channel admins can manage channel members.");
            }
        } else if matches!(request.action.as_str(), "rename_channel" | "delete_channel") {
            if !workspace.is_channel_admin(channel_id, sender)? {
                bail!("Only channel admins can manage this conversation.");
            }
        } else if request.action != "create_channel"
            && !workspace.is_channel_member(channel_id, sender)?
        {
            bail!("You are not a member of this channel.");
        }
    }
    if request.action == "set_member_admin" && owner != Some(sender) {
        bail!("Only the workspace owner can manage member roles.");
    }
    if request.action == "remove_member" && owner != Some(sender) && !workspace.is_admin(sender)? {
        bail!("Only workspace owners and admins can remove members.");
    }
    let update = match request.action.as_str() {
        "typing" => {
            let expires_in = request.expires_in_seconds.unwrap_or(4).clamp(1, 30);
            let expires_at = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs() as i64
                + expires_in as i64;
            let update = WorkspaceUpdate {
                action: "typing".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![],
                messages: vec![],
                agents: vec![],
                conversation_agents: vec![],
                conversation_preprompts: vec![],
                typing: Some(WorkspaceTypingPayload {
                    sender_pubkey: sender.to_string(),
                    agent_id: None,
                    agent_name: None,
                    stage: None,
                    channel_id: request.channel_id.clone(),
                    recipient_pubkey: request.recipient_pubkey.clone(),
                    member_pubkey: None,
                    peer_pubkey: None,
                    parent_id: request.parent_id.clone(),
                    expires_at,
                }),
            };
            if request.channel_id.is_some() {
                for member in
                    workspace.channel_members(request.channel_id.as_deref().unwrap_or_default())?
                {
                    if member.pubkey != sender {
                        messenger
                            .send_ephemeral_wire_to(
                                PublicKey::parse(&member.pubkey)?,
                                WireMessage::workspace_update(update.clone()),
                                Duration::from_secs(expires_in),
                            )
                            .await?;
                    }
                }
            } else {
                let recipient = request.recipient_pubkey.as_deref().unwrap_or_default();
                messenger
                    .send_ephemeral_wire_to(
                        PublicKey::parse(recipient)?,
                        WireMessage::workspace_update(update),
                        Duration::from_secs(expires_in),
                    )
                    .await?;
            }
            return Ok(());
        }
        "list" => {
            if !request.fips_snapshot {
                send_workspace_snapshot(workspace, messenger, outbound, sender).await?;
                return Ok(());
            }
            let capability = issue_workspace_fips_capability(fips_capabilities, sender).await;
            // The capability upgrades this client to FIPS after the Nostr
            // bootstrap snapshot has made its workspace usable.
            messenger
                .send_wire_to_pubkey(
                    sender,
                    WireMessage::workspace_update(WorkspaceUpdate {
                        action: format!("fips_snapshot_offer:{capability}"),
                        revision: workspace.revision()?,
                        channels: vec![],
                        members: vec![],
                        messages: vec![],
                        agents: vec![],
                        conversation_agents: vec![],
                        conversation_preprompts: vec![],
                        typing: None,
                    }),
                )
                .await?;
            // Bootstrap the visible workspace through Nostr in the same
            // request. FIPS is an upgrade for live traffic, never a reason to
            // make a newly connected client wait for its initial state.
            send_workspace_snapshot(workspace, messenger, outbound, sender).await?;
            return Ok(());
        }
        "list_fallback" => {
            // This request follows a failed or disabled FIPS bootstrap. Remove
            // any stale route so its snapshot cannot be sent over FIPS again.
            outbound.fips_routes.lock().await.remove(sender);
            send_workspace_snapshot(workspace, messenger, outbound, sender).await?;
            return Ok(());
        }
        "fips_mesh" => {
            let peers: Vec<WorkspaceMemberPayload> = outbound
                .fips_routes
                .lock()
                .await
                .keys()
                .cloned()
                .map(|pubkey| WorkspaceMemberPayload {
                    pubkey,
                    display_name: String::new(),
                    is_admin: false,
                })
                .collect();
            info!(
                live_routes = peers.len(),
                requester = sender,
                "reporting FIPS topology"
            );
            outbound
                .send(
                    messenger,
                    sender,
                    WireMessage::workspace_update(WorkspaceUpdate {
                        action: "fips_mesh".to_string(),
                        revision: workspace.revision()?,
                        channels: vec![],
                        members: peers,
                        messages: vec![],
                        agents: vec![],
                        conversation_agents: vec![],
                        conversation_preprompts: vec![],
                        typing: None,
                    }),
                )
                .await?;
            return Ok(());
        }
        "fips_presence_offer" | "fips_presence_ready" => {
            let recipient = request.recipient_pubkey.as_deref().unwrap_or_default();
            if recipient.is_empty() || recipient == sender || !workspace.is_member(recipient)? {
                bail!("FIPS presence recipient is not a workspace member");
            }
            let routes = outbound.fips_routes.lock().await;
            if !routes.contains_key(sender) || !routes.contains_key(recipient) {
                return Ok(());
            }
            drop(routes);
            outbound
                .send(
                    messenger,
                    recipient,
                    WireMessage::workspace_update(WorkspaceUpdate {
                        action: request.action,
                        revision: workspace.revision()?,
                        channels: vec![],
                        members: vec![WorkspaceMemberPayload {
                            pubkey: sender.to_string(),
                            display_name: String::new(),
                            is_admin: false,
                        }],
                        messages: vec![],
                        agents: vec![],
                        conversation_agents: vec![],
                        conversation_preprompts: vec![],
                        typing: None,
                    }),
                )
                .await?;
            return Ok(());
        }
        "create_channel" => {
            let default_folder;
            let scope = if request.folder_scope.is_empty() {
                default_folder = canonical_worker_root_dir()?.to_string_lossy().into_owned();
                std::slice::from_ref(&default_folder)
            } else {
                &request.folder_scope
            };
            let folder_scope = canonical_conversation_folder_scope(scope, codex_config)?;
            let channel = workspace
                .create_channel(request.channel_name.as_deref().unwrap_or_default(), sender)?;
            workspace.set_conversation_preprompt(
                Some(&channel.id),
                None,
                None,
                request.body.as_deref().unwrap_or_default(),
                &folder_scope,
            )?;
            let update = WorkspaceUpdate {
                action: "channel_created".to_string(),
                revision: workspace.revision()?,
                channels: vec![channel_payload(workspace, channel)?],
                members: vec![],
                messages: vec![],
                agents: vec![],
                conversation_agents: vec![],
                conversation_preprompts: workspace
                    .conversation_preprompts()?
                    .into_iter()
                    .map(conversation_preprompt_payload)
                    .collect(),
                typing: None,
            };
            outbound
                .send(messenger, sender, WireMessage::workspace_update(update))
                .await?;
            return Ok(());
        }
        "rename_channel" => {
            let channel = workspace.rename_channel(
                request.channel_id.as_deref().unwrap_or_default(),
                request.channel_name.as_deref().unwrap_or_default(),
            )?;
            broadcast_workspace_update(
                workspace,
                messenger,
                outbound,
                &WorkspaceUpdate {
                    action: "channel_renamed".to_string(),
                    revision: workspace.revision()?,
                    channels: vec![channel_payload(workspace, channel)?],
                    members: vec![],
                    messages: vec![],
                    agents: vec![],
                    conversation_agents: vec![],
                    conversation_preprompts: vec![],
                    typing: None,
                },
            )
            .await?;
            return Ok(());
        }
        "delete_channel" => {
            workspace.delete_channel(request.channel_id.as_deref().unwrap_or_default())?;
            broadcast_workspace_snapshots(workspace, messenger, outbound).await?;
            return Ok(());
        }
        "add_channel_member" => {
            workspace.add_channel_member(
                request.channel_id.as_deref().unwrap_or_default(),
                request.member_pubkey.as_deref().unwrap_or_default(),
            )?;
            broadcast_workspace_snapshots(workspace, messenger, outbound).await?;
            return Ok(());
        }
        "remove_channel_member" => {
            workspace.remove_channel_member(
                request.channel_id.as_deref().unwrap_or_default(),
                request.member_pubkey.as_deref().unwrap_or_default(),
            )?;
            broadcast_workspace_snapshots(workspace, messenger, outbound).await?;
            return Ok(());
        }
        "delete_direct_conversation" => {
            workspace.delete_direct_conversation(
                sender,
                request.recipient_pubkey.as_deref().unwrap_or_default(),
            )?;
            broadcast_workspace_snapshots(workspace, messenger, outbound).await?;
            return Ok(());
        }
        "set_profile" => {
            let member = workspace.set_member_display_name(
                sender,
                request.display_name.as_deref().unwrap_or_default(),
            )?;
            let update = WorkspaceUpdate {
                action: "profile_updated".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![member_payload(member)],
                messages: vec![],
                agents: vec![],
                conversation_agents: vec![],
                conversation_preprompts: vec![],
                typing: None,
            };
            broadcast_workspace_update(workspace, messenger, outbound, &update).await?;
            return Ok(());
        }
        "set_conversation_preprompt" => {
            let channel_id = request.channel_id.as_deref();
            let recipient = request.recipient_pubkey.as_deref();
            workspace.set_conversation_preprompt(
                channel_id,
                channel_id.is_none().then_some(sender),
                recipient,
                request.body.as_deref().unwrap_or_default(),
                &canonical_conversation_folder_scope_or_empty(&request.folder_scope, codex_config)?,
            )?;
            let update = WorkspaceUpdate {
                action: "conversation_preprompt_updated".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![],
                messages: vec![],
                agents: vec![],
                conversation_agents: vec![],
                conversation_preprompts: workspace
                    .conversation_preprompts()?
                    .into_iter()
                    .map(conversation_preprompt_payload)
                    .collect(),
                typing: None,
            };
            broadcast_workspace_update(workspace, messenger, outbound, &update).await?;
            return Ok(());
        }
        "list_channel_messages" => {
            send_channel_history(
                workspace,
                messenger,
                sender,
                request.channel_id.as_deref().unwrap_or_default(),
            )
            .await?;
            return Ok(());
        }
        "list_direct_messages" => WorkspaceUpdate {
            action: "direct_messages".to_string(),
            revision: workspace.revision()?,
            channels: vec![],
            members: vec![],
            messages: workspace
                .direct_messages(
                    sender,
                    request.recipient_pubkey.as_deref().unwrap_or_default(),
                )?
                .into_iter()
                .map(message_payload)
                .collect(),
            agents: vec![],
            conversation_agents: workspace
                .conversation_agents()?
                .into_iter()
                .filter(|membership| {
                    direct_membership_matches(
                        membership,
                        sender,
                        request.recipient_pubkey.as_deref().unwrap_or_default(),
                    )
                })
                .map(conversation_agent_payload)
                .collect(),
            conversation_preprompts: workspace
                .conversation_preprompts()?
                .into_iter()
                .filter(|preprompt| {
                    direct_preprompt_matches(
                        preprompt,
                        sender,
                        request.recipient_pubkey.as_deref().unwrap_or_default(),
                    )
                })
                .map(conversation_preprompt_payload)
                .collect(),
            typing: None,
        },
        "transcribe_workspace_voice" => {
            let attachment = request
                .attachments
                .first()
                .ok_or_else(|| anyhow!("voice transcription requires an audio attachment"))?;
            if !attachment.media_type.starts_with("audio/") {
                bail!("voice transcription requires an audio attachment");
            }
            let audio = media_reference_to_audio(attachment);
            let downloaded = download_blossom_audio(&audio, audio_config).await?;
            let transcript = transcribe_audio(&downloaded.path, transcribe_config).await?;
            messenger
                .send_transcript_for_event_to(
                    sender,
                    transcript,
                    event_id.to_string(),
                    codex_config.working_dir.to_string_lossy().to_string(),
                )
                .await?;
            return Ok(());
        }
        "send_channel_message" => {
            let message = workspace.add_channel_message_with_main_and_id(
                sender,
                request.channel_id.as_deref().unwrap_or_default(),
                request.body.as_deref().unwrap_or_default(),
                &request.attachments,
                &request.mentions,
                request.parent_id.as_deref(),
                request.also_send_to_main,
                request.message_id.as_deref(),
            )?;
            let message_id = message.id.clone();
            let update = WorkspaceUpdate {
                action: "message_created".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![],
                messages: vec![message_payload(message)],
                agents: vec![],
                conversation_agents: vec![],
                conversation_preprompts: vec![],
                typing: None,
            };
            queue_workspace_update(
                workspace,
                workspace
                    .channel_members(request.channel_id.as_deref().unwrap_or_default())?
                    .into_iter()
                    .map(|member| member.pubkey),
                &update,
            )
            .await?;
            flush_workspace_notification_outbox(workspace, messenger, outbound).await;
            enqueue_conversation_agents(
                workspace,
                agent_queues,
                Some(request.channel_id.as_deref().unwrap_or_default()),
                None,
                None,
                &request.mentions,
                &message_id,
            )?;
            return Ok(());
        }
        "send_direct_message" => {
            let message = workspace.add_direct_message_with_main_and_id(
                sender,
                request.recipient_pubkey.as_deref().unwrap_or_default(),
                request.body.as_deref().unwrap_or_default(),
                &request.attachments,
                &request.mentions,
                request.parent_id.as_deref(),
                request.also_send_to_main,
                request.message_id.as_deref(),
            )?;
            let message_id = message.id.clone();
            let update = WorkspaceUpdate {
                action: "message_created".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![],
                messages: vec![message_payload(message)],
                agents: vec![],
                conversation_agents: vec![],
                conversation_preprompts: vec![],
                typing: None,
            };
            // A direct message is only delivered to its two participants.
            queue_workspace_update(
                workspace,
                [
                    sender.to_string(),
                    request
                        .recipient_pubkey
                        .as_deref()
                        .unwrap_or_default()
                        .to_string(),
                ],
                &update,
            )
            .await?;
            flush_workspace_notification_outbox(workspace, messenger, outbound).await;
            enqueue_conversation_agents(
                workspace,
                agent_queues,
                None,
                Some(sender),
                request.recipient_pubkey.as_deref(),
                &request.mentions,
                &message_id,
            )?;
            return Ok(());
        }
        "call_invite" | "call_answer" | "call_hangup" => {
            let call_id = request.call_id.as_deref().unwrap_or_default();
            let wire = match request.action.as_str() {
                "call_invite" => WireMessage::call_invite_from(call_id, sender),
                "call_answer" => WireMessage::call_answer_from(call_id, sender),
                _ => WireMessage::call_hangup_from(call_id, sender),
            };
            messenger
                .send_wire_to_pubkey(
                    request.recipient_pubkey.as_deref().unwrap_or_default(),
                    wire,
                )
                .await?;
            return Ok(());
        }
        "group_call_invite" | "group_call_answer" | "group_call_hangup" => {
            let channel_id = request.channel_id.as_deref().unwrap_or_default();
            let call_id = request.call_id.as_deref().unwrap_or_default();
            let participants = &request.participant_pubkeys;
            if !participants.iter().any(|participant| participant == sender)
                || participants.iter().any(|participant| {
                    !workspace
                        .is_channel_member(channel_id, participant)
                        .unwrap_or(false)
                })
            {
                bail!("group call participants must be channel members and include the sender");
            }
            for recipient in participants
                .iter()
                .filter(|participant| participant.as_str() != sender)
            {
                let wire = match request.action.as_str() {
                    "group_call_invite" => WireMessage::group_call_invite_from(
                        call_id,
                        channel_id,
                        participants.clone(),
                        sender,
                    ),
                    "group_call_answer" => WireMessage::group_call_answer_from(
                        call_id,
                        channel_id,
                        participants.clone(),
                        sender,
                    ),
                    _ => WireMessage::group_call_hangup_from(
                        call_id,
                        channel_id,
                        participants.clone(),
                        sender,
                    ),
                };
                messenger.send_wire_to_pubkey(recipient, wire).await?;
            }
            return Ok(());
        }
        "toggle_reaction" => {
            let message = workspace.toggle_reaction(
                sender,
                request.parent_id.as_deref().unwrap_or_default(),
                request.reaction.as_deref().unwrap_or_default(),
            )?;
            let update = WorkspaceUpdate {
                action: "message_updated".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![],
                messages: vec![message_payload(message)],
                agents: vec![],
                conversation_agents: vec![],
                conversation_preprompts: vec![],
                typing: None,
            };
            if update.messages[0].channel_id.is_some() {
                for member in workspace
                    .channel_members(update.messages[0].channel_id.as_deref().unwrap_or_default())?
                {
                    outbound
                        .send(
                            messenger,
                            &member.pubkey,
                            WireMessage::workspace_update(update.clone()),
                        )
                        .await?;
                }
            } else {
                for member in [
                    sender,
                    update.messages[0]
                        .recipient_pubkey
                        .as_deref()
                        .unwrap_or_default(),
                ] {
                    outbound
                        .send(
                            messenger,
                            member,
                            WireMessage::workspace_update(update.clone()),
                        )
                        .await?;
                }
            }
            return Ok(());
        }
        "toggle_pin" => {
            let message =
                workspace.toggle_pin(sender, request.parent_id.as_deref().unwrap_or_default())?;
            let update = WorkspaceUpdate {
                action: "message_updated".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![],
                messages: vec![message_payload(message)],
                agents: vec![],
                conversation_agents: vec![],
                conversation_preprompts: vec![],
                typing: None,
            };
            if update.messages[0].channel_id.is_some() {
                for member in workspace
                    .channel_members(update.messages[0].channel_id.as_deref().unwrap_or_default())?
                {
                    outbound
                        .send(
                            messenger,
                            &member.pubkey,
                            WireMessage::workspace_update(update.clone()),
                        )
                        .await?;
                }
            } else {
                for member in [
                    sender,
                    update.messages[0]
                        .recipient_pubkey
                        .as_deref()
                        .unwrap_or_default(),
                ] {
                    outbound
                        .send(
                            messenger,
                            member,
                            WireMessage::workspace_update(update.clone()),
                        )
                        .await?;
                }
            }
            return Ok(());
        }
        "list_agents" => {
            let sessions = list_opencode_sessions(codex_config)
                .await
                .unwrap_or_default();
            WorkspaceUpdate {
                action: "agents".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![],
                messages: vec![],
                agents: workspace
                    .agents()?
                    .into_iter()
                    .map(|agent| {
                        agent_payload(resolve_agent_runtime(agent, &sessions, codex_config))
                    })
                    .collect(),
                conversation_agents: workspace
                    .conversation_agents()?
                    .into_iter()
                    .map(conversation_agent_payload)
                    .collect(),
                conversation_preprompts: workspace
                    .conversation_preprompts()?
                    .into_iter()
                    .map(conversation_preprompt_payload)
                    .collect(),
                typing: None,
            }
        }
        "create_agent" | "create_conversation_agent" => {
            let conversation_scoped = request.action == "create_conversation_agent";
            let mut profile = workspace_agent_profile_from_request(&request, codex_config)?;
            let folder_scope = conversation_scoped
                .then(|| {
                    if request.folder_scope.is_empty() {
                        // The custom-agent dialog's "Worker default" option
                        // intentionally omits a scope, just like presets.
                        let default_scope = workspace.conversation_folder_scope(
                            request.channel_id.as_deref(),
                            request.channel_id.is_none().then_some(sender),
                            request.recipient_pubkey.as_deref(),
                        )?;
                        let default_folder;
                        let scope = if default_scope.is_empty() {
                            default_folder =
                                canonical_worker_root_dir()?.to_string_lossy().into_owned();
                            std::slice::from_ref(&default_folder)
                        } else {
                            &default_scope
                        };
                        canonical_conversation_folder_scope(scope, codex_config)
                    } else {
                        canonical_conversation_folder_scope(&request.folder_scope, codex_config)
                    }
                })
                .transpose()?;
            // Conversation-created agents never retain a global workdir. Their
            // membership folder is the directory used for session provisioning.
            if conversation_scoped {
                profile.workdir = None;
            }
            let mut agent_config = codex_config_for_workspace_agent(codex_config, &profile)?;
            if let Some(folder) = folder_scope.as_ref().and_then(|scope| scope.first()) {
                agent_config.working_dir = PathBuf::from(folder);
            }
            let (session_id, session_status, session_error) =
                provision_workspace_agent_session(&agent_config).await;
            let agent = workspace.create_agent_with_profile(
                request.agent_name.as_deref().unwrap_or_default(),
                request.agent_role.as_deref().unwrap_or_default(),
                request.agent_traits.as_deref().unwrap_or_default(),
                &request.agent_skills,
                request.agent_preset.as_deref(),
                profile,
                session_id.as_deref(),
                &session_status,
                session_error.as_deref(),
                sender,
            )?;
            if let Some(folder_scope) = folder_scope {
                let channel_id = request.channel_id.as_deref();
                workspace.add_conversation_agent(
                    &agent.id,
                    channel_id,
                    channel_id.is_none().then_some(sender),
                    request.recipient_pubkey.as_deref(),
                    &folder_scope,
                )?;
            }
            let update = WorkspaceUpdate {
                action: "agent_created".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![],
                messages: vec![],
                agents: vec![agent_payload(agent)],
                conversation_agents: if conversation_scoped {
                    workspace
                        .conversation_agents()?
                        .into_iter()
                        .map(conversation_agent_payload)
                        .collect()
                } else {
                    vec![]
                },
                conversation_preprompts: vec![],
                typing: None,
            };
            broadcast_workspace_update(workspace, messenger, outbound, &update).await?;
            return Ok(());
        }
        "set_member_admin" => {
            let member = workspace.set_member_admin(
                request.member_pubkey.as_deref().unwrap_or_default(),
                request.member_is_admin,
            )?;
            let update = WorkspaceUpdate {
                action: "member_role_updated".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![member_payload(member)],
                messages: vec![],
                agents: vec![],
                conversation_agents: vec![],
                conversation_preprompts: vec![],
                typing: None,
            };
            broadcast_workspace_update(workspace, messenger, outbound, &update).await?;
            return Ok(());
        }
        "remove_member" => {
            let member = request.member_pubkey.as_deref().unwrap_or_default();
            if owner == Some(member) {
                bail!("The workspace owner cannot be removed.");
            }
            workspace.remove_member(member)?;
            outbound.fips_routes.lock().await.remove(member);
            fips_capabilities
                .lock()
                .await
                .retain(|_, (capability_member, _)| capability_member.as_str() != member);
            let update = WorkspaceUpdate {
                action: "member_removed".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: workspace
                    .members()?
                    .into_iter()
                    .map(member_payload)
                    .collect(),
                messages: vec![],
                agents: vec![],
                conversation_agents: vec![],
                conversation_preprompts: vec![],
                typing: None,
            };
            broadcast_workspace_update(workspace, messenger, outbound, &update).await?;
            return Ok(());
        }
        "rename_agent" => {
            let agent = workspace.rename_agent(
                request.agent_id.as_deref().unwrap_or_default(),
                request.agent_name.as_deref().unwrap_or_default(),
            )?;
            let update = WorkspaceUpdate {
                action: "agent_renamed".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![],
                messages: vec![],
                agents: vec![agent_payload(agent)],
                conversation_agents: vec![],
                conversation_preprompts: vec![],
                typing: None,
            };
            broadcast_workspace_update(workspace, messenger, outbound, &update).await?;
            return Ok(());
        }
        "restart_agent_session" => {
            let agent_id = request.agent_id.as_deref().unwrap_or_default();
            let agent = workspace
                .agents()?
                .into_iter()
                .find(|agent| agent.id == agent_id)
                .ok_or_else(|| anyhow::anyhow!("agent does not exist"))?;
            let agent_config = codex_config_for_workspace_agent_record(codex_config, &agent)?;
            let (session_id, session_status, session_error) =
                provision_workspace_agent_session(&agent_config).await;
            let agent = workspace.update_agent_session(
                &agent.id,
                session_id.as_deref(),
                &session_status,
                session_error.as_deref(),
            )?;
            let update = WorkspaceUpdate {
                action: "agent_session_restarted".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![],
                messages: vec![],
                agents: vec![agent_payload(agent)],
                conversation_agents: vec![],
                conversation_preprompts: vec![],
                typing: None,
            };
            broadcast_workspace_update(workspace, messenger, outbound, &update).await?;
            return Ok(());
        }
        "abort_agent_task" => {
            let agent_id = request.agent_id.as_deref().unwrap_or_default();
            let _agent = workspace
                .agents()?
                .into_iter()
                .find(|agent| agent.id == agent_id)
                .ok_or_else(|| anyhow::anyhow!("agent does not exist"))?;
            if let Some(cancel_token) = agent_queues
                .active_turns
                .lock()
                .await
                .get(agent_id)
                .cloned()
            {
                cancel_token.cancel();
            }
            return Ok(());
        }
        "update_agent_profile" => {
            let agent_id = request.agent_id.as_deref().unwrap_or_default();
            let profile = workspace_agent_profile_from_request(&request, codex_config)?;
            let agent_config = codex_config_for_workspace_agent(codex_config, &profile)?;
            let (session_id, session_status, session_error) =
                provision_workspace_agent_session(&agent_config).await;
            let agent = workspace.update_agent_profile_and_session(
                agent_id,
                profile,
                session_id.as_deref(),
                &session_status,
                session_error.as_deref(),
            )?;
            let update = WorkspaceUpdate {
                action: "agent_profile_updated".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![],
                messages: vec![],
                agents: vec![agent_payload(agent)],
                conversation_agents: vec![],
                conversation_preprompts: vec![],
                typing: None,
            };
            broadcast_workspace_update(workspace, messenger, outbound, &update).await?;
            return Ok(());
        }
        "delete_agent" => {
            workspace.delete_agent(request.agent_id.as_deref().unwrap_or_default())?;
            let update = WorkspaceUpdate {
                action: "agent_deleted".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![],
                messages: vec![],
                agents: workspace.agents()?.into_iter().map(agent_payload).collect(),
                conversation_agents: workspace
                    .conversation_agents()?
                    .into_iter()
                    .map(conversation_agent_payload)
                    .collect(),
                conversation_preprompts: workspace
                    .conversation_preprompts()?
                    .into_iter()
                    .map(conversation_preprompt_payload)
                    .collect(),
                typing: None,
            };
            broadcast_workspace_update(workspace, messenger, outbound, &update).await?;
            return Ok(());
        }
        "add_conversation_agent" | "remove_conversation_agent" => {
            let channel_id = request.channel_id.as_deref();
            let recipient = request.recipient_pubkey.as_deref();
            if request.action == "add_conversation_agent" {
                workspace.add_conversation_agent(
                    request.agent_id.as_deref().unwrap_or_default(),
                    channel_id,
                    channel_id.is_none().then_some(sender),
                    recipient,
                    &canonical_conversation_folder_scope(&request.folder_scope, codex_config)?,
                )?;
            } else {
                workspace.remove_conversation_agent(
                    request.agent_id.as_deref().unwrap_or_default(),
                    channel_id,
                    channel_id.is_none().then_some(sender),
                    recipient,
                )?;
            }
            let update = WorkspaceUpdate {
                action: "conversation_agents_updated".to_string(),
                revision: workspace.revision()?,
                channels: vec![],
                members: vec![],
                messages: vec![],
                agents: vec![],
                conversation_agents: workspace
                    .conversation_agents()?
                    .into_iter()
                    .map(conversation_agent_payload)
                    .collect(),
                conversation_preprompts: workspace
                    .conversation_preprompts()?
                    .into_iter()
                    .map(conversation_preprompt_payload)
                    .collect(),
                typing: None,
            };
            broadcast_workspace_update(workspace, messenger, outbound, &update).await?;
            return Ok(());
        }
        _ => bail!("unsupported workspace request"),
    };
    outbound
        .send(messenger, sender, WireMessage::workspace_update(update))
        .await?;
    Ok(())
}

async fn send_workspace_snapshot(
    workspace: &WorkspaceStore,
    messenger: &NostrMessenger,
    outbound: &WorkspaceOutbound,
    sender: &str,
) -> Result<()> {
    let snapshot = workspace_snapshot(workspace, sender)?;
    let transfer_id = generate_pairing_secret();
    let chunks = nostr_workspace_snapshot_chunks(&snapshot, &transfer_id)?;
    info!(
        channels = snapshot.channels.len(),
        members = snapshot.members.len(),
        messages = snapshot.messages.len(),
        agents = snapshot.agents.len(),
        chunks = chunks.len(),
        "sending chunked workspace snapshot"
    );
    for update in chunks {
        outbound
            .send(messenger, sender, WireMessage::workspace_update(update))
            .await?;
    }
    Ok(())
}

async fn issue_workspace_fips_capability(
    capabilities: &Arc<Mutex<HashMap<String, (String, Instant)>>>,
    member: &str,
) -> String {
    let mut bytes = [0u8; WORKSPACE_FIPS_CAPABILITY_BYTES];
    OsRng.fill_bytes(&mut bytes);
    let capability = URL_SAFE_NO_PAD.encode(bytes);
    let mut capabilities = capabilities.lock().await;
    let now = Instant::now();
    capabilities.retain(|_, (_, expires_at)| *expires_at > now);
    capabilities.insert(
        capability.clone(),
        (member.to_string(), now + WORKSPACE_FIPS_CAPABILITY_TTL),
    );
    capability
}

async fn run_workspace_fips_acceptor(
    secret_key: String,
    relays: Vec<String>,
    capabilities: Arc<Mutex<HashMap<String, (String, Instant)>>>,
    workspace_path: PathBuf,
    incoming: mpsc::Sender<IncomingMessage>,
    routes: Arc<Mutex<HashMap<String, String>>>,
    mut outgoing: mpsc::Receiver<WorkspaceFipsOutbound>,
) {
    let mut client = match build_workspace_fips_client(&secret_key, &relays).await {
        Ok(client) => client,
        Err(error) => {
            error!("cannot start shared FIPS workspace transport: {error:#}");
            return;
        }
    };
    let workspace = match WorkspaceStore::open(&workspace_path) {
        Ok(workspace) => workspace,
        Err(error) => {
            error!("cannot open FIPS workspace database: {error:#}");
            let _ = client.stop().await;
            return;
        }
    };
    let mut assemblers = HashMap::new();
    let mut peers = HashMap::<String, WorkspaceFipsPeer>::new();
    let mut frame_id = 0u64;
    let mut heartbeat = interval(WORKSPACE_FIPS_HEARTBEAT_INTERVAL);
    loop {
        tokio::select! {
            packet = client.recv_service_packet() => {
                let Some(packet) = packet else {
                    error!("shared FIPS workspace service transport closed");
                    return;
                };
                if packet.src_port != WORKSPACE_FIPS_SERVICE_PORT || packet.dst_port != WORKSPACE_FIPS_SERVICE_PORT {
                    continue;
                }
                let source = packet.src_addr.to_string();
                if !assemblers.contains_key(&source)
                    && assemblers.len() >= WORKSPACE_FIPS_ASSEMBLER_CAPACITY
                {
                    warn!("dropped FIPS workspace frame because the assembler registry is full");
                    continue;
                }
                let frame = match assemblers.entry(source.clone()).or_insert_with(FipsApplicationFrameAssembler::default).push(&packet.payload) {
                    Ok(Some(frame)) => frame,
                    Ok(None) => continue,
                    Err(error) => {
                        warn!("rejected invalid FIPS workspace frame: {error:#}");
                        assemblers.remove(&source);
                        continue;
                    }
                };
                if let Some(peer) = peers.get_mut(&source) {
                    if let Ok(envelope) = FipsApplicationEnvelope::decode(&frame) {
                        if envelope.version != WORKSPACE_FIPS_PROTOCOL_VERSION {
                            continue;
                        }
                        match envelope.kind.as_str() {
                        "pong" => peer.last_pong = Instant::now(),
                        "ping" => {
                            peer.last_pong = Instant::now();
                            if let Err(error) = send_workspace_fips_envelope(
                                &client,
                                &peer.npub,
                                &mut frame_id,
                                "pong",
                                None,
                            )
                            .await
                            {
                                warn!(member = %peer.member, "failed to answer FIPS workspace heartbeat: {error:#}");
                            }
                        }
                        "app" => {
                            let Some(message_id) = envelope.message_id else {
                                warn!(member = %peer.member, "rejected FIPS app envelope without a message id");
                                continue;
                            };
                            if message_id <= peer.last_message_id {
                                warn!(member = %peer.member, message_id, "rejected replayed FIPS app envelope");
                                continue;
                            }
                            let Some(frame) = envelope.frame else {
                                warn!(member = %peer.member, "rejected FIPS app envelope without a wire message");
                                continue;
                            };
                            if parse_wire_message(&frame).is_err() {
                                warn!(member = %peer.member, "rejected invalid FIPS wire message");
                                continue;
                            }
                            peer.last_message_id = message_id;
                            // Turn an authenticated FIPS payload back into the
                            // same shape as a decrypted Nostr DM. Dispatch and
                            // authorization must not depend on its transport.
                            let wire = match parse_wire_message(&frame) {
                                Ok(wire) => wire,
                                Err(_) => unreachable!("validated above"),
                            };
                            let message = IncomingMessage {
                                sender_pubkey: peer.npub.clone(),
                                sender_pubkey_hex: peer.member.clone(),
                                kind: wire.kind().to_string(),
                                text: wire.text().to_string(),
                                raw_json: frame,
                                // App IDs restart when a client restarts. Scope
                                // them to this accepted capability connection so
                                // durable request de-duplication does not drop
                                // the first request after reconnect.
                                event_id: format!(
                                    "fips:{}:{}:{message_id}",
                                    peer.member, peer.connection_id
                                ),
                            };
                            if incoming.try_send(message).is_err() {
                                warn!(member = %peer.member, "dropped FIPS app envelope because worker dispatch queue is full");
                            }
                        }
                            _ => warn!(member = %peer.member, kind = %envelope.kind, "rejected unexpected FIPS workspace peer envelope"),
                        }
                        continue;
                    }
                }
                let member = match String::from_utf8(frame) {
                    Ok(capability) => {
                        let mut capabilities = capabilities.lock().await;
                        let now = Instant::now();
                        capabilities.retain(|_, (_, expires_at)| *expires_at > now);
                        capabilities.remove(&capability).map(|(member, _)| member)
                    }
                    Err(_) => None,
                };
                let Some(member) = member else {
                    warn!("rejected FIPS workspace peer without a valid capability");
                    continue;
                };
                if !peers.contains_key(&source) && peers.len() >= WORKSPACE_FIPS_ROUTE_CAPACITY {
                    warn!(member, "rejected FIPS workspace peer because the route registry is full");
                    continue;
                }
                if !workspace.is_member(&member).unwrap_or(false) {
                    warn!(member, "rejected FIPS workspace capability for non-member");
                    continue;
                }
                let peer_npub = match PublicKey::parse(&member) {
                    Ok(key) => match key.to_bech32() {
                        Ok(npub) => npub,
                        Err(error) => {
                            warn!(member, "cannot derive FIPS workspace peer identity: {error:#}");
                            continue;
                        }
                    },
                    Err(error) => {
                        warn!(member, "cannot parse FIPS workspace peer identity: {error:#}");
                        continue;
                    }
                };
                let previous_sources = peers
                    .iter()
                    .filter_map(|(source, peer)| (peer.member == member).then_some(source.clone()))
                    .collect::<Vec<_>>();
                for previous_source in previous_sources {
                    peers.remove(&previous_source);
                    assemblers.remove(&previous_source);
                }
                routes.lock().await.remove(&member);
                peers.insert(source.clone(), WorkspaceFipsPeer {
                    member: member.clone(),
                    npub: peer_npub.clone(),
                    connection_id: generate_pairing_secret(),
                    last_pong: Instant::now(),
                    last_message_id: 0,
                    next_message_id: 0,
                });
                info!(
                    member,
                    peer_npub,
                    direct_peers = peers.len(),
                    "FIPS workspace peer connected"
                );
                if let Err(error) = send_workspace_fips_envelope(&client, &peer_npub, &mut frame_id, "hello", None).await {
                    warn!(member, "failed to send FIPS workspace hello: {error:#}");
                    continue;
                }
                match workspace_snapshot_frames(&workspace, &member) {
                    Ok(frames) => {
                        info!(member, frames = frames.len(), "sending workspace snapshot over shared FIPS transport");
                        for update in frames {
                            let frame = match WireMessage::workspace_update(update).to_json() {
                                Ok(frame) => frame,
                                Err(error) => {
                                    warn!(member, "cannot encode FIPS workspace snapshot frame: {error:#}");
                                    break;
                                }
                            };
                            let peer = peers.get_mut(&source).expect("peer was just inserted");
                            if let Err(error) = send_workspace_fips_app(
                                &client,
                                &peer.npub,
                                &mut frame_id,
                                &mut peer.next_message_id,
                                frame,
                            ).await {
                                warn!(member, "failed to send FIPS workspace snapshot frame: {error:#}");
                                break;
                            }
                        }
                    }
                    Err(error) => warn!(member, "cannot build FIPS workspace snapshot: {error:#}"),
                }
                routes.lock().await.insert(member, peer_npub);
            }
            outbound = outgoing.recv() => {
                let Some(outbound) = outbound else {
                    error!("shared FIPS workspace outbound queue closed");
                    return;
                };
                let result = match peers.values_mut().find(|peer| peer.member == outbound.member) {
                    Some(peer) => match outbound.wire.to_json() {
                        Ok(frame) => send_workspace_fips_app(
                            &client,
                            &peer.npub,
                            &mut frame_id,
                            &mut peer.next_message_id,
                            frame,
                        ).await,
                        Err(error) => Err(error.into()),
                    },
                    None => Err(anyhow!("FIPS workspace peer is disconnected")),
                };
                if let Err(error) = &result {
                    warn!(member = %outbound.member, "failed to send workspace FIPS outbound message: {error:#}");
                    // The next outbox attempt must use Nostr, not queue another
                    // packet for the peer that just proved unavailable.
                    routes.lock().await.remove(&outbound.member);
                }
                let _ = outbound.delivered.send(result);
            }
            _ = heartbeat.tick() => {
                // A reconnect restarts application frame IDs from one. Remove
                // the source assembler with an expired peer so its first
                // capability frame is not mistaken for a replay.
                let stale_sources = peers
                    .iter()
                    .filter_map(|(source, peer)| {
                        (peer.last_pong.elapsed()
                            >= WORKSPACE_FIPS_HEARTBEAT_INTERVAL
                                + WORKSPACE_FIPS_HEARTBEAT_TIMEOUT)
                            .then_some(source.clone())
                    })
                    .collect::<Vec<_>>();
                for source in stale_sources {
                    if let Some(peer) = peers.remove(&source) {
                        info!(
                            member = %peer.member,
                            peer_npub = %peer.npub,
                            direct_peers = peers.len(),
                            "expired FIPS workspace peer route"
                        );
                    }
                    assemblers.remove(&source);
                }
                let live_npubs = peers
                    .values()
                    .map(|peer| (peer.member.clone(), peer.npub.clone()))
                    .collect::<HashMap<_, _>>();
                routes.lock().await.retain(|member, npub| {
                    live_npubs.get(member).is_some_and(|live| live == npub)
                });
                for peer in peers.values() {
                    if let Err(error) = send_workspace_fips_envelope(&client, &peer.npub, &mut frame_id, "ping", None).await {
                        warn!(peer_npub = %peer.npub, "failed to send FIPS workspace heartbeat: {error:#}");
                    }
                }
            }
        }
    }
}

async fn build_workspace_fips_client(
    secret_key: &str,
    relays: &[String],
) -> Result<FipsMobileClient> {
    FipsClientConfig {
        secret_key: secret_key.to_string(),
        relays: relays.to_vec(),
        stun_servers: vec![
            "stun:45.77.228.152:3478".to_string(),
            "stun:stun.l.google.com:19302".to_string(),
            "stun:stun.cloudflare.com:3478".to_string(),
            "stun:global.stun.twilio.com:3478".to_string(),
        ],
    }
    .application_client(WORKSPACE_FIPS_SERVICE_PORT, 256)
    .await
}

async fn send_workspace_fips_envelope(
    client: &FipsMobileClient,
    peer_npub: &str,
    frame_id: &mut u64,
    kind: &str,
    frame: Option<String>,
) -> Result<()> {
    let envelope = FipsApplicationEnvelope::control(kind, frame);
    *frame_id = frame_id.wrapping_add(1);
    for packet in fips_application_service_frames(*frame_id, &envelope.encode()?)? {
        client
            .send_service_frame_to_npub(
                peer_npub,
                WORKSPACE_FIPS_SERVICE_PORT,
                WORKSPACE_FIPS_SERVICE_PORT,
                packet,
                Duration::from_secs(5),
            )
            .await?;
    }
    Ok(())
}

/// Application frames always carry a monotonically increasing ID. The mobile
/// client can therefore reject retransmits before they reach workspace state.
async fn send_workspace_fips_app(
    client: &FipsMobileClient,
    peer_npub: &str,
    frame_id: &mut u64,
    message_id: &mut u64,
    frame: String,
) -> Result<()> {
    *message_id = message_id.wrapping_add(1);
    if *message_id == 0 {
        *message_id = 1;
    }
    let envelope = FipsApplicationEnvelope::app(*message_id, frame)?;
    *frame_id = frame_id.wrapping_add(1);
    for packet in fips_application_service_frames(*frame_id, &envelope.encode()?)? {
        client
            .send_service_frame_to_npub(
                peer_npub,
                WORKSPACE_FIPS_SERVICE_PORT,
                WORKSPACE_FIPS_SERVICE_PORT,
                packet,
                Duration::from_secs(5),
            )
            .await?;
    }
    Ok(())
}

fn workspace_snapshot_frames(
    workspace: &WorkspaceStore,
    sender: &str,
) -> Result<Vec<WorkspaceUpdate>> {
    let mut snapshot = workspace_snapshot(workspace, sender)?;
    let revision = snapshot.revision;
    let messages = std::mem::take(&mut snapshot.messages);
    let transfer_id = generate_pairing_secret();
    let total_chunks = messages.chunks(WORKSPACE_FIPS_TRANSFER_CHUNK_SIZE).len() + 1;
    snapshot.action = history_transfer_action(&transfer_id, 0, total_chunks, "snapshot");
    let mut frames = vec![snapshot];
    for (index, messages) in messages
        .chunks(WORKSPACE_FIPS_TRANSFER_CHUNK_SIZE)
        .enumerate()
    {
        frames.push(WorkspaceUpdate {
            action: history_transfer_action(
                &transfer_id,
                index + 1,
                total_chunks,
                "snapshot_messages",
            ),
            revision,
            channels: vec![],
            members: vec![],
            messages: messages.to_vec(),
            agents: vec![],
            conversation_agents: vec![],
            conversation_preprompts: vec![],
            typing: None,
        });
    }
    Ok(frames)
}

async fn send_channel_history(
    workspace: &WorkspaceStore,
    messenger: &NostrMessenger,
    sender: &str,
    channel_id: &str,
) -> Result<()> {
    let messages = workspace
        .channel_messages(channel_id)?
        .into_iter()
        .map(message_payload)
        .collect::<Vec<_>>();
    let revision = workspace.revision()?;
    let transfer_id = generate_pairing_secret();
    let message_chunks =
        nostr_workspace_message_chunks(&messages, &transfer_id, "channel_messages")?;
    let total_chunks = message_chunks.len() + 1;
    info!(
        channel_id,
        count = messages.len(),
        "sending channel history"
    );
    let header = WorkspaceUpdate {
        action: history_transfer_action(&transfer_id, 0, total_chunks, "channel_messages"),
        revision,
        channels: vec![],
        members: vec![],
        messages: vec![],
        agents: vec![],
        conversation_agents: workspace
            .conversation_agents()?
            .into_iter()
            .filter(|membership| membership.channel_id.as_deref() == Some(channel_id))
            .map(conversation_agent_payload)
            .collect(),
        conversation_preprompts: workspace
            .conversation_preprompts()?
            .into_iter()
            .filter(|preprompt| preprompt.channel_id.as_deref() == Some(channel_id))
            .map(conversation_preprompt_payload)
            .collect(),
        typing: None,
    };
    messenger
        .send_wire_to_pubkey(sender, WireMessage::workspace_update(header))
        .await?;
    for (index, chunk) in message_chunks.into_iter().enumerate() {
        messenger
            .send_wire_to_pubkey(
                sender,
                WireMessage::workspace_update(WorkspaceUpdate {
                    action: history_transfer_action(
                        &transfer_id,
                        index + 1,
                        total_chunks,
                        "channel_messages",
                    ),
                    revision,
                    channels: vec![],
                    members: vec![],
                    messages: chunk,
                    agents: vec![],
                    conversation_agents: vec![],
                    conversation_preprompts: vec![],
                    typing: None,
                }),
            )
            .await?;
    }
    Ok(())
}

fn nostr_workspace_message_chunks(
    messages: &[WorkspaceMessagePayload],
    transfer_id: &str,
    action: &str,
) -> Result<Vec<Vec<WorkspaceMessagePayload>>> {
    let mut chunks = Vec::new();
    let mut chunk = Vec::new();
    // Use maximum-width sequence fields while budgeting, so final transfer
    // metadata cannot make a valid chunk exceed the NIP-44 plaintext limit.
    let transfer_action = history_transfer_action(transfer_id, usize::MAX, usize::MAX, action);
    for message in messages {
        chunk.push(message.clone());
        let update = WorkspaceUpdate {
            action: transfer_action.clone(),
            revision: 0,
            channels: vec![],
            members: vec![],
            messages: chunk.clone(),
            agents: vec![],
            conversation_agents: vec![],
            conversation_preprompts: vec![],
            typing: None,
        };
        if WireMessage::workspace_update(update).to_json()?.len()
            <= NOSTR_WORKSPACE_TRANSFER_MAX_BYTES
        {
            continue;
        }
        let message = chunk.pop().expect("chunk contains the just-added message");
        if chunk.is_empty() {
            bail!("workspace message is too large for Nostr fallback");
        }
        chunks.push(std::mem::take(&mut chunk));
        chunk.push(message);
        let single_message = WorkspaceUpdate {
            action: transfer_action.clone(),
            revision: 0,
            channels: vec![],
            members: vec![],
            messages: chunk.clone(),
            agents: vec![],
            conversation_agents: vec![],
            conversation_preprompts: vec![],
            typing: None,
        };
        if WireMessage::workspace_update(single_message)
            .to_json()?
            .len()
            > NOSTR_WORKSPACE_TRANSFER_MAX_BYTES
        {
            bail!("workspace message is too large for Nostr fallback");
        }
    }
    if !chunk.is_empty() {
        chunks.push(chunk);
    }
    Ok(chunks)
}

/// Split every snapshot collection below the wrapped-DM payload limit. A single
/// ordered transfer lets clients rebuild the complete snapshot atomically.
fn nostr_workspace_snapshot_chunks(
    snapshot: &WorkspaceUpdate,
    transfer_id: &str,
) -> Result<Vec<WorkspaceUpdate>> {
    let mut template = serde_json::to_value(snapshot)?;
    let object = template
        .as_object_mut()
        .ok_or_else(|| anyhow!("workspace snapshot is not an object"))?;
    let fields = [
        "channels",
        "members",
        "messages",
        "agents",
        "conversation_agents",
        "conversation_preprompts",
    ];
    let collections: Vec<_> = fields
        .iter()
        .map(|field| {
            (
                *field,
                object
                    .insert((*field).to_string(), serde_json::Value::Array(vec![]))
                    .and_then(|value| value.as_array().cloned())
                    .unwrap_or_default(),
            )
        })
        .collect();
    object.insert(
        "action".to_string(),
        serde_json::Value::String(history_transfer_action(
            transfer_id,
            usize::MAX,
            usize::MAX,
            "snapshot",
        )),
    );
    let mut chunks = vec![template.clone()];
    for (field, items) in collections {
        for item in items {
            let current = chunks.last_mut().expect("snapshot has a chunk");
            current[field]
                .as_array_mut()
                .expect("snapshot field is an array")
                .push(item.clone());
            let update: WorkspaceUpdate = serde_json::from_value(current.clone())?;
            if WireMessage::workspace_update(update).to_json()?.len()
                <= NOSTR_WORKSPACE_TRANSFER_MAX_BYTES
            {
                continue;
            }
            current[field]
                .as_array_mut()
                .expect("snapshot field is an array")
                .pop();
            if current[field]
                .as_array()
                .expect("snapshot field is an array")
                .is_empty()
                && chunks.len() == 1
            {
                bail!("workspace snapshot item is too large for Nostr fallback");
            }
            let mut next = template.clone();
            next[field]
                .as_array_mut()
                .expect("snapshot field is an array")
                .push(item);
            let update: WorkspaceUpdate = serde_json::from_value(next.clone())?;
            if WireMessage::workspace_update(update).to_json()?.len()
                > NOSTR_WORKSPACE_TRANSFER_MAX_BYTES
            {
                bail!("workspace snapshot item is too large for Nostr fallback");
            }
            chunks.push(next);
        }
    }
    let total = chunks.len();
    chunks
        .into_iter()
        .enumerate()
        .map(|(sequence, mut chunk)| {
            chunk["action"] = serde_json::Value::String(history_transfer_action(
                transfer_id,
                sequence,
                total,
                "snapshot",
            ));
            Ok(serde_json::from_value(chunk)?)
        })
        .collect()
}

// A transfer envelope keeps chunked history identifiable across relay reordering.
// The receiving client applies it only after all sequence numbers are present.
fn history_transfer_action(
    transfer_id: &str,
    sequence: usize,
    total: usize,
    action: &str,
) -> String {
    format!("history_transfer:v1:{transfer_id}:{sequence}:{total}:{action}")
}

fn workspace_snapshot(workspace: &WorkspaceStore, member: &str) -> Result<WorkspaceUpdate> {
    Ok(WorkspaceUpdate {
        action: "snapshot".to_string(),
        revision: workspace.revision()?,
        channels: workspace
            .channels_for_member(member)?
            .into_iter()
            .map(|channel| channel_payload(workspace, channel))
            .collect::<Result<_>>()?,
        agents: workspace.agents()?.into_iter().map(agent_payload).collect(),
        conversation_agents: workspace
            .conversation_agents()?
            .into_iter()
            .map(conversation_agent_payload)
            .collect(),
        conversation_preprompts: workspace
            .conversation_preprompts()?
            .into_iter()
            .map(conversation_preprompt_payload)
            .collect(),
        members: workspace
            .members()?
            .into_iter()
            .map(member_payload)
            .collect(),
        messages: recent_workspace_snapshot_messages(workspace, member)?,
        typing: None,
    })
}

/// A reconnect must make every conversation immediately useful. Limit each
/// conversation independently instead of letting a busy channel hide all DMs.
fn recent_workspace_snapshot_messages(
    workspace: &WorkspaceStore,
    member: &str,
) -> Result<Vec<WorkspaceMessagePayload>> {
    let mut conversations = BTreeMap::<String, Vec<WorkspaceMessage>>::new();
    for message in workspace.snapshot_messages(member)? {
        let key = match &message.channel_id {
            Some(channel_id) => format!("channel:{channel_id}"),
            None => {
                let mut peers = [
                    message.sender_pubkey.clone(),
                    message.recipient_pubkey.clone().unwrap_or_default(),
                ];
                peers.sort();
                format!("direct:{}:{}", peers[0], peers[1])
            }
        };
        conversations.entry(key).or_default().push(message);
    }
    let mut recent = conversations
        .into_values()
        .flat_map(|messages| {
            let first = messages
                .len()
                .saturating_sub(WORKSPACE_SNAPSHOT_MESSAGE_LIMIT);
            messages.into_iter().skip(first)
        })
        .collect::<Vec<_>>();
    recent.sort_by(|left, right| {
        left.created_at
            .cmp(&right.created_at)
            .then_with(|| left.id.cmp(&right.id))
    });
    Ok(recent.into_iter().map(message_payload).collect())
}

async fn broadcast_workspace_update(
    workspace: &WorkspaceStore,
    messenger: &NostrMessenger,
    outbound: &WorkspaceOutbound,
    update: &WorkspaceUpdate,
) -> Result<()> {
    for member in workspace.members()? {
        outbound
            .send(
                messenger,
                &member.pubkey,
                WireMessage::workspace_update(update.clone()),
            )
            .await?;
    }
    Ok(())
}

async fn broadcast_workspace_snapshots(
    workspace: &WorkspaceStore,
    messenger: &NostrMessenger,
    outbound: &WorkspaceOutbound,
) -> Result<()> {
    for member in workspace.members()? {
        send_workspace_snapshot(workspace, messenger, outbound, &member.pubkey).await?;
    }
    Ok(())
}

async fn send_agent_typing(
    workspace: &WorkspaceStore,
    messenger: &NostrMessenger,
    agent: &WorkspaceAgent,
    channel_id: Option<&str>,
    member: Option<&str>,
    peer: Option<&str>,
    parent_id: Option<&str>,
    stage: Option<&str>,
    expires_in: Option<Duration>,
    fips_only: bool,
) -> Result<()> {
    let expires_at = expires_in
        .map(|duration| {
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs() as i64
                + duration.as_secs() as i64
        })
        .unwrap_or(0);
    let update = WorkspaceUpdate {
        action: "typing".to_string(),
        revision: workspace.revision()?,
        channels: vec![],
        members: vec![],
        messages: vec![],
        agents: vec![],
        conversation_agents: vec![],
        conversation_preprompts: vec![],
        typing: Some(WorkspaceTypingPayload {
            sender_pubkey: format!("agent:{}", agent.id),
            agent_id: Some(agent.id.clone()),
            agent_name: Some(agent.name.clone()),
            stage: stage.map(str::to_string),
            channel_id: channel_id.map(str::to_string),
            recipient_pubkey: None,
            member_pubkey: member.map(str::to_string),
            peer_pubkey: peer.map(str::to_string),
            parent_id: parent_id.map(str::to_string),
            expires_at,
        }),
    };
    let recipients: Vec<String> = if let Some(channel_id) = channel_id {
        workspace
            .channel_members(channel_id)?
            .into_iter()
            .map(|member| member.pubkey)
            .collect()
    } else {
        [member, peer]
            .into_iter()
            .flatten()
            .map(str::to_string)
            .collect()
    };
    let duration = expires_in.unwrap_or(Duration::from_secs(1));
    for recipient in recipients {
        let outbound = WORKSPACE_OUTBOUND
            .lock()
            .expect("workspace outbound registry lock poisoned")
            .clone();
        if let Some(outbound) = outbound {
            if outbound.has_fips_route(&recipient).await {
                outbound
                    .send(
                        messenger,
                        &recipient,
                        WireMessage::workspace_update(update.clone()),
                    )
                    .await?;
                continue;
            }
        }
        if fips_only {
            continue;
        }
        messenger
            .send_ephemeral_wire_to(
                PublicKey::parse(&recipient)?,
                WireMessage::workspace_update(update.clone()),
                duration,
            )
            .await?;
    }
    Ok(())
}

async fn run_workspace_agent_with_typing(
    workspace: &WorkspaceStore,
    messenger: &NostrMessenger,
    agent: &WorkspaceAgent,
    channel_id: Option<&str>,
    member: Option<&str>,
    peer: Option<&str>,
    parent_id: Option<&str>,
    body: &str,
    config: &CodexConfig,
    session_id: &str,
    active_turns: &Arc<Mutex<HashMap<String, CodexCancelToken>>>,
) -> Result<CodexRunResult> {
    const TYPING_LEASE: Duration = Duration::from_secs(6);
    if let Err(err) = send_agent_typing(
        workspace,
        messenger,
        agent,
        channel_id,
        member,
        peer,
        parent_id,
        None,
        Some(TYPING_LEASE),
        false,
    )
    .await
    {
        warn!(agent = %agent.id, "failed to send agent typing state: {err:#}");
    }
    let mut renew = interval(Duration::from_secs(3));
    renew.set_missed_tick_behavior(MissedTickBehavior::Delay);
    renew.tick().await;
    let cancel_token = CodexCancelToken::new();
    active_turns
        .lock()
        .await
        .insert(agent.id.clone(), cancel_token.clone());
    let (event_sender, mut events) = mpsc::unbounded_channel();
    let mut stage = None;
    let mut last_stage_sent = Instant::now() - CODEX_STATUS_MIN_INTERVAL;
    let mut events_open = true;
    let mut run = Box::pin(run_codex_session_with_cancel_and_events(
        body,
        config,
        Some(session_id),
        Some(&cancel_token),
        Some(event_sender),
    ));
    let result = loop {
        tokio::select! {
            result = &mut run => break result,
            event = events.recv(), if events_open => {
                let Some(event) = event else {
                    events_open = false;
                    continue;
                };
                let Some((next_stage, force)) = codex_status_from_event(&event) else { continue; };
                if stage.as_deref() == Some(next_stage.as_str()) || (!force && last_stage_sent.elapsed() < CODEX_STATUS_MIN_INTERVAL) {
                    continue;
                }
                stage = Some(next_stage);
                last_stage_sent = Instant::now();
                if let Err(err) = send_agent_typing(workspace, messenger, agent, channel_id, member, peer, parent_id, stage.as_deref(), Some(TYPING_LEASE), true).await {
                    warn!(agent = %agent.id, "failed to send agent progress state: {err:#}");
                }
            }
            _ = renew.tick() => {
                if let Err(err) = send_agent_typing(workspace, messenger, agent, channel_id, member, peer, parent_id, stage.as_deref(), Some(TYPING_LEASE), true).await {
                    warn!(agent = %agent.id, "failed to refresh agent typing state: {err:#}");
                }
                if let Err(err) = send_agent_typing(workspace, messenger, agent, channel_id, member, peer, parent_id, None, Some(TYPING_LEASE), false).await {
                    warn!(agent = %agent.id, "failed to refresh agent typing state: {err:#}");
                }
            }
        }
    };
    if let Err(err) = send_agent_typing(
        workspace, messenger, agent, channel_id, member, peer, parent_id, None, None, false,
    )
    .await
    {
        warn!(agent = %agent.id, "failed to clear agent typing state: {err:#}");
    }
    active_turns.lock().await.remove(&agent.id);
    result
}

fn initialize_workspace_members(
    workspace: &WorkspaceStore,
    owner: Option<&str>,
    allowed_members: &[String],
) -> Result<()> {
    if let Some(owner) = owner {
        workspace.add_member(owner)?;
        workspace.set_member_admin(owner, true)?;
    }
    // Existing trusted worker recipients are workspace members on first start.
    // This preserves established owner/peer access when workspace storage is added.
    for member in allowed_members {
        workspace.add_member(member)?;
    }
    Ok(())
}

fn channel_payload(
    workspace: &WorkspaceStore,
    channel: rust_lib_nostr_codex_phone::workspace::WorkspaceChannel,
) -> Result<WorkspaceChannelPayload> {
    let members = workspace
        .channel_members(&channel.id)?
        .into_iter()
        .map(|member| WorkspaceChannelMemberPayload {
            pubkey: member.pubkey,
            is_admin: member.is_admin,
        })
        .collect();
    Ok(WorkspaceChannelPayload {
        id: channel.id,
        name: channel.name,
        created_by: channel.created_by,
        created_at: channel.created_at,
        members,
    })
}

fn member_payload(
    member: rust_lib_nostr_codex_phone::workspace::WorkspaceMember,
) -> WorkspaceMemberPayload {
    WorkspaceMemberPayload {
        pubkey: member.pubkey,
        display_name: member.display_name,
        is_admin: member.is_admin,
    }
}
fn message_payload(message: WorkspaceMessage) -> WorkspaceMessagePayload {
    WorkspaceMessagePayload {
        id: message.id,
        channel_id: message.channel_id,
        recipient_pubkey: message.recipient_pubkey,
        sender_pubkey: message.sender_pubkey,
        body: message.body,
        attachments: message.attachments,
        mentions: message.mentions,
        parent_id: message.parent_id,
        also_send_to_main: message.also_send_to_main,
        pinned: message.pinned,
        reactions: message.reactions,
        created_at: message.created_at,
    }
}
fn agent_payload(
    agent: rust_lib_nostr_codex_phone::workspace::WorkspaceAgent,
) -> WorkspaceAgentPayload {
    let scope_metrics = agent
        .opencode_session_id
        .as_deref()
        .and_then(agent_scope_metrics);
    let availability = agent_availability(&agent, scope_metrics.as_ref());
    WorkspaceAgentPayload {
        id: agent.id,
        name: agent.name,
        role: agent.role,
        traits: agent.traits,
        skills: agent.skills,
        preset: agent.preset,
        opencode_provider_id: agent.opencode_provider_id,
        opencode_provider_name: agent.opencode_provider_name,
        opencode_model_id: agent.opencode_model_id,
        opencode_model_name: agent.opencode_model_name,
        opencode_agent: agent.opencode_agent,
        workdir: agent.workdir,
        restart_on_failure: agent.restart_on_failure,
        opencode_session_id: agent.opencode_session_id,
        session_status: agent.session_status,
        session_error: agent.session_error,
        availability,
        scope_memory_bytes: scope_metrics
            .as_ref()
            .and_then(|metrics| metrics.memory_bytes),
        scope_cpu_usage_nsec: scope_metrics
            .as_ref()
            .and_then(|metrics| metrics.cpu_usage_nsec),
        scope_task_count: scope_metrics
            .as_ref()
            .and_then(|metrics| metrics.task_count),
        scope_started_at: scope_metrics
            .as_ref()
            .and_then(|metrics| metrics.started_at),
        instance_id: agent.instance_id,
        created_by: agent.created_by,
        created_at: agent.created_at,
        initialized_at: agent.initialized_at,
        input_tokens: agent.input_tokens,
        output_tokens: agent.output_tokens,
    }
}

fn agent_scope_metrics(session_id: &str) -> Option<AgentScopeMetrics> {
    AGENT_SCOPE_METRICS
        .lock()
        .ok()
        .and_then(|metrics| metrics.get(session_id).cloned())
}

fn agent_availability(agent: &WorkspaceAgent, scope: Option<&AgentScopeMetrics>) -> String {
    if agent.session_status == "failed" || agent.session_error.is_some() {
        return "errored".to_string();
    }
    if agent.session_status != "ready" || agent.opencode_session_id.is_none() {
        return "unavailable".to_string();
    }
    let Some(scope) = scope else {
        return "available".to_string();
    };
    if scope.active_state == "failed" {
        return "errored".to_string();
    }
    if scope.active_state == "active" {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        if scope.started_at.is_some_and(|started_at| {
            now.saturating_sub(started_at) >= AGENT_SCOPE_STUCK_AFTER.as_secs() as i64
        }) {
            return "stuck".to_string();
        }
        return "busy".to_string();
    }
    "available".to_string()
}

fn resolve_agent_runtime(
    mut agent: rust_lib_nostr_codex_phone::workspace::WorkspaceAgent,
    sessions: &[OpenCodeSessionInfo],
    config: &CodexConfig,
) -> rust_lib_nostr_codex_phone::workspace::WorkspaceAgent {
    let session = agent
        .opencode_session_id
        .as_deref()
        .and_then(|id| sessions.iter().find(|session| session.id == id));
    if let Some(session) = session {
        agent.workdir = session.directory.clone().or(agent.workdir);
        agent.opencode_agent = session.agent.clone().or(agent.opencode_agent);
        agent.opencode_provider_id = session.provider_id.clone().or(agent.opencode_provider_id);
        agent.opencode_provider_name = agent
            .opencode_provider_name
            .or_else(|| agent.opencode_provider_id.clone());
        agent.opencode_model_id = session.model_id.clone().or(agent.opencode_model_id);
        agent.opencode_model_name = agent
            .opencode_model_name
            .or_else(|| agent.opencode_model_id.clone());
        agent.initialized_at = session_created_at(session).or(agent.initialized_at);
        agent.input_tokens = session
            .input_tokens
            .and_then(|tokens| i64::try_from(tokens).ok())
            .or(agent.input_tokens);
        agent.output_tokens = session
            .output_tokens
            .and_then(|tokens| i64::try_from(tokens).ok())
            .or(agent.output_tokens);
    }
    agent.workdir = agent
        .workdir
        .or_else(|| Some(config.working_dir.to_string_lossy().to_string()));
    agent.opencode_agent = agent
        .opencode_agent
        .or_else(|| Some(config.opencode.agent.clone()));
    if agent.opencode_provider_id.is_none() {
        agent.opencode_provider_id = config
            .opencode
            .model
            .as_ref()
            .map(|model| model.provider_id.clone());
        agent.opencode_provider_name = agent.opencode_provider_id.clone();
    }
    if agent.opencode_model_id.is_none() {
        agent.opencode_model_id = config
            .opencode
            .model
            .as_ref()
            .map(|model| model.model_id.clone());
        agent.opencode_model_name = agent.opencode_model_id.clone();
    }
    agent
}

fn session_created_at(session: &OpenCodeSessionInfo) -> Option<i64> {
    let timestamp = session.created_at.as_deref()?.parse::<i64>().ok()?;
    Some(if timestamp > 10_000_000_000 {
        timestamp / 1000
    } else {
        timestamp
    })
}
fn conversation_agent_payload(
    agent: WorkspaceConversationAgent,
) -> WorkspaceConversationAgentPayload {
    WorkspaceConversationAgentPayload {
        agent_id: agent.agent_id,
        channel_id: agent.channel_id,
        member_pubkey: agent.member_pubkey,
        peer_pubkey: agent.peer_pubkey,
        folder_scope: agent.folder_scope,
    }
}

fn conversation_preprompt_payload(
    preprompt: WorkspaceConversationPreprompt,
) -> WorkspaceConversationPrepromptPayload {
    WorkspaceConversationPrepromptPayload {
        channel_id: preprompt.channel_id,
        member_pubkey: preprompt.member_pubkey,
        peer_pubkey: preprompt.peer_pubkey,
        preprompt: preprompt.preprompt,
        folder_scope: preprompt.folder_scope,
    }
}

fn canonical_conversation_folder_scope(
    requested_scope: &[String],
    _codex_config: &CodexConfig,
) -> Result<Vec<String>> {
    if requested_scope.is_empty() || requested_scope.len() > 20 {
        bail!("select between one and 20 folders for conversation access");
    }
    let allowed_roots = vec![canonical_conversation_root_dir()?];
    let mut scope = Vec::with_capacity(requested_scope.len());
    for requested in requested_scope {
        let path = PathBuf::from(requested.trim());
        let canonical = path
            .canonicalize()
            .with_context(|| format!("scope folder `{}` is not accessible", path.display()))?;
        if !canonical.is_dir() {
            bail!("scope folder `{}` is not a directory", canonical.display());
        }
        ensure_spawn_existing_allowed(&canonical, &allowed_roots)?;
        let canonical = canonical.to_string_lossy().to_string();
        if !scope.contains(&canonical) {
            scope.push(canonical);
        }
    }
    Ok(scope)
}

fn canonical_conversation_folder_scope_or_empty(
    requested_scope: &[String],
    codex_config: &CodexConfig,
) -> Result<Vec<String>> {
    if requested_scope.is_empty() {
        Ok(Vec::new())
    } else {
        canonical_conversation_folder_scope(requested_scope, codex_config)
    }
}

fn direct_membership_matches(
    membership: &WorkspaceConversationAgent,
    one: &str,
    two: &str,
) -> bool {
    let mut participants = [one, two];
    participants.sort();
    membership.member_pubkey.as_deref() == Some(participants[0])
        && membership.peer_pubkey.as_deref() == Some(participants[1])
}

async fn provision_workspace_agent_session(
    codex_config: &CodexConfig,
) -> (Option<String>, String, Option<String>) {
    if codex_config.backend != AgentBackend::OpenCode {
        return (
            None,
            "failed".to_string(),
            Some("OpenCode is not the configured agent backend".to_string()),
        );
    }

    match new_opencode_session(codex_config).await {
        Ok(session_id) => (Some(session_id), "ready".to_string(), None),
        Err(err) => (
            None,
            "failed".to_string(),
            Some(format!("OpenCode session provisioning failed: {err:#}")),
        ),
    }
}

fn enqueue_conversation_agents(
    workspace: &WorkspaceStore,
    queues: &mut WorkspaceAgentQueues,
    channel_id: Option<&str>,
    member: Option<&str>,
    peer: Option<&str>,
    mentions: &[WorkspaceMentionPayload],
    trigger_message_id: &str,
) -> Result<()> {
    let conversation = match channel_id {
        Some(channel_id) => WorkspaceConversation::Channel(channel_id.to_string()),
        None => {
            let mut participants = [
                member
                    .context("direct workspace message is missing sender")?
                    .to_string(),
                peer.context("direct workspace message is missing recipient")?
                    .to_string(),
            ];
            participants.sort();
            WorkspaceConversation::Direct(participants[0].clone(), participants[1].clone())
        }
    };
    for agent in workspace.agents_for_conversation(channel_id, member, peer)? {
        if conversation_agent_is_targeted(&agent.id, mentions) {
            queues.enqueue(
                agent.id,
                conversation.clone(),
                trigger_message_id.to_string(),
            );
        }
    }
    Ok(())
}

async fn workspace_agent_queue_worker(
    mut receiver: mpsc::UnboundedReceiver<WorkspaceAgentJob>,
    agent_id: String,
    conversation: WorkspaceConversation,
    active_turns: Arc<Mutex<HashMap<String, CodexCancelToken>>>,
    workspace_path: PathBuf,
    messenger: Arc<NostrMessenger>,
    outbound: WorkspaceOutbound,
    codex_config: CodexConfig,
) {
    while let Some(job) = receiver.recv().await {
        if let Err(err) = process_workspace_agent_job(
            &workspace_path,
            messenger.as_ref(),
            &outbound,
            &codex_config,
            &agent_id,
            &conversation,
            &job.trigger_message_id,
            &active_turns,
        )
        .await
        {
            warn!(agent = %agent_id, trigger = %job.trigger_message_id, "workspace agent job failed: {err:#}");
        }
    }
}

async fn process_workspace_agent_job(
    workspace_path: &Path,
    messenger: &NostrMessenger,
    outbound: &WorkspaceOutbound,
    codex_config: &CodexConfig,
    agent_id: &str,
    conversation: &WorkspaceConversation,
    trigger_message_id: &str,
    active_turns: &Arc<Mutex<HashMap<String, CodexCancelToken>>>,
) -> Result<()> {
    let workspace = WorkspaceStore::open_existing(workspace_path)?;
    let Some(message) = workspace.message_by_id(trigger_message_id)? else {
        return Ok(());
    };
    if !workspace_agent_job_matches_trigger(&message, conversation) {
        return Ok(());
    }
    let reply_parent_id = workspace_agent_reply_parent_id(&message);

    match (&message.channel_id, &message.recipient_pubkey) {
        (Some(channel_id), None) => {
            route_conversation_agents(
                &workspace,
                messenger,
                outbound,
                codex_config,
                Some(agent_id),
                Some(channel_id),
                None,
                None,
                Some(reply_parent_id),
                &message.body,
                &message.mentions,
                active_turns,
            )
            .await
        }
        (None, Some(recipient)) => {
            route_conversation_agents(
                &workspace,
                messenger,
                outbound,
                codex_config,
                Some(agent_id),
                None,
                Some(&message.sender_pubkey),
                Some(recipient),
                Some(reply_parent_id),
                &message.body,
                &message.mentions,
                active_turns,
            )
            .await
        }
        _ => Ok(()),
    }
}

fn workspace_agent_reply_parent_id(message: &WorkspaceMessage) -> &str {
    message.parent_id.as_deref().unwrap_or(&message.id)
}

fn workspace_agent_profile_from_request(
    request: &WorkspaceRequest,
    codex_config: &CodexConfig,
) -> Result<WorkspaceAgentOpenCodeProfile> {
    let provider_id =
        optional_opencode_segment("provider", request.opencode_provider_id.as_deref())?;
    let model_id = optional_opencode_segment("model", request.opencode_model_id.as_deref())?;
    if provider_id.is_some() != model_id.is_some() {
        bail!("choose both an OpenCode provider and model, or leave both as worker default");
    }
    let agent = optional_opencode_segment("OpenCode agent", request.opencode_agent.as_deref())?;
    let workdir = request
        .agent_workdir
        .as_deref()
        .map(|value| {
            let requested = PathBuf::from(value.trim());
            let canonical = requested.canonicalize().with_context(|| {
                format!("agent workdir `{}` is not accessible", requested.display())
            })?;
            if !canonical.is_dir() {
                bail!("agent workdir `{}` is not a directory", canonical.display());
            }
            ensure_spawn_existing_allowed(
                &canonical,
                &canonical_allowed_workdir_roots(&codex_config.working_dir)?,
            )?;
            Ok(canonical.to_string_lossy().to_string())
        })
        .transpose()?;
    Ok(WorkspaceAgentOpenCodeProfile {
        provider_name: request
            .opencode_provider_name
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string),
        model_name: request
            .opencode_model_name
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string),
        provider_id,
        model_id,
        agent,
        workdir,
        restart_on_failure: request.restart_agent_session_on_failure,
    })
}

fn optional_opencode_segment(label: &str, value: Option<&str>) -> Result<Option<String>> {
    let Some(value) = value.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(None);
    };
    if value.len() > 100
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
    {
        bail!("{label} must contain only letters, numbers, `.`, `_`, or `-`");
    }
    Ok(Some(value.to_string()))
}

fn codex_config_for_workspace_agent(
    config: &CodexConfig,
    profile: &WorkspaceAgentOpenCodeProfile,
) -> Result<CodexConfig> {
    let mut resolved = config.clone();
    if let (Some(provider_id), Some(model_id)) = (&profile.provider_id, &profile.model_id) {
        resolved.opencode.model = Some(OpenCodeModel {
            provider_id: provider_id.clone(),
            model_id: model_id.clone(),
        });
    }
    if let Some(agent) = &profile.agent {
        resolved.opencode.agent = agent.clone();
    }
    if let Some(workdir) = &profile.workdir {
        resolved.working_dir = PathBuf::from(workdir);
    }
    Ok(resolved)
}

fn codex_config_for_workspace_agent_record(
    config: &CodexConfig,
    agent: &WorkspaceAgent,
) -> Result<CodexConfig> {
    let profile = WorkspaceAgentOpenCodeProfile {
        provider_id: agent.opencode_provider_id.clone(),
        provider_name: agent.opencode_provider_name.clone(),
        model_id: agent.opencode_model_id.clone(),
        model_name: agent.opencode_model_name.clone(),
        agent: agent.opencode_agent.clone(),
        workdir: agent.workdir.clone(),
        restart_on_failure: agent.restart_on_failure,
    };
    if let Some(workdir) = &profile.workdir {
        let canonical = PathBuf::from(workdir)
            .canonicalize()
            .with_context(|| format!("agent workdir `{workdir}` is not accessible"))?;
        ensure_spawn_existing_allowed(
            &canonical,
            &canonical_allowed_workdir_roots(&config.working_dir)?,
        )?;
    }
    codex_config_for_workspace_agent(config, &profile)
}

async fn route_conversation_agents(
    workspace: &WorkspaceStore,
    messenger: &NostrMessenger,
    outbound: &WorkspaceOutbound,
    codex_config: &CodexConfig,
    only_agent_id: Option<&str>,
    channel_id: Option<&str>,
    member: Option<&str>,
    peer: Option<&str>,
    parent_id: Option<&str>,
    body: &str,
    mentions: &[WorkspaceMentionPayload],
    active_turns: &Arc<Mutex<HashMap<String, CodexCancelToken>>>,
) -> Result<()> {
    let memberships = workspace.conversation_agents()?;
    let preprompts = workspace.conversation_preprompts()?;
    for mut agent in workspace.agents_for_conversation(channel_id, member, peer)? {
        if only_agent_id.is_some_and(|agent_id| agent.id != agent_id) {
            continue;
        }
        if !conversation_agent_is_targeted(&agent.id, mentions) {
            continue;
        }
        if agent.session_status != "ready" && agent.restart_on_failure {
            let agent_config = match codex_config_for_workspace_agent_record(codex_config, &agent) {
                Ok(config) => config,
                Err(err) => {
                    warn!(agent = %agent.id, "workspace agent configuration is invalid: {err:#}");
                    continue;
                }
            };
            let (session_id, status, session_error) =
                provision_workspace_agent_session(&agent_config).await;
            agent = workspace.update_agent_session(
                &agent.id,
                session_id.as_deref(),
                &status,
                session_error.as_deref(),
            )?;
            broadcast_workspace_update(
                workspace,
                messenger,
                outbound,
                &WorkspaceUpdate {
                    action: "agent_session_restarted".to_string(),
                    revision: workspace.revision()?,
                    channels: vec![],
                    members: vec![],
                    messages: vec![],
                    agents: vec![agent_payload(agent.clone())],
                    conversation_agents: vec![],
                    conversation_preprompts: vec![],
                    typing: None,
                },
            )
            .await?;
        }
        let Some(session_id) = (agent.session_status == "ready")
            .then_some(agent.opencode_session_id.as_deref())
            .flatten()
        else {
            warn!(agent = %agent.id, status = %agent.session_status, "workspace agent is not ready to respond");
            continue;
        };
        let folder_scope = memberships
            .iter()
            .find(|membership| {
                membership.agent_id == agent.id
                    && match channel_id {
                        Some(channel_id) => membership.channel_id.as_deref() == Some(channel_id),
                        None => direct_membership_matches(
                            membership,
                            member.unwrap_or_default(),
                            peer.unwrap_or_default(),
                        ),
                    }
            })
            .map(|membership| membership.folder_scope.as_slice())
            .unwrap_or_default();
        let mut agent_config = match codex_config_for_workspace_agent_record(codex_config, &agent) {
            Ok(config) => config,
            Err(err) => {
                warn!(agent = %agent.id, "workspace agent configuration is invalid: {err:#}");
                continue;
            }
        };
        // A membership's folder scope owns the execution directory. An agent's
        // saved workdir is only a profile default and must not escape this
        // conversation when the same agent is assigned elsewhere.
        if let Some(working_folder) = folder_scope.first() {
            agent_config.working_dir = PathBuf::from(working_folder);
        }
        let preprompt = preprompts
            .iter()
            .find(|preprompt| match channel_id {
                Some(channel_id) => preprompt.channel_id.as_deref() == Some(channel_id),
                None => direct_preprompt_matches(
                    preprompt,
                    member.unwrap_or_default(),
                    peer.unwrap_or_default(),
                ),
            })
            .map(|preprompt| preprompt.preprompt.as_str())
            .unwrap_or_default();
        let thread_context =
            workspace_thread_context(workspace, parent_id, channel_id, member, peer)?;
        let prompt = match conversation_scope_prompt(folder_scope, &agent_config) {
            Ok(scope) => format!(
                "{}\n\n{}",
                conversation_agent_session_prompt(preprompt, &scope),
                conversation_agent_prompt(&thread_context, body),
            ),
            Err(err) => {
                warn!(agent = %agent.id, "conversation folder scope is invalid: {err:#}");
                continue;
            }
        };
        let mut active_session_id = session_id.to_string();
        if workspace.agent_session_context(&agent.id)?.as_deref()
            != Some(WORKSPACE_AGENT_SESSION_CONTEXT)
        {
            match run_workspace_agent_with_typing(
                workspace,
                messenger,
                &agent,
                channel_id,
                member,
                peer,
                parent_id,
                &conversation_agent_initialization_prompt(),
                &agent_config,
                &active_session_id,
                active_turns,
            )
            .await
            {
                Ok(_) => workspace
                    .set_agent_session_context(&agent.id, WORKSPACE_AGENT_SESSION_CONTEXT)?,
                Err(err) => {
                    warn!(agent = %agent.id, "workspace agent session initialization failed: {err:#}");
                    continue;
                }
            }
        }
        let mut result = match run_workspace_agent_with_typing(
            workspace,
            messenger,
            &agent,
            channel_id,
            member,
            peer,
            parent_id,
            &prompt,
            &agent_config,
            &active_session_id,
            active_turns,
        )
        .await
        {
            Ok(result) if !result.response.trim().is_empty() => result,
            Ok(_) => continue,
            Err(err) if is_agent_cancelled_error(&err) => {
                info!(agent = %agent.id, "workspace agent task cancelled");
                continue;
            }
            Err(err) if agent.restart_on_failure => {
                warn!(agent = %agent.id, "workspace agent response failed; restarting dedicated session: {err:#}");
                let (new_session_id, status, session_error) =
                    provision_workspace_agent_session(&agent_config).await;
                let Some(new_session_id) = new_session_id else {
                    let updated = workspace.update_agent_session(
                        &agent.id,
                        None,
                        &status,
                        session_error.as_deref(),
                    )?;
                    broadcast_workspace_update(
                        workspace,
                        messenger,
                        outbound,
                        &WorkspaceUpdate {
                            action: "agent_session_restarted".to_string(),
                            revision: workspace.revision()?,
                            channels: vec![],
                            members: vec![],
                            messages: vec![],
                            agents: vec![agent_payload(updated)],
                            conversation_agents: vec![],
                            conversation_preprompts: vec![],
                            typing: None,
                        },
                    )
                    .await?;
                    continue;
                };
                let updated = workspace.update_agent_session(
                    &agent.id,
                    Some(&new_session_id),
                    &status,
                    None,
                )?;
                active_session_id = new_session_id;
                broadcast_workspace_update(
                    workspace,
                    messenger,
                    outbound,
                    &WorkspaceUpdate {
                        action: "agent_session_restarted".to_string(),
                        revision: workspace.revision()?,
                        channels: vec![],
                        members: vec![],
                        messages: vec![],
                        agents: vec![agent_payload(updated)],
                        conversation_agents: vec![],
                        conversation_preprompts: vec![],
                        typing: None,
                    },
                )
                .await?;
                match run_workspace_agent_with_typing(
                    workspace,
                    messenger,
                    &agent,
                    channel_id,
                    member,
                    peer,
                    parent_id,
                    &prompt,
                    &agent_config,
                    &active_session_id,
                    active_turns,
                )
                .await
                {
                    Ok(result) if !result.response.trim().is_empty() => result,
                    Ok(_) => continue,
                    Err(restart_err) => {
                        warn!(agent = %agent.id, "workspace agent response failed after restart: {restart_err:#}");
                        continue;
                    }
                }
            }
            Err(err) => {
                warn!(agent = %agent.id, "workspace agent response failed: {err:#}");
                continue;
            }
        };
        let mut history_follow_up_failed = false;
        for _ in 0..WORKSPACE_HISTORY_REQUEST_ATTEMPTS {
            let Some(message_count) = workspace_history_request_count(&result.response) else {
                break;
            };
            let history =
                workspace_agent_history(workspace, channel_id, member, peer, message_count)?;
            let prompt = format!(
                "Here is the requested conversation history. Use it to answer the user's message. Do not mention this retrieval.\n\n{history}"
            );
            match run_workspace_agent_with_typing(
                workspace,
                messenger,
                &agent,
                channel_id,
                member,
                peer,
                parent_id,
                &prompt,
                &agent_config,
                &active_session_id,
                active_turns,
            )
            .await
            {
                Ok(next) if !next.response.trim().is_empty() => result = next,
                Ok(_) => {
                    history_follow_up_failed = true;
                    break;
                }
                Err(err) => {
                    warn!(agent = %agent.id, "workspace history request failed: {err:#}");
                    history_follow_up_failed = true;
                    break;
                }
            }
        }
        // A history request is an internal control response, never a message to show in the thread.
        if history_follow_up_failed || workspace_history_request_count(&result.response).is_some() {
            continue;
        }
        if let Some(usage) = result.token_usage {
            let updated = workspace.record_agent_token_usage(
                &agent.id,
                usage.input_tokens,
                usage.output_tokens,
            )?;
            broadcast_workspace_update(
                workspace,
                messenger,
                outbound,
                &WorkspaceUpdate {
                    action: "agent_usage_updated".to_string(),
                    revision: workspace.revision()?,
                    channels: vec![],
                    members: vec![],
                    messages: vec![],
                    agents: vec![agent_payload(updated)],
                    conversation_agents: vec![],
                    conversation_preprompts: vec![],
                    typing: None,
                },
            )
            .await?;
        }
        let also_send_to_main = parent_id.is_none();
        let message = match channel_id {
            Some(channel_id) => workspace.add_channel_message_with_main(
                &format!("agent:{}", agent.id),
                channel_id,
                &result.response,
                &[],
                &[],
                parent_id,
                also_send_to_main,
            )?,
            None => workspace.add_direct_message_with_main(
                &format!("agent:{}", agent.id),
                peer.unwrap_or_default(),
                &result.response,
                &[],
                &[],
                parent_id,
                also_send_to_main,
            )?,
        };
        let update = WorkspaceUpdate {
            action: "message_created".to_string(),
            revision: workspace.revision()?,
            channels: vec![],
            members: vec![],
            messages: vec![message_payload(message)],
            agents: vec![],
            conversation_agents: vec![],
            conversation_preprompts: vec![],
            typing: None,
        };
        let recipients = if channel_id.is_some() {
            workspace
                .channel_members(channel_id.unwrap_or_default())?
                .into_iter()
                .map(|member| member.pubkey)
                .collect()
        } else {
            vec![
                member.unwrap_or_default().to_string(),
                peer.unwrap_or_default().to_string(),
            ]
        };
        queue_workspace_update(workspace, recipients, &update).await?;
        flush_workspace_notification_outbox(workspace, messenger, outbound).await;
    }
    Ok(())
}

fn conversation_scope_prompt(scope: &[String], config: &CodexConfig) -> Result<String> {
    if scope.is_empty() {
        return Ok(String::new());
    }
    let folders = canonical_conversation_folder_scope(scope, config)?;
    let reference_roots = canonical_allowed_workdir_roots(&config.working_dir)?;
    let repositories = repositories_in_folder_scope(&folders)?;
    let repository_list = if repositories.is_empty() {
        "No Git repositories were found in the selected folders.".to_string()
    } else {
        repositories.join("\n")
    };
    Ok(format!(
        "Conversation folder access: make changes only in these folders (their nested repositories are included):\n{}\n\nRead-only local resources: you may inspect these folders to reference related projects, but do not modify them unless they are also listed above:\n{}\n\nRepositories in scope:\n{}",
        folders.join("\n"),
        reference_roots
            .iter()
            .map(|root| root.to_string_lossy())
            .collect::<Vec<_>>()
            .join("\n"),
        repository_list,
    ))
}

fn direct_preprompt_matches(
    preprompt: &WorkspaceConversationPreprompt,
    one: &str,
    two: &str,
) -> bool {
    let mut participants = [one, two];
    participants.sort();
    preprompt.member_pubkey.as_deref() == Some(participants[0])
        && preprompt.peer_pubkey.as_deref() == Some(participants[1])
}

fn conversation_agent_session_prompt(preprompt: &str, scope: &str) -> String {
    let mut sections = Vec::new();
    if !preprompt.is_empty() {
        sections.push(preprompt.to_string());
    }
    if !scope.is_empty() {
        sections.push(scope.to_string());
    }
    sections.join("\n\n")
}

fn conversation_agent_initialization_prompt() -> String {
    format!(
        "You are in a shared conversation. Other participants' messages are not automatically in your context. If you need recent context, reply with only `[[WORKSPACE_HISTORY: N]]`, where N is 5, 10, 15, and so on up to {WORKSPACE_HISTORY_REQUEST_MAX}. You will then receive that many recent messages before replying. This setup applies to all following messages in this session. Reply only READY to acknowledge it."
    )
}

fn conversation_agent_prompt(thread_context: &str, body: &str) -> String {
    let mut sections = Vec::new();
    if !thread_context.is_empty() {
        sections.push(format!("Thread context:\n{thread_context}"));
    }
    sections.push(format!("User message:\n{body}"));
    sections.join("\n\n")
}

fn workspace_thread_context(
    workspace: &WorkspaceStore,
    parent_id: Option<&str>,
    channel_id: Option<&str>,
    member: Option<&str>,
    peer: Option<&str>,
) -> Result<String> {
    let Some(parent_id) = parent_id else {
        return Ok(String::new());
    };
    let messages = match channel_id {
        Some(channel_id) => workspace.channel_messages(channel_id)?,
        None => workspace.direct_messages(member.unwrap_or_default(), peer.unwrap_or_default())?,
    };
    let thread = messages
        .iter()
        .filter(|message| {
            message.id == parent_id || message.parent_id.as_deref() == Some(parent_id)
        })
        .map(|message| format!("{}: {}", message.sender_pubkey, message.body))
        .collect::<Vec<_>>();
    Ok(thread.join("\n"))
}

fn workspace_history_request_count(response: &str) -> Option<usize> {
    let value = response
        .trim()
        .strip_prefix("[[WORKSPACE_HISTORY: ")?
        .strip_suffix("]]")?
        .trim()
        .parse::<usize>()
        .ok()?;
    (value >= WORKSPACE_HISTORY_REQUEST_STEP
        && value <= WORKSPACE_HISTORY_REQUEST_MAX
        && value % WORKSPACE_HISTORY_REQUEST_STEP == 0)
        .then_some(value)
}

fn workspace_agent_history(
    workspace: &WorkspaceStore,
    channel_id: Option<&str>,
    member: Option<&str>,
    peer: Option<&str>,
    message_count: usize,
) -> Result<String> {
    let messages = match channel_id {
        Some(channel_id) => workspace.channel_messages(channel_id)?,
        None => workspace.direct_messages(member.unwrap_or_default(), peer.unwrap_or_default())?,
    };
    let recent = messages
        .iter()
        .rev()
        .take(message_count)
        .rev()
        .map(|message| format!("{}: {}", message.sender_pubkey, message.body))
        .collect::<Vec<_>>();
    Ok(format!(
        "Recent conversation messages (up to {message_count}):\n{}",
        if recent.is_empty() {
            "(No earlier messages.)".to_string()
        } else {
            recent.join("\n")
        }
    ))
}

fn repositories_in_folder_scope(folders: &[String]) -> Result<Vec<String>> {
    let mut repositories = Vec::new();
    for folder in folders {
        collect_repositories(Path::new(folder), &mut repositories)?;
    }
    repositories.sort();
    repositories.dedup();
    Ok(repositories)
}

fn collect_repositories(folder: &Path, repositories: &mut Vec<String>) -> Result<()> {
    if folder.join(".git").is_dir() {
        repositories.push(folder.to_string_lossy().to_string());
    }
    for entry in fs::read_dir(folder)
        .with_context(|| format!("failed to read scope folder `{}`", folder.display()))?
    {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let path = entry.path();
        let hidden = path
            .file_name()
            .and_then(|name| name.to_str())
            .is_some_and(|name| name.starts_with('.'));
        if file_type.is_dir() && !hidden {
            collect_repositories(&path, repositories)?;
        }
    }
    Ok(())
}

fn conversation_agent_is_targeted(agent_id: &str, mentions: &[WorkspaceMentionPayload]) -> bool {
    mentions
        .iter()
        .any(|mention| mention.kind == "agent" && mention.id == agent_id)
}

fn session_worker_key(message: &IncomingMessage) -> String {
    let workdir = route_workdir_from_json(&message.raw_json)
        .or_else(|| route_workdir_from_json(&message.text))
        .unwrap_or_default();
    let session_id = route_session_id_from_json(&message.raw_json)
        .or_else(|| route_session_id_from_json(&message.text))
        .unwrap_or_default();
    format!(
        "{}\u{1f}{workdir}\u{1f}{session_id}",
        message.sender_pubkey_hex
    )
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
    messenger: &Arc<NostrMessenger>,
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
                messenger.as_ref(),
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
        Some(NonblockingControlRequest::RepoList(path)) => {
            info!(
                "processing repo list request event {} while codex task is active",
                message.event_id
            );
            process_repo_list_request(
                messenger.as_ref(),
                &message.sender_pubkey_hex,
                path.as_deref(),
            )
            .await;
            true
        }
        Some(NonblockingControlRequest::OpenCodeSessions) => {
            info!(
                "processing OpenCode session list request event {} while codex task is active",
                message.event_id
            );
            let codex_config = match routed_codex_config(codex_config, message) {
                Ok(config) => config,
                Err(err) => {
                    send_response(
                        messenger.as_ref(),
                        &message.sender_pubkey_hex,
                        format!("Invalid route: {err:#}"),
                    )
                    .await;
                    return true;
                }
            };
            let messenger = Arc::clone(messenger);
            let owner_pubkey_hex = message.sender_pubkey_hex.clone();
            tokio::spawn(async move {
                process_opencode_session_list_request(
                    messenger.as_ref(),
                    &owner_pubkey_hex,
                    &codex_config,
                )
                .await;
            });
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
        return Some(NonblockingControlRequest::RepoList(repo_list_request_path(
            text,
        )));
    }
    if is_opencode_session_list_request(text) {
        return Some(NonblockingControlRequest::OpenCodeSessions);
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
                let path = repo_list_request_path(&message.text);
                process_repo_list_request(messenger, &message.sender_pubkey_hex, path.as_deref())
                    .await;
                return;
            }

            if is_opencode_session_list_request(&message.text) {
                process_opencode_session_list_request(
                    messenger,
                    &message.sender_pubkey_hex,
                    &codex_config,
                )
                .await;
                return;
            }

            if let Some(request_id) = opencode_model_list_request_id(&message.text) {
                process_opencode_model_list_request(
                    messenger,
                    &message.sender_pubkey_hex,
                    &codex_config,
                    &request_id,
                )
                .await;
                return;
            }

            if let Some(tool_result) = structured_tool_result(
                memory,
                &message.sender_pubkey_hex,
                &message.text,
                &codex_config.working_dir,
            ) {
                let delivery_error = ToolResult {
                    data: serde_json::json!({
                        "error": "The tool result could not be delivered. Please retry."
                    }),
                    ..tool_result.clone()
                };
                if let Err(err) = messenger
                    .send_wire_to_pubkey(
                        &message.sender_pubkey_hex,
                        WireMessage::tool_result(tool_result),
                    )
                    .await
                {
                    error!("failed to send structured tool result: {err:#}");
                    if let Err(fallback_err) = messenger
                        .send_wire_to_pubkey(
                            &message.sender_pubkey_hex,
                            WireMessage::tool_result(delivery_error),
                        )
                        .await
                    {
                        error!("failed to send tool delivery error: {fallback_err:#}");
                    }
                }
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
                report_codex_cancelled::<()>(messenger, &message.sender_pubkey_hex)
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
                    codex_config.working_dir.to_string_lossy().to_string(),
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

    let mut attachment_lines = Vec::new();
    let mut transcripts = Vec::new();
    let mut local_texts = Vec::new();
    let mut local_attachments: Vec<DownloadedAudio> = Vec::new();
    let voice_only = !bundle.attachments.is_empty()
        && bundle
            .attachments
            .iter()
            .all(|attachment| attachment.media_type.starts_with("audio/"));

    for (index, attachment) in bundle.attachments.iter().enumerate() {
        if cancel_token.is_cancelled() {
            report_codex_cancelled::<()>(messenger, peer_pubkey)
                .await
                .ok();
            return;
        }
        let label = attachment
            .name
            .clone()
            .unwrap_or_else(|| format!("attachment-{}", index + 1));
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
                report_codex_cancelled::<()>(messenger, peer_pubkey)
                    .await
                    .ok();
                return;
            }

            transcripts.push(transcript.clone());

            if let Err(err) = messenger
                .send_transcript_for_event_to(
                    peer_pubkey,
                    transcript.clone(),
                    message.event_id.clone(),
                    codex_config.working_dir.to_string_lossy().to_string(),
                )
                .await
            {
                warn!("failed to send transcript DM: {err:#}");
            }
            continue;
        }

        attachment_lines.push(format!(
            "- {label} ({}) => {}",
            attachment.media_type, attachment.url
        ));

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
                report_codex_cancelled::<()>(messenger, peer_pubkey)
                    .await
                    .ok();
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
                report_codex_cancelled::<()>(messenger, peer_pubkey)
                    .await
                    .ok();
                return;
            }
            let local_path = downloaded.path.display().to_string();
            attachment_lines.push(format!("  local decrypted image: {local_path}"));
            local_texts.push(format!(
                "{label}:\nLocal decrypted image file: {local_path}\nUse this local file when inspecting the image."
            ));
            local_attachments.push(downloaded);
            continue;
        }

        let downloaded = match download_local_attachment(
            attachment,
            audio_config,
            messenger,
            peer_pubkey,
            "file",
        )
        .await
        {
            Some(downloaded) => downloaded,
            None => continue,
        };
        if cancel_token.is_cancelled() {
            report_codex_cancelled::<()>(messenger, peer_pubkey)
                .await
                .ok();
            return;
        }
        let local_path = downloaded.path.display().to_string();
        local_texts.push(format!(
            "{label}:\nLocal decrypted file: {local_path}\nUse this file when handling the request."
        ));
        local_attachments.push(downloaded);
    }

    if cancel_token.is_cancelled() {
        report_codex_cancelled::<()>(messenger, peer_pubkey)
            .await
            .ok();
        return;
    }

    let request_text = media_bundle_request_text(
        user_query,
        &attachment_lines,
        &transcripts,
        &local_texts,
        voice_only,
    );

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

async fn process_repo_list_request(
    messenger: &NostrMessenger,
    owner_pubkey_hex: &str,
    path: Option<&str>,
) {
    match build_repo_list(path) {
        Ok(repo_list) => {
            if let Err(err) = send_application_wire(
                messenger,
                owner_pubkey_hex,
                WireMessage::repo_list(repo_list),
            )
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

async fn process_opencode_session_list_request(
    messenger: &NostrMessenger,
    owner_pubkey_hex: &str,
    codex_config: &CodexConfig,
) {
    info!(
        "listing OpenCode sessions for {}",
        codex_config.working_dir.display()
    );
    match list_opencode_sessions(codex_config).await {
        Ok(sessions) => {
            let session_list = OpenCodeSessionList {
                workdir: Some(codex_config.working_dir.to_string_lossy().to_string()),
                sessions: sessions.into_iter().map(opencode_session_entry).collect(),
            };
            let session_count = session_list.sessions.len();
            if let Err(err) = messenger
                .send_wire_to_pubkey(
                    owner_pubkey_hex,
                    WireMessage::opencode_sessions(session_list),
                )
                .await
            {
                error!("failed to send OpenCode session list DM: {err:#}");
            } else {
                info!("sent {session_count} OpenCode sessions");
            }
        }
        Err(err) => {
            send_response(
                messenger,
                owner_pubkey_hex,
                format!("Could not list OpenCode sessions: {err:#}"),
            )
            .await;
        }
    }
}

async fn process_opencode_model_list_request(
    messenger: &NostrMessenger,
    owner_pubkey_hex: &str,
    codex_config: &CodexConfig,
    request_id: &str,
) {
    match list_opencode_models(codex_config).await {
        Ok(models) => {
            let result = ToolResult {
                tool: "model_list".to_string(),
                request_id: request_id.to_string(),
                workdir: codex_config.working_dir.to_string_lossy().to_string(),
                data: serde_json::json!({
                    "models": models.into_iter().map(|model| serde_json::json!({
                        "provider_id": model.provider_id,
                        "provider_name": model.provider_name,
                        "model_id": model.model_id,
                        "model_name": model.model_name,
                    })).collect::<Vec<_>>(),
                }),
            };
            if let Err(err) = messenger
                .send_wire_to_pubkey(owner_pubkey_hex, WireMessage::tool_result(result))
                .await
            {
                error!("failed to send OpenCode model list DM: {err:#}");
            }
        }
        Err(err) => {
            let result = ToolResult {
                tool: "model_list".to_string(),
                request_id: request_id.to_string(),
                workdir: codex_config.working_dir.to_string_lossy().to_string(),
                data: serde_json::json!({ "error": format!("Could not list OpenCode models: {err:#}") }),
            };
            let _ = messenger
                .send_wire_to_pubkey(owner_pubkey_hex, WireMessage::tool_result(result))
                .await;
        }
    }
}

fn opencode_session_entry(session: OpenCodeSessionInfo) -> OpenCodeSessionListEntry {
    OpenCodeSessionListEntry {
        id: session.id,
        title: session.title,
        directory: session.directory,
        created_at: session.created_at,
        updated_at: session.updated_at,
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
    codex_config: &CodexConfig,
    _audio_config: &AudioConfig,
    _transcribe_config: &TranscribeConfig,
    _manager: &RepoRuntimeManager,
) -> Result<(TargetInvite, u32, bool)> {
    let context = repo_target_context(request, relays, current_workdir)?;

    if codex_config.backend == AgentBackend::OpenCode {
        let mut target_config = codex_config.clone();
        target_config.working_dir = context.workdir.clone();
        let session_id = if request.new_session {
            new_opencode_session(&target_config).await?
        } else {
            ensure_opencode_session(&target_config).await?
        };
        info!(
            "ensured OpenCode session {session_id} for {}",
            context.workdir.display()
        );
    }

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
    let Some(workdir) = path.parent().and_then(Path::parent) else {
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

fn repo_list_request_path(request: &str) -> Option<String> {
    let value: serde_json::Value = serde_json::from_str(request.trim()).ok()?;
    value
        .as_object()?
        .get("repo_list_request")?
        .as_object()?
        .get("path")?
        .as_str()
        .map(str::trim)
        .filter(|path| !path.is_empty())
        .map(ToOwned::to_owned)
}

fn is_opencode_session_list_request(request: &str) -> bool {
    let trimmed = request.trim();
    if matches!(
        trimmed,
        "/opencode-sessions" | "/opencode_sessions" | "/sessions"
    ) {
        return true;
    }
    let Ok(value) = serde_json::from_str::<serde_json::Value>(trimmed) else {
        return false;
    };
    value
        .as_object()
        .is_some_and(|object| object.contains_key("opencode_session_list_request"))
}

fn opencode_model_list_request_id(request: &str) -> Option<String> {
    let value: serde_json::Value = serde_json::from_str(request.trim()).ok()?;
    let object = value.as_object()?;
    if object.get("opencode_model_list_request") != Some(&serde_json::Value::Bool(true)) {
        return None;
    }
    object
        .get("request_id")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|request_id| !request_id.is_empty())
        .map(ToOwned::to_owned)
}

fn build_repo_list(requested_path: Option<&str>) -> Result<RepoList> {
    let worker_root = canonical_conversation_root_dir()?;
    let requested = requested_path.unwrap_or("").trim();
    if requested.split('/').any(|part| part == "..") {
        bail!("folder path cannot contain ..");
    }
    let directory = if requested.is_empty() {
        worker_root.clone()
    } else {
        worker_root
            .join(requested)
            .canonicalize()
            .with_context(|| format!("failed to resolve folder `{requested}`"))?
    };
    if !directory.starts_with(&worker_root) || !directory.is_dir() {
        bail!("folder is outside the worker root");
    }
    Ok(RepoList {
        roots: vec![list_repo_root(&worker_root, &directory)?],
    })
}

fn list_repo_root(worker_root: &Path, root: &Path) -> Result<RepoListRoot> {
    let mut repos = Vec::new();
    if root == worker_root {
        repos.push(RepoListEntry {
            name: "Workspace root".to_string(),
            path: worker_root.to_string_lossy().to_string(),
            relative_path: ".".to_string(),
            is_git_repo: worker_root.join(".git").is_dir(),
        });
    }
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

fn resolve_spawn_workdir(request: &SpawnWorkerRequest, current_workdir: &Path) -> Result<PathBuf> {
    let allowed_roots = canonical_allowed_workdir_roots(current_workdir)?;
    let worker_root = allowed_roots
        .first()
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("no allowed worker root configured"))?;
    let requested = expand_home_path(clean_path_argument(&request.workdir));
    let path = if requested.is_absolute() {
        requested
    } else {
        worker_root.join(requested)
    };
    if request.create && !path.exists() {
        ensure_spawn_create_allowed(&path, &allowed_roots)?;
        fs::create_dir_all(&path)
            .with_context(|| format!("failed to create `{}`", path.display()))?;
    }
    let canonical = path
        .canonicalize()
        .with_context(|| format!("failed to resolve `{}`", path.display()))?;
    if !canonical.is_dir() {
        anyhow::bail!("`{}` is not a directory", canonical.display());
    }
    ensure_spawn_existing_allowed(&canonical, &allowed_roots)?;
    Ok(canonical)
}

fn ensure_spawn_existing_allowed(path: &Path, allowed_roots: &[PathBuf]) -> Result<()> {
    if allowed_roots
        .iter()
        .any(|root| path == root || path.starts_with(root))
    {
        return Ok(());
    }
    anyhow::bail!(
        "`{}` is outside the allowed folders ({})",
        path.display(),
        allowed_roots_text(allowed_roots)
    )
}

fn ensure_spawn_create_allowed(path: &Path, allowed_roots: &[PathBuf]) -> Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("new folder path must have a parent"))?
        .canonicalize()
        .with_context(|| format!("failed to resolve parent of `{}`", path.display()))?;
    if allowed_roots
        .iter()
        .any(|root| parent == *root || parent.starts_with(root))
    {
        return Ok(());
    }
    anyhow::bail!(
        "new folders may only be created inside the allowed folders ({})",
        allowed_roots_text(allowed_roots)
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

fn canonical_conversation_root_dir() -> Result<PathBuf> {
    let worker_root = canonical_worker_root_dir()?;
    worker_root
        .parent()
        .ok_or_else(|| anyhow::anyhow!("worker root has no parent"))?
        .canonicalize()
        .with_context(|| {
            format!(
                "failed to resolve parent workspace directory `{}`",
                worker_root.display()
            )
        })
}

fn canonical_spawn_root_dir(current_workdir: &Path) -> Result<PathBuf> {
    let root = env::var("CODEX_WORKDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| current_workdir.to_path_buf());
    root.canonicalize()
        .with_context(|| format!("failed to resolve worker root `{}`", root.display()))
}

fn canonical_allowed_workdir_roots(current_workdir: &Path) -> Result<Vec<PathBuf>> {
    let mut roots = vec![canonical_spawn_root_dir(current_workdir)?];
    for root in env_csv("NOSTR_ALLOWED_WORKDIR_ROOTS")
        .or_else(|| env_csv("NOSTR_SPAWN_ROOTS"))
        .unwrap_or_default()
    {
        let canonical = PathBuf::from(&root)
            .canonicalize()
            .with_context(|| format!("failed to resolve allowed worker root `{root}`"))?;
        if !roots.iter().any(|existing| existing == &canonical) {
            roots.push(canonical);
        }
    }
    Ok(roots)
}

fn allowed_roots_text(allowed_roots: &[PathBuf]) -> String {
    allowed_roots
        .iter()
        .map(|root| format!("`{}`", root.display()))
        .collect::<Vec<_>>()
        .join(", ")
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
                    new_session: false,
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
                    new_session: false,
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
    let new_session = raw_object
        .get("new_session")
        .or_else(|| raw_object.get("newSession"))
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
        new_session,
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
    } else if codex_config.backend == AgentBackend::Codex && codex_config.persist_sessions {
        load_codex_session(
            memory,
            peer_pubkey,
            &codex_config.working_dir,
            request,
            codex_config.backend,
        )
    } else {
        None
    };
    let memory_context = if codex_config.backend == AgentBackend::Codex && session_id.is_none() {
        memory_context(memory, peer_pubkey, recorded_id, request)
    } else {
        None
    };
    if cancel_token.is_cancelled() {
        report_codex_cancelled::<()>(messenger, peer_pubkey)
            .await
            .ok();
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

    let response_session_id = response
        .session_id
        .as_deref()
        .or(session_id.as_deref())
        .map(ToOwned::to_owned);
    send_response_and_remember(
        messenger,
        memory,
        peer_pubkey,
        response.response,
        &codex_config.working_dir,
        response_session_id.as_deref(),
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

    Some(transcript)
}

fn codex_phone_prompt(user_request: &str, _memory_context: Option<&str>) -> String {
    user_request.to_string()
}

fn media_bundle_request_text(
    user_query: &str,
    attachment_lines: &[String],
    transcripts: &[String],
    local_texts: &[String],
    voice_only: bool,
) -> String {
    let mut request_parts = Vec::new();
    if !user_query.is_empty() {
        request_parts.push(user_query.to_string());
    }

    if voice_only {
        request_parts.extend(transcripts.iter().cloned());
    } else {
        if !attachment_lines.is_empty() {
            request_parts.push(format!("Attached files:\n{}", attachment_lines.join("\n")));
        }
        if !transcripts.is_empty() {
            request_parts.push(format!(
                "Attachment transcripts:\n{}",
                transcripts.join("\n\n")
            ));
        }
    }

    if !local_texts.is_empty() {
        request_parts.push(format!(
            "Attachment text content:\n{}\n\nUse this content for the request.",
            local_texts.join("\n\n")
        ));
    }

    if request_parts.is_empty() {
        "Process the attached media and answer the user's request.".to_string()
    } else {
        request_parts.join("\n\n")
    }
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

    if let Some(response) = handle_tool_request(memory, peer_pubkey, request, workdir) {
        return Some(response);
    }

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
        "/status" | "/agent-status" => {
            return Some(local_status_text(memory, peer_pubkey, workdir));
        }
        "/git" | "/git-status" => return Some(git_status_text(workdir)),
        "/diff" => return Some(git_diff_text(workdir)),
        "/history" | "/task-history" => return Some(task_history_text(memory, peer_pubkey)),
        "/model" | "/models" | "/config" => return Some(agent_config_text()),
        "/commit" => return Some(commit_help_text(workdir)),
        "/release" => return Some(release_help_text()),
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

fn handle_tool_request(
    memory: &mut Option<MemoryStore>,
    peer_pubkey: &str,
    request: &str,
    workdir: &Path,
) -> Option<String> {
    let value = serde_json::from_str::<serde_json::Value>(request.trim()).ok()?;
    let object = value.as_object()?;
    let tool = object
        .get("tool_request")
        .or_else(|| object.get("tool"))
        .and_then(|value| value.as_str())?
        .trim();
    match tool {
        "status" => Some(local_status_text(memory, peer_pubkey, workdir)),
        "git_status" | "diff" | "read_file" | "file_browser"
            if object.get("request_id").is_some() =>
        {
            None
        }
        "git_status" => Some(git_status_text(workdir)),
        "diff" => Some(git_diff_text(workdir)),
        "history" => Some(task_history_text(memory, peer_pubkey)),
        "model_config" => Some(agent_config_text()),
        "commit_help" => Some(commit_help_text(workdir)),
        "release_help" => Some(release_help_text()),
        "read_file" => Some(read_file_request_text(object, workdir)),
        _ => Some(format!("Unknown tool request `{tool}`.")),
    }
}

fn structured_tool_result(
    memory: &mut Option<MemoryStore>,
    peer_pubkey: &str,
    request: &str,
    workdir: &Path,
) -> Option<ToolResult> {
    let value = serde_json::from_str::<serde_json::Value>(request.trim()).ok()?;
    let object = value.as_object()?;
    let tool = object.get("tool_request")?.as_str()?.trim();
    let request_id = object.get("request_id")?.as_str()?.trim();
    if request_id.is_empty() {
        return None;
    }

    let data = match tool {
        "git_status" => git_status_data(workdir),
        "diff" => git_diff_data(workdir),
        "read_file" => object
            .get("path")
            .and_then(serde_json::Value::as_str)
            .map(|path| read_file_data(workdir, path))
            .unwrap_or_else(|| serde_json::json!({ "error": "A file path is required." })),
        "file_browser" => file_browser_data(
            workdir,
            object.get("path").and_then(serde_json::Value::as_str),
        ),
        "system_status" => worker_system_status_data(
            workdir,
            object
                .get("history_range")
                .and_then(serde_json::Value::as_str)
                .unwrap_or("24h"),
        ),
        _ => serde_json::json!({
            "text": handle_tool_request(memory, peer_pubkey, request, workdir)
                .unwrap_or_else(|| format!("Unknown tool request `{tool}`.")),
        }),
    };

    Some(ToolResult {
        tool: tool.to_string(),
        request_id: request_id.to_string(),
        workdir: workdir.to_string_lossy().to_string(),
        data,
    })
}

fn collect_system_status_sample() -> serde_json::Value {
    let sampled_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let first_cpu = read_cpu_counters();
    std::thread::sleep(Duration::from_millis(250));
    let cpu_percent = first_cpu
        .zip(read_cpu_counters())
        .and_then(|(first, second)| {
            let total = second.0.checked_sub(first.0)?;
            let idle = second.1.checked_sub(first.1)?;
            (total > 0).then(|| 100.0 * (total.saturating_sub(idle) as f64) / total as f64)
        });
    let memory = read_meminfo();
    let sample = serde_json::json!({
        "sampled_at": sampled_at,
        "uptime_seconds": read_proc_number("/proc/uptime").map(|value| value as u64),
        "cpu_percent": cpu_percent,
        "memory": memory.as_ref().map(|values| serde_json::json!({
            "used_bytes": values.get("MemTotal").unwrap_or(&0).saturating_sub(*values.get("MemAvailable").unwrap_or(&0)),
            "total_bytes": values.get("MemTotal").unwrap_or(&0),
        })),
        "swap": memory.as_ref().map(|values| serde_json::json!({
            "used_bytes": values.get("SwapTotal").unwrap_or(&0).saturating_sub(*values.get("SwapFree").unwrap_or(&0)),
            "total_bytes": values.get("SwapTotal").unwrap_or(&0),
        })),
        "load": fs::read_to_string("/proc/loadavg").ok().map(|raw| raw.split_whitespace().take(3).filter_map(|value| value.parse::<f64>().ok()).collect::<Vec<_>>()),
        "filesystem": root_filesystem_status(),
        "disk_io": read_disk_io(),
        "networks": read_networks(),
        "temperatures": read_temperatures(),
        "battery": read_battery_status(),
        "system": system_information(),
    });
    sample
}

fn system_information() -> serde_json::Value {
    let os_name = fs::read_to_string("/etc/os-release")
        .ok()
        .and_then(|contents| {
            contents.lines().find_map(|line| {
                line.strip_prefix("PRETTY_NAME=")
                    .map(|value| value.trim_matches('"').to_string())
            })
        })
        .unwrap_or_else(|| "Linux".to_string());
    serde_json::json!({
        "hostname": fs::read_to_string("/proc/sys/kernel/hostname").ok().map(|value| value.trim().to_string()),
        "os_name": os_name,
        "kernel_version": fs::read_to_string("/proc/sys/kernel/osrelease").ok().map(|value| value.trim().to_string()),
        "architecture": std::env::consts::ARCH,
    })
}

fn worker_system_status_data(workdir: &Path, history_range: &str) -> serde_json::Value {
    let history = read_system_status_history(&worker_state_path(workdir, "system-status.jsonl"));
    let current = history
        .last()
        .cloned()
        .unwrap_or_else(|| serde_json::json!({}));
    let range = SystemStatusHistoryRange::parse(history_range);
    serde_json::json!({
        "current": current,
        "history": range.select(history),
        "history_range": range.name(),
    })
}

#[derive(Clone, Copy)]
enum SystemStatusHistoryRange {
    OneHour,
    Day,
    Week,
    All,
}

impl SystemStatusHistoryRange {
    fn parse(value: &str) -> Self {
        match value {
            "1h" => Self::OneHour,
            "1w" => Self::Week,
            "all" => Self::All,
            _ => Self::Day,
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::OneHour => "1h",
            Self::Day => "24h",
            Self::Week => "1w",
            Self::All => "all",
        }
    }

    fn select(self, history: Vec<serde_json::Value>) -> Vec<serde_json::Value> {
        let seconds = match self {
            Self::OneHour => Some(60 * 60),
            Self::Day => Some(24 * 60 * 60),
            Self::Week => Some(7 * 24 * 60 * 60),
            Self::All => None,
        };
        let latest = history
            .last()
            .and_then(|entry| entry.get("sampled_at"))
            .and_then(serde_json::Value::as_u64)
            .unwrap_or_default();
        let entries = history
            .into_iter()
            .filter(|entry| {
                seconds.is_none_or(|window| {
                    entry
                        .get("sampled_at")
                        .and_then(serde_json::Value::as_u64)
                        .is_some_and(|timestamp| latest.saturating_sub(timestamp) <= window)
                })
            })
            .collect::<Vec<_>>();
        let maximum_points = match self {
            Self::OneHour => 6,
            Self::Day => 24 * 6,
            Self::Week => 7 * 24,
            // Gift-wrapped Nostr messages have a practical size limit. Keep
            // all-history charts useful without making their result undeliverable.
            Self::All => 192,
        };
        downsample_system_status_history(entries, maximum_points)
            .iter()
            .map(compact_system_status_history_entry)
            .collect()
    }
}

fn compact_system_status_history_entry(sample: &serde_json::Value) -> serde_json::Value {
    serde_json::json!({
        "sampled_at": sample.get("sampled_at"),
        "cpu_percent": sample.get("cpu_percent"),
        "memory": {
            "used_bytes": sample.pointer("/memory/used_bytes"),
            "total_bytes": sample.pointer("/memory/total_bytes"),
        },
        "swap": {
            "used_bytes": sample.pointer("/swap/used_bytes"),
            "total_bytes": sample.pointer("/swap/total_bytes"),
        },
        "filesystem": {
            "used_bytes": sample.pointer("/filesystem/used_bytes"),
            "total_bytes": sample.pointer("/filesystem/total_bytes"),
        },
    })
}

fn downsample_system_status_history(
    history: Vec<serde_json::Value>,
    maximum_points: usize,
) -> Vec<serde_json::Value> {
    if history.len() <= maximum_points {
        return history;
    }
    let bucket_size = history.len().div_ceil(maximum_points);
    history
        .chunks(bucket_size)
        .filter_map(|bucket| bucket.last().cloned())
        .collect()
}

fn read_system_status_history(path: &Path) -> Vec<serde_json::Value> {
    fs::read_to_string(path)
        .unwrap_or_default()
        .lines()
        .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
        .collect()
}

fn append_system_status_sample(path: &Path, sample: &serde_json::Value) {
    let line = match serde_json::to_string(sample) {
        Ok(line) => line,
        Err(err) => {
            warn!("failed to serialize system status sample: {err}");
            return;
        }
    };
    let mut contents = fs::read_to_string(path).unwrap_or_default();
    contents.push_str(&line);
    contents.push('\n');
    if contents.len() > SYSTEM_STATUS_HISTORY_MAX_BYTES {
        let start = contents
            .len()
            .saturating_sub(SYSTEM_STATUS_HISTORY_MAX_BYTES);
        contents = contents[start..]
            .split_once('\n')
            .map(|(_, remainder)| remainder.to_string())
            .unwrap_or_default();
    }
    if let Some(parent) = path.parent() {
        if let Err(err) = fs::create_dir_all(parent) {
            warn!(path = %path.display(), "failed to create system status history directory: {err}");
        }
    }
    if let Err(err) = fs::write(path, &contents) {
        warn!(path = %path.display(), "failed to save system status history: {err}");
    }
}

fn read_cpu_counters() -> Option<(u64, u64)> {
    let fields = fs::read_to_string("/proc/stat")
        .ok()?
        .lines()
        .next()?
        .split_whitespace()
        .skip(1)
        .filter_map(|value| value.parse::<u64>().ok())
        .collect::<Vec<_>>();
    let total = fields.iter().sum();
    Some((
        total,
        fields
            .get(3)
            .copied()
            .unwrap_or_default()
            .saturating_add(fields.get(4).copied().unwrap_or_default()),
    ))
}

fn read_proc_number(path: &str) -> Option<f64> {
    fs::read_to_string(path)
        .ok()?
        .split_whitespace()
        .next()?
        .parse()
        .ok()
}

fn read_meminfo() -> Option<HashMap<String, u64>> {
    let values = fs::read_to_string("/proc/meminfo")
        .ok()?
        .lines()
        .filter_map(|line| {
            let (name, value) = line.split_once(':')?;
            Some((
                name.to_string(),
                value
                    .split_whitespace()
                    .next()?
                    .parse::<u64>()
                    .ok()?
                    .saturating_mul(1024),
            ))
        })
        .collect::<HashMap<_, _>>();
    Some(values)
}

#[cfg(unix)]
fn root_filesystem_status() -> Option<serde_json::Value> {
    let path = std::ffi::CString::new("/").ok()?;
    let mut stat = std::mem::MaybeUninit::<libc::statvfs>::uninit();
    (unsafe { libc::statvfs(path.as_ptr(), stat.as_mut_ptr()) } == 0).then(|| {
        let stat = unsafe { stat.assume_init() };
        let total = stat.f_blocks.saturating_mul(stat.f_frsize);
        let available = stat.f_bavail.saturating_mul(stat.f_frsize);
        serde_json::json!({"mount": "/", "total_bytes": total, "available_bytes": available, "used_bytes": total.saturating_sub(available)})
    })
}

#[cfg(not(unix))]
fn root_filesystem_status() -> Option<serde_json::Value> {
    None
}

fn read_disk_io() -> serde_json::Value {
    let (read_sectors, write_sectors) = fs::read_dir("/sys/block")
        .ok()
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with("loop")
                || name.starts_with("ram")
                || name.starts_with("zram")
                || name.starts_with("dm-")
                || name.starts_with("md")
            {
                return None;
            }
            Some(
                fs::read_to_string(entry.path().join("stat"))
                    .ok()?
                    .split_whitespace()
                    .filter_map(|value| value.parse::<u64>().ok())
                    .collect::<Vec<_>>(),
            )
        })
        .fold((0_u64, 0_u64), |(read, write), values| {
            (
                read.saturating_add(values.get(2).copied().unwrap_or_default()),
                write.saturating_add(values.get(6).copied().unwrap_or_default()),
            )
        });
    serde_json::json!({"read_bytes": read_sectors.saturating_mul(512), "written_bytes": write_sectors.saturating_mul(512)})
}

fn read_networks() -> Vec<serde_json::Value> {
    let Ok(raw) = fs::read_to_string("/proc/net/dev") else {
        return vec![];
    };
    raw.lines().skip(2).filter_map(|line| {
        let (name, values) = line.split_once(':')?;
        let values = values.split_whitespace().filter_map(|value| value.parse::<u64>().ok()).collect::<Vec<_>>();
        (name.trim() != "lo").then(|| serde_json::json!({"name": name.trim(), "received_bytes": values.first().copied().unwrap_or_default(), "transmitted_bytes": values.get(8).copied().unwrap_or_default()}))
    }).collect()
}

fn read_temperatures() -> Vec<serde_json::Value> {
    fs::read_dir("/sys/class/thermal")
        .ok()
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let path = entry.path();
            let milli_celsius = fs::read_to_string(path.join("temp"))
                .ok()?
                .trim()
                .parse::<f64>()
                .ok()?;
            let label = fs::read_to_string(path.join("type"))
                .ok()
                .map(|label| label.trim().to_string())
                .unwrap_or_else(|| entry.file_name().to_string_lossy().to_string());
            Some(serde_json::json!({"label": label, "celsius": milli_celsius / 1000.0}))
        })
        .collect()
}

fn read_battery_status() -> Option<serde_json::Value> {
    fs::read_dir("/sys/class/power_supply").ok()?.filter_map(Result::ok).find_map(|entry| {
        let path = entry.path();
        (fs::read_to_string(path.join("type")).ok()?.trim() == "Battery").then(|| serde_json::json!({
            "capacity_percent": fs::read_to_string(path.join("capacity")).ok().and_then(|value| value.trim().parse::<u8>().ok()),
            "status": fs::read_to_string(path.join("status")).ok().map(|value| value.trim().to_string()),
        }))
    })
}

fn git_status_data(workdir: &Path) -> serde_json::Value {
    let branch = run_git(workdir, &["branch", "--show-current"]).unwrap_or_default();
    let latest_hash = run_git(workdir, &["log", "-1", "--format=%h"]).unwrap_or_default();
    let latest_subject = run_git(workdir, &["log", "-1", "--format=%s"]).unwrap_or_default();
    let status = match run_git(
        workdir,
        &["status", "--porcelain=v1", "--untracked-files=all"],
    ) {
        Ok(status) => status,
        Err(error) => return serde_json::json!({ "error": error }),
    };
    let files = status
        .lines()
        .filter(|line| line.len() >= 3)
        .take(500)
        .map(|line| {
            let index_status = &line[0..1];
            let worktree_status = &line[1..2];
            let path = line[3..].split(" -> ").last().unwrap_or_default();
            serde_json::json!({
                "path": path,
                "index_status": index_status,
                "worktree_status": worktree_status,
                "staged": index_status != " " && index_status != "?",
                "untracked": index_status == "?" && worktree_status == "?",
            })
        })
        .collect::<Vec<_>>();

    serde_json::json!({
        "branch": branch,
        "clean": files.is_empty(),
        "latest": { "hash": latest_hash, "subject": latest_subject },
        "files": files,
    })
}

fn git_diff_data(workdir: &Path) -> serde_json::Value {
    let name_status = run_git(workdir, &["diff", "HEAD", "--name-status", "--", "."])
        .or_else(|_| run_git(workdir, &["diff", "--name-status", "--", "."]));
    let name_status = match name_status {
        Ok(value) => value,
        Err(error) => return serde_json::json!({ "error": error }),
    };
    let numstat = run_git(workdir, &["diff", "HEAD", "--numstat", "--", "."])
        .or_else(|_| run_git(workdir, &["diff", "--numstat", "--", "."]))
        .unwrap_or_default();
    let stats = numstat
        .lines()
        .filter_map(|line| {
            let mut parts = line.splitn(3, '\t');
            Some((
                parts.next()?.to_string(),
                parts.next()?.to_string(),
                parts.next()?.to_string(),
            ))
        })
        .map(|(additions, deletions, path)| (path, (additions, deletions)))
        .collect::<HashMap<_, _>>();

    let mut remaining_patch_chars = 36000_usize;
    let files = name_status
        .lines()
        .take(100)
        .filter_map(|line| {
            let mut parts = line.split('\t');
            let status = parts.next()?.to_string();
            let path = parts.last()?.to_string();
            let patch = run_git(workdir, &["diff", "HEAD", "--", &path])
                .or_else(|_| run_git(workdir, &["diff", "--", &path]))
                .unwrap_or_default();
            let patch = if remaining_patch_chars == 0 {
                "[patch omitted: result size limit reached]".to_string()
            } else {
                let patch = truncate_text(&patch, remaining_patch_chars.min(12000));
                remaining_patch_chars = remaining_patch_chars.saturating_sub(patch.chars().count());
                patch
            };
            let (additions, deletions) = stats
                .get(&path)
                .cloned()
                .unwrap_or_else(|| ("0".to_string(), "0".to_string()));
            Some(serde_json::json!({
                "path": path,
                "status": status,
                "additions": additions,
                "deletions": deletions,
                "patch": patch,
            }))
        })
        .collect::<Vec<_>>();

    serde_json::json!({ "files": files })
}

fn read_file_data(workdir: &Path, requested: &str) -> serde_json::Value {
    let path = PathBuf::from(clean_path_argument(requested));
    let path = if path.is_absolute() {
        path
    } else {
        workdir.join(path)
    };
    let canonical = match path.canonicalize() {
        Ok(path) => path,
        Err(error) => {
            return serde_json::json!({ "error": format!("Could not read `{requested}`: {error}") })
        }
    };
    let root = workdir
        .canonicalize()
        .unwrap_or_else(|_| workdir.to_path_buf());
    if !canonical.starts_with(&root) {
        return serde_json::json!({ "error": format!("Refusing to read outside `{}`.", root.display()) });
    }
    match fs::read_to_string(&canonical) {
        Ok(content) => {
            let relative = canonical.strip_prefix(&root).unwrap_or(&canonical);
            let line_count = content.lines().count();
            let truncated = content.chars().count() > 40000;
            serde_json::json!({
                "path": relative.to_string_lossy(),
                "content": truncate_text(&content, 40000),
                "line_count": line_count,
                "truncated": truncated,
            })
        }
        Err(error) => {
            serde_json::json!({ "error": format!("Could not read `{}`: {error}", canonical.display()) })
        }
    }
}

fn file_browser_data(workdir: &Path, requested: Option<&str>) -> serde_json::Value {
    const MAX_ENTRIES: usize = 500;
    const MAX_SERIALIZED_ENTRY_BYTES: usize = 16000;
    let root = match workdir.canonicalize() {
        Ok(root) => root,
        Err(error) => {
            return serde_json::json!({ "error": format!("Could not open repo: {error}") })
        }
    };
    let requested = requested.unwrap_or_default();
    let directory = if requested.trim().is_empty() {
        root.clone()
    } else {
        root.join(clean_path_argument(requested))
    };
    let directory = match directory.canonicalize() {
        Ok(directory) if directory.starts_with(&root) && directory.is_dir() => directory,
        Ok(_) => return serde_json::json!({ "error": "Folder is outside the repository." }),
        Err(error) => {
            return serde_json::json!({ "error": format!("Could not open `{requested}`: {error}") })
        }
    };
    let mut entries = Vec::new();
    let mut serialized_entry_bytes = 0;
    let mut truncated = false;
    let Ok(read_dir) = fs::read_dir(&directory) else {
        return serde_json::json!({ "error": format!("Could not read `{}`", directory.display()) });
    };
    let mut children = read_dir.filter_map(|entry| entry.ok()).collect::<Vec<_>>();
    children.sort_by_key(|entry| entry.file_name().to_string_lossy().to_ascii_lowercase());
    for entry in children {
        if entries.len() >= MAX_ENTRIES {
            truncated = true;
            break;
        }
        let name = entry.file_name();
        let name = name.to_string_lossy();
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_symlink() || file_browser_entry_excluded(&name, file_type.is_dir()) {
            continue;
        }
        let value = serde_json::json!({
            "path": name,
            "is_dir": file_type.is_dir(),
        });
        let value_bytes = value.to_string().len() + 1;
        if serialized_entry_bytes + value_bytes > MAX_SERIALIZED_ENTRY_BYTES {
            truncated = true;
            break;
        }
        serialized_entry_bytes += value_bytes;
        entries.push(value);
    }
    serde_json::json!({
        "directory": directory.strip_prefix(&root).unwrap_or(&directory).to_string_lossy(),
        "entries": entries,
        "truncated": truncated,
    })
}

fn file_browser_entry_excluded(name: &str, is_dir: bool) -> bool {
    if is_dir
        && matches!(
            name,
            ".git"
                | ".nostr-codex"
                | ".dart_tool"
                | ".gradle"
                | ".idea"
                | "build"
                | "target"
                | "node_modules"
                | "Pods"
        )
    {
        return true;
    }
    let lower = name.to_ascii_lowercase();
    !is_dir
        && (name == ".env"
            || name.starts_with(".env.")
            || name.ends_with(".key")
            || name.ends_with(".pem")
            || [
                ".apk",
                ".aab",
                ".bin",
                ".db",
                ".gif",
                ".ico",
                ".jpeg",
                ".jpg",
                ".keystore",
                ".mp3",
                ".mp4",
                ".ogg",
                ".pdf",
                ".png",
                ".sqlite",
                ".sqlite3",
                ".wav",
                ".webm",
                ".webp",
                ".zip",
            ]
            .iter()
            .any(|extension| lower.ends_with(extension)))
}

fn git_status_text(workdir: &Path) -> String {
    let branch = run_git(workdir, &["branch", "--show-current"]).unwrap_or_else(|err| err);
    let latest = run_git(workdir, &["log", "--oneline", "-1"]).unwrap_or_else(|err| err);
    let porcelain = run_git(workdir, &["status", "--short"]).unwrap_or_else(|err| err);
    let staged = run_git(workdir, &["diff", "--cached", "--stat"]).unwrap_or_else(|err| err);
    format!(
        "Git status\nBranch: {}\nLatest: {}\n\nDirty files:\n{}\n\nStaged:\n{}",
        branch.trim().if_empty("unknown"),
        latest.trim().if_empty("none"),
        porcelain.trim().if_empty("clean"),
        staged.trim().if_empty("none")
    )
}

fn git_diff_text(workdir: &Path) -> String {
    let stat = run_git(workdir, &["diff", "--stat"]).unwrap_or_else(|err| err);
    let diff = run_git(workdir, &["diff", "--", "."]).unwrap_or_else(|err| err);
    format!(
        "Git diff\n{}\n\n{}",
        stat.trim().if_empty("No unstaged diff."),
        truncate_text(diff.trim().if_empty("No patch."), 18000)
    )
}

fn commit_help_text(workdir: &Path) -> String {
    let status = git_status_text(workdir);
    let diff = run_git(workdir, &["diff", "--stat"]).unwrap_or_else(|err| err);
    format!(
        "Commit prep only. Review this, edit a commit message on the phone, then ask OpenCode to commit.\n\n{}\n\nSuggested message:\n{}",
        status,
        suggest_commit_message(&diff)
    )
}

fn release_help_text() -> String {
    "Release workflow buttons send prompts only; the agent still performs checks. Typical flow: analyze/test, build APK, package assets, create GitHub release, install worker, restart service.".to_string()
}

fn agent_config_text() -> String {
    let backend = env::var("AGENT_BACKEND").unwrap_or_else(|_| "opencode".to_string());
    let opencode_bin = env::var("OPENCODE_BIN").unwrap_or_else(|_| "opencode".to_string());
    let agent = env::var("OPENCODE_AGENT").unwrap_or_else(|_| "build".to_string());
    let model = env::var("OPENCODE_MODEL").unwrap_or_else(|_| "default".to_string());
    format!(
        "Agent config\nBackend: {backend}\nOpenCode CLI: {opencode_bin}\nAgent: {agent}\nModel: {model}\n\nSubagents are configured in OpenCode config/skills; this app can show current env-selected agent/model."
    )
}

fn task_history_text(memory: &Option<MemoryStore>, peer_pubkey: &str) -> String {
    match memory.as_ref() {
        Some(memory) => memory
            .history_text(peer_pubkey, 12)
            .unwrap_or_else(|err| format!("Task history failed: {err:#}")),
        None => "Task history requires memory to be enabled.".to_string(),
    }
}

fn read_file_request_text(
    object: &serde_json::Map<String, serde_json::Value>,
    workdir: &Path,
) -> String {
    let Some(path) = object.get("path").and_then(|value| value.as_str()) else {
        return "Read file requires a `path`.".to_string();
    };
    read_file_text(workdir, path)
}

fn read_file_text(workdir: &Path, requested: &str) -> String {
    let path = PathBuf::from(clean_path_argument(requested));
    let path = if path.is_absolute() {
        path
    } else {
        workdir.join(path)
    };
    let canonical = match path.canonicalize() {
        Ok(path) => path,
        Err(err) => return format!("Could not read `{requested}`: {err}"),
    };
    let root = workdir
        .canonicalize()
        .unwrap_or_else(|_| workdir.to_path_buf());
    if !canonical.starts_with(&root) {
        return format!("Refusing to read outside `{}`.", root.display());
    }
    match fs::read_to_string(&canonical) {
        Ok(raw) => format!("{}\n\n{}", canonical.display(), truncate_text(&raw, 18000)),
        Err(err) => format!("Could not read `{}`: {err}", canonical.display()),
    }
}

fn run_git(workdir: &Path, args: &[&str]) -> std::result::Result<String, String> {
    let output = StdCommand::new("git")
        .args(args)
        .current_dir(workdir)
        .output()
        .map_err(|err| format!("git {} failed: {err}", args.join(" ")))?;
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if output.status.success() {
        Ok(stdout)
    } else if stderr.is_empty() {
        Err(format!(
            "git {} exited with {}",
            args.join(" "),
            output.status
        ))
    } else {
        Err(stderr)
    }
}

fn suggest_commit_message(diff_stat: &str) -> &'static str {
    if diff_stat.trim().is_empty() {
        "chore: no changes to commit"
    } else {
        "feat: update mobile OpenCode tools"
    }
}

fn truncate_text(value: &str, max_chars: usize) -> String {
    let mut chars = value.chars();
    let mut output = chars.by_ref().take(max_chars).collect::<String>();
    if chars.next().is_some() {
        output.push_str("\n[truncated]");
    }
    output
}

trait IfEmpty {
    fn if_empty<'a>(&'a self, fallback: &'a str) -> &'a str;
}

impl IfEmpty for str {
    fn if_empty<'a>(&'a self, fallback: &'a str) -> &'a str {
        if self.is_empty() {
            fallback
        } else {
            self
        }
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
            status.push_str(&format!("\nAgent session: {session}"));
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
    let pairing_confirmation = pairing_secret
        .filter(|secret| !secret.trim().is_empty())
        .map(pairing_confirmation_code);
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
        payload["pairing_confirmation"] = serde_json::Value::String(
            pairing_confirmation
                .as_deref()
                .expect("pairing confirmation exists with pairing secret")
                .to_string(),
        );
    }
    let Ok(payload) = serde_json::to_string(&payload) else {
        warn!("failed to serialize worker QR payload");
        return;
    };

    let code = match QrCode::new(payload.as_bytes()) {
        Ok(code) => code,
        Err(err) => {
            warn!("failed to build worker target QR: {err:#}");
            return;
        }
    };

    if env_bool("NOSTR_CODEX_QR_PRINT", true) {
        if let Some(confirmation) = &pairing_confirmation {
            println!("First-owner pairing confirmation: {confirmation}");
        }
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
    if pairing_confirmation.is_some() {
        set_private_file_permissions(&qr_path);
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
    if pairing_confirmation.is_some() {
        set_private_file_permissions(&payload_path);
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
    _request: &str,
    backend: AgentBackend,
) -> Option<String> {
    if backend == AgentBackend::OpenCode {
        return None;
    }

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
    cwd: String,
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
                best_session.last_timestamp.as_str(),
                best_session.started_at.as_str(),
                best_session.cwd.as_str(),
                best_session.session_id.as_str(),
            ) >= (
                session.last_timestamp.as_str(),
                session.started_at.as_str(),
                session.cwd.as_str(),
                session.session_id.as_str(),
            ) => {}
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
        cwd: cwd.to_string(),
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

async fn send_response(messenger: &NostrMessenger, receiver_pubkey: &str, response: String) {
    if let Err(err) =
        send_application_wire(messenger, receiver_pubkey, WireMessage::response(response)).await
    {
        error!("failed to send response: {err:#}");
    }
}

async fn send_status(messenger: &NostrMessenger, receiver_pubkey: &str, status: &str) {
    let status = status.trim();
    if status.is_empty() {
        return;
    }
    if let Err(err) =
        send_application_wire(messenger, receiver_pubkey, WireMessage::status(status)).await
    {
        warn!("failed to send status: {err:#}");
    }
}

async fn send_response_and_remember(
    messenger: &NostrMessenger,
    memory: &mut Option<MemoryStore>,
    receiver_pubkey: &str,
    response: String,
    workdir: &Path,
    session_id: Option<&str>,
) {
    let wire = WireMessage::routed_response(
        response.clone(),
        workdir.to_string_lossy().to_string(),
        session_id.map(ToOwned::to_owned),
    );
    match send_application_wire(messenger, receiver_pubkey, wire).await {
        Ok(()) => {
            if let Some(memory) = memory.as_mut() {
                // FIPS envelopes have no Nostr event ID. The local record only
                // needs a stable outgoing identifier for memory bookkeeping.
                let event_id = format!("outbound:{}", generate_pairing_secret());
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
) -> std::result::Result<CodexRunResult, ()> {
    let first_attempt_config = codex_config_for_first_attempt(codex_config, session_id);
    let result = match run_codex_session_with_status(
        messenger,
        receiver_pubkey,
        prompt,
        &first_attempt_config,
        session_id,
        cancel_token,
    )
    .await
    {
        Ok(result) => result,
        Err(err) if is_codex_cancelled_error(&err) => {
            return report_codex_cancelled(messenger, receiver_pubkey).await;
        }
        Err(err) if is_codex_usage_limit_error(&err) => {
            match retry_codex_with_usage_limit_fallback(
                messenger,
                receiver_pubkey,
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
        Err(err) if is_opencode_busy_error(&err) => {
            return report_opencode_busy(messenger, receiver_pubkey, err).await;
        }
        Err(err) if session_id.is_some() => {
            warn!("agent resume failed; clearing session and retrying once: {err:#}");
            send_status(
                messenger,
                receiver_pubkey,
                "Resume failed; starting a fresh agent turn.",
            )
            .await;
            if let Some(memory) = memory.as_mut() {
                if let Err(clear_err) =
                    memory.clear_codex_session(receiver_pubkey, &codex_config.working_dir)
                {
                    warn!("failed to clear agent session: {clear_err:#}");
                }
            }
            match run_codex_session_with_status(
                messenger,
                receiver_pubkey,
                prompt,
                codex_config,
                None,
                cancel_token,
            )
            .await
            {
                Ok(result) => result,
                Err(err) if is_codex_cancelled_error(&err) => {
                    return report_codex_cancelled(messenger, receiver_pubkey).await;
                }
                Err(err) if is_codex_usage_limit_error(&err) => {
                    match retry_codex_with_usage_limit_fallback(
                        messenger,
                        receiver_pubkey,
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

    if codex_config.backend == AgentBackend::Codex {
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
                    warn!("failed to save agent session: {err:#}");
                }
            }
        }
    }

    Ok(result)
}

async fn run_codex_session_with_status(
    messenger: &NostrMessenger,
    receiver_pubkey: &str,
    prompt: &str,
    codex_config: &CodexConfig,
    session_id: Option<&str>,
    cancel_token: &CodexCancelToken,
) -> Result<CodexRunResult> {
    let (tx, mut rx) = mpsc::unbounded_channel();
    let mut reporter = CodexStatusReporter::new();
    reporter
        .send(
            messenger,
            receiver_pubkey,
            agent_start_status(codex_config.backend, session_id.is_some()).to_string(),
            true,
        )
        .await;

    let run = run_codex_session_with_cancel_and_events(
        prompt,
        codex_config,
        session_id,
        Some(cancel_token),
        Some(tx),
    );
    tokio::pin!(run);

    let mut events_open = true;
    loop {
        tokio::select! {
            result = &mut run => return result,
            event = rx.recv(), if events_open => {
                match event {
                    Some(event) => {
                        reporter.handle(messenger, receiver_pubkey, &event).await;
                    }
                    None => events_open = false,
                }
            }
        }
    }
}

fn agent_start_status(backend: AgentBackend, resume: bool) -> &'static str {
    match (backend, resume) {
        (AgentBackend::OpenCode, true) => "Resuming OpenCode session...",
        (AgentBackend::OpenCode, false) => "Starting OpenCode...",
        (AgentBackend::Codex, true) => "Resuming Codex session...",
        (AgentBackend::Codex, false) => "Starting Codex...",
    }
}

struct CodexStatusReporter {
    last_sent_at: Option<Instant>,
    last_message: Option<String>,
}

impl CodexStatusReporter {
    fn new() -> Self {
        Self {
            last_sent_at: None,
            last_message: None,
        }
    }

    async fn handle(
        &mut self,
        messenger: &NostrMessenger,
        receiver_pubkey: &str,
        event: &serde_json::Value,
    ) {
        let Some((message, force)) = codex_status_from_event(event) else {
            return;
        };
        self.send(messenger, receiver_pubkey, message, force).await;
    }

    async fn send(
        &mut self,
        messenger: &NostrMessenger,
        receiver_pubkey: &str,
        message: String,
        force: bool,
    ) {
        if self.last_message.as_deref() == Some(message.as_str()) {
            return;
        }
        if !force {
            if let Some(last_sent_at) = self.last_sent_at {
                if last_sent_at.elapsed() < CODEX_STATUS_MIN_INTERVAL {
                    return;
                }
            }
        }
        send_status(messenger, receiver_pubkey, &message).await;
        self.last_sent_at = Some(Instant::now());
        self.last_message = Some(message);
    }
}

fn codex_status_from_event(event: &serde_json::Value) -> Option<(String, bool)> {
    match event.get("type").and_then(serde_json::Value::as_str) {
        Some("session.status") => match event
            .pointer("/properties/status/type")
            .and_then(serde_json::Value::as_str)
        {
            Some("busy") => Some(("OpenCode is working.".to_string(), false)),
            Some("retry") => Some((
                format!(
                    "OpenCode is retrying: {}",
                    status_detail(
                        event
                            .pointer("/properties/status/message")
                            .and_then(serde_json::Value::as_str)
                    )
                ),
                true,
            )),
            Some("idle") => Some(("OpenCode is finishing.".to_string(), true)),
            _ => None,
        },
        Some("message.part.updated") => {
            let part = event.pointer("/properties/part")?;
            match part.get("type").and_then(serde_json::Value::as_str) {
                Some("tool") => {
                    let state = part
                        .pointer("/state/status")
                        .and_then(serde_json::Value::as_str)?;
                    let title = part
                        .pointer("/state/title")
                        .and_then(serde_json::Value::as_str)
                        .or_else(|| part.get("tool").and_then(serde_json::Value::as_str))
                        .unwrap_or("tool");
                    match state {
                        "running" => Some((
                            format!("OpenCode: running {}.", status_detail(Some(title))),
                            false,
                        )),
                        "completed" => Some((
                            format!("OpenCode: finished {}.", status_detail(Some(title))),
                            true,
                        )),
                        "error" => Some((
                            format!("OpenCode: {} failed.", status_detail(Some(title))),
                            true,
                        )),
                        _ => None,
                    }
                }
                Some("text") | Some("reasoning")
                    if event.pointer("/properties/delta").is_some() =>
                {
                    Some(("OpenCode is drafting a response.".to_string(), false))
                }
                _ => None,
            }
        }
        Some("todo.updated") => {
            let todos = event
                .pointer("/properties/todos")
                .and_then(serde_json::Value::as_array)?;
            Some((format_todo_status(todos), true))
        }
        Some("permission.updated") => Some((
            format!(
                "OpenCode needs permission: {}.",
                status_detail(
                    event
                        .pointer("/properties/title")
                        .and_then(serde_json::Value::as_str)
                )
            ),
            true,
        )),
        Some("session.diff") => event
            .pointer("/properties/diff")
            .and_then(serde_json::Value::as_array)
            .map(|files| (format!("OpenCode changed {} file(s).", files.len()), false)),
        Some("turn.started") => Some(("Codex started.".to_string(), false)),
        Some("turn.completed") => Some(("Codex finished; sending response.".to_string(), true)),
        Some("turn.failed") | Some("error") => Some(("Codex failed.".to_string(), true)),
        Some("item.started") => {
            codex_item_status(event).map(|message| (message.to_string(), false))
        }
        _ => None,
    }
}

fn status_detail(value: Option<&str>) -> String {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.chars().take(96).collect())
        .unwrap_or_else(|| "working".to_string())
}

fn format_todo_status(todos: &[serde_json::Value]) -> String {
    const MAX_VISIBLE_TODOS: usize = 8;

    let completed = todos
        .iter()
        .filter(|todo| todo.get("status").and_then(serde_json::Value::as_str) == Some("completed"))
        .count();
    let mut lines = vec![format!(
        "OpenCode todos: {completed}/{} complete",
        todos.len()
    )];

    for todo in todos.iter().take(MAX_VISIBLE_TODOS) {
        let status = todo
            .get("status")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("pending");
        let marker = match status {
            "completed" => "[x]",
            "in_progress" => "[~]",
            _ => "[ ]",
        };
        let content = todo
            .get("content")
            .or_else(|| todo.get("title"))
            .or_else(|| todo.get("text"))
            .and_then(serde_json::Value::as_str)
            .map(|value| status_detail(Some(value)))
            .unwrap_or_else(|| "Unnamed task".to_string());
        lines.push(format!("{marker} {content}"));
    }
    if todos.len() > MAX_VISIBLE_TODOS {
        lines.push(format!("... and {} more", todos.len() - MAX_VISIBLE_TODOS));
    }

    lines.join("\n")
}

fn codex_item_status(event: &serde_json::Value) -> Option<&'static str> {
    let text = event.to_string().to_ascii_lowercase();
    if text.contains("flutter analyze")
        || text.contains("cargo test")
        || text.contains("cargo clippy")
        || text.contains("dart format")
        || text.contains("cargo fmt")
    {
        return Some("Running checks.");
    }
    if text.contains("flutter build") || text.contains("cargo build") {
        return Some("Building.");
    }
    if text.contains("apply_patch") || text.contains("patch") {
        return Some("Editing files.");
    }
    if text.contains("\"rg\"")
        || text.contains("rg ")
        || text.contains("rg -")
        || text.contains("git status")
        || text.contains("\"sed\"")
        || text.contains("sed ")
        || text.contains("sed -")
        || text.contains("\"cat\"")
        || text.contains("cat ")
        || text.contains("\"ls\"")
        || text.contains("ls ")
        || text.contains("\"grep\"")
        || text.contains("grep ")
    {
        return Some("Inspecting code.");
    }
    if text.contains("tool") || text.contains("function_call") || text.contains("exec") {
        return Some("Using tools.");
    }
    None
}

fn codex_config_for_first_attempt(
    codex_config: &CodexConfig,
    session_id: Option<&str>,
) -> CodexConfig {
    if codex_config.backend != AgentBackend::Codex
        || session_id.is_none()
        || codex_config.timeout <= CODEX_RESUME_TIMEOUT
    {
        return codex_config.clone();
    }

    let mut config = codex_config.clone();
    config.timeout = CODEX_RESUME_TIMEOUT;
    config
}

async fn retry_codex_with_usage_limit_fallback(
    messenger: &NostrMessenger,
    receiver_pubkey: &str,
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
    send_status(
        messenger,
        receiver_pubkey,
        "Usage limit hit; trying fallback model.",
    )
    .await;
    let fallback_config = codex_config.with_model_override(fallback_model);

    run_codex_session_with_status(
        messenger,
        receiver_pubkey,
        prompt,
        &fallback_config,
        session_id,
        cancel_token,
    )
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

fn is_agent_cancelled_error(err: &anyhow::Error) -> bool {
    let message = format!("{err:#}");
    message.contains("Codex cancelled") || message.contains("OpenCode cancelled")
}

fn is_opencode_busy_error(err: &anyhow::Error) -> bool {
    format!("{err:#}").contains("OpenCode is still busy after")
}

async fn report_codex_cancelled<T>(
    messenger: &NostrMessenger,
    receiver_pubkey: &str,
) -> std::result::Result<T, ()> {
    info!("codex task cancelled for {receiver_pubkey}");
    send_status(messenger, receiver_pubkey, "Cancelled.").await;
    Err(())
}

async fn report_opencode_busy<T>(
    messenger: &NostrMessenger,
    receiver_pubkey: &str,
    err: anyhow::Error,
) -> std::result::Result<T, ()> {
    warn!("OpenCode remains busy: {err:#}");
    send_status(
        messenger,
        receiver_pubkey,
        "OpenCode is still busy. It was not cancelled; open its session to follow the active work.",
    )
    .await;
    Err(())
}

async fn report_codex_error<T>(
    messenger: &NostrMessenger,
    receiver_pubkey: &str,
    err: anyhow::Error,
) -> std::result::Result<T, ()> {
    error!("codex failed: {err:#}");
    if let Err(send_err) = messenger
        .send_error_to(receiver_pubkey, format!("Agent failed: {err:#}"))
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
    let mut receive_pubkeys = env_csv("NOSTR_RECEIVE_PUBKEYS")
        .or_else(|| env_csv("NOSTR_ALLOWED_PUBKEYS"))
        .unwrap_or_default();
    if let Some(peer) = &peer_pubkey {
        if !receive_pubkeys.iter().any(|existing| existing == peer) {
            receive_pubkeys.push(peer.clone());
        }
    }
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
        receive_pubkeys,
        peer_pubkey,
        relays,
    })
}

fn env_csv(name: &str) -> Option<Vec<String>> {
    env::var(name)
        .ok()
        .map(|raw| {
            raw.split(',')
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToOwned::to_owned)
                .collect::<Vec<_>>()
        })
        .filter(|values| !values.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_lib_nostr_codex_phone::codex::OpenCodeConfig;

    static ENV_LOCK: once_cell::sync::Lazy<std::sync::Mutex<()>> =
        once_cell::sync::Lazy::new(|| std::sync::Mutex::new(()));

    fn restore_env_var(key: &str, value: Option<std::ffi::OsString>) {
        match value {
            Some(value) => env::set_var(key, value),
            None => env::remove_var(key),
        }
    }

    fn test_codex_config(working_dir: PathBuf) -> CodexConfig {
        CodexConfig {
            backend: AgentBackend::Codex,
            bin: "codex".to_string(),
            args: vec!["exec".to_string()],
            working_dir,
            timeout: Duration::from_secs(300),
            persist_sessions: true,
            usage_limit_fallback_model: None,
            opencode: OpenCodeConfig {
                bin: "opencode".to_string(),
                agent: "build".to_string(),
                model: None,
            },
        }
    }

    #[tokio::test]
    async fn workspace_fips_capabilities_are_random_member_bound_and_single_use() {
        let capabilities = Arc::new(Mutex::new(HashMap::new()));
        let first = issue_workspace_fips_capability(&capabilities, "member-a").await;
        let second = issue_workspace_fips_capability(&capabilities, "member-a").await;

        assert_eq!(first.len(), 43);
        assert_ne!(first, second);
        let mut capabilities = capabilities.lock().await;
        let (member, expires_at) = capabilities.remove(&first).expect("capability exists");
        assert_eq!(member, "member-a");
        assert!(expires_at > Instant::now());
        assert!(capabilities.remove(&first).is_none());
    }

    #[test]
    fn workspace_fips_app_envelope_is_ordered_and_contains_a_wire_message() {
        let frame = WireMessage::workspace_update(WorkspaceUpdate {
            action: "snapshot".to_string(),
            revision: 1,
            channels: vec![],
            members: vec![],
            messages: vec![],
            agents: vec![],
            conversation_agents: vec![],
            conversation_preprompts: vec![],
            typing: None,
        })
        .to_json()
        .unwrap();
        let envelope = FipsApplicationEnvelope::app(1, frame.clone()).unwrap();

        let encoded = envelope.encode().unwrap();
        let decoded = FipsApplicationEnvelope::decode(&encoded).unwrap();
        assert_eq!(decoded.kind, "app");
        assert_eq!(decoded.message_id, Some(1));
        assert!(parse_wire_message(decoded.frame.as_deref().unwrap()).is_ok());
    }

    #[test]
    fn workspace_agent_jobs_use_a_canonical_direct_conversation_key() {
        let message = WorkspaceMessage {
            id: "trigger".to_string(),
            channel_id: None,
            recipient_pubkey: Some("alice".to_string()),
            sender_pubkey: "bob".to_string(),
            body: "hello".to_string(),
            attachments: vec![],
            mentions: vec![],
            parent_id: None,
            also_send_to_main: false,
            reactions: vec![],
            pinned: false,
            created_at: 0,
        };
        let conversation = WorkspaceConversation::Direct("alice".to_string(), "bob".to_string());

        assert_eq!(
            WorkspaceConversation::from_message(&message),
            Some(conversation.clone())
        );
        assert!(workspace_agent_job_matches_trigger(&message, &conversation));
        assert_eq!(workspace_agent_reply_parent_id(&message), "trigger");
        let threaded = WorkspaceMessage {
            parent_id: Some("thread-root".to_string()),
            ..message.clone()
        };
        assert_eq!(workspace_agent_reply_parent_id(&threaded), "thread-root");
        assert!(!workspace_agent_job_matches_trigger(
            &WorkspaceMessage {
                sender_pubkey: "agent:scout".to_string(),
                ..message
            },
            &conversation,
        ));
    }

    #[test]
    fn parses_active_scope_metrics_from_an_opencode_session_description() {
        let metrics = parse_agent_scope_metrics(
            "Description=opencode run --format json --session ses_abc123\nActiveState=active\nMemoryCurrent=1048576\nCPUUsageNSec=9000\nTasksCurrent=7\nActiveEnterTimestampMonotonic=12000000\n",
            Some(1_700_000_000),
        )
        .unwrap();

        assert_eq!(metrics.0, "ses_abc123");
        assert_eq!(
            metrics.1,
            AgentScopeMetrics {
                active_state: "active".to_string(),
                memory_bytes: Some(1_048_576),
                cpu_usage_nsec: Some(9_000),
                task_count: Some(7),
                started_at: Some(1_700_000_012),
            }
        );
    }

    #[test]
    fn ignores_scope_without_a_valid_opencode_session() {
        assert!(parse_agent_scope_metrics(
            "Description=opencode run --format json --session invalid\nActiveState=active\n",
            Some(1_700_000_000),
        )
        .is_none());
    }

    #[test]
    fn workspace_agent_turn_queue_does_not_drop_backlogged_turns() {
        let (sender, mut receiver) = mpsc::unbounded_channel();
        for index in 0..32 {
            sender
                .send(WorkspaceAgentJob {
                    trigger_message_id: index.to_string(),
                })
                .unwrap();
        }

        assert_eq!(receiver.try_recv().unwrap().trigger_message_id, "0");
        assert_eq!(receiver.try_recv().unwrap().trigger_message_id, "1");
    }

    #[test]
    fn finds_repositories_recursively_in_selected_folders() {
        let root = tempfile::tempdir().unwrap();
        let nested_repo = root.path().join("apps").join("phone");
        fs::create_dir_all(nested_repo.join(".git")).unwrap();
        fs::create_dir_all(root.path().join("tools").join("script")).unwrap();

        assert_eq!(
            repositories_in_folder_scope(&[root.path().to_string_lossy().to_string()]).unwrap(),
            vec![nested_repo.to_string_lossy().to_string()],
        );
    }

    #[test]
    fn repository_list_includes_its_root_and_directories() {
        let root = tempfile::tempdir().unwrap();
        fs::create_dir(root.path().join("phone")).unwrap();

        let entries = list_repo_root(root.path(), root.path()).unwrap().repos;

        assert_eq!(entries[0].relative_path, ".");
        assert_eq!(entries[0].path, root.path().to_string_lossy().to_string());
        assert_eq!(entries[1].relative_path, "phone");
    }

    #[test]
    fn empty_conversation_scope_does_not_restrict_the_agent() {
        let root = tempfile::tempdir().unwrap();
        let config = test_codex_config(root.path().to_path_buf());

        assert_eq!(conversation_scope_prompt(&[], &config).unwrap(), "");
    }

    #[test]
    fn conversation_prompt_keeps_scoped_context_with_the_user_message() {
        let session_prompt =
            conversation_agent_session_prompt("Review carefully.", "Folder scope.");
        let prompt =
            conversation_agent_prompt("ResearchBot: Proposed implementation.", "Fix the bug.");
        assert!(session_prompt.starts_with("Review carefully.\n\nFolder scope."));
        assert!(!session_prompt.contains("[[WORKSPACE_HISTORY: N]]"));
        assert!(!prompt.contains("[[WORKSPACE_HISTORY: N]]"));
        assert!(prompt.contains("Thread context:\nResearchBot: Proposed implementation."));
        assert!(prompt.ends_with("User message:\nFix the bug."));
    }

    #[test]
    fn initializes_sessions_with_the_workspace_history_protocol() {
        let prompt = conversation_agent_initialization_prompt();

        assert!(prompt.contains("[[WORKSPACE_HISTORY: N]]"));
        assert!(prompt.contains("Reply only READY"));
    }

    #[test]
    fn accepts_only_bounded_incremental_workspace_history_requests() {
        assert_eq!(
            workspace_history_request_count("[[WORKSPACE_HISTORY: 5]]"),
            Some(5)
        );
        assert_eq!(
            workspace_history_request_count(" [[WORKSPACE_HISTORY: 50]] "),
            Some(50)
        );
        assert_eq!(
            workspace_history_request_count("[[WORKSPACE_HISTORY: 6]]"),
            None
        );
        assert_eq!(
            workspace_history_request_count("[[WORKSPACE_HISTORY: 55]]"),
            None
        );
        assert_eq!(workspace_history_request_count("History: 5"), None);
    }

    #[test]
    fn seeds_all_trusted_recipients_as_workspace_members() {
        let temp_dir = tempfile::tempdir().unwrap();
        let workspace = WorkspaceStore::open(&temp_dir.path().join("workspace.sqlite3")).unwrap();
        let trusted = vec!["phone".to_string(), "desktop".to_string()];

        initialize_workspace_members(&workspace, Some("owner"), &trusted).unwrap();

        let mut members = workspace.members().unwrap();
        members.sort_by(|left, right| left.pubkey.cmp(&right.pubkey));
        assert_eq!(
            members
                .into_iter()
                .map(|member| member.pubkey)
                .collect::<Vec<_>>(),
            vec!["desktop", "owner", "phone"],
        );
        assert!(workspace.is_admin("owner").unwrap());
        assert!(!workspace.is_admin("phone").unwrap());
    }

    #[test]
    fn routes_only_explicitly_mentioned_workspace_agents() {
        let mentions = vec![WorkspaceMentionPayload {
            kind: "agent".to_string(),
            id: "scout".to_string(),
            label: "Scout".to_string(),
        }];

        assert!(conversation_agent_is_targeted("scout", &mentions));
        assert!(!conversation_agent_is_targeted("writer", &mentions));
    }

    #[test]
    fn does_not_route_conversation_agents_without_agent_mentions() {
        let member_mentions = vec![WorkspaceMentionPayload {
            kind: "member".to_string(),
            id: "member".to_string(),
            label: "Member".to_string(),
        }];

        assert!(!conversation_agent_is_targeted("scout", &[]));
        assert!(!conversation_agent_is_targeted("writer", &member_mentions));
    }

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
    fn treats_timed_out_agent_turns_as_failures_not_cancellations() {
        assert!(!is_agent_cancelled_error(&anyhow!(
            "OpenCode timed out after 300s"
        )));
        assert!(is_agent_cancelled_error(&anyhow!("OpenCode cancelled")));
    }

    fn legacy_voice_message(sha256: &str) -> IncomingMessage {
        IncomingMessage {
            sender_pubkey: "npub-sender".to_string(),
            sender_pubkey_hex: "sender".to_string(),
            kind: "media_bundle".to_string(),
            text: "[media bundle]".to_string(),
            raw_json: serde_json::json!({
                "media_bundle": {
                    "attachments": [{
                        "url": "https://media.example/voice.ogg",
                        "sha256": sha256,
                        "size": 4,
                        "type": "audio/ogg"
                    }]
                }
            })
            .to_string(),
            event_id: "legacy-event".to_string(),
        }
    }

    #[test]
    fn suppresses_legacy_replay_after_workspace_voice_transcription() {
        let sha256 = "a".repeat(64);
        let request = parse_wire_message(
            &serde_json::json!({
                "workspace_request": {
                    "action": "transcribe_workspace_voice",
                    "channel_id": "general",
                    "attachments": [{
                        "url": "https://media.example/voice.ogg",
                        "sha256": sha256,
                        "size": 4,
                        "type": "audio/ogg"
                    }]
                }
            })
            .to_string(),
        )
        .unwrap();
        let WireMessage::WorkspaceRequest { workspace_request } = request else {
            panic!("expected workspace request");
        };
        let key = workspace_voice_key("sender", &workspace_request).unwrap();
        let mut deduper = WorkspaceVoiceDeduper::new();

        assert!(!legacy_message_replays_workspace_voice(
            &legacy_voice_message(&sha256),
            &deduper,
        ));
        deduper.insert(key);
        assert!(legacy_message_replays_workspace_voice(
            &legacy_voice_message(&sha256),
            &deduper,
        ));
    }

    #[test]
    fn does_not_suppress_independent_session_voice() {
        let mut deduper = WorkspaceVoiceDeduper::new();
        deduper.insert(WorkspaceVoiceKey {
            sender_pubkey: "sender".to_string(),
            sha256: "a".repeat(64),
        });

        assert!(!legacy_message_replays_workspace_voice(
            &legacy_voice_message(&"b".repeat(64)),
            &deduper,
        ));
    }

    #[test]
    fn voice_only_media_prompt_is_just_the_transcript() {
        assert_eq!(
            media_bundle_request_text(
                "",
                &["- voice.ogg (audio/ogg) => https://example.test/voice.ogg".to_string()],
                &["Update the iOS fast unlock flow.".to_string()],
                &[],
                true,
            ),
            "Update the iOS fast unlock flow."
        );
    }

    #[test]
    fn phone_prompt_is_just_the_user_request() {
        let prompt = codex_phone_prompt("status", None);

        assert_eq!(prompt, "status");
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
    fn builds_structured_read_file_tool_result() {
        let temp_dir = tempfile::tempdir().unwrap();
        fs::write(temp_dir.path().join("README.md"), "first\nsecond\n").unwrap();
        let request = serde_json::json!({
            "tool_request": "read_file",
            "request_id": "request-1",
            "path": "README.md",
        })
        .to_string();

        let result =
            structured_tool_result(&mut None, "peer-1", &request, temp_dir.path()).unwrap();

        assert_eq!(result.tool, "read_file");
        assert_eq!(result.request_id, "request-1");
        assert_eq!(result.data["path"], "README.md");
        assert_eq!(result.data["line_count"], 2);
        assert_eq!(result.data["content"], "first\nsecond\n");
    }

    #[test]
    fn compacts_system_status_history_for_delivery() {
        let sample = serde_json::json!({
            "sampled_at": 100,
            "cpu_percent": 12.5,
            "memory": {"used_bytes": 10, "total_bytes": 20},
            "swap": {"used_bytes": 2, "total_bytes": 4},
            "filesystem": {"used_bytes": 30, "total_bytes": 40},
            "networks": [{"name": "eth0", "received_bytes": 999}],
            "temperatures": [{"name": "cpu", "celsius": 55}],
        });

        assert_eq!(
            compact_system_status_history_entry(&sample),
            serde_json::json!({
                "sampled_at": 100,
                "cpu_percent": 12.5,
                "memory": {"used_bytes": 10, "total_bytes": 20},
                "swap": {"used_bytes": 2, "total_bytes": 4},
                "filesystem": {"used_bytes": 30, "total_bytes": 40},
            })
        );
    }

    #[test]
    fn file_browser_excludes_generated_and_secret_paths() {
        let temp_dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(temp_dir.path().join("lib")).unwrap();
        fs::create_dir_all(temp_dir.path().join(".git")).unwrap();
        fs::create_dir_all(temp_dir.path().join("node_modules/package")).unwrap();
        fs::create_dir_all(temp_dir.path().join(".nostr-codex")).unwrap();
        fs::write(temp_dir.path().join("README.md"), "readme").unwrap();
        fs::write(temp_dir.path().join("lib/main.dart"), "void main() {}").unwrap();
        fs::write(temp_dir.path().join(".env"), "SECRET=value").unwrap();
        fs::write(temp_dir.path().join("image.png"), [0_u8, 1, 2]).unwrap();
        fs::write(temp_dir.path().join(".git/config"), "git").unwrap();
        fs::write(
            temp_dir.path().join("node_modules/package/index.js"),
            "module",
        )
        .unwrap();
        fs::write(temp_dir.path().join(".nostr-codex/.env.server"), "secret").unwrap();
        let request = serde_json::json!({
            "tool_request": "file_browser",
            "request_id": "request-2",
        })
        .to_string();

        let result =
            structured_tool_result(&mut None, "peer-1", &request, temp_dir.path()).unwrap();
        let paths = result.data["entries"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|entry| entry["path"].as_str())
            .collect::<Vec<_>>();

        assert!(paths.contains(&"README.md"));
        assert!(paths.contains(&"lib"));
        assert!(!paths.iter().any(|path| path.starts_with(".git")));
        assert!(!paths.iter().any(|path| path.starts_with("node_modules")));
        assert!(!paths.iter().any(|path| path.starts_with(".nostr-codex")));
        assert!(!paths.contains(&".env"));
        assert!(!paths.contains(&"image.png"));

        let lib = file_browser_data(temp_dir.path(), Some("lib"));
        assert!(lib["entries"]
            .as_array()
            .unwrap()
            .iter()
            .any(|entry| entry["path"] == "main.dart"));
    }

    #[test]
    fn file_browser_caps_serialized_payload() {
        let temp_dir = tempfile::tempdir().unwrap();
        for index in 0..600 {
            fs::write(
                temp_dir
                    .path()
                    .join(format!("{index:04}-long-repository-file-name.txt")),
                "content",
            )
            .unwrap();
        }

        let data = file_browser_data(temp_dir.path(), None);

        assert_eq!(data["truncated"], true);
        assert!(data.to_string().len() <= 16100);
    }

    #[test]
    fn file_browser_loads_a_requested_directory() {
        let temp_dir = tempfile::tempdir().unwrap();
        let crowded = temp_dir.path().join("aaa-crowded");
        fs::create_dir(&crowded).unwrap();
        fs::create_dir(temp_dir.path().join("zzz-needed")).unwrap();
        for index in 0..600 {
            fs::write(crowded.join(format!("{index:04}.txt")), "content").unwrap();
        }

        let data = file_browser_data(temp_dir.path(), Some("aaa-crowded"));
        let paths = data["entries"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|entry| entry["path"].as_str())
            .collect::<Vec<_>>();

        assert!(paths.contains(&"0000.txt"));
    }

    #[test]
    fn maps_codex_events_to_sparse_statuses() {
        let started = serde_json::json!({"type": "turn.started"});
        let check = serde_json::json!({
            "type": "item.started",
            "item": {"type": "tool_call", "command": "flutter analyze"}
        });
        let final_message = serde_json::json!({
            "type": "item.completed",
            "item": {"type": "agent_message", "text": "Done"}
        });

        assert_eq!(
            codex_status_from_event(&started).map(|(message, _)| message),
            Some("Codex started.".to_string())
        );
        assert_eq!(
            codex_status_from_event(&check).map(|(message, _)| message),
            Some("Running checks.".to_string())
        );
        assert_eq!(codex_status_from_event(&final_message), None);
    }

    #[test]
    fn maps_opencode_events_to_statuses() {
        let busy = serde_json::json!({
            "type": "session.status",
            "properties": {"status": {"type": "busy"}}
        });
        let tool = serde_json::json!({
            "type": "message.part.updated",
            "properties": {"part": {"type": "tool", "tool": "read", "state": {"status": "running", "title": "Inspect workspace routing"}}}
        });

        assert_eq!(
            codex_status_from_event(&busy).map(|(message, _)| message),
            Some("OpenCode is working.".to_string())
        );
        assert_eq!(
            codex_status_from_event(&tool).map(|(message, _)| message),
            Some("OpenCode: running Inspect workspace routing.".to_string())
        );
    }

    #[test]
    fn formats_opencode_todos_as_a_checklist() {
        let todos = serde_json::json!([
            {"content": "Inspect status routing", "status": "completed"},
            {"content": "Show updates on the phone", "status": "in_progress"},
            {"content": "Run checks", "status": "pending"}
        ]);

        assert_eq!(
            format_todo_status(todos.as_array().unwrap()),
            "OpenCode todos: 1/3 complete\n[x] Inspect status routing\n[~] Show updates on the phone\n[ ] Run checks"
        );
    }

    #[test]
    fn parses_spawn_worker_requests() {
        assert_eq!(
            parse_spawn_worker_request("/spawn /home/tom/code/repo"),
            Some(SpawnWorkerRequest {
                workdir: "/home/tom/code/repo".to_string(),
                create: false,
                new_session: false,
                silent: false,
            })
        );
        assert_eq!(
            parse_spawn_worker_request("/spawn '/home/tom/code/repo with spaces'"),
            Some(SpawnWorkerRequest {
                workdir: "/home/tom/code/repo with spaces".to_string(),
                create: false,
                new_session: false,
                silent: false,
            })
        );
        assert_eq!(
            parse_spawn_worker_request("start worker in ~/code/repo"),
            Some(SpawnWorkerRequest {
                workdir: "~/code/repo".to_string(),
                create: false,
                new_session: false,
                silent: false,
            })
        );
        assert_eq!(
            parse_spawn_worker_request("Spawn session in /home/tom/code/repo"),
            Some(SpawnWorkerRequest {
                workdir: "/home/tom/code/repo".to_string(),
                create: false,
                new_session: false,
                silent: false,
            })
        );
        assert_eq!(
            parse_spawn_worker_request("Start session in /home/tom/code/repo"),
            Some(SpawnWorkerRequest {
                workdir: "/home/tom/code/repo".to_string(),
                create: false,
                new_session: false,
                silent: false,
            })
        );
        assert_eq!(
            parse_spawn_worker_request("Restart session in /home/tom/code/repo"),
            Some(SpawnWorkerRequest {
                workdir: "/home/tom/code/repo".to_string(),
                create: false,
                new_session: false,
                silent: false,
            })
        );
        assert_eq!(
            parse_spawn_worker_request("Create session in /home/tom/code/new"),
            Some(SpawnWorkerRequest {
                workdir: "/home/tom/code/new".to_string(),
                create: true,
                new_session: false,
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
                new_session: false,
                silent: true,
            })
        );
        assert_eq!(
            parse_spawn_worker_request(
                r#"{"spawn_session":{"workdir":"/home/tom/code/repo","new_session":true}}"#
            ),
            Some(SpawnWorkerRequest {
                workdir: "/home/tom/code/repo".to_string(),
                create: false,
                new_session: true,
                silent: false,
            })
        );
        assert_eq!(
            parse_spawn_worker_request("/spawn --create new-repo"),
            Some(SpawnWorkerRequest {
                workdir: "new-repo".to_string(),
                create: true,
                new_session: false,
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
            Some(NonblockingControlRequest::RepoList(None))
        );
        assert_eq!(
            nonblocking_control_request("query", r#"{"repo_list_request":{"path":"buzz/buzz"}}"#,),
            Some(NonblockingControlRequest::RepoList(Some(
                "buzz/buzz".to_string(),
            )))
        );
        assert_eq!(
            nonblocking_control_request("query", r#"{"opencode_session_list_request":{}}"#),
            Some(NonblockingControlRequest::OpenCodeSessions)
        );
        assert_eq!(
            nonblocking_control_request(
                "query",
                r#"{"spawn_session":{"workdir":"/home/tom/code/repo"}}"#
            ),
            Some(NonblockingControlRequest::Spawn(SpawnWorkerRequest {
                workdir: "/home/tom/code/repo".to_string(),
                create: false,
                new_session: false,
                silent: false,
            }))
        );
        assert_eq!(
            nonblocking_control_request("audio", r#"{"repo_list_request":{}}"#),
            None
        );
        assert_eq!(
            nonblocking_control_request("audio", r#"{"opencode_session_list_request":{}}"#),
            None
        );
    }

    #[test]
    fn caps_resume_attempt_timeout_only() {
        let config = CodexConfig {
            backend: AgentBackend::Codex,
            bin: "codex".to_string(),
            args: vec!["exec".to_string()],
            working_dir: PathBuf::from("/tmp"),
            timeout: Duration::from_secs(300),
            persist_sessions: true,
            usage_limit_fallback_model: None,
            opencode: OpenCodeConfig {
                bin: "opencode".to_string(),
                agent: "build".to_string(),
                model: None,
            },
        };

        assert_eq!(
            codex_config_for_first_attempt(&config, Some("session")).timeout,
            CODEX_RESUME_TIMEOUT
        );
        assert_eq!(
            codex_config_for_first_attempt(&config, None).timeout,
            Duration::from_secs(300)
        );

        let opencode_config = CodexConfig {
            backend: AgentBackend::OpenCode,
            ..config
        };
        assert_eq!(
            codex_config_for_first_attempt(&opencode_config, Some("session")).timeout,
            Duration::from_secs(300)
        );
    }

    #[test]
    fn recognizes_busy_opencode_timeout() {
        assert!(is_opencode_busy_error(&anyhow::anyhow!(
            "OpenCode is still busy after 300s"
        )));
        assert!(!is_opencode_busy_error(&anyhow::anyhow!(
            "OpenCode connection failed"
        )));
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
    fn detects_opencode_session_list_requests() {
        assert!(is_opencode_session_list_request("/opencode-sessions"));
        assert!(is_opencode_session_list_request(
            r#"{"opencode_session_list_request":{}}"#
        ));
        assert!(is_opencode_session_list_request(
            r#"{"workdir":"/home/tom/code/phone","opencode_session_list_request":{}}"#
        ));
        assert!(!is_opencode_session_list_request("list sessions"));
    }

    #[test]
    fn nostr_config_accepts_extra_receive_pubkeys() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let previous_secret = env::var_os("NOSTR_SECRET_KEY");
        let previous_peer = env::var_os("NOSTR_PEER_PUBKEY");
        let previous_mobile = env::var_os("NOSTR_MOBILE_PUBKEY");
        let previous_receive = env::var_os("NOSTR_RECEIVE_PUBKEYS");
        let previous_allowed = env::var_os("NOSTR_ALLOWED_PUBKEYS");

        env::set_var("NOSTR_SECRET_KEY", "secret");
        env::set_var("NOSTR_PEER_PUBKEY", "npub-current");
        env::set_var(
            "NOSTR_RECEIVE_PUBKEYS",
            "npub-old, npub-current, npub-extra",
        );
        env::remove_var("NOSTR_MOBILE_PUBKEY");
        env::remove_var("NOSTR_ALLOWED_PUBKEYS");

        let temp_dir = tempfile::tempdir().unwrap();
        let config = nostr_config_from_env(&WorkerEnvFile {
            path: temp_dir.path().join(".env.server"),
        })
        .unwrap();

        assert_eq!(config.peer_pubkey.as_deref(), Some("npub-current"));
        assert_eq!(
            config.receive_pubkeys,
            vec!["npub-old", "npub-current", "npub-extra"]
        );

        match previous_secret {
            Some(value) => env::set_var("NOSTR_SECRET_KEY", value),
            None => env::remove_var("NOSTR_SECRET_KEY"),
        }
        match previous_peer {
            Some(value) => env::set_var("NOSTR_PEER_PUBKEY", value),
            None => env::remove_var("NOSTR_PEER_PUBKEY"),
        }
        match previous_mobile {
            Some(value) => env::set_var("NOSTR_MOBILE_PUBKEY", value),
            None => env::remove_var("NOSTR_MOBILE_PUBKEY"),
        }
        match previous_receive {
            Some(value) => env::set_var("NOSTR_RECEIVE_PUBKEYS", value),
            None => env::remove_var("NOSTR_RECEIVE_PUBKEYS"),
        }
        match previous_allowed {
            Some(value) => env::set_var("NOSTR_ALLOWED_PUBKEYS", value),
            None => env::remove_var("NOSTR_ALLOWED_PUBKEYS"),
        }
    }

    #[test]
    fn owner_gate_accepts_configured_receive_peer() {
        let temp_dir = tempfile::tempdir().unwrap();
        let env_file = WorkerEnvFile {
            path: temp_dir.path().join(".env.server"),
        };
        let mut owner = Some("owner-hex".to_string());
        let message = IncomingMessage {
            sender_pubkey: "npub-extra".to_string(),
            sender_pubkey_hex: "extra-hex".to_string(),
            kind: "query".to_string(),
            text: "hello".to_string(),
            raw_json: r#"{"message":"hello"}"#.to_string(),
            event_id: "event-1".to_string(),
        };

        assert!(accept_or_claim_owner(
            &env_file,
            &mut owner,
            &["owner-hex".to_string(), "extra-hex".to_string()],
            &None,
            &message,
        ));
        assert_eq!(owner.as_deref(), Some("owner-hex"));

        assert!(!accept_or_claim_owner(
            &env_file,
            &mut owner,
            &["owner-hex".to_string()],
            &None,
            &message,
        ));
    }

    #[test]
    fn recognizes_query_wrapped_desktop_invite_redemption() {
        let code = "a".repeat(43);
        let message = IncomingMessage {
            sender_pubkey: "desktop-npub".to_string(),
            sender_pubkey_hex: "desktop-hex".to_string(),
            kind: "query".to_string(),
            text: String::new(),
            raw_json: serde_json::json!({
                "query": serde_json::json!({"redeem_invite": {"code": &code}}).to_string(),
            })
            .to_string(),
            event_id: "event-1".to_string(),
        };

        assert_eq!(invite_redemption_code(&message), Some(code));
    }

    #[test]
    fn redeemed_member_snapshot_includes_workspace_and_only_its_direct_messages() {
        let temp_dir = tempfile::tempdir().unwrap();
        let workspace = WorkspaceStore::open(&temp_dir.path().join("workspace.sqlite3")).unwrap();
        workspace.add_member("owner").unwrap();
        workspace.add_member("desktop").unwrap();
        workspace.add_member("other").unwrap();
        let channel = workspace.create_channel("general", "owner").unwrap();
        workspace
            .add_channel_member(&channel.id, "desktop")
            .unwrap();
        workspace
            .add_channel_message("owner", &channel.id, "team", &[], &[], None)
            .unwrap();
        workspace
            .add_direct_message("owner", "desktop", "for desktop", &[], &[], None)
            .unwrap();
        workspace
            .add_direct_message("owner", "other", "not for desktop", &[], &[], None)
            .unwrap();
        workspace
            .set_conversation_preprompt(Some(&channel.id), None, None, "Review carefully.", &[])
            .unwrap();

        let snapshot = workspace_snapshot(&workspace, "desktop").unwrap();

        assert_eq!(snapshot.action, "snapshot");
        assert_eq!(
            snapshot.channels,
            vec![channel_payload(&workspace, channel).unwrap()]
        );
        assert_eq!(snapshot.members.len(), 3);
        assert_eq!(snapshot.conversation_preprompts.len(), 1);
        assert_eq!(
            snapshot.conversation_preprompts[0].preprompt,
            "Review carefully."
        );
        let mut bodies = snapshot
            .messages
            .into_iter()
            .map(|message| message.body)
            .collect::<Vec<_>>();
        bodies.sort();
        assert_eq!(bodies, vec!["for desktop", "team"]);
    }

    #[test]
    fn first_owner_requires_matching_secret_and_confirmation_even_with_legacy_bypass() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let previous_bypass = env::var_os("NOSTR_ALLOW_FIRST_OWNER_CLAIM");
        env::set_var("NOSTR_ALLOW_FIRST_OWNER_CLAIM", "true");

        let temp_dir = tempfile::tempdir().unwrap();
        let env_file = WorkerEnvFile {
            path: temp_dir.path().join(".env.server"),
        };
        let secret = "0123456789abcdef".to_string();
        let confirmation = pairing_confirmation_code(&secret);
        let mut owner = None;
        let message = IncomingMessage {
            sender_pubkey: "npub-first".to_string(),
            sender_pubkey_hex: "first-hex".to_string(),
            kind: "query".to_string(),
            text: serde_json::json!({"pairing_secret": secret.clone()}).to_string(),
            raw_json: "{}".to_string(),
            event_id: "event-1".to_string(),
        };

        assert!(!accept_or_claim_owner(
            &env_file,
            &mut owner,
            &[],
            &Some(secret.clone()),
            &message,
        ));
        assert_eq!(owner, None);

        let message = IncomingMessage {
            text: serde_json::json!({
                "pairing_secret": secret.clone(),
                "pairing_confirmation": "000000",
            })
            .to_string(),
            ..message
        };
        assert!(!accept_or_claim_owner(
            &env_file,
            &mut owner,
            &[],
            &Some(secret.clone()),
            &message,
        ));
        assert_eq!(owner, None);

        let message = IncomingMessage {
            text: serde_json::json!({
                "pairing_secret": secret,
                "pairing_confirmation": confirmation,
            })
            .to_string(),
            ..message
        };
        assert!(accept_or_claim_owner(
            &env_file,
            &mut owner,
            &[],
            &Some("0123456789abcdef".to_string()),
            &message,
        ));
        assert_eq!(owner.as_deref(), Some("first-hex"));
        restore_env_var("NOSTR_ALLOW_FIRST_OWNER_CLAIM", previous_bypass);
    }

    #[test]
    fn pairing_confirmation_uses_the_documented_domain_separated_sha256_input() {
        let secret = "test-secret";
        let mut hasher = Sha256::new();
        hasher.update(b"nostr-codex/first-owner-confirmation/v1\0test-secret");
        let digest = hasher.finalize();
        let expected = format!(
            "{:06}",
            u32::from_be_bytes(digest[..4].try_into().unwrap()) % 1_000_000
        );

        assert_eq!(pairing_confirmation_code(secret), expected);
        assert_eq!(pairing_confirmation_code(secret).len(), 6);
    }

    #[test]
    fn routed_workdir_must_be_inside_a_canonical_allowed_root() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let previous_allowed_roots = env::var_os("NOSTR_ALLOWED_WORKDIR_ROOTS");
        let previous_spawn_roots = env::var_os("NOSTR_SPAWN_ROOTS");
        let previous_workdir = env::var_os("CODEX_WORKDIR");
        let temp_dir = tempfile::tempdir().unwrap();
        let worker_root = temp_dir.path().join("worker");
        let allowed_root = temp_dir.path().join("allowed");
        let routed_dir = allowed_root.join("repo");
        let outside_dir = temp_dir.path().join("outside");
        fs::create_dir_all(&worker_root).unwrap();
        fs::create_dir_all(&routed_dir).unwrap();
        fs::create_dir_all(&outside_dir).unwrap();
        env::set_var("CODEX_WORKDIR", &worker_root);
        env::set_var("NOSTR_ALLOWED_WORKDIR_ROOTS", &allowed_root);
        env::remove_var("NOSTR_SPAWN_ROOTS");

        let config = test_codex_config(worker_root);
        let allowed_message = IncomingMessage {
            sender_pubkey: "npub".to_string(),
            sender_pubkey_hex: "hex".to_string(),
            kind: "query".to_string(),
            text: serde_json::json!({"workdir": routed_dir}).to_string(),
            raw_json: "{}".to_string(),
            event_id: "event".to_string(),
        };
        assert_eq!(
            routed_codex_config(&config, &allowed_message)
                .unwrap()
                .working_dir,
            routed_dir.canonicalize().unwrap()
        );

        let outside_message = IncomingMessage {
            text: serde_json::json!({"workdir": outside_dir}).to_string(),
            ..allowed_message
        };
        assert!(routed_codex_config(&config, &outside_message).is_err());
        restore_env_var("CODEX_WORKDIR", previous_workdir);
        restore_env_var("NOSTR_ALLOWED_WORKDIR_ROOTS", previous_allowed_roots);
        restore_env_var("NOSTR_SPAWN_ROOTS", previous_spawn_roots);
    }

    #[cfg(unix)]
    #[test]
    fn routed_workdir_rejects_a_symlink_that_escapes_an_allowed_root() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let previous_allowed_roots = env::var_os("NOSTR_ALLOWED_WORKDIR_ROOTS");
        let previous_workdir = env::var_os("CODEX_WORKDIR");
        let temp_dir = tempfile::tempdir().unwrap();
        let worker_root = temp_dir.path().join("worker");
        let allowed_root = temp_dir.path().join("allowed");
        let outside_dir = temp_dir.path().join("outside");
        fs::create_dir_all(&worker_root).unwrap();
        fs::create_dir_all(&allowed_root).unwrap();
        fs::create_dir_all(&outside_dir).unwrap();
        std::os::unix::fs::symlink(&outside_dir, allowed_root.join("escape")).unwrap();
        env::set_var("CODEX_WORKDIR", &worker_root);
        env::set_var("NOSTR_ALLOWED_WORKDIR_ROOTS", &allowed_root);

        let message = IncomingMessage {
            sender_pubkey: "npub".to_string(),
            sender_pubkey_hex: "hex".to_string(),
            kind: "query".to_string(),
            text: serde_json::json!({"workdir": allowed_root.join("escape")}).to_string(),
            raw_json: "{}".to_string(),
            event_id: "event".to_string(),
        };
        assert!(routed_codex_config(&test_codex_config(worker_root), &message).is_err());
        restore_env_var("CODEX_WORKDIR", previous_workdir);
        restore_env_var("NOSTR_ALLOWED_WORKDIR_ROOTS", previous_allowed_roots);
    }

    #[cfg(unix)]
    #[test]
    fn secret_bearing_qr_artifacts_are_private() {
        use std::os::unix::fs::PermissionsExt;

        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let previous_print = env::var_os("NOSTR_CODEX_QR_PRINT");
        let previous_qr_path = env::var_os("NOSTR_CODEX_QR_PATH");
        let previous_payload_path = env::var_os("NOSTR_CODEX_TARGET_PAYLOAD_PATH");
        let temp_dir = tempfile::tempdir().unwrap();
        let qr_path = temp_dir.path().join("target.svg");
        let payload_path = temp_dir.path().join("target.txt");
        env::set_var("NOSTR_CODEX_QR_PRINT", "false");
        env::set_var("NOSTR_CODEX_QR_PATH", &qr_path);
        env::set_var("NOSTR_CODEX_TARGET_PAYLOAD_PATH", &payload_path);

        write_worker_target_qr(
            "npub-test",
            "hex-test",
            temp_dir.path(),
            &["wss://relay.example".to_string()],
            Some("secret"),
        );

        assert_eq!(
            fs::metadata(qr_path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_eq!(
            fs::metadata(&payload_path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        let payload = fs::read_to_string(payload_path).unwrap();
        assert!(payload.contains("\"pairing_secret\":\"secret\""));
        assert!(payload.contains(&format!(
            "\"pairing_confirmation\":\"{}\"",
            pairing_confirmation_code("secret")
        )));
        restore_env_var("NOSTR_CODEX_QR_PRINT", previous_print);
        restore_env_var("NOSTR_CODEX_QR_PATH", previous_qr_path);
        restore_env_var("NOSTR_CODEX_TARGET_PAYLOAD_PATH", previous_payload_path);
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
            new_session: false,
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
        let previous_spawn_roots = env::var_os("NOSTR_SPAWN_ROOTS");
        let previous_allowed_roots = env::var_os("NOSTR_ALLOWED_WORKDIR_ROOTS");

        let temp_dir = tempfile::tempdir().unwrap();
        let current_workdir = temp_dir.path().join("worker-root");
        let outside = temp_dir.path().join("other");
        fs::create_dir_all(&current_workdir).unwrap();
        fs::create_dir_all(&outside).unwrap();
        env::remove_var("CODEX_WORKDIR");
        env::remove_var("NOSTR_SPAWN_ROOTS");
        env::remove_var("NOSTR_ALLOWED_WORKDIR_ROOTS");

        let request = SpawnWorkerRequest {
            workdir: outside.to_string_lossy().to_string(),
            create: false,
            new_session: false,
            silent: false,
        };
        let error = resolve_spawn_workdir(&request, &current_workdir)
            .expect_err("existing folder outside worker root should fail");

        match previous_workdir {
            Some(value) => env::set_var("CODEX_WORKDIR", value),
            None => env::remove_var("CODEX_WORKDIR"),
        }
        restore_env_var("NOSTR_SPAWN_ROOTS", previous_spawn_roots);
        restore_env_var("NOSTR_ALLOWED_WORKDIR_ROOTS", previous_allowed_roots);

        assert!(error.to_string().contains("outside the allowed folders"));
    }

    #[test]
    fn rejects_spawn_create_outside_worker_root() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let previous_workdir = env::var_os("CODEX_WORKDIR");
        let previous_spawn_roots = env::var_os("NOSTR_SPAWN_ROOTS");
        let previous_allowed_roots = env::var_os("NOSTR_ALLOWED_WORKDIR_ROOTS");

        let temp_dir = tempfile::tempdir().unwrap();
        let current_workdir = temp_dir.path().join("worker-root");
        fs::create_dir_all(&current_workdir).unwrap();
        fs::create_dir_all(temp_dir.path().join("tmp")).unwrap();
        env::remove_var("CODEX_WORKDIR");
        env::remove_var("NOSTR_SPAWN_ROOTS");
        env::remove_var("NOSTR_ALLOWED_WORKDIR_ROOTS");

        let request = SpawnWorkerRequest {
            workdir: "../tmp/new-repo".to_string(),
            create: true,
            new_session: false,
            silent: false,
        };
        let error = resolve_spawn_workdir(&request, &current_workdir)
            .expect_err("create outside worker root should fail");

        match previous_workdir {
            Some(value) => env::set_var("CODEX_WORKDIR", value),
            None => env::remove_var("CODEX_WORKDIR"),
        }
        restore_env_var("NOSTR_SPAWN_ROOTS", previous_spawn_roots);
        restore_env_var("NOSTR_ALLOWED_WORKDIR_ROOTS", previous_allowed_roots);

        assert!(error
            .to_string()
            .contains("new folders may only be created"));
    }

    #[test]
    fn allows_spawn_create_inside_configured_extra_root() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let previous_workdir = env::var_os("CODEX_WORKDIR");
        let previous_spawn_roots = env::var_os("NOSTR_SPAWN_ROOTS");
        let previous_allowed_roots = env::var_os("NOSTR_ALLOWED_WORKDIR_ROOTS");

        let temp_dir = tempfile::tempdir().unwrap();
        let current_workdir = temp_dir.path().join("worker-root");
        let extra_root = temp_dir.path().join("tmp-root");
        fs::create_dir_all(&current_workdir).unwrap();
        fs::create_dir_all(&extra_root).unwrap();
        env::remove_var("CODEX_WORKDIR");
        env::set_var("NOSTR_SPAWN_ROOTS", &extra_root);
        env::remove_var("NOSTR_ALLOWED_WORKDIR_ROOTS");

        let request = SpawnWorkerRequest {
            workdir: extra_root.join("new-repo").to_string_lossy().to_string(),
            create: true,
            new_session: false,
            silent: false,
        };
        let resolved = resolve_spawn_workdir(&request, &current_workdir).unwrap();

        match previous_workdir {
            Some(value) => env::set_var("CODEX_WORKDIR", value),
            None => env::remove_var("CODEX_WORKDIR"),
        }
        match previous_spawn_roots {
            Some(value) => env::set_var("NOSTR_SPAWN_ROOTS", value),
            None => env::remove_var("NOSTR_SPAWN_ROOTS"),
        }
        match previous_allowed_roots {
            Some(value) => env::set_var("NOSTR_ALLOWED_WORKDIR_ROOTS", value),
            None => env::remove_var("NOSTR_ALLOWED_WORKDIR_ROOTS"),
        }

        assert_eq!(
            resolved,
            extra_root.join("new-repo").canonicalize().unwrap()
        );
        assert!(resolved.is_dir());
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
    fn loads_saved_codex_session_from_memory_when_no_workdir_session_exists() {
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

        let session = load_codex_session(
            &Some(memory),
            "peer-1",
            &workdir,
            "continue",
            AgentBackend::Codex,
        );
        assert_eq!(session.as_deref(), Some("stored-session"));
    }

    #[test]
    fn opencode_ignores_saved_sqlite_session() {
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

        let session = load_codex_session(
            &Some(memory),
            "peer-1",
            &workdir,
            "continue",
            AgentBackend::OpenCode,
        );

        assert_eq!(session, None);
    }

    #[test]
    fn opencode_does_not_adopt_codex_session_files() {
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
            "codex-session",
            &workdir,
            "2026-06-16T10:00:00Z",
            "2026-06-16T10:05:00Z",
        );

        let session = load_codex_session(
            &None,
            "peer-1",
            &workdir,
            "continue",
            AgentBackend::OpenCode,
        );
        match previous_sessions_dir {
            Some(value) => env::set_var("CODEX_SESSIONS_DIR", value),
            None => env::remove_var("CODEX_SESSIONS_DIR"),
        }

        assert_eq!(session, None);
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

        let session =
            load_codex_session(&None, "peer-1", &workdir, "continue", AgentBackend::Codex);
        match previous_sessions_dir {
            Some(value) => env::set_var("CODEX_SESSIONS_DIR", value),
            None => env::remove_var("CODEX_SESSIONS_DIR"),
        }

        assert_eq!(session.as_deref(), Some("latest-session"));
    }

    #[test]
    fn adopts_latest_workdir_session_over_older_saved_codex_session() {
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
            "continue",
            AgentBackend::Codex,
        );
        match previous_sessions_dir {
            Some(value) => env::set_var("CODEX_SESSIONS_DIR", value),
            None => env::remove_var("CODEX_SESSIONS_DIR"),
        }

        assert_eq!(session.as_deref(), Some("newer-session"));
    }

    #[test]
    fn latest_codex_session_uses_last_activity_before_start_time() {
        let temp_dir = tempfile::tempdir().unwrap();
        let sessions_dir = temp_dir.path().join("sessions");
        let workdir = temp_dir.path().join("repo");
        fs::create_dir_all(sessions_dir.join("2026/06/16")).unwrap();
        fs::create_dir_all(&workdir).unwrap();

        write_session_fixture(
            &sessions_dir.join("2026/06/16/started-later.jsonl"),
            "started-later-session",
            &workdir,
            "2026-06-16T11:00:00Z",
            "2026-06-16T11:01:00Z",
        );
        write_session_fixture(
            &sessions_dir.join("2026/06/16/active-later.jsonl"),
            "active-later-session",
            &workdir,
            "2026-06-16T10:00:00Z",
            "2026-06-16T11:05:00Z",
        );

        let session = latest_codex_session_for_workdir_in(&sessions_dir, &workdir).unwrap();
        assert_eq!(session.as_deref(), Some("active-later-session"));
    }

    #[test]
    fn latest_codex_session_tie_breaks_like_codex_sessions_script() {
        let temp_dir = tempfile::tempdir().unwrap();
        let sessions_dir = temp_dir.path().join("sessions");
        let workdir = temp_dir.path().join("repo");
        fs::create_dir_all(sessions_dir.join("2026/06/16")).unwrap();
        fs::create_dir_all(&workdir).unwrap();

        write_session_fixture(
            &sessions_dir.join("2026/06/16/a.jsonl"),
            "aaa-session",
            &workdir,
            "2026-06-16T10:00:00Z",
            "2026-06-16T10:05:00Z",
        );
        write_session_fixture(
            &sessions_dir.join("2026/06/16/z.jsonl"),
            "zzz-session",
            &workdir,
            "2026-06-16T10:00:00Z",
            "2026-06-16T10:05:00Z",
        );

        let session = latest_codex_session_for_workdir_in(&sessions_dir, &workdir).unwrap();
        assert_eq!(session.as_deref(), Some("zzz-session"));
    }

    #[test]
    fn permits_workspace_admins_to_manage_agents() {
        assert!(workspace_action_requires_admin("create_conversation_agent"));
        assert!(workspace_action_requires_admin("delete_agent"));
        assert!(!workspace_action_requires_admin("send_channel_message"));
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
