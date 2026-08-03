use std::collections::BTreeMap;
use std::time::{Duration, Instant};

use anyhow::{anyhow, Result};
use serde::Serialize;

use crate::realtime_audio::{
    RealtimeAudioDecoder, RealtimeAudioEncoder, RealtimeAudioPacket, FRAME_SAMPLES,
    REALTIME_AUDIO_HARNESS_ECHO_FLAG,
};

pub const HARNESS_FRAME_INTERVAL: Duration = Duration::from_millis(20);

/// JSON result contract shared by the desktop harness runs.
#[derive(Debug, Serialize)]
pub struct FipsHarnessReport {
    pub pass: bool,
    pub role: String,
    pub traversal: Check,
    pub identity: Check,
    pub datagram: Check,
    pub frame: FrameMetrics,
    pub loss: LossMetrics,
    pub jitter: JitterMetrics,
    pub hangup: Check,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct Check {
    pub pass: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct FrameMetrics {
    pub sent: u32,
    pub received: u32,
    pub decoded: u32,
    pub pass: bool,
}

#[derive(Debug, Serialize)]
pub struct LossMetrics {
    pub lost: u32,
    pub percent: f64,
    pub pass: bool,
}

#[derive(Debug, Serialize)]
pub struct JitterMetrics {
    pub max_ms: f64,
    pub pass: bool,
}

impl FipsHarnessReport {
    pub fn failed(role: impl Into<String>, error: impl ToString) -> Self {
        Self {
            pass: false,
            role: role.into(),
            traversal: failed_check("not established"),
            identity: failed_check("not verified"),
            datagram: failed_check("not negotiated"),
            frame: FrameMetrics {
                sent: 0,
                received: 0,
                decoded: 0,
                pass: false,
            },
            loss: LossMetrics {
                lost: 0,
                percent: 100.0,
                pass: false,
            },
            jitter: JitterMetrics {
                max_ms: 0.0,
                pass: false,
            },
            hangup: failed_check("not sent"),
            error: Some(error.to_string()),
        }
    }
}

pub fn deterministic_pcm(frame: u32) -> Vec<u8> {
    // A fixed non-silent waveform makes codec regressions observable and repeatable.
    (0..FRAME_SAMPLES)
        .flat_map(|sample| {
            let value = (((frame as usize * 97 + sample * 31) % 32_768) as i16).to_le_bytes();
            value.into_iter()
        })
        .collect()
}

pub fn encode_test_frames(frame_count: u32) -> Result<Vec<Vec<u8>>> {
    let mut encoder = RealtimeAudioEncoder::new()?;
    (0..frame_count)
        .map(|frame| {
            let mut packet = encoder.encode_pcm(&deterministic_pcm(frame))?;
            packet.flags = REALTIME_AUDIO_HARNESS_ECHO_FLAG;
            packet.encode()
        })
        .collect()
}

/// Reject anything other than one of the byte-identical packets sent by the
/// harness. QUIC datagrams may be reordered, so sequence numbers identify the
/// outstanding deterministic packets.
pub fn take_echoed_frame(datagram: &[u8], expected: &mut BTreeMap<u16, Vec<u8>>) -> Result<()> {
    let packet = RealtimeAudioPacket::decode(datagram)?;
    if packet.flags & REALTIME_AUDIO_HARNESS_ECHO_FLAG == 0 {
        return Err(anyhow!(
            "received a realtime packet without the harness echo flag"
        ));
    }
    let expected_datagram = expected.remove(&packet.sequence).ok_or_else(|| {
        anyhow!(
            "received duplicate or unexpected echoed sequence {}",
            packet.sequence
        )
    })?;
    if datagram != expected_datagram {
        return Err(anyhow!(
            "echoed packet {} differs from the deterministic packet sent",
            packet.sequence
        ));
    }
    Ok(())
}

pub struct ReceivedAudio {
    decoder: RealtimeAudioDecoder,
    received: u32,
    decoded: u32,
    last_arrival: Option<Instant>,
    max_jitter: Duration,
}

impl ReceivedAudio {
    pub fn new() -> Result<Self> {
        Ok(Self {
            decoder: RealtimeAudioDecoder::new()?,
            received: 0,
            decoded: 0,
            last_arrival: None,
            max_jitter: Duration::ZERO,
        })
    }

    pub fn push(&mut self, datagram: &[u8], now: Instant) -> Result<()> {
        let packet = RealtimeAudioPacket::decode(datagram)?;
        if let Some(last) = self.last_arrival {
            self.max_jitter = self.max_jitter.max(
                now.saturating_duration_since(last)
                    .abs_diff(HARNESS_FRAME_INTERVAL),
            );
        }
        self.last_arrival = Some(now);
        self.received += 1;
        if self.decoder.push(packet)?.is_some() {
            self.decoded += 1;
        }
        Ok(())
    }

    pub fn received_count(&self) -> u32 {
        self.received
    }

    pub fn finish(
        mut self,
        sent: u32,
        max_loss_percent: f64,
        max_jitter_ms: f64,
    ) -> Result<(FrameMetrics, LossMetrics, JitterMetrics)> {
        while self.decoder.decode_ready()?.is_some() {
            self.decoded += 1;
        }
        let lost = sent.saturating_sub(self.received);
        let percent = if sent == 0 {
            100.0
        } else {
            lost as f64 * 100.0 / sent as f64
        };
        let jitter_ms = self.max_jitter.as_secs_f64() * 1000.0;
        Ok((
            FrameMetrics {
                sent,
                received: self.received,
                decoded: self.decoded,
                pass: self.received == sent && self.decoded >= sent.saturating_sub(2),
            },
            LossMetrics {
                lost,
                percent,
                pass: percent <= max_loss_percent,
            },
            JitterMetrics {
                max_ms: jitter_ms,
                pass: jitter_ms <= max_jitter_ms,
            },
        ))
    }
}

pub fn checked_report(
    role: impl Into<String>,
    traversal: bool,
    identity: bool,
    datagram: bool,
    frame: FrameMetrics,
    loss: LossMetrics,
    jitter: JitterMetrics,
    hangup: bool,
) -> FipsHarnessReport {
    let pass =
        traversal && identity && datagram && frame.pass && loss.pass && jitter.pass && hangup;
    FipsHarnessReport {
        pass,
        role: role.into(),
        traversal: Check {
            pass: traversal,
            detail: None,
        },
        identity: Check {
            pass: identity,
            detail: None,
        },
        datagram: Check {
            pass: datagram,
            detail: None,
        },
        frame,
        loss,
        jitter,
        hangup: Check {
            pass: hangup,
            detail: None,
        },
        error: None,
    }
}

fn failed_check(detail: impl Into<String>) -> Check {
    Check {
        pass: false,
        detail: Some(detail.into()),
    }
}

pub fn validate_frame_count(frame_count: u32) -> Result<()> {
    if !(3..=10_000).contains(&frame_count) {
        return Err(anyhow!("--frames must be between 3 and 10000"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::realtime_audio::FRAME_BYTES;

    #[test]
    fn deterministic_frames_are_valid_opus_datagrams() {
        let frames = encode_test_frames(3).unwrap();
        assert_eq!(frames.len(), 3);
        assert_eq!(RealtimeAudioPacket::decode(&frames[0]).unwrap().sequence, 0);
        assert_ne!(deterministic_pcm(0), vec![0; FRAME_BYTES]);
    }

    #[test]
    fn metrics_pass_for_a_paced_complete_exchange() {
        let frames = encode_test_frames(4).unwrap();
        let start = Instant::now();
        let mut received = ReceivedAudio::new().unwrap();
        for (index, frame) in frames.iter().enumerate() {
            received
                .push(frame, start + HARNESS_FRAME_INTERVAL * index as u32)
                .unwrap();
        }
        let (frame, loss, jitter) = received.finish(4, 0.0, 1.0).unwrap();
        assert!(frame.pass);
        assert!(loss.pass);
        assert!(jitter.pass);
    }

    #[test]
    fn accepts_each_deterministic_echo_once_and_byte_for_byte() {
        let frames = encode_test_frames(3).unwrap();
        let mut expected = frames
            .iter()
            .map(|frame| {
                let sequence = RealtimeAudioPacket::decode(frame).unwrap().sequence;
                (sequence, frame.clone())
            })
            .collect();

        take_echoed_frame(&frames[2], &mut expected).unwrap();
        take_echoed_frame(&frames[0], &mut expected).unwrap();
        take_echoed_frame(&frames[1], &mut expected).unwrap();
        assert!(expected.is_empty());
        assert!(take_echoed_frame(&frames[1], &mut expected).is_err());
    }
}
