use std::collections::BTreeMap;
use std::env;
use std::process::ExitCode;
use std::time::{Duration, Instant};

use anyhow::{anyhow, Context, Result};
use fips_mobile::{
    FipsMobileQuicSession, FipsMobileQuicSessionConfig, FipsMobileQuicSessionStatus, Identity,
};
use nostr_sdk::prelude::{PublicKey, ToBech32};
use rust_lib_nostr_codex_phone::fips_harness::{
    checked_report, encode_test_frames, take_echoed_frame, validate_frame_count, FipsHarnessReport,
    ReceivedAudio, HARNESS_FRAME_INTERVAL,
};
use rust_lib_nostr_codex_phone::nostr_client::{NostrConfig, NostrMessenger};
use rust_lib_nostr_codex_phone::protocol::WireMessage;
use rust_lib_nostr_codex_phone::realtime_audio::RealtimeAudioPacket;

struct Args {
    role: String,
    secret: String,
    peer: Option<String>,
    relays: Vec<String>,
    stun: Vec<String>,
    frames: u32,
    timeout: Duration,
    max_loss_percent: f64,
    max_jitter_ms: f64,
    nostr_control: bool,
    call_id: String,
}

#[tokio::main]
async fn main() -> ExitCode {
    let args = match Args::parse() {
        Ok(args) => args,
        Err(error) => {
            eprintln!("{error}\n\n{}", Args::usage());
            return ExitCode::from(2);
        }
    };
    let role = args.role.clone();
    match run(args).await {
        Ok(report) => {
            println!(
                "{}",
                serde_json::to_string(&report).expect("serializable report")
            );
            if report.pass {
                ExitCode::SUCCESS
            } else {
                ExitCode::from(1)
            }
        }
        Err(error) => {
            let report = FipsHarnessReport::failed(role, format!("{error:#}"));
            println!(
                "{}",
                serde_json::to_string(&report).expect("serializable error report")
            );
            ExitCode::from(1)
        }
    }
}

async fn run(args: Args) -> Result<FipsHarnessReport> {
    let identity = Identity::from_secret_str(&args.secret).context("invalid --secret nsec")?;
    let mut config = FipsMobileQuicSessionConfig::default();
    config.discovery.advert_relays = args.relays.clone();
    config.discovery.dm_relays = args.relays.clone();
    config.discovery.stun_servers = args.stun;
    config.quic.timeout = args.timeout;
    let mut session = FipsMobileQuicSession::new(identity, config);

    let control = if args.nostr_control {
        let peer = args
            .peer
            .as_deref()
            .ok_or_else(|| anyhow!("--nostr-control requires --peer"))?;
        Some(
            NostrMessenger::connect(NostrConfig {
                secret_key: args.secret.clone(),
                peer_pubkey: Some(peer.to_string()),
                receive_pubkeys: vec![],
                relays: args.relays.clone(),
            })
            .await?,
        )
    } else {
        None
    };

    if args.role == "connect" {
        let peer = PublicKey::parse(
            args.peer
                .as_deref()
                .ok_or_else(|| anyhow!("--peer is required for connect"))?,
        )?
        .to_bech32()?;
        if let Some(control) = &control {
            control
                .send_wire(WireMessage::call_invite(&args.call_id))
                .await?;
        }
        session.connect(peer).await?;
    } else {
        session.start_accept().await?;
        session.accept().await?;
    }

    let traversal = session.status() == FipsMobileQuicSessionStatus::Connected;
    let identity = traversal; // FIPS only exposes Connected after its certificate-bound peer authentication.
    let datagram = session.max_datagram_size().is_ok();
    if !datagram {
        return Err(anyhow!(
            "connected FIPS peer did not negotiate QUIC datagrams"
        ));
    }

    let sent = args.frames;
    let mut received = ReceivedAudio::new()?;
    if args.role == "connect" {
        let frames = encode_test_frames(sent)?;
        let mut expected_echoes = expected_echoes(&frames)?;
        for frame in &frames {
            session.send_datagram(&frame)?;
            tokio::time::sleep(HARNESS_FRAME_INTERVAL).await;
        }
        receive_frames(
            &session,
            &mut received,
            &mut expected_echoes,
            sent,
            args.timeout,
        )
        .await?;
        if !expected_echoes.is_empty() {
            return Err(anyhow!(
                "did not receive {} deterministic packet echoes",
                expected_echoes.len()
            ));
        }
    } else {
        // Accept mode is the real second peer: it returns each received Opus datagram unchanged.
        // It never simulates a Pixel or manufactures received audio.
        for _ in 0..sent {
            let datagram = tokio::time::timeout(args.timeout, session.receive_datagram()).await??;
            received.push(&datagram, Instant::now())?;
            session.send_datagram(&datagram)?;
        }
    }
    let (frame, loss, jitter) = received.finish(sent, args.max_loss_percent, args.max_jitter_ms)?;
    let hangup = if let Some(control) = &control {
        control
            .send_wire(WireMessage::call_hangup(&args.call_id))
            .await
            .is_ok()
    } else {
        true
    };
    session.stop().await?;
    if let Some(control) = control {
        control.shutdown().await;
    }
    Ok(checked_report(
        args.role, traversal, identity, datagram, frame, loss, jitter, hangup,
    ))
}

