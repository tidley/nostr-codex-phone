use std::env;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use reqwest::Client;
use tempfile::TempDir;
use tokio::process::Command;

use crate::blossom::sha256_hex;
use crate::protocol::AudioReference;

#[derive(Debug, Clone)]
pub struct AudioConfig {
    pub max_bytes: u64,
}

#[derive(Debug, Clone)]
pub struct TranscribeConfig {
    pub bin: String,
    pub args: Vec<String>,
    pub timeout: Duration,
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

        Ok(Self {
            bin,
            args,
            timeout: Duration::from_secs(timeout_secs),
        })
    }
}

pub async fn download_blossom_audio(
    audio: &AudioReference,
    config: &AudioConfig,
) -> Result<DownloadedAudio> {
    if audio.size > config.max_bytes {
        return Err(anyhow!(
            "audio blob is too large: {} bytes > {} byte limit",
            audio.size,
            config.max_bytes
        ));
    }

    let response = Client::new()
        .get(&audio.url)
        .send()
        .await
        .with_context(|| format!("failed to download audio blob `{}`", audio.url))?;
    let status = response.status();
    if !status.is_success() {
        return Err(anyhow!(
            "failed to download audio blob `{}`: HTTP {status}",
            audio.url
        ));
    }

    let bytes = response
        .bytes()
        .await
        .with_context(|| format!("failed to read audio blob `{}`", audio.url))?;
    if bytes.len() as u64 > config.max_bytes {
        return Err(anyhow!(
            "downloaded audio blob is too large: {} bytes > {} byte limit",
            bytes.len(),
            config.max_bytes
        ));
    }

    let actual_hash = sha256_hex(&bytes);
    if actual_hash != audio.sha256.to_lowercase() {
        return Err(anyhow!(
            "audio blob sha256 mismatch: expected {}, got {actual_hash}",
            audio.sha256
        ));
    }

    let temp_dir = tempfile::tempdir().context("failed to create audio temp directory")?;
    let extension = audio_extension(audio);
    let path = temp_dir
        .path()
        .join(format!("{}.{}", audio.sha256, extension));
    tokio::fs::write(&path, &bytes)
        .await
        .with_context(|| format!("failed to write downloaded audio to `{}`", path.display()))?;

    Ok(DownloadedAudio {
        _temp_dir: temp_dir,
        path,
    })
}

pub async fn transcribe_audio(audio_path: &Path, config: &TranscribeConfig) -> Result<String> {
    let output_dir = tempfile::tempdir().context("failed to create transcript temp directory")?;
    let audio_arg = audio_path.to_string_lossy().to_string();
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

fn audio_extension(audio: &AudioReference) -> String {
    match audio.media_type.as_str() {
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
