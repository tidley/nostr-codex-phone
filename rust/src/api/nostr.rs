use std::sync::Arc;
use std::time::Duration;

use anyhow::{anyhow, Result};
use fips_mobile::{FipsMobileQuicSession, FipsMobileQuicSessionConfig, Identity};
use nostr_sdk::prelude::*;
use once_cell::sync::Lazy;
use tokio::sync::Mutex;

use crate::blossom::{download_attachment, upload_audio, BlossomUploadConfig};
use crate::nostr_client::{default_relays, IncomingMessage, NostrConfig, NostrMessenger};
use crate::protocol::{AudioEncryption, AudioReference, MediaReference};
use crate::realtime_audio::{
    RealtimeAudioDecoder, RealtimeAudioEncoder, RealtimeAudioPacket,
    REALTIME_AUDIO_HARNESS_ECHO_FLAG,
};

static SESSION: Lazy<Mutex<Option<Arc<NostrMessenger>>>> = Lazy::new(|| Mutex::new(None));
static CALL_SESSION: Lazy<Mutex<Option<FipsMobileQuicSession>>> = Lazy::new(|| Mutex::new(None));
static REALTIME_AUDIO: Lazy<Mutex<Option<RealtimeAudioPipeline>>> = Lazy::new(|| Mutex::new(None));

struct RealtimeAudioPipeline {
    encoder: RealtimeAudioEncoder,
    decoder: RealtimeAudioDecoder,
}

impl RealtimeAudioPipeline {
    fn new() -> Result<Self> {
        Ok(Self {
            encoder: RealtimeAudioEncoder::new()?,
            decoder: RealtimeAudioDecoder::new()?,
        })
    }
}

