use anyhow::{anyhow, Result};
use opus::{Application, Bitrate, Channels, Decoder, Encoder};
use std::collections::BTreeMap;

pub const REALTIME_AUDIO_VERSION: u8 = 1;
pub const REALTIME_AUDIO_HEADER_BYTES: usize = 8;
/// Reserved for the desktop FIPS harness. Peers return these packets unchanged
/// instead of playing them, which verifies the real mobile datagram path.
pub const REALTIME_AUDIO_HARNESS_ECHO_FLAG: u8 = 0x80;
pub const MAX_REALTIME_AUDIO_DATAGRAM_BYTES: usize = 1200;
pub const MAX_OPUS_PAYLOAD_BYTES: usize =
    MAX_REALTIME_AUDIO_DATAGRAM_BYTES - REALTIME_AUDIO_HEADER_BYTES;
pub const SAMPLE_RATE: u32 = 48_000;
pub const FRAME_SAMPLES: usize = 960;
pub const FRAME_BYTES: usize = FRAME_SAMPLES * 2;
const OPUS_BITRATE_BPS: i32 = 16_000;
const JITTER_BUFFER_PACKETS: usize = 3;
const JITTER_BUFFER_MAX_PACKETS: usize = 8;

/// Stateful 20 ms Opus encoder for the platform PCM bridge.
pub struct RealtimeAudioEncoder {
    encoder: Encoder,
    sequence: u16,
    timestamp_48khz: u32,
}

impl RealtimeAudioEncoder {
    pub fn new() -> Result<Self> {
        let mut encoder = Encoder::new(SAMPLE_RATE, Channels::Mono, Application::Voip)?;
        encoder.set_bitrate(Bitrate::Bits(OPUS_BITRATE_BPS))?;
        Ok(Self {
            encoder,
            sequence: 0,
            timestamp_48khz: 0,
        })
    }

    pub fn encode_pcm(&mut self, pcm: &[u8]) -> Result<RealtimeAudioPacket> {
        if pcm.len() != FRAME_BYTES {
            return Err(anyhow!(
                "realtime PCM frame must contain exactly {FRAME_BYTES} bytes"
            ));
        }
        let samples = pcm
            .chunks_exact(2)
            .map(|sample| i16::from_le_bytes([sample[0], sample[1]]))
            .collect::<Vec<_>>();
        let opus_payload = self.encoder.encode_vec(&samples, MAX_OPUS_PAYLOAD_BYTES)?;
        let packet = RealtimeAudioPacket {
            sequence: self.sequence,
            timestamp_48khz: self.timestamp_48khz,
            flags: 0,
            opus_payload,
        };
        self.sequence = self.sequence.wrapping_add(1);
        self.timestamp_48khz = self.timestamp_48khz.wrapping_add(FRAME_SAMPLES as u32);
        Ok(packet)
    }
}

/// A bounded packet reorder queue. It starts after three packets and advances
/// past a loss only when later packets show that the missing packet will not arrive.
pub struct RealtimeAudioDecoder {
    decoder: Decoder,
    packets: BTreeMap<u16, RealtimeAudioPacket>,
    expected_sequence: Option<u16>,
    started: bool,
}

impl RealtimeAudioDecoder {
    pub fn new() -> Result<Self> {
        Ok(Self {
            decoder: Decoder::new(SAMPLE_RATE, Channels::Mono)?,
            packets: BTreeMap::new(),
            expected_sequence: None,
            started: false,
        })
    }

    pub fn push(&mut self, packet: RealtimeAudioPacket) -> Result<Option<Vec<u8>>> {
        if self
            .expected_sequence
            .is_some_and(|expected| sequence_before(packet.sequence, expected))
        {
            return Ok(None);
        }
        self.packets.entry(packet.sequence).or_insert(packet);
        while self.packets.len() > JITTER_BUFFER_MAX_PACKETS {
            self.packets.pop_first();
        }
        self.decode_ready()
    }

