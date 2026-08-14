use std::net::IpAddr;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Context, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use futures_util::StreamExt;
use nostr_sdk::prelude::*;
use reqwest::header::{HeaderMap, CONTENT_LENGTH, CONTENT_TYPE};
use reqwest::{Client, StatusCode, Url};
use serde::Deserialize;
use sha2::{Digest, Sha256};

use crate::audio_crypto::{
    decrypt_audio_payload, encrypt_audio_payload, unwrap_encrypted_payload,
    wrap_encrypted_payload_as_png,
};
use crate::protocol::{AudioReference, MediaReference};

const BLOSSOM_AUTH_KIND: u16 = 24_242;
const ENCRYPTED_BLOB_CONTENT_TYPE: &str = "image/png";
const BLOSSOM_UPLOAD_TIMEOUT: Duration = Duration::from_secs(90);
const BLOSSOM_DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(90);
const MAX_ATTACHMENT_BYTES: u64 = 32 * 1024 * 1024;
const MAX_REDIRECTS: usize = 5;

#[derive(Debug, Clone)]
pub struct DownloadedAttachment {
    pub path: String,
    pub media_type: String,
    pub name: String,
}

#[derive(Debug, Clone)]
pub struct BlossomUploadConfig {
    pub secret_key: String,
    pub server_url: String,
    pub file_path: String,
    pub file_bytes: Option<Vec<u8>>,
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
    let plaintext = match config.file_bytes {
        Some(bytes) => bytes,
        None => tokio::fs::read(&config.file_path)
            .await
            .with_context(|| format!("failed to read audio file `{}`", config.file_path))?,
    };
    if plaintext.is_empty() {
        return Err(anyhow!("audio file is empty"));
    }

    let content_type = clean_content_type(&config.content_type);
    let (ciphertext, encryption) = encrypt_audio_payload(&plaintext, &content_type)?;
    let upload_bytes = wrap_encrypted_payload_as_png(&ciphertext);
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

/// Retrieve an attachment only after validating its transport and integrity metadata.
pub async fn download_attachment(
    reference: MediaReference,
    destination_dir: &str,
) -> Result<DownloadedAttachment> {
    validate_download_reference(&reference)?;
    let client = Client::builder()
        .timeout(BLOSSOM_DOWNLOAD_TIMEOUT)
        .connect_timeout(Duration::from_secs(15))
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .context("failed to build Blossom download client")?;

    let mut url = checked_public_https_url(&reference.url)?;
    let mut redirects = 0;
    let bytes = loop {
        validate_public_host(&url).await?;
        let response = client
            .get(url.clone())
            .send()
            .await
            .with_context(|| format!("failed to download attachment from `{url}`"))?;
        if response.status().is_redirection() {
            if redirects == MAX_REDIRECTS {
                return Err(anyhow!(
                    "attachment download exceeded {MAX_REDIRECTS} redirects"
                ));
            }
            let location = response
                .headers()
                .get(reqwest::header::LOCATION)
                .and_then(|value| value.to_str().ok())
                .ok_or_else(|| anyhow!("attachment redirect has no valid Location header"))?;
            url = checked_public_https_url(url.join(location)?.as_str())?;
            redirects += 1;
            continue;
        }
        if !response.status().is_success() {
            return Err(anyhow!(
                "attachment download failed with HTTP {}",
                response.status()
            ));
        }
        if response
            .content_length()
            .is_some_and(|size| size > reference.size || size > MAX_ATTACHMENT_BYTES)
        {
            return Err(anyhow!(
                "attachment response exceeds its declared size limit"
            ));
        }
        let mut bytes = Vec::with_capacity(reference.size as usize);
        let mut stream = response.bytes_stream();
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.context("failed while reading attachment response")?;
            if bytes.len().saturating_add(chunk.len()) > reference.size as usize
                || bytes.len().saturating_add(chunk.len()) > MAX_ATTACHMENT_BYTES as usize
            {
                return Err(anyhow!(
                    "attachment response exceeds its declared size limit"
                ));
            }
            bytes.extend_from_slice(&chunk);
        }
        break bytes;
    };

    if bytes.len() as u64 != reference.size {
        return Err(anyhow!(
            "attachment size mismatch: expected {} bytes, got {} bytes",
            reference.size,
            bytes.len()
        ));
    }
    let actual_hash = sha256_hex(&bytes);
    if actual_hash != reference.sha256.to_ascii_lowercase() {
        return Err(anyhow!("attachment ciphertext sha256 mismatch"));
    }

    let (plaintext, media_type) = match reference.encryption.as_ref() {
        Some(encryption) => (
            decrypt_audio_payload(&unwrap_encrypted_payload(&bytes)?, encryption)?,
            encryption.plaintext_media_type.clone(),
        ),
        None => (bytes, reference.media_type.clone()),
    };
    if plaintext.len() as u64 > MAX_ATTACHMENT_BYTES {
        return Err(anyhow!(
            "attachment plaintext exceeds {MAX_ATTACHMENT_BYTES} bytes"
        ));
    }

