use std::any::Any;
use std::env;
use std::fs::File;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use hound::{SampleFormat, WavReader, WavSpec, WavWriter};
use ogg::PacketReader;
use opus_decoder::OpusDecoder;
use reqwest::Client;
use symphonia::core::audio::{AudioBufferRef, SampleBuffer};
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error as SymphoniaError;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use symphonia::default::{get_codecs, get_probe};
use tempfile::TempDir;
use tokio::process::Command;

use crate::audio_crypto::{decrypt_audio_payload, unwrap_encrypted_payload};
use crate::blossom::sha256_hex;
use crate::protocol::AudioReference;

const MIN_TRANSCRIBE_AUDIO_DURATION: Duration = Duration::from_secs(1);

#[derive(Debug, Clone)]
pub struct AudioConfig {
    pub max_bytes: u64,
}

#[derive(Debug, Clone)]
pub struct TranscribeConfig {
    pub bin: String,
    pub args: Vec<String>,
    pub timeout: Duration,
    pub ffmpeg_bin: String,
    pub transcode_timeout: Duration,
}

pub struct DownloadedAudio {
    _temp_dir: TempDir,
    pub path: PathBuf,
}

impl AudioConfig {
    pub fn from_env() -> Self {
        let max_bytes = env::var("AUDIO_MAX_BYTES")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(25 * 1024 * 1024);
        Self { max_bytes }
    }
}

impl TranscribeConfig {
    pub fn from_env() -> Result<Self> {
        let bin = env::var("TRANSCRIBE_BIN").unwrap_or_else(|_| "whisper".to_string());
        let args = match env::var("TRANSCRIBE_ARGS") {
            Ok(raw) if !raw.trim().is_empty() => shell_words::split(&raw)
                .with_context(|| format!("failed to parse TRANSCRIBE_ARGS `{raw}`"))?,
            _ => vec![
                "{audio}".to_string(),
                "--model".to_string(),
                env::var("WHISPER_MODEL").unwrap_or_else(|_| "base.en".to_string()),
                "--output_format".to_string(),
                "txt".to_string(),
                "--output_dir".to_string(),
                "{output_dir}".to_string(),
            ],
        };
        let timeout_secs = env::var("TRANSCRIBE_TIMEOUT_SECS")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(180);
        let ffmpeg_bin = env::var("FFMPEG_BIN").unwrap_or_else(|_| "ffmpeg".to_string());
        let transcode_timeout_secs = env::var("AUDIO_TRANSCODE_TIMEOUT_SECS")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(60);

        Ok(Self {
            bin,
            args,
            timeout: Duration::from_secs(timeout_secs),
            ffmpeg_bin,
            transcode_timeout: Duration::from_secs(transcode_timeout_secs),
        })
    }
}

pub async fn download_blossom_audio(
    audio: &AudioReference,
    config: &AudioConfig,
) -> Result<DownloadedAudio> {
    let extension = audio_extension(audio);
    download_blossom_attachment(audio, &extension, config).await
}

pub async fn download_blossom_attachment(
    attachment: &AudioReference,
    extension: &str,
    config: &AudioConfig,
) -> Result<DownloadedAudio> {
    if attachment.size > config.max_bytes {
        return Err(anyhow!(
            "attachment blob is too large: {} bytes > {} byte limit",
            attachment.size,
            config.max_bytes
        ));
    }

    let response = Client::new()
        .get(&attachment.url)
        .send()
        .await
        .with_context(|| format!("failed to download attachment `{}`", attachment.url))?;
    let status = response.status();
    if !status.is_success() {
        return Err(anyhow!(
            "failed to download attachment blob `{}`: HTTP {status}",
            attachment.url
        ));
    }

    let bytes = response
        .bytes()
        .await
        .with_context(|| format!("failed to read attachment blob `{}`", attachment.url))?;
    if bytes.len() as u64 > config.max_bytes {
        return Err(anyhow!(
            "downloaded attachment blob is too large: {} bytes > {} byte limit",
            bytes.len(),
            config.max_bytes
        ));
    }

    let actual_hash = sha256_hex(&bytes);
    if actual_hash != attachment.sha256.to_lowercase() {
        return Err(anyhow!(
            "attachment blob sha256 mismatch: expected {}, got {actual_hash}",
            attachment.sha256
        ));
    }

    let (attachment_bytes, attachment_hash) = if let Some(encryption) = &attachment.encryption {
        let ciphertext = unwrap_encrypted_payload(&bytes)?;
        let plaintext = decrypt_audio_payload(&ciphertext, encryption)?;
        if plaintext.len() as u64 > config.max_bytes {
            return Err(anyhow!(
                "decrypted attachment is too large: {} bytes > {} byte limit",
                plaintext.len(),
                config.max_bytes
            ));
        }
        (plaintext, encryption.plaintext_sha256.to_lowercase())
    } else {
        (bytes.to_vec(), actual_hash)
    };

    let temp_dir = tempfile::tempdir().context("failed to create attachment temp directory")?;
    let extension = if extension.trim().is_empty() {
        "bin"
    } else {
        extension.trim()
    };
    let path = temp_dir
        .path()
        .join(format!("{attachment_hash}.{extension}"));
    tokio::fs::write(&path, &attachment_bytes)
        .await
        .with_context(|| {
            format!(
                "failed to write downloaded attachment to `{}`",
                path.display()
            )
        })?;

    Ok(DownloadedAudio {
        _temp_dir: temp_dir,
        path,
    })
}