async fn receive_frames(
    session: &FipsMobileQuicSession,
    received: &mut ReceivedAudio,
    expected_echoes: &mut BTreeMap<u16, Vec<u8>>,
    expected: u32,
    timeout: Duration,
) -> Result<()> {
    let deadline = Instant::now() + timeout;
    while received_count(received) < expected && Instant::now() < deadline {
        let remaining = deadline.saturating_duration_since(Instant::now());
        match tokio::time::timeout(remaining, session.receive_datagram()).await {
            Ok(Ok(datagram)) => {
                take_echoed_frame(&datagram, expected_echoes)?;
                received.push(&datagram, Instant::now())?;
            }
            Ok(Err(error)) => return Err(error.into()),
            Err(_) => break,
        }
    }
    Ok(())
}

fn expected_echoes(frames: &[Vec<u8>]) -> Result<BTreeMap<u16, Vec<u8>>> {
    frames
        .iter()
        .map(|frame| Ok((RealtimeAudioPacket::decode(frame)?.sequence, frame.clone())))
        .collect()
}

fn received_count(received: &ReceivedAudio) -> u32 {
    received.received_count()
}

impl Args {
    fn parse() -> Result<Self> {
        let mut values = env::args().skip(1);
        let role = values
            .next()
            .ok_or_else(|| anyhow!("missing role: connect or accept"))?;
        if !matches!(role.as_str(), "connect" | "accept") {
            return Err(anyhow!("role must be connect or accept"));
        }
        let mut args = Self {
            role,
            secret: String::new(),
            peer: None,
            relays: vec![],
            stun: vec![],
            frames: 50,
            timeout: Duration::from_secs(30),
            max_loss_percent: 5.0,
            max_jitter_ms: 40.0,
            nostr_control: false,
            call_id: format!("fips-harness-{}", std::process::id()),
        };
        while let Some(flag) = values.next() {
            match flag.as_str() {
                "--secret" => args.secret = required_value(&mut values, &flag)?,
                "--peer" => args.peer = Some(required_value(&mut values, &flag)?),
                "--relay" => args.relays.push(required_value(&mut values, &flag)?),
                "--stun" => args.stun.push(required_value(&mut values, &flag)?),
                "--frames" => args.frames = required_value(&mut values, &flag)?.parse()?,
                "--timeout-seconds" => {
                    args.timeout = Duration::from_secs(required_value(&mut values, &flag)?.parse()?)
                }
                "--max-loss-percent" => {
                    args.max_loss_percent = required_value(&mut values, &flag)?.parse()?
                }
                "--max-jitter-ms" => {
                    args.max_jitter_ms = required_value(&mut values, &flag)?.parse()?
                }
                "--call-id" => args.call_id = required_value(&mut values, &flag)?,
                "--nostr-control" => args.nostr_control = true,
                _ => return Err(anyhow!("unknown argument `{flag}`")),
            }
        }
        if args.secret.is_empty() {
            return Err(anyhow!("--secret is required"));
        }
        if args.relays.is_empty() {
            return Err(anyhow!("at least one --relay is required"));
        }
        if args.role == "connect" && args.peer.is_none() {
            return Err(anyhow!("connect requires --peer"));
        }
        validate_frame_count(args.frames)?;
        Ok(args)
    }

    fn usage() -> &'static str {
        "Usage: fips-call-harness <connect|accept> --secret nsec... --relay wss://... [--peer npub...] [--stun stun:host:port] [--frames 50] [--nostr-control]"
    }
}

fn required_value(values: &mut impl Iterator<Item = String>, flag: &str) -> Result<String> {
    values
        .next()
        .ok_or_else(|| anyhow!("{flag} requires a value"))
}
