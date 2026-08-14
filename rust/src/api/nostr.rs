use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, bail, Result};
use fips_client::{call_status, clean_endpoints, FipsClientConfig};
use fips_mobile::{
    fips_application_service_frames, FipsApplicationEnvelope, FipsApplicationFrameAssembler,
    FipsMobileClient, FipsMobileQuicSession, FipsMobileQuicSessionConfig,
};
use nostr_sdk::prelude::*;
use once_cell::sync::Lazy;
use tokio::sync::{oneshot, Mutex};

use crate::api::fips_relay::{create_offer, new_session_id, verify_offer};
use crate::blossom::{download_attachment, upload_audio, BlossomUploadConfig};
use crate::nostr_client::{default_relays, IncomingMessage, NostrConfig, NostrMessenger};
use crate::protocol::{parse_wire_message, AudioEncryption, AudioReference, MediaReference};
use crate::realtime_audio::{
    RealtimeAudioDecoder, RealtimeAudioEncoder, RealtimeAudioPacket,
    REALTIME_AUDIO_HARNESS_ECHO_FLAG,
};
use crate::realtime_video::RealtimeVideoFragment;

static SESSION: Lazy<Mutex<Option<Arc<NostrMessenger>>>> = Lazy::new(|| Mutex::new(None));
static CALL_SESSION: Lazy<Mutex<Option<FipsMobileQuicSession>>> = Lazy::new(|| Mutex::new(None));
// Workspace frames use one embedded FIPS node, separate from the QUIC call
// session whose datagrams are consumed by realtime media.
static WORKSPACE_SNAPSHOT_CLIENTS: Lazy<Mutex<HashMap<String, Arc<Mutex<WorkspaceFipsClient>>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static CALL_ACCEPT_CANCEL: Lazy<Mutex<Option<oneshot::Sender<()>>>> =
    Lazy::new(|| Mutex::new(None));
static REALTIME_AUDIO: Lazy<Mutex<Option<RealtimeAudioPipeline>>> = Lazy::new(|| Mutex::new(None));
static GROUP_CALL_SESSIONS: Lazy<Mutex<HashMap<String, FipsMobileQuicSession>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static GROUP_CALL_AUDIO: Lazy<Mutex<HashMap<String, RealtimeAudioPipeline>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static GROUP_CALL_ACCEPT_CANCEL: Lazy<Mutex<HashMap<String, oneshot::Sender<()>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static RELAY_TUNNELS: Lazy<Mutex<HashMap<String, RelayTunnel>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static RELAY_ACCEPT_CANCEL: Lazy<Mutex<HashMap<String, oneshot::Sender<()>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static RELAY_PENDING: Lazy<Mutex<HashMap<String, PendingRelaySession>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static RELAY_USED_OFFERS: Lazy<Mutex<HashMap<String, u64>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

const WORKSPACE_FIPS_SERVICE_PORT: u16 = 49_160;
const MAX_RELAY_SESSIONS: usize = 128;

struct RelayTunnel {
    session: FipsMobileQuicSession,
    peer_npub: String,
    expires_at: u64,
}

struct PendingRelaySession {
    session: FipsMobileQuicSession,
    expires_at: u64,
}

// This client carries both the legacy snapshot envelopes and future app envelopes.
// The public snapshot bridge names remain stable for the current Flutter client.
struct WorkspaceFipsClient {
    client: Option<FipsMobileClient>,
    peer_npub: String,
    next_frame_id: u64,
    assembler: FipsApplicationFrameAssembler,
}

/// Legacy Flutter DTO retained for generated-binding compatibility. Transport
/// assembly uses [`FipsApplicationFrameAssembler`] from `fips-mobile`.
#[derive(Default)]
pub struct WorkspaceFrameAssembler {
    pub frame_id: Option<u64>,
    pub last_completed_frame_id: u64,
    pub chunk_count: u16,
    pub chunks: Vec<Option<Vec<u8>>>,
}

struct RealtimeAudioPipeline {
    encoder: RealtimeAudioEncoder,
    decoder: RealtimeAudioDecoder,
    queued_audio: VecDeque<Vec<u8>>,
    queued_video: VecDeque<Vec<u8>>,
}

impl RealtimeAudioPipeline {
    fn new() -> Result<Self> {
        Ok(Self {
            encoder: RealtimeAudioEncoder::new()?,
            decoder: RealtimeAudioDecoder::new()?,
            queued_audio: VecDeque::with_capacity(8),
            queued_video: VecDeque::with_capacity(32),
        })
    }

    fn queue(&mut self, datagram: Vec<u8>) -> Result<()> {
        let queue = match datagram.first() {
            Some(&1) => &mut self.queued_audio,
            Some(&2) => &mut self.queued_video,
            Some(version) => {
                return Err(anyhow!("unsupported realtime datagram version {version}"))
            }
            None => return Err(anyhow!("empty realtime datagram")),
        };
        if queue.len() == queue.capacity() {
            queue.pop_front();
        }
        queue.push_back(datagram);
        Ok(())
    }

