use std::collections::{HashSet, VecDeque};
use std::time::Duration;

use anyhow::{anyhow, bail, Context, Result};
use nostr_sdk::prelude::*;
use serde_json::json;
use tokio::sync::{mpsc, Mutex};
use tokio::task::JoinHandle;

use crate::protocol::{parse_wire_message, AudioReference, WireMessage};

const SEND_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Debug, Clone)]
pub struct NostrConfig {
    pub secret_key: String,
    pub peer_pubkey: Option<String>,
    pub receive_pubkeys: Vec<String>,
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
    peer: Option<PublicKey>,
    receive_peers: Option<HashSet<PublicKey>>,
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
        let peer = config
            .peer_pubkey
            .as_deref()
            .map(str::trim)
            .filter(|peer| !peer.is_empty())
            .map(PublicKey::parse)
            .transpose()
            .context("invalid peer public key")?;
        let receive_peers = parse_receive_peers(config.receive_pubkeys, peer)?;
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
        let listener_receive_peers = receive_peers.clone();
        let listener = tokio::spawn(async move {
            let mut seen_event_ids = SeenEventIds::new(4096);

            while let Some(notification) = notifications.next().await {
                let ClientNotification::Event { event, .. } = notification else {
                    continue;
                };

                if event.kind != Kind::GiftWrap {
                    continue;
                }

                if !seen_event_ids.insert(event.id.to_hex()) {
                    continue;
                }

                match decode_gift_wrap(&listener_keys, &listener_receive_peers, &event) {
                    Ok(Some(message)) => match tx.try_send(message) {
                        Ok(()) => {}
                        Err(mpsc::error::TrySendError::Closed(_)) => break,
                        Err(mpsc::error::TrySendError::Full(_)) => {
                            tracing::warn!(
                                "dropping GiftWrap DM because the inbound queue is full"
                            );
                        }
                    },
                    Ok(None) => {}
                    Err(err) => tracing::warn!("failed to process GiftWrap DM: {err:#}"),
                }
            }
        });

