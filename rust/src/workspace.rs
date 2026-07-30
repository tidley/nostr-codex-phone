use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{bail, Context, Result};
use rand::{rngs::OsRng, RngCore};
use rusqlite::{params, Connection};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceChannel {
    pub id: String,
    pub name: String,
    pub created_by: String,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceMessage {
    pub id: String,
    pub channel_id: Option<String>,
    pub recipient_pubkey: Option<String>,
    pub sender_pubkey: String,
    pub body: String,
    pub parent_id: Option<String>,
    pub created_at: i64,
}

pub struct WorkspaceStore {
    conn: Connection,
}

impl WorkspaceStore {
    pub fn open(path: &Path) -> Result<Self> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let conn = Connection::open(path)
            .with_context(|| format!("failed to open workspace store `{}`", path.display()))?;
        conn.execute_batch(
            "PRAGMA journal_mode = WAL;
             CREATE TABLE IF NOT EXISTS workspace_members (pubkey TEXT PRIMARY KEY, joined_at INTEGER NOT NULL);
             CREATE TABLE IF NOT EXISTS workspace_channels (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, created_by TEXT NOT NULL, created_at INTEGER NOT NULL);
             CREATE TABLE IF NOT EXISTS workspace_messages (id TEXT PRIMARY KEY, channel_id TEXT, recipient_pubkey TEXT, sender_pubkey TEXT NOT NULL, body TEXT NOT NULL, parent_id TEXT, created_at INTEGER NOT NULL,
               CHECK ((channel_id IS NOT NULL) != (recipient_pubkey IS NOT NULL)));
             CREATE INDEX IF NOT EXISTS workspace_messages_channel ON workspace_messages(channel_id, created_at);
             CREATE INDEX IF NOT EXISTS workspace_messages_direct ON workspace_messages(recipient_pubkey, sender_pubkey, created_at);",
        )?;
        Ok(Self { conn })
    }

    pub fn add_member(&self, pubkey: &str) -> Result<()> {
        let pubkey = required("member pubkey", pubkey)?;
        self.conn.execute(
            "INSERT OR IGNORE INTO workspace_members (pubkey, joined_at) VALUES (?1, ?2)",
            params![pubkey, now()],
        )?;
        Ok(())
    }

    pub fn is_member(&self, pubkey: &str) -> Result<bool> {
        Ok(self.conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM workspace_members WHERE pubkey = ?1)",
            [pubkey.trim()],
            |row| row.get(0),
        )?)
    }

    pub fn members(&self) -> Result<Vec<String>> {
        let mut statement = self
            .conn
            .prepare("SELECT pubkey FROM workspace_members ORDER BY joined_at, pubkey")?;
        let members = statement
            .query_map([], |row| row.get(0))?
            .collect::<rusqlite::Result<_>>()
            .map_err(Into::into);
        members
    }

    pub fn create_channel(&self, name: &str, created_by: &str) -> Result<WorkspaceChannel> {
        let name = required("channel name", name)?.to_ascii_lowercase();
        if !name
            .chars()
            .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '-')
        {
            bail!("channel name may contain lowercase letters, numbers, and hyphens only");
        }
        let channel = WorkspaceChannel {
            id: new_id(),
            name,
            created_by: required("creator", created_by)?,
            created_at: now(),
        };
        self.conn.execute("INSERT INTO workspace_channels (id, name, created_by, created_at) VALUES (?1, ?2, ?3, ?4)", params![channel.id, channel.name, channel.created_by, channel.created_at])?;
        Ok(channel)
    }

    pub fn channels(&self) -> Result<Vec<WorkspaceChannel>> {
        let mut statement = self.conn.prepare("SELECT id, name, created_by, created_at FROM workspace_channels ORDER BY created_at, name")?;
        let channels = statement
            .query_map([], channel_from_row)?
            .collect::<rusqlite::Result<_>>()
            .map_err(Into::into);
        channels
    }

    pub fn add_channel_message(
        &self,
        sender: &str,
        channel_id: &str,
        body: &str,
        parent_id: Option<&str>,
    ) -> Result<WorkspaceMessage> {
        self.require_channel(channel_id)?;
        self.add_message(sender, Some(channel_id), None, body, parent_id)
    }

    pub fn add_direct_message(
        &self,
        sender: &str,
        recipient: &str,
        body: &str,
        parent_id: Option<&str>,
    ) -> Result<WorkspaceMessage> {
        let recipient = required("recipient", recipient)?;
        if !self.is_member(&recipient)? {
            bail!("recipient is not a workspace member");
        }
        self.add_message(sender, None, Some(&recipient), body, parent_id)
    }

    fn add_message(
        &self,
        sender: &str,
        channel_id: Option<&str>,
        recipient: Option<&str>,
        body: &str,
        parent_id: Option<&str>,
    ) -> Result<WorkspaceMessage> {
        let message = WorkspaceMessage {
            id: new_id(),
            channel_id: channel_id.map(ToOwned::to_owned),
            recipient_pubkey: recipient.map(ToOwned::to_owned),
            sender_pubkey: required("sender", sender)?,
            body: required("message", body)?,
            parent_id: parent_id.map(|id| required("parent id", id)).transpose()?,
            created_at: now(),
        };
        if let Some(parent_id) = &message.parent_id {
            self.require_parent(
                parent_id,
                message.channel_id.as_deref(),
                message.recipient_pubkey.as_deref(),
                &message.sender_pubkey,
            )?;
        }
        self.conn.execute("INSERT INTO workspace_messages (id, channel_id, recipient_pubkey, sender_pubkey, body, parent_id, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)", params![message.id, message.channel_id, message.recipient_pubkey, message.sender_pubkey, message.body, message.parent_id, message.created_at])?;
        Ok(message)
    }

    pub fn channel_messages(&self, channel_id: &str) -> Result<Vec<WorkspaceMessage>> {
        self.require_channel(channel_id)?;
        self.messages("channel_id = ?1", [channel_id])
    }

    pub fn direct_messages(&self, member: &str, peer: &str) -> Result<Vec<WorkspaceMessage>> {
        let member = required("member", member)?;
        let peer = required("peer", peer)?;
        self.messages("channel_id IS NULL AND ((sender_pubkey = ?1 AND recipient_pubkey = ?2) OR (sender_pubkey = ?2 AND recipient_pubkey = ?1))", [&member, &peer])
    }

    fn messages<P: rusqlite::Params>(
        &self,
        predicate: &str,
        params: P,
    ) -> Result<Vec<WorkspaceMessage>> {
        let query = format!("SELECT id, channel_id, recipient_pubkey, sender_pubkey, body, parent_id, created_at FROM workspace_messages WHERE {predicate} ORDER BY created_at, id");
        let mut statement = self.conn.prepare(&query)?;
        let messages = statement
            .query_map(params, message_from_row)?
            .collect::<rusqlite::Result<_>>()
            .map_err(Into::into);
        messages
    }

    fn require_channel(&self, channel_id: &str) -> Result<()> {
        if self.conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM workspace_channels WHERE id = ?1)",
            [channel_id],
            |row| row.get::<_, bool>(0),
        )? {
            Ok(())
        } else {
            bail!("channel does not exist")
        }
    }
    fn require_parent(
        &self,
        parent_id: &str,
        channel_id: Option<&str>,
        recipient: Option<&str>,
        sender: &str,
    ) -> Result<()> {
        let parent = self.conn.query_row("SELECT channel_id, recipient_pubkey, sender_pubkey FROM workspace_messages WHERE id = ?1", [parent_id], |row| Ok((row.get::<_, Option<String>>(0)?, row.get::<_, Option<String>>(1)?, row.get::<_, String>(2)?))).optional()?;
        let Some((parent_channel, parent_recipient, parent_sender)) = parent else {
            bail!("thread parent does not exist")
        };
        if parent_channel.as_deref() != channel_id {
            bail!("thread parent belongs to another channel")
        }
        if recipient.is_some()
            && !(parent_sender == sender
                || parent_sender == recipient.unwrap()
                || parent_recipient.as_deref() == Some(sender)
                || parent_recipient.as_deref() == recipient)
        {
            bail!("thread parent belongs to another direct conversation")
        }
        Ok(())
    }
}

