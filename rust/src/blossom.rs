use std::path::Path;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Context, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use nostr_sdk::prelude::*;
use reqwest::header::{HeaderMap, CONTENT_LENGTH, CONTENT_TYPE};
use reqwest::{Client, StatusCode, Url};
use serde::Deserialize;
use sha2::{Digest, Sha256};

use crate::audio_crypto::encrypt_audio_payload;
use crate::protocol::AudioReference;

const BLOSSOM_AUTH_KIND: u16 = 24_242;
const ENCRYPTED_BLOB_CONTENT_TYPE: &str = "application/octet-stream";
const BLOSSOM_UPLOAD_TIMEOUT: Duration = Duration::from_secs(90);

#[derive(Debug, Clone)]
pub struct BlossomUploadConfig {
    pub secret_key: String,
    pub server_url: String,
    pub file_path: String,
    pub content_type: String,
    pub file_name: Option<String>,
}

#[derive(Debug, Deserialize)]
struct BlobDescriptor {
    url: String,
    sha256: String,
    size: u64,
    #[serde(rename = "type")]
    _media_type: String,
}

pub async fn upload_audio(config: BlossomUploadConfig) -> Result<AudioReference> {
    let plaintext = tokio::fs::read(&config.file_path)
        .await
        .with_context(|| format!("failed to read audio file `{}`", config.file_path))?;
    if plaintext.is_empty() {
        return Err(anyhow!("audio file is empty"));
    }

    let content_type = clean_content_type(&config.content_type);
    let (upload_bytes, encryption) = encrypt_audio_payload(&plaintext, &content_type)?;
    let sha256 = sha256_hex(&upload_bytes);
    let upload_len = upload_bytes.len();
    let upload_url = upload_url(&config.server_url)?;
    let auth = blossom_upload_auth(&config.secret_key, &upload_url, &sha256)?;

    let client = Client::builder()
        .timeout(BLOSSOM_UPLOAD_TIMEOUT)
        .connect_timeout(Duration::from_secs(15))
        .build()
        .context("failed to build Blossom client")?;

    let response = client
        .put(upload_url.clone())
        .header(CONTENT_TYPE, ENCRYPTED_BLOB_CONTENT_TYPE)
        .header(CONTENT_LENGTH, upload_len.to_string())
        .header("X-SHA-256", sha256.as_str())
        .header("Authorization", auth)
        .body(upload_bytes)
        .send()
        .await
        .with_context(|| format!("failed to upload audio to Blossom server `{upload_url}`"))?;

    let status = response.status();
    let headers = response.headers().clone();
    if status != StatusCode::OK && status != StatusCode::CREATED {
        return Err(anyhow!(
            "Blossom upload failed with HTTP {status}: {}",
            blossom_error_reason(&headers, response).await
        ));
    }

    let descriptor: BlobDescriptor = response
        .json()
        .await
        .context("failed to parse Blossom blob descriptor")?;

    if descriptor.sha256.to_lowercase() != sha256 {
        return Err(anyhow!(
            "Blossom server returned mismatched sha256: expected {sha256}, got {}",
            descriptor.sha256
        ));
    }
    if descriptor.size as usize == 0 {
        return Err(anyhow!("Blossom server returned an empty blob descriptor"));
    }
    if descriptor.size as usize != upload_len {
        return Err(anyhow!(
            "Blossom server returned mismatched size: expected {}, got {}",
            upload_len,
            descriptor.size
        ));
    }

    Ok(AudioReference {
        url: descriptor.url,
        sha256,
        size: descriptor.size,
        media_type: content_type,
        name: config
            .file_name
            .filter(|name| !name.trim().is_empty())
            .or_else(|| {
                Path::new(&config.file_path)
                    .file_name()
                    .and_then(|name| name.to_str())
                    .map(ToOwned::to_owned)
            }),
        encryption: Some(encryption),
    })
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn blossom_upload_auth(secret_key: &str, upload_url: &Url, sha256: &str) -> Result<String> {
    let keys = Keys::parse(secret_key.trim()).context("invalid Blossom upload secret key")?;
    let expiration = SystemTime::now()
        .checked_add(Duration::from_secs(10 * 60))
        .ok_or_else(|| anyhow!("failed to calculate Blossom auth expiration"))?
        .duration_since(UNIX_EPOCH)
        .context("system clock is before UNIX epoch")?
        .as_secs();

    let mut tags = vec![
        Tag::parse(["t", "upload"])?,
        Tag::parse(["expiration", &expiration.to_string()])?,
        Tag::parse(["x", sha256])?,
    ];
    if let Some(host) = upload_url.host_str() {
        tags.push(Tag::parse(["server", &host.to_lowercase()])?);
    }

    let event = EventBuilder::new(Kind::Custom(BLOSSOM_AUTH_KIND), "Upload audio blob")
        .tags(tags)
        .finalize(&keys)
        .context("failed to sign Blossom authorization event")?;
    let token = URL_SAFE_NO_PAD.encode(event.as_json());
    Ok(format!("Nostr {token}"))
}

fn upload_url(server_url: &str) -> Result<Url> {
    let base = server_url.trim().trim_end_matches('/');
    if base.is_empty() {
        return Err(anyhow!("Blossom server URL is required"));
    }
    Url::parse(&format!("{base}/upload")).context("invalid Blossom server URL")
}

fn clean_content_type(value: &str) -> String {
    let value = value.trim().to_ascii_lowercase();
    let base = value
        .split(';')
        .next()
        .map(str::trim)
        .filter(|entry| !entry.is_empty())
        .unwrap_or("");
    if base.contains('/') {
        base.to_string()
    } else {
        "application/octet-stream".to_string()
    }
}

async fn blossom_error_reason(headers: &HeaderMap, response: reqwest::Response) -> String {
    let header_reason = headers
        .get("X-Reason")
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned);
    if let Some(reason) = header_reason {
        return reason;
    }

    response
        .text()
        .await
        .map(|body| {
            let body = body.trim();
            if body.is_empty() {
                "empty error response".to_string()
            } else {
                body.to_string()
            }
        })
        .unwrap_or_else(|err| format!("failed to read error response body: {err}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hashes_bytes_as_lowercase_hex() {
        assert_eq!(
            sha256_hex(b"hello"),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        );
    }

    #[test]
    fn builds_upload_url() {
        assert_eq!(
            upload_url("https://example.com/").unwrap().as_str(),
            "https://example.com/upload"
        );
    }

    #[test]
    fn normalizes_content_type() {
        assert_eq!(clean_content_type("image/jpeg"), "image/jpeg");
        assert_eq!(
            clean_content_type("Image/JPEG; charset=utf-8"),
            "image/jpeg"
        );
        assert_eq!(clean_content_type("audio/ogg"), "audio/ogg");
        assert_eq!(clean_content_type(""), "application/octet-stream");
        assert_eq!(clean_content_type("audio"), "application/octet-stream");
    }
}
