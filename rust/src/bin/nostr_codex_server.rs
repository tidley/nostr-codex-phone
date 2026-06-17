use std::any::Any;
use std::collections::{HashMap, HashSet};
use std::env;
use std::fs::{self, File};
use std::io::{BufRead, BufReader};
use std::panic::AssertUnwindSafe;
use std::path::{Path, PathBuf};
use std::process::Command as StdCommand;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
use futures_util::FutureExt;
use nostr_sdk::prelude::{Keys, PublicKey, ToBech32};
use qrcode::{Color, QrCode};
#[path = "nostr_codex_server/memory.rs"]
mod memory;
use memory::{MemoryConfig, MemoryStore, RecordedMessage};
use rust_lib_nostr_codex_phone::codex::{
    is_codex_usage_limit_error, run_codex, run_codex_session, CodexConfig, CodexRunResult,
};
use rust_lib_nostr_codex_phone::nostr_client::{
    default_relays, IncomingMessage, NostrConfig, NostrMessenger,
};
use rust_lib_nostr_codex_phone::protocol::{parse_wire_message, AudioReference, WireMessage};
use rust_lib_nostr_codex_phone::transcribe::{
    download_blossom_audio, transcribe_audio, AudioConfig, TranscribeConfig,
};
use tokio::sync::mpsc;
use tracing::{error, info, warn};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RequestClass {
    Command,
    Coding,
    Clarification,
    MemoryLookup,
    NoOp,
}

#[derive(Debug, Clone)]
struct WorkerEnvFile {
    path: PathBuf,
}

impl WorkerEnvFile {
    fn for_workdir(workdir: &Path) -> Self {
        let path = env::var("NOSTR_CODEX_ENV_FILE")
            .map(PathBuf::from)
            .unwrap_or_else(|_| workdir.join(".env.server"));
        Self { path }
    }