pub async fn transcribe_audio(audio_path: &Path, config: &TranscribeConfig) -> Result<String> {
    let prepared_audio = prepare_audio_for_transcription(audio_path, config).await?;
    reject_short_audio(&prepared_audio.path)?;
    let output_dir = tempfile::tempdir().context("failed to create transcript temp directory")?;
    let audio_arg = prepared_audio.path.to_string_lossy().to_string();
    let output_dir_arg = output_dir.path().to_string_lossy().to_string();
    let args = config
        .args
        .iter()
        .map(|arg| {
            arg.replace("{audio}", &audio_arg)
                .replace("{output_dir}", &output_dir_arg)
        })
        .collect::<Vec<_>>();

    let mut command = Command::new(&config.bin);
    command
        .args(&args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);

    let output = tokio::time::timeout(config.timeout, command.output())
        .await
        .map_err(|_| anyhow!("transcription timed out after {}s", config.timeout.as_secs()))?
        .with_context(|| {
            format!(
                "failed to run `{}`; set TRANSCRIBE_BIN/TRANSCRIBE_ARGS if Whisper is installed elsewhere",
                config.bin
            )
        })?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !output.status.success() {
        if stderr.is_empty() {
            return Err(anyhow!(
                "transcription exited with status {}",
                output.status
            ));
        }
        return Err(anyhow!(
            "transcription exited with status {}: {}",
            output.status,
            stderr
        ));
    }

    let transcript = read_transcript_file(output_dir.path())
        .await?
        .unwrap_or(stdout);
    let transcript = transcript.trim().to_string();
    if transcript.is_empty() {
        return Err(anyhow!("transcription completed but produced no text"));
    }

    Ok(transcript)
}

fn reject_short_audio(audio_path: &Path) -> Result<()> {
    let reader = WavReader::open(audio_path).with_context(|| {
        format!(
            "failed to inspect prepared audio `{}`",
            audio_path.display()
        )
    })?;
    let sample_rate = reader.spec().sample_rate;
    if sample_rate == 0 {
        return Err(anyhow!("prepared audio sample rate is zero"));
    }

    let duration = Duration::from_secs_f64(reader.duration() as f64 / sample_rate as f64);
    if duration < MIN_TRANSCRIBE_AUDIO_DURATION {
        return Err(anyhow!(
            "audio recording is too short: {:.2}s; minimum is 1.00s",
            duration.as_secs_f64()
        ));
    }
    Ok(())
}

struct PreparedAudio {
    _temp_dir: Option<TempDir>,
    path: PathBuf,
}

async fn prepare_audio_for_transcription(
    audio_path: &Path,
    config: &TranscribeConfig,
) -> Result<PreparedAudio> {
    if is_wav_path(audio_path) {
        return Ok(PreparedAudio {
            _temp_dir: None,
            path: audio_path.to_path_buf(),
        });
    }

    let temp_dir = tempfile::tempdir().context("failed to create transcode temp directory")?;
    let wav_path = temp_dir.path().join("audio.wav");
    if let Err(rust_err) =
        transcode_to_wav_with_rust_blocking(audio_path.to_path_buf(), wav_path.clone()).await
    {
        transcode_to_wav_with_ffmpeg(audio_path, &wav_path, config)
            .await
            .with_context(|| {
                format!("pure-Rust audio transcode failed: {rust_err:#}; ffmpeg fallback failed")
            })?;
    }

    Ok(PreparedAudio {
        _temp_dir: Some(temp_dir),
        path: wav_path,
    })
}

