use std::collections::HashMap;
use std::env;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
#[path = "nostr_codex_server/memory.rs"]
mod memory;
use memory::{MemoryConfig, MemoryStore, RecordedMessage};
use rust_lib_nostr_codex_phone::codex::{run_codex, run_codex_session, CodexConfig};
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

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "nostr_codex_server=info,warn".into()),
        )
        .init();

    let nostr_config = nostr_config_from_env()?;
    let codex_config = CodexConfig::from_env()?;
    let audio_config = AudioConfig::from_env();
    let transcribe_config = TranscribeConfig::from_env()?;
    let memory_config = MemoryConfig::from_env(&codex_config.working_dir);
    let memory_probe = open_memory_store(memory_config.clone());
    let messenger = Arc::new(NostrMessenger::connect(nostr_config.clone()).await?);

    info!("server pubkey: {}", messenger.public_key_bech32()?);
    info!("server pubkey hex: {}", messenger.public_key_hex());
    match &nostr_config.peer_pubkey {
        Some(peer) => info!("peer pubkey: {peer}"),
        None => warn!("peer pubkey not configured; accepting DMs from any sender"),
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
    drop(memory_probe);

    let mut peer_workers = HashMap::<String, mpsc::Sender<IncomingMessage>>::new();

    loop {
        let Some(message) = messenger.next_message(Duration::from_secs(3600)).await? else {
            continue;
        };

        let worker_key = message.sender_pubkey_hex.clone();
        let sender = peer_workers.entry(worker_key.clone()).or_insert_with(|| {
            let (tx, rx) = mpsc::channel(32);
            tokio::spawn(peer_worker(
                worker_key,
                rx,
                Arc::clone(&messenger),
                memory_config.clone(),
                codex_config.clone(),
                audio_config.clone(),
                transcribe_config.clone(),
            ));
            tx
        });

        if sender.send(message).await.is_err() {
            warn!("peer worker stopped; dropping incoming message");
        }
    }
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
        process_message(
            message,
            &messenger,
            &mut memory,
            &codex_config,
            &audio_config,
            &transcribe_config,
        )
        .await;
    }
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
    memory
        .as_ref()
        .and_then(|memory| match memory.codex_session(peer_pubkey, workdir) {
            Ok(session_id) => session_id,
            Err(err) => {
                warn!("failed to load Codex session; starting a fresh turn: {err:#}");
                None
            }
        })
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

fn nostr_config_from_env() -> Result<NostrConfig> {
    let secret_key = env::var("NOSTR_SECRET_KEY")
        .context("NOSTR_SECRET_KEY must contain the server nsec/secret key")?;
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
}
