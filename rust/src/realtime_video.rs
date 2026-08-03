use anyhow::{anyhow, Result};

/// H.264 access units are fragmented into bounded QUIC datagrams. The first
/// byte differs from the audio wire version, allowing one receiver to demux.
pub const REALTIME_VIDEO_VERSION: u8 = 2;
pub const REALTIME_VIDEO_HEADER_BYTES: usize = 10;
pub const MAX_REALTIME_VIDEO_DATAGRAM_BYTES: usize = 1200;
pub const MAX_VIDEO_FRAGMENT_BYTES: usize =
    MAX_REALTIME_VIDEO_DATAGRAM_BYTES - REALTIME_VIDEO_HEADER_BYTES;
pub const VIDEO_KEY_FRAME_FLAG: u8 = 0x01;
pub const VIDEO_END_OF_FRAME_FLAG: u8 = 0x02;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RealtimeVideoFragment {
    pub flags: u8,
    pub frame_sequence: u16,
    pub fragment_sequence: u16,
    pub timestamp_us: u32,
    pub h264: Vec<u8>,
}

impl RealtimeVideoFragment {
    pub fn encode(&self) -> Result<Vec<u8>> {
        if self.h264.is_empty() || self.h264.len() > MAX_VIDEO_FRAGMENT_BYTES {
            return Err(anyhow!(
                "video fragment must contain 1 to {MAX_VIDEO_FRAGMENT_BYTES} bytes"
            ));
        }
        let mut datagram = Vec::with_capacity(REALTIME_VIDEO_HEADER_BYTES + self.h264.len());
        datagram.push(REALTIME_VIDEO_VERSION);
        datagram.push(self.flags);
        datagram.extend_from_slice(&self.frame_sequence.to_be_bytes());
        datagram.extend_from_slice(&self.fragment_sequence.to_be_bytes());
        datagram.extend_from_slice(&self.timestamp_us.to_be_bytes());
        datagram.extend_from_slice(&self.h264);
        Ok(datagram)
    }

    pub fn decode(datagram: &[u8]) -> Result<Self> {
        if datagram.len() <= REALTIME_VIDEO_HEADER_BYTES {
            return Err(anyhow!(
                "realtime video datagram is shorter than its header"
            ));
        }
        if datagram.len() > MAX_REALTIME_VIDEO_DATAGRAM_BYTES {
            return Err(anyhow!(
                "realtime video datagram exceeds {MAX_REALTIME_VIDEO_DATAGRAM_BYTES} bytes"
            ));
        }
        if datagram[0] != REALTIME_VIDEO_VERSION {
            return Err(anyhow!(
                "unsupported realtime video version {}",
                datagram[0]
            ));
        }
        Ok(Self {
            flags: datagram[1],
            frame_sequence: u16::from_be_bytes([datagram[2], datagram[3]]),
            fragment_sequence: u16::from_be_bytes([datagram[4], datagram[5]]),
            timestamp_us: u32::from_be_bytes([datagram[6], datagram[7], datagram[8], datagram[9]]),
            h264: datagram[REALTIME_VIDEO_HEADER_BYTES..].to_vec(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn video_fragment_round_trips_at_the_datagram_boundary() {
        let fragment = RealtimeVideoFragment {
            flags: VIDEO_KEY_FRAME_FLAG | VIDEO_END_OF_FRAME_FLAG,
            frame_sequence: 7,
            fragment_sequence: 2,
            timestamp_us: 123,
            h264: vec![0, 0, 0, 1, 0x65],
        };
        assert_eq!(
            RealtimeVideoFragment::decode(&fragment.encode().unwrap()).unwrap(),
            fragment
        );
    }

    #[test]
    fn rejects_empty_or_oversized_video_fragments() {
        assert!(RealtimeVideoFragment::decode(
            &[REALTIME_VIDEO_VERSION; REALTIME_VIDEO_HEADER_BYTES]
        )
        .is_err());
        assert!(RealtimeVideoFragment {
            flags: 0,
            frame_sequence: 0,
            fragment_sequence: 0,
            timestamp_us: 0,
            h264: vec![0; MAX_VIDEO_FRAGMENT_BYTES + 1],
        }
        .encode()
        .is_err());
    }
}