async fn transcode_to_wav_with_rust_blocking(input: PathBuf, output: PathBuf) -> Result<()> {
    let input_display = input.display().to_string();
    match tokio::task::spawn_blocking(move || transcode_to_wav_with_rust(&input, &output)).await {
        Ok(result) => result,
        Err(err) => Err(transcode_join_error(err, &input_display)),
    }
}

fn transcode_join_error(err: tokio::task::JoinError, input: &str) -> anyhow::Error {
    if err.is_panic() {
        let payload = err.into_panic();
        return anyhow!(
            "pure-Rust audio transcode panicked for `{input}`: {}",
            panic_payload_description(payload.as_ref())
        );
    }
    if err.is_cancelled() {
        return anyhow!("pure-Rust audio transcode task was cancelled for `{input}`");
    }
    anyhow!("pure-Rust audio transcode task failed for `{input}`: {err}")
}

fn panic_payload_description(payload: &(dyn Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<&'static str>() {
        return (*message).to_string();
    }
    if let Some(message) = payload.downcast_ref::<String>() {
        return message.clone();
    }
    "non-string panic payload".to_string()
}

fn transcode_to_wav_with_rust(input: &Path, output: &Path) -> Result<()> {
    if is_ogg_path(input) {
        return transcode_ogg_opus_to_wav_with_rust(input, output);
    }

    let source = File::open(input)
        .with_context(|| format!("failed to open compressed audio `{}`", input.display()))?;
    let media_source = MediaSourceStream::new(Box::new(source), Default::default());
    let mut hint = Hint::new();
    if let Some(extension) = input.extension().and_then(|extension| extension.to_str()) {
        hint.with_extension(extension);
    }

    let probed = get_probe()
        .format(
            &hint,
            media_source,
            &FormatOptions::default(),
            &MetadataOptions::default(),
        )
        .context("failed to probe compressed audio container")?;
    let mut format = probed.format;
    let track = format
        .default_track()
        .or_else(|| {
            format
                .tracks()
                .iter()
                .find(|track| track.codec_params.codec != CODEC_TYPE_NULL)
        })
        .ok_or_else(|| anyhow!("compressed audio contains no supported audio track"))?;
    let track_id = track.id;
    let codec_params = track.codec_params.clone();
    let mut decoder = get_codecs()
        .make(&codec_params, &DecoderOptions::default())
        .context("failed to create compressed audio decoder")?;

    let mut mono_samples = Vec::<f32>::new();
    let mut sample_rate = codec_params.sample_rate.unwrap_or(0);

    loop {
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(SymphoniaError::IoError(err)) if err.kind() == ErrorKind::UnexpectedEof => break,
            Err(err) => return Err(anyhow!("failed to read compressed audio packet: {err}")),
        };

        if packet.track_id() != track_id {
            continue;
        }

        let decoded = match decoder.decode(&packet) {
            Ok(decoded) => decoded,
            Err(SymphoniaError::DecodeError(_)) => continue,
            Err(SymphoniaError::IoError(err)) if err.kind() == ErrorKind::UnexpectedEof => break,
            Err(err) => return Err(anyhow!("failed to decode compressed audio packet: {err}")),
        };
        append_decoded_mono_samples(decoded, &mut mono_samples, &mut sample_rate)?;
    }

    if mono_samples.is_empty() {
        return Err(anyhow!("compressed audio decoded to no samples"));
    }
    if sample_rate == 0 {
        return Err(anyhow!("compressed audio sample rate is unknown"));
    }

    let resampled = resample_linear_mono(&mono_samples, sample_rate, 16_000);
    write_mono_wav(output, 16_000, &resampled)?;
    Ok(())
}