    fn take(&mut self, video: bool) -> Option<Vec<u8>> {
        if video {
            self.queued_video.pop_front()
        } else {
            self.queued_audio.pop_front()
        }
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

/// A profile-signed, NIP-17-deliverable relay offer. `signed_offer` must be
/// delivered privately to another client using the same profile.
#[derive(Debug, Clone)]
pub struct BridgeFipsRelayOffer {
    pub session_id: String,
    pub tunnel_npub: String,
    pub signed_offer: String,
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
    pub file_bytes: Option<Vec<u8>>,
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
    let relays = clean_endpoints(&config.relays);
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
        file_bytes: config.file_bytes,
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

/// Publish the responder advert. This completes before traversal so callers can
/// send their signaling answer only after the caller can discover this endpoint.
pub async fn fips_call_accept_start(config: BridgeFipsCallConfig) -> Result<BridgeFipsCallStatus> {
    let audio = RealtimeAudioPipeline::new()?;
    let mut session = build_fips_call_session(config)?;
    session.start_accept().await?;
    let status = fips_call_status(&session);
    *CALL_SESSION.lock().await = Some(session);
    *REALTIME_AUDIO.lock().await = Some(audio);
    Ok(status)
}

/// Wait for the caller's traversal after [`fips_call_accept_start`] has made
/// the responder advert available.
pub async fn fips_call_accept_complete() -> Result<BridgeFipsCallStatus> {
    // `accept` can wait for the full traversal timeout. Keep the global slot
    // available so hangup can cancel that wait instead of blocking on it.
    let (cancel, cancelled) = oneshot::channel();
    *CALL_ACCEPT_CANCEL.lock().await = Some(cancel);
    let session = CALL_SESSION
        .lock()
        .await
        .take()
        .ok_or_else(|| anyhow!("FIPS call acceptance is not started"));
    let mut session = match session {
        Ok(session) => session,
        Err(error) => {
            CALL_ACCEPT_CANCEL.lock().await.take();
            return Err(error);
        }
    };
    let result = tokio::select! {
        result = session.accept() => result.map_err(anyhow::Error::from),
        _ = cancelled => Err(anyhow!("FIPS call acceptance cancelled")),
    };
    let was_cancelled = CALL_ACCEPT_CANCEL.lock().await.take().is_none();
    if was_cancelled {
        let _ = session.stop().await;
        return Err(anyhow!("FIPS call acceptance cancelled"));
    }

    let status = result.map(|()| fips_call_status(&session));
    *CALL_SESSION.lock().await = Some(session);
    status
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

/// Sends one bounded UTF-8 control frame on QUIC's reliable ordered stream.
/// Call setup remains Nostr-signaled because this stream exists only after the
/// peer-to-peer session is connected.
pub async fn fips_call_send_control(frame: String) -> Result<()> {
    validate_control_frame(&frame)?;
    let mut session = CALL_SESSION.lock().await;
    let session = session
        .as_mut()
        .ok_or_else(|| anyhow!("FIPS call is not active"))?;
    session.send(frame.as_bytes()).await?;
    Ok(())
}

/// Receives one control frame from QUIC's reliable ordered stream.
pub async fn fips_call_receive_control(timeout_ms: u64) -> Result<Option<String>> {
    let mut session = CALL_SESSION.lock().await;
    let session = session
        .as_mut()
        .ok_or_else(|| anyhow!("FIPS call is not active"))?;
    match tokio::time::timeout(
        // The session mutex also protects datagram sends. Bound this receive so
        // reliable control traffic cannot interrupt realtime media for long.
        Duration::from_millis(timeout_ms.clamp(1, 50)),
        session.receive(),
    )
    .await
    {
        Ok(result) => {
            let frame = String::from_utf8(result?)?;
            validate_control_frame(&frame)?;
            Ok(Some(frame))
        }
        Err(_) => Ok(None),
    }
}

pub async fn fips_call_send_realtime_audio(packet: BridgeRealtimeAudioPacket) -> Result<()> {
    fips_call_send_datagram(RealtimeAudioPacket::from(packet).encode()?).await
}

pub async fn fips_call_receive_realtime_audio(
    timeout_ms: u64,
) -> Result<Option<BridgeRealtimeAudioPacket>> {
    fips_call_receive_media(timeout_ms, false)
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
    let Some(datagram) = fips_call_receive_media(timeout_ms, false).await? else {
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

/// Sends one already-bounded H.264 fragment from the native MediaCodec bridge.
pub async fn fips_call_send_realtime_video(fragment: Vec<u8>) -> Result<()> {
    RealtimeVideoFragment::decode(&fragment)?;
    fips_call_send_datagram(fragment).await
}

/// Returns only H.264 video fragments. Audio is queued for its decoder rather
/// than discarded, so audio and video never compete for the QUIC receiver.
pub async fn fips_call_receive_realtime_video(timeout_ms: u64) -> Result<Option<Vec<u8>>> {
    fips_call_receive_media(timeout_ms, true).await
}

async fn fips_call_receive_media(timeout_ms: u64, video: bool) -> Result<Option<Vec<u8>>> {
    if let Some(datagram) = REALTIME_AUDIO
        .lock()
        .await
        .as_mut()
        .and_then(|media| media.take(video))
    {
        return Ok(Some(datagram));
    }
    let datagram = fips_call_receive_datagram(timeout_ms).await?;
    let Some(datagram) = datagram else {
        return Ok(None);
    };
    let mut media = REALTIME_AUDIO.lock().await;
    let media = media
        .as_mut()
        .ok_or_else(|| anyhow!("FIPS realtime media is not active"))?;
    media.queue(datagram)?;
    Ok(media.take(video))
}

pub async fn fips_call_stop() -> Result<()> {
    if let Some(cancel) = CALL_ACCEPT_CANCEL.lock().await.take() {
        let _ = cancel.send(());
    }
    let session = CALL_SESSION.lock().await.take();
    if let Some(mut session) = session {
        session.stop().await?;
    }
    *REALTIME_AUDIO.lock().await = None;
    Ok(())
}

/// Connect to the worker's workspace transport and prove possession of the
/// one-time capability delivered to this authenticated Nostr member.
pub async fn fips_workspace_snapshot_connect(
    config: BridgeFipsCallConfig,
    workspace_key: String,
    peer_npub: String,
    capability: String,
) -> Result<()> {
    if capability.len() < 32 {
        return Err(anyhow!("workspace FIPS capability is invalid"));
    }
    let workspace_key = workspace_transport_key(&workspace_key)?;
    let peer_npub = PublicKey::parse(peer_npub.trim())?.to_bech32()?;
    let mut client = WorkspaceFipsClient {
        client: Some(build_workspace_fips_client(config).await?),
        peer_npub,
        // The worker retains replay state while a peer reconnects. Start each
        // client transport above earlier sessions instead of reusing frame 1.
        next_frame_id: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis()
            .try_into()
            .unwrap_or(u64::MAX - 1),
        assembler: FipsApplicationFrameAssembler::default(),
    };
    workspace_snapshot_send_frame(&mut client, capability.into_bytes()).await?;
    let replaced = WORKSPACE_SNAPSHOT_CLIENTS
        .lock()
        .await
        .insert(workspace_key, Arc::new(Mutex::new(client)));
    if let Some(replaced) = replaced {
        // A repeated offer must close its superseded node instead of retaining
        // sockets and tasks until the process exits.
        let client = replaced.lock().await.client.take();
        if let Some(client) = client {
            client.stop().await?;
        }
    }
    Ok(())
}

/// Receive one JSON workspace frame from the shared FIPS service transport.
pub async fn fips_workspace_snapshot_receive(
    workspace_key: String,
    timeout_ms: u64,
) -> Result<Option<String>> {
    let workspace_key = workspace_transport_key(&workspace_key)?;
    let transport = WORKSPACE_SNAPSHOT_CLIENTS
        .lock()
        .await
        .get_mut(&workspace_key)
        .cloned()
        .ok_or_else(|| anyhow!("FIPS workspace transport is not active"))?;
    // Do not hold the registry lock while waiting for a network packet. Each
    // workspace transport can now receive independently.
    let mut transport = transport.lock().await;
    let deadline = tokio::time::Instant::now() + Duration::from_millis(timeout_ms.clamp(1, 5_000));
    loop {
        let now = tokio::time::Instant::now();
        if now >= deadline {
            return Ok(None);
        }
        let packet = match tokio::time::timeout(
            deadline - now,
            transport
                .client
                .as_mut()
                .ok_or_else(|| anyhow!("FIPS workspace transport is stopped"))?
                .recv_service_packet(),
        )
        .await
        {
            Ok(Some(packet)) => packet,
            Ok(None) => return Err(anyhow!("FIPS workspace service transport closed")),
            Err(_) => return Ok(None),
        };
        if packet.src_port != WORKSPACE_FIPS_SERVICE_PORT
            || packet.dst_port != WORKSPACE_FIPS_SERVICE_PORT
        {
            continue;
        }
        if let Some(frame) = transport.assembler.push(&packet.payload)? {
            return String::from_utf8(frame).map(Some).map_err(Into::into);
        }
    }
}

/// Send one JSON workspace control frame over the dedicated reliable stream.
pub async fn fips_workspace_snapshot_send(workspace_key: String, frame: String) -> Result<()> {
    let workspace_key = workspace_transport_key(&workspace_key)?;
    let transport = WORKSPACE_SNAPSHOT_CLIENTS
        .lock()
        .await
        .get_mut(&workspace_key)
        .cloned()
        .ok_or_else(|| anyhow!("FIPS workspace transport is not active"))?;
    let mut transport = transport.lock().await;
    workspace_snapshot_send_frame(&mut transport, frame.into_bytes()).await
}

/// Send one application envelope on the persistent workspace FIPS service.
/// The snapshot bridge remains available for legacy hello/ping/pong traffic.
pub async fn fips_workspace_send_wire(
    workspace_key: String,
    frame: String,
    message_id: u64,
) -> Result<()> {
    let envelope = workspace_fips_app_envelope(&frame, message_id)?;
    let workspace_key = workspace_transport_key(&workspace_key)?;
    let transport = WORKSPACE_SNAPSHOT_CLIENTS
        .lock()
        .await
        .get_mut(&workspace_key)
        .cloned()
        .ok_or_else(|| anyhow!("FIPS workspace transport is not active"))?;
    let mut transport = transport.lock().await;
    workspace_snapshot_send_frame(&mut transport, envelope).await
}

fn workspace_fips_app_envelope(frame: &str, message_id: u64) -> Result<Vec<u8>> {
    if message_id == 0 {
        return Err(anyhow!("FIPS workspace app message id must be positive"));
    }
    parse_wire_message(frame)?;
    Ok(FipsApplicationEnvelope::app(message_id, frame.to_string())?.encode()?)
}

pub async fn fips_workspace_snapshot_stop(workspace_key: String) -> Result<()> {
    let workspace_key = workspace_transport_key(&workspace_key)?;
    if let Some(transport) = WORKSPACE_SNAPSHOT_CLIENTS
        .lock()
        .await
        .remove(&workspace_key)
    {
        let client = transport.lock().await.client.take();
        if let Some(client) = client {
            client.stop().await?;
        }
    }
    Ok(())
}

fn workspace_transport_key(workspace_key: &str) -> Result<String> {
    PublicKey::parse(workspace_key.trim())?
        .to_bech32()
        .map_err(Into::into)
}

async fn workspace_snapshot_send_frame(
    transport: &mut WorkspaceFipsClient,
    payload: Vec<u8>,
) -> Result<()> {
    transport.next_frame_id = transport.next_frame_id.wrapping_add(1);
    for packet in fips_application_service_frames(transport.next_frame_id, &payload)? {
        transport
            .client
            .as_mut()
            .ok_or_else(|| anyhow!("FIPS workspace transport is stopped"))?
            .send_service_frame_to_npub(
                &transport.peer_npub,
                WORKSPACE_FIPS_SERVICE_PORT,
                WORKSPACE_FIPS_SERVICE_PORT,
                packet,
                // Nostr has already provided the visible workspace snapshot.
                // Give STUN discovery enough time to establish the optional
                // direct FIPS route before declaring this bootstrap failed.
                Duration::from_secs(20),
            )
            .await?;
    }
    Ok(())
}

/// Starts one direct FIPS edge of a channel-call mesh. These keyed sessions do
/// not share the legacy direct-call slot, so direct calls retain their protocol.
pub async fn fips_group_call_connect(
    config: BridgeFipsCallConfig,
    call_id: String,
    peer_npub: String,
) -> Result<BridgeFipsCallStatus> {
    let key = group_call_key(&call_id, &peer_npub)?;
    let mut session = build_fips_call_session(config)?;
    let peer_npub = PublicKey::parse(peer_npub.trim())?.to_bech32()?;
    session.connect(&peer_npub).await?;
    let status = fips_call_status(&session);
    GROUP_CALL_SESSIONS
        .lock()
        .await
        .insert(key.clone(), session);
    GROUP_CALL_AUDIO
        .lock()
        .await
        .insert(key, RealtimeAudioPipeline::new()?);
    Ok(status)
}

pub async fn fips_group_call_accept_start(
    config: BridgeFipsCallConfig,
    call_id: String,
    peer_npub: String,
) -> Result<BridgeFipsCallStatus> {
    let key = group_call_key(&call_id, &peer_npub)?;
    let mut session = build_fips_call_session(config)?;
    session.start_accept().await?;
    let status = fips_call_status(&session);
    GROUP_CALL_SESSIONS
        .lock()
        .await
        .insert(key.clone(), session);
    GROUP_CALL_AUDIO
        .lock()
        .await
        .insert(key, RealtimeAudioPipeline::new()?);
    Ok(status)
}

pub async fn fips_group_call_accept_complete(
    call_id: String,
    peer_npub: String,
) -> Result<BridgeFipsCallStatus> {
    let key = group_call_key(&call_id, &peer_npub)?;
    let (cancel, cancelled) = oneshot::channel();
    GROUP_CALL_ACCEPT_CANCEL
        .lock()
        .await
        .insert(key.clone(), cancel);
    let mut session = GROUP_CALL_SESSIONS
        .lock()
        .await
        .remove(&key)
        .ok_or_else(|| anyhow!("FIPS group call acceptance is not started"))?;
    let result = tokio::select! {
        result = session.accept() => result.map_err(anyhow::Error::from),
        _ = cancelled => Err(anyhow!("FIPS group call acceptance cancelled")),
    };
    let was_cancelled = GROUP_CALL_ACCEPT_CANCEL.lock().await.remove(&key).is_none();
    if was_cancelled {
        let _ = session.stop().await;
        return Err(anyhow!("FIPS group call acceptance cancelled"));
    }
    let status = result.map(|()| fips_call_status(&session));
    GROUP_CALL_SESSIONS.lock().await.insert(key, session);
    status
}

pub async fn fips_group_call_send_realtime_pcm(
    call_id: String,
    peer_npub: String,
    pcm: Vec<u8>,
) -> Result<()> {
    let key = group_call_key(&call_id, &peer_npub)?;
    let datagram = GROUP_CALL_AUDIO
        .lock()
        .await
        .get_mut(&key)
        .ok_or_else(|| anyhow!("FIPS group realtime audio is not active"))?
        .encoder
        .encode_pcm(&pcm)?
        .encode()?;
    GROUP_CALL_SESSIONS
        .lock()
        .await
        .get(&key)
        .ok_or_else(|| anyhow!("FIPS group call is not active"))?
        .send_datagram(&datagram)?;
    Ok(())
}

pub async fn fips_group_call_receive_realtime_pcm(
    call_id: String,
    peer_npub: String,
    timeout_ms: u64,
) -> Result<Option<Vec<u8>>> {
    let key = group_call_key(&call_id, &peer_npub)?;
    let Some(datagram) = fips_group_call_receive_media(&key, timeout_ms, false).await? else {
        return Ok(None);
    };
    let packet = RealtimeAudioPacket::decode(&datagram)?;
    GROUP_CALL_AUDIO
        .lock()
        .await
        .get_mut(&key)
        .ok_or_else(|| anyhow!("FIPS group realtime audio is not active"))?
        .decoder
        .push(packet)
}

/// Sends one bounded UTF-8 control frame to a group-call peer over its
/// reliable QUIC stream.
pub async fn fips_group_call_send_control(
    call_id: String,
    peer_npub: String,
    frame: String,
) -> Result<()> {
    validate_control_frame(&frame)?;
    let key = group_call_key(&call_id, &peer_npub)?;
    let mut sessions = GROUP_CALL_SESSIONS.lock().await;
    let session = sessions
        .get_mut(&key)
        .ok_or_else(|| anyhow!("FIPS group call is not active"))?;
    session.send(frame.as_bytes()).await?;
    Ok(())
}

/// Receives one control frame from a group-call peer's reliable QUIC stream.
pub async fn fips_group_call_receive_control(
    call_id: String,
    peer_npub: String,
    timeout_ms: u64,
) -> Result<Option<String>> {
    let key = group_call_key(&call_id, &peer_npub)?;
    let mut sessions = GROUP_CALL_SESSIONS.lock().await;
    let session = sessions
        .get_mut(&key)
        .ok_or_else(|| anyhow!("FIPS group call is not active"))?;
    match tokio::time::timeout(
        Duration::from_millis(timeout_ms.clamp(1, 5_000)),
        session.receive(),
    )
    .await
    {
        Ok(result) => {
            let frame = String::from_utf8(result?)?;
            validate_control_frame(&frame)?;
            Ok(Some(frame))
        }
        Err(_) => Ok(None),
    }
}

/// Creates a private, profile-signed offer for a newly generated ephemeral
/// tunnel identity. Deliver `signed_offer` only through an authenticated Nostr
/// DM to another client that has the same profile secret.
pub async fn fips_relay_request_offer(
    config: BridgeFipsCallConfig,
    device_name: String,
    lan_endpoints: Vec<String>,
) -> Result<BridgeFipsRelayOffer> {
    prune_expired_relay_state().await;
    let session_id = new_session_id();
    let session = build_ephemeral_fips_session(&config)?;
    let tunnel_npub = session.npub();
    let offer = create_offer(
        &config.secret_key,
        &session_id,
        "requester",
        &tunnel_npub,
        None,
        None,
        &device_name,
        &lan_endpoints,
    )?;
    let mut pending = RELAY_PENDING.lock().await;
    if pending.len() >= MAX_RELAY_SESSIONS {
        bail!("too many pending FIPS relay sessions");
    }
    pending.insert(
        session_id.clone(),
        PendingRelaySession {
            session,
            expires_at: offer.expires_at,
        },
    );
    Ok(BridgeFipsRelayOffer {
        session_id,
        tunnel_npub,
        signed_offer: offer.signed_offer,
    })
}

/// Verifies a same-profile requester offer, creates a distinct ephemeral relay
/// identity, and starts its short-lived FIPS acceptor.
pub async fn fips_relay_accept_start(
    config: BridgeFipsCallConfig,
    requester_offer: String,
    device_name: String,
    lan_endpoints: Vec<String>,
) -> Result<BridgeFipsRelayOffer> {
    prune_expired_relay_state().await;
    let requester = verify_offer(&requester_offer, &config.secret_key, "requester")?;
    consume_relay_offer(&requester_offer, requester.expires_at).await?;
    let mut session = build_ephemeral_fips_session(&config)?;
    let tunnel_npub = session.npub();
    let offer = create_offer(
        &config.secret_key,
        &requester.session_id,
        "relay",
        &tunnel_npub,
        Some(&requester.tunnel_npub),
        Some(requester.expires_at),
        &device_name,
        &lan_endpoints,
    )?;
    session.start_accept().await?;
    let key = group_call_key(&requester.session_id, &requester.tunnel_npub)?;
    let mut tunnels = RELAY_TUNNELS.lock().await;
    if tunnels.len() >= MAX_RELAY_SESSIONS {
        let _ = session.stop().await;
        bail!("too many active FIPS relay sessions");
    }
    tunnels.insert(
        key,
        RelayTunnel {
            session,
            peer_npub: requester.tunnel_npub,
            expires_at: requester.expires_at,
        },
    );
    Ok(BridgeFipsRelayOffer {
        session_id: requester.session_id,
        tunnel_npub,
        signed_offer: offer.signed_offer,
    })
}

/// Connects the requester's generated ephemeral key to the authenticated relay
/// offer. Both offers must be signed by the same profile and share one session.
pub async fn fips_relay_connect(
    config: BridgeFipsCallConfig,
    requester_offer: String,
    relay_offer: String,
) -> Result<BridgeFipsCallStatus> {
    prune_expired_relay_state().await;
    let requester = verify_offer(&requester_offer, &config.secret_key, "requester")?;
    let relay = verify_offer(&relay_offer, &config.secret_key, "relay")?;
    if requester.session_id != relay.session_id {
        bail!("relay offers do not bind the same session");
    }
    if relay.peer_tunnel_npub.as_deref() != Some(requester.tunnel_npub.as_str()) {
        bail!("relay offer does not bind the requester ephemeral identity");
    }
    if relay.expires_at != requester.expires_at {
        bail!("relay offers do not have the same expiration");
    }
    consume_relay_offer(&relay_offer, relay.expires_at).await?;
    let pending = RELAY_PENDING
        .lock()
        .await
        .remove(&requester.session_id)
        .ok_or_else(|| anyhow!("relay requester offer is unknown or already used"))?;
    let mut session = pending.session;
    if session.npub() != requester.tunnel_npub {
        let _ = session.stop().await;
        bail!("relay requester offer does not match its ephemeral identity");
    }
    if pending.expires_at != requester.expires_at || now_secs() >= requester.expires_at {
        let _ = session.stop().await;
        bail!("relay offer is expired");
    }
    if let Err(error) = session.connect(&relay.tunnel_npub).await {
        let _ = session.stop().await;
        return Err(error.into());
    }
    let status = fips_call_status(&session);
    let key = group_call_key(&requester.session_id, &relay.tunnel_npub)?;
    let mut tunnels = RELAY_TUNNELS.lock().await;
    if tunnels.len() >= MAX_RELAY_SESSIONS {
        let _ = session.stop().await;
        bail!("too many active FIPS relay sessions");
    }
    tunnels.insert(
        key,
        RelayTunnel {
            session,
            peer_npub: relay.tunnel_npub,
            expires_at: requester.expires_at,
        },
    );
    Ok(status)
}

/// Waits for the requesting device to complete the relay tunnel traversal.
pub async fn fips_relay_accept_complete(
    tunnel_id: String,
    requester_npub: String,
) -> Result<BridgeFipsCallStatus> {
    prune_expired_relay_state().await;
    let key = group_call_key(&tunnel_id, &requester_npub)?;
    let (cancel, cancelled) = oneshot::channel();
    RELAY_ACCEPT_CANCEL.lock().await.insert(key.clone(), cancel);
    let mut tunnel = RELAY_TUNNELS
        .lock()
        .await
        .remove(&key)
        .ok_or_else(|| anyhow!("FIPS relay acceptance is not started"))?;
    validate_relay_tunnel(&tunnel, &requester_npub)?;
    let result = tokio::select! {
        result = tunnel.session.accept() => result.map_err(anyhow::Error::from),
        _ = cancelled => Err(anyhow!("FIPS relay acceptance cancelled")),
    };
    RELAY_ACCEPT_CANCEL.lock().await.remove(&key);
    match result {
        Ok(()) => {
            let status = fips_call_status(&tunnel.session);
            RELAY_TUNNELS.lock().await.insert(key, tunnel);
            Ok(status)
        }
        Err(error) => {
            let _ = tunnel.session.stop().await;
            Err(error)
        }
    }
}

/// Sends one bounded opaque relay frame. Relay payloads are deliberately not
/// parsed here: authorization and session binding happen in the signed offer.
pub async fn fips_relay_send(tunnel_id: String, peer_npub: String, frame: String) -> Result<()> {
    prune_expired_relay_state().await;
    validate_control_frame(&frame)?;
    let key = group_call_key(&tunnel_id, &peer_npub)?;
    let mut tunnels = RELAY_TUNNELS.lock().await;
    let tunnel = tunnels
        .get_mut(&key)
        .ok_or_else(|| anyhow!("FIPS relay tunnel is not active"))?;
    validate_relay_tunnel(tunnel, &peer_npub)?;
    tunnel.session.send(frame.as_bytes()).await?;
    Ok(())
}

/// Receives one opaque relay frame from a peer device.
pub async fn fips_relay_receive(
    tunnel_id: String,
    peer_npub: String,
    timeout_ms: u64,
) -> Result<Option<String>> {
    prune_expired_relay_state().await;
    let key = group_call_key(&tunnel_id, &peer_npub)?;
    let mut tunnels = RELAY_TUNNELS.lock().await;
    let tunnel = tunnels
        .get_mut(&key)
        .ok_or_else(|| anyhow!("FIPS relay tunnel is not active"))?;
    validate_relay_tunnel(tunnel, &peer_npub)?;
    let frame = tokio::time::timeout(
        Duration::from_millis(timeout_ms.clamp(1, 5_000)),
        tunnel.session.receive(),
    )
    .await;
    match frame {
        Ok(frame) => String::from_utf8(frame?).map(Some).map_err(Into::into),
        Err(_) => Ok(None),
    }
}

/// Closes a relay tunnel and any pending accept operation.
pub async fn fips_relay_stop(tunnel_id: String, peer_npub: String) -> Result<()> {
    let key = group_call_key(&tunnel_id, &peer_npub)?;
    if let Some(cancel) = RELAY_ACCEPT_CANCEL.lock().await.remove(&key) {
        let _ = cancel.send(());
    }
    if let Some(mut tunnel) = RELAY_TUNNELS.lock().await.remove(&key) {
        tunnel.session.stop().await?;
    }
    Ok(())
}

pub async fn fips_group_call_send_realtime_video(
    call_id: String,
    peer_npub: String,
    fragment: Vec<u8>,
) -> Result<()> {
    RealtimeVideoFragment::decode(&fragment)?;
    let key = group_call_key(&call_id, &peer_npub)?;
    GROUP_CALL_SESSIONS
        .lock()
        .await
        .get(&key)
        .ok_or_else(|| anyhow!("FIPS group call is not active"))?
        .send_datagram(&fragment)?;
    Ok(())
}

pub async fn fips_group_call_receive_realtime_video(
    call_id: String,
    peer_npub: String,
    timeout_ms: u64,
) -> Result<Option<Vec<u8>>> {
    let key = group_call_key(&call_id, &peer_npub)?;
    fips_group_call_receive_media(&key, timeout_ms, true).await
}

async fn fips_group_call_receive_media(
    key: &str,
    timeout_ms: u64,
    video: bool,
) -> Result<Option<Vec<u8>>> {
    if let Some(datagram) = GROUP_CALL_AUDIO
        .lock()
        .await
        .get_mut(key)
        .and_then(|media| media.take(video))
    {
        return Ok(Some(datagram));
    }
    let datagram = {
        let sessions = GROUP_CALL_SESSIONS.lock().await;
        let session = sessions
            .get(key)
            .ok_or_else(|| anyhow!("FIPS group call is not active"))?;
        match tokio::time::timeout(
            Duration::from_millis(timeout_ms.clamp(1, 50)),
            session.receive_datagram(),
        )
        .await
        {
            Ok(result) => result.map_err(anyhow::Error::from)?,
            Err(_) => return Ok(None),
        }
    };
    let mut media = GROUP_CALL_AUDIO.lock().await;
    let media = media
        .get_mut(key)
        .ok_or_else(|| anyhow!("FIPS group realtime media is not active"))?;
    media.queue(datagram)?;
    Ok(media.take(video))
}

pub async fn fips_group_call_stop(call_id: String) -> Result<()> {
    let prefix = format!("{call_id}\u{1f}");
    let keys = GROUP_CALL_SESSIONS
        .lock()
        .await
        .keys()
        .filter(|key| key.starts_with(&prefix))
        .cloned()
        .collect::<Vec<_>>();
    for key in &keys {
        if let Some(cancel) = GROUP_CALL_ACCEPT_CANCEL.lock().await.remove(key) {
            let _ = cancel.send(());
        }
        if let Some(mut session) = GROUP_CALL_SESSIONS.lock().await.remove(key) {
            session.stop().await?;
        }
        GROUP_CALL_AUDIO.lock().await.remove(key);
    }
    Ok(())
}

fn group_call_key(call_id: &str, peer_npub: &str) -> Result<String> {
    if call_id.trim().is_empty() {
        return Err(anyhow!("group call id is required"));
    }
    Ok(format!(
        "{}\u{1f}{}",
        call_id.trim(),
        PublicKey::parse(peer_npub.trim())?.to_bech32()?
    ))
}

fn validate_control_frame(frame: &str) -> Result<()> {
    if frame.is_empty() || frame.len() > 16 * 1024 {
        return Err(anyhow!("control frame must contain 1 to 16384 bytes"));
    }
    Ok(())
}

fn build_fips_call_session(config: BridgeFipsCallConfig) -> Result<FipsMobileQuicSession> {
    FipsClientConfig::from(config).quic_session()
}

fn build_ephemeral_fips_session(config: &BridgeFipsCallConfig) -> Result<FipsMobileQuicSession> {
    // The profile key signs authorization offers only. A tunnel always uses a
    // new identity so it cannot replace or collide with the profile's FIPS node.
    let identity = fips_mobile::Identity::generate();
    let mut session_config = FipsMobileQuicSessionConfig::default();
    let relays = clean_endpoints(&config.relays);
    if !relays.is_empty() {
        session_config.discovery.advert_relays = relays.clone();
        session_config.discovery.dm_relays = relays;
    }
    let stun_servers = clean_endpoints(&config.stun_servers);
    if !stun_servers.is_empty() {
        session_config.discovery.stun_servers = stun_servers;
    }
    Ok(FipsMobileQuicSession::new(identity, session_config))
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn validate_relay_tunnel(tunnel: &RelayTunnel, peer_npub: &str) -> Result<()> {
    if now_secs() >= tunnel.expires_at {
        bail!("relay tunnel has expired");
    }
    if PublicKey::parse(peer_npub.trim())?.to_bech32()? != tunnel.peer_npub {
        bail!("relay peer does not match the authorized ephemeral identity");
    }
    Ok(())
}

async fn consume_relay_offer(signed_offer: &str, expires_at: u64) -> Result<()> {
    use sha2::{Digest, Sha256};

    let fingerprint = format!("{:x}", Sha256::digest(signed_offer.as_bytes()));
    let now = now_secs();
    let mut used = RELAY_USED_OFFERS.lock().await;
    used.retain(|_, expiry| *expiry > now);
    if used.len() >= 128 {
        bail!("relay offer replay registry is full");
    }
    if used.insert(fingerprint, expires_at).is_some() {
        bail!("relay offer was already used");
    }
    Ok(())
}

async fn prune_expired_relay_state() {
    let now = now_secs();
    let expired_pending = {
        let mut pending = RELAY_PENDING.lock().await;
        let keys = pending
            .iter()
            .filter_map(|(key, pending)| (pending.expires_at <= now).then_some(key.clone()))
            .collect::<Vec<_>>();
        keys.into_iter()
            .filter_map(|key| pending.remove(&key))
            .collect::<Vec<_>>()
    };
    for mut pending in expired_pending {
        let _ = pending.session.stop().await;
    }
    let expired = {
        let mut tunnels = RELAY_TUNNELS.lock().await;
        let keys = tunnels
            .iter()
            .filter_map(|(key, tunnel)| (tunnel.expires_at <= now).then_some(key.clone()))
            .collect::<Vec<_>>();
        keys.into_iter()
            .filter_map(|key| tunnels.remove(&key))
            .collect::<Vec<_>>()
    };
    for mut tunnel in expired {
        let _ = tunnel.session.stop().await;
    }
}

async fn build_workspace_fips_client(config: BridgeFipsCallConfig) -> Result<FipsMobileClient> {
    FipsClientConfig::from(config)
        .application_client(WORKSPACE_FIPS_SERVICE_PORT, 128)
        .await
}

fn fips_call_status(session: &FipsMobileQuicSession) -> BridgeFipsCallStatus {
    let status = call_status(session);
    BridgeFipsCallStatus {
        state: status.state,
        max_datagram_bytes: status.max_datagram_bytes,
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

impl From<BridgeFipsCallConfig> for FipsClientConfig {
    fn from(value: BridgeFipsCallConfig) -> Self {
        Self {
            secret_key: value.secret_key,
            relays: value.relays,
            stun_servers: value.stun_servers,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fips_mobile::{FipsMobileQuicSessionConfig, Identity};

    static CALL_SLOT_TEST_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));
    static RELAY_STATE_TEST_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

    #[tokio::test]
    async fn stopping_a_call_cancels_pending_acceptance() {
        let _guard = CALL_SLOT_TEST_LOCK.lock().await;
        *CALL_SESSION.lock().await = Some(FipsMobileQuicSession::new(
            Identity::generate(),
            FipsMobileQuicSessionConfig::default(),
        ));
        let (cancel, cancelled) = oneshot::channel();
        *CALL_ACCEPT_CANCEL.lock().await = Some(cancel);

        fips_call_stop().await.unwrap();

        assert!(cancelled.await.is_ok());
        assert!(CALL_SESSION.lock().await.is_none());
    }

    #[tokio::test]
    async fn completing_acceptance_requires_a_published_advert() {
        let _guard = CALL_SLOT_TEST_LOCK.lock().await;
        let error = fips_call_accept_complete().await.unwrap_err();

        assert!(error.to_string().contains("acceptance is not started"));
    }

    #[tokio::test]
    async fn stopping_workspace_transport_does_not_use_the_call_slot() {
        let _guard = CALL_SLOT_TEST_LOCK.lock().await;
        *CALL_SESSION.lock().await = Some(FipsMobileQuicSession::new(
            Identity::generate(),
            FipsMobileQuicSessionConfig::default(),
        ));
        assert!(CALL_SESSION.lock().await.is_some());
        fips_call_stop().await.unwrap();
    }

    #[test]
    fn workspace_app_envelope_requires_a_valid_wire_message_and_positive_id() {
        let envelope = workspace_fips_app_envelope(r#"{"query":"hello"}"#, 7).unwrap();
        assert_eq!(
            serde_json::from_slice::<serde_json::Value>(&envelope).unwrap()["message_id"],
            7
        );
        assert!(workspace_fips_app_envelope("not a wire message", 7).is_err());
        assert!(workspace_fips_app_envelope(r#"{"query":"hello"}"#, 0).is_err());
    }

    #[test]
    fn workspace_transport_key_is_a_canonical_npub() {
        let public_key = Keys::generate().public_key();

        assert_eq!(
            workspace_transport_key(&format!("  {}  ", public_key.to_hex())).unwrap(),
            public_key.to_bech32().unwrap()
        );
        assert!(workspace_transport_key("not-a-public-key").is_err());
    }

    #[test]
    fn control_frames_are_bounded() {
        assert!(validate_control_frame("{\"type\":\"hangup\"}").is_ok());
        assert!(validate_control_frame("").is_err());
        assert!(validate_control_frame(&"x".repeat(16 * 1024 + 1)).is_err());
    }

    #[tokio::test]
    async fn relay_offers_are_single_use() {
        let _guard = RELAY_STATE_TEST_LOCK.lock().await;
        let offer = "signed-offer";
        let expiry = now_secs() + 60;
        consume_relay_offer(offer, expiry).await.unwrap();
        assert!(consume_relay_offer(offer, expiry).await.is_err());
        RELAY_USED_OFFERS.lock().await.clear();
    }

    #[tokio::test]
    async fn expired_relay_sessions_are_stopped_and_removed() {
        let _guard = RELAY_STATE_TEST_LOCK.lock().await;
        let expired_at = now_secs().saturating_sub(1);
        let pending_id = new_session_id();
        let peer = Identity::generate();
        let peer_npub = peer.npub();
        let tunnel_key = group_call_key(&new_session_id(), &peer_npub).unwrap();

        RELAY_PENDING.lock().await.insert(
            pending_id.clone(),
            PendingRelaySession {
                session: FipsMobileQuicSession::new(
                    Identity::generate(),
                    FipsMobileQuicSessionConfig::default(),
                ),
                expires_at: expired_at,
            },
        );
        RELAY_TUNNELS.lock().await.insert(
            tunnel_key.clone(),
            RelayTunnel {
                session: FipsMobileQuicSession::new(
                    Identity::generate(),
                    FipsMobileQuicSessionConfig::default(),
                ),
                peer_npub,
                expires_at: expired_at,
            },
        );

        prune_expired_relay_state().await;

        assert!(!RELAY_PENDING.lock().await.contains_key(&pending_id));
        assert!(!RELAY_TUNNELS.lock().await.contains_key(&tunnel_key));
    }

    #[tokio::test]
    async fn relay_request_refuses_a_full_pending_registry() {
        let _guard = RELAY_STATE_TEST_LOCK.lock().await;
        let expires_at = now_secs() + 60;
        let mut pending = RELAY_PENDING.lock().await;
        pending.clear();
        for _ in 0..MAX_RELAY_SESSIONS {
            pending.insert(
                new_session_id(),
                PendingRelaySession {
                    session: FipsMobileQuicSession::new(
                        Identity::generate(),
                        FipsMobileQuicSessionConfig::default(),
                    ),
                    expires_at,
                },
            );
        }
        drop(pending);

        let result = fips_relay_request_offer(
            BridgeFipsCallConfig {
                secret_key: Keys::generate().secret_key().to_bech32().unwrap(),
                relays: vec![],
                stun_servers: vec![],
            },
            "Phone".to_string(),
            vec![],
        )
        .await;

        assert!(result.unwrap_err().to_string().contains("too many pending"));
        RELAY_PENDING.lock().await.clear();
    }
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
