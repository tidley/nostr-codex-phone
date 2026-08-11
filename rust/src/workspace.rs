use std::path::Path;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::protocol::{MediaReference, WorkspaceMentionPayload, WorkspaceReactionPayload};
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
pub struct WorkspaceMember {
    pub pubkey: String,
    pub display_name: String,
    pub is_admin: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceMessage {
    pub id: String,
    pub channel_id: Option<String>,
    pub recipient_pubkey: Option<String>,
    pub sender_pubkey: String,
    pub body: String,
    pub attachments: Vec<MediaReference>,
    pub mentions: Vec<WorkspaceMentionPayload>,
    pub parent_id: Option<String>,
    pub also_send_to_main: bool,
    pub reactions: Vec<WorkspaceReactionPayload>,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceAgent {
    pub id: String,
    pub name: String,
    pub role: String,
    pub traits: String,
    pub skills: Vec<String>,
    pub preset: Option<String>,
    pub opencode_provider_id: Option<String>,
    pub opencode_provider_name: Option<String>,
    pub opencode_model_id: Option<String>,
    pub opencode_model_name: Option<String>,
    pub opencode_agent: Option<String>,
    pub workdir: Option<String>,
    pub restart_on_failure: bool,
    pub opencode_session_id: Option<String>,
    pub session_status: String,
    pub session_error: Option<String>,
    pub instance_id: String,
    pub created_by: String,
    pub created_at: i64,
    pub initialized_at: Option<i64>,
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct WorkspaceAgentOpenCodeProfile {
    pub provider_id: Option<String>,
    pub provider_name: Option<String>,
    pub model_id: Option<String>,
    pub model_name: Option<String>,
    pub agent: Option<String>,
    pub workdir: Option<String>,
    pub restart_on_failure: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceConversationAgent {
    pub agent_id: String,
    pub channel_id: Option<String>,
    pub member_pubkey: Option<String>,
    pub peer_pubkey: Option<String>,
    pub folder_scope: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceConversationPreprompt {
    pub channel_id: Option<String>,
    pub member_pubkey: Option<String>,
    pub peer_pubkey: Option<String>,
    pub preprompt: String,
}

pub struct WorkspaceStore {
    conn: Connection,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceNotification {
    pub id: i64,
    pub recipient: String,
    pub payload: String,
    pub attempts: i64,
}

impl WorkspaceStore {
    pub fn open(path: &Path) -> Result<Self> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let conn = Self::open_connection(path)?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS workspace_members (pubkey TEXT PRIMARY KEY, display_name TEXT NOT NULL DEFAULT '', is_admin INTEGER NOT NULL DEFAULT 0, joined_at INTEGER NOT NULL);
               CREATE TABLE IF NOT EXISTS workspace_channels (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, created_by TEXT NOT NULL, created_at INTEGER NOT NULL);
                 CREATE TABLE IF NOT EXISTS workspace_messages (id TEXT PRIMARY KEY, channel_id TEXT, recipient_pubkey TEXT, sender_pubkey TEXT NOT NULL, body TEXT NOT NULL, attachments_json TEXT NOT NULL DEFAULT '[]', mentions_json TEXT NOT NULL DEFAULT '[]', parent_id TEXT, also_send_to_main INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL,
                   CHECK ((channel_id IS NOT NULL) != (recipient_pubkey IS NOT NULL)));
                  CREATE TABLE IF NOT EXISTS workspace_message_reactions (message_id TEXT NOT NULL REFERENCES workspace_messages(id), emoji TEXT NOT NULL, sender_pubkey TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (message_id, emoji, sender_pubkey));
                  CREATE TABLE IF NOT EXISTS workspace_notification_outbox (id INTEGER PRIMARY KEY, recipient TEXT NOT NULL, payload TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
                 CREATE TABLE IF NOT EXISTS workspace_agents (id TEXT PRIMARY KEY, name TEXT NOT NULL, role TEXT NOT NULL, traits TEXT NOT NULL DEFAULT '', skills_json TEXT NOT NULL DEFAULT '[]', preset TEXT, opencode_provider_id TEXT, opencode_provider_name TEXT, opencode_model_id TEXT, opencode_model_name TEXT, opencode_agent TEXT, workdir TEXT, restart_on_failure INTEGER NOT NULL DEFAULT 1, opencode_session_id TEXT, session_status TEXT NOT NULL DEFAULT 'failed', session_error TEXT, created_by TEXT NOT NULL, created_at INTEGER NOT NULL, initialized_at INTEGER, input_tokens INTEGER, output_tokens INTEGER);
                CREATE TABLE IF NOT EXISTS workspace_agent_instances (id TEXT PRIMARY KEY, agent_id TEXT NOT NULL REFERENCES workspace_agents(id), opencode_session_id TEXT, created_at INTEGER NOT NULL);
                 CREATE TABLE IF NOT EXISTS workspace_conversation_agents (agent_id TEXT NOT NULL REFERENCES workspace_agents(id), channel_id TEXT REFERENCES workspace_channels(id), member_pubkey TEXT, peer_pubkey TEXT,
                    folder_scope_json TEXT NOT NULL DEFAULT '[]',
                    PRIMARY KEY (agent_id, channel_id, member_pubkey, peer_pubkey),
                    CHECK ((channel_id IS NOT NULL AND member_pubkey IS NULL AND peer_pubkey IS NULL) OR (channel_id IS NULL AND member_pubkey IS NOT NULL AND peer_pubkey IS NOT NULL)));
                 CREATE TABLE IF NOT EXISTS workspace_conversation_preprompts (channel_id TEXT REFERENCES workspace_channels(id), member_pubkey TEXT, peer_pubkey TEXT, preprompt TEXT NOT NULL,
                    PRIMARY KEY (channel_id, member_pubkey, peer_pubkey),
                    CHECK ((channel_id IS NOT NULL AND member_pubkey IS NULL AND peer_pubkey IS NULL) OR (channel_id IS NULL AND member_pubkey IS NOT NULL AND peer_pubkey IS NOT NULL)));
                CREATE INDEX IF NOT EXISTS workspace_messages_channel ON workspace_messages(channel_id, created_at);
                CREATE INDEX IF NOT EXISTS workspace_messages_direct ON workspace_messages(recipient_pubkey, sender_pubkey, created_at);",
        )?;
        Self::migrate(conn)
    }

    /// Opens an already initialized workspace for a queued agent turn.
    pub fn open_existing(path: &Path) -> Result<Self> {
        Ok(Self {
            conn: Self::open_connection(path)?,
        })
    }

    fn open_connection(path: &Path) -> Result<Connection> {
        let conn = Connection::open(path)
            .with_context(|| format!("failed to open workspace store `{}`", path.display()))?;
        // Queue workers open their own connections. Wait briefly for a concurrent
        // writer instead of failing a turn with SQLite's immediate busy error.
        conn.busy_timeout(Duration::from_secs(5))?;
        conn.execute_batch("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;")?;
        Ok(conn)
    }

    fn migrate(conn: Connection) -> Result<Self> {
        let has_display_name = conn
            .prepare("PRAGMA table_info(workspace_members)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?
            .iter()
            .any(|column| column == "display_name");
        if !has_display_name {
            conn.execute(
                "ALTER TABLE workspace_members ADD COLUMN display_name TEXT NOT NULL DEFAULT ''",
                [],
            )?;
        }
        let has_admin_role = conn
            .prepare("PRAGMA table_info(workspace_members)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?
            .iter()
            .any(|column| column == "is_admin");
        if !has_admin_role {
            conn.execute(
                "ALTER TABLE workspace_members ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0",
                [],
            )?;
        }
        let has_attachments = conn
            .prepare("PRAGMA table_info(workspace_messages)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?
            .iter()
            .any(|column| column == "attachments_json");
        if !has_attachments {
            conn.execute(
                "ALTER TABLE workspace_messages ADD COLUMN attachments_json TEXT NOT NULL DEFAULT '[]'",
                [],
            )?;
        }
        let has_mentions = conn
            .prepare("PRAGMA table_info(workspace_messages)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?
            .iter()
            .any(|column| column == "mentions_json");
        if !has_mentions {
            conn.execute(
                "ALTER TABLE workspace_messages ADD COLUMN mentions_json TEXT NOT NULL DEFAULT '[]'",
                [],
            )?;
        }
        let has_also_send_to_main = conn
            .prepare("PRAGMA table_info(workspace_messages)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?
            .iter()
            .any(|column| column == "also_send_to_main");
        if !has_also_send_to_main {
            conn.execute(
                "ALTER TABLE workspace_messages ADD COLUMN also_send_to_main INTEGER NOT NULL DEFAULT 0",
                [],
            )?;
        }
        let agent_columns = conn
            .prepare("PRAGMA table_info(workspace_agents)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        if !agent_columns
            .iter()
            .any(|column| column == "session_status")
        {
            conn.execute(
                "ALTER TABLE workspace_agents ADD COLUMN session_status TEXT NOT NULL DEFAULT 'failed'",
                [],
            )?;
            conn.execute(
                "UPDATE workspace_agents SET session_status = 'ready' WHERE opencode_session_id IS NOT NULL AND opencode_session_id != ''",
                [],
            )?;
        }
        if !agent_columns.iter().any(|column| column == "session_error") {
            conn.execute(
                "ALTER TABLE workspace_agents ADD COLUMN session_error TEXT",
                [],
            )?;
        }
        for (column, definition) in [
            ("opencode_provider_id", "TEXT"),
            ("opencode_provider_name", "TEXT"),
            ("opencode_model_id", "TEXT"),
            ("opencode_model_name", "TEXT"),
            ("opencode_agent", "TEXT"),
            ("workdir", "TEXT"),
            ("initialized_at", "INTEGER"),
            ("input_tokens", "INTEGER"),
            ("output_tokens", "INTEGER"),
            ("restart_on_failure", "INTEGER NOT NULL DEFAULT 1"),
        ] {
            if !agent_columns.iter().any(|existing| existing == column) {
                conn.execute(
                    &format!("ALTER TABLE workspace_agents ADD COLUMN {column} {definition}"),
                    [],
                )?;
            }
        }
        let conversation_agent_columns = conn
            .prepare("PRAGMA table_info(workspace_conversation_agents)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        if !conversation_agent_columns
            .iter()
            .any(|column| column == "folder_scope_json")
        {
            conn.execute(
                "ALTER TABLE workspace_conversation_agents ADD COLUMN folder_scope_json TEXT NOT NULL DEFAULT '[]'",
                [],
            )?;
        }
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS workspace_metadata (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
             INSERT OR IGNORE INTO workspace_metadata (key, value) VALUES ('revision', 0);
             CREATE TRIGGER IF NOT EXISTS workspace_members_revision_insert AFTER INSERT ON workspace_members BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_members_revision_update AFTER UPDATE ON workspace_members BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_channels_revision_insert AFTER INSERT ON workspace_channels BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_channels_revision_update AFTER UPDATE ON workspace_channels BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_channels_revision_delete AFTER DELETE ON workspace_channels BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_messages_revision_insert AFTER INSERT ON workspace_messages BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_messages_revision_update AFTER UPDATE ON workspace_messages BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_messages_revision_delete AFTER DELETE ON workspace_messages BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_message_reactions_revision_insert AFTER INSERT ON workspace_message_reactions BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_message_reactions_revision_delete AFTER DELETE ON workspace_message_reactions BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_agents_revision_insert AFTER INSERT ON workspace_agents BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_agents_revision_update AFTER UPDATE ON workspace_agents BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_agents_revision_delete AFTER DELETE ON workspace_agents BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_agent_instances_revision_insert AFTER INSERT ON workspace_agent_instances BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_agent_instances_revision_update AFTER UPDATE ON workspace_agent_instances BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_agent_instances_revision_delete AFTER DELETE ON workspace_agent_instances BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_conversation_agents_revision_insert AFTER INSERT ON workspace_conversation_agents BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_conversation_agents_revision_update AFTER UPDATE ON workspace_conversation_agents BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_conversation_agents_revision_delete AFTER DELETE ON workspace_conversation_agents BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_conversation_preprompts_revision_insert AFTER INSERT ON workspace_conversation_preprompts BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_conversation_preprompts_revision_update AFTER UPDATE ON workspace_conversation_preprompts BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_conversation_preprompts_revision_delete AFTER DELETE ON workspace_conversation_preprompts BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;",
        )?;
        Ok(Self { conn })
    }

    pub fn revision(&self) -> Result<u64> {
        let revision: i64 = self.conn.query_row(
            "SELECT value FROM workspace_metadata WHERE key = 'revision'",
            [],
            |row| row.get(0),
        )?;
        u64::try_from(revision).context("workspace revision is invalid")
    }

    pub fn add_member(&self, pubkey: &str) -> Result<()> {
        let pubkey = required("member pubkey", pubkey)?;
        self.conn.execute(
            "INSERT OR IGNORE INTO workspace_members (pubkey, joined_at) VALUES (?1, ?2)",
            params![pubkey, now()],
        )?;
        Ok(())
    }

    pub fn queue_notification(&self, recipient: &str, payload: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO workspace_notification_outbox (recipient, payload, created_at) VALUES (?1, ?2, ?3)",
            params![required("notification recipient", recipient)?, payload, now()],
        )?;
        Ok(())
    }

    pub fn pending_notifications(&self) -> Result<Vec<WorkspaceNotification>> {
        Ok(self.conn.prepare("SELECT id, recipient, payload, attempts FROM workspace_notification_outbox ORDER BY id")?
            .query_map([], |row| Ok(WorkspaceNotification { id: row.get(0)?, recipient: row.get(1)?, payload: row.get(2)?, attempts: row.get(3)? }))?
            .collect::<rusqlite::Result<Vec<_>>>()?)
    }

    pub fn delivered_notification(&self, id: i64) -> Result<()> {
        self.conn.execute(
            "DELETE FROM workspace_notification_outbox WHERE id = ?1",
            [id],
        )?;
        Ok(())
    }

    pub fn failed_notification_attempt(&self, id: i64) -> Result<()> {
        self.conn.execute(
            "UPDATE workspace_notification_outbox SET attempts = attempts + 1 WHERE id = ?1",
            [id],
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

    pub fn is_admin(&self, pubkey: &str) -> Result<bool> {
        Ok(self.conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM workspace_members WHERE pubkey = ?1 AND is_admin = 1)",
            [pubkey.trim()],
            |row| row.get(0),
        )?)
    }

    pub fn members(&self) -> Result<Vec<WorkspaceMember>> {
        let mut statement = self.conn.prepare(
            "SELECT pubkey, display_name, is_admin FROM workspace_members ORDER BY joined_at, pubkey",
        )?;
        let members = statement
            .query_map([], |row| {
                Ok(WorkspaceMember {
                    pubkey: row.get(0)?,
                    display_name: row.get(1)?,
                    is_admin: row.get(2)?,
                })
            })?
            .collect::<rusqlite::Result<_>>()
            .map_err(Into::into);
        members
    }

    pub fn set_member_display_name(
        &self,
        pubkey: &str,
        display_name: &str,
    ) -> Result<WorkspaceMember> {
        let pubkey = required("member pubkey", pubkey)?;
        let display_name = display_name.trim();
        if display_name.len() > 100 {
            bail!("display name may not exceed 100 characters");
        }
        if self.conn.execute(
            "UPDATE workspace_members SET display_name = ?2 WHERE pubkey = ?1",
            params![pubkey, display_name],
        )? == 0
        {
            bail!("member is not a workspace member");
        }
        let is_admin = self.is_admin(&pubkey)?;
        Ok(WorkspaceMember {
            pubkey,
            display_name: display_name.to_string(),
            is_admin,
        })
    }

    pub fn set_member_admin(&self, pubkey: &str, is_admin: bool) -> Result<WorkspaceMember> {
        let pubkey = required("member pubkey", pubkey)?;
        if self.conn.execute(
            "UPDATE workspace_members SET is_admin = ?2 WHERE pubkey = ?1",
            params![pubkey, is_admin],
        )? == 0
        {
            bail!("member is not a workspace member");
        }
        let display_name = self.conn.query_row(
            "SELECT display_name FROM workspace_members WHERE pubkey = ?1",
            [&pubkey],
            |row| row.get(0),
        )?;
        Ok(WorkspaceMember {
            pubkey,
            display_name,
            is_admin,
        })
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

    pub fn rename_channel(&self, channel_id: &str, name: &str) -> Result<WorkspaceChannel> {
        let name = required("channel name", name)?.to_ascii_lowercase();
        if !name
            .chars()
            .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '-')
        {
            bail!("channel name may contain lowercase letters, numbers, and hyphens only");
        }
        if self.conn.execute(
            "UPDATE workspace_channels SET name = ?2 WHERE id = ?1",
            params![required("channel id", channel_id)?, name],
        )? == 0
        {
            bail!("channel does not exist");
        }
        self.conn
            .query_row(
                "SELECT id, name, created_by, created_at FROM workspace_channels WHERE id = ?1",
                [channel_id],
                channel_from_row,
            )
            .map_err(Into::into)
    }

    pub fn delete_channel(&self, channel_id: &str) -> Result<()> {
        self.require_channel(channel_id)?;
        self.conn.execute(
            "DELETE FROM workspace_message_reactions WHERE message_id IN (SELECT id FROM workspace_messages WHERE channel_id = ?1)",
            [channel_id],
        )?;
        self.conn.execute(
            "DELETE FROM workspace_messages WHERE channel_id = ?1",
            [channel_id],
        )?;
        self.conn.execute(
            "DELETE FROM workspace_conversation_agents WHERE channel_id = ?1",
            [channel_id],
        )?;
        self.conn.execute(
            "DELETE FROM workspace_conversation_preprompts WHERE channel_id = ?1",
            [channel_id],
        )?;
        self.conn
            .execute("DELETE FROM workspace_channels WHERE id = ?1", [channel_id])?;
        Ok(())
    }

    pub fn delete_direct_conversation(&self, member: &str, peer: &str) -> Result<()> {
        let (member, peer) = direct_participants(member, peer)?;
        self.conn.execute(
            "DELETE FROM workspace_message_reactions WHERE message_id IN (SELECT id FROM workspace_messages WHERE channel_id IS NULL AND ((sender_pubkey = ?1 AND recipient_pubkey = ?2) OR (sender_pubkey = ?2 AND recipient_pubkey = ?1)))",
            params![member, peer],
        )?;
        self.conn.execute(
            "DELETE FROM workspace_messages WHERE channel_id IS NULL AND ((sender_pubkey = ?1 AND recipient_pubkey = ?2) OR (sender_pubkey = ?2 AND recipient_pubkey = ?1))",
            params![member, peer],
        )?;
        self.conn.execute("DELETE FROM workspace_conversation_agents WHERE member_pubkey = ?1 AND peer_pubkey = ?2", params![member, peer])?;
        self.conn.execute("DELETE FROM workspace_conversation_preprompts WHERE member_pubkey = ?1 AND peer_pubkey = ?2", params![member, peer])?;
        Ok(())
    }

    pub fn has_channel(&self, channel_id: &str) -> Result<bool> {
        Ok(self.conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM workspace_channels WHERE id = ?1)",
            [channel_id.trim()],
            |row| row.get(0),
        )?)
    }

    pub fn create_agent(
        &self,
        name: &str,
        role: &str,
        traits: &str,
        skills: &[String],
        preset: Option<&str>,
        opencode_session_id: Option<&str>,
        session_status: &str,
        session_error: Option<&str>,
        created_by: &str,
    ) -> Result<WorkspaceAgent> {
        self.create_agent_with_profile(
            name,
            role,
            traits,
            skills,
            preset,
            WorkspaceAgentOpenCodeProfile::default(),
            opencode_session_id,
            session_status,
            session_error,
            created_by,
        )
    }

    pub fn create_agent_with_profile(
        &self,
        name: &str,
        role: &str,
        traits: &str,
        skills: &[String],
        preset: Option<&str>,
        profile: WorkspaceAgentOpenCodeProfile,
        opencode_session_id: Option<&str>,
        session_status: &str,
        session_error: Option<&str>,
        created_by: &str,
    ) -> Result<WorkspaceAgent> {
        let name = required("agent name", name)?;
        let role = required("agent role", role)?;
        if name.len() > 100 || role.len() > 500 || traits.trim().len() > 1000 {
            bail!("agent details are too long");
        }
        if skills.len() > 8
            || skills
                .iter()
                .any(|skill| skill.trim().is_empty() || skill.len() > 80)
        {
            bail!("agents may have up to 8 named skills");
        }
        let agent = WorkspaceAgent {
            id: new_id(),
            name,
            role,
            traits: traits.trim().to_string(),
            skills: skills
                .iter()
                .map(|skill| skill.trim().to_string())
                .collect(),
            preset: preset.and_then(|value| non_empty(value)),
            opencode_provider_id: profile.provider_id.and_then(|value| non_empty(&value)),
            opencode_provider_name: profile.provider_name.and_then(|value| non_empty(&value)),
            opencode_model_id: profile.model_id.and_then(|value| non_empty(&value)),
            opencode_model_name: profile.model_name.and_then(|value| non_empty(&value)),
            opencode_agent: profile.agent.and_then(|value| non_empty(&value)),
            workdir: profile.workdir.and_then(|value| non_empty(&value)),
            restart_on_failure: profile.restart_on_failure,
            opencode_session_id: opencode_session_id.and_then(|value| non_empty(value)),
            session_status: required("agent session status", session_status)?,
            session_error: session_error.and_then(|value| non_empty(value)),
            instance_id: new_id(),
            created_by: required("creator", created_by)?,
            created_at: now(),
            initialized_at: (session_status == "ready" && opencode_session_id.is_some()).then(now),
            input_tokens: None,
            output_tokens: None,
        };
        self.conn.execute("INSERT INTO workspace_agents (id, name, role, traits, skills_json, preset, opencode_provider_id, opencode_provider_name, opencode_model_id, opencode_model_name, opencode_agent, workdir, restart_on_failure, opencode_session_id, session_status, session_error, created_by, created_at, initialized_at, input_tokens, output_tokens) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21)", params![agent.id, agent.name, agent.role, agent.traits, serde_json::to_string(&agent.skills)?, agent.preset, agent.opencode_provider_id, agent.opencode_provider_name, agent.opencode_model_id, agent.opencode_model_name, agent.opencode_agent, agent.workdir, agent.restart_on_failure, agent.opencode_session_id, agent.session_status, agent.session_error, agent.created_by, agent.created_at, agent.initialized_at, agent.input_tokens, agent.output_tokens])?;
        self.conn.execute("INSERT INTO workspace_agent_instances (id, agent_id, opencode_session_id, created_at) VALUES (?1, ?2, ?3, ?4)", params![agent.instance_id, agent.id, agent.opencode_session_id, agent.created_at])?;
        Ok(agent)
    }

    pub fn agents(&self) -> Result<Vec<WorkspaceAgent>> {
        let mut statement = self.conn.prepare("SELECT a.id, a.name, a.role, a.traits, a.skills_json, a.preset, a.opencode_provider_id, a.opencode_provider_name, a.opencode_model_id, a.opencode_model_name, a.opencode_agent, a.workdir, a.restart_on_failure, i.opencode_session_id, a.session_status, a.session_error, i.id, a.created_by, a.created_at, a.initialized_at, a.input_tokens, a.output_tokens FROM workspace_agents a JOIN workspace_agent_instances i ON i.agent_id = a.id ORDER BY a.created_at, a.name")?;
        let agents = statement
            .query_map([], |row| {
                Ok(WorkspaceAgent {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    role: row.get(2)?,
                    traits: row.get(3)?,
                    skills: serde_json::from_str(&row.get::<_, String>(4)?).unwrap_or_default(),
                    preset: row.get(5)?,
                    opencode_provider_id: row.get(6)?,
                    opencode_provider_name: row.get(7)?,
                    opencode_model_id: row.get(8)?,
                    opencode_model_name: row.get(9)?,
                    opencode_agent: row.get(10)?,
                    workdir: row.get(11)?,
                    restart_on_failure: row.get(12)?,
                    opencode_session_id: row.get(13)?,
                    session_status: row.get(14)?,
                    session_error: row.get(15)?,
                    instance_id: row.get(16)?,
                    created_by: row.get(17)?,
                    created_at: row.get(18)?,
                    initialized_at: row.get(19)?,
                    input_tokens: row.get(20)?,
                    output_tokens: row.get(21)?,
                })
            })?
            .collect::<rusqlite::Result<_>>()?;
        Ok(agents)
    }

    pub fn update_agent_session(
        &self,
        agent_id: &str,
        opencode_session_id: Option<&str>,
        session_status: &str,
        session_error: Option<&str>,
    ) -> Result<WorkspaceAgent> {
        let agent_id = required("agent id", agent_id)?;
        if self.conn.execute(
            "UPDATE workspace_agents SET session_status = ?2, session_error = ?3, initialized_at = CASE WHEN initialized_at IS NULL AND ?4 = 'ready' AND ?5 IS NOT NULL THEN ?6 ELSE initialized_at END WHERE id = ?1",
            params![
                agent_id,
                required("agent session status", session_status)?,
                session_error.and_then(non_empty),
                session_status,
                opencode_session_id.and_then(non_empty),
                now(),
            ],
        )? == 0
        {
            bail!("agent does not exist");
        }
        self.conn.execute(
            "UPDATE workspace_agent_instances SET opencode_session_id = ?2 WHERE agent_id = ?1",
            params![agent_id, opencode_session_id.and_then(non_empty)],
        )?;
        self.agents()?
            .into_iter()
            .find(|agent| agent.id == agent_id)
            .context("updated agent instance is missing")
    }

    pub fn record_agent_token_usage(
        &self,
        agent_id: &str,
        input_tokens: u64,
        output_tokens: u64,
    ) -> Result<WorkspaceAgent> {
        let input_tokens = i64::try_from(input_tokens).context("input token count is too large")?;
        let output_tokens =
            i64::try_from(output_tokens).context("output token count is too large")?;
        if self.conn.execute(
            "UPDATE workspace_agents SET input_tokens = COALESCE(input_tokens, 0) + ?2, output_tokens = COALESCE(output_tokens, 0) + ?3 WHERE id = ?1",
            params![required("agent id", agent_id)?, input_tokens, output_tokens],
        )? == 0 {
            bail!("agent does not exist");
        }
        self.agents()?
            .into_iter()
            .find(|agent| agent.id == agent_id)
            .context("updated agent is missing")
    }

    pub fn update_agent_profile_and_session(
        &self,
        agent_id: &str,
        profile: WorkspaceAgentOpenCodeProfile,
        opencode_session_id: Option<&str>,
        session_status: &str,
        session_error: Option<&str>,
    ) -> Result<WorkspaceAgent> {
        let agent_id = required("agent id", agent_id)?;
        if self.conn.execute(
            "UPDATE workspace_agents SET opencode_provider_id = ?2, opencode_provider_name = ?3, opencode_model_id = ?4, opencode_model_name = ?5, opencode_agent = ?6, workdir = ?7, restart_on_failure = ?8, session_status = ?9, session_error = ?10, initialized_at = CASE WHEN initialized_at IS NULL AND ?9 = 'ready' AND ?11 IS NOT NULL THEN ?12 ELSE initialized_at END WHERE id = ?1",
            params![agent_id, profile.provider_id.and_then(|value| non_empty(&value)), profile.provider_name.and_then(|value| non_empty(&value)), profile.model_id.and_then(|value| non_empty(&value)), profile.model_name.and_then(|value| non_empty(&value)), profile.agent.and_then(|value| non_empty(&value)), profile.workdir.and_then(|value| non_empty(&value)), profile.restart_on_failure, required("agent session status", session_status)?, session_error.and_then(non_empty), opencode_session_id.and_then(non_empty), now()],
        )? == 0 {
            bail!("agent does not exist");
        }
        self.conn.execute(
            "UPDATE workspace_agent_instances SET opencode_session_id = ?2 WHERE agent_id = ?1",
            params![agent_id, opencode_session_id.and_then(non_empty)],
        )?;
        self.agents()?
            .into_iter()
            .find(|agent| agent.id == agent_id)
            .context("updated agent instance is missing")
    }

    pub fn rename_agent(&self, agent_id: &str, name: &str) -> Result<WorkspaceAgent> {
        let agent_id = required("agent id", agent_id)?;
        let name = required("agent name", name)?;
        if name.len() > 100 {
            bail!("agent name may not exceed 100 characters");
        }
        if self.conn.execute(
            "UPDATE workspace_agents SET name = ?2 WHERE id = ?1",
            params![agent_id, name],
        )? == 0
        {
            bail!("agent does not exist");
        }
        self.agents()?
            .into_iter()
            .find(|agent| agent.id == agent_id)
            .context("renamed agent instance is missing")
    }

    pub fn delete_agent(&self, agent_id: &str) -> Result<()> {
        let agent_id = required("agent id", agent_id)?;
        let transaction = self.conn.unchecked_transaction()?;
        if !transaction.query_row(
            "SELECT EXISTS(SELECT 1 FROM workspace_agents WHERE id = ?1)",
            [&agent_id],
            |row| row.get::<_, bool>(0),
        )? {
            bail!("agent does not exist");
        }
        transaction.execute(
            "DELETE FROM workspace_conversation_agents WHERE agent_id = ?1",
            [&agent_id],
        )?;
        transaction.execute(
            "DELETE FROM workspace_agent_instances WHERE agent_id = ?1",
            [&agent_id],
        )?;
        transaction.execute("DELETE FROM workspace_agents WHERE id = ?1", [&agent_id])?;
        transaction.commit()?;
        Ok(())
    }

    pub fn conversation_agents(&self) -> Result<Vec<WorkspaceConversationAgent>> {
        let mut statement = self.conn.prepare("SELECT agent_id, channel_id, member_pubkey, peer_pubkey, folder_scope_json FROM workspace_conversation_agents ORDER BY agent_id")?;
        let memberships = statement
            .query_map([], conversation_agent_from_row)?
            .collect::<rusqlite::Result<_>>()?;
        Ok(memberships)
    }

    pub fn conversation_preprompts(&self) -> Result<Vec<WorkspaceConversationPreprompt>> {
        let mut statement = self.conn.prepare("SELECT channel_id, member_pubkey, peer_pubkey, preprompt FROM workspace_conversation_preprompts ORDER BY channel_id, member_pubkey, peer_pubkey")?;
        let preprompts = statement
            .query_map([], conversation_preprompt_from_row)?
            .collect::<rusqlite::Result<_>>()?;
        Ok(preprompts)
    }

    pub fn set_conversation_preprompt(
        &self,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
        preprompt: &str,
    ) -> Result<()> {
        if preprompt.chars().count() > 4_000 {
            bail!("conversation pre-prompt may not exceed 4000 characters");
        }
        let (channel_id, member, peer) = match (channel_id, member, peer) {
            (Some(channel_id), None, None) => {
                self.require_channel(channel_id)?;
                (Some(channel_id.to_string()), None, None)
            }
            (None, Some(member), Some(peer)) => {
                let (member, peer) = direct_participants(member, peer)?;
                if !self.is_member(&member)? || !self.is_member(&peer)? {
                    bail!("direct conversation participant is not a workspace member");
                }
                (None, Some(member), Some(peer))
            }
            _ => bail!("conversation must be a channel or a direct message"),
        };
        let preprompt = preprompt.trim();
        self.conn.execute("DELETE FROM workspace_conversation_preprompts WHERE channel_id IS ?1 AND member_pubkey IS ?2 AND peer_pubkey IS ?3", params![channel_id, member, peer])?;
        if !preprompt.is_empty() {
            self.conn.execute("INSERT INTO workspace_conversation_preprompts (channel_id, member_pubkey, peer_pubkey, preprompt) VALUES (?1, ?2, ?3, ?4)", params![channel_id, member, peer, preprompt])?;
        }
        Ok(())
    }

    pub fn add_conversation_agent(
        &self,
        agent_id: &str,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
        folder_scope: &[String],
    ) -> Result<()> {
        let agent_id = required("agent id", agent_id)?;
        if !self.conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM workspace_agents WHERE id = ?1)",
            [&agent_id],
            |row| row.get::<_, bool>(0),
        )? {
            bail!("agent does not exist");
        }
        let (channel_id, member, peer) = match (channel_id, member, peer) {
            (Some(channel_id), None, None) => {
                self.require_channel(channel_id)?;
                (Some(channel_id.to_string()), None, None)
            }
            (None, Some(member), Some(peer)) => {
                let (member, peer) = direct_participants(member, peer)?;
                if !self.is_member(&member)? || !self.is_member(&peer)? {
                    bail!("direct conversation participant is not a workspace member");
                }
                (None, Some(member), Some(peer))
            }
            _ => bail!("conversation must be a channel or a direct message"),
        };
        self.conn.execute("INSERT INTO workspace_conversation_agents (agent_id, channel_id, member_pubkey, peer_pubkey, folder_scope_json) VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT(agent_id, channel_id, member_pubkey, peer_pubkey) DO UPDATE SET folder_scope_json = excluded.folder_scope_json", params![agent_id, channel_id, member, peer, serde_json::to_string(folder_scope)?])?;
        Ok(())
    }

    pub fn remove_conversation_agent(
        &self,
        agent_id: &str,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
    ) -> Result<()> {
        let agent_id = required("agent id", agent_id)?;
        let (channel_id, member, peer) = match (channel_id, member, peer) {
            (Some(channel_id), None, None) => (Some(channel_id.to_string()), None, None),
            (None, Some(member), Some(peer)) => {
                let (member, peer) = direct_participants(member, peer)?;
                (None, Some(member), Some(peer))
            }
            _ => bail!("conversation must be a channel or a direct message"),
        };
        self.conn.execute("DELETE FROM workspace_conversation_agents WHERE agent_id = ?1 AND channel_id IS ?2 AND member_pubkey IS ?3 AND peer_pubkey IS ?4", params![agent_id, channel_id, member, peer])?;
        Ok(())
    }

    pub fn agents_for_conversation(
        &self,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
    ) -> Result<Vec<WorkspaceAgent>> {
        let ids = if let Some(channel_id) = channel_id {
            self.conn
                .prepare(
                    "SELECT agent_id FROM workspace_conversation_agents WHERE channel_id = ?1",
                )?
                .query_map([channel_id], |row| row.get::<_, String>(0))?
                .collect::<rusqlite::Result<Vec<_>>>()?
        } else {
            let (member, peer) =
                direct_participants(member.unwrap_or_default(), peer.unwrap_or_default())?;
            self.conn.prepare("SELECT agent_id FROM workspace_conversation_agents WHERE member_pubkey = ?1 AND peer_pubkey = ?2")?.query_map(params![member, peer], |row| row.get::<_, String>(0))?.collect::<rusqlite::Result<Vec<_>>>()?
        };
        let agents = self.agents()?;
        Ok(agents
            .into_iter()
            .filter(|agent| ids.contains(&agent.id))
            .collect())
    }

    pub fn add_channel_message(
        &self,
        sender: &str,
        channel_id: &str,
        body: &str,
        attachments: &[MediaReference],
        mentions: &[WorkspaceMentionPayload],
        parent_id: Option<&str>,
    ) -> Result<WorkspaceMessage> {
        self.add_channel_message_with_main(
            sender,
            channel_id,
            body,
            attachments,
            mentions,
            parent_id,
            false,
        )
    }

    pub fn add_channel_message_with_main(
        &self,
        sender: &str,
        channel_id: &str,
        body: &str,
        attachments: &[MediaReference],
        mentions: &[WorkspaceMentionPayload],
        parent_id: Option<&str>,
        also_send_to_main: bool,
    ) -> Result<WorkspaceMessage> {
        self.add_channel_message_with_main_and_id(
            sender,
            channel_id,
            body,
            attachments,
            mentions,
            parent_id,
            also_send_to_main,
            None,
        )
    }

    pub fn add_channel_message_with_main_and_id(
        &self,
        sender: &str,
        channel_id: &str,
        body: &str,
        attachments: &[MediaReference],
        mentions: &[WorkspaceMentionPayload],
        parent_id: Option<&str>,
        also_send_to_main: bool,
        message_id: Option<&str>,
    ) -> Result<WorkspaceMessage> {
        self.require_channel(channel_id)?;
        self.add_message(
            sender,
            Some(channel_id),
            None,
            body,
            attachments,
            mentions,
            parent_id,
            also_send_to_main,
            message_id,
        )
    }

    pub fn add_direct_message(
        &self,
        sender: &str,
        recipient: &str,
        body: &str,
        attachments: &[MediaReference],
        mentions: &[WorkspaceMentionPayload],
        parent_id: Option<&str>,
    ) -> Result<WorkspaceMessage> {
        self.add_direct_message_with_main(
            sender,
            recipient,
            body,
            attachments,
            mentions,
            parent_id,
            false,
        )
    }

    pub fn add_direct_message_with_main(
        &self,
        sender: &str,
        recipient: &str,
        body: &str,
        attachments: &[MediaReference],
        mentions: &[WorkspaceMentionPayload],
        parent_id: Option<&str>,
        also_send_to_main: bool,
    ) -> Result<WorkspaceMessage> {
        self.add_direct_message_with_main_and_id(
            sender,
            recipient,
            body,
            attachments,
            mentions,
            parent_id,
            also_send_to_main,
            None,
        )
    }

    pub fn add_direct_message_with_main_and_id(
        &self,
        sender: &str,
        recipient: &str,
        body: &str,
        attachments: &[MediaReference],
        mentions: &[WorkspaceMentionPayload],
        parent_id: Option<&str>,
        also_send_to_main: bool,
        message_id: Option<&str>,
    ) -> Result<WorkspaceMessage> {
        let recipient = required("recipient", recipient)?;
        if !self.is_member(&recipient)? {
            bail!("recipient is not a workspace member");
        }
        self.add_message(
            sender,
            None,
            Some(&recipient),
            body,
            attachments,
            mentions,
            parent_id,
            also_send_to_main,
            message_id,
        )
    }

    fn add_message(
        &self,
        sender: &str,
        channel_id: Option<&str>,
        recipient: Option<&str>,
        body: &str,
        attachments: &[MediaReference],
        mentions: &[WorkspaceMentionPayload],
        parent_id: Option<&str>,
        also_send_to_main: bool,
        message_id: Option<&str>,
    ) -> Result<WorkspaceMessage> {
        let message = WorkspaceMessage {
            id: message_id
                .map(|id| required("message id", id))
                .transpose()?
                .unwrap_or_else(new_id),
            channel_id: channel_id.map(ToOwned::to_owned),
            recipient_pubkey: recipient.map(ToOwned::to_owned),
            sender_pubkey: required("sender", sender)?,
            body: body.trim().to_string(),
            attachments: attachments.to_vec(),
            mentions: mentions.to_vec(),
            parent_id: parent_id.map(|id| required("parent id", id)).transpose()?,
            also_send_to_main,
            reactions: vec![],
            created_at: now(),
        };
        if message.body.is_empty() && message.attachments.is_empty() {
            bail!("message cannot be empty")
        }
        self.validate_mentions(&message.mentions)?;
        if let Some(parent_id) = &message.parent_id {
            self.require_parent(
                parent_id,
                message.channel_id.as_deref(),
                message.recipient_pubkey.as_deref(),
                &message.sender_pubkey,
            )?;
        }
        self.conn.execute("INSERT INTO workspace_messages (id, channel_id, recipient_pubkey, sender_pubkey, body, attachments_json, mentions_json, parent_id, also_send_to_main, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)", params![message.id, message.channel_id, message.recipient_pubkey, message.sender_pubkey, message.body, serde_json::to_string(&message.attachments)?, serde_json::to_string(&message.mentions)?, message.parent_id, message.also_send_to_main, message.created_at])?;
        Ok(message)
    }

    pub fn channel_messages(&self, channel_id: &str) -> Result<Vec<WorkspaceMessage>> {
        self.require_channel(channel_id)?;
        self.messages("channel_id = ?1", [channel_id])
    }

    pub fn direct_messages(&self, member: &str, peer: &str) -> Result<Vec<WorkspaceMessage>> {
        let member = required("member", member)?;
        let peer = required("peer", peer)?;
        self.messages("channel_id IS NULL AND ((sender_pubkey = ?1 AND recipient_pubkey = ?2) OR (sender_pubkey = ?2 AND recipient_pubkey = ?1) OR (recipient_pubkey = ?2 AND substr(sender_pubkey, 7) IN (SELECT agent_id FROM workspace_conversation_agents WHERE member_pubkey = min(?1, ?2) AND peer_pubkey = max(?1, ?2))))", [&member, &peer])
    }

    pub fn snapshot_messages(&self, member: &str) -> Result<Vec<WorkspaceMessage>> {
        let member = required("member pubkey", member)?;
        self.messages(
            "channel_id IS NOT NULL OR sender_pubkey = ?1 OR recipient_pubkey = ?1 OR (sender_pubkey LIKE 'agent:%' AND substr(sender_pubkey, 7) IN (SELECT agent_id FROM workspace_conversation_agents WHERE member_pubkey = ?1 OR peer_pubkey = ?1))",
            [&member],
        )
    }

    pub fn toggle_reaction(
        &self,
        sender: &str,
        message_id: &str,
        emoji: &str,
    ) -> Result<WorkspaceMessage> {
        let sender = required("sender", sender)?;
        let message_id = required("message id", message_id)?;
        let emoji = required("reaction", emoji)?;
        if !self.is_member(&sender)? {
            bail!("sender is not a workspace member");
        }
        if emoji.chars().count() > 16 {
            bail!("reaction is too long");
        }
        let message = self.message(&message_id)?;
        if message.channel_id.is_none()
            && message.sender_pubkey != sender
            && message.recipient_pubkey.as_deref() != Some(sender.as_str())
        {
            bail!("message belongs to another direct conversation");
        }
        let changed = self.conn.execute(
            "DELETE FROM workspace_message_reactions WHERE message_id = ?1 AND emoji = ?2 AND sender_pubkey = ?3",
            params![message_id, emoji, sender],
        )?;
        if changed == 0 {
            self.conn.execute(
                "INSERT INTO workspace_message_reactions (message_id, emoji, sender_pubkey, created_at) VALUES (?1, ?2, ?3, ?4)",
                params![message_id, emoji, sender, now()],
            )?;
        }
        self.message(&message_id)
    }

    fn messages<P: rusqlite::Params>(
        &self,
        predicate: &str,
        params: P,
    ) -> Result<Vec<WorkspaceMessage>> {
        let query = format!("SELECT id, channel_id, recipient_pubkey, sender_pubkey, body, attachments_json, mentions_json, parent_id, also_send_to_main, created_at FROM workspace_messages WHERE {predicate} ORDER BY created_at, id");
        let mut statement = self.conn.prepare(&query)?;
        let mut messages: Vec<WorkspaceMessage> = statement
            .query_map(params, message_from_row)?
            .collect::<rusqlite::Result<_>>()?;
        for message in &mut messages {
            message.reactions = self.reactions_for_message(&message.id)?;
        }
        Ok(messages)
    }

    pub fn message_by_id(&self, id: &str) -> Result<Option<WorkspaceMessage>> {
        let message = self
            .conn
            .query_row("SELECT id, channel_id, recipient_pubkey, sender_pubkey, body, attachments_json, mentions_json, parent_id, also_send_to_main, created_at FROM workspace_messages WHERE id = ?1", [id], message_from_row)
            .optional()?;
        message
            .map(|mut message| {
                message.reactions = self.reactions_for_message(id)?;
                Ok(message)
            })
            .transpose()
    }

    fn message(&self, id: &str) -> Result<WorkspaceMessage> {
        self.message_by_id(id)?
            .context("workspace message is missing")
    }

    fn reactions_for_message(&self, message_id: &str) -> Result<Vec<WorkspaceReactionPayload>> {
        let mut statement = self.conn.prepare("SELECT emoji, sender_pubkey FROM workspace_message_reactions WHERE message_id = ?1 ORDER BY created_at, emoji, sender_pubkey")?;
        let reactions = statement
            .query_map([message_id], |row| {
                Ok(WorkspaceReactionPayload {
                    emoji: row.get(0)?,
                    sender_pubkey: row.get(1)?,
                })
            })?
            .collect::<rusqlite::Result<_>>()?;
        Ok(reactions)
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
    fn validate_mentions(&self, mentions: &[WorkspaceMentionPayload]) -> Result<()> {
        for mention in mentions {
            let exists = match mention.kind.as_str() {
                "member" => self.is_member(&mention.id)?,
                "agent" => self.conn.query_row(
                    "SELECT EXISTS(SELECT 1 FROM workspace_agents WHERE id = ?1)",
                    [&mention.id],
                    |row| row.get::<_, bool>(0),
                )?,
                _ => false,
            };
            if !exists {
                bail!("workspace mention target does not exist");
            }
        }
        Ok(())
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
        attachments: serde_json::from_str(&row.get::<_, String>(5)?).unwrap_or_default(),
        mentions: serde_json::from_str(&row.get::<_, String>(6)?).unwrap_or_default(),
        parent_id: row.get(7)?,
        also_send_to_main: row.get(8)?,
        reactions: Vec::new(),
        created_at: row.get(9)?,
    })
}
fn conversation_agent_from_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<WorkspaceConversationAgent> {
    Ok(WorkspaceConversationAgent {
        agent_id: row.get(0)?,
        channel_id: row.get(1)?,
        member_pubkey: row.get(2)?,
        peer_pubkey: row.get(3)?,
        folder_scope: serde_json::from_str(&row.get::<_, String>(4)?).unwrap_or_default(),
    })
}
fn conversation_preprompt_from_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<WorkspaceConversationPreprompt> {
    Ok(WorkspaceConversationPreprompt {
        channel_id: row.get(0)?,
        member_pubkey: row.get(1)?,
        peer_pubkey: row.get(2)?,
        preprompt: row.get(3)?,
    })
}
fn direct_participants(member: &str, peer: &str) -> Result<(String, String)> {
    let mut participants = [required("member", member)?, required("peer", peer)?];
    participants.sort();
    Ok((participants[0].clone(), participants[1].clone()))
}
fn required(label: &str, value: &str) -> Result<String> {
    let value = value.trim();
    if value.is_empty() {
        bail!("{label} cannot be empty")
    }
    Ok(value.to_string())
}
fn non_empty(value: &str) -> Option<String> {
    (!value.trim().is_empty()).then(|| value.trim().to_string())
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
            .add_channel_message("owner", &channel.id, "hello", &[], &[], None)
            .unwrap();
        store
            .add_channel_message("member", &channel.id, "reply", &[], &[], Some(&parent.id))
            .unwrap();
        drop(store);
        let reopened = WorkspaceStore::open(path.path()).unwrap();
        assert_eq!(reopened.channels().unwrap().len(), 1);
        assert!(reopened
            .channel_messages(&channel.id)
            .unwrap()
            .iter()
            .any(|message| message.parent_id.as_deref() == Some(parent.id.as_str())));
    }

    #[test]
    fn persists_monotonic_workspace_revision() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        let initial = store.revision().unwrap();
        store.add_member("owner").unwrap();
        let after_member = store.revision().unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let after_channel = store.revision().unwrap();
        assert!(after_member > initial);
        assert!(after_channel > after_member);
        drop(store);
        assert_eq!(
            WorkspaceStore::open(path.path())
                .unwrap()
                .revision()
                .unwrap(),
            after_channel
        );
        let _ = channel;
    }

    #[test]
    fn loads_a_message_by_id_or_returns_none() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let message = store
            .add_channel_message("owner", &channel.id, "hello", &[], &[], None)
            .unwrap();

        assert_eq!(store.message_by_id(&message.id).unwrap(), Some(message));
        assert_eq!(store.message_by_id("missing").unwrap(), None);
    }

    #[test]
    fn persists_reactions_and_thread_main_visibility() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let parent = store
            .add_channel_message("owner", &channel.id, "hello", &[], &[], None)
            .unwrap();
        let reply = store
            .add_channel_message_with_main(
                "member",
                &channel.id,
                "also main",
                &[],
                &[],
                Some(&parent.id),
                true,
            )
            .unwrap();
        store.toggle_reaction("member", &parent.id, "👍").unwrap();
        drop(store);

        let messages = WorkspaceStore::open(path.path())
            .unwrap()
            .channel_messages(&channel.id)
            .unwrap();
        let restored_parent = messages
            .iter()
            .find(|message| message.id == parent.id)
            .unwrap();
        let restored_reply = messages
            .iter()
            .find(|message| message.id == reply.id)
            .unwrap();
        assert_eq!(
            restored_parent.reactions,
            vec![WorkspaceReactionPayload {
                emoji: "👍".to_string(),
                sender_pubkey: "member".to_string()
            }]
        );
        assert!(restored_reply.also_send_to_main);
    }

    #[test]
    fn toggling_a_reaction_removes_only_the_senders_reaction() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let message = store
            .add_channel_message("owner", &channel.id, "hello", &[], &[], None)
            .unwrap();
        store.toggle_reaction("owner", &message.id, "👀").unwrap();
        store.toggle_reaction("member", &message.id, "👀").unwrap();
        let updated = store.toggle_reaction("owner", &message.id, "👀").unwrap();
        assert_eq!(
            updated.reactions,
            vec![WorkspaceReactionPayload {
                emoji: "👀".to_string(),
                sender_pubkey: "member".to_string()
            }]
        );
    }

    #[test]
    fn persists_attachment_only_messages() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let attachment = MediaReference {
            url: "https://cdn.example/report".to_string(),
            sha256: "a".repeat(64),
            size: 4,
            media_type: "application/pdf".to_string(),
            name: Some("report.pdf".to_string()),
            encryption: None,
        };

        let message = store
            .add_channel_message("owner", &channel.id, "", &[attachment.clone()], &[], None)
            .unwrap();
        let restored = store.channel_messages(&channel.id).unwrap();

        assert_eq!(restored, vec![message]);
        assert_eq!(restored[0].attachments, vec![attachment]);
    }

    #[test]
    fn snapshot_includes_channels_and_only_member_direct_messages() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        store.add_member("other").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let channel_message = store
            .add_channel_message("owner", &channel.id, "team", &[], &[], None)
            .unwrap();
        let member_message = store
            .add_direct_message("owner", "member", "private", &[], &[], None)
            .unwrap();
        store
            .add_direct_message("owner", "other", "not for member", &[], &[], None)
            .unwrap();

        let messages = store.snapshot_messages("member").unwrap();
        assert!(messages
            .iter()
            .any(|message| message.id == channel_message.id));
        assert!(messages
            .iter()
            .any(|message| message.id == member_message.id));
        assert_eq!(messages.len(), 2);
    }
    #[test]
    fn rejects_unrelated_direct_thread_and_non_members() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        assert!(store
            .add_direct_message("owner", "outsider", "no", &[], &[], None)
            .is_err());
        let message = store
            .add_direct_message("owner", "member", "hi", &[], &[], None)
            .unwrap();
        assert!(store
            .add_direct_message("owner", "member", "bad", &[], &[], Some("unknown"))
            .is_err());
        assert_eq!(
            store.direct_messages("owner", "member").unwrap()[0].id,
            message.id
        );
    }

    #[test]
    fn persists_member_display_names() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("member").unwrap();
        store.set_member_display_name("member", "Ada").unwrap();
        drop(store);

        let reopened = WorkspaceStore::open(path.path()).unwrap();
        assert_eq!(
            reopened.members().unwrap(),
            vec![WorkspaceMember {
                pubkey: "member".to_string(),
                display_name: "Ada".to_string(),
                is_admin: false,
            }]
        );
    }

    #[test]
    fn persists_agents_and_session_association() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        let agent = store
            .create_agent(
                "Scout",
                "Researcher",
                "Careful",
                &["Web research".to_string()],
                Some("researcher"),
                Some("ses_1"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        drop(store);
        let agents = WorkspaceStore::open(path.path()).unwrap().agents().unwrap();
        assert_eq!(agents, vec![agent]);
    }

    #[test]
    fn records_initialized_time_and_reliable_token_usage() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        let agent = store
            .create_agent(
                "Scout",
                "Researcher",
                "",
                &[],
                None,
                Some("ses_1"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        assert!(agent.initialized_at.is_some());
        assert_eq!(agent.input_tokens, None);

        let updated = store.record_agent_token_usage(&agent.id, 12, 3).unwrap();
        assert_eq!(updated.input_tokens, Some(12));
        assert_eq!(updated.output_tokens, Some(3));
    }

    #[test]
    fn persists_mentions_and_renamed_agents() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let agent = store
            .create_agent(
                "Scout",
                "Researcher",
                "",
                &[],
                None,
                None,
                "failed",
                None,
                "owner",
            )
            .unwrap();
        let mentions = vec![WorkspaceMentionPayload {
            kind: "agent".to_string(),
            id: agent.id.clone(),
            label: "Scout".to_string(),
        }];
        store
            .add_channel_message(
                "owner",
                &channel.id,
                "@[Scout](agent:agent-1)",
                &[],
                &mentions,
                None,
            )
            .unwrap();
        let renamed = store.rename_agent(&agent.id, "Navigator").unwrap();
        drop(store);

        let reopened = WorkspaceStore::open(path.path()).unwrap();
        assert_eq!(reopened.agents().unwrap(), vec![renamed]);
        assert_eq!(
            reopened.channel_messages(&channel.id).unwrap()[0].mentions,
            mentions
        );
    }

    #[test]
    fn persists_channel_and_direct_agent_membership() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let agent = store
            .create_agent(
                "Scout",
                "Researcher",
                "",
                &[],
                None,
                Some("ses_1"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        store
            .add_conversation_agent(&agent.id, Some(&channel.id), None, None, &[])
            .unwrap();
        store
            .add_conversation_agent(&agent.id, None, Some("member"), Some("owner"), &[])
            .unwrap();
        drop(store);
        let store = WorkspaceStore::open(path.path()).unwrap();
        assert_eq!(store.conversation_agents().unwrap().len(), 2);
        assert_eq!(
            store
                .agents_for_conversation(Some(&channel.id), None, None)
                .unwrap(),
            vec![agent]
        );
    }

    #[test]
    fn persists_folder_scope_per_conversation_agent() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let agent = store
            .create_agent(
                "Scout",
                "Researcher",
                "",
                &[],
                None,
                Some("ses_1"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        let scope = vec!["/work/monorepo".to_string(), "/work/tools".to_string()];
        store
            .add_conversation_agent(&agent.id, Some(&channel.id), None, None, &scope)
            .unwrap();
        drop(store);

        let memberships = WorkspaceStore::open(path.path())
            .unwrap()
            .conversation_agents()
            .unwrap();
        assert_eq!(memberships[0].folder_scope, scope);
    }

    #[test]
    fn persists_channel_and_direct_conversation_preprompts() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        store
            .set_conversation_preprompt(Some(&channel.id), None, None, "Review carefully.")
            .unwrap();
        store
            .set_conversation_preprompt(None, Some("member"), Some("owner"), "Be concise.")
            .unwrap();
        drop(store);

        let mut preprompts = WorkspaceStore::open(path.path())
            .unwrap()
            .conversation_preprompts()
            .unwrap();
        preprompts.sort_by(|left, right| left.preprompt.cmp(&right.preprompt));
        assert_eq!(preprompts[0].preprompt, "Be concise.");
        assert_eq!(preprompts[0].member_pubkey.as_deref(), Some("member"));
        assert_eq!(preprompts[0].peer_pubkey.as_deref(), Some("owner"));
        assert_eq!(preprompts[1].preprompt, "Review carefully.");
        assert_eq!(
            preprompts[1].channel_id.as_deref(),
            Some(channel.id.as_str())
        );

        let store = WorkspaceStore::open(path.path()).unwrap();
        store
            .set_conversation_preprompt(Some(&channel.id), None, None, "")
            .unwrap();
        assert_eq!(store.conversation_preprompts().unwrap().len(), 1);
    }

    #[test]
    fn deleting_an_agent_removes_all_conversation_memberships() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let agent = store
            .create_agent(
                "Scout",
                "Researcher",
                "",
                &[],
                None,
                Some("ses_1"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        store
            .add_conversation_agent(&agent.id, Some(&channel.id), None, None, &[])
            .unwrap();
        store
            .add_conversation_agent(&agent.id, None, Some("owner"), Some("member"), &[])
            .unwrap();

        store.delete_agent(&agent.id).unwrap();

        assert!(store.agents().unwrap().is_empty());
        assert!(store.conversation_agents().unwrap().is_empty());
        assert!(store
            .agents_for_conversation(Some(&channel.id), None, None)
            .unwrap()
            .is_empty());
        assert!(store.delete_agent(&agent.id).is_err());
    }

    #[test]
    fn snapshot_keeps_agent_replies_for_both_direct_participants() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let agent = store
            .create_agent(
                "Scout",
                "Researcher",
                "",
                &[],
                None,
                Some("ses_1"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        store
            .add_conversation_agent(&agent.id, None, Some("owner"), Some("member"), &[])
            .unwrap();
        let reply = store
            .add_direct_message(
                &format!("agent:{}", agent.id),
                "member",
                "answer",
                &[],
                &[],
                None,
            )
            .unwrap();
        assert!(store
            .snapshot_messages("owner")
            .unwrap()
            .iter()
            .any(|message| message.id == reply.id));
    }
}