use rusqlite::OptionalExtension;
fn channel_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<WorkspaceChannel> {
    Ok(WorkspaceChannel {
        id: row.get(0)?,
        name: row.get(1)?,
        created_by: row.get(2)?,
        created_at: row.get(3)?,
    })
}
fn message_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<WorkspaceMessage> {
    Ok(WorkspaceMessage {
        id: row.get(0)?,
        channel_id: row.get(1)?,
        recipient_pubkey: row.get(2)?,
        sender_pubkey: row.get(3)?,
        body: row.get(4)?,
        parent_id: row.get(5)?,
        created_at: row.get(6)?,
    })
}
fn required(label: &str, value: &str) -> Result<String> {
    let value = value.trim();
    if value.is_empty() {
        bail!("{label} cannot be empty")
    }
    Ok(value.to_string())
}
fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0)
}
fn new_id() -> String {
    let mut bytes = [0; 16];
    OsRng.fill_bytes(&mut bytes);
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn persists_channels_messages_and_threads() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let parent = store
            .add_channel_message("owner", &channel.id, "hello", None)
            .unwrap();
        store
            .add_channel_message("member", &channel.id, "reply", Some(&parent.id))
            .unwrap();
        drop(store);
        let reopened = WorkspaceStore::open(path.path()).unwrap();
        assert_eq!(reopened.channels().unwrap().len(), 1);
        assert_eq!(
            reopened.channel_messages(&channel.id).unwrap()[1]
                .parent_id
                .as_deref(),
            Some(parent.id.as_str())
        );
    }
    #[test]
    fn rejects_unrelated_direct_thread_and_non_members() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        assert!(store
            .add_direct_message("owner", "outsider", "no", None)
            .is_err());
        let message = store
            .add_direct_message("owner", "member", "hi", None)
            .unwrap();
        assert!(store
            .add_direct_message("owner", "member", "bad", Some("unknown"))
            .is_err());
        assert_eq!(
            store.direct_messages("owner", "member").unwrap()[0].id,
            message.id
        );
    }
}
