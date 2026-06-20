use std::env;
use std::io::{self, Read};

use anyhow::{bail, Context, Result};
use rust_lib_nostr_codex_phone::nostr_client::{default_relays, NostrConfig, NostrMessenger};

#[tokio::main]
async fn main() -> Result<()> {
    let response = response_from_args_or_stdin()?;
    let messenger = NostrMessenger::connect(nostr_config_from_env()?).await?;
    let peer = messenger
        .peer_pubkey_bech32()?
        .context("NOSTR_PEER_PUBKEY must be set to the phone npub")?;

    let event_id = messenger
        .send_response(response)
        .await
        .context("failed to send response DM")?;

    println!("sent response DM to {peer}");
    println!("event id: {event_id}");
    messenger.shutdown().await;
    Ok(())
}

fn response_from_args_or_stdin() -> Result<String> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let response = if args.is_empty() {
        let mut stdin = String::new();
        io::stdin()
            .read_to_string(&mut stdin)
            .context("failed to read response from stdin")?;
        stdin
    } else {
        args.join(" ")
    };

    let response = response.trim().to_string();
    if response.is_empty() {
        bail!("response text cannot be empty");
    }
    Ok(response)
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
        receive_pubkeys: peer_pubkey.iter().cloned().collect(),
        peer_pubkey,
        relays,
    })
}