    fn load_missing(&self) -> Result<()> {
        if !self.path.is_file() {
            return Ok(());
        }

        let raw = fs::read_to_string(&self.path)
            .with_context(|| format!("failed to read worker env file `{}`", self.path.display()))?;
        for line in raw.lines() {
            let Some((key, value)) = parse_env_assignment(line) else {
                continue;
            };
            if env::var_os(&key).is_none() {
                env::set_var(key, value);
            }
        }

        Ok(())
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
    env::var("CODEX_WORKDIR")
        .map(PathBuf::from)
        .or_else(|_| env::current_dir())
        .context("failed to resolve worker directory")
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

    let initial_env = WorkerEnvFile::for_workdir(&initial_workdir()?);
    initial_env.load_missing()?;
    let codex_config = CodexConfig::from_env()?;
    let worker_env = WorkerEnvFile::for_workdir(&codex_config.working_dir);
    if worker_env.path != initial_env.path {
        worker_env.load_missing()?;
    }
    let nostr_config = nostr_config_from_env(&worker_env)?;
    let audio_config = AudioConfig::from_env();
    let transcribe_config = TranscribeConfig::from_env()?;
    let memory_config = MemoryConfig::from_env(&codex_config.working_dir);
    let memory_probe = open_memory_store(memory_config.clone());
    let messenger = Arc::new(NostrMessenger::connect(nostr_config.clone()).await?);
    let mut owner_peer_hex = nostr_config
        .peer_pubkey
        .as_deref()
        .map(pubkey_to_hex)
        .transpose()?;

    let server_pubkey = messenger.public_key_bech32()?;
    info!("server pubkey: {}", server_pubkey);
    info!("server pubkey hex: {}", messenger.public_key_hex());
    match &nostr_config.peer_pubkey {
        Some(peer) => info!("peer pubkey: {peer}"),
        None => warn!("peer pubkey not configured; first valid DM sender will be saved as owner"),
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
    );
    drop(memory_probe);

    let mut peer_workers = HashMap::<String, mpsc::Sender<IncomingMessage>>::new();

    loop {
        let Some(message) = messenger.next_message(Duration::from_secs(3600)).await? else {
            continue;
        };
        if !accept_or_claim_owner(&worker_env, &mut owner_peer_hex, &message) {
            continue;
        }

        let worker_key = message.sender_pubkey_hex.clone();
        let sender = peer_workers
            .entry(worker_key.clone())
            .or_insert_with(|| {
                spawn_peer_worker(
                    worker_key.clone(),
                    Arc::clone(&messenger),
                    memory_config.clone(),
                    codex_config.clone(),
                    audio_config.clone(),
                    transcribe_config.clone(),
                )
            })
            .clone();

        if let Err(send_err) = sender.send(message).await {
            warn!("peer worker for {worker_key} stopped; restarting and retrying message");
            peer_workers.remove(&worker_key);
            let message = send_err.0;
            let sender = spawn_peer_worker(
                worker_key.clone(),
                Arc::clone(&messenger),
                memory_config.clone(),
                codex_config.clone(),
                audio_config.clone(),
                transcribe_config.clone(),
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
) {
    let mut memory = open_memory_store(memory_config);
    info!("started worker for peer {peer_pubkey}");

    while let Some(message) = receiver.recv().await {
        let event_id = message.event_id.clone();
        let sender_pubkey_hex = message.sender_pubkey_hex.clone();
        let kind = message.kind.clone();
        let result = AssertUnwindSafe(process_message(
            message,
            &messenger,
            &mut memory,
            &codex_config,
            &audio_config,
            &transcribe_config,
        ))
        .catch_unwind()
        .await;

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

async fn process_message(
    message: IncomingMessage,
    messenger: &NostrMessenger,
    memory: &mut Option<MemoryStore>,
    codex_config: &CodexConfig,
    audio_config: &AudioConfig,
    transcribe_config: &TranscribeConfig,
) {
    match message.kind.as_str() {
        "query" => {
            info!(
                "received query event {} from {}",
                message.event_id, message.sender_pubkey
            );

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
                codex_config,
            )
            .await;
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
                .send_transcript_to(&message.sender_pubkey_hex, transcript.clone())
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
                codex_config,
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

async fn process_text_turn(
    messenger: &NostrMessenger,
    memory: &mut Option<MemoryStore>,
    peer_pubkey: &str,
    recorded_id: i64,
    request: &str,
    codex_config: &CodexConfig,
) {
    if is_long_running_request(request) {
        send_status(
            messenger,
            peer_pubkey,
            "Understood — starting work on this request.",
        )
        .await;
    }

    let session_id = load_codex_session(memory, peer_pubkey, &codex_config.working_dir);
    let memory_context = if session_id.is_none() {
        memory_context(memory, peer_pubkey, recorded_id, request)
    } else {
        None
    };
    let prompt = codex_phone_prompt(request, memory_context.as_deref());

    let response = match run_codex_and_report(
        messenger,
        memory,
        peer_pubkey,
        &prompt,
        codex_config,
        session_id.as_deref(),
    )
    .await
    {
        Ok(response) => response,
        Err(()) => return,
    };

    send_response_and_remember(messenger, memory, peer_pubkey, response).await;
    spawn_compaction_if_needed(memory, peer_pubkey, codex_config);
}

fn is_long_running_request(request: &str) -> bool {
    let normalized = normalize_transcript(request);
    if normalized.starts_with('/') {
        return false;
    }

    if normalized.len() > 180 {
        return true;
    }

    matches!(
        normalized.as_str(),
        "build the apk"
            | "build the android apk"
            | "build android apk"
            | "build an apk"
            | "build apk"
            | "investigate this issue"
            | "investigate this problem"
            | "investigate issue"
    ) || (normalized.contains("build")
        && (normalized.contains("apk") || normalized.contains("release")))
        || (normalized.contains("investigate")
            || normalized.contains("analysis")
            || normalized.contains("investigation")
            || normalized.contains("debug")
            || normalized.contains("trace")
            || normalized.contains("diagnose")
            || normalized.contains("root cause")
            || normalized.contains("refactor")
            || normalized.contains("large"))
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
    let Some(memory) = memory.as_ref() else {
        return None;
    };

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

fn write_worker_target_qr(pubkey: &str, pubkey_hex: &str, workdir: &Path, relays: &[String]) {
    let payload = serde_json::json!({
        "type": "nostr_codex_target",
        "version": 1,
        "name": worker_target_name(workdir),
        "pubkey": pubkey,
        "pubkey_hex": pubkey_hex,
        "workdir": workdir.to_string_lossy(),
        "relays": relays,
    });
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
        .unwrap_or_else(|_| workdir.join(".nostr-codex-target.svg"));
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
    if stored.is_some() {
        return stored;
    }

    if !env_bool("CODEX_RESUME_LATEST_BY_WORKDIR", true) {
        return None;
    }

    match latest_codex_session_for_workdir(workdir) {
        Ok(Some(session_id)) => {
            info!(
                "adopting latest existing Codex session {session_id} for {}",
                workdir.display()
            );
            Some(session_id)
        }
        Ok(None) => None,
        Err(err) => {
            warn!("failed to discover latest Codex session for workdir: {err:#}");
            None
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

    let target = canonical_path_key(workdir);
    let mut best: Option<(String, String)> = None;
    collect_latest_codex_session(sessions_dir, &target, &mut best)?;
    Ok(best.map(|(_, session_id)| session_id))
}

fn collect_latest_codex_session(
    path: &Path,
    target_workdir: &str,
    best: &mut Option<(String, String)>,
) -> Result<()> {
    if path.is_dir() {
        for entry in
            fs::read_dir(path).with_context(|| format!("failed to read `{}`", path.display()))?
        {
            let entry = entry?;
            collect_latest_codex_session(&entry.path(), target_workdir, best)?;
        }
        return Ok(());
    }

    if path.extension().and_then(|extension| extension.to_str()) != Some("jsonl") {
        return Ok(());
    }

    let Some(session) = parse_codex_session_file(path, target_workdir)? else {
        return Ok(());
    };
    match best {
        Some((best_timestamp, _)) if best_timestamp.as_str() >= session.0.as_str() => {}
        _ => *best = Some(session),
    }
    Ok(())
}

fn parse_codex_session_file(path: &Path, target_workdir: &str) -> Result<Option<(String, String)>> {
    let file = File::open(path).with_context(|| format!("failed to open `{}`", path.display()))?;
    let reader = BufReader::new(file);
    let mut first_line = None;
    let mut last_line = None;

    for line in reader.lines() {
        let line = line.with_context(|| format!("failed to read `{}`", path.display()))?;
        if first_line.is_none() {
            first_line = Some(line.clone());
        }
        if !line.trim().is_empty() {
            last_line = Some(line);
        }
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
    if canonical_path_key(Path::new(cwd)) != target_workdir {
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

    Ok(Some((last_timestamp, session_id.to_string())))
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
) {
    match messenger
        .send_response_to(receiver_pubkey, response.clone())
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
) -> std::result::Result<String, ()> {
    let result = match run_codex_session(prompt, codex_config, session_id).await {
        Ok(result) => result,
        Err(err) if is_codex_usage_limit_error(&err) => {
            match retry_codex_with_usage_limit_fallback(prompt, codex_config, session_id, err).await
            {
                Ok(result) => result,
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
            match run_codex_session(prompt, codex_config, None).await {
                Ok(result) => result,
                Err(err) if is_codex_usage_limit_error(&err) => {
                    match retry_codex_with_usage_limit_fallback(prompt, codex_config, None, err)
                        .await
                    {
                        Ok(result) => result,
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

async fn retry_codex_with_usage_limit_fallback(
    prompt: &str,
    codex_config: &CodexConfig,
    session_id: Option<&str>,
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

    run_codex_session(prompt, &fallback_config, session_id)
        .await
        .with_context(|| {
            format!(
                "Codex fallback model `{fallback_model}` failed after usage-limit error: {original}"
            )
        })
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
        peer_pubkey,
        relays,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

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
        write_session_fixture(
            &sessions_dir.join("2026/06/16/other.jsonl"),
            "other-session",
            &other_workdir,
            "2026-06-16T10:00:00Z",
            "2026-06-16T10:10:00Z",
        );

        let session = latest_codex_session_for_workdir_in(&sessions_dir, &workdir).unwrap();
        assert_eq!(session.as_deref(), Some("new-session"));
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
}