fn transcode_ogg_opus_to_wav_with_rust(input: &Path, output: &Path) -> Result<()> {
    let source = File::open(input)
        .with_context(|| format!("failed to open Ogg Opus `{}`", input.display()))?;
    let mut reader = PacketReader::new(source);

    let head_packet = reader
        .read_packet()
        .context("failed to read Ogg Opus head packet")?
        .ok_or_else(|| anyhow!("Ogg Opus stream is empty"))?;
    let head = parse_opus_head(&head_packet.data)?;
    if head.mapping_family != 0 {
        return Err(anyhow!(
            "unsupported Ogg Opus channel mapping family {}; only mono/stereo family 0 is supported",
            head.mapping_family
        ));
    }
    if !(1..=2).contains(&head.channels) {
        return Err(anyhow!(
            "unsupported Ogg Opus channel count {}; only mono/stereo is supported",
            head.channels
        ));
    }

    let tags_packet = reader
        .read_packet()
        .context("failed to read Ogg Opus tags packet")?
        .ok_or_else(|| anyhow!("Ogg Opus stream is missing OpusTags packet"))?;
    if !tags_packet.data.starts_with(b"OpusTags") {
        return Err(anyhow!("Ogg Opus stream is missing OpusTags packet"));
    }

    let mut decoder = OpusDecoder::new(48_000, head.channels)
        .map_err(|err| anyhow!("failed to create pure-Rust Opus decoder: {err:?}"))?;
    let mut frame = vec![0i16; OpusDecoder::MAX_FRAME_SIZE_48K * head.channels];
    let mut decoded = Vec::<f32>::new();
    let mut samples_to_skip = head.pre_skip_48k;

    while let Some(packet) = reader
        .read_packet()
        .context("failed to read Ogg Opus audio packet")?
    {
        if packet.data.is_empty() {
            continue;
        }
        let samples_per_channel = decoder
            .decode(&packet.data, &mut frame, false)
            .map_err(|err| anyhow!("failed to decode Ogg Opus packet: {err:?}"))?;
        let frame_samples = &frame[..samples_per_channel * head.channels];

        for sample_index in 0..samples_per_channel {
            if samples_to_skip > 0 {
                samples_to_skip -= 1;
                continue;
            }

            let mono = if head.channels == 1 {
                frame_samples[sample_index] as f32 / i16::MAX as f32
            } else {
                let left = frame_samples[sample_index * 2] as f32 / i16::MAX as f32;
                let right = frame_samples[sample_index * 2 + 1] as f32 / i16::MAX as f32;
                (left + right) * 0.5
            };
            decoded.push(mono.clamp(-1.0, 1.0));
        }
    }

    if decoded.is_empty() {
        return Err(anyhow!("Ogg Opus decoded to no samples"));
    }

    let resampled = resample_linear_mono(&decoded, 48_000, 16_000);
    write_mono_wav(output, 16_000, &resampled)?;
    Ok(())
}

#[derive(Debug, Clone, Copy)]
struct OpusHead {
    channels: usize,
    pre_skip_48k: usize,
    mapping_family: u8,
}

fn parse_opus_head(packet: &[u8]) -> Result<OpusHead> {
    if packet.len() < 19 || !packet.starts_with(b"OpusHead") {
        return Err(anyhow!("Ogg stream is missing OpusHead packet"));
    }

    let version = packet[8];
    if version & 0xf0 != 0 {
        return Err(anyhow!("unsupported OpusHead version {version}"));
    }

    let channels = packet[9] as usize;
    if channels == 0 {
        return Err(anyhow!("OpusHead channel count must be greater than zero"));
    }

    let pre_skip_48k = u16::from_le_bytes([packet[10], packet[11]]) as usize;
    let mapping_family = packet[18];

    Ok(OpusHead {
        channels,
        pre_skip_48k,
        mapping_family,
    })
}

fn append_decoded_mono_samples(
    decoded: AudioBufferRef<'_>,
    mono_samples: &mut Vec<f32>,
    sample_rate: &mut u32,
) -> Result<()> {
    let spec = *decoded.spec();
    if *sample_rate == 0 {
        *sample_rate = spec.rate;
    }

    let channels = spec.channels.count();
    if channels == 0 {
        return Err(anyhow!("decoded audio packet has no channels"));
    }

    let mut sample_buffer = SampleBuffer::<f32>::new(decoded.capacity() as u64, spec);
    sample_buffer.copy_interleaved_ref(decoded);
    for frame in sample_buffer.samples().chunks(channels) {
        let mono = frame.iter().copied().sum::<f32>() / frame.len().max(1) as f32;
        mono_samples.push(mono);
    }

    Ok(())
}

