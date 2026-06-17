use anyhow::{anyhow, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

pub const AUDIO_ENCRYPTION_ALGORITHM: &str = "xchacha20poly1305";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum WireMessage {
    Query { query: String },
    Audio { audio: AudioReference },
    MediaBundle { media_bundle: MediaBundle },
    AudioRetry { audio_retry: AudioRetryRequest },
    Transcript { transcript: String },
    Status { status: String },
    Response { response: String },
    Error { error: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AudioReference {
    pub url: String,
    pub sha256: String,
    pub size: u64,
    #[serde(rename = "type")]
    pub media_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub encryption: Option<AudioEncryption>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MediaBundle {
    #[serde(default)]
    pub query: Option<String>,
    #[serde(default)]
    pub attachments: Vec<MediaReference>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MediaReference {
    pub url: String,
    pub sha256: String,
    pub size: u64,
    #[serde(rename = "type")]
    pub media_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub encryption: Option<AudioEncryption>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AudioEncryption {
    pub algorithm: String,
    pub key: String,
    pub nonce: String,
    pub plaintext_sha256: String,
    pub plaintext_size: u64,
    #[serde(rename = "plaintext_type")]
    pub plaintext_media_type: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AudioRetryRequest {
    pub format: String,
    pub reason: String,
}

impl WireMessage {
    pub fn query<S: Into<String>>(query: S) -> Self {
        Self::Query {
            query: query.into(),
        }
    }

    pub fn audio(audio: AudioReference) -> Self {
        Self::Audio { audio }
    }

    pub fn media_bundle(media_bundle: MediaBundle) -> Self {
        Self::MediaBundle { media_bundle }
    }

    pub fn audio_retry(format: impl Into<String>, reason: impl Into<String>) -> Self {
        Self::AudioRetry {
            audio_retry: AudioRetryRequest {
                format: format.into(),
                reason: reason.into(),
            },
        }
    }

    pub fn response<S: Into<String>>(response: S) -> Self {
        Self::Response {
            response: response.into(),
        }
    }

    pub fn transcript<S: Into<String>>(transcript: S) -> Self {
        Self::Transcript {
            transcript: transcript.into(),
        }
    }

    pub fn status<S: Into<String>>(status: S) -> Self {
        Self::Status {
            status: status.into(),
        }
    }

    pub fn error<S: Into<String>>(error: S) -> Self {
        Self::Error {
            error: error.into(),
        }
    }

    pub fn kind(&self) -> &'static str {
        match self {
            Self::Query { .. } => "query",
            Self::Audio { .. } => "audio",
            Self::MediaBundle { .. } => "media_bundle",
            Self::AudioRetry { .. } => "audio_retry",
            Self::Transcript { .. } => "transcript",
            Self::Status { .. } => "status",
            Self::Response { .. } => "response",
            Self::Error { .. } => "error",
        }
    }

    pub fn text(&self) -> &str {
        match self {
            Self::Query { query } => query,
            Self::Audio { audio } => &audio.url,
            Self::MediaBundle { media_bundle } => {
                media_bundle.query.as_deref().unwrap_or("[media bundle]")
            }
            Self::AudioRetry { audio_retry } => &audio_retry.reason,
            Self::Transcript { transcript } => transcript,
            Self::Status { status } => status,
            Self::Response { response } => response,
            Self::Error { error } => error,
        }
    }

    pub fn audio_reference(&self) -> Option<&AudioReference> {
        match self {
            Self::Audio { audio } => Some(audio),
            _ => None,
        }
    }

    pub fn media_bundle_ref(&self) -> Option<&MediaBundle> {
        match self {
            Self::MediaBundle { media_bundle } => Some(media_bundle),
            _ => None,
        }
    }

    pub fn to_json(&self) -> Result<String> {
        let value = match self {
            Self::Query { query } => json!({ "query": query }),
            Self::Audio { audio } => json!({ "audio": audio }),
            Self::MediaBundle { media_bundle } => {
                json!({ "media_bundle": media_bundle })
            }
            Self::AudioRetry { audio_retry } => json!({ "audio_retry": audio_retry }),
            Self::Transcript { transcript } => json!({ "transcript": transcript }),
            Self::Status { status } => json!({ "status": status }),
            Self::Response { response } => json!({ "response": response }),
            Self::Error { error } => json!({ "error": error }),
        };
        Ok(serde_json::to_string(&value)?)
    }
}

pub fn parse_wire_message(content: &str) -> Result<WireMessage> {
    let value: Value =
        serde_json::from_str(content).map_err(|err| anyhow!("message is not valid JSON: {err}"))?;
    let object = value
        .as_object()
        .ok_or_else(|| anyhow!("message must be a JSON object"))?;

    if let Some(media_bundle) = object.get("media_bundle") {
        let media_bundle: MediaBundle = serde_json::from_value(media_bundle.clone())
            .map_err(|err| anyhow!("field `media_bundle` is invalid: {err}"))?;
        validate_media_bundle(&media_bundle)?;
        return Ok(WireMessage::media_bundle(media_bundle));
    }

    if let Some(query) = object.get("query") {
        return query
            .as_str()
            .map(WireMessage::query)
            .ok_or_else(|| anyhow!("field `query` must be a string"));
    }

    if let Some(audio) = object.get("audio") {
        let audio: AudioReference = serde_json::from_value(audio.clone())
            .map_err(|err| anyhow!("field `audio` is invalid: {err}"))?;
        validate_audio_reference(&audio)?;
        return Ok(WireMessage::audio(audio));
    }

    if let Some(audio_retry) = object.get("audio_retry") {
        let audio_retry: AudioRetryRequest = serde_json::from_value(audio_retry.clone())
            .map_err(|err| anyhow!("field `audio_retry` is invalid: {err}"))?;
        validate_audio_retry_request(&audio_retry)?;
        return Ok(WireMessage::audio_retry(
            audio_retry.format,
            audio_retry.reason,
        ));
    }

    if let Some(response) = object.get("response") {
        return response
            .as_str()
            .map(WireMessage::response)
            .ok_or_else(|| anyhow!("field `response` must be a string"));
    }

    if let Some(transcript) = object.get("transcript") {
        return transcript
            .as_str()
            .map(WireMessage::transcript)
            .ok_or_else(|| anyhow!("field `transcript` must be a string"));
    }

    if let Some(status) = object.get("status") {
        return status
            .as_str()
            .map(WireMessage::status)
            .ok_or_else(|| anyhow!("field `status` must be a string"));
    }

    if let Some(error) = object.get("error") {
        return error
            .as_str()
            .map(WireMessage::error)
            .ok_or_else(|| anyhow!("field `error` must be a string"));
    }

    Err(anyhow!(
        "message must contain a string `query`, `transcript`, `status`, `response`, `error`, object `audio`, object `audio_retry`, or object `media_bundle` field"
    ))
}

pub fn parse_media_bundle_query(content: &str) -> Result<MediaBundle> {
    let value: Value = serde_json::from_str(content)
        .map_err(|err| anyhow!("media bundle must be valid JSON: {err}"))?;
    let object = value
        .as_object()
        .ok_or_else(|| anyhow!("media bundle request must be a JSON object"))?;

    let raw_bundle = if object.contains_key("media_bundle") {
        object
            .get("media_bundle")
            .ok_or_else(|| anyhow!("media bundle request is missing `media_bundle`"))?
            .clone()
    } else if object.contains_key("attachments") {
        value
    } else {
        return Err(anyhow!(
            "media bundle request must either include `media_bundle` or `attachments`"
        ));
    };

    let media_bundle: MediaBundle = serde_json::from_value(raw_bundle)
        .map_err(|err| anyhow!("media_bundle is invalid: {err}"))?;
    validate_media_bundle(&media_bundle)?;
    Ok(media_bundle)
}

fn validate_audio_reference(audio: &AudioReference) -> Result<()> {
    if !(audio.url.starts_with("https://") || audio.url.starts_with("http://")) {
        return Err(anyhow!("field `audio.url` must be an HTTP(S) URL"));
    }
    if audio.sha256.len() != 64 || !audio.sha256.chars().all(|ch| ch.is_ascii_hexdigit()) {
        return Err(anyhow!(
            "field `audio.sha256` must be a 64-character hex SHA-256"
        ));
    }
    if audio.size == 0 {
        return Err(anyhow!("field `audio.size` must be greater than zero"));
    }
    if !audio.media_type.starts_with("audio/") {
        return Err(anyhow!("field `audio.type` must be an audio MIME type"));
    }
    if let Some(encryption) = &audio.encryption {
        validate_audio_encryption(encryption)?;
    }
    Ok(())
}

fn validate_media_bundle(media_bundle: &MediaBundle) -> Result<()> {
    if media_bundle.query.is_none() && media_bundle.attachments.is_empty() {
        return Err(anyhow!(
            "media_bundle must include `query` and/or `attachments`"
        ));
    }

    for attachment in &media_bundle.attachments {
        validate_media_reference(attachment)?;
    }

    Ok(())
}

fn validate_media_reference(reference: &MediaReference) -> Result<()> {
    if !(reference.url.starts_with("https://") || reference.url.starts_with("http://")) {
        return Err(anyhow!(
            "field `media.reference.url` must be an HTTP(S) URL"
        ));
    }
    if reference.sha256.len() != 64 || !reference.sha256.chars().all(|ch| ch.is_ascii_hexdigit()) {
        return Err(anyhow!(
            "field `media.reference.sha256` must be a 64-character hex SHA-256"
        ));
    }
    if reference.size == 0 {
        return Err(anyhow!(
            "field `media.reference.size` must be greater than zero"
        ));
    }
    if !reference.media_type.contains('/') {
        return Err(anyhow!(
            "field `media.reference.type` must be a MIME type such as `image/jpeg`"
        ));
    }
    if let Some(encryption) = &reference.encryption {
        validate_media_encryption(encryption)?;
    }
    Ok(())
}

fn validate_audio_encryption(encryption: &AudioEncryption) -> Result<()> {
    validate_media_encryption(encryption)?;
    if !encryption.plaintext_media_type.starts_with("audio/") {
        return Err(anyhow!(
            "field `audio.encryption.plaintext_type` must be an audio MIME type"
        ));
    }
    Ok(())
}

fn validate_media_encryption(encryption: &AudioEncryption) -> Result<()> {
    if encryption.algorithm != AUDIO_ENCRYPTION_ALGORITHM {
        return Err(anyhow!(
            "field `audio.encryption.algorithm` must be `{AUDIO_ENCRYPTION_ALGORITHM}`"
        ));
    }
    validate_base64url_len("audio.encryption.key", &encryption.key, 32)?;
    validate_base64url_len("audio.encryption.nonce", &encryption.nonce, 24)?;
    if encryption.plaintext_sha256.len() != 64
        || !encryption
            .plaintext_sha256
            .chars()
            .all(|ch| ch.is_ascii_hexdigit())
    {
        return Err(anyhow!(
            "field `audio.encryption.plaintext_sha256` must be a 64-character hex SHA-256"
        ));
    }
    if encryption.plaintext_size == 0 {
        return Err(anyhow!(
            "field `audio.encryption.plaintext_size` must be greater than zero"
        ));
    }
    if !encryption.plaintext_media_type.contains('/') {
        return Err(anyhow!(
            "field `audio.encryption.plaintext_type` must be a MIME type such as `audio/wav`"
        ));
    }
    Ok(())
}

fn validate_audio_retry_request(request: &AudioRetryRequest) -> Result<()> {
    if request.format.trim().is_empty() {
        return Err(anyhow!(
            "field `audio_retry.format` must be a non-empty string"
        ));
    }
    if request.reason.trim().is_empty() {
        return Err(anyhow!(
            "field `audio_retry.reason` must be a non-empty string"
        ));
    }
    Ok(())
}

fn validate_base64url_len(field: &str, value: &str, expected_len: usize) -> Result<()> {
    let decoded = URL_SAFE_NO_PAD
        .decode(value)
        .map_err(|err| anyhow!("field `{field}` must be base64url: {err}"))?;
    if decoded.len() != expected_len {
        return Err(anyhow!(
            "field `{field}` must decode to {expected_len} bytes, got {} bytes",
            decoded.len()
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_query_contract() {
        let parsed = parse_wire_message(r#"{ "query": "hello" }"#).unwrap();
        assert_eq!(parsed, WireMessage::query("hello"));
        assert_eq!(parsed.kind(), "query");
        assert_eq!(parsed.text(), "hello");
    }

    #[test]
    fn parses_media_bundle_payload() {
        let parsed = parse_wire_message(
            r#"{
                "media_bundle": {
                    "query": "review this image",
                    "attachments": [
                        {
                            "url": "https://cdn.example.com/photo.jpg",
                            "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                            "size": 123,
                            "type": "image/jpeg",
                            "name": "photo.jpg"
                        }
                    ]
                }
            }"#,
        )
        .unwrap();
        assert_eq!(parsed.kind(), "media_bundle");
        assert_eq!(
            parsed
                .media_bundle_ref()
                .and_then(|bundle| bundle.query.clone()),
            Some("review this image".to_string())
        );
    }

    #[test]
    fn serializes_response_contract() {
        assert_eq!(
            WireMessage::response("done").to_json().unwrap(),
            r#"{"response":"done"}"#
        );
    }

    #[test]
    fn parses_status_contract() {
        let parsed = parse_wire_message(r#"{ "status": "working" }"#).unwrap();
        assert_eq!(parsed, WireMessage::status("working"));
        assert_eq!(parsed.kind(), "status");
        assert_eq!(parsed.text(), "working");
    }

    #[test]
    fn serializes_status_contract() {
        assert_eq!(
            WireMessage::status("working").to_json().unwrap(),
            r#"{"status":"working"}"#
        );
    }

    #[test]
    fn parses_transcript_contract() {
        let parsed = parse_wire_message(r#"{ "transcript": "turn on the lights" }"#).unwrap();
        assert_eq!(parsed.kind(), "transcript");
        assert_eq!(parsed.text(), "turn on the lights");
    }

    #[test]
    fn parses_audio_contract() {
        let parsed = parse_wire_message(
            r#"{
                "audio": {
                    "url": "https://cdn.example.com/abc.mp4",
                    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                    "size": 123,
                    "type": "audio/mp4",
                    "name": "voice.m4a",
                    "encryption": {
                        "algorithm": "xchacha20poly1305",
                        "key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                        "nonce": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                        "plaintext_sha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
                        "plaintext_size": 107,
                        "plaintext_type": "audio/mp4"
                    }
                }
            }"#,
        )
        .unwrap();
        assert_eq!(parsed.kind(), "audio");
        assert_eq!(parsed.text(), "https://cdn.example.com/abc.mp4");
        assert_eq!(
            parsed.audio_reference().unwrap().sha256,
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        );
        assert!(parsed.audio_reference().unwrap().encryption.is_some());
    }

    #[test]
    fn parses_audio_retry_contract() {
        let parsed = parse_wire_message(
            r#"{
                "audio_retry": {
                    "format": "wav",
                    "reason": "Compressed audio failed; please retry in WAV mode."
                }
            }"#,
        )
        .unwrap();

        assert_eq!(parsed.kind(), "audio_retry");
        assert_eq!(
            parsed.text(),
            "Compressed audio failed; please retry in WAV mode."
        );
        assert_eq!(
            parsed.to_json().unwrap(),
            r#"{"audio_retry":{"format":"wav","reason":"Compressed audio failed; please retry in WAV mode."}}"#
        );
    }

    #[test]
    fn rejects_malformed_payloads() {
        assert!(parse_wire_message(r#"{ "query": 42 }"#).is_err());
        assert!(parse_wire_message(r#"{ "message": "hello" }"#).is_err());
        assert!(parse_wire_message(
            r#"{ "audio": { "url": "ftp://x", "sha256": "bad", "size": 1, "type": "audio/mp4" } }"#
        )
        .is_err());
        assert!(parse_wire_message(
            r#"{ "audio": { "url": "https://x", "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", "size": 1, "type": "audio/mp4", "encryption": { "algorithm": "xchacha20poly1305", "key": "bad", "nonce": "bad", "plaintext_sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", "plaintext_size": 1, "plaintext_type": "audio/mp4" } } }"#
        )
        .is_err());
        assert!(parse_wire_message(r#"{ "audio_retry": "wav" }"#).is_err());
        assert!(
            parse_wire_message(r#"{ "audio_retry": { "format": "", "reason": "retry" } }"#)
                .is_err()
        );
        assert!(parse_wire_message("hello").is_err());
    }
}
