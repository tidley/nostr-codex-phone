use std::env;
use std::time::Duration;

use anyhow::{Context, Result};
#[path = "nostr_codex_server/memory.rs"]
mod memory;
use memory::{MemoryConfig, MemoryStore, RecordedMessage};
use rust_lib_nostr_codex_phone::codex::{run_codex, CodexConfig};
use rust_lib_nostr_codex_phone::nostr_client::{default_relays, NostrConfig, NostrMessenger};
use rust_lib_nostr_codex_phone::protocol::{parse_wire_message, WireMessage};
use rust_lib_nostr_codex_phone::transcribe::{
    download_blossom_audio, transcribe_audio, AudioConfig, TranscribeConfig,
};
use tracing::{error, info, warn};

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
    let mut memory = open_memory_store(MemoryConfig::from_env(&codex_config.working_dir));
    let messenger = NostrMessenger::connect(nostr_config.clone()).await?;

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
        "transcribe command: {} {}",
        transcribe_config.bin,
        transcribe_config.args.join(" ")
    );
    info!("max audio bytes: {}", audio_config.max_bytes);
    match &memory {
        Some(memory) => info!("memory database: {}", memory.db_path().display()),
        None => warn!("SQLite memory is disabled or unavailable"),
    }

    loop {
        let Some(message) = messenger.next_message(Duration::from_secs(3600)).await? else {
            continue;
        };

        match message.kind.as_str() {
            "query" => {
                info!(
                    "received query event {} from {}",
                    message.event_id, message.sender_pubkey
                );

                if let Some(response) =
                    handle_memory_command(&mut memory, &message.sender_pubkey_hex, &message.text)
                {
                    send_response(&messenger, &message.sender_pubkey_hex, response).await;
                    continue;
                }

                let Some(recorded) = remember_incoming(
                    &mut memory,
                    &message.sender_pubkey_hex,
                    &message.event_id,
                    "query",
                    &message.text,
                ) else {
                    continue;
                };
                if !recorded.inserted {
                    info!("ignored already-persisted query event {}", message.event_id);
                    continue;
                }

                let prompt = codex_phone_prompt(
                    &message.text,
                    memory_context(&memory, &message.sender_pubkey_hex, recorded.id).as_deref(),
                );
                let response = match run_codex_and_report(
                    &messenger,
                    &message.sender_pubkey_hex,
                    &prompt,
                    &codex_config,
                )
                .await
                {
                    Ok(response) => response,
                    Err(()) => continue,
                };

                send_response_and_remember(
                    &messenger,
                    &mut memory,
                    &message.sender_pubkey_hex,
                    response,
                )
                .await;
                compact_memory_if_needed(&mut memory, &message.sender_pubkey_hex, &codex_config)
                    .await;
            }
            "audio" => {
                info!(
                    "received audio event {} from {}",
                    message.event_id, message.sender_pubkey
                );
                let Some(recorded) = remember_incoming(
                    &mut memory,
                    &message.sender_pubkey_hex,
                    &message.event_id,
                    "audio",
                    &message.text,
                ) else {
                    continue;
                };
                if !recorded.inserted {
                    info!("ignored already-persisted audio event {}", message.event_id);
                    continue;
                }

                let audio = match parse_wire_message(&message.raw_json) {
                    Ok(WireMessage::Audio { audio }) => audio,
                    Ok(_) => {
                        warn!("audio event parsed as a different message kind");
                        continue;
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
                        continue;
                    }
                };

                let downloaded = match download_blossom_audio(&audio, &audio_config).await {
                    Ok(downloaded) => downloaded,
                    Err(err) => {
                        error!("audio download failed: {err:#}");
                        if let Err(send_err) = messenger
                            .send_error_to(
                                &message.sender_pubkey_hex,
                                format!("Audio download failed: {err:#}"),
                            )
                            .await
                        {
                            error!("failed to send audio download error DM: {send_err:#}");
                        }
                        continue;
                    }
                };

                let transcript = match transcribe_audio(&downloaded.path, &transcribe_config).await
                {
                    Ok(transcript) => transcript,
                    Err(err) => {
                        error!("audio transcription failed: {err:#}");
                        if let Err(send_err) = messenger
                            .send_error_to(
                                &message.sender_pubkey_hex,
                                format!("Audio transcription failed: {err:#}"),
                            )
                            .await
                        {
                            error!("failed to send transcription error DM: {send_err:#}");
                        }
                        continue;
                    }
                };

                info!(
                    "transcribed audio event {}: {}",
                    message.event_id,
                    transcript_preview(&transcript)
                );
                if let Some(memory) = memory.as_mut() {
                    if let Err(err) = memory.update_message(recorded.id, "transcript", &transcript)
                    {
                        warn!("failed to store transcript memory: {err:#}");
                    }
                }

                if let Err(err) = messenger
                    .send_transcript_to(&message.sender_pubkey_hex, transcript.clone())
                    .await
                {
                    warn!("failed to send transcript DM: {err:#}");
                }

                if let Some(response) =
                    handle_memory_command(&mut memory, &message.sender_pubkey_hex, &transcript)
                {
                    send_response(&messenger, &message.sender_pubkey_hex, response).await;
                    continue;
                }

                let prompt = codex_phone_prompt(
                    &transcript,
                    memory_context(&memory, &message.sender_pubkey_hex, recorded.id).as_deref(),
                );
                let response = match run_codex_and_report(
                    &messenger,
                    &message.sender_pubkey_hex,
                    &prompt,
                    &codex_config,
                )
                .await
                {
                    Ok(response) => response,
                    Err(()) => continue,
                };

                send_response_and_remember(
                    &messenger,
                    &mut memory,
                    &message.sender_pubkey_hex,
                    response,
                )
                .await;
                compact_memory_if_needed(&mut memory, &message.sender_pubkey_hex, &codex_config)
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
) -> Option<String> {
    let Some(memory) = memory.as_ref() else {
        return None;
    };

    match memory.prompt_context(peer_pubkey, before_message_id) {
        Ok(context) => context,
        Err(err) => {
            warn!("failed to load memory context; continuing without it: {err:#}");
            None
        }
    }
}

fn handle_memory_command(
    memory: &mut Option<MemoryStore>,
    peer_pubkey: &str,
    request: &str,
) -> Option<String> {
    let command = request.trim().to_ascii_lowercase();
    match command.as_str() {
        "/memory" | "/summary" => Some(match memory.as_ref() {
            Some(memory) => memory
                .status_text(peer_pubkey)
                .unwrap_or_else(|err| format!("Memory status failed: {err:#}")),
            None => "Memory is disabled.".to_string(),
        }),
        "/forget" | "/reset" | "/reset memory" => Some(match memory.as_mut() {
            Some(memory) => match memory.clear_peer(peer_pubkey) {
                Ok(()) => "Memory reset for this peer.".to_string(),
                Err(err) => format!("Memory reset failed: {err:#}"),
            },
            None => "Memory is disabled.".to_string(),
        }),
        _ => None,
    }
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
    receiver_pubkey: &str,
    prompt: &str,
    codex_config: &CodexConfig,
) -> std::result::Result<String, ()> {
    match run_codex(prompt, codex_config).await {
        Ok(response) => Ok(response),
        Err(err) => {
            error!("codex failed: {err:#}");
            if let Err(send_err) = messenger
                .send_error_to(receiver_pubkey, format!("Codex failed: {err:#}"))
                .await
            {
                error!("failed to send error DM: {send_err:#}");
            }
            Err(())
        }
    }
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