fn resample_linear_mono(samples: &[f32], input_rate: u32, output_rate: u32) -> Vec<f32> {
    if samples.is_empty() || input_rate == output_rate {
        return samples.to_vec();
    }

    let output_len = ((samples.len() as u64 * output_rate as u64) / input_rate as u64)
        .max(1)
        .min(usize::MAX as u64) as usize;
    let step = input_rate as f64 / output_rate as f64;
    let mut output = Vec::with_capacity(output_len);

    for output_index in 0..output_len {
        let position = output_index as f64 * step;
        let base = position.floor() as usize;
        let next = (base + 1).min(samples.len() - 1);
        let fraction = (position - base as f64) as f32;
        output.push(samples[base] + (samples[next] - samples[base]) * fraction);
    }

    output
}

fn write_mono_wav(path: &Path, sample_rate: u32, samples: &[f32]) -> Result<()> {
    let spec = WavSpec {
        channels: 1,
        sample_rate,
        bits_per_sample: 16,
        sample_format: SampleFormat::Int,
    };
    let mut writer = WavWriter::create(path, spec)
        .with_context(|| format!("failed to create WAV `{}`", path.display()))?;
    for sample in samples {
        writer
            .write_sample(f32_to_i16(*sample))
            .context("failed to write WAV sample")?;
    }
    writer.finalize().context("failed to finalize WAV")?;
    Ok(())
}

fn f32_to_i16(sample: f32) -> i16 {
    let clamped = sample.clamp(-1.0, 1.0);
    (clamped * i16::MAX as f32).round() as i16
}

async fn transcode_to_wav_with_ffmpeg(
    input: &Path,
    output: &Path,
    config: &TranscribeConfig,
) -> Result<()> {
    let mut command = Command::new(&config.ffmpeg_bin);
    command
        .arg("-y")
        .arg("-hide_banner")
        .arg("-loglevel")
        .arg("error")
        .arg("-i")
        .arg(input)
        .arg("-ac")
        .arg("1")
        .arg("-ar")
        .arg("16000")
        .arg("-c:a")
        .arg("pcm_s16le")
        .arg(output)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);

    let output_result = tokio::time::timeout(config.transcode_timeout, command.output())
        .await
        .map_err(|_| {
            anyhow!(
                "audio transcode timed out after {}s",
                config.transcode_timeout.as_secs()
            )
        })?
        .with_context(|| {
            format!(
                "failed to run `{}`; install ffmpeg or set FFMPEG_BIN for unsupported compressed audio fallback",
                config.ffmpeg_bin
            )
        })?;

    let stderr = String::from_utf8_lossy(&output_result.stderr)
        .trim()
        .to_string();
    if !output_result.status.success() {
        if stderr.is_empty() {
            return Err(anyhow!(
                "audio transcode exited with status {}",
                output_result.status
            ));
        }
        return Err(anyhow!(
            "audio transcode exited with status {}: {}",
            output_result.status,
            stderr
        ));
    }

    Ok(())
}

fn is_wav_path(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .map(|extension| extension.eq_ignore_ascii_case("wav"))
        .unwrap_or(false)
}

fn is_ogg_path(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .map(|extension| {
            extension.eq_ignore_ascii_case("ogg") || extension.eq_ignore_ascii_case("opus")
        })
        .unwrap_or(false)
}

fn audio_extension(audio: &AudioReference) -> String {
    let media_type = audio
        .encryption
        .as_ref()
        .map(|encryption| encryption.plaintext_media_type.as_str())
        .unwrap_or(audio.media_type.as_str());

    match media_type {
        "audio/mpeg" | "audio/mp3" => "mp3".to_string(),
        "audio/wav" | "audio/wave" | "audio/x-wav" => "wav".to_string(),
        "audio/ogg" => "ogg".to_string(),
        "audio/webm" => "webm".to_string(),
        "audio/aac" => "aac".to_string(),
        "audio/flac" => "flac".to_string(),
        "audio/mp4" | "audio/x-m4a" | "audio/m4a" => "m4a".to_string(),
        _ => audio
            .name
            .as_deref()
            .and_then(|name| name.rsplit_once('.').map(|(_, ext)| ext))
            .filter(|ext| !ext.is_empty() && ext.len() <= 8)
            .unwrap_or("m4a")
            .to_string(),
    }
}

