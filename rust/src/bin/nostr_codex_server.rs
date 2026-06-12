use std::env;
use std::time::Duration;

use anyhow::{Context, Result};
use rust_lib_nostr_codex_phone::codex::{run_codex, CodexConfig};
use rust_lib_nostr_codex_phone::nostr_client::{default_relays, NostrConfig, NostrMessenger};
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

    loop {
        let Some(message) = messenger.next_message(Duration::from_secs(3600)).await? else {
            continue;
        };

        match message.kind.as_str() {
            "query" => {
                info!("received query event {}", message.event_id);
                let response = match run_codex(&message.text, &codex_config).await {
                    Ok(response) => response,
                    Err(err) => {
                        error!("codex failed: {err:#}");
                        if let Err(send_err) = messenger
                            .send_error_to(
                                &message.sender_pubkey_hex,
                                format!("Codex failed: {err:#}"),
                            )
                            .await
                        {
                            error!("failed to send error DM: {send_err:#}");
                        }
                        continue;
                    }
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
