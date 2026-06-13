use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum WireMessage {
    Query { query: String },
    Audio { audio: AudioReference },
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

    pub fn response<S: Into<String>>(response: S) -> Self {
        Self::Response {
            response: response.into(),
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
            Self::Response { .. } => "response",
            Self::Error { .. } => "error",
        }
    }

    pub fn text(&self) -> &str {
        match self {
            Self::Query { query } => query,
            Self::Audio { audio } => &audio.url,
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

    pub fn to_json(&self) -> Result<String> {
        let value = match self {
            Self::Query { query } => json!({ "query": query }),
            Self::Audio { audio } => json!({ "audio": audio }),
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

    if let Some(response) = object.get("response") {
        return response
            .as_str()
            .map(WireMessage::response)
            .ok_or_else(|| anyhow!("field `response` must be a string"));
    }

    if let Some(error) = object.get("error") {
        return error
            .as_str()
            .map(WireMessage::error)
            .ok_or_else(|| anyhow!("field `error` must be a string"));
    }

    Err(anyhow!(
        "message must contain a string `query`, `response`, `error`, or object `audio` field"
    ))
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
    fn serializes_response_contract() {
        assert_eq!(
            WireMessage::response("done").to_json().unwrap(),
            r#"{"response":"done"}"#
        );
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
                    "name": "voice.m4a"
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
    }

    #[test]
    fn rejects_malformed_payloads() {
        assert!(parse_wire_message(r#"{ "query": 42 }"#).is_err());
        assert!(parse_wire_message(r#"{ "message": "hello" }"#).is_err());
        assert!(parse_wire_message(
            r#"{ "audio": { "url": "ftp://x", "sha256": "bad", "size": 1, "type": "audio/mp4" } }"#
        )
        .is_err());
        assert!(parse_wire_message("hello").is_err());
    }
}