    pub fn decode_ready(&mut self) -> Result<Option<Vec<u8>>> {
        if self.expected_sequence.is_none() {
            self.expected_sequence = self
                .packets
                .first_key_value()
                .map(|(&sequence, _)| sequence);
        }
        if !self.started {
            if self.packets.len() < JITTER_BUFFER_PACKETS {
                return Ok(None);
            }
            self.started = true;
        }

        let expected = self.expected_sequence.expect("set above");
        let sequence = if self.packets.contains_key(&expected) {
            expected
        } else if self.packets.len() >= JITTER_BUFFER_PACKETS {
            *self.packets.first_key_value().expect("not empty").0
        } else {
            return Ok(None);
        };
        let packet = self.packets.remove(&sequence).expect("present above");
        self.expected_sequence = Some(sequence.wrapping_add(1));

        let mut samples = [0i16; FRAME_SAMPLES];
        let sample_count = self
            .decoder
            .decode(&packet.opus_payload, &mut samples, false)?;
        let mut pcm = Vec::with_capacity(sample_count * 2);
        for sample in &samples[..sample_count] {
            pcm.extend_from_slice(&sample.to_le_bytes());
        }
        Ok(Some(pcm))
    }
}

fn sequence_before(sequence: u16, expected: u16) -> bool {
    sequence != expected && expected.wrapping_sub(sequence) < 0x8000
}

/// A single Opus access unit carried by one unreliable QUIC datagram.
///
/// Wire format: version (u8), flags (u8), sequence (u16 BE), timestamp at
/// 48 kHz (u32 BE), then the Opus payload. The datagram has no length field;
/// its length is supplied by the QUIC datagram boundary.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RealtimeAudioPacket {
    pub sequence: u16,
    pub timestamp_48khz: u32,
    pub flags: u8,
    pub opus_payload: Vec<u8>,
}

impl RealtimeAudioPacket {
    pub fn encode(&self) -> Result<Vec<u8>> {
        validate_payload(&self.opus_payload)?;

        let mut datagram =
            Vec::with_capacity(REALTIME_AUDIO_HEADER_BYTES + self.opus_payload.len());
        datagram.push(REALTIME_AUDIO_VERSION);
        datagram.push(self.flags);
        datagram.extend_from_slice(&self.sequence.to_be_bytes());
        datagram.extend_from_slice(&self.timestamp_48khz.to_be_bytes());
        datagram.extend_from_slice(&self.opus_payload);
        Ok(datagram)
    }

    pub fn decode(datagram: &[u8]) -> Result<Self> {
        if datagram.len() < REALTIME_AUDIO_HEADER_BYTES {
            return Err(anyhow!(
                "realtime audio datagram is shorter than its header"
            ));
        }
        if datagram.len() > MAX_REALTIME_AUDIO_DATAGRAM_BYTES {
            return Err(anyhow!(
                "realtime audio datagram exceeds {MAX_REALTIME_AUDIO_DATAGRAM_BYTES} bytes"
            ));
        }
        if datagram[0] != REALTIME_AUDIO_VERSION {
            return Err(anyhow!(
                "unsupported realtime audio version {}",
                datagram[0]
            ));
        }

        let opus_payload = datagram[REALTIME_AUDIO_HEADER_BYTES..].to_vec();
        validate_payload(&opus_payload)?;
        Ok(Self {
            flags: datagram[1],
            sequence: u16::from_be_bytes([datagram[2], datagram[3]]),
            timestamp_48khz: u32::from_be_bytes([
                datagram[4],
                datagram[5],
                datagram[6],
                datagram[7],
            ]),
            opus_payload,
        })
    }
}