#[derive(Debug, Clone)]
pub struct BridgeNostrConfig {
    pub secret_key: String,
    pub peer_pubkey: String,
    pub receive_pubkeys: Vec<String>,
    pub relays: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct BridgeFipsCallConfig {
    pub secret_key: String,
    pub relays: Vec<String>,
    pub stun_servers: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct BridgeFipsCallStatus {
    pub state: String,
    pub max_datagram_bytes: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct BridgeRealtimeAudioPacket {
    pub sequence: u16,
    pub timestamp_48khz: u32,
    pub flags: u8,
    pub opus_payload: Vec<u8>,
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

#[derive(Debug, Clone)]
pub struct BridgeAudioReference {
    pub url: String,
    pub sha256: String,
    pub size: u64,
    pub media_type: String,
    pub name: Option<String>,
    pub encryption: Option<BridgeAudioEncryption>,
}

#[derive(Debug, Clone)]
pub struct BridgeAudioEncryption {
    pub algorithm: String,
    pub key: String,
    pub nonce: String,
    pub plaintext_sha256: String,
    pub plaintext_size: u64,
    pub plaintext_media_type: String,
}

#[derive(Debug, Clone)]
pub struct BridgeBlossomUploadConfig {
    pub secret_key: String,
    pub server_url: String,
    pub file_path: String,
    pub content_type: String,
    pub file_name: Option<String>,
}

#[derive(Debug, Clone)]
pub struct BridgeDownloadedAttachment {
    pub path: String,
    pub media_type: String,
    pub name: String,
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
            peer_pubkey: Some(config.peer_pubkey),
            receive_pubkeys: config.receive_pubkeys,
            relays: relays.clone(),
        })
        .await?,
    );

    let status = BridgeSessionStatus {
        public_key: messenger.public_key_bech32()?,
        public_key_hex: messenger.public_key_hex(),
        peer_pubkey: messenger.peer_pubkey_bech32()?.unwrap_or_default(),
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

pub async fn nostr_send_ephemeral_query(query: String, expires_in_seconds: u64) -> Result<String> {
    let query = query.trim().to_string();
    if query.is_empty() {
        return Err(anyhow!("query cannot be empty"));
    }
    active_session()
        .await?
        .send_ephemeral_query(query, Duration::from_secs(expires_in_seconds.clamp(1, 30)))
        .await
}

pub async fn blossom_upload_audio(
    config: BridgeBlossomUploadConfig,
) -> Result<BridgeAudioReference> {
    upload_audio(BlossomUploadConfig {
        secret_key: config.secret_key,
        server_url: config.server_url,
        file_path: config.file_path,
        content_type: config.content_type,
        file_name: config.file_name,
    })
    .await
    .map(BridgeAudioReference::from)
}

pub async fn blossom_download_attachment(
    attachment: BridgeAudioReference,
    destination_dir: String,
) -> Result<BridgeDownloadedAttachment> {
    download_attachment(
        MediaReference {
            url: attachment.url,
            sha256: attachment.sha256,
            size: attachment.size,
            media_type: attachment.media_type,
            name: attachment.name,
            encryption: attachment.encryption.map(AudioEncryption::from),
        },
        &destination_dir,
    )
    .await
    .map(|attachment| BridgeDownloadedAttachment {
        path: attachment.path,
        media_type: attachment.media_type,
        name: attachment.name,
    })
}

pub async fn nostr_send_audio(audio: BridgeAudioReference) -> Result<String> {
    active_session().await?.send_audio(audio.into()).await
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

pub async fn nostr_fetch_recent_messages(lookback_secs: u64) -> Result<Vec<BridgeIncomingMessage>> {
    active_session()
        .await?
        .fetch_recent_messages(Duration::from_secs(lookback_secs.max(60)))
        .await
        .map(|messages| {
            messages
                .into_iter()
                .map(BridgeIncomingMessage::from)
                .collect()
        })
}

pub async fn nostr_is_started() -> Result<bool> {
    Ok(SESSION.lock().await.is_some())
}

pub async fn fips_call_connect(
    config: BridgeFipsCallConfig,
    peer_npub: String,
) -> Result<BridgeFipsCallStatus> {
    let audio = RealtimeAudioPipeline::new()?;
    let mut session = build_fips_call_session(config)?;
    let peer_npub = PublicKey::parse(peer_npub.trim())?.to_bech32()?;
    session.connect(&peer_npub).await?;
    let status = fips_call_status(&session);
    *CALL_SESSION.lock().await = Some(session);
    *REALTIME_AUDIO.lock().await = Some(audio);
    Ok(status)
}

pub async fn fips_call_accept(config: BridgeFipsCallConfig) -> Result<BridgeFipsCallStatus> {
    let audio = RealtimeAudioPipeline::new()?;
    let mut session = build_fips_call_session(config)?;
    session.accept().await?;
    let status = fips_call_status(&session);
    *CALL_SESSION.lock().await = Some(session);
    *REALTIME_AUDIO.lock().await = Some(audio);
    Ok(status)
}

pub async fn fips_call_send_datagram(payload: Vec<u8>) -> Result<()> {
    let session = CALL_SESSION.lock().await;
    session
        .as_ref()
        .ok_or_else(|| anyhow!("FIPS call is not active"))?
        .send_datagram(&payload)?;
    Ok(())
}

pub async fn fips_call_receive_datagram(timeout_ms: u64) -> Result<Option<Vec<u8>>> {
    // Keep the session lock for only a short receive window so microphone sends
    // and hangup can interleave with the receive loop.
    let session = CALL_SESSION.lock().await;
    let session = session
        .as_ref()
        .ok_or_else(|| anyhow!("FIPS call is not active"))?;
    match tokio::time::timeout(
        Duration::from_millis(timeout_ms.clamp(1, 50)),
        session.receive_datagram(),
    )
    .await
    {
        Ok(result) => result.map(Some).map_err(Into::into),
        Err(_) => Ok(None),
    }
}

pub async fn fips_call_send_realtime_audio(packet: BridgeRealtimeAudioPacket) -> Result<()> {
    fips_call_send_datagram(RealtimeAudioPacket::from(packet).encode()?).await
}

pub async fn fips_call_receive_realtime_audio(
    timeout_ms: u64,
) -> Result<Option<BridgeRealtimeAudioPacket>> {
    fips_call_receive_datagram(timeout_ms)
        .await?
        .map(|datagram| RealtimeAudioPacket::decode(&datagram).map(BridgeRealtimeAudioPacket::from))
        .transpose()
}

/// Encodes one 20 ms, 48 kHz mono signed-16-bit PCM frame and sends it as an
/// Opus realtime datagram.
pub async fn fips_call_send_realtime_pcm(pcm: Vec<u8>) -> Result<()> {
    let datagram = {
        let mut audio = REALTIME_AUDIO.lock().await;
        let audio = audio
            .as_mut()
            .ok_or_else(|| anyhow!("FIPS realtime audio is not active"))?;
        audio.encoder.encode_pcm(&pcm)?.encode()?
    };
    fips_call_send_datagram(datagram).await
}

/// Receives an Opus realtime datagram and returns PCM only when the small
/// reorder buffer has a frame ready for playout.
pub async fn fips_call_receive_realtime_pcm(timeout_ms: u64) -> Result<Option<Vec<u8>>> {
    let Some(datagram) = fips_call_receive_datagram(timeout_ms).await? else {
        return Ok(None);
    };
    let packet = RealtimeAudioPacket::decode(&datagram)?;
    if packet.flags & REALTIME_AUDIO_HARNESS_ECHO_FLAG != 0 {
        // A harness peer proves the mobile FIPS datagram path by echoing its
        // encoded frame. This never reaches capture or speaker playback.
        fips_call_send_datagram(datagram).await?;
        return Ok(None);
    }
    let mut audio = REALTIME_AUDIO.lock().await;
    let audio = audio
        .as_mut()
        .ok_or_else(|| anyhow!("FIPS realtime audio is not active"))?;
    audio.decoder.push(packet)
}

pub async fn fips_call_stop() -> Result<()> {
    let session = CALL_SESSION.lock().await.take();
    if let Some(mut session) = session {
        session.stop().await?;
    }
    *REALTIME_AUDIO.lock().await = None;
    Ok(())
}

fn build_fips_call_session(config: BridgeFipsCallConfig) -> Result<FipsMobileQuicSession> {
    let identity = Identity::from_secret_str(config.secret_key.trim())?;
    let mut session_config = FipsMobileQuicSessionConfig::default();
    let relays = clean_relays(config.relays);
    if !relays.is_empty() {
        session_config.discovery.advert_relays = relays.clone();
        session_config.discovery.dm_relays = relays;
    }
    let stun_servers = clean_relays(config.stun_servers);
    if !stun_servers.is_empty() {
        session_config.discovery.stun_servers = stun_servers;
    }
    Ok(FipsMobileQuicSession::new(identity, session_config))
}

fn fips_call_status(session: &FipsMobileQuicSession) -> BridgeFipsCallStatus {
    BridgeFipsCallStatus {
        state: format!("{:?}", session.status()).to_lowercase(),
        max_datagram_bytes: session
            .max_datagram_size()
            .ok()
            .and_then(|size| u32::try_from(size).ok()),
    }
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

impl From<AudioReference> for BridgeAudioReference {
    fn from(value: AudioReference) -> Self {
        Self {
            url: value.url,
            sha256: value.sha256,
            size: value.size,
            media_type: value.media_type,
            name: value.name,
            encryption: value.encryption.map(BridgeAudioEncryption::from),
        }
    }
}

impl From<BridgeAudioReference> for AudioReference {
    fn from(value: BridgeAudioReference) -> Self {
        Self {
            url: value.url,
            sha256: value.sha256,
            size: value.size,
            media_type: value.media_type,
            name: value.name,
            encryption: value.encryption.map(AudioEncryption::from),
        }
    }
}

impl From<AudioEncryption> for BridgeAudioEncryption {
    fn from(value: AudioEncryption) -> Self {
        Self {
            algorithm: value.algorithm,
            key: value.key,
            nonce: value.nonce,
            plaintext_sha256: value.plaintext_sha256,
            plaintext_size: value.plaintext_size,
            plaintext_media_type: value.plaintext_media_type,
        }
    }
}

impl From<BridgeAudioEncryption> for AudioEncryption {
    fn from(value: BridgeAudioEncryption) -> Self {
        Self {
            algorithm: value.algorithm,
            key: value.key,
            nonce: value.nonce,
            plaintext_sha256: value.plaintext_sha256,
            plaintext_size: value.plaintext_size,
            plaintext_media_type: value.plaintext_media_type,
        }
    }
}

impl From<BridgeRealtimeAudioPacket> for RealtimeAudioPacket {
    fn from(value: BridgeRealtimeAudioPacket) -> Self {
        Self {
            sequence: value.sequence,
            timestamp_48khz: value.timestamp_48khz,
            flags: value.flags,
            opus_payload: value.opus_payload,
        }
    }
}

impl From<RealtimeAudioPacket> for BridgeRealtimeAudioPacket {
    fn from(value: RealtimeAudioPacket) -> Self {
        Self {
            sequence: value.sequence,
            timestamp_48khz: value.timestamp_48khz,
            flags: value.flags,
            opus_payload: value.opus_payload,
        }
    }
}
