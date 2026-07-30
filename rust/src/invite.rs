use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{bail, Context, Result};
use rand::{rngs::OsRng, RngCore};
use rusqlite::{params, Connection};
use sha2::{Digest, Sha256};

pub const DEFAULT_INVITE_TTL_SECONDS: u64 = 15 * 60;
pub const MAX_INVITE_TTL_SECONDS: u64 = 60 * 60;

pub struct InviteStore {
    conn: Connection,
}
pub struct CreatedInvite {
    pub code: String,
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
        let mut bytes = [0_u8; 5];
        OsRng.fill_bytes(&mut bytes);
        let code = bytes
            .iter()
            .map(|byte| format!("{byte:02X}"))
            .collect::<String>();
        let expires_at = now_unix() + ttl as i64;
        self.conn.execute(
            "INSERT INTO workspace_invites (code_hash, expires_at) VALUES (?1, ?2)",
            params![hash_code(&code), expires_at],
        )?;
        Ok(CreatedInvite { code, expires_at })
    }
    pub fn redeem(&mut self, code: &str, recipient_pubkey: &str) -> Result<bool> {
        let code = normalize_code(code)?;
        Ok(self.conn.execute("UPDATE workspace_invites SET redeemed_by = ?1, redeemed_at = ?2 WHERE code_hash = ?3 AND redeemed_by IS NULL AND expires_at > ?2", params![recipient_pubkey, now_unix(), hash_code(&code)])? == 1)
    }
}
fn normalize_code(code: &str) -> Result<String> {
    let code = code.trim().replace([' ', '-'], "").to_ascii_uppercase();
    if code.len() != 10 || !code.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("invite code is invalid");
    }
    Ok(code)
}
fn hash_code(code: &str) -> String {
    let mut hash = Sha256::new();
    hash.update(code.as_bytes());
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
        assert!(store.redeem(&invite.code, "member").unwrap());
        assert!(!store.redeem(&invite.code, "other").unwrap());
    }
}
