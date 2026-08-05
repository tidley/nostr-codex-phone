use std::env;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use nostr_sdk::prelude::*;
use reqwest::header::{CONTENT_LENGTH, CONTENT_TYPE};
use reqwest::Url;
use serde::Deserialize;
use sha2::{Digest, Sha256};

const BLOSSOM_AUTH_KIND: u16 = 24_242;

#[derive(Debug, Deserialize)]
struct BlobDescriptor {
    url: String,
    sha256: String,
    size: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
    let path = env::args()
        .nth(1)
        .context("usage: tmp-upload-public-blob <file>")?;
    let content_type = env::args()
        .nth(2)
        .unwrap_or_else(|| "application/octet-stream".to_string());
    let bytes = tokio::fs::read(&path)
        .await
        .with_context(|| format!("failed to read `{path}`"))?;
    let sha256 = sha256_hex(&bytes);
    let upload_url = Url::parse("https://blossom.primal.net/upload")?;
    let keys = Keys::generate();
    let auth = blossom_upload_auth(&keys, &upload_url, &sha256)?;

    let response = reqwest::Client::new()
        .put(upload_url)
        .header(CONTENT_TYPE, content_type)
        .header(CONTENT_LENGTH, bytes.len().to_string())
        .header("X-SHA-256", sha256.as_str())
        .header("Authorization", auth)
        .body(bytes)
        .send()
        .await?;

    let status = response.status();
    if !status.is_success() {
        anyhow::bail!(
            "upload failed with HTTP {status}: {}",
            response.text().await?
        );
    }

    let descriptor: BlobDescriptor = response.json().await?;
    if descriptor.sha256 != sha256 {
        anyhow::bail!("sha mismatch: expected {sha256}, got {}", descriptor.sha256);
    }
    println!("url={}", descriptor.url);
    println!("sha256={}", descriptor.sha256);
    println!("size={}", descriptor.size);
    Ok(())
}

fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn blossom_upload_auth(keys: &Keys, upload_url: &Url, sha256: &str) -> Result<String> {
    let expiration = SystemTime::now()
        .checked_add(Duration::from_secs(10 * 60))
        .context("failed to calculate expiration")?
        .duration_since(UNIX_EPOCH)?
        .as_secs();
    let mut tags = vec![
        Tag::parse(["t", "upload"])?,
        Tag::parse(["expiration", &expiration.to_string()])?,
        Tag::parse(["x", sha256])?,
    ];
    if let Some(host) = upload_url.host_str() {
        tags.push(Tag::parse(["server", &host.to_lowercase()])?);
    }
    let event = EventBuilder::new(Kind::Custom(BLOSSOM_AUTH_KIND), "Upload screen recording")
        .tags(tags)
        .finalize(keys)?;
    Ok(format!("Nostr {}", STANDARD.encode(event.as_json())))
}
