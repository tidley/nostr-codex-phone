use std::env;
use std::time::Duration;

use anyhow::{Context, Result};
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
                let response = match run_codex_and_report(
                    &messenger,
                    &message.sender_pubkey_hex,
                    &message.text,
                    &codex_config,
                )
                .await
                {
                    Ok(response) => response,
                    Err(()) => continue,
                };

                if let Err(err) = messenger
                    .send_response_to(&message.sender_pubkey_hex, response)
                    .await
                {
                    error!("failed to send response DM: {err:#}");
                }
            }
            "audio" => {
                info!(
                    "received audio event {} from {}",
                    message.event_id, message.sender_pubkey
                );
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
                if let Err(err) = messenger
                    .send_transcript_to(&message.sender_pubkey_hex, transcript.clone())
                    .await
                {
                    warn!("failed to send transcript DM: {err:#}");
                }

                let prompt = codex_phone_prompt(&transcript);
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

                if let Err(err) = messenger
                    .send_response_to(&message.sender_pubkey_hex, response)
                    .await
                {
                    error!("failed to send response DM: {err:#}");
                }
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

fn codex_phone_prompt(user_request: &str) -> String {
    format!(
        "You are responding to a request sent from a phone over Nostr.\n\
         Answer the user's request directly and concretely.\n\
         If the request is ambiguous, say what you heard and ask one concise clarifying question.\n\
         Do not answer with a generic greeting such as \"I'm here\" unless the user only greeted you.\n\n\
         User request:\n{user_request}"
    )
}

fn transcript_preview(transcript: &str) -> String {
    let normalized = transcript.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut preview = normalized.chars().take(160).collect::<String>();
    if normalized.chars().count() > 160 {
        preview.push_str("...");
    }
    preview
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