        Ok(Self {
            keys,
            peer,
            receive_peers,
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

    pub fn peer_pubkey_bech32(&self) -> Result<Option<String>> {
        self.peer
            .map(|peer| peer.to_bech32())
            .transpose()
            .map_err(Into::into)
    }

    pub async fn send_query(&self, query: impl Into<String>) -> Result<String> {
        self.send_wire(WireMessage::query(query)).await
    }

    pub async fn send_audio(&self, audio: AudioReference) -> Result<String> {
        self.send_wire(WireMessage::audio(audio)).await
    }

    pub async fn send_response(&self, response: impl Into<String>) -> Result<String> {
        self.send_wire(WireMessage::response(response)).await
    }

    pub async fn send_transcript_to(
        &self,
        receiver_pubkey: &str,
        transcript: impl Into<String>,
    ) -> Result<String> {
        self.send_wire_to_pubkey(receiver_pubkey, WireMessage::transcript(transcript))
            .await
    }

    pub async fn send_transcript_for_event_to(
        &self,
        receiver_pubkey: &str,
        transcript: impl Into<String>,
        source_event_id: impl Into<String>,
        workdir: impl Into<String>,
    ) -> Result<String> {
        let receiver =
            PublicKey::parse(receiver_pubkey.trim()).context("invalid receiver pubkey")?;
        let payload = serde_json::to_string(&json!({
            "transcript": transcript.into(),
            "source_event_id": source_event_id.into(),
            "workdir": workdir.into(),
        }))?;
        self.send_payload_to(receiver, payload).await
    }

    pub async fn send_audio_retry_to(
        &self,
        receiver_pubkey: &str,
        format: impl Into<String>,
        reason: impl Into<String>,
    ) -> Result<String> {
        self.send_wire_to_pubkey(receiver_pubkey, WireMessage::audio_retry(format, reason))
            .await
    }

    pub async fn send_response_to(
        &self,
        receiver_pubkey: &str,
        response: impl Into<String>,
    ) -> Result<String> {
        self.send_wire_to_pubkey(receiver_pubkey, WireMessage::response(response))
            .await
    }

    pub async fn send_routed_response_to(
        &self,
        receiver_pubkey: &str,
        response: impl Into<String>,
        workdir: impl Into<String>,
    ) -> Result<String> {
        self.send_wire_to_pubkey(
            receiver_pubkey,
            WireMessage::routed_response(response, workdir),
        )
        .await
    }

    pub async fn send_error(&self, error: impl Into<String>) -> Result<String> {
        self.send_wire(WireMessage::error(error)).await
    }

    pub async fn send_error_to(
        &self,
        receiver_pubkey: &str,
        error: impl Into<String>,
    ) -> Result<String> {
        self.send_wire_to_pubkey(receiver_pubkey, WireMessage::error(error))
            .await
    }

    pub async fn send_wire(&self, message: WireMessage) -> Result<String> {
        let receiver = self
            .peer
            .ok_or_else(|| anyhow!("peer public key is not configured"))?;
        self.send_wire_to(receiver, message).await
    }

    pub async fn send_wire_to_pubkey(
        &self,
        receiver_pubkey: &str,
        message: WireMessage,
    ) -> Result<String> {
        let receiver =
            PublicKey::parse(receiver_pubkey.trim()).context("invalid receiver pubkey")?;
        self.send_wire_to(receiver, message).await
    }

    pub async fn send_wire_to(&self, receiver: PublicKey, message: WireMessage) -> Result<String> {
        let payload = message.to_json()?;
        self.send_payload_to(receiver, payload).await
    }

    async fn send_payload_to(&self, receiver: PublicKey, payload: String) -> Result<String> {
        let event = PrivateDirectMessageBuilder::new(receiver, payload)
            .finalize(&self.keys)
            .context("failed to build GiftWrapped DM")?;
        let client = self.client.clone();
        let mut send_task = tokio::spawn(async move {
            client
                .send_event(&event)
                .broadcast()
                .ack_policy(AckPolicy::none())
                .ok_timeout(Duration::from_secs(2))
                .await
        });
        let output = tokio::select! {
            result = &mut send_task => result
                .context("GiftWrapped DM send task failed")?,
            _ = tokio::time::sleep(SEND_TIMEOUT) => {
                send_task.abort();
                return Err(anyhow!("timed out sending GiftWrapped DM after {SEND_TIMEOUT:?}"));
            }
        }
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

    pub async fn fetch_recent_messages(&self, lookback: Duration) -> Result<Vec<IncomingMessage>> {
        let now = Timestamp::now();
        let since_secs = now.as_secs().saturating_sub(lookback.as_secs());
        let filter = Filter::new()
            .kind(Kind::GiftWrap)
            .pubkey(self.keys.public_key())
            .since(Timestamp::from(since_secs))
            .limit(1000);
        let events = self
            .client
            .fetch_events(filter)
            .timeout(Duration::from_secs(12))
            .await
            .context("failed to fetch recent GiftWrap DMs")?;
        let mut messages = Vec::new();
        for event in events.into_iter() {
            match decode_gift_wrap(&self.keys, &self.receive_peers, &event) {
                Ok(Some(message)) => messages.push(message),
                Ok(None) => {}
                Err(err) => tracing::warn!("failed to decode fetched GiftWrap DM: {err:#}"),
            }
        }
        messages.sort_by(|left, right| left.event_id.cmp(&right.event_id));
        Ok(messages)
    }

    pub async fn shutdown(&self) {
        self.listener.abort();
        self.client.shutdown().await;
    }
}

fn parse_receive_peers(
    raw_pubkeys: Vec<String>,
    selected_peer: Option<PublicKey>,
) -> Result<Option<HashSet<PublicKey>>> {
    let mut peers = HashSet::new();
    if let Some(peer) = selected_peer {
        peers.insert(peer);
    }
    for raw in raw_pubkeys {
        let cleaned = raw.trim();
        if cleaned.is_empty() {
            continue;
        }
        peers.insert(PublicKey::parse(cleaned).context("invalid receive peer public key")?);
    }
    if peers.is_empty() {
        Ok(None)
    } else {
        Ok(Some(peers))
    }
}

struct SeenEventIds {
    max_len: usize,
    order: VecDeque<String>,
    set: HashSet<String>,
}

impl SeenEventIds {
    fn new(max_len: usize) -> Self {
        Self {
            max_len: max_len.max(1),
            order: VecDeque::new(),
            set: HashSet::new(),
        }
    }

    fn insert(&mut self, event_id: String) -> bool {
        if self.set.contains(&event_id) {
            return false;
        }

        self.order.push_back(event_id.clone());
        self.set.insert(event_id);

        while self.order.len() > self.max_len {
            if let Some(oldest) = self.order.pop_front() {
                self.set.remove(&oldest);
            }
        }

        true
    }
}

fn decode_gift_wrap(
    keys: &Keys,
    expected_peers: &Option<HashSet<PublicKey>>,
    event: &Event,
) -> Result<Option<IncomingMessage>> {
    let UnwrappedGift { rumor, sender } =
        UnwrappedGift::from_gift_wrap(keys, event).context("failed to unwrap GiftWrap")?;

    if expected_peers
        .as_ref()
        .is_some_and(|peers| !peers.contains(&sender))
    {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seen_event_ids_rejects_duplicates_and_evicts_oldest() {
        let mut seen = SeenEventIds::new(2);

        assert!(seen.insert("a".to_string()));
        assert!(!seen.insert("a".to_string()));
        assert!(seen.insert("b".to_string()));
        assert!(seen.insert("c".to_string()));
        assert!(seen.insert("a".to_string()));
        assert!(!seen.insert("c".to_string()));
    }
}
