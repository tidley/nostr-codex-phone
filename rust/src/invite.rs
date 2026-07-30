use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{bail, Context, Result};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use rand::{rngs::OsRng, RngCore};
use rusqlite::{params, Connection};
use sha2::{Digest, Sha256};

pub const DEFAULT_INVITE_TTL_SECONDS: u64 = 15 * 60;
pub const MAX_INVITE_TTL_SECONDS: u64 = 60 * 60;

pub struct InviteStore {
    conn: Connection,
}
pub struct CreatedInvite {
    pub secret: String,
    pub expires_at: i64,
}

impl InviteStore {
    pub fn open(path: &Path) -> Result<Self> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let conn = Connection::open(path)
            .with_context(|| format!("failed to open invite store `{}`", path.display()))?;
        conn.execute_batch("PRAGMA journal_mode = WAL; CREATE TABLE IF NOT EXISTS workspace_invites (code_hash TEXT PRIMARY KEY, expires_at INTEGER NOT NULL, redeemed_by TEXT, redeemed_at INTEGER);")?;
        Ok(Self { conn })
    }
    pub fn create(&mut self, ttl_seconds: Option<u64>) -> Result<CreatedInvite> {
        let ttl = ttl_seconds.unwrap_or(DEFAULT_INVITE_TTL_SECONDS);
        if ttl == 0 || ttl > MAX_INVITE_TTL_SECONDS {
            bail!("invite expiry must be between 1 and {MAX_INVITE_TTL_SECONDS} seconds");
        }
        let mut bytes = [0_u8; 32];
        OsRng.fill_bytes(&mut bytes);
        let secret = URL_SAFE_NO_PAD.encode(bytes);
        let expires_at = now_unix() + ttl as i64;
        self.conn.execute(
            "INSERT INTO workspace_invites (code_hash, expires_at) VALUES (?1, ?2)",
            params![hash_secret(&secret), expires_at],
        )?;
        Ok(CreatedInvite { secret, expires_at })
    }
    pub fn redeem(&mut self, secret: &str, recipient_pubkey: &str) -> Result<bool> {
        let secret = normalize_secret(secret)?;
        Ok(self.conn.execute("UPDATE workspace_invites SET redeemed_by = ?1, redeemed_at = ?2 WHERE code_hash = ?3 AND redeemed_by IS NULL AND expires_at > ?2", params![recipient_pubkey, now_unix(), hash_secret(&secret)])? == 1)
    }
}
fn normalize_secret(secret: &str) -> Result<String> {
    let secret = secret.trim();
    if secret.len() != 43
        || !secret
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_')
        || URL_SAFE_NO_PAD
            .decode(secret)
            .map(|bytes| bytes.len() != 32)
            .unwrap_or(true)
    {
        bail!("invite code is invalid");
    }
    Ok(secret.to_string())
}
fn hash_secret(secret: &str) -> String {
    let mut hash = Sha256::new();
    hash.update(secret.as_bytes());
    format!("{:x}", hash.finalize())
}
fn now_unix() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_secs() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn invite_is_consumed_once() {
        let mut store = InviteStore::open(Path::new(":memory:")).unwrap();
        let invite = store.create(Some(60)).unwrap();
        assert!(store.redeem(&invite.secret, "member").unwrap());
        assert!(!store.redeem(&invite.secret, "other").unwrap());
    }

    #[test]
    fn rejects_non_url_safe_or_wrong_length_secrets() {
        assert!(normalize_secret("A1B2C3D4E5").is_err());
        assert!(normalize_secret(&"a".repeat(43)).is_err());
    }
}