async fn read_transcript_file(output_dir: &Path) -> Result<Option<String>> {
    let mut entries = tokio::fs::read_dir(output_dir).await.with_context(|| {
        format!(
            "failed to read transcript output dir `{}`",
            output_dir.display()
        )
    })?;
    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) == Some("txt") {
            return tokio::fs::read_to_string(&path)
                .await
                .map(Some)
                .with_context(|| format!("failed to read transcript `{}`", path.display()));
        }
    }
    Ok(None)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_wav_paths_case_insensitively() {
        assert!(is_wav_path(Path::new("voice.wav")));
        assert!(is_wav_path(Path::new("voice.WAV")));
        assert!(!is_wav_path(Path::new("voice.m4a")));
    }

    #[test]
    fn detects_ogg_paths_case_insensitively() {
        assert!(is_ogg_path(Path::new("voice.ogg")));
        assert!(is_ogg_path(Path::new("voice.OPUS")));
        assert!(!is_ogg_path(Path::new("voice.m4a")));
    }

    #[test]
    fn parses_opus_head_contract() {
        let mut packet = b"OpusHead".to_vec();
        packet.extend_from_slice(&[1, 1, 0x80, 0x02, 0x80, 0xbb, 0x00, 0x00, 0, 0, 0]);

        let head = parse_opus_head(&packet).unwrap();
        assert_eq!(head.channels, 1);
        assert_eq!(head.pre_skip_48k, 640);
        assert_eq!(head.mapping_family, 0);
    }

    #[test]
    fn resamples_mono_audio_to_target_rate() {
        let input = vec![0.0, 1.0, 0.0, -1.0];
        let output = resample_linear_mono(&input, 4, 2);

        assert_eq!(output.len(), 2);
        assert_eq!(output, vec![0.0, 0.0]);
    }

    #[test]
    fn clamps_f32_samples_to_i16() {
        assert_eq!(f32_to_i16(2.0), i16::MAX);
        assert_eq!(f32_to_i16(-2.0), -i16::MAX);
        assert_eq!(f32_to_i16(0.0), 0);
    }

    #[test]
    fn rejects_prepared_audio_under_one_second() {
        let temp_dir = tempfile::tempdir().unwrap();
        let short_wav = temp_dir.path().join("short.wav");
        let full_wav = temp_dir.path().join("full.wav");

        write_mono_wav(&short_wav, 16_000, &vec![0.0; 15_999]).unwrap();
        write_mono_wav(&full_wav, 16_000, &vec![0.0; 16_000]).unwrap();

        assert!(reject_short_audio(&short_wav).is_err());
        assert!(reject_short_audio(&full_wav).is_ok());
    }

    #[test]
    fn pure_rust_transcodes_generated_m4a_when_ffmpeg_is_available() {
        let ffmpeg = std::env::var("FFMPEG_BIN").unwrap_or_else(|_| "ffmpeg".to_string());
        if std::process::Command::new(&ffmpeg)
            .arg("-version")
            .output()
            .is_err()
        {
            return;
        }

        let temp_dir = tempfile::tempdir().unwrap();
        let input = temp_dir.path().join("test.m4a");
        let output = temp_dir.path().join("test.wav");
        let status = std::process::Command::new(&ffmpeg)
            .args([
                "-hide_banner",
                "-loglevel",
                "error",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=1000:duration=1",
                "-ac",
                "1",
                "-ar",
                "16000",
                "-c:a",
                "aac",
            ])
            .arg(&input)
            .status()
            .unwrap();
        assert!(status.success());

        transcode_to_wav_with_rust(&input, &output).unwrap();
        assert!(is_wav_path(&output));
        assert!(std::fs::metadata(output).unwrap().len() > 44);
    }

    #[test]
    fn pure_rust_transcodes_generated_ogg_opus_when_ffmpeg_is_available() {
        let ffmpeg = std::env::var("FFMPEG_BIN").unwrap_or_else(|_| "ffmpeg".to_string());
        if std::process::Command::new(&ffmpeg)
            .arg("-version")
            .output()
            .is_err()
        {
            return;
        }

        let temp_dir = tempfile::tempdir().unwrap();
        let input = temp_dir.path().join("test.ogg");
        let output = temp_dir.path().join("test.wav");
        let status = std::process::Command::new(&ffmpeg)
            .args([
                "-hide_banner",
                "-loglevel",
                "error",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=1000:duration=1",
                "-ac",
                "1",
                "-ar",
                "48000",
                "-c:a",
                "libopus",
                "-b:a",
                "32k",
            ])
            .arg(&input)
            .status()
            .unwrap();
        if !status.success() {
            return;
        }

        transcode_ogg_opus_to_wav_with_rust(&input, &output).unwrap();
        assert!(is_wav_path(&output));
        assert!(std::fs::metadata(output).unwrap().len() > 44);
    }
}