    let destination_dir = Path::new(destination_dir);
    std::fs::create_dir_all(destination_dir).context("failed to create attachment directory")?;
    let name = safe_attachment_name(reference.name.as_deref());
    let path = unique_attachment_path(destination_dir, &name);
    let temporary = path.with_extension(format!(
        "{}.part",
        path.extension()
            .and_then(|value| value.to_str())
            .unwrap_or("download")
    ));
    std::fs::write(&temporary, plaintext).context("failed to write validated attachment")?;
    std::fs::rename(&temporary, &path).context("failed to finalize validated attachment")?;
    Ok(DownloadedAttachment {
        path: path.to_string_lossy().into_owned(),
        media_type,
        name,
    })
}

fn validate_download_reference(reference: &MediaReference) -> Result<()> {
    checked_public_https_url(&reference.url)?;
    if reference.size == 0 || reference.size > MAX_ATTACHMENT_BYTES {
        return Err(anyhow!(
            "attachment size must be between 1 and {MAX_ATTACHMENT_BYTES} bytes"
        ));
    }
    if reference.sha256.len() != 64
        || !reference
            .sha256
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit())
    {
        return Err(anyhow!(
            "attachment sha256 must be a 64-character hex SHA-256"
        ));
    }
    if reference.media_type.trim().is_empty() || !reference.media_type.contains('/') {
        return Err(anyhow!("attachment type must be a MIME type"));
    }
    Ok(())
}

fn checked_public_https_url(value: &str) -> Result<Url> {
    let url = Url::parse(value.trim()).context("attachment URL is invalid")?;
    if url.scheme() != "https"
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return Err(anyhow!(
            "attachment URL must be a credential-free HTTPS URL"
        ));
    }
    Ok(url)
}

async fn validate_public_host(url: &Url) -> Result<()> {
    let host = url
        .host_str()
        .ok_or_else(|| anyhow!("attachment URL has no host"))?;
    let addresses = tokio::net::lookup_host((host, url.port_or_known_default().unwrap_or(443)))
        .await
        .with_context(|| format!("failed to resolve attachment host `{host}`"))?;
    let mut found = false;
    for address in addresses {
        found = true;
        if !is_public_ip(address.ip()) {
            return Err(anyhow!("attachment URL resolves to a non-public address"));
        }
    }
    if !found {
        return Err(anyhow!("attachment host did not resolve to an address"));
    }
    Ok(())
}

fn is_public_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ip) => {
            let octets = ip.octets();
            !(ip.is_private()
                || ip.is_loopback()
                || ip.is_link_local()
                || ip.is_multicast()
                || ip.is_unspecified()
                || octets[0] == 0
                || octets[0] >= 240
                || (octets[0] == 100 && (64..=127).contains(&octets[1]))
                || (octets[0] == 192 && octets[1] == 0 && octets[2] == 2)
                || (octets[0] == 198 && octets[1] == 51 && octets[2] == 100)
                || (octets[0] == 203 && octets[1] == 0 && octets[2] == 113))
        }
        IpAddr::V6(ip) => {
            !(ip.is_loopback()
                || ip.is_unspecified()
                || ip.is_multicast()
                || ip.is_unicast_link_local()
                || (ip.segments()[0] & 0xfe00) == 0xfc00)
        }
    }
}

fn safe_attachment_name(name: Option<&str>) -> String {
    let candidate = name
        .and_then(|value| Path::new(value).file_name())
        .and_then(|value| value.to_str())
        .unwrap_or("attachment");
    let cleaned: String = candidate
        .chars()
        .filter(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '.' | '-' | '_')
        })
        .collect();
    if cleaned.is_empty() || cleaned == "." || cleaned == ".." {
        "attachment".to_string()
    } else {
        cleaned
    }
}

fn unique_attachment_path(directory: &Path, name: &str) -> PathBuf {
    let suffix = format!("{:016x}", rand::random::<u64>());
    directory.join(format!("{suffix}-{name}"))
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

    #[test]
    fn rejects_non_public_attachment_urls() {
        assert!(checked_public_https_url("http://example.com/file").is_err());
        assert!(checked_public_https_url("https://user@example.com/file").is_err());
        assert!(is_public_ip("8.8.8.8".parse().unwrap()));
        assert!(!is_public_ip("127.0.0.1".parse().unwrap()));
        assert!(!is_public_ip("10.0.0.1".parse().unwrap()));
        assert!(!is_public_ip("::1".parse().unwrap()));
    }

    #[test]
    fn validates_bounded_attachment_reference() {
        let reference = MediaReference {
            url: "https://example.com/file".to_string(),
            sha256: "0".repeat(64),
            size: MAX_ATTACHMENT_BYTES + 1,
            media_type: "application/octet-stream".to_string(),
            name: None,
            encryption: None,
        };
        assert!(validate_download_reference(&reference).is_err());
        assert_eq!(
            safe_attachment_name(Some("../../voice note.wav")),
            "voicenote.wav"
        );
    }
}
