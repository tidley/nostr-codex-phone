use std::sync::Arc;
use std::time::Duration;

use anyhow::{anyhow, Result};
use nostr_sdk::prelude::*;
use once_cell::sync::Lazy;
use tokio::sync::Mutex;

use crate::nostr_client::{default_relays, IncomingMessage, NostrConfig, NostrMessenger};

static SESSION: Lazy<Mutex<Option<Arc<NostrMessenger>>>> = Lazy::new(|| Mutex::new(None));

#[derive(Debug, Clone)]
pub struct BridgeNostrConfig {
    pub secret_key: String,
    pub peer_pubkey: String,
    pub relays: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct BridgeKeyPair {
    pub secret_key: String,
    pub public_key: String,
    pub public_key_hex: String,
}

#[derive(Debug, Clone)]
pub struct BridgeSessionStatus {
    pub public_key: String,
    pub public_key_hex: String,
    pub peer_pubkey: String,
    pub relay_count: u32,
}

#[derive(Debug, Clone)]
pub struct BridgeIncomingMessage {
    pub sender_pubkey: String,
    pub sender_pubkey_hex: String,
    pub kind: String,
    pub text: String,
    pub raw_json: String,
    pub event_id: String,
}

#[flutter_rust_bridge::frb(sync)]
pub fn nostr_default_relays() -> Vec<String> {
    default_relays()
}

#[flutter_rust_bridge::frb(sync)]
pub fn nostr_generate_secret_key() -> Result<BridgeKeyPair> {
    let keys = Keys::generate();
    key_pair_from_keys(keys)
}

#[flutter_rust_bridge::frb(sync)]
pub fn nostr_public_key(secret_key: String) -> Result<BridgeKeyPair> {
    let keys = Keys::parse(secret_key.trim())?;
    key_pair_from_keys(keys)
}

pub async fn nostr_start(config: BridgeNostrConfig) -> Result<BridgeSessionStatus> {
    let relays = clean_relays(config.relays);
    let old = {
        let mut session = SESSION.lock().await;
        session.take()
    };
    if let Some(old) = old {
        old.shutdown().await;
    }

    let messenger = Arc::new(
        NostrMessenger::connect(NostrConfig {
            secret_key: config.secret_key,
            peer_pubkey: config.peer_pubkey,
            relays: relays.clone(),
        })
        .await?,
    );

    let status = BridgeSessionStatus {
        public_key: messenger.public_key_bech32()?,
        public_key_hex: messenger.public_key_hex(),
        peer_pubkey: messenger.peer_pubkey_bech32()?,
        relay_count: relays.len() as u32,
    };

    let mut session = SESSION.lock().await;
    *session = Some(messenger);
    Ok(status)
}

pub async fn nostr_stop() -> Result<()> {
    let old = {
        let mut session = SESSION.lock().await;
        session.take()
    };
    if let Some(old) = old {
        old.shutdown().await;
    }
    Ok(())
}

pub async fn nostr_send_query(query: String) -> Result<String> {
    let query = query.trim().to_string();
    if query.is_empty() {
        return Err(anyhow!("query cannot be empty"));
    }
    active_session().await?.send_query(query).await
}

pub async fn nostr_send_response(response: String) -> Result<String> {
    active_session().await?.send_response(response).await
}

pub async fn nostr_send_error(error: String) -> Result<String> {
    active_session().await?.send_error(error).await
}

pub async fn nostr_next_message(timeout_ms: u64) -> Result<Option<BridgeIncomingMessage>> {
    let timeout = Duration::from_millis(timeout_ms.max(100));
    active_session()
        .await?
        .next_message(timeout)
        .await
        .map(|message| message.map(BridgeIncomingMessage::from))
}

pub async fn nostr_is_started() -> Result<bool> {
    Ok(SESSION.lock().await.is_some())
}

async fn active_session() -> Result<Arc<NostrMessenger>> {
    SESSION
        .lock()
        .await
        .clone()
        .ok_or_else(|| anyhow!("Nostr session is not started"))
}

fn key_pair_from_keys(keys: Keys) -> Result<BridgeKeyPair> {
    Ok(BridgeKeyPair {
        secret_key: keys.secret_key().to_bech32()?,
        public_key: keys.public_key().to_bech32()?,
        public_key_hex: keys.public_key().to_hex(),
    })
}

fn clean_relays(relays: Vec<String>) -> Vec<String> {
    relays
        .into_iter()
        .map(|relay| relay.trim().to_string())
        .filter(|relay| !relay.is_empty())
        .collect()
}

impl From<IncomingMessage> for BridgeIncomingMessage {
    fn from(value: IncomingMessage) -> Self {
        Self {
            sender_pubkey: value.sender_pubkey,
            sender_pubkey_hex: value.sender_pubkey_hex,
            kind: value.kind,
            text: value.text,
            raw_json: value.raw_json,
            event_id: value.event_id,
        }
    }
}