fn validate_payload(opus_payload: &[u8]) -> Result<()> {
    if opus_payload.is_empty() {
        return Err(anyhow!("realtime audio packet requires an Opus payload"));
    }
    if opus_payload.len() > MAX_OPUS_PAYLOAD_BYTES {
        return Err(anyhow!(
            "Opus payload exceeds {MAX_OPUS_PAYLOAD_BYTES} bytes"
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_packet_with_network_byte_order() {
        let packet = RealtimeAudioPacket {
            sequence: 0x1234,
            timestamp_48khz: 0x5678_9abc,
            flags: 0x05,
            opus_payload: vec![0xf8, 0xff, 0xfe],
        };

        let encoded = packet.encode().unwrap();
        assert_eq!(
            encoded,
            vec![1, 0x05, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xf8, 0xff, 0xfe]
        );
        assert_eq!(RealtimeAudioPacket::decode(&encoded).unwrap(), packet);
    }

    #[test]
    fn preserves_the_harness_echo_flag_on_the_wire() {
        let packet = RealtimeAudioPacket {
            sequence: 7,
            timestamp_48khz: 960,
            flags: REALTIME_AUDIO_HARNESS_ECHO_FLAG,
            opus_payload: vec![0xf8],
        };

        assert_eq!(
            RealtimeAudioPacket::decode(&packet.encode().unwrap()).unwrap(),
            packet
        );
    }

    #[test]
    fn rejects_invalid_or_oversized_datagrams() {
        assert!(RealtimeAudioPacket::decode(&[REALTIME_AUDIO_VERSION]).is_err());
        assert!(RealtimeAudioPacket::decode(&[2, 0, 0, 0, 0, 0, 0, 0, 1]).is_err());
        assert!(RealtimeAudioPacket::decode(&[1, 0, 0, 0, 0, 0, 0, 0]).is_err());

        let oversized = RealtimeAudioPacket {
            sequence: 0,
            timestamp_48khz: 0,
            flags: 0,
            opus_payload: vec![0; MAX_OPUS_PAYLOAD_BYTES + 1],
        };
        assert!(oversized.encode().is_err());

        let at_limit = RealtimeAudioPacket {
            sequence: 0,
            timestamp_48khz: 0,
            flags: 0,
            opus_payload: vec![0; MAX_OPUS_PAYLOAD_BYTES],
        };
        assert_eq!(
            at_limit.encode().unwrap().len(),
            MAX_REALTIME_AUDIO_DATAGRAM_BYTES
        );
    }

    #[test]
    fn opus_round_trip_and_jitter_reorders_packets() {
        let mut encoder = RealtimeAudioEncoder::new().unwrap();
        let input = vec![0u8; FRAME_BYTES];
        let first = encoder.encode_pcm(&input).unwrap();
        let second = encoder.encode_pcm(&input).unwrap();
        let third = encoder.encode_pcm(&input).unwrap();
        assert_eq!(first.sequence, 0);
        assert_eq!(second.timestamp_48khz, FRAME_SAMPLES as u32);

        let mut decoder = RealtimeAudioDecoder::new().unwrap();
        assert!(decoder.push(first).unwrap().is_none());
        assert!(decoder.push(third).unwrap().is_none());
        let pcm = decoder.push(second).unwrap().unwrap();
        assert_eq!(pcm.len(), FRAME_BYTES);
        assert!(decoder.decode_ready().unwrap().is_some());
    }

    #[test]
    fn encoder_requires_one_pcm_frame() {
        assert!(RealtimeAudioEncoder::new()
            .unwrap()
            .encode_pcm(&[0; FRAME_BYTES - 1])
            .is_err());
    }

    #[test]
    fn jitter_buffer_skips_a_lost_packet_after_later_packets_arrive() {
        let mut encoder = RealtimeAudioEncoder::new().unwrap();
        let input = vec![0u8; FRAME_BYTES];
        let packets = (0..7)
            .map(|_| encoder.encode_pcm(&input).unwrap())
            .collect::<Vec<_>>();
        let mut decoder = RealtimeAudioDecoder::new().unwrap();

        assert!(decoder.push(packets[0].clone()).unwrap().is_none());
        assert!(decoder.push(packets[1].clone()).unwrap().is_none());
        assert!(decoder.push(packets[2].clone()).unwrap().is_some());
        assert!(decoder.decode_ready().unwrap().is_some());
        assert!(decoder.decode_ready().unwrap().is_some());

        // Packet 3 was lost. Three newer packets make that loss conclusive.
        assert!(decoder.push(packets[4].clone()).unwrap().is_none());
        assert!(decoder.push(packets[5].clone()).unwrap().is_none());
        assert!(decoder.push(packets[6].clone()).unwrap().is_some());
    }

    #[test]
    fn jitter_buffer_handles_sequence_rollover() {
        let mut encoder = RealtimeAudioEncoder::new().unwrap();
        let input = vec![0u8; FRAME_BYTES];
        let mut packets = (0..3)
            .map(|_| encoder.encode_pcm(&input).unwrap())
            .collect::<Vec<_>>();
        packets[0].sequence = u16::MAX - 1;
        packets[1].sequence = u16::MAX;
        packets[2].sequence = 0;

        let mut decoder = RealtimeAudioDecoder::new().unwrap();
        assert!(decoder.push(packets[0].clone()).unwrap().is_none());
        assert!(decoder.push(packets[2].clone()).unwrap().is_none());
        assert!(decoder.push(packets[1].clone()).unwrap().is_some());
        assert!(decoder.decode_ready().unwrap().is_some());
        assert!(decoder.decode_ready().unwrap().is_some());
    }
}
