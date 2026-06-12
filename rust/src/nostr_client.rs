use std::time::Duration;

use anyhow::{anyhow, bail, Context, Result};
use nostr_sdk::prelude::*;
use tokio::sync::{mpsc, Mutex};
use tokio::task::JoinHandle;

use crate::protocol::{parse_wire_message, WireMessage};

#[derive(Debug, Clone)]
pub struct NostrConfig {
    pub secret_key: String,
    pub peer_pubkey: String,
    pub relays: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct IncomingMessage {
    pub sender_pubkey: String,
    pub sender_pubkey_hex: String,
    pub kind: String,
    pub text: String,
    pub raw_json: String,
    pub event_id: String,
}

pub struct NostrMessenger {
    keys: Keys,
    peer: PublicKey,
    client: Client,
    incoming: Mutex<mpsc::Receiver<IncomingMessage>>,
    listener: JoinHandle<()>,
}

impl NostrMessenger {
    pub async fn connect(config: NostrConfig) -> Result<Self> {
        if config.relays.is_empty() {
            bail!("at least one relay URL is required");
        }

        let keys =
            Keys::parse(config.secret_key.trim()).context("invalid local nsec/secret key")?;
        let peer =
            PublicKey::parse(config.peer_pubkey.trim()).context("invalid peer public key")?;
        let client = Client::default();

        for relay in &config.relays {
            client
                .add_relay(relay.trim())
                .await
                .with_context(|| format!("failed to add relay `{relay}`"))?;
        }

        let mut notifications = client.notifications();
        client.connect().await;

        let subscription = Filter::new()
            .kind(Kind::GiftWrap)
            .pubkey(keys.public_key())
            .limit(0);
        client
            .subscribe(subscription)
            .await
            .context("failed to subscribe to GiftWrap DMs")?;

        let (tx, rx) = mpsc::channel(128);
        let listener_keys = keys.clone();
        let listener_peer = peer;
        let listener = tokio::spawn(async move {
            while let Some(notification) = notifications.next().await {
                let ClientNotification::Event { event, .. } = notification else {
                    continue;
                };

                if event.kind != Kind::GiftWrap {
                    continue;
                }

                match decode_gift_wrap(&listener_keys, listener_peer, &event) {
                    Ok(Some(message)) => {
                        if tx.send(message).await.is_err() {
                            break;
                        }
                    }
                    Ok(None) => {}
                    Err(err) => tracing::warn!("failed to process GiftWrap DM: {err:#}"),
                }
            }
        });

        Ok(Self {
            keys,
            peer,
            client,
            incoming: Mutex::new(rx),
            listener,
        })
    }

    pub fn public_key(&self) -> PublicKey {
        self.keys.public_key()
    }

    pub fn public_key_bech32(&self) -> Result<String> {
        Ok(self.keys.public_key().to_bech32()?)
    }

    pub fn public_key_hex(&self) -> String {
        self.keys.public_key().to_hex()
    }

    pub fn peer_pubkey_bech32(&self) -> Result<String> {
        Ok(self.peer.to_bech32()?)
    }

    pub async fn send_query(&self, query: impl Into<String>) -> Result<String> {
        self.send_wire(WireMessage::query(query)).await
    }

    pub async fn send_response(&self, response: impl Into<String>) -> Result<String> {
        self.send_wire(WireMessage::response(response)).await
    }

    pub async fn send_error(&self, error: impl Into<String>) -> Result<String> {
        self.send_wire(WireMessage::error(error)).await
    }

    pub async fn send_wire(&self, message: WireMessage) -> Result<String> {
        let payload = message.to_json()?;
        let event = PrivateDirectMessageBuilder::new(self.peer, payload)
            .finalize(&self.keys)
            .context("failed to build GiftWrapped DM")?;
        let output = self
            .client
            .send_event(&event)
            .broadcast()
            .await
            .context("failed to send GiftWrapped DM")?;

        if output.success.is_empty() {
            return Err(anyhow!(
                "no relay accepted the DM; relay failures: {:?}",
                output.failed
            ));
        }

        Ok(output.id().to_hex())
    }

    pub async fn next_message(
        &self,
        timeout_duration: Duration,
    ) -> Result<Option<IncomingMessage>> {
        let mut incoming = self.incoming.lock().await;
        match tokio::time::timeout(timeout_duration, incoming.recv()).await {
            Ok(Some(message)) => Ok(Some(message)),
            Ok(None) => Err(anyhow!("Nostr listener has stopped")),
            Err(_) => Ok(None),
        }
    }

    pub async fn shutdown(&self) {
        self.listener.abort();
        self.client.shutdown().await;
    }
}

fn decode_gift_wrap(
    keys: &Keys,
    expected_peer: PublicKey,
    event: &Event,
) -> Result<Option<IncomingMessage>> {
    let UnwrappedGift { rumor, sender } =
        UnwrappedGift::from_gift_wrap(keys, event).context("failed to unwrap GiftWrap")?;

    if sender != expected_peer {
        return Ok(None);
    }

    let sender_pubkey = sender
        .to_bech32()
        .unwrap_or_else(|_| sender.to_hex().to_string());
    let sender_pubkey_hex = sender.to_hex();
    let event_id = event.id.to_hex();

    if rumor.kind != Kind::PrivateDirectMessage {
        return Ok(Some(IncomingMessage {
            sender_pubkey,
            sender_pubkey_hex,
            kind: "unsupported".to_string(),
            text: format!("unsupported rumor kind: {}", rumor.kind),
            raw_json: rumor.content,
            event_id,
        }));
    }

    let raw_json = rumor.content;
    let (kind, text) = match parse_wire_message(&raw_json) {
        Ok(message) => (message.kind().to_string(), message.text().to_string()),
        Err(err) => ("invalid".to_string(), err.to_string()),
    };

    Ok(Some(IncomingMessage {
        sender_pubkey,
        sender_pubkey_hex,
        kind,
        text,
        raw_json,
        event_id,
    }))
}

pub fn default_relays() -> Vec<String> {
    vec![
        "wss://relay.damus.io".to_string(),
        "wss://nos.lol".to_string(),
        "wss://nostr.mom".to_string(),
    ]
}
