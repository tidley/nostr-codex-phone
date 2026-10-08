use std::path::Path;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::protocol::{
    MediaReference, WorkspaceBoardTaskPayload, WorkspaceBoardTimelinePayload,
    WorkspaceMentionPayload, WorkspaceReactionPayload,
};
use anyhow::{bail, Context, Result};
use rand::{rngs::OsRng, RngCore};
use rusqlite::{params, types::Type, Connection, OptionalExtension};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceChannel {
    pub id: String,
    pub name: String,
    pub created_by: String,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceChannelMember {
    pub pubkey: String,
    pub is_admin: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceMember {
    pub pubkey: String,
    pub display_name: String,
    pub is_admin: bool,
    pub joined_at: i64,
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
    pub pinned: bool,
    pub reactions: Vec<WorkspaceReactionPayload>,
    pub work_history: Vec<String>,
    pub edited_at: Option<i64>,
    pub deleted_at: Option<i64>,
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
    pub session_context: Option<String>,
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
    pub parent_id: Option<String>,
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
    pub agent_routing_enabled: bool,
    pub folder_scope: Vec<String>,
    pub model: Option<String>,
}

/// The authoritative native OpenCode session for one conversation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceConversationSession {
    pub channel_id: Option<String>,
    pub member_pubkey: Option<String>,
    pub peer_pubkey: Option<String>,
    pub folder_path: String,
    pub opencode_session_id: String,
    pub session_status: String,
    pub session_error: Option<String>,
    pub session_context: Option<String>,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceBoardTask {
    pub id: String,
    pub title: String,
    pub conversation_key: String,
    pub instruction: String,
    pub folder_scope: Vec<String>,
    pub schedule: String,
    pub state: String,
    pub board_column: String,
    pub next_run_at: Option<i64>,
    pub created_by: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub root_message_id: Option<String>,
    pub agent_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceBoardTaskWorkstream {
    pub task_id: String,
    pub root_message_id: String,
    pub agent_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceBoardIntegration {
    pub id: String,
    pub conversation_key: String,
    pub task_id: String,
    pub run_id: Option<String>,
    pub proposal_message_id: String,
    pub state: String,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceBoardRun {
    pub id: String,
    pub task_id: String,
    pub scheduled_at: i64,
    pub state: String,
    pub started_at: Option<i64>,
    pub completed_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceBoardTimelineEntry {
    pub id: String,
    pub task_id: String,
    pub state: String,
    pub detail: String,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct WorkspaceBoardColumn {
    pub id: String,
    pub name: String,
    pub rank: i64,
    pub wip_limit: Option<i64>,
    pub archived_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct WorkspaceBoardCard {
    pub id: String,
    pub title: String,
    pub description: String,
    pub column_id: String,
    pub rank: i64,
    pub priority: String,
    pub estimate: Option<i64>,
    pub due_at: Option<i64>,
    pub created_by: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub archived_at: Option<i64>,
    pub source_thread_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceBoardCardActivity {
    pub id: String,
    pub card_id: String,
    pub kind: String,
    pub detail: String,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceBoardLabel {
    pub id: String,
    pub name: String,
    pub color: String,
}

impl From<WorkspaceBoardTask> for WorkspaceBoardTaskPayload {
    fn from(task: WorkspaceBoardTask) -> Self {
        Self {
            id: task.id,
            title: task.title,
            conversation_key: task.conversation_key,
            instruction: task.instruction,
            folder_scope: task.folder_scope,
            schedule: task.schedule,
            state: task.state,
            board_column: task.board_column,
            next_run_at: task.next_run_at,
            created_by: task.created_by,
            created_at: task.created_at,
            updated_at: task.updated_at,
            root_message_id: task.root_message_id,
            agent_id: task.agent_id,
        }
    }
}

impl From<WorkspaceBoardTimelineEntry> for WorkspaceBoardTimelinePayload {
    fn from(entry: WorkspaceBoardTimelineEntry) -> Self {
        Self {
            id: entry.id,
            task_id: entry.task_id,
            state: entry.state,
            detail: entry.detail,
            created_at: entry.created_at,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceThreadAgentTurn {
    pub parent_id: String,
    pub agent_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EmbeddedConversationBinding {
    pub conversation_id: String,
    pub ready: bool,
    pub closed_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EmbeddedThreadBinding {
    pub conversation_id: String,
    pub thread_id: String,
    pub last_activity_at: i64,
    pub ready: bool,
    pub closed_at: Option<i64>,
}

const EMBEDDED_THREAD_EXPIRY_SECONDS: i64 = 7 * 24 * 60 * 60;

pub struct WorkspaceStore {
    conn: Connection,
}

/// A0 coordinates a conversation but is never allocated to a thread.
pub fn is_workspace_coordinator(agent: &WorkspaceAgent) -> bool {
    agent.name == "A0" || agent.role == "Task coordinator"
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceNotification {
    pub id: i64,
    pub recipient: String,
    pub payload: String,
    pub attempts: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceAgentHandoffOutboxEntry {
    pub reply_message_id: String,
    pub agent_id: String,
    pub member_pubkey: Option<String>,
    pub peer_pubkey: Option<String>,
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
                   CREATE TABLE IF NOT EXISTS workspace_messages (id TEXT PRIMARY KEY, channel_id TEXT, recipient_pubkey TEXT, sender_pubkey TEXT NOT NULL, body TEXT NOT NULL, attachments_json TEXT NOT NULL DEFAULT '[]', mentions_json TEXT NOT NULL DEFAULT '[]', parent_id TEXT, also_send_to_main INTEGER NOT NULL DEFAULT 0, pinned INTEGER NOT NULL DEFAULT 0, work_history_json TEXT NOT NULL DEFAULT '[]', created_at INTEGER NOT NULL,
                   CHECK ((channel_id IS NOT NULL) != (recipient_pubkey IS NOT NULL)));
                  CREATE TABLE IF NOT EXISTS workspace_message_reactions (message_id TEXT NOT NULL REFERENCES workspace_messages(id), emoji TEXT NOT NULL, sender_pubkey TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (message_id, emoji, sender_pubkey));
                  CREATE TABLE IF NOT EXISTS workspace_notification_outbox (id INTEGER PRIMARY KEY, recipient TEXT NOT NULL, payload TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
                 CREATE TABLE IF NOT EXISTS workspace_agents (id TEXT PRIMARY KEY, name TEXT NOT NULL, role TEXT NOT NULL, traits TEXT NOT NULL DEFAULT '', skills_json TEXT NOT NULL DEFAULT '[]', preset TEXT, opencode_provider_id TEXT, opencode_provider_name TEXT, opencode_model_id TEXT, opencode_model_name TEXT, opencode_agent TEXT, workdir TEXT, restart_on_failure INTEGER NOT NULL DEFAULT 1, opencode_session_id TEXT, session_status TEXT NOT NULL DEFAULT 'failed', session_error TEXT, session_context TEXT, created_by TEXT NOT NULL, created_at INTEGER NOT NULL, initialized_at INTEGER, input_tokens INTEGER, output_tokens INTEGER);
                CREATE TABLE IF NOT EXISTS workspace_agent_instances (id TEXT PRIMARY KEY, agent_id TEXT NOT NULL REFERENCES workspace_agents(id), opencode_session_id TEXT, created_at INTEGER NOT NULL);
                   CREATE TABLE IF NOT EXISTS workspace_conversation_agents (agent_id TEXT NOT NULL REFERENCES workspace_agents(id), channel_id TEXT REFERENCES workspace_channels(id), member_pubkey TEXT, peer_pubkey TEXT,
                      folder_scope_json TEXT NOT NULL DEFAULT '[]',
                      PRIMARY KEY (agent_id, channel_id, member_pubkey, peer_pubkey),
                      CHECK ((channel_id IS NOT NULL AND member_pubkey IS NULL AND peer_pubkey IS NULL) OR (channel_id IS NULL AND member_pubkey IS NOT NULL AND peer_pubkey IS NOT NULL)));
                  CREATE TABLE IF NOT EXISTS workspace_conversation_coordinators (agent_id TEXT PRIMARY KEY REFERENCES workspace_agents(id) ON DELETE CASCADE, channel_id TEXT REFERENCES workspace_channels(id), member_pubkey TEXT, peer_pubkey TEXT,
                      CHECK ((channel_id IS NOT NULL AND member_pubkey IS NULL AND peer_pubkey IS NULL) OR (channel_id IS NULL AND member_pubkey IS NOT NULL AND peer_pubkey IS NOT NULL)));
                  CREATE UNIQUE INDEX IF NOT EXISTS workspace_channel_coordinator ON workspace_conversation_coordinators(channel_id) WHERE channel_id IS NOT NULL;
                  CREATE UNIQUE INDEX IF NOT EXISTS workspace_direct_coordinator ON workspace_conversation_coordinators(member_pubkey, peer_pubkey) WHERE channel_id IS NULL;
                    CREATE TABLE IF NOT EXISTS workspace_thread_agents (parent_id TEXT PRIMARY KEY REFERENCES workspace_messages(id) ON DELETE CASCADE, agent_id TEXT NOT NULL REFERENCES workspace_agents(id) ON DELETE CASCADE);
                    CREATE TABLE IF NOT EXISTS workspace_completed_thread_agents (parent_id TEXT PRIMARY KEY REFERENCES workspace_messages(id) ON DELETE CASCADE, agent_id TEXT NOT NULL REFERENCES workspace_agents(id) ON DELETE CASCADE);
                   CREATE TABLE IF NOT EXISTS workspace_thread_agent_routing (parent_id TEXT PRIMARY KEY REFERENCES workspace_messages(id) ON DELETE CASCADE, route_agent INTEGER NOT NULL);
                    CREATE TABLE IF NOT EXISTS workspace_conversation_round_robin (channel_id TEXT REFERENCES workspace_channels(id), member_pubkey TEXT, peer_pubkey TEXT, next_worker INTEGER NOT NULL DEFAULT 0,
                      CHECK ((channel_id IS NOT NULL AND member_pubkey IS NULL AND peer_pubkey IS NULL) OR (channel_id IS NULL AND member_pubkey IS NOT NULL AND peer_pubkey IS NOT NULL)));
                  CREATE UNIQUE INDEX IF NOT EXISTS workspace_channel_round_robin ON workspace_conversation_round_robin(channel_id) WHERE channel_id IS NOT NULL;
                  CREATE UNIQUE INDEX IF NOT EXISTS workspace_direct_round_robin ON workspace_conversation_round_robin(member_pubkey, peer_pubkey) WHERE channel_id IS NULL;
                   CREATE TABLE IF NOT EXISTS workspace_conversation_preprompts (channel_id TEXT REFERENCES workspace_channels(id), member_pubkey TEXT, peer_pubkey TEXT, preprompt TEXT NOT NULL, folder_scope_json TEXT NOT NULL DEFAULT '[]', agent_routing_enabled INTEGER NOT NULL DEFAULT 0, model TEXT,
                     PRIMARY KEY (channel_id, member_pubkey, peer_pubkey),
                        CHECK ((channel_id IS NOT NULL AND member_pubkey IS NULL AND peer_pubkey IS NULL) OR (channel_id IS NULL AND member_pubkey IS NOT NULL AND peer_pubkey IS NOT NULL)));
                   CREATE TABLE IF NOT EXISTS workspace_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                   CREATE TABLE IF NOT EXISTS workspace_conversation_sessions (channel_id TEXT REFERENCES workspace_channels(id), member_pubkey TEXT, peer_pubkey TEXT, folder_path TEXT NOT NULL, opencode_session_id TEXT NOT NULL, session_status TEXT NOT NULL DEFAULT 'ready', session_error TEXT, session_context TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
                          PRIMARY KEY (channel_id, member_pubkey, peer_pubkey),
                        CHECK ((channel_id IS NOT NULL AND member_pubkey IS NULL AND peer_pubkey IS NULL) OR (channel_id IS NULL AND member_pubkey IS NOT NULL AND peer_pubkey IS NOT NULL)));
                   CREATE TABLE IF NOT EXISTS workspace_native_turns (message_id TEXT PRIMARY KEY REFERENCES workspace_messages(id) ON DELETE CASCADE, created_at INTEGER NOT NULL);
                CREATE INDEX IF NOT EXISTS workspace_messages_channel ON workspace_messages(channel_id, created_at);
                CREATE INDEX IF NOT EXISTS workspace_messages_direct ON workspace_messages(recipient_pubkey, sender_pubkey, created_at);",
        )?;
        let store = Self::migrate(conn)?;
        store.init_board_schema()?;
        store.init_agent_handoff_schema()?;
        store.init_herdr_schema()?;
        Ok(store)
    }

    /// Opens an already initialized workspace for a queued agent turn.
    pub fn open_existing(path: &Path) -> Result<Self> {
        let store = Self {
            conn: Self::open_connection(path)?,
        };
        store.init_agent_handoff_schema()?;
        store.init_herdr_schema()?;
        Ok(store)
    }

    fn init_herdr_schema(&self) -> Result<()> {
        self.conn.execute_batch(
             "CREATE TABLE IF NOT EXISTS herdr_embedded_conversation_bindings (
                 conversation_id TEXT PRIMARY KEY,
                 ready INTEGER NOT NULL DEFAULT 0,
                 closed_at INTEGER
             );
             CREATE TABLE IF NOT EXISTS herdr_embedded_thread_bindings (
                 conversation_id TEXT NOT NULL,
                 thread_id TEXT NOT NULL,
                 last_activity_at INTEGER NOT NULL,
                 ready INTEGER NOT NULL DEFAULT 0,
                 closed_at INTEGER,
                 PRIMARY KEY (conversation_id, thread_id)
             );
             CREATE INDEX IF NOT EXISTS herdr_embedded_thread_bindings_expiry
                 ON herdr_embedded_thread_bindings(last_activity_at);
             CREATE TABLE IF NOT EXISTS herdr_worker_execution_attempts (
                  delivery_id TEXT NOT NULL,
                  execution_attempt TEXT NOT NULL,
                  turn_id TEXT NOT NULL UNIQUE,
                  PRIMARY KEY (delivery_id, execution_attempt)
              );",
        )?;
        Ok(())
    }

    pub fn claim_embedded_conversation_binding(&self, conversation_id: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO herdr_embedded_conversation_bindings (conversation_id, ready, closed_at)
             VALUES (?1, 0, NULL)
             ON CONFLICT(conversation_id) DO UPDATE SET ready = 0, closed_at = NULL",
            [required("embedded conversation ID", conversation_id)?],
        )?;
        Ok(())
    }

    pub fn mark_embedded_conversation_binding_ready(&self, conversation_id: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE herdr_embedded_conversation_bindings SET ready = 1 WHERE conversation_id = ?1",
            [required("embedded conversation ID", conversation_id)?],
        )?;
        Ok(())
    }

    pub fn invalidate_embedded_conversation_binding(&self, conversation_id: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE herdr_embedded_conversation_bindings SET ready = 0 WHERE conversation_id = ?1",
            [required("embedded conversation ID", conversation_id)?],
        )?;
        Ok(())
    }

    /// Event subscriptions are lossy. Once their continuity is unknown, no
    /// persisted embedded target may be treated as ready.
    pub fn invalidate_all_embedded_bindings(&self) -> Result<()> {
        self.conn.execute(
            "UPDATE herdr_embedded_conversation_bindings SET ready = 0",
            [],
        )?;
        self.conn.execute(
            "UPDATE herdr_embedded_thread_bindings SET ready = 0",
            [],
        )?;
        Ok(())
    }

    pub fn embedded_conversation_binding(
        &self,
        conversation_id: &str,
    ) -> Result<Option<EmbeddedConversationBinding>> {
        self.conn
            .query_row(
                "SELECT conversation_id, ready, closed_at FROM herdr_embedded_conversation_bindings WHERE conversation_id = ?1",
                [required("embedded conversation ID", conversation_id)?],
                |row| {
                    Ok(EmbeddedConversationBinding {
                        conversation_id: row.get(0)?,
                        ready: row.get(1)?,
                        closed_at: row.get(2)?,
                    })
                },
            )
            .optional()
            .map_err(Into::into)
    }

    pub fn claim_embedded_thread_binding(
        &self,
        conversation_id: &str,
        thread_id: &str,
        last_activity_at: i64,
    ) -> Result<()> {
        self.conn.execute(
            "INSERT INTO herdr_embedded_thread_bindings (conversation_id, thread_id, last_activity_at, ready, closed_at)
             VALUES (?1, ?2, ?3, 0, NULL)
             ON CONFLICT(conversation_id, thread_id) DO UPDATE SET last_activity_at = excluded.last_activity_at, ready = 0, closed_at = NULL",
            params![required("embedded conversation ID", conversation_id)?, required("embedded thread ID", thread_id)?, last_activity_at],
        )?;
        Ok(())
    }

    pub fn mark_embedded_thread_binding_ready(
        &self,
        conversation_id: &str,
        thread_id: &str,
    ) -> Result<()> {
        self.conn.execute(
            "UPDATE herdr_embedded_thread_bindings SET ready = 1 WHERE conversation_id = ?1 AND thread_id = ?2",
            params![required("embedded conversation ID", conversation_id)?, required("embedded thread ID", thread_id)?],
        )?;
        Ok(())
    }

    pub fn invalidate_embedded_thread_binding(
        &self,
        conversation_id: &str,
        thread_id: &str,
    ) -> Result<()> {
        self.conn.execute(
            "UPDATE herdr_embedded_thread_bindings SET ready = 0 WHERE conversation_id = ?1 AND thread_id = ?2",
            params![required("embedded conversation ID", conversation_id)?, required("embedded thread ID", thread_id)?],
        )?;
        Ok(())
    }

    pub fn close_embedded_thread_binding(
        &self,
        conversation_id: &str,
        thread_id: &str,
        closed_at: i64,
    ) -> Result<()> {
        self.conn.execute(
            "UPDATE herdr_embedded_thread_bindings SET ready = 0, closed_at = ?3 WHERE conversation_id = ?1 AND thread_id = ?2",
            params![required("embedded conversation ID", conversation_id)?, required("embedded thread ID", thread_id)?, closed_at],
        )?;
        Ok(())
    }

    pub fn expired_embedded_threads(&self, current_time: i64) -> Result<Vec<EmbeddedThreadBinding>> {
        self.conn
            .prepare(
                "SELECT conversation_id, thread_id, last_activity_at, ready, closed_at
                 FROM herdr_embedded_thread_bindings
                 WHERE closed_at IS NULL AND last_activity_at <= ?1",
            )?
            .query_map([current_time - EMBEDDED_THREAD_EXPIRY_SECONDS], |row| {
                Ok(EmbeddedThreadBinding {
                    conversation_id: row.get(0)?,
                    thread_id: row.get(1)?,
                    last_activity_at: row.get(2)?,
                    ready: row.get(3)?,
                    closed_at: row.get(4)?,
                })
            })?
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(Into::into)
    }

    pub fn embedded_thread_binding(
        &self,
        conversation_id: &str,
        thread_id: &str,
    ) -> Result<Option<EmbeddedThreadBinding>> {
        self.conn
            .query_row(
                "SELECT conversation_id, thread_id, last_activity_at, ready, closed_at FROM herdr_embedded_thread_bindings WHERE conversation_id = ?1 AND thread_id = ?2",
                params![required("embedded conversation ID", conversation_id)?, required("embedded thread ID", thread_id)?],
                |row| {
                    Ok(EmbeddedThreadBinding {
                        conversation_id: row.get(0)?,
                        thread_id: row.get(1)?,
                        last_activity_at: row.get(2)?,
                        ready: row.get(3)?,
                        closed_at: row.get(4)?,
                    })
                },
            )
            .optional()
            .map_err(Into::into)
    }

    pub fn worker_turn_id_for_execution_attempt(
        &self,
        delivery_id: &str,
        execution_attempt: &str,
    ) -> Result<String> {
        let delivery_id = required("worker delivery ID", delivery_id)?;
        let execution_attempt = required("worker execution attempt", execution_attempt)?;
        let turn_id = format!("worker:{delivery_id}:{execution_attempt}");
        self.conn.execute(
            "INSERT OR IGNORE INTO herdr_worker_execution_attempts (delivery_id, execution_attempt, turn_id) VALUES (?1, ?2, ?3)",
            params![delivery_id, execution_attempt, turn_id],
        )?;
        self.conn
            .query_row(
                "SELECT turn_id FROM herdr_worker_execution_attempts WHERE delivery_id = ?1 AND execution_attempt = ?2",
                params![delivery_id, execution_attempt],
                |row| row.get(0),
            )
            .map_err(Into::into)
    }

    fn init_agent_handoff_schema(&self) -> Result<()> {
        self.conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS workspace_agent_handoff_outbox (
                 reply_message_id TEXT NOT NULL REFERENCES workspace_messages(id) ON DELETE CASCADE,
                 agent_id TEXT NOT NULL REFERENCES workspace_agents(id) ON DELETE CASCADE,
                 member_pubkey TEXT,
                 peer_pubkey TEXT,
                 PRIMARY KEY (reply_message_id, agent_id)
             );
             CREATE TRIGGER IF NOT EXISTS workspace_agent_handoff_target_deleted
             AFTER DELETE ON workspace_agents BEGIN
                 DELETE FROM workspace_agent_handoff_outbox WHERE agent_id = OLD.id;
             END;",
        )?;
        let mut columns = self
            .conn
            .prepare("PRAGMA table_info(workspace_agent_handoff_outbox)")?;
        let columns = columns
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        for column in ["member_pubkey", "peer_pubkey"] {
            if !columns.iter().any(|existing| existing == column) {
                self.conn.execute(
                    &format!("ALTER TABLE workspace_agent_handoff_outbox ADD COLUMN {column} TEXT"),
                    [],
                )?;
            }
        }
        Ok(())
    }

    fn init_board_schema(&self) -> Result<()> {
        self.conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS workspace_board_tasks (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                conversation_key TEXT NOT NULL,
                instruction TEXT NOT NULL,
                folder_scope_json TEXT NOT NULL DEFAULT '[]',
                schedule TEXT NOT NULL,
                state TEXT NOT NULL,
                next_run_at INTEGER,
                created_by TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS workspace_board_runs (
                id TEXT PRIMARY KEY,
                task_id TEXT NOT NULL REFERENCES workspace_board_tasks(id) ON DELETE CASCADE,
                scheduled_at INTEGER NOT NULL,
                state TEXT NOT NULL,
                started_at INTEGER,
                completed_at INTEGER,
                UNIQUE(task_id, scheduled_at)
            );
             CREATE TABLE IF NOT EXISTS workspace_board_timeline (
                 id TEXT PRIMARY KEY,
                 task_id TEXT NOT NULL REFERENCES workspace_board_tasks(id) ON DELETE CASCADE,
                 state TEXT NOT NULL,
                 detail TEXT NOT NULL,
                 created_at INTEGER NOT NULL
             );
              CREATE TABLE IF NOT EXISTS workspace_board_turns (
                  message_id TEXT PRIMARY KEY REFERENCES workspace_messages(id) ON DELETE CASCADE,
                  task_id TEXT NOT NULL REFERENCES workspace_board_tasks(id) ON DELETE CASCADE
              );
              CREATE TABLE IF NOT EXISTS workspace_board_task_workstreams (
                  task_id TEXT PRIMARY KEY REFERENCES workspace_board_tasks(id) ON DELETE CASCADE,
                  root_message_id TEXT NOT NULL UNIQUE REFERENCES workspace_messages(id) ON DELETE CASCADE,
                  agent_id TEXT NOT NULL UNIQUE REFERENCES workspace_agents(id) ON DELETE CASCADE
              );
               CREATE TABLE IF NOT EXISTS workspace_board_integrations (
                  id TEXT PRIMARY KEY,
                  conversation_key TEXT NOT NULL,
                   task_id TEXT NOT NULL REFERENCES workspace_board_tasks(id) ON DELETE CASCADE,
                   run_id TEXT REFERENCES workspace_board_runs(id) ON DELETE SET NULL,
                  proposal_message_id TEXT NOT NULL REFERENCES workspace_messages(id) ON DELETE CASCADE,
                   state TEXT NOT NULL,
                   result TEXT,
                   created_at INTEGER NOT NULL
              );
            CREATE INDEX IF NOT EXISTS workspace_board_tasks_due
                ON workspace_board_tasks(state, next_run_at);
             CREATE INDEX IF NOT EXISTS workspace_board_timeline_task
                ON workspace_board_timeline(task_id, created_at);
             CREATE INDEX IF NOT EXISTS workspace_board_integrations_fifo
                ON workspace_board_integrations(conversation_key, state, created_at, id);
            CREATE TRIGGER IF NOT EXISTS workspace_board_tasks_revision_insert AFTER INSERT ON workspace_board_tasks BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
            CREATE TRIGGER IF NOT EXISTS workspace_board_tasks_revision_update AFTER UPDATE ON workspace_board_tasks BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
            CREATE TRIGGER IF NOT EXISTS workspace_board_runs_revision_insert AFTER INSERT ON workspace_board_runs BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_board_timeline_revision_insert AFTER INSERT ON workspace_board_timeline BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;",
        )?;
        let integration_columns = self
            .conn
            .prepare("PRAGMA table_info(workspace_board_integrations)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        if !integration_columns.iter().any(|column| column == "result") {
            self.conn
                .execute_batch("ALTER TABLE workspace_board_integrations ADD COLUMN result TEXT")?;
        }
        if !integration_columns.iter().any(|column| column == "run_id") {
            self.conn.execute_batch(
                "ALTER TABLE workspace_board_integrations RENAME TO workspace_board_integrations_legacy;
                 CREATE TABLE workspace_board_integrations (
                     id TEXT PRIMARY KEY,
                     conversation_key TEXT NOT NULL,
                     task_id TEXT NOT NULL REFERENCES workspace_board_tasks(id) ON DELETE CASCADE,
                     run_id TEXT REFERENCES workspace_board_runs(id) ON DELETE SET NULL,
                     proposal_message_id TEXT NOT NULL REFERENCES workspace_messages(id) ON DELETE CASCADE,
                     state TEXT NOT NULL,
                     result TEXT,
                     created_at INTEGER NOT NULL
                 );
                 INSERT INTO workspace_board_integrations (id, conversation_key, task_id, proposal_message_id, state, result, created_at)
                 SELECT id, conversation_key, task_id, proposal_message_id, state, result, created_at FROM workspace_board_integrations_legacy;
                 DROP TABLE workspace_board_integrations_legacy;",
            )?;
            self.conn.execute_batch("CREATE INDEX IF NOT EXISTS workspace_board_integrations_fifo ON workspace_board_integrations(conversation_key, state, created_at, id);")?;
        }
        let board_task_columns = self
            .conn
            .prepare("PRAGMA table_info(workspace_board_tasks)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        if !board_task_columns
            .iter()
            .any(|column| column == "board_column")
        {
            self.conn.execute_batch(
                "ALTER TABLE workspace_board_tasks ADD COLUMN board_column TEXT NOT NULL DEFAULT 'scheduled';
                 UPDATE workspace_board_tasks SET board_column = state;",
            )?;
        }
        self.conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS workspace_board_columns (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL UNIQUE,
                rank INTEGER NOT NULL,
                wip_limit INTEGER,
                archived_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS workspace_board_cards (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                column_id TEXT NOT NULL REFERENCES workspace_board_columns(id),
                rank INTEGER NOT NULL,
                priority TEXT NOT NULL DEFAULT 'none',
                estimate INTEGER,
                due_at INTEGER,
                created_by TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                 updated_at INTEGER NOT NULL,
                 archived_at INTEGER,
                 source_thread_id TEXT UNIQUE REFERENCES workspace_messages(id) ON DELETE SET NULL
            );
            CREATE TABLE IF NOT EXISTS workspace_board_card_activity (
                id TEXT PRIMARY KEY,
                card_id TEXT NOT NULL REFERENCES workspace_board_cards(id) ON DELETE CASCADE,
                kind TEXT NOT NULL,
                detail TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS workspace_board_card_assignees (card_id TEXT NOT NULL REFERENCES workspace_board_cards(id) ON DELETE CASCADE, assignee_id TEXT NOT NULL, PRIMARY KEY (card_id, assignee_id));
            CREATE TABLE IF NOT EXISTS workspace_board_labels (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, color TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS workspace_board_card_labels (card_id TEXT NOT NULL REFERENCES workspace_board_cards(id) ON DELETE CASCADE, label_id TEXT NOT NULL REFERENCES workspace_board_labels(id) ON DELETE CASCADE, PRIMARY KEY (card_id, label_id));
            CREATE TABLE IF NOT EXISTS workspace_board_card_dependencies (card_id TEXT NOT NULL REFERENCES workspace_board_cards(id) ON DELETE CASCADE, depends_on_card_id TEXT NOT NULL REFERENCES workspace_board_cards(id) ON DELETE CASCADE, PRIMARY KEY (card_id, depends_on_card_id), CHECK (card_id != depends_on_card_id));
            CREATE INDEX IF NOT EXISTS workspace_board_columns_rank ON workspace_board_columns(rank);
            CREATE INDEX IF NOT EXISTS workspace_board_cards_column_rank ON workspace_board_cards(column_id, rank);
            CREATE INDEX IF NOT EXISTS workspace_board_card_activity_card ON workspace_board_card_activity(card_id, created_at);
            CREATE TRIGGER IF NOT EXISTS workspace_board_columns_revision_insert AFTER INSERT ON workspace_board_columns BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
            CREATE TRIGGER IF NOT EXISTS workspace_board_columns_revision_update AFTER UPDATE ON workspace_board_columns BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
            CREATE TRIGGER IF NOT EXISTS workspace_board_cards_revision_insert AFTER INSERT ON workspace_board_cards BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
            CREATE TRIGGER IF NOT EXISTS workspace_board_cards_revision_update AFTER UPDATE ON workspace_board_cards BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
            CREATE TRIGGER IF NOT EXISTS workspace_board_card_activity_revision_insert AFTER INSERT ON workspace_board_card_activity BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;",
        )?;
        self.ensure_board_card_column("estimate", "INTEGER")?;
        self.ensure_board_card_column("due_at", "INTEGER")?;
        self.ensure_board_card_column(
            "source_thread_id",
            "TEXT REFERENCES workspace_messages(id) ON DELETE SET NULL",
        )?;
        self.conn.execute_batch("CREATE UNIQUE INDEX IF NOT EXISTS workspace_board_cards_source_thread ON workspace_board_cards(source_thread_id) WHERE source_thread_id IS NOT NULL;")?;
        let column_count: i64 =
            self.conn
                .query_row("SELECT COUNT(*) FROM workspace_board_columns", [], |row| {
                    row.get(0)
                })?;
        if column_count == 0 {
            for (index, name) in ["Backlog", "Ready", "In Progress", "Review", "Done"]
                .into_iter()
                .enumerate()
            {
                self.conn.execute(
                    "INSERT INTO workspace_board_columns (id, name, rank) VALUES (?1, ?2, ?3)",
                    params![new_id(), name, (index as i64 + 1) * 1024],
                )?;
            }
        }
        Ok(())
    }

    pub fn conversation_session(
        &self,
        channel_id: Option<&str>,
        member_pubkey: Option<&str>,
        peer_pubkey: Option<&str>,
    ) -> Result<Option<WorkspaceConversationSession>> {
        let (channel_id, member_pubkey, peer_pubkey) =
            conversation_session_key(channel_id, member_pubkey, peer_pubkey)?;
        self.conn
            .query_row(
                "SELECT channel_id, member_pubkey, peer_pubkey, folder_path, opencode_session_id, session_status, session_error, session_context, updated_at FROM workspace_conversation_sessions WHERE channel_id IS ?1 AND member_pubkey IS ?2 AND peer_pubkey IS ?3",
                params![channel_id, member_pubkey, peer_pubkey],
                conversation_session_from_row,
            )
            .optional()
            .map_err(Into::into)
    }

    pub fn upsert_conversation_session(
        &self,
        channel_id: Option<&str>,
        member_pubkey: Option<&str>,
        peer_pubkey: Option<&str>,
        folder_path: &str,
        opencode_session_id: &str,
        session_status: &str,
        session_error: Option<&str>,
    ) -> Result<()> {
        let (channel_id, member_pubkey, peer_pubkey) =
            conversation_session_key(channel_id, member_pubkey, peer_pubkey)?;
        let folder_path = required("session folder", folder_path)?;
        let opencode_session_id = required("OpenCode session ID", opencode_session_id)?;
        let session_status = required("session status", session_status)?;
        let timestamp = now();
        // `folder_path` remains metadata. A folder-policy edit must not create
        // a new session for the same conversation.
        let updated = self.conn.execute(
            "UPDATE workspace_conversation_sessions SET opencode_session_id = ?4, session_status = ?5, session_error = ?6, updated_at = ?7 WHERE channel_id IS ?1 AND member_pubkey IS ?2 AND peer_pubkey IS ?3",
            params![channel_id, member_pubkey, peer_pubkey, opencode_session_id, session_status, session_error, timestamp],
        )?;
        if updated == 0 {
            self.conn.execute(
                "INSERT INTO workspace_conversation_sessions (channel_id, member_pubkey, peer_pubkey, folder_path, opencode_session_id, session_status, session_error, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8)",
                params![channel_id, member_pubkey, peer_pubkey, folder_path, opencode_session_id, session_status, session_error, timestamp],
            )?;
        }
        Ok(())
    }

    pub fn set_conversation_session_context(
        &self,
        channel_id: Option<&str>,
        member_pubkey: Option<&str>,
        peer_pubkey: Option<&str>,
        session_context: &str,
    ) -> Result<()> {
        let (channel_id, member_pubkey, peer_pubkey) =
            conversation_session_key(channel_id, member_pubkey, peer_pubkey)?;
        self.conn.execute(
            "UPDATE workspace_conversation_sessions SET session_context = ?4, updated_at = ?5 WHERE channel_id IS ?1 AND member_pubkey IS ?2 AND peer_pubkey IS ?3",
            params![channel_id, member_pubkey, peer_pubkey, required("session context", session_context)?, now()],
        )?;
        Ok(())
    }

    pub fn queue_native_turn(&self, message_id: &str) -> Result<()> {
        self.conn.execute(
            "INSERT OR IGNORE INTO workspace_native_turns (message_id, created_at) VALUES (?1, ?2)",
            params![required("native turn message id", message_id)?, now()],
        )?;
        Ok(())
    }

    pub fn complete_native_turn(&self, message_id: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM workspace_native_turns WHERE message_id = ?1",
            [required("native turn message id", message_id)?],
        )?;
        Ok(())
    }

    pub fn link_board_turn(&self, task_id: &str, message_id: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO workspace_board_turns (message_id, task_id) VALUES (?1, ?2)",
            params![
                required("native turn message id", message_id)?,
                required("board task ID", task_id)?
            ],
        )?;
        Ok(())
    }

    pub fn board_task_for_turn(&self, message_id: &str) -> Result<Option<String>> {
        self.conn
            .query_row(
                "SELECT task_id FROM workspace_board_turns WHERE message_id = ?1",
                [required("native turn message id", message_id)?],
                |row| row.get(0),
            )
            .optional()
            .map_err(Into::into)
    }

    pub fn pending_native_turns(&self) -> Result<Vec<String>> {
        let mut statement = self.conn.prepare(
            "SELECT message_id FROM workspace_native_turns ORDER BY created_at ASC, rowid ASC",
        )?;
        let pending = statement
            .query_map([], |row| row.get(0))?
            .collect::<rusqlite::Result<_>>()
            .map_err(Into::into);
        pending
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
        let has_channel_members = conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'workspace_channel_members')",
            [],
            |row| row.get::<_, bool>(0),
        )?;
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
        let has_pinned = conn
            .prepare("PRAGMA table_info(workspace_messages)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?
            .iter()
            .any(|column| column == "pinned");
        if !has_pinned {
            conn.execute(
                "ALTER TABLE workspace_messages ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0",
                [],
            )?;
        }
        let has_work_history = conn
            .prepare("PRAGMA table_info(workspace_messages)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?
            .iter()
            .any(|column| column == "work_history_json");
        if !has_work_history {
            conn.execute(
                "ALTER TABLE workspace_messages ADD COLUMN work_history_json TEXT NOT NULL DEFAULT '[]'",
                [],
            )?;
        }
        let message_columns = conn
            .prepare("PRAGMA table_info(workspace_messages)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        if !message_columns.iter().any(|column| column == "edited_at") {
            conn.execute(
                "ALTER TABLE workspace_messages ADD COLUMN edited_at INTEGER",
                [],
            )?;
        }
        if !message_columns.iter().any(|column| column == "deleted_at") {
            conn.execute(
                "ALTER TABLE workspace_messages ADD COLUMN deleted_at INTEGER",
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
        if !agent_columns
            .iter()
            .any(|column| column == "session_context")
        {
            conn.execute(
                "ALTER TABLE workspace_agents ADD COLUMN session_context TEXT",
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
        let conversation_preprompt_columns = conn
            .prepare("PRAGMA table_info(workspace_conversation_preprompts)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        if !conversation_preprompt_columns
            .iter()
            .any(|column| column == "folder_scope_json")
        {
            conn.execute(
                "ALTER TABLE workspace_conversation_preprompts ADD COLUMN folder_scope_json TEXT NOT NULL DEFAULT '[]'",
                [],
            )?;
        }
        if !conversation_preprompt_columns
            .iter()
            .any(|column| column == "model")
        {
            conn.execute(
                "ALTER TABLE workspace_conversation_preprompts ADD COLUMN model TEXT",
                [],
            )?;
        }
        if !conversation_preprompt_columns
            .iter()
            .any(|column| column == "agent_routing_enabled")
        {
            conn.execute(
                "ALTER TABLE workspace_conversation_preprompts ADD COLUMN agent_routing_enabled INTEGER NOT NULL DEFAULT 0",
                [],
            )?;
        }
        let conversation_session_columns = conn
            .prepare("PRAGMA table_info(workspace_conversation_sessions)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let has_thread_root_session_key = conversation_session_columns
            .iter()
            .any(|column| column == "thread_root_id");
        if has_thread_root_session_key {
            // Older versions created a session for every thread. Retain only
            // the most recently used session per conversation so all future
            // turns are serialized through one OpenCode instance.
            conn.execute_batch(
                "ALTER TABLE workspace_conversation_sessions RENAME TO workspace_conversation_sessions_legacy;
                 CREATE TABLE workspace_conversation_sessions (channel_id TEXT REFERENCES workspace_channels(id), member_pubkey TEXT, peer_pubkey TEXT, folder_path TEXT NOT NULL, opencode_session_id TEXT NOT NULL, session_status TEXT NOT NULL DEFAULT 'ready', session_error TEXT, session_context TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY (channel_id, member_pubkey, peer_pubkey), CHECK ((channel_id IS NOT NULL AND member_pubkey IS NULL AND peer_pubkey IS NULL) OR (channel_id IS NULL AND member_pubkey IS NOT NULL AND peer_pubkey IS NOT NULL)));
                 INSERT INTO workspace_conversation_sessions (channel_id, member_pubkey, peer_pubkey, folder_path, opencode_session_id, session_status, session_error, session_context, created_at, updated_at)
                 SELECT channel_id, member_pubkey, peer_pubkey, folder_path, opencode_session_id, session_status, session_error, session_context, created_at, updated_at
                 FROM workspace_conversation_sessions_legacy AS session
                 WHERE rowid = (SELECT candidate.rowid FROM workspace_conversation_sessions_legacy AS candidate WHERE candidate.channel_id IS session.channel_id AND candidate.member_pubkey IS session.member_pubkey AND candidate.peer_pubkey IS session.peer_pubkey ORDER BY candidate.updated_at DESC, candidate.rowid DESC LIMIT 1);
                 DROP TABLE workspace_conversation_sessions_legacy;",
            )?;
        }
        if !has_thread_root_session_key
            && !conversation_session_columns
                .iter()
                .any(|column| column == "session_context")
        {
            conn.execute(
                "ALTER TABLE workspace_conversation_sessions ADD COLUMN session_context TEXT",
                [],
            )?;
        }
        // Channels created before per-channel membership were visible to every
        // workspace member. Preserve that access when upgrading existing stores.
        conn.execute_batch("CREATE TABLE IF NOT EXISTS workspace_channel_members (channel_id TEXT NOT NULL REFERENCES workspace_channels(id), pubkey TEXT NOT NULL REFERENCES workspace_members(pubkey), is_admin INTEGER NOT NULL DEFAULT 0, joined_at INTEGER NOT NULL, PRIMARY KEY (channel_id, pubkey));")?;
        conn.execute_batch("CREATE TABLE IF NOT EXISTS workspace_conversation_coordinators (agent_id TEXT PRIMARY KEY REFERENCES workspace_agents(id) ON DELETE CASCADE, channel_id TEXT REFERENCES workspace_channels(id), member_pubkey TEXT, peer_pubkey TEXT, CHECK ((channel_id IS NOT NULL AND member_pubkey IS NULL AND peer_pubkey IS NULL) OR (channel_id IS NULL AND member_pubkey IS NOT NULL AND peer_pubkey IS NOT NULL))); CREATE UNIQUE INDEX IF NOT EXISTS workspace_channel_coordinator ON workspace_conversation_coordinators(channel_id) WHERE channel_id IS NOT NULL; CREATE UNIQUE INDEX IF NOT EXISTS workspace_direct_coordinator ON workspace_conversation_coordinators(member_pubkey, peer_pubkey) WHERE channel_id IS NULL; CREATE TABLE IF NOT EXISTS workspace_completed_thread_agents (parent_id TEXT PRIMARY KEY REFERENCES workspace_messages(id) ON DELETE CASCADE, agent_id TEXT NOT NULL REFERENCES workspace_agents(id) ON DELETE CASCADE); CREATE TABLE IF NOT EXISTS workspace_conversation_round_robin (channel_id TEXT REFERENCES workspace_channels(id), member_pubkey TEXT, peer_pubkey TEXT, next_worker INTEGER NOT NULL DEFAULT 0, CHECK ((channel_id IS NOT NULL AND member_pubkey IS NULL AND peer_pubkey IS NULL) OR (channel_id IS NULL AND member_pubkey IS NOT NULL AND peer_pubkey IS NOT NULL))); CREATE UNIQUE INDEX IF NOT EXISTS workspace_channel_round_robin ON workspace_conversation_round_robin(channel_id) WHERE channel_id IS NOT NULL; CREATE UNIQUE INDEX IF NOT EXISTS workspace_direct_round_robin ON workspace_conversation_round_robin(member_pubkey, peer_pubkey) WHERE channel_id IS NULL;")?;
        conn.execute_batch("CREATE TABLE IF NOT EXISTS workspace_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);")?;
        if has_thread_root_session_key {
            // Native conversation sessions replaced the coordinator/worker model.
            // Drop legacy assignments while upgrading from per-thread sessions.
            conn.execute_batch(
                "DELETE FROM workspace_thread_agents;
             DELETE FROM workspace_completed_thread_agents;
             DELETE FROM workspace_conversation_round_robin;
             DELETE FROM workspace_conversation_coordinators;
             DELETE FROM workspace_conversation_agents
               WHERE agent_id IN (
                 SELECT id FROM workspace_agents
                 WHERE name = 'A0'
                    OR role IN ('Task coordinator', 'Conversation worker', 'Round-robin worker')
               );
             DELETE FROM workspace_agent_instances
               WHERE agent_id IN (
                 SELECT id FROM workspace_agents
                 WHERE name = 'A0'
                    OR role IN ('Task coordinator', 'Conversation worker', 'Round-robin worker')
               );
              DELETE FROM workspace_agents
                WHERE name = 'A0'
                   OR role IN ('Task coordinator', 'Conversation worker', 'Round-robin worker');",
            )?;
        }
        if !has_channel_members {
            conn.execute_batch("INSERT OR IGNORE INTO workspace_channel_members (channel_id, pubkey, joined_at) SELECT c.id, m.pubkey, c.created_at FROM workspace_channels c CROSS JOIN workspace_members m; UPDATE workspace_channel_members SET is_admin = 1 WHERE (channel_id, pubkey) IN (SELECT id, created_by FROM workspace_channels);")?;
        }
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS workspace_metadata (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
             INSERT OR IGNORE INTO workspace_metadata (key, value) VALUES ('revision', 0);
             CREATE TRIGGER IF NOT EXISTS workspace_members_revision_insert AFTER INSERT ON workspace_members BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_members_revision_update AFTER UPDATE ON workspace_members BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_channels_revision_insert AFTER INSERT ON workspace_channels BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
             CREATE TRIGGER IF NOT EXISTS workspace_channels_revision_update AFTER UPDATE ON workspace_channels BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
              CREATE TRIGGER IF NOT EXISTS workspace_channels_revision_delete AFTER DELETE ON workspace_channels BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
              CREATE TRIGGER IF NOT EXISTS workspace_channel_members_revision_insert AFTER INSERT ON workspace_channel_members BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
              CREATE TRIGGER IF NOT EXISTS workspace_channel_members_revision_update AFTER UPDATE ON workspace_channel_members BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
              CREATE TRIGGER IF NOT EXISTS workspace_channel_members_revision_delete AFTER DELETE ON workspace_channel_members BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
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
              CREATE TRIGGER IF NOT EXISTS workspace_thread_agents_revision_insert AFTER INSERT ON workspace_thread_agents BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
              CREATE TRIGGER IF NOT EXISTS workspace_thread_agents_revision_update AFTER UPDATE ON workspace_thread_agents BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
               CREATE TRIGGER IF NOT EXISTS workspace_thread_agents_revision_delete AFTER DELETE ON workspace_thread_agents BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
              CREATE TRIGGER IF NOT EXISTS workspace_completed_thread_agents_revision_insert AFTER INSERT ON workspace_completed_thread_agents BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
              CREATE TRIGGER IF NOT EXISTS workspace_completed_thread_agents_revision_update AFTER UPDATE ON workspace_completed_thread_agents BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
              CREATE TRIGGER IF NOT EXISTS workspace_completed_thread_agents_revision_delete AFTER DELETE ON workspace_completed_thread_agents BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
              CREATE TRIGGER IF NOT EXISTS workspace_conversation_preprompts_revision_insert AFTER INSERT ON workspace_conversation_preprompts BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
              CREATE TRIGGER IF NOT EXISTS workspace_conversation_preprompts_revision_update AFTER UPDATE ON workspace_conversation_preprompts BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
              CREATE TRIGGER IF NOT EXISTS workspace_conversation_preprompts_revision_delete AFTER DELETE ON workspace_conversation_preprompts BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
               CREATE TRIGGER IF NOT EXISTS workspace_conversation_sessions_revision_insert AFTER INSERT ON workspace_conversation_sessions BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
               CREATE TRIGGER IF NOT EXISTS workspace_conversation_sessions_revision_update AFTER UPDATE ON workspace_conversation_sessions BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
               CREATE TRIGGER IF NOT EXISTS workspace_settings_revision_insert AFTER INSERT ON workspace_settings BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
               CREATE TRIGGER IF NOT EXISTS workspace_settings_revision_update AFTER UPDATE ON workspace_settings BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;
               CREATE TRIGGER IF NOT EXISTS workspace_settings_revision_delete AFTER DELETE ON workspace_settings BEGIN UPDATE workspace_metadata SET value = value + 1 WHERE key = 'revision'; END;",
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

    pub fn create_board_task(
        &self,
        created_by: &str,
        title: &str,
        conversation_key: &str,
        instruction: &str,
        folder_scope: &[String],
        schedule: &str,
        next_run_at: i64,
    ) -> Result<WorkspaceBoardTask> {
        let title = required("board task title", title)?;
        let conversation_key = required("board task conversation", conversation_key)?;
        let instruction = required("board task instruction", instruction)?;
        let schedule = required("board task schedule", schedule)?;
        if !matches!(
            schedule.as_str(),
            "once" | "daily" | "weekdays" | "weekly" | "monthly"
        ) {
            bail!("board task schedule is invalid");
        }
        let created_by = required("board task creator", created_by)?;
        if !self.is_member(&created_by)? {
            bail!("board task creator is not a workspace member");
        }
        let timestamp = now();
        let task = WorkspaceBoardTask {
            id: new_id(),
            title,
            conversation_key,
            instruction,
            folder_scope: folder_scope.to_vec(),
            schedule,
            state: "scheduled".to_string(),
            board_column: "scheduled".to_string(),
            next_run_at: Some(next_run_at),
            created_by,
            created_at: timestamp,
            updated_at: timestamp,
            root_message_id: None,
            agent_id: None,
        };
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            self.conn.execute(
                "INSERT INTO workspace_board_tasks (id, title, conversation_key, instruction, folder_scope_json, schedule, state, board_column, next_run_at, created_by, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
                params![task.id, task.title, task.conversation_key, task.instruction, serde_json::to_string(&task.folder_scope)?, task.schedule, task.state, task.board_column, task.next_run_at, task.created_by, task.created_at, task.updated_at],
            )?;
            self.append_board_timeline_at(&task.id, "scheduled", "Task scheduled", timestamp)
        })();
        self.finish_board_transaction(result)?;
        Ok(task)
    }

    pub fn discard_board_task(&self, task_id: &str) -> Result<()> {
        if self.conn.execute(
            "DELETE FROM workspace_board_tasks WHERE id = ?1 AND state = 'scheduled'",
            [required("board task ID", task_id)?],
        )? != 1
        {
            bail!("scheduled board task could not be discarded");
        }
        Ok(())
    }

    pub fn board_tasks(&self) -> Result<Vec<WorkspaceBoardTask>> {
        Ok(self.conn.prepare("SELECT task.id, task.title, task.conversation_key, task.instruction, task.folder_scope_json, task.schedule, task.state, task.board_column, task.next_run_at, task.created_by, task.created_at, task.updated_at, workstream.root_message_id, workstream.agent_id FROM workspace_board_tasks task LEFT JOIN workspace_board_task_workstreams workstream ON workstream.task_id = task.id ORDER BY task.next_run_at, task.created_at")?
            .query_map([], board_task_from_row)?
            .collect::<rusqlite::Result<_>>()?)
    }

    pub fn move_board_task(&self, task_id: &str, board_column: &str) -> Result<()> {
        let task_id = required("board task ID", task_id)?;
        let board_column = required("board task board column", board_column)?;
        if !valid_board_task_column(&board_column) {
            bail!("board task board column is invalid");
        }
        if self.conn.execute(
            "UPDATE workspace_board_tasks SET board_column = ?2, updated_at = ?3 WHERE id = ?1",
            params![task_id, board_column, now()],
        )? != 1
        {
            bail!("board task does not exist");
        }
        Ok(())
    }

    pub fn link_board_task_workstream(
        &self,
        task_id: &str,
        root_message_id: &str,
        agent_id: &str,
    ) -> Result<()> {
        let task_id = required("board task ID", task_id)?;
        let root_message_id = required("board task root message ID", root_message_id)?;
        let agent_id = required("board task agent ID", agent_id)?;
        let is_root = self
            .conn
            .query_row(
                "SELECT parent_id IS NULL FROM workspace_messages WHERE id = ?1",
                [&root_message_id],
                |row| row.get::<_, bool>(0),
            )
            .optional()?
            .context("board task root message does not exist")?;
        if !is_root {
            bail!("board task workstream message must be a thread root");
        }
        if self.conn.execute(
            "INSERT INTO workspace_board_task_workstreams (task_id, root_message_id, agent_id) VALUES (?1, ?2, ?3)",
            params![task_id, root_message_id, agent_id],
        )? != 1 {
            bail!("board task workstream could not be linked");
        }
        Ok(())
    }

    pub fn board_task_workstream(
        &self,
        task_id: &str,
    ) -> Result<Option<WorkspaceBoardTaskWorkstream>> {
        self.conn
            .query_row(
                "SELECT task_id, root_message_id, agent_id FROM workspace_board_task_workstreams WHERE task_id = ?1",
                [required("board task ID", task_id)?],
                |row| {
                    Ok(WorkspaceBoardTaskWorkstream {
                        task_id: row.get(0)?,
                        root_message_id: row.get(1)?,
                        agent_id: row.get(2)?,
                    })
                },
            )
            .optional()
            .map_err(Into::into)
    }

    pub fn board_task_workstream_for_root(
        &self,
        root_message_id: &str,
    ) -> Result<Option<WorkspaceBoardTaskWorkstream>> {
        self.conn.query_row("SELECT task_id, root_message_id, agent_id FROM workspace_board_task_workstreams WHERE root_message_id = ?1", [required("board task root message ID", root_message_id)?], |row| Ok(WorkspaceBoardTaskWorkstream { task_id: row.get(0)?, root_message_id: row.get(1)?, agent_id: row.get(2)? })).optional().map_err(Into::into)
    }

    pub fn board_task_workstream_for_agent(
        &self,
        agent_id: &str,
    ) -> Result<Option<WorkspaceBoardTaskWorkstream>> {
        self.conn.query_row("SELECT task_id, root_message_id, agent_id FROM workspace_board_task_workstreams WHERE agent_id = ?1", [required("board task agent ID", agent_id)?], |row| Ok(WorkspaceBoardTaskWorkstream { task_id: row.get(0)?, root_message_id: row.get(1)?, agent_id: row.get(2)? })).optional().map_err(Into::into)
    }

    pub fn enqueue_board_integration(
        &self,
        task_id: &str,
        proposal_message_id: &str,
    ) -> Result<WorkspaceBoardIntegration> {
        let task = self
            .board_task(task_id)?
            .context("board task does not exist")?;
        let workstream = self
            .board_task_workstream(&task.id)?
            .context("board task has no workstream")?;
        let proposal_message_id = required("board proposal message ID", proposal_message_id)?;
        let proposal = self
            .message_by_id(&proposal_message_id)?
            .context("board proposal message does not exist")?;
        if proposal.parent_id.as_deref() != Some(&workstream.root_message_id) {
            bail!("board proposal must belong to the task thread");
        }
        let run_id = self.conn.query_row(
            "SELECT id FROM workspace_board_runs WHERE task_id = ?1 AND state = 'running' ORDER BY started_at DESC LIMIT 1",
            [&task.id],
            |row| row.get(0),
        ).optional()?;
        let integration = WorkspaceBoardIntegration {
            id: new_id(),
            conversation_key: task.conversation_key,
            task_id: task.id,
            run_id,
            proposal_message_id,
            state: "queued".to_string(),
            created_at: now(),
        };
        self.conn.execute("INSERT INTO workspace_board_integrations (id, conversation_key, task_id, run_id, proposal_message_id, state, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)", params![integration.id, integration.conversation_key, integration.task_id, integration.run_id, integration.proposal_message_id, integration.state, integration.created_at])?;
        self.append_board_timeline(
            &integration.task_id,
            "integration_queued",
            "Proposal queued for private head integration",
        )?;
        Ok(integration)
    }

    /// Marks one task-thread message as the task's explicit integration proposal.
    pub fn mark_board_proposal_ready(
        &self,
        task_id: &str,
        proposal_message_id: &str,
    ) -> Result<Option<WorkspaceBoardIntegration>> {
        let task = self
            .board_task(task_id)?
            .context("board task does not exist")?;
        if task.state != "running" {
            return Ok(None);
        }
        let exists: bool = self.conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM workspace_board_integrations WHERE task_id = ?1 AND proposal_message_id = ?2)",
            params![task_id, proposal_message_id],
            |row| row.get(0),
        )?;
        if exists {
            return Ok(None);
        }
        self.enqueue_board_integration(task_id, proposal_message_id)
            .map(Some)
    }

    pub fn claim_next_board_integration(
        &self,
        conversation_key: &str,
    ) -> Result<Option<WorkspaceBoardIntegration>> {
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            let integration = self.conn.query_row("SELECT id, conversation_key, task_id, run_id, proposal_message_id, state, created_at FROM workspace_board_integrations WHERE conversation_key = ?1 AND state = 'queued' AND NOT EXISTS (SELECT 1 FROM workspace_board_integrations running WHERE running.conversation_key = workspace_board_integrations.conversation_key AND running.state = 'running') ORDER BY created_at, rowid LIMIT 1", [required("board conversation", conversation_key)?], board_integration_from_row).optional()?;
            let Some(integration) = integration else {
                return Ok(None);
            };
            self.conn.execute(
                "UPDATE workspace_board_integrations SET state = 'running' WHERE id = ?1",
                [&integration.id],
            )?;
            self.append_board_timeline(
                &integration.task_id,
                "integrating",
                "Private head integration started",
            )?;
            Ok(Some(WorkspaceBoardIntegration {
                state: "running".to_string(),
                ..integration
            }))
        })();
        self.finish_board_transaction(result)
    }

    pub fn cancel_board_integrations(&self, task_id: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE workspace_board_integrations SET state = 'cancelled', result = 'Integration cancelled' WHERE task_id = ?1 AND state IN ('queued', 'running')",
            [required("board task ID", task_id)?],
        )?;
        Ok(())
    }

    /// Returns false when cancellation won the race with an in-flight head result.
    pub fn finish_board_integration(
        &self,
        integration_id: &str,
        result: Result<&str>,
    ) -> Result<bool> {
        let integration_id = required("board integration ID", integration_id)?;
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let transaction = (|| {
            let (task_id, state): (String, String) = self
                .conn
                .query_row(
                    "SELECT task_id, state FROM workspace_board_integrations WHERE id = ?1",
                    [&integration_id],
                    |row| Ok((row.get(0)?, row.get(1)?)),
                )
                .context("board integration does not exist")?;
            if state == "cancelled" {
                return Ok(false);
            }
            if state != "running" {
                bail!("board integration is not running");
            }
            let (state, detail) = match result {
                Ok(result) => ("completed", result.to_string()),
                Err(error) => ("failed", format!("Integration failed: {error:#}")),
            };
            self.conn.execute(
                "UPDATE workspace_board_integrations SET state = ?2, result = ?3 WHERE id = ?1",
                params![integration_id, state, detail],
            )?;
            self.append_board_timeline(&task_id, state, &detail)?;
            if state == "completed" {
                self.complete_board_task_in_transaction(&task_id, now())?;
            } else {
                self.block_board_task_in_transaction(&task_id, &detail, now())?;
            }
            Ok(true)
        })();
        self.finish_board_transaction(transaction)
    }

    pub fn recover_board_integrations(&self) -> Result<()> {
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            let task_ids = self
                .conn
                .prepare(
                    "SELECT task_id FROM workspace_board_integrations WHERE state = 'running'",
                )?
                .query_map([], |row| row.get::<_, String>(0))?
                .collect::<rusqlite::Result<Vec<_>>>()?;
            for task_id in task_ids {
                let detail = "Integration interrupted by worker restart";
                self.conn.execute(
                    "UPDATE workspace_board_integrations SET state = 'blocked', result = ?2 WHERE task_id = ?1 AND state = 'running'",
                    params![task_id, detail],
                )?;
                self.block_board_task_in_transaction(&task_id, detail, now())?;
            }
            Ok(())
        })();
        self.finish_board_transaction(result)
    }

    /// A worker restart cannot resume an in-flight task-agent turn safely.
    pub fn recover_board_task_workstreams(&self) -> Result<()> {
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            let task_ids = self.conn.prepare(
                "SELECT task.id
                 FROM workspace_board_tasks task
                 JOIN workspace_board_task_workstreams workstream ON workstream.task_id = task.id
                 WHERE task.state = 'running'
                    AND NOT EXISTS (
                        SELECT 1 FROM workspace_board_integrations integration
                        WHERE integration.task_id = task.id AND integration.state IN ('queued', 'running')
                    )",
            )?
            .query_map([], |row| row.get::<_, String>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
            for task_id in task_ids {
                self.block_board_task_in_transaction(
                    &task_id,
                    "Task worker interrupted by worker restart",
                    now(),
                )?;
            }
            Ok(())
        })();
        self.finish_board_transaction(result)
    }

    pub fn board_timeline(&self, task_id: &str) -> Result<Vec<WorkspaceBoardTimelineEntry>> {
        Ok(self.conn.prepare("SELECT id, task_id, state, detail, created_at FROM workspace_board_timeline WHERE task_id = ?1 ORDER BY created_at, rowid")?
            .query_map([required("board task ID", task_id)?], |row| Ok(WorkspaceBoardTimelineEntry { id: row.get(0)?, task_id: row.get(1)?, state: row.get(2)?, detail: row.get(3)?, created_at: row.get(4)? }))?
            .collect::<rusqlite::Result<_>>()?)
    }

    pub fn board_timeline_entries(&self) -> Result<Vec<WorkspaceBoardTimelineEntry>> {
        Ok(self.conn.prepare("SELECT id, task_id, state, detail, created_at FROM workspace_board_timeline ORDER BY created_at, rowid")?
            .query_map([], |row| Ok(WorkspaceBoardTimelineEntry { id: row.get(0)?, task_id: row.get(1)?, state: row.get(2)?, detail: row.get(3)?, created_at: row.get(4)? }))?
            .collect::<rusqlite::Result<_>>()?)
    }

    pub fn board_runs(&self, task_id: &str) -> Result<Vec<WorkspaceBoardRun>> {
        Ok(self.conn.prepare("SELECT id, task_id, scheduled_at, state, started_at, completed_at FROM workspace_board_runs WHERE task_id = ?1 ORDER BY scheduled_at, id")?
            .query_map([required("board task ID", task_id)?], board_run_from_row)?
            .collect::<rusqlite::Result<_>>()?)
    }

    pub fn board_columns(&self) -> Result<Vec<WorkspaceBoardColumn>> {
        Ok(self
            .conn
            .prepare("SELECT id, name, rank, wip_limit, archived_at FROM workspace_board_columns WHERE archived_at IS NULL ORDER BY rank, id")?
            .query_map([], |row| {
                Ok(WorkspaceBoardColumn {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    rank: row.get(2)?,
                    wip_limit: row.get(3)?,
                    archived_at: row.get(4)?,
                })
            })?
            .collect::<rusqlite::Result<_>>()?)
    }

    pub fn set_board_column_wip_limit(
        &self,
        column_id: &str,
        wip_limit: Option<i64>,
    ) -> Result<()> {
        let column_id = required("board column ID", column_id)?;
        if wip_limit.is_some_and(|limit| limit < 1) {
            bail!("board column WIP limit must be positive");
        }
        if self.conn.execute(
            "UPDATE workspace_board_columns SET wip_limit = ?2 WHERE id = ?1 AND archived_at IS NULL",
            params![column_id, wip_limit],
        )? != 1 {
            bail!("board column does not exist");
        }
        Ok(())
    }

    pub fn board_column_is_over_wip_limit(&self, column_id: &str) -> Result<bool> {
        self.conn.query_row(
            "SELECT wip_limit IS NOT NULL AND (SELECT COUNT(*) FROM workspace_board_cards WHERE column_id = workspace_board_columns.id AND archived_at IS NULL) > wip_limit FROM workspace_board_columns WHERE id = ?1 AND archived_at IS NULL",
            [required("board column ID", column_id)?],
            |row| row.get(0),
        ).optional()?.context("board column does not exist")
    }

    pub fn create_board_card(
        &self,
        created_by: &str,
        title: &str,
        description: &str,
        column_id: &str,
        priority: &str,
    ) -> Result<WorkspaceBoardCard> {
        self.create_board_card_with_source(
            created_by,
            title,
            description,
            column_id,
            priority,
            None,
        )
    }

    fn create_board_card_with_source(
        &self,
        created_by: &str,
        title: &str,
        description: &str,
        column_id: &str,
        priority: &str,
        source_thread_id: Option<&str>,
    ) -> Result<WorkspaceBoardCard> {
        let created_by = required("board card creator", created_by)?;
        let title = required("board card title", title)?;
        let column_id = required("board column ID", column_id)?;
        let priority = validate_board_card_priority(priority)?;
        let timestamp = now();
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            let column_exists: bool = self.conn.query_row(
                "SELECT EXISTS(SELECT 1 FROM workspace_board_columns WHERE id = ?1 AND archived_at IS NULL)",
                [&column_id],
                |row| row.get(0),
            )?;
            if !column_exists {
                bail!("board column does not exist");
            }
            let rank: i64 = self.conn.query_row(
                "SELECT COALESCE(MAX(rank), 0) + 1024 FROM workspace_board_cards WHERE column_id = ?1 AND archived_at IS NULL",
                [&column_id],
                |row| row.get(0),
            )?;
            let card = WorkspaceBoardCard {
                id: new_id(),
                title,
                description: description.trim().to_string(),
                column_id,
                rank,
                priority,
                estimate: None,
                due_at: None,
                created_by,
                created_at: timestamp,
                updated_at: timestamp,
                archived_at: None,
                source_thread_id: source_thread_id.map(str::to_string),
            };
            self.conn.execute(
                "INSERT INTO workspace_board_cards (id, title, description, column_id, rank, priority, created_by, created_at, updated_at, source_thread_id) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
                params![card.id, card.title, card.description, card.column_id, card.rank, card.priority, card.created_by, card.created_at, card.updated_at, card.source_thread_id],
            )?;
            self.append_board_card_activity_at(&card.id, "created", "Card created", timestamp)?;
            if source_thread_id.is_some() {
                self.append_board_card_activity_at(
                    &card.id,
                    "created_from_thread",
                    "Created from thread",
                    timestamp,
                )?;
            }
            Ok(card)
        })();
        self.finish_board_transaction(result)
    }

    pub fn create_board_card_from_thread(
        &self,
        root_id: &str,
        topic: &str,
    ) -> Result<Option<WorkspaceBoardCard>> {
        let root_id = required("thread root ID", root_id)?;
        let topic = required("thread topic", topic)?;
        let root = self
            .message_by_id(&root_id)?
            .context("thread root does not exist")?;
        if root.parent_id.is_some() || root.deleted_at.is_some() {
            bail!("thread root must be a live root message");
        }
        if let Some(card_id) = self
            .conn
            .query_row(
                "SELECT id FROM workspace_board_cards WHERE source_thread_id = ?1",
                [&root_id],
                |row| row.get::<_, String>(0),
            )
            .optional()?
        {
            let card = self
                .board_card(&card_id)?
                .context("thread card does not exist")?;
            if card.title != topic {
                self.conn.execute_batch("BEGIN IMMEDIATE")?;
                let result = (|| {
                    self.conn.execute("UPDATE workspace_board_cards SET title = ?2, updated_at = ?3 WHERE id = ?1", params![card_id, topic, now()])?;
                    self.append_board_card_activity(&card_id, "title_changed", &topic)
                })();
                self.finish_board_transaction(result)?;
            }
            return self.board_card(&card_id);
        }
        let replies = self.thread_messages(&root_id)?;
        let content_replies = replies
            .iter()
            .filter(|message| {
                let body = message.body.trim();
                message.parent_id.as_deref() == Some(root_id.as_str())
                    && message.deleted_at.is_none()
                    && !body.starts_with("[[THREAD_")
                    && !body.starts_with("[[RELATED_THREAD")
                    && (!body.is_empty() || !message.attachments.is_empty())
            })
            .count();
        if content_replies < 3 {
            return Ok(None);
        }
        let backlog = self
            .board_columns()?
            .into_iter()
            .find(|column| column.name == "Backlog")
            .context("Backlog board column is missing")?;
        self.create_board_card_with_source(
            &root.sender_pubkey,
            &topic,
            &root.body,
            &backlog.id,
            "none",
            Some(&root_id),
        )
        .map(Some)
    }

    pub fn board_cards(&self) -> Result<Vec<WorkspaceBoardCard>> {
        let ids = self.conn.prepare("SELECT id FROM workspace_board_cards WHERE archived_at IS NULL ORDER BY column_id, rank, id")?
            .query_map([], |row| row.get::<_, String>(0))?.collect::<rusqlite::Result<Vec<_>>>()?;
        ids.iter()
            .map(|id| self.board_card(id)?.context("board card disappeared"))
            .collect()
    }

    pub fn integrate_thread_board_card(&self, root_id: &str) -> Result<bool> {
        let Some(card) = self
            .board_cards()?
            .into_iter()
            .find(|card| card.source_thread_id.as_deref() == Some(root_id))
        else {
            return Ok(false);
        };
        self.conn.execute("INSERT OR IGNORE INTO workspace_board_columns (id, name, rank) VALUES (?1, 'Integrating', 4608)", [new_id()])?;
        let column = self
            .board_columns()?
            .into_iter()
            .find(|column| column.name == "Integrating")
            .context("Integrating board column is missing")?;
        if card.column_id == column.id {
            return Ok(false);
        }
        self.move_board_card(&card.id, &column.id, None)?;
        Ok(true)
    }

    pub fn can_read_board_card(&self, member: &str, card: &WorkspaceBoardCard) -> Result<bool> {
        if !self.is_member(member)? {
            return Ok(false);
        }
        let Some(root_id) = card.source_thread_id.as_deref() else {
            // A deleted source must not turn a formerly private card public.
            return Ok(!self.conn.query_row(
                "SELECT EXISTS(SELECT 1 FROM workspace_board_card_activity WHERE card_id = ?1 AND kind = 'created_from_thread')",
                [&card.id], |row| row.get::<_, bool>(0),
            )?);
        };
        let Some(root) = self.message_by_id(root_id)? else {
            return Ok(false);
        };
        if let Some(channel_id) = root.channel_id.as_deref() {
            self.is_channel_member(channel_id, member)
        } else {
            Ok(root.sender_pubkey == member || root.recipient_pubkey.as_deref() == Some(member))
        }
    }

    pub fn board_cards_for_member(&self, member: &str) -> Result<Vec<WorkspaceBoardCard>> {
        self.board_cards()?
            .into_iter()
            .filter_map(|card| match self.can_read_board_card(member, &card) {
                Ok(true) => Some(Ok(card)),
                Ok(false) => None,
                Err(error) => Some(Err(error)),
            })
            .collect()
    }

    pub fn move_board_card(
        &self,
        card_id: &str,
        column_id: &str,
        before_card_id: Option<&str>,
    ) -> Result<()> {
        let card_id = required("board card ID", card_id)?;
        let column_id = required("board column ID", column_id)?;
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            let card = self
                .board_card(&card_id)?
                .context("board card does not exist")?;
            let column_exists: bool = self.conn.query_row(
                "SELECT EXISTS(SELECT 1 FROM workspace_board_columns WHERE id = ?1 AND archived_at IS NULL)",
                [&column_id],
                |row| row.get(0),
            )?;
            if !column_exists {
                bail!("board column does not exist");
            }
            let rank = if let Some(before_card_id) = before_card_id {
                let before_rank: i64 = self.conn.query_row(
                    "SELECT rank FROM workspace_board_cards WHERE id = ?1 AND column_id = ?2 AND archived_at IS NULL",
                    params![required("before board card ID", before_card_id)?, column_id],
                    |row| row.get(0),
                )?;
                let previous_rank: i64 = self.conn.query_row(
                    "SELECT COALESCE(MAX(rank), 0) FROM workspace_board_cards WHERE column_id = ?1 AND archived_at IS NULL AND id != ?2 AND rank < ?3",
                    params![column_id, card_id, before_rank],
                    |row| row.get(0),
                )?;
                (previous_rank + before_rank) / 2
            } else {
                self.conn.query_row(
                    "SELECT COALESCE(MAX(rank), 0) + 1024 FROM workspace_board_cards WHERE column_id = ?1 AND archived_at IS NULL AND id != ?2",
                    params![column_id, card_id],
                    |row| row.get(0),
                )?
            };
            self.conn.execute(
                "UPDATE workspace_board_cards SET column_id = ?2, rank = ?3, updated_at = ?4 WHERE id = ?1 AND archived_at IS NULL",
                params![card_id, column_id, rank, now()],
            )?;
            self.append_board_card_activity(
                &card_id,
                "moved",
                &format!("Moved from {}", card.column_id),
            )
        })();
        self.finish_board_transaction(result)
    }

    pub fn set_board_card_metadata(
        &self,
        card_id: &str,
        priority: &str,
        estimate: Option<i64>,
        due_at: Option<i64>,
    ) -> Result<()> {
        let card_id = required("board card ID", card_id)?;
        let priority = validate_board_card_priority(priority)?;
        if estimate.is_some_and(|estimate| estimate < 0) {
            bail!("board card estimate cannot be negative");
        }
        if self.conn.execute(
            "UPDATE workspace_board_cards SET priority = ?2, estimate = ?3, due_at = ?4, updated_at = ?5 WHERE id = ?1 AND archived_at IS NULL",
            params![card_id, priority, estimate, due_at, now()],
        )? != 1 {
            bail!("board card does not exist");
        }
        self.append_board_card_activity(&card_id, "updated", "Planning metadata updated")
    }

    pub fn archive_board_card(&self, card_id: &str) -> Result<()> {
        self.set_board_card_archive_state(card_id, Some(now()), "archived", "Card archived")
    }

    pub fn restore_board_card(&self, card_id: &str) -> Result<()> {
        self.set_board_card_archive_state(card_id, None, "restored", "Card restored")
    }

    fn set_board_card_archive_state(
        &self,
        card_id: &str,
        archived_at: Option<i64>,
        kind: &str,
        detail: &str,
    ) -> Result<()> {
        let card_id = required("board card ID", card_id)?;
        if self.conn.execute(
            "UPDATE workspace_board_cards SET archived_at = ?2, updated_at = ?3 WHERE id = ?1",
            params![card_id, archived_at, now()],
        )? != 1
        {
            bail!("board card does not exist");
        }
        self.append_board_card_activity(&card_id, kind, detail)
    }

    pub fn create_board_label(&self, name: &str, color: &str) -> Result<WorkspaceBoardLabel> {
        let label = WorkspaceBoardLabel {
            id: new_id(),
            name: required("board label name", name)?,
            color: required("board label color", color)?,
        };
        self.conn.execute(
            "INSERT INTO workspace_board_labels (id, name, color) VALUES (?1, ?2, ?3)",
            params![label.id, label.name, label.color],
        )?;
        Ok(label)
    }

    pub fn set_board_card_assignees(&self, card_id: &str, assignees: &[String]) -> Result<()> {
        self.replace_board_card_relation(
            card_id,
            "workspace_board_card_assignees",
            "assignee_id",
            assignees,
        )
    }

    pub fn set_board_card_labels(&self, card_id: &str, labels: &[String]) -> Result<()> {
        self.replace_board_card_relation(card_id, "workspace_board_card_labels", "label_id", labels)
    }

    pub fn set_board_card_dependencies(
        &self,
        card_id: &str,
        dependencies: &[String],
    ) -> Result<()> {
        if dependencies.iter().any(|dependency| dependency == card_id) {
            bail!("board card cannot depend on itself");
        }
        self.replace_board_card_relation(
            card_id,
            "workspace_board_card_dependencies",
            "depends_on_card_id",
            dependencies,
        )
    }

    pub fn board_card_assignees(&self, card_id: &str) -> Result<Vec<String>> {
        self.board_card_relation(card_id, "workspace_board_card_assignees", "assignee_id")
    }
    pub fn board_card_labels(&self, card_id: &str) -> Result<Vec<String>> {
        self.board_card_relation(card_id, "workspace_board_card_labels", "label_id")
    }
    pub fn board_card_dependencies(&self, card_id: &str) -> Result<Vec<String>> {
        self.board_card_relation(
            card_id,
            "workspace_board_card_dependencies",
            "depends_on_card_id",
        )
    }

    fn replace_board_card_relation(
        &self,
        card_id: &str,
        table: &str,
        field: &str,
        values: &[String],
    ) -> Result<()> {
        let card_id = required("board card ID", card_id)?;
        if self.board_card(&card_id)?.is_none() {
            bail!("board card does not exist");
        }
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            self.conn.execute(
                &format!("DELETE FROM {table} WHERE card_id = ?1"),
                [&card_id],
            )?;
            for value in values {
                self.conn.execute(
                    &format!("INSERT INTO {table} (card_id, {field}) VALUES (?1, ?2)"),
                    params![card_id, required("board card relation", value)?],
                )?;
            }
            self.append_board_card_activity(&card_id, "updated", "Card relations updated")
        })();
        self.finish_board_transaction(result)
    }

    fn board_card_relation(&self, card_id: &str, table: &str, field: &str) -> Result<Vec<String>> {
        Ok(self
            .conn
            .prepare(&format!(
                "SELECT {field} FROM {table} WHERE card_id = ?1 ORDER BY {field}"
            ))?
            .query_map([required("board card ID", card_id)?], |row| row.get(0))?
            .collect::<rusqlite::Result<_>>()?)
    }

    pub fn board_card(&self, card_id: &str) -> Result<Option<WorkspaceBoardCard>> {
        self.conn
            .query_row(
                "SELECT id, title, description, column_id, rank, priority, estimate, due_at, created_by, created_at, updated_at, archived_at, source_thread_id FROM workspace_board_cards WHERE id = ?1",
                [required("board card ID", card_id)?],
                |row| {
                    Ok(WorkspaceBoardCard {
                        id: row.get(0)?,
                        title: row.get(1)?,
                        description: row.get(2)?,
                        column_id: row.get(3)?,
                    rank: row.get(4)?,
                    priority: row.get(5)?,
                    estimate: row.get(6)?,
                    due_at: row.get(7)?,
                    created_by: row.get(8)?,
                    created_at: row.get(9)?,
                    updated_at: row.get(10)?,
                    archived_at: row.get(11)?,
                    source_thread_id: row.get(12)?,
                    })
                },
            )
            .optional()
            .map_err(Into::into)
    }

    pub fn board_card_activity(&self, card_id: &str) -> Result<Vec<WorkspaceBoardCardActivity>> {
        Ok(self
            .conn
            .prepare("SELECT id, card_id, kind, detail, created_at FROM workspace_board_card_activity WHERE card_id = ?1 ORDER BY created_at, rowid")?
            .query_map([required("board card ID", card_id)?], |row| {
                Ok(WorkspaceBoardCardActivity {
                    id: row.get(0)?,
                    card_id: row.get(1)?,
                    kind: row.get(2)?,
                    detail: row.get(3)?,
                    created_at: row.get(4)?,
                })
            })?
            .collect::<rusqlite::Result<_>>()?)
    }

    fn append_board_card_activity(&self, card_id: &str, kind: &str, detail: &str) -> Result<()> {
        self.append_board_card_activity_at(card_id, kind, detail, now())
    }

    fn append_board_card_activity_at(
        &self,
        card_id: &str,
        kind: &str,
        detail: &str,
        created_at: i64,
    ) -> Result<()> {
        self.conn.execute(
            "INSERT INTO workspace_board_card_activity (id, card_id, kind, detail, created_at) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![new_id(), required("board card ID", card_id)?, required("board activity kind", kind)?, required("board activity detail", detail)?, created_at],
        )?;
        Ok(())
    }

    fn ensure_board_card_column(&self, name: &str, definition: &str) -> Result<()> {
        let columns = self
            .conn
            .prepare("PRAGMA table_info(workspace_board_cards)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        if !columns.iter().any(|column| column == name) {
            self.conn.execute(
                &format!("ALTER TABLE workspace_board_cards ADD COLUMN {name} {definition}"),
                [],
            )?;
        }
        Ok(())
    }

    pub fn update_board_task(
        &self,
        task_id: &str,
        title: &str,
        conversation_key: &str,
        instruction: &str,
        folder_scope: &[String],
        schedule: &str,
        next_run_at: i64,
    ) -> Result<()> {
        let task_id = required("board task ID", task_id)?;
        let title = required("board task title", title)?;
        let conversation_key = required("board task conversation", conversation_key)?;
        let instruction = required("board task instruction", instruction)?;
        validate_board_schedule(schedule)?;
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            let existing = self
                .board_task(&task_id)?
                .context("board task does not exist")?;
            if self.board_task_workstream(&task_id)?.is_some()
                && (existing.conversation_key != conversation_key
                    || existing.folder_scope != folder_scope)
            {
                bail!("linked board task target and scope cannot be changed");
            }
            if self.conn.execute(
                "UPDATE workspace_board_tasks SET title = ?2, conversation_key = ?3, instruction = ?4, folder_scope_json = ?5, schedule = ?6, state = 'scheduled', next_run_at = ?7, updated_at = ?8 WHERE id = ?1 AND state IN ('scheduled', 'blocked', 'done')",
                params![task_id, title, conversation_key, instruction, serde_json::to_string(folder_scope)?, schedule.trim(), next_run_at, now()],
            )? != 1 {
                bail!("board task cannot be updated in its current state");
            }
            self.append_board_timeline(&task_id, "scheduled", "Task updated")
        })();
        self.finish_board_transaction(result)
    }

    pub fn cancel_board_task(&self, task_id: &str) -> Result<()> {
        let task_id = required("board task ID", task_id)?;
        let timestamp = now();
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            let task = self
                .board_task(&task_id)?
                .context("board task does not exist")?;
            if !["scheduled", "queued", "running", "blocked"].contains(&task.state.as_str()) {
                bail!("board task cannot transition from {}", task.state);
            }
            self.cancel_board_integrations(&task_id)?;
            self.conn.execute(
                "UPDATE workspace_board_runs SET state = 'cancelled', completed_at = ?2 WHERE task_id = ?1 AND state IN ('queued', 'running')",
                params![task_id, timestamp],
            )?;
            self.conn.execute(
                "UPDATE workspace_board_tasks SET state = 'cancelled', next_run_at = NULL, updated_at = ?2 WHERE id = ?1",
                params![task_id, timestamp],
            )?;
            self.append_board_timeline_at(&task_id, "cancelled", "Task cancelled", timestamp)
        })();
        self.finish_board_transaction(result)
    }

    pub fn retry_board_task(&self, task_id: &str, next_run_at: i64) -> Result<()> {
        let task_id = required("board task ID", task_id)?;
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            if self.conn.execute(
                "UPDATE workspace_board_tasks SET state = 'scheduled', next_run_at = ?2, updated_at = ?3 WHERE id = ?1 AND state = 'blocked'",
                params![task_id, next_run_at, now()],
            )? != 1 {
                bail!("only blocked board tasks can be retried");
            }
            self.append_board_timeline(&task_id, "scheduled", "Task retried")
        })();
        self.finish_board_transaction(result)
    }

    /// Claims the exact persisted schedule slot and makes it ready for a worker.
    pub fn queue_board_task(
        &self,
        task_id: &str,
        claimed_at: i64,
    ) -> Result<Option<WorkspaceBoardTask>> {
        self.claim_due_board_task(task_id, claimed_at)
    }

    pub fn claim_due_board_task(
        &self,
        task_id: &str,
        scheduled_at: i64,
    ) -> Result<Option<WorkspaceBoardTask>> {
        let task_id = required("board task ID", task_id)?;
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            let Some(task) = self.board_task(&task_id)? else {
                return Ok(None);
            };
            let Some(run_at) = task.next_run_at else {
                return Ok(None);
            };
            if task.state != "scheduled" || run_at > scheduled_at {
                return Ok(None);
            }
            if self.conn.execute(
                "INSERT OR IGNORE INTO workspace_board_runs (id, task_id, scheduled_at, state) VALUES (?1, ?2, ?3, 'queued')",
                params![new_id(), task_id, run_at],
            )? != 1 {
                return Ok(None);
            }
            self.conn.execute(
                "UPDATE workspace_board_tasks SET state = 'queued', updated_at = ?2 WHERE id = ?1",
                params![task_id, scheduled_at],
            )?;
            self.append_board_timeline_at(&task_id, "queued", "Task queued", scheduled_at)?;
            Ok(self.board_task(&task_id)?)
        })();
        self.finish_board_transaction(result)
    }

    pub fn start_board_task(&self, task_id: &str, started_at: i64) -> Result<()> {
        self.transition_board_task(
            task_id,
            &["queued"],
            "running",
            "Task started",
            Some(("running", started_at)),
        )
    }

    pub fn complete_board_task(&self, task_id: &str, completed_at: i64) -> Result<()> {
        let task_id = required("board task ID", task_id)?;
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| self.complete_board_task_in_transaction(&task_id, completed_at))();
        self.finish_board_transaction(result)
    }

    pub fn block_board_task(&self, task_id: &str, detail: &str) -> Result<()> {
        self.transition_board_task(
            task_id,
            &["queued", "running"],
            "blocked",
            detail,
            Some(("blocked", now())),
        )
    }

    pub fn block_scheduled_board_task(&self, task_id: &str, detail: &str) -> Result<()> {
        let task_id = required("board task ID", task_id)?;
        let detail = required("board task detail", detail)?;
        let timestamp = now();
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            if self.conn.execute(
                "UPDATE workspace_board_tasks SET state = 'blocked', updated_at = ?2 WHERE id = ?1 AND state = 'scheduled'",
                params![task_id, timestamp],
            )? != 1 {
                bail!("scheduled board task cannot be blocked");
            }
            self.append_board_timeline_at(&task_id, "blocked", &detail, timestamp)
        })();
        self.finish_board_transaction(result)
    }

    fn complete_board_task_in_transaction(&self, task_id: &str, completed_at: i64) -> Result<()> {
        let task = self
            .board_task(task_id)?
            .context("board task does not exist")?;
        if task.state != "running" {
            bail!("only running board tasks can be completed");
        }
        let scheduled_at: i64 = self.conn.query_row(
            "SELECT scheduled_at FROM workspace_board_runs WHERE task_id = ?1 AND state = 'running' ORDER BY scheduled_at DESC LIMIT 1",
            [task_id], |row| row.get(0),
        ).context("running board task has no running run")?;
        let next_run_at = next_board_run_at(&task.schedule, scheduled_at)?;
        let state = if next_run_at.is_some() {
            "scheduled"
        } else {
            "done"
        };
        self.conn.execute(
            "UPDATE workspace_board_runs SET state = 'completed', completed_at = ?2 WHERE task_id = ?1 AND state = 'running'",
            params![task_id, completed_at],
        )?;
        self.conn.execute(
            "UPDATE workspace_board_tasks SET state = ?2, next_run_at = ?3, updated_at = ?4 WHERE id = ?1",
            params![task_id, state, next_run_at, completed_at],
        )?;
        self.append_board_timeline_at(task_id, state, "Task completed", completed_at)
    }

    fn block_board_task_in_transaction(
        &self,
        task_id: &str,
        detail: &str,
        timestamp: i64,
    ) -> Result<()> {
        let task = self
            .board_task(task_id)?
            .context("board task does not exist")?;
        if task.state == "cancelled" {
            return Ok(());
        }
        if !["queued", "running", "blocked"].contains(&task.state.as_str()) {
            bail!("board task cannot transition from {}", task.state);
        }
        self.conn.execute(
            "UPDATE workspace_board_runs SET state = 'blocked', completed_at = ?2 WHERE task_id = ?1 AND state IN ('queued', 'running')",
            params![task_id, timestamp],
        )?;
        self.conn.execute(
            "UPDATE workspace_board_tasks SET state = 'blocked', updated_at = ?2 WHERE id = ?1",
            params![task_id, timestamp],
        )?;
        self.append_board_timeline_at(task_id, "blocked", detail, timestamp)
    }

    fn board_task(&self, task_id: &str) -> Result<Option<WorkspaceBoardTask>> {
        self.conn.query_row(
            "SELECT id, title, conversation_key, instruction, folder_scope_json, schedule, state, board_column, next_run_at, created_by, created_at, updated_at, NULL, NULL FROM workspace_board_tasks WHERE id = ?1",
            [task_id], board_task_from_row,
        ).optional().map_err(Into::into)
    }

    fn transition_board_task(
        &self,
        task_id: &str,
        from: &[&str],
        state: &str,
        detail: &str,
        run_update: Option<(&str, i64)>,
    ) -> Result<()> {
        let task_id = required("board task ID", task_id)?;
        let detail = required("board task detail", detail)?;
        let timestamp = now();
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            let task = self
                .board_task(&task_id)?
                .context("board task does not exist")?;
            if !from.contains(&task.state.as_str()) {
                bail!("board task cannot transition from {}", task.state);
            }
            if let Some((run_state, run_timestamp)) = run_update {
                if self.conn.execute(
                    "UPDATE workspace_board_runs SET state = ?2, started_at = CASE WHEN ?2 = 'running' THEN ?3 ELSE started_at END, completed_at = CASE WHEN ?2 = 'blocked' THEN ?3 ELSE completed_at END WHERE task_id = ?1 AND state = ?4",
                    params![task_id, run_state, run_timestamp, task.state],
                )? != 1 {
                    bail!("board task has no active run");
                }
            } else if state == "cancelled" {
                self.conn.execute(
                    "UPDATE workspace_board_runs SET state = 'cancelled', completed_at = ?2 WHERE task_id = ?1 AND state = 'queued'",
                    params![task_id, timestamp],
                )?;
            }
            if self.conn.execute(
                "UPDATE workspace_board_tasks SET state = ?2, next_run_at = CASE WHEN ?2 = 'cancelled' THEN NULL ELSE next_run_at END, updated_at = ?3 WHERE id = ?1",
                params![task_id, state, timestamp],
            )? != 1 {
                bail!("board task does not exist");
            }
            self.append_board_timeline_at(&task_id, state, &detail, timestamp)
        })();
        self.finish_board_transaction(result)
    }

    fn finish_board_transaction<T>(&self, result: Result<T>) -> Result<T> {
        if result.is_ok() {
            self.conn.execute_batch("COMMIT")?;
        } else {
            self.conn.execute_batch("ROLLBACK")?;
        }
        result
    }

    fn append_board_timeline(&self, task_id: &str, state: &str, detail: &str) -> Result<()> {
        self.append_board_timeline_at(task_id, state, detail, now())
    }

    fn append_board_timeline_at(
        &self,
        task_id: &str,
        state: &str,
        detail: &str,
        created_at: i64,
    ) -> Result<()> {
        self.conn.execute(
            "INSERT INTO workspace_board_timeline (id, task_id, state, detail, created_at) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![new_id(), task_id, state, detail, created_at],
        )?;
        Ok(())
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

    pub fn queue_agent_handoffs(
        &self,
        reply_message_id: &str,
        mentions: &[WorkspaceMentionPayload],
    ) -> Result<Vec<WorkspaceAgentHandoffOutboxEntry>> {
        let reply_message_id = required("agent handoff reply message ID", reply_message_id)?;
        let mut handoffs = Vec::new();
        for mention in mentions.iter().filter(|mention| mention.kind == "agent") {
            let agent_id = required("agent handoff target", &mention.id)?;
            if self.conn.execute(
                "INSERT OR IGNORE INTO workspace_agent_handoff_outbox (reply_message_id, agent_id) VALUES (?1, ?2)",
                params![reply_message_id, agent_id],
            )? > 0 {
                handoffs.push(WorkspaceAgentHandoffOutboxEntry {
                    reply_message_id: reply_message_id.clone(),
                    agent_id,
                    member_pubkey: None,
                    peer_pubkey: None,
                });
            }
        }
        Ok(handoffs)
    }

    pub fn pending_agent_handoffs(&self) -> Result<Vec<WorkspaceAgentHandoffOutboxEntry>> {
        Ok(self
            .conn
            .prepare(
                "SELECT reply_message_id, agent_id, member_pubkey, peer_pubkey FROM workspace_agent_handoff_outbox ORDER BY rowid",
            )?
            .query_map([], |row| {
                Ok(WorkspaceAgentHandoffOutboxEntry {
                    reply_message_id: row.get(0)?,
                    agent_id: row.get(1)?,
                    member_pubkey: row.get(2)?,
                    peer_pubkey: row.get(3)?,
                })
            })?
            .collect::<rusqlite::Result<_>>()?)
    }

    pub fn delivered_agent_handoff(&self, reply_message_id: &str, agent_id: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM workspace_agent_handoff_outbox WHERE reply_message_id = ?1 AND agent_id = ?2",
            params![
                required("agent handoff reply message ID", reply_message_id)?,
                required("agent handoff target", agent_id)?
            ],
        )?;
        Ok(())
    }

    pub fn add_channel_agent_reply_with_handoffs(
        &self,
        sender: &str,
        channel_id: &str,
        body: &str,
        mentions: &[WorkspaceMentionPayload],
        parent_id: Option<&str>,
        also_send_to_main: bool,
        incoming_handoff: Option<&(String, String)>,
    ) -> Result<(WorkspaceMessage, Vec<WorkspaceAgentHandoffOutboxEntry>)> {
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            let message = self.add_channel_message_with_main(
                sender,
                channel_id,
                body,
                &[],
                mentions,
                parent_id,
                also_send_to_main,
            )?;
            let handoffs = self.queue_agent_handoffs(&message.id, mentions)?;
            if let Some((reply_id, agent_id)) = incoming_handoff {
                self.delivered_agent_handoff(reply_id, agent_id)?;
            }
            Ok((message, handoffs))
        })();
        match result {
            Ok(result) => {
                self.conn.execute_batch("COMMIT")?;
                Ok(result)
            }
            Err(error) => {
                self.conn.execute_batch("ROLLBACK")?;
                Err(error)
            }
        }
    }

    pub fn add_direct_agent_reply_with_handoffs(
        &self,
        sender: &str,
        recipient: &str,
        body: &str,
        mentions: &[WorkspaceMentionPayload],
        parent_id: Option<&str>,
        also_send_to_main: bool,
        member_pubkey: &str,
        peer_pubkey: &str,
        incoming_handoff: Option<&(String, String)>,
    ) -> Result<(WorkspaceMessage, Vec<WorkspaceAgentHandoffOutboxEntry>)> {
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            let message = self.add_direct_message_with_main(
                sender,
                recipient,
                body,
                &[],
                mentions,
                parent_id,
                also_send_to_main,
            )?;
            let handoffs = self.queue_direct_agent_handoffs(
                &message.id,
                mentions,
                member_pubkey,
                peer_pubkey,
            )?;
            if let Some((reply_id, agent_id)) = incoming_handoff {
                self.delivered_agent_handoff(reply_id, agent_id)?;
            }
            Ok((message, handoffs))
        })();
        match result {
            Ok(result) => {
                self.conn.execute_batch("COMMIT")?;
                Ok(result)
            }
            Err(error) => {
                self.conn.execute_batch("ROLLBACK")?;
                Err(error)
            }
        }
    }

    fn queue_direct_agent_handoffs(
        &self,
        reply_message_id: &str,
        mentions: &[WorkspaceMentionPayload],
        member_pubkey: &str,
        peer_pubkey: &str,
    ) -> Result<Vec<WorkspaceAgentHandoffOutboxEntry>> {
        let reply_message_id = required("agent handoff reply message ID", reply_message_id)?;
        let member_pubkey = required("direct handoff member", member_pubkey)?;
        let peer_pubkey = required("direct handoff peer", peer_pubkey)?;
        let mut handoffs = Vec::new();
        for mention in mentions.iter().filter(|mention| mention.kind == "agent") {
            let agent_id = required("agent handoff target", &mention.id)?;
            if self.conn.execute(
                "INSERT OR IGNORE INTO workspace_agent_handoff_outbox (reply_message_id, agent_id, member_pubkey, peer_pubkey) VALUES (?1, ?2, ?3, ?4)",
                params![reply_message_id, agent_id, member_pubkey, peer_pubkey],
            )? > 0 {
                handoffs.push(WorkspaceAgentHandoffOutboxEntry {
                    reply_message_id: reply_message_id.clone(),
                    agent_id,
                    member_pubkey: Some(member_pubkey.clone()),
                    peer_pubkey: Some(peer_pubkey.clone()),
                });
            }
        }
        Ok(handoffs)
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
            "SELECT pubkey, display_name, is_admin, joined_at FROM workspace_members ORDER BY joined_at, pubkey",
        )?;
        let members = statement
            .query_map([], |row| {
                Ok(WorkspaceMember {
                    pubkey: row.get(0)?,
                    display_name: row.get(1)?,
                    is_admin: row.get(2)?,
                    joined_at: row.get(3)?,
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
        let joined_at = self.conn.query_row(
            "SELECT joined_at FROM workspace_members WHERE pubkey = ?1",
            [&pubkey],
            |row| row.get(0),
        )?;
        Ok(WorkspaceMember {
            pubkey,
            display_name: display_name.to_string(),
            is_admin,
            joined_at,
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
        let (display_name, joined_at) = self.conn.query_row(
            "SELECT display_name, joined_at FROM workspace_members WHERE pubkey = ?1",
            [&pubkey],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )?;
        Ok(WorkspaceMember {
            pubkey,
            display_name,
            is_admin,
            joined_at,
        })
    }

    pub fn remove_member(&self, pubkey: &str) -> Result<()> {
        let pubkey = required("member pubkey", pubkey)?;
        self.conn.execute(
            "DELETE FROM workspace_channel_members WHERE pubkey = ?1",
            [&pubkey],
        )?;
        if self
            .conn
            .execute("DELETE FROM workspace_members WHERE pubkey = ?1", [&pubkey])?
            == 0
        {
            bail!("member is not a workspace member");
        }
        Ok(())
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
        let transaction = self.conn.unchecked_transaction()?;
        transaction.execute("INSERT INTO workspace_channels (id, name, created_by, created_at) VALUES (?1, ?2, ?3, ?4)", params![channel.id, channel.name, channel.created_by, channel.created_at])?;
        transaction.execute(
            "INSERT INTO workspace_channel_members (channel_id, pubkey, is_admin, joined_at) VALUES (?1, ?2, 1, ?3)",
            params![channel.id, channel.created_by, channel.created_at],
        )?;
        transaction.commit()?;
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

    pub fn channels_for_member(&self, pubkey: &str) -> Result<Vec<WorkspaceChannel>> {
        let mut statement = self.conn.prepare("SELECT c.id, c.name, c.created_by, c.created_at FROM workspace_channels c JOIN workspace_channel_members cm ON cm.channel_id = c.id WHERE cm.pubkey = ?1 ORDER BY c.created_at, c.name")?;
        let channels = statement
            .query_map([required("member pubkey", pubkey)?], channel_from_row)?
            .collect::<rusqlite::Result<_>>()?;
        Ok(channels)
    }

    pub fn channel_members(&self, channel_id: &str) -> Result<Vec<WorkspaceChannelMember>> {
        self.require_channel(channel_id)?;
        let mut statement = self.conn.prepare("SELECT pubkey, is_admin FROM workspace_channel_members WHERE channel_id = ?1 ORDER BY joined_at, pubkey")?;
        let members = statement
            .query_map([channel_id], |row| {
                Ok(WorkspaceChannelMember {
                    pubkey: row.get(0)?,
                    is_admin: row.get(1)?,
                })
            })?
            .collect::<rusqlite::Result<_>>()?;
        Ok(members)
    }

    pub fn is_channel_member(&self, channel_id: &str, pubkey: &str) -> Result<bool> {
        Ok(self.conn.query_row("SELECT EXISTS(SELECT 1 FROM workspace_channel_members WHERE channel_id = ?1 AND pubkey = ?2)", params![channel_id.trim(), pubkey.trim()], |row| row.get(0))?)
    }

    pub fn is_channel_admin(&self, channel_id: &str, pubkey: &str) -> Result<bool> {
        Ok(self.conn.query_row("SELECT EXISTS(SELECT 1 FROM workspace_channel_members WHERE channel_id = ?1 AND pubkey = ?2 AND is_admin = 1)", params![channel_id.trim(), pubkey.trim()], |row| row.get(0))?)
    }

    pub fn add_channel_member(&self, channel_id: &str, pubkey: &str) -> Result<()> {
        let channel_id = required("channel id", channel_id)?;
        let pubkey = required("member pubkey", pubkey)?;
        self.require_channel(&channel_id)?;
        if !self.is_member(&pubkey)? {
            bail!("member is not a workspace member");
        }
        self.conn.execute("INSERT OR IGNORE INTO workspace_channel_members (channel_id, pubkey, joined_at) VALUES (?1, ?2, ?3)", params![channel_id, pubkey, now()])?;
        Ok(())
    }

    pub fn remove_channel_member(
        &self,
        channel_id: &str,
        pubkey: &str,
        replacement_admin: &str,
    ) -> Result<()> {
        let channel_id = required("channel id", channel_id)?;
        let pubkey = required("member pubkey", pubkey)?;
        let replacement_admin = required("replacement admin", replacement_admin)?;
        let created_by: String = self.conn.query_row(
            "SELECT created_by FROM workspace_channels WHERE id = ?1",
            [&channel_id],
            |row| row.get(0),
        )?;
        if pubkey == created_by {
            if pubkey == replacement_admin {
                bail!("the conversation creator cannot remove themselves");
            }
            let transaction = self.conn.unchecked_transaction()?;
            transaction.execute(
                "UPDATE workspace_channels SET created_by = ?2 WHERE id = ?1",
                params![channel_id, replacement_admin],
            )?;
            transaction.execute(
                "INSERT INTO workspace_channel_members (channel_id, pubkey, is_admin, joined_at) VALUES (?1, ?2, 1, ?3) ON CONFLICT(channel_id, pubkey) DO UPDATE SET is_admin = 1",
                params![channel_id, replacement_admin, now()],
            )?;
            transaction.execute(
                "DELETE FROM workspace_channel_members WHERE channel_id = ?1 AND pubkey = ?2",
                params![channel_id, pubkey],
            )?;
            transaction.commit()?;
            return Ok(());
        }
        if self.conn.execute(
            "DELETE FROM workspace_channel_members WHERE channel_id = ?1 AND pubkey = ?2",
            params![channel_id, pubkey],
        )? == 0
        {
            bail!("member is not in this channel");
        }
        Ok(())
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
        let agent_ids = self.conversation_agent_ids("channel_id = ?1", [channel_id])?;
        let coordinator_ids = self.conversation_coordinator_ids("channel_id = ?1", [channel_id])?;
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
            "DELETE FROM workspace_conversation_coordinators WHERE channel_id = ?1",
            [channel_id],
        )?;
        self.conn.execute(
            "DELETE FROM workspace_conversation_round_robin WHERE channel_id = ?1",
            [channel_id],
        )?;
        self.conn.execute(
            "DELETE FROM workspace_conversation_preprompts WHERE channel_id = ?1",
            [channel_id],
        )?;
        self.conn.execute(
            "DELETE FROM workspace_channel_members WHERE channel_id = ?1",
            [channel_id],
        )?;
        self.conn
            .execute("DELETE FROM workspace_channels WHERE id = ?1", [channel_id])?;
        self.delete_unassigned_agents(&agent_ids)?;
        self.delete_unassigned_agents(&coordinator_ids)?;
        Ok(())
    }

    pub fn delete_direct_conversation(&self, member: &str, peer: &str) -> Result<()> {
        let (member, peer) = direct_participants(member, peer)?;
        let agent_ids = self.conversation_agent_ids(
            "member_pubkey = ?1 AND peer_pubkey = ?2",
            params![&member, &peer],
        )?;
        let coordinator_ids = self.conversation_coordinator_ids(
            "member_pubkey = ?1 AND peer_pubkey = ?2",
            params![&member, &peer],
        )?;
        self.conn.execute(
            "DELETE FROM workspace_message_reactions WHERE message_id IN (SELECT id FROM workspace_messages WHERE channel_id IS NULL AND ((sender_pubkey = ?1 AND recipient_pubkey = ?2) OR (sender_pubkey = ?2 AND recipient_pubkey = ?1)))",
            params![member, peer],
        )?;
        self.conn.execute(
            "DELETE FROM workspace_messages WHERE channel_id IS NULL AND ((sender_pubkey = ?1 AND recipient_pubkey = ?2) OR (sender_pubkey = ?2 AND recipient_pubkey = ?1))",
            params![member, peer],
        )?;
        self.conn.execute("DELETE FROM workspace_conversation_agents WHERE member_pubkey = ?1 AND peer_pubkey = ?2", params![member, peer])?;
        self.conn.execute("DELETE FROM workspace_conversation_coordinators WHERE member_pubkey = ?1 AND peer_pubkey = ?2", params![member, peer])?;
        self.conn.execute("DELETE FROM workspace_conversation_round_robin WHERE member_pubkey = ?1 AND peer_pubkey = ?2", params![member, peer])?;
        self.conn.execute("DELETE FROM workspace_conversation_preprompts WHERE member_pubkey = ?1 AND peer_pubkey = ?2", params![member, peer])?;
        self.delete_unassigned_agents(&agent_ids)?;
        self.delete_unassigned_agents(&coordinator_ids)?;
        Ok(())
    }

    fn conversation_agent_ids<P>(&self, predicate: &str, params: P) -> Result<Vec<String>>
    where
        P: rusqlite::Params,
    {
        let sql = format!("SELECT agent_id FROM workspace_conversation_agents WHERE {predicate}");
        Ok(self
            .conn
            .prepare(&sql)?
            .query_map(params, |row| row.get(0))?
            .collect::<rusqlite::Result<_>>()?)
    }

    fn conversation_coordinator_ids<P>(&self, predicate: &str, params: P) -> Result<Vec<String>>
    where
        P: rusqlite::Params,
    {
        let sql =
            format!("SELECT agent_id FROM workspace_conversation_coordinators WHERE {predicate}");
        Ok(self
            .conn
            .prepare(&sql)?
            .query_map(params, |row| row.get(0))?
            .collect::<rusqlite::Result<_>>()?)
    }

    fn delete_unassigned_agents(&self, agent_ids: &[String]) -> Result<()> {
        for agent_id in agent_ids {
            let assigned = self.conn.query_row(
                "SELECT EXISTS(SELECT 1 FROM workspace_conversation_agents WHERE agent_id = ?1) OR EXISTS(SELECT 1 FROM workspace_conversation_coordinators WHERE agent_id = ?1)",
                [agent_id],
                |row| row.get::<_, bool>(0),
            )?;
            if assigned {
                continue;
            }
            self.conn.execute(
                "DELETE FROM workspace_agent_instances WHERE agent_id = ?1",
                [agent_id],
            )?;
            self.conn
                .execute("DELETE FROM workspace_agents WHERE id = ?1", [agent_id])?;
        }
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
            session_context: None,
            instance_id: new_id(),
            created_by: required("creator", created_by)?,
            created_at: now(),
            initialized_at: (session_status == "ready" && opencode_session_id.is_some()).then(now),
            input_tokens: None,
            output_tokens: None,
        };
        self.conn.execute("INSERT INTO workspace_agents (id, name, role, traits, skills_json, preset, opencode_provider_id, opencode_provider_name, opencode_model_id, opencode_model_name, opencode_agent, workdir, restart_on_failure, opencode_session_id, session_status, session_error, session_context, created_by, created_at, initialized_at, input_tokens, output_tokens) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22)", params![agent.id, agent.name, agent.role, agent.traits, serde_json::to_string(&agent.skills)?, agent.preset, agent.opencode_provider_id, agent.opencode_provider_name, agent.opencode_model_id, agent.opencode_model_name, agent.opencode_agent, agent.workdir, agent.restart_on_failure, agent.opencode_session_id, agent.session_status, agent.session_error, agent.session_context, agent.created_by, agent.created_at, agent.initialized_at, agent.input_tokens, agent.output_tokens])?;
        self.conn.execute("INSERT INTO workspace_agent_instances (id, agent_id, opencode_session_id, created_at) VALUES (?1, ?2, ?3, ?4)", params![agent.instance_id, agent.id, agent.opencode_session_id, agent.created_at])?;
        Ok(agent)
    }

    pub fn agents(&self) -> Result<Vec<WorkspaceAgent>> {
        let mut statement = self.conn.prepare("SELECT a.id, a.name, a.role, a.traits, a.skills_json, a.preset, a.opencode_provider_id, a.opencode_provider_name, a.opencode_model_id, a.opencode_model_name, a.opencode_agent, a.workdir, a.restart_on_failure, i.opencode_session_id, a.session_status, a.session_error, a.session_context, i.id, a.created_by, a.created_at, a.initialized_at, a.input_tokens, a.output_tokens FROM workspace_agents a JOIN workspace_agent_instances i ON i.agent_id = a.id ORDER BY a.created_at, a.name")?;
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
                    session_context: row.get(16)?,
                    instance_id: row.get(17)?,
                    created_by: row.get(18)?,
                    created_at: row.get(19)?,
                    initialized_at: row.get(20)?,
                    input_tokens: row.get(21)?,
                    output_tokens: row.get(22)?,
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
            "UPDATE workspace_agents SET session_status = ?2, session_error = ?3, session_context = NULL, initialized_at = CASE WHEN initialized_at IS NULL AND ?4 = 'ready' AND ?5 IS NOT NULL THEN ?6 ELSE initialized_at END WHERE id = ?1",
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

    pub fn agent_session_context(&self, agent_id: &str) -> Result<Option<String>> {
        self.conn
            .query_row(
                "SELECT session_context FROM workspace_agents WHERE id = ?1",
                [required("agent id", agent_id)?],
                |row| row.get(0),
            )
            .optional()
            .context("failed to read agent session context")?
            .context("agent does not exist")
    }

    pub fn set_agent_session_context(&self, agent_id: &str, context: &str) -> Result<()> {
        if self.conn.execute(
            "UPDATE workspace_agents SET session_context = ?2 WHERE id = ?1",
            params![
                required("agent id", agent_id)?,
                required("agent session context", context)?
            ],
        )? == 0
        {
            bail!("agent does not exist");
        }
        Ok(())
    }

    pub fn set_agent_restart_on_failure(
        &self,
        agent_id: &str,
        restart_on_failure: bool,
    ) -> Result<WorkspaceAgent> {
        if self.conn.execute(
            "UPDATE workspace_agents SET restart_on_failure = ?2 WHERE id = ?1",
            params![required("agent id", agent_id)?, restart_on_failure],
        )? == 0
        {
            bail!("agent does not exist");
        }
        self.agents()?
            .into_iter()
            .find(|agent| agent.id == agent_id)
            .context("updated agent is missing")
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
            "UPDATE workspace_agents SET opencode_provider_id = ?2, opencode_provider_name = ?3, opencode_model_id = ?4, opencode_model_name = ?5, opencode_agent = ?6, workdir = ?7, restart_on_failure = ?8, session_status = ?9, session_error = ?10, session_context = NULL, initialized_at = CASE WHEN initialized_at IS NULL AND ?9 = 'ready' AND ?11 IS NOT NULL THEN ?12 ELSE initialized_at END WHERE id = ?1",
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
            "DELETE FROM workspace_conversation_coordinators WHERE agent_id = ?1",
            [&agent_id],
        )?;
        transaction.execute(
            "DELETE FROM workspace_thread_agents WHERE agent_id = ?1",
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
        // Include A0 in client-facing conversation directories without making it
        // an allocatable worker membership.
        let mut statement = self.conn.prepare(
            "SELECT membership.agent_id, membership.channel_id, membership.member_pubkey,
                    membership.peer_pubkey, membership.folder_scope_json, assignment.parent_id
             FROM workspace_conversation_agents membership
             LEFT JOIN (workspace_thread_agents assignment
                        JOIN workspace_messages root ON root.id = assignment.parent_id)
               ON assignment.agent_id = membership.agent_id
              AND (root.channel_id = membership.channel_id
                   OR (root.channel_id IS NULL AND membership.channel_id IS NULL
                       AND ((root.sender_pubkey = membership.member_pubkey AND root.recipient_pubkey = membership.peer_pubkey)
                            OR (root.sender_pubkey = membership.peer_pubkey AND root.recipient_pubkey = membership.member_pubkey))))
             UNION ALL
             SELECT agent_id, channel_id, member_pubkey, peer_pubkey, '[]', NULL
             FROM workspace_conversation_coordinators ORDER BY agent_id",
        )?;
        let memberships = statement
            .query_map([], conversation_agent_from_row)?
            .collect::<rusqlite::Result<_>>()?;
        Ok(memberships)
    }

    pub fn conversation_preprompts(&self) -> Result<Vec<WorkspaceConversationPreprompt>> {
        let mut statement = self.conn.prepare("SELECT channel_id, member_pubkey, peer_pubkey, preprompt, folder_scope_json, agent_routing_enabled, model FROM workspace_conversation_preprompts ORDER BY channel_id, member_pubkey, peer_pubkey")?;
        let preprompts: Vec<_> = statement
            .query_map([], conversation_preprompt_from_row)?
            .collect::<rusqlite::Result<_>>()?;
        let mut preprompts = preprompts;
        let default_prompt = self.default_agent_prompt()?;
        let default_model = self.default_model()?;
        if default_prompt.is_some() || default_model.is_some() {
            preprompts.push(WorkspaceConversationPreprompt {
                // An empty channel ID identifies workspace-level settings in
                // the existing snapshot payload without matching a channel.
                channel_id: Some(String::new()),
                member_pubkey: None,
                peer_pubkey: None,
                preprompt: default_prompt.unwrap_or_default(),
                folder_scope: vec![],
                agent_routing_enabled: false,
                model: default_model,
            });
        }
        Ok(preprompts)
    }

    pub fn default_agent_prompt(&self) -> Result<Option<String>> {
        self.conn
            .query_row(
                "SELECT value FROM workspace_settings WHERE key = 'default_agent_prompt'",
                [],
                |row| row.get(0),
            )
            .optional()
            .map_err(Into::into)
    }

    pub fn set_default_agent_prompt(&self, preprompt: &str) -> Result<()> {
        if preprompt.chars().count() > 4_000 {
            bail!("workspace default agent prompt may not exceed 4000 characters");
        }
        let preprompt = preprompt.trim();
        if preprompt.is_empty() {
            self.conn.execute(
                "DELETE FROM workspace_settings WHERE key = 'default_agent_prompt'",
                [],
            )?;
        } else {
            self.conn.execute(
                "INSERT INTO workspace_settings (key, value) VALUES ('default_agent_prompt', ?1) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [preprompt],
            )?;
        }
        Ok(())
    }

    pub fn default_model(&self) -> Result<Option<String>> {
        self.conn
            .query_row(
                "SELECT value FROM workspace_settings WHERE key = 'default_model'",
                [],
                |row| row.get(0),
            )
            .optional()
            .map_err(Into::into)
    }

    pub fn set_default_model(&self, model: Option<&str>) -> Result<()> {
        match model {
            Some(model) => self.conn.execute(
                "INSERT INTO workspace_settings (key, value) VALUES ('default_model', ?1) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [model],
            )?,
            None => self.conn.execute("DELETE FROM workspace_settings WHERE key = 'default_model'", [])?,
        };
        Ok(())
    }

    pub fn set_conversation_preprompt(
        &self,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
        preprompt: &str,
        folder_scope: &[String],
        agent_routing_enabled: Option<bool>,
        model: Option<&str>,
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
        let existing_routing_enabled = self.conn.query_row(
            "SELECT agent_routing_enabled FROM workspace_conversation_preprompts WHERE channel_id IS ?1 AND member_pubkey IS ?2 AND peer_pubkey IS ?3",
            params![channel_id, member, peer],
            |row| row.get::<_, bool>(0),
        ).optional()?.unwrap_or(false);
        let agent_routing_enabled = agent_routing_enabled.unwrap_or(existing_routing_enabled);
        self.conn.execute("DELETE FROM workspace_conversation_preprompts WHERE channel_id IS ?1 AND member_pubkey IS ?2 AND peer_pubkey IS ?3", params![channel_id, member, peer])?;
        if !preprompt.is_empty()
            || !folder_scope.is_empty()
            || agent_routing_enabled
            || model.is_some()
        {
            self.conn.execute("INSERT INTO workspace_conversation_preprompts (channel_id, member_pubkey, peer_pubkey, preprompt, folder_scope_json, agent_routing_enabled, model) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)", params![channel_id, member, peer, preprompt, serde_json::to_string(folder_scope)?, agent_routing_enabled, model])?;
        }
        Ok(())
    }

    pub fn conversation_folder_scope(
        &self,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
    ) -> Result<Vec<String>> {
        let scope = match (channel_id, member, peer) {
            (Some(channel_id), None, None) => self.conn.query_row(
                "SELECT folder_scope_json FROM workspace_conversation_preprompts WHERE channel_id = ?1 AND member_pubkey IS NULL AND peer_pubkey IS NULL",
                [channel_id],
                |row| row.get::<_, String>(0),
            ).optional()?,
            (None, Some(member), Some(peer)) => {
                let (member, peer) = direct_participants(member, peer)?;
                self.conn.query_row(
                    "SELECT folder_scope_json FROM workspace_conversation_preprompts WHERE channel_id IS NULL AND member_pubkey = ?1 AND peer_pubkey = ?2",
                    params![member, peer],
                    |row| row.get::<_, String>(0),
                ).optional()?
            }
            _ => bail!("conversation must be a channel or a direct message"),
        };
        Ok(scope
            .as_deref()
            .and_then(|scope| serde_json::from_str(scope).ok())
            .unwrap_or_default())
    }

    pub fn conversation_agent_routing_enabled(
        &self,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
    ) -> Result<bool> {
        match (channel_id, member, peer) {
            (Some(channel_id), None, None) => self
                .conn
                .query_row(
                    "SELECT agent_routing_enabled FROM workspace_conversation_preprompts WHERE channel_id = ?1 AND member_pubkey IS NULL AND peer_pubkey IS NULL",
                    [channel_id],
                    |row| row.get(0),
                )
                .optional()
                .map(|enabled| enabled.unwrap_or(false))
                .map_err(Into::into),
            (None, Some(member), Some(peer)) => {
                let (member, peer) = direct_participants(member, peer)?;
                self.conn
                    .query_row(
                        "SELECT agent_routing_enabled FROM workspace_conversation_preprompts WHERE channel_id IS NULL AND member_pubkey = ?1 AND peer_pubkey = ?2",
                        params![member, peer],
                        |row| row.get(0),
                    )
                    .optional()
                    .map(|enabled| enabled.unwrap_or(false))
                    .map_err(Into::into)
            }
            _ => bail!("conversation must be a channel or a direct message"),
        }
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

    /// Persists the single A0 coordinator for a channel or direct conversation.
    /// Coordinators are intentionally not conversation-agent memberships.
    pub fn set_conversation_coordinator(
        &self,
        agent_id: &str,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
    ) -> Result<bool> {
        let agent_id = required("agent id", agent_id)?;
        if !self.agents()?.iter().any(|agent| agent.id == agent_id) {
            bail!("agent does not exist");
        }
        let (channel_id, member, peer) = match (channel_id, member, peer) {
            (Some(channel_id), None, None) => {
                self.require_channel(channel_id)?;
                (Some(channel_id.to_string()), None, None)
            }
            (None, Some(member), Some(peer)) => {
                let (member, peer) = direct_participants(member, peer)?;
                (None, Some(member), Some(peer))
            }
            _ => bail!("conversation must be a channel or a direct message"),
        };
        let changed = self.conn.execute(
            "INSERT OR IGNORE INTO workspace_conversation_coordinators (agent_id, channel_id, member_pubkey, peer_pubkey) VALUES (?1, ?2, ?3, ?4)",
            params![agent_id, channel_id, member, peer],
        )?;
        Ok(changed == 1)
    }

    pub fn conversation_coordinator(
        &self,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
    ) -> Result<Option<WorkspaceAgent>> {
        let agent_id = match channel_id {
            Some(channel_id) => self.conn.query_row(
                "SELECT agent_id FROM workspace_conversation_coordinators WHERE channel_id = ?1",
                [channel_id],
                |row| row.get::<_, String>(0),
            ).optional()?,
            None => {
                let (member, peer) = direct_participants(member.unwrap_or_default(), peer.unwrap_or_default())?;
                self.conn.query_row(
                    "SELECT agent_id FROM workspace_conversation_coordinators WHERE member_pubkey = ?1 AND peer_pubkey = ?2",
                    params![member, peer],
                    |row| row.get::<_, String>(0),
                ).optional()?
            }
        };
        let Some(agent_id) = agent_id else {
            return Ok(None);
        };
        Ok(self
            .agents()?
            .into_iter()
            .find(|agent| agent.id == agent_id))
    }

    pub fn set_thread_agent_routing(&self, parent_id: &str, route_agent: bool) -> Result<()> {
        let parent_id = required("thread parent id", parent_id)?;
        if self.message(&parent_id)?.parent_id.is_some() {
            bail!("thread routing requires the root parent message");
        }
        self.conn.execute(
            "INSERT INTO workspace_thread_agent_routing (parent_id, route_agent) VALUES (?1, ?2) ON CONFLICT(parent_id) DO UPDATE SET route_agent = excluded.route_agent",
            params![parent_id, route_agent],
        )?;
        Ok(())
    }

    pub fn thread_agent_routing_enabled(&self, parent_id: &str) -> Result<Option<bool>> {
        Ok(self
            .conn
            .query_row(
                "SELECT route_agent FROM workspace_thread_agent_routing WHERE parent_id = ?1",
                [required("thread parent id", parent_id)?],
                |row| row.get(0),
            )
            .optional()?)
    }

    /// Assigns an existing conversation agent to the root message of one thread.
    pub fn assign_thread_agent(
        &self,
        agent_id: &str,
        parent_id: &str,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
    ) -> Result<()> {
        let agent_id = required("agent id", agent_id)?;
        let parent_id = required("thread parent id", parent_id)?;
        let parent = self.message(&parent_id)?;
        if parent.parent_id.is_some() {
            bail!("thread assignment requires the root parent message");
        }
        let matches_scope = match channel_id {
            Some(channel_id) => parent.channel_id.as_deref() == Some(channel_id),
            None => {
                let (member, peer) =
                    direct_participants(member.unwrap_or_default(), peer.unwrap_or_default())?;
                direct_message_matches(&parent, &member, &peer)
            }
        };
        if !matches_scope {
            bail!("thread parent belongs to another conversation");
        }
        let is_conversation_agent = self
            .agents_for_conversation(channel_id, member, peer)?
            .iter()
            .any(|agent| agent.id == agent_id);
        let is_conversation_coordinator = self
            .conversation_coordinator(channel_id, member, peer)?
            .is_some_and(|agent| agent.id == agent_id);
        if !is_conversation_agent && !is_conversation_coordinator {
            bail!("agent is not assigned to this conversation");
        }
        self.conn.execute(
            "INSERT INTO workspace_thread_agents (parent_id, agent_id) VALUES (?1, ?2) ON CONFLICT(parent_id) DO UPDATE SET agent_id = excluded.agent_id",
            params![parent_id, agent_id],
        )?;
        self.conn.execute(
            "DELETE FROM workspace_completed_thread_agents WHERE parent_id = ?1",
            [parent_id],
        )?;
        Ok(())
    }

    /// Atomically selects the next idle A1+ worker and persists the ring position.
    pub fn assign_oldest_available_thread_agent(
        &self,
        parent_id: &str,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
    ) -> Result<Option<WorkspaceAgent>> {
        self.validate_thread_root(parent_id, channel_id, member, peer)?;
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            // Recheck while holding the write lock. Two root messages can arrive
            // together, and retries must retain an existing assignment.
            if let Some(agent) = self.thread_agent(parent_id, channel_id, member, peer)? {
                return Ok(Some(agent));
            }
            let mut workers = self.agents_for_conversation(channel_id, member, peer)?;
            workers.retain(|agent| worker_number(agent).is_some());
            workers.sort_by_key(|agent| worker_number(agent));
            if workers.is_empty() {
                return Ok(None);
            }
            let next_worker =
                self.round_robin_next_worker(channel_id, member, peer, workers.len())?;
            let agent = (0..workers.len())
                .map(|offset| (next_worker + offset) % workers.len())
                .map(|index| (index, workers[index].clone()))
                .next();
            if let Some((index, agent)) = &agent {
                self.conn.execute(
                    "INSERT INTO workspace_thread_agents (parent_id, agent_id) VALUES (?1, ?2)",
                    params![required("thread parent id", parent_id)?, agent.id],
                )?;
                self.set_round_robin_next_worker(
                    channel_id,
                    member,
                    peer,
                    (index + 1) % workers.len(),
                )?;
            }
            Ok(agent.map(|(_, agent)| agent))
        })();
        if result.is_ok() {
            self.conn.execute_batch("COMMIT")?;
        } else {
            self.conn.execute_batch("ROLLBACK")?;
        }
        result
    }

    /// Completion preserves ownership for history and reopening, while making
    /// the worker immediately available for another routed thread.
    pub fn complete_thread(
        &self,
        sender: &str,
        parent_id: &str,
        channel_id: Option<&str>,
        recipient: Option<&str>,
    ) -> Result<Option<WorkspaceMessage>> {
        self.validate_thread_root(
            parent_id,
            channel_id,
            channel_id.is_none().then_some(sender),
            recipient,
        )?;
        let Some(agent) = self.thread_agent(
            parent_id,
            channel_id,
            channel_id.is_none().then_some(sender),
            recipient,
        )?
        else {
            return Ok(None);
        };
        let replied = self.conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM workspace_messages WHERE parent_id = ?1 AND sender_pubkey = ?2)",
            params![parent_id, format!("agent:{}", agent.id)],
            |row| row.get::<_, bool>(0),
        )?;
        if !replied {
            bail!("a thread can be completed only after its worker replies");
        }
        let message = WorkspaceMessage {
            id: new_id(),
            channel_id: channel_id.map(ToOwned::to_owned),
            recipient_pubkey: recipient.map(ToOwned::to_owned),
            sender_pubkey: required("sender", sender)?,
            body: "[[THREAD_COMPLETED]]".to_string(),
            attachments: vec![],
            mentions: vec![],
            parent_id: Some(required("thread parent id", parent_id)?),
            also_send_to_main: false,
            pinned: false,
            reactions: vec![],
            work_history: vec![],
            edited_at: None,
            deleted_at: None,
            created_at: now(),
        };
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result: Result<()> = (|| {
            self.conn.execute(
                "INSERT INTO workspace_completed_thread_agents (parent_id, agent_id) VALUES (?1, ?2) ON CONFLICT(parent_id) DO UPDATE SET agent_id = excluded.agent_id",
                params![parent_id, agent.id],
            )?;
            self.conn.execute(
                "DELETE FROM workspace_thread_agents WHERE parent_id = ?1",
                [parent_id],
            )?;
            self.conn.execute("INSERT INTO workspace_messages (id, channel_id, recipient_pubkey, sender_pubkey, body, attachments_json, mentions_json, parent_id, also_send_to_main, pinned, created_at) VALUES (?1, ?2, ?3, ?4, ?5, '[]', '[]', ?6, 0, 0, ?7)", params![message.id, message.channel_id, message.recipient_pubkey, message.sender_pubkey, message.body, message.parent_id, message.created_at])?;
            Ok(())
        })();
        if result.is_ok() {
            self.conn.execute_batch("COMMIT")?;
        } else {
            self.conn.execute_batch("ROLLBACK")?;
        }
        result?;
        Ok(Some(message))
    }

    /// Reopening restores the worker reserved by completion to the same thread.
    pub fn reopen_thread(
        &self,
        sender: &str,
        parent_id: &str,
        channel_id: Option<&str>,
        recipient: Option<&str>,
    ) -> Result<Option<WorkspaceMessage>> {
        self.validate_thread_root(
            parent_id,
            channel_id,
            channel_id.is_none().then_some(sender),
            recipient,
        )?;
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        let result = (|| {
            let agent_id = self
                .conn
                .query_row(
                    "SELECT agent_id FROM workspace_completed_thread_agents WHERE parent_id = ?1",
                    [required("thread parent id", parent_id)?],
                    |row| row.get::<_, String>(0),
                )
                .optional()?;
            let Some(agent_id) = agent_id else {
                return Ok(None);
            };
            self.conn.execute(
                "INSERT INTO workspace_thread_agents (parent_id, agent_id) VALUES (?1, ?2)",
                params![parent_id, agent_id],
            )?;
            self.conn.execute(
                "DELETE FROM workspace_completed_thread_agents WHERE parent_id = ?1",
                [parent_id],
            )?;
            let message = WorkspaceMessage {
                id: new_id(),
                channel_id: channel_id.map(ToOwned::to_owned),
                recipient_pubkey: recipient.map(ToOwned::to_owned),
                sender_pubkey: required("sender", sender)?,
                body: "[[THREAD_REOPENED]]".to_string(),
                attachments: vec![],
                mentions: vec![],
                parent_id: Some(required("thread parent id", parent_id)?),
                also_send_to_main: false,
                pinned: false,
                reactions: vec![],
                work_history: vec![],
                edited_at: None,
                deleted_at: None,
                created_at: now(),
            };
            self.conn.execute("INSERT INTO workspace_messages (id, channel_id, recipient_pubkey, sender_pubkey, body, attachments_json, mentions_json, parent_id, also_send_to_main, pinned, created_at) VALUES (?1, ?2, ?3, ?4, ?5, '[]', '[]', ?6, 0, 0, ?7)", params![message.id, message.channel_id, message.recipient_pubkey, message.sender_pubkey, message.body, message.parent_id, message.created_at])?;
            Ok(Some(message))
        })();
        if result.is_ok() {
            self.conn.execute_batch("COMMIT")?;
        } else {
            self.conn.execute_batch("ROLLBACK")?;
        }
        result
    }

    /// Returns whether a completed thread retains an owner that should be
    /// preferred if a participant reopens the discussion.
    pub fn has_completed_thread_agent(&self, parent_id: &str) -> Result<bool> {
        Ok(self.conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM workspace_completed_thread_agents WHERE parent_id = ?1)",
            [required("thread parent id", parent_id)?],
            |row| row.get(0),
        )?)
    }

    fn round_robin_next_worker(
        &self,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
        worker_count: usize,
    ) -> Result<usize> {
        let next = match channel_id {
            Some(channel_id) => self.conn.query_row("SELECT next_worker FROM workspace_conversation_round_robin WHERE channel_id = ?1", [channel_id], |row| row.get::<_, i64>(0)).optional()?,
            None => {
                let (member, peer) = direct_participants(member.unwrap_or_default(), peer.unwrap_or_default())?;
                self.conn.query_row("SELECT next_worker FROM workspace_conversation_round_robin WHERE member_pubkey = ?1 AND peer_pubkey = ?2", params![member, peer], |row| row.get::<_, i64>(0)).optional()?
            }
        }.unwrap_or(0);
        Ok(next.rem_euclid(worker_count.max(1) as i64) as usize)
    }

    fn set_round_robin_next_worker(
        &self,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
        next: usize,
    ) -> Result<()> {
        match channel_id {
            Some(channel_id) => {
                self.conn.execute("INSERT INTO workspace_conversation_round_robin (channel_id, next_worker) VALUES (?1, ?2) ON CONFLICT(channel_id) WHERE channel_id IS NOT NULL DO UPDATE SET next_worker = excluded.next_worker", params![channel_id, next])?;
            }
            None => {
                let (member, peer) =
                    direct_participants(member.unwrap_or_default(), peer.unwrap_or_default())?;
                self.conn.execute("INSERT INTO workspace_conversation_round_robin (member_pubkey, peer_pubkey, next_worker) VALUES (?1, ?2, ?3) ON CONFLICT(member_pubkey, peer_pubkey) WHERE channel_id IS NULL DO UPDATE SET next_worker = excluded.next_worker", params![member, peer, next])?;
            }
        }
        Ok(())
    }

    /// Returns the assigned agent for a root thread, if that agent is still in scope.
    pub fn thread_agent(
        &self,
        parent_id: &str,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
    ) -> Result<Option<WorkspaceAgent>> {
        let parent_id = required("thread parent id", parent_id)?;
        let Some(agent_id) = self
            .conn
            .query_row(
                "SELECT agent_id FROM workspace_thread_agents WHERE parent_id = ?1",
                [&parent_id],
                |row| row.get::<_, String>(0),
            )
            .optional()?
        else {
            return Ok(None);
        };
        let parent = self.message(&parent_id)?;
        let matches_scope = match channel_id {
            Some(channel_id) => parent.channel_id.as_deref() == Some(channel_id),
            None => {
                let (member, peer) =
                    direct_participants(member.unwrap_or_default(), peer.unwrap_or_default())?;
                direct_message_matches(&parent, &member, &peer)
            }
        };
        if !matches_scope {
            return Ok(None);
        }
        let conversation_agent = self
            .agents_for_conversation(channel_id, member, peer)?
            .into_iter()
            .find(|agent| agent.id == agent_id);
        Ok(conversation_agent.or(self
            .conversation_coordinator(channel_id, member, peer)?
            .filter(|agent| agent.id == agent_id)))
    }

    /// Returns the newest message in a root thread, including the root itself.
    /// Reactivation uses this as the trigger so the retained agent receives the
    /// new thread's compact handoff rather than replaying stale root text.
    pub fn pending_thread_agent_turns(&self) -> Result<Vec<WorkspaceThreadAgentTurn>> {
        let mut statement = self.conn.prepare(
            "SELECT assignment.parent_id, assignment.agent_id
             FROM workspace_thread_agents assignment
             JOIN workspace_messages latest ON latest.id = (
                 SELECT message.id FROM workspace_messages message
                 WHERE message.id = assignment.parent_id OR message.parent_id = assignment.parent_id
                 ORDER BY message.rowid DESC LIMIT 1
             )
             LEFT JOIN workspace_board_task_workstreams board
                 ON board.root_message_id = assignment.parent_id
             WHERE board.task_id IS NULL
                 AND latest.deleted_at IS NULL
                 AND latest.sender_pubkey != 'agent:' || assignment.agent_id",
        )?;
        let turns = statement
            .query_map([], |row| {
                Ok(WorkspaceThreadAgentTurn {
                    parent_id: row.get(0)?,
                    agent_id: row.get(1)?,
                })
            })?
            .collect::<rusqlite::Result<_>>()?;
        Ok(turns)
    }

    pub fn latest_thread_message_id(&self, parent_id: &str) -> Result<String> {
        let parent_id = required("thread parent id", parent_id)?;
        self.conn
            .query_row(
                "SELECT id FROM workspace_messages WHERE (id = ?1 OR parent_id = ?1) AND body NOT LIKE '[[RELATED_THREAD:%' ORDER BY rowid DESC LIMIT 1",
                [&parent_id],
                |row| row.get(0),
            )
            .optional()?
            .context("thread parent message does not exist")
    }

    /// Validates a root thread within the caller's conversation scope.
    pub fn validate_thread_root(
        &self,
        parent_id: &str,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
    ) -> Result<()> {
        let parent_id = required("thread parent id", parent_id)?;
        let message = self.message(&parent_id)?;
        if message.parent_id.is_some() {
            bail!("thread operations require root messages");
        }
        if message.deleted_at.is_some() {
            bail!("deleted messages cannot be thread roots");
        }
        let in_scope = match channel_id {
            Some(channel_id) => message.channel_id.as_deref() == Some(channel_id),
            None => {
                let (member, peer) =
                    direct_participants(member.unwrap_or_default(), peer.unwrap_or_default())?;
                direct_message_matches(&message, &member, &peer)
            }
        };
        if !in_scope {
            bail!("thread parent belongs to another conversation");
        }
        Ok(())
    }

    /// Validates a persisted related-thread marker without changing message
    /// parentage. Both roots must remain in the caller's conversation scope.
    pub fn validate_related_thread(
        &self,
        parent_id: &str,
        related_parent_id: &str,
        channel_id: Option<&str>,
        member: Option<&str>,
        peer: Option<&str>,
    ) -> Result<()> {
        let parent_id = required("thread parent id", parent_id)?;
        let related_parent_id = required("related thread parent id", related_parent_id)?;
        if parent_id == related_parent_id {
            bail!("a thread cannot reference itself");
        }
        self.validate_thread_root(&parent_id, channel_id, member, peer)?;
        self.validate_thread_root(&related_parent_id, channel_id, member, peer)?;
        Ok(())
    }

    /// Returns the active related root. Marker history is append-only, and the
    /// newest valid marker is authoritative. A clear marker returns `None`.
    pub fn active_related_thread(&self, parent_id: &str) -> Result<Option<String>> {
        let parent_id = required("thread parent id", parent_id)?;
        let mut statement = self.conn.prepare(
            "SELECT body FROM workspace_messages WHERE parent_id = ?1 ORDER BY rowid DESC",
        )?;
        let bodies = statement
            .query_map([parent_id], |row| row.get::<_, String>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(bodies
            .into_iter()
            .find_map(|body| parse_related_thread_marker(&body))
            .flatten())
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
        if !sender.starts_with("agent:") && !self.is_channel_member(channel_id, sender)? {
            bail!("sender is not a channel member");
        }
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
            pinned: false,
            reactions: vec![],
            work_history: vec![],
            edited_at: None,
            deleted_at: None,
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
        self.conn.execute("INSERT INTO workspace_messages (id, channel_id, recipient_pubkey, sender_pubkey, body, attachments_json, mentions_json, parent_id, also_send_to_main, pinned, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)", params![message.id, message.channel_id, message.recipient_pubkey, message.sender_pubkey, message.body, serde_json::to_string(&message.attachments)?, serde_json::to_string(&message.mentions)?, message.parent_id, message.also_send_to_main, message.pinned, message.created_at])?;
        Ok(message)
    }

    pub fn set_message_work_history(&self, id: &str, work_history: &[String]) -> Result<()> {
        self.conn.execute(
            "UPDATE workspace_messages SET work_history_json = ?2 WHERE id = ?1",
            params![id, serde_json::to_string(work_history)?],
        )?;
        Ok(())
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
            "channel_id IN (SELECT channel_id FROM workspace_channel_members WHERE pubkey = ?1) OR sender_pubkey = ?1 OR recipient_pubkey = ?1 OR (sender_pubkey LIKE 'agent:%' AND substr(sender_pubkey, 7) IN (SELECT agent_id FROM workspace_conversation_agents WHERE member_pubkey = ?1 OR peer_pubkey = ?1))",
            [&member],
        )
    }

    pub fn snapshot_messages_since(
        &self,
        member: &str,
        since: i64,
    ) -> Result<Vec<WorkspaceMessage>> {
        Ok(self
            .snapshot_messages(member)?
            .into_iter()
            .filter(|message| message.created_at >= since)
            .collect())
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

    pub fn toggle_pin(&self, sender: &str, message_id: &str) -> Result<WorkspaceMessage> {
        let sender = required("sender", sender)?;
        let message_id = required("message id", message_id)?;
        let message = self.message(&message_id)?;
        if message.channel_id.is_some() {
            if !self
                .is_channel_member(message.channel_id.as_deref().unwrap_or_default(), &sender)?
            {
                bail!("message belongs to another channel");
            }
        } else if message.sender_pubkey != sender
            && message.recipient_pubkey.as_deref() != Some(sender.as_str())
        {
            bail!("message belongs to another direct conversation");
        }
        self.conn.execute(
            "UPDATE workspace_messages SET pinned = NOT pinned WHERE id = ?1",
            [message_id.as_str()],
        )?;
        self.message(&message_id)
    }

    pub fn edit_message(
        &self,
        sender: &str,
        message_id: &str,
        body: &str,
    ) -> Result<WorkspaceMessage> {
        let sender = required("sender", sender)?;
        let message_id = required("message id", message_id)?;
        let body = required("message body", body.trim())?;
        if !self.is_member(&sender)? {
            bail!("sender is not a workspace member");
        }
        let message = self.message(&message_id)?;
        if message.sender_pubkey != sender {
            bail!("only the message author can edit it");
        }
        if message.deleted_at.is_some() {
            bail!("deleted messages cannot be edited");
        }
        self.conn.execute(
            "UPDATE workspace_messages SET body = ?2, edited_at = ?3 WHERE id = ?1",
            params![message_id, body, now()],
        )?;
        self.message(&message_id)
    }

    pub fn delete_message(&self, sender: &str, message_id: &str) -> Result<WorkspaceMessage> {
        let sender = required("sender", sender)?;
        let message_id = required("message id", message_id)?;
        if !self.is_member(&sender)? {
            bail!("sender is not a workspace member");
        }
        let message = self.message(&message_id)?;
        if message.sender_pubkey != sender {
            bail!("only the message author can delete it");
        }
        let transaction = self.conn.unchecked_transaction()?;
        transaction.execute(
            "UPDATE workspace_messages SET body = '', attachments_json = '[]', mentions_json = '[]', deleted_at = ?2 WHERE id = ?1",
            params![message_id, now()],
        )?;
        transaction.execute(
            "DELETE FROM workspace_agent_handoff_outbox WHERE reply_message_id = ?1",
            [message_id.as_str()],
        )?;
        transaction.execute(
            "DELETE FROM workspace_native_turns WHERE message_id = ?1",
            [message_id.as_str()],
        )?;
        if message.parent_id.is_none() {
            transaction.execute(
                "DELETE FROM workspace_native_turns WHERE message_id IN (SELECT id FROM workspace_messages WHERE id = ?1 OR parent_id = ?1)",
                [message_id.as_str()],
            )?;
            transaction.execute(
                "DELETE FROM workspace_agent_handoff_outbox WHERE reply_message_id IN (SELECT id FROM workspace_messages WHERE id = ?1 OR parent_id = ?1)",
                [message_id.as_str()],
            )?;
        }
        transaction.commit()?;
        self.message(&message_id)
    }

    fn messages<P: rusqlite::Params>(
        &self,
        predicate: &str,
        params: P,
    ) -> Result<Vec<WorkspaceMessage>> {
        // IDs are random and cannot break same-second timestamp ties reliably.
        // Rowid preserves the append order used for thread previews and handoffs.
        let query = format!("SELECT id, channel_id, recipient_pubkey, sender_pubkey, body, attachments_json, mentions_json, parent_id, also_send_to_main, pinned, work_history_json, edited_at, deleted_at, created_at FROM workspace_messages WHERE {predicate} ORDER BY created_at, rowid");
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
            .query_row("SELECT id, channel_id, recipient_pubkey, sender_pubkey, body, attachments_json, mentions_json, parent_id, also_send_to_main, pinned, work_history_json, edited_at, deleted_at, created_at FROM workspace_messages WHERE id = ?1", [id], message_from_row)
            .optional()?;
        message
            .map(|mut message| {
                message.reactions = self.reactions_for_message(id)?;
                Ok(message)
            })
            .transpose()
    }

    /// Returns a root message and its direct replies regardless of conversation.
    /// Callers use this for explicit workspace message references only.
    pub fn thread_messages(&self, parent_id: &str) -> Result<Vec<WorkspaceMessage>> {
        if self.message(parent_id)?.deleted_at.is_some() {
            bail!("deleted messages cannot be thread roots");
        }
        self.messages(
            "id = ?1 OR parent_id = ?1",
            [required("thread parent id", parent_id)?],
        )
    }

    pub fn thread_state(&self, parent_id: &str) -> Result<Vec<(String, Option<i64>, Option<i64>)>> {
        self.conn
            .prepare("SELECT id, edited_at, deleted_at FROM workspace_messages WHERE id = ?1 OR parent_id = ?1 ORDER BY rowid")?
            .query_map([required("thread parent id", parent_id)?], |row| {
                Ok((row.get(0)?, row.get(1)?, row.get(2)?))
            })?
            .collect::<rusqlite::Result<_>>()
            .map_err(Into::into)
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
                "agent" => {
                    mention.id == "native-opencode"
                        || self.conn.query_row(
                            "SELECT EXISTS(SELECT 1 FROM workspace_agents WHERE id = ?1)",
                            [&mention.id],
                            |row| row.get::<_, bool>(0),
                        )?
                }
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
        let parent = self.conn.query_row("SELECT channel_id, recipient_pubkey, sender_pubkey, deleted_at FROM workspace_messages WHERE id = ?1", [parent_id], |row| Ok((row.get::<_, Option<String>>(0)?, row.get::<_, Option<String>>(1)?, row.get::<_, String>(2)?, row.get::<_, Option<i64>>(3)?))).optional()?;
        let Some((parent_channel, parent_recipient, parent_sender, deleted_at)) = parent else {
            bail!("thread parent does not exist")
        };
        if deleted_at.is_some() {
            bail!("thread parent is deleted");
        }
        if parent_channel.as_deref() != channel_id {
            bail!("thread parent belongs to another channel")
        }
        if let Some(recipient) = recipient {
            if !sender.starts_with("agent:")
                && !parent_sender.starts_with("agent:")
                && !((parent_sender == sender && parent_recipient.as_deref() == Some(recipient))
                    || (parent_sender == recipient && parent_recipient.as_deref() == Some(sender)))
            {
                bail!("thread parent belongs to another direct conversation");
            }
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

fn direct_message_matches(message: &WorkspaceMessage, member: &str, peer: &str) -> bool {
    message.channel_id.is_none()
        && ((message.sender_pubkey == member && message.recipient_pubkey.as_deref() == Some(peer))
            || (message.sender_pubkey == peer
                && message.recipient_pubkey.as_deref() == Some(member)))
}

/// `Some(None)` is an explicit append-only clear operation. Non-marker text is
/// ignored so ordinary thread messages cannot change the active reference.
fn parse_related_thread_marker(body: &str) -> Option<Option<String>> {
    let value = body
        .strip_prefix("[[RELATED_THREAD:")?
        .strip_suffix("]]")?
        .trim();
    if value == "CLEAR" {
        Some(None)
    } else {
        (!value.is_empty()).then(|| Some(value.to_string()))
    }
}

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
        pinned: row.get(9)?,
        reactions: Vec::new(),
        work_history: serde_json::from_str(&row.get::<_, String>(10)?).unwrap_or_default(),
        edited_at: row.get(11)?,
        deleted_at: row.get(12)?,
        created_at: row.get(13)?,
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
        parent_id: row.get(5)?,
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
        folder_scope: serde_json::from_str(&row.get::<_, String>(4)?).unwrap_or_default(),
        agent_routing_enabled: row.get(5)?,
        model: row.get(6)?,
    })
}
fn direct_participants(member: &str, peer: &str) -> Result<(String, String)> {
    let mut participants = [required("member", member)?, required("peer", peer)?];
    participants.sort();
    Ok((participants[0].clone(), participants[1].clone()))
}
fn worker_number(agent: &WorkspaceAgent) -> Option<u32> {
    (agent.role == "Conversation worker" || agent.role == "Round-robin worker")
        .then(|| agent.name.strip_prefix('A')?.parse().ok())
        .flatten()
        .filter(|number| *number > 0)
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
fn conversation_session_key(
    channel_id: Option<&str>,
    member_pubkey: Option<&str>,
    peer_pubkey: Option<&str>,
) -> Result<(Option<String>, Option<String>, Option<String>)> {
    match (channel_id, member_pubkey, peer_pubkey) {
        (Some(channel_id), None, None) => {
            Ok((Some(required("channel ID", channel_id)?), None, None))
        }
        (None, Some(member), Some(peer)) => {
            let (member, peer) = direct_participants(member, peer)?;
            Ok((None, Some(member), Some(peer)))
        }
        _ => bail!("conversation must be a channel or a direct message"),
    }
}
fn conversation_session_from_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<WorkspaceConversationSession> {
    Ok(WorkspaceConversationSession {
        channel_id: row.get(0)?,
        member_pubkey: row.get(1)?,
        peer_pubkey: row.get(2)?,
        folder_path: row.get(3)?,
        opencode_session_id: row.get(4)?,
        session_status: row.get(5)?,
        session_error: row.get(6)?,
        session_context: row.get(7)?,
        updated_at: row.get(8)?,
    })
}

fn board_task_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<WorkspaceBoardTask> {
    let folder_scope_json: String = row.get(4)?;
    let folder_scope = serde_json::from_str(&folder_scope_json).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(4, Type::Text, Box::new(error))
    })?;
    Ok(WorkspaceBoardTask {
        id: row.get(0)?,
        title: row.get(1)?,
        conversation_key: row.get(2)?,
        instruction: row.get(3)?,
        folder_scope,
        schedule: row.get(5)?,
        state: row.get(6)?,
        board_column: row.get(7)?,
        next_run_at: row.get(8)?,
        created_by: row.get(9)?,
        created_at: row.get(10)?,
        updated_at: row.get(11)?,
        root_message_id: row.get(12)?,
        agent_id: row.get(13)?,
    })
}

fn board_integration_from_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<WorkspaceBoardIntegration> {
    Ok(WorkspaceBoardIntegration {
        id: row.get(0)?,
        conversation_key: row.get(1)?,
        task_id: row.get(2)?,
        run_id: row.get(3)?,
        proposal_message_id: row.get(4)?,
        state: row.get(5)?,
        created_at: row.get(6)?,
    })
}

fn board_run_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<WorkspaceBoardRun> {
    Ok(WorkspaceBoardRun {
        id: row.get(0)?,
        task_id: row.get(1)?,
        scheduled_at: row.get(2)?,
        state: row.get(3)?,
        started_at: row.get(4)?,
        completed_at: row.get(5)?,
    })
}

fn validate_board_schedule(schedule: &str) -> Result<()> {
    if matches!(
        schedule.trim(),
        "once" | "daily" | "weekdays" | "weekly" | "monthly"
    ) {
        Ok(())
    } else {
        bail!("board task schedule is invalid")
    }
}

fn valid_board_task_column(column: &str) -> bool {
    matches!(
        column,
        "scheduled" | "queued" | "running" | "integrating" | "blocked" | "done"
    )
}

fn validate_board_card_priority(priority: &str) -> Result<String> {
    let priority = priority.trim().to_ascii_lowercase();
    if matches!(
        priority.as_str(),
        "none" | "low" | "medium" | "high" | "urgent"
    ) {
        Ok(priority)
    } else {
        bail!("board card priority is invalid")
    }
}

/// Schedules by UTC timestamps because the store has no time-zone setting.
fn next_board_run_at(schedule: &str, scheduled_at: i64) -> Result<Option<i64>> {
    const DAY: i64 = 24 * 60 * 60;
    validate_board_schedule(schedule)?;
    Ok(match schedule.trim() {
        "once" => None,
        "daily" => Some(scheduled_at + DAY),
        "weekdays" => {
            let weekday = (scheduled_at.div_euclid(DAY) + 4).rem_euclid(7);
            Some(
                scheduled_at
                    + match weekday {
                        5 => 3 * DAY,
                        6 => 2 * DAY,
                        _ => DAY,
                    },
            )
        }
        "weekly" => Some(scheduled_at + 7 * DAY),
        "monthly" => Some(scheduled_at + 30 * DAY),
        _ => unreachable!(),
    })
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

    use anyhow::anyhow;

    #[test]
    fn execution_attempt_turn_ids_are_durable_and_distinct_within_a_delivery() {
        let database = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(database.path()).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let first_delivery = store
            .add_channel_message("owner", &channel.id, "same text", &[], &[], None)
            .unwrap();
        let second_delivery = store
            .add_channel_message("owner", &channel.id, "same text", &[], &[], None)
            .unwrap();

        let first = store
            .worker_turn_id_for_execution_attempt(&first_delivery.id, "agent:worker-1:initial")
            .unwrap();
        let history_first = store
            .worker_turn_id_for_execution_attempt(&first_delivery.id, "agent:worker-1:history:0")
            .unwrap();
        let history_second = store
            .worker_turn_id_for_execution_attempt(&first_delivery.id, "agent:worker-1:history:1")
            .unwrap();
        let continuation = store
            .worker_turn_id_for_execution_attempt(&first_delivery.id, "agent:worker-1:continuation")
            .unwrap();
        let second = store
            .worker_turn_id_for_execution_attempt(&second_delivery.id, "agent:worker-1:initial")
            .unwrap();
        drop(store);
        let reopened = WorkspaceStore::open(database.path()).unwrap();
        let retried = reopened
            .worker_turn_id_for_execution_attempt(&first_delivery.id, "agent:worker-1:initial")
            .unwrap();

        assert_eq!(first, retried);
        assert_ne!(first, history_first);
        assert_ne!(history_first, history_second);
        assert_ne!(history_second, continuation);
        assert_ne!(first, second);
    }

    #[test]
    fn embedded_thread_binding_is_keyed_by_conversation_and_thread() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();

        store
            .claim_embedded_thread_binding("conversation-1", "thread-1", 100)
            .unwrap();
        store
            .mark_embedded_thread_binding_ready("conversation-1", "thread-1")
            .unwrap();
        store
            .claim_embedded_thread_binding("conversation-2", "thread-1", 200)
            .unwrap();

        assert_eq!(
            store
                .embedded_thread_binding("conversation-1", "thread-1")
                .unwrap()
                .unwrap()
                .ready,
            true
        );
        assert_eq!(
            store
                .embedded_thread_binding("conversation-2", "thread-1")
                .unwrap()
                .unwrap()
                .ready,
            false
        );
    }

    #[test]
    fn persists_channels_messages_and_threads() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        store.add_channel_member(&channel.id, "member").unwrap();
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
    fn board_task_claims_a_due_run_once() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let task = store
            .create_board_task(
                "owner",
                "Review open issues",
                "channel:engineering",
                "Review the open issues and report blockers.",
                &[],
                "once",
                100,
            )
            .unwrap();

        assert_eq!(store.board_tasks().unwrap()[0].state, "scheduled");
        assert!(store.claim_due_board_task(&task.id, 100).unwrap().is_some());
        assert!(store.claim_due_board_task(&task.id, 100).unwrap().is_none());
        assert_eq!(store.board_tasks().unwrap()[0].state, "queued");
        assert_eq!(store.board_runs(&task.id).unwrap()[0].state, "queued");
        store.start_board_task(&task.id, 101).unwrap();
        assert_eq!(store.board_tasks().unwrap()[0].state, "running");
        assert_eq!(store.board_runs(&task.id).unwrap()[0].state, "running");
        store.block_board_task(&task.id, "agent failed").unwrap();
        assert_eq!(store.board_tasks().unwrap()[0].state, "blocked");
        assert_eq!(store.board_runs(&task.id).unwrap()[0].state, "blocked");
        assert_eq!(
            store
                .board_timeline(&task.id)
                .unwrap()
                .last()
                .unwrap()
                .state,
            "blocked"
        );
    }

    #[test]
    fn board_task_requires_a_workspace_member_creator() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();

        assert!(store
            .create_board_task(
                "outsider",
                "Review open issues",
                "channel:engineering",
                "Review the open issues and report blockers.",
                &[],
                "once",
                100,
            )
            .is_err());
    }

    #[test]
    fn board_task_move_persists_without_changing_its_execution_state() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        let task = store
            .create_board_task(
                "owner",
                "Review open issues",
                "channel:engineering",
                "Review the open issues and report blockers.",
                &[],
                "once",
                100,
            )
            .unwrap();

        store.move_board_task(&task.id, "done").unwrap();
        let moved = store.board_tasks().unwrap().pop().unwrap();
        assert_eq!(moved.board_column, "done");
        assert_eq!(moved.state, "scheduled");
        assert_eq!(moved.next_run_at, Some(100));
        drop(store);

        let reopened = WorkspaceStore::open(path.path()).unwrap();
        let moved = reopened.board_tasks().unwrap().pop().unwrap();
        assert_eq!(moved.board_column, "done");
        assert_eq!(moved.state, "scheduled");
        assert!(reopened.move_board_task(&task.id, "unknown").is_err());
    }

    #[test]
    fn board_cards_move_between_default_columns_and_keep_activity() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        let columns = store.board_columns().unwrap();
        assert_eq!(
            columns
                .iter()
                .map(|column| column.name.as_str())
                .collect::<Vec<_>>(),
            ["Backlog", "Ready", "In Progress", "Review", "Done"]
        );
        let card = store
            .create_board_card("owner", "Review open issues", "", &columns[0].id, "high")
            .unwrap();

        store
            .move_board_card(&card.id, &columns[3].id, None)
            .unwrap();

        let card = store.board_card(&card.id).unwrap().unwrap();
        assert_eq!(card.column_id, columns[3].id);
        assert_eq!(store.board_card_activity(&card.id).unwrap().len(), 2,);
    }

    #[test]
    fn thread_board_cards_require_three_live_content_replies_and_preserve_identity() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let root = store
            .add_channel_message("owner", &channel.id, "root", &[], &[], None)
            .unwrap();
        for body in [
            "first",
            "second",
            " [[THREAD_TOPIC: title]]",
            "[[THREAD_TOPIC_REQUEST]]",
            "[[RELATED_THREAD: other]]",
        ] {
            store
                .add_channel_message("owner", &channel.id, body, &[], &[], Some(&root.id))
                .unwrap();
        }
        let deleted = store
            .add_channel_message("owner", &channel.id, "deleted", &[], &[], Some(&root.id))
            .unwrap();
        store.delete_message("owner", &deleted.id).unwrap();
        assert!(store
            .create_board_card_from_thread(&root.id, "Title")
            .unwrap()
            .is_none());
        store
            .add_channel_message(
                "owner",
                &channel.id,
                "[[ordinary linked text]] is content",
                &[],
                &[],
                Some(&root.id),
            )
            .unwrap();
        let card = store
            .create_board_card_from_thread(&root.id, "Title")
            .unwrap()
            .unwrap();
        assert_eq!(card.source_thread_id.as_deref(), Some(root.id.as_str()));
        assert_eq!(card.column_id, store.board_columns().unwrap()[0].id);
        let revision = store.revision().unwrap();
        assert_eq!(
            store
                .create_board_card_from_thread(&root.id, "Title")
                .unwrap()
                .unwrap(),
            card
        );
        assert_eq!(store.revision().unwrap(), revision);
        let renamed = store
            .create_board_card_from_thread(&root.id, "New title")
            .unwrap()
            .unwrap();
        assert_eq!(renamed.id, card.id);
        assert_eq!(renamed.title, "New title");
        assert!(store.integrate_thread_board_card(&root.id).unwrap());
        let history = store.board_card_activity(&card.id).unwrap();
        assert!(!store.integrate_thread_board_card(&root.id).unwrap());
        assert_eq!(store.board_card_activity(&card.id).unwrap(), history);
        assert_eq!(
            store
                .create_board_card_from_thread(&root.id, "Latest title")
                .unwrap()
                .unwrap()
                .column_id,
            store
                .board_columns()
                .unwrap()
                .into_iter()
                .find(|column| column.name == "Integrating")
                .unwrap()
                .id
        );
        assert_eq!(store.board_cards().unwrap().len(), 1);
        for table in [
            "workspace_board_tasks",
            "workspace_board_runs",
            "workspace_board_task_workstreams",
        ] {
            assert_eq!(
                store
                    .conn
                    .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| row
                        .get::<_, i64>(0))
                    .unwrap(),
                0
            );
        }
    }

    #[test]
    fn thread_board_card_migrates_an_existing_card_table() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = Connection::open(file.path()).unwrap();
        conn.execute_batch("CREATE TABLE workspace_board_cards (id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', column_id TEXT NOT NULL, rank INTEGER NOT NULL, priority TEXT NOT NULL DEFAULT 'none', created_by TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, archived_at INTEGER);
            INSERT INTO workspace_board_cards VALUES ('existing', 'Keep me', '', 'old-column', 1024, 'none', 'owner', 1, 1, NULL);").unwrap();
        drop(conn);
        let store = WorkspaceStore::open(file.path()).unwrap();
        let card = store.board_card("existing").unwrap().unwrap();
        assert_eq!(card.title, "Keep me");
        assert_eq!(card.source_thread_id, None);
        assert!(store
            .conn
            .prepare("SELECT source_thread_id FROM workspace_board_cards")
            .is_ok());
        drop(store);
        assert_eq!(
            WorkspaceStore::open(file.path())
                .unwrap()
                .board_card("existing")
                .unwrap()
                .unwrap(),
            card
        );
    }

    #[test]
    fn thread_board_card_link_failure_cannot_leave_an_unlinked_card() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let root = store
            .add_channel_message("owner", &channel.id, "root", &[], &[], None)
            .unwrap();
        for _ in 0..3 {
            store
                .add_channel_message("owner", &channel.id, "reply", &[], &[], Some(&root.id))
                .unwrap();
        }
        store.conn.execute_batch("CREATE TRIGGER reject_thread_link_insert BEFORE INSERT ON workspace_board_cards WHEN NEW.source_thread_id IS NOT NULL BEGIN SELECT RAISE(ABORT, 'test link failure'); END;
            CREATE TRIGGER reject_thread_link_update BEFORE UPDATE OF source_thread_id ON workspace_board_cards BEGIN SELECT RAISE(ABORT, 'test link failure'); END;").unwrap();
        assert!(store
            .create_board_card_from_thread(&root.id, "title")
            .is_err());
        assert!(store.board_cards().unwrap().is_empty());
    }

    #[test]
    fn board_cards_store_planning_metadata_and_report_wip_overload() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        let ready = store
            .board_columns()
            .unwrap()
            .into_iter()
            .find(|column| column.name == "Ready")
            .unwrap();
        store
            .set_board_column_wip_limit(&ready.id, Some(1))
            .unwrap();
        let card = store
            .create_board_card("owner", "Release", "", &ready.id, "none")
            .unwrap();

        store
            .set_board_card_metadata(&card.id, "urgent", Some(3), Some(200))
            .unwrap();
        store
            .create_board_card("owner", "Follow up", "", &ready.id, "none")
            .unwrap();

        let card = store.board_card(&card.id).unwrap().unwrap();
        assert_eq!(card.priority, "urgent");
        assert_eq!(card.estimate, Some(3));
        assert_eq!(card.due_at, Some(200));
        assert!(store.board_column_is_over_wip_limit(&ready.id).unwrap());
    }

    #[test]
    fn board_cards_store_assignees_labels_and_dependencies() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        let backlog = store.board_columns().unwrap().remove(0);
        let blocker = store
            .create_board_card("owner", "Prepare release", "", &backlog.id, "none")
            .unwrap();
        let card = store
            .create_board_card("owner", "Publish release", "", &backlog.id, "none")
            .unwrap();

        store
            .set_board_card_assignees(
                &card.id,
                &["member:alice".to_string(), "agent:build".to_string()],
            )
            .unwrap();
        let label = store.create_board_label("release", "#1976d2").unwrap();
        store
            .set_board_card_labels(&card.id, &[label.id.clone()])
            .unwrap();
        store
            .set_board_card_dependencies(&card.id, &[blocker.id.clone()])
            .unwrap();

        assert_eq!(
            store.board_card_assignees(&card.id).unwrap(),
            ["agent:build", "member:alice"]
        );
        assert_eq!(store.board_card_labels(&card.id).unwrap(), [label.id]);
        assert_eq!(
            store.board_card_dependencies(&card.id).unwrap(),
            [blocker.id]
        );
    }

    #[test]
    fn archived_board_cards_are_hidden_and_can_be_restored() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        let backlog = store.board_columns().unwrap().remove(0);
        let card = store
            .create_board_card("owner", "Old work", "", &backlog.id, "none")
            .unwrap();

        store.archive_board_card(&card.id).unwrap();
        assert!(store
            .board_card(&card.id)
            .unwrap()
            .unwrap()
            .archived_at
            .is_some());
        store.restore_board_card(&card.id).unwrap();

        assert!(store
            .board_card(&card.id)
            .unwrap()
            .unwrap()
            .archived_at
            .is_none());
    }

    #[test]
    fn board_turn_links_a_native_turn_to_its_task() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let task = store
            .create_board_task(
                "owner",
                "Review open issues",
                &format!("channel:{}", channel.id),
                "Review the open issues and report blockers.",
                &[],
                "once",
                100,
            )
            .unwrap();
        let message = store
            .add_channel_message(
                "owner",
                &channel.id,
                "Review the open issues.",
                &[],
                &[],
                None,
            )
            .unwrap();

        store.link_board_turn(&task.id, &message.id).unwrap();

        assert_eq!(
            store.board_task_for_turn(&message.id).unwrap(),
            Some(task.id)
        );
    }

    #[test]
    fn converts_board_records_to_protocol_payloads() {
        let task: WorkspaceBoardTaskPayload = WorkspaceBoardTask {
            id: "task-1".to_string(),
            title: "Review open issues".to_string(),
            conversation_key: "channel:engineering".to_string(),
            instruction: "Review the open issues and report blockers.".to_string(),
            folder_scope: vec!["/work/phone".to_string()],
            schedule: "daily".to_string(),
            state: "running".to_string(),
            board_column: "done".to_string(),
            next_run_at: Some(100),
            created_by: "owner".to_string(),
            created_at: 10,
            updated_at: 20,
            root_message_id: Some("message-1".to_string()),
            agent_id: Some("agent-1".to_string()),
        }
        .into();
        assert_eq!(task.board_column, "done");
        let entry: WorkspaceBoardTimelinePayload = WorkspaceBoardTimelineEntry {
            id: "entry-1".to_string(),
            task_id: "task-1".to_string(),
            state: "running".to_string(),
            detail: "Task started".to_string(),
            created_at: 20,
        }
        .into();

        assert_eq!(task.conversation_key, "channel:engineering");
        assert_eq!(task.folder_scope, ["/work/phone"]);
        assert_eq!(entry.task_id, task.id);
        assert_eq!(entry.detail, "Task started");
    }

    #[test]
    fn completing_tasks_marks_one_time_done_and_reschedules_recurring_tasks() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let once = store
            .create_board_task("owner", "Once", "channel:eng", "Do it", &[], "once", 100)
            .unwrap();
        let daily = store
            .create_board_task("owner", "Daily", "channel:eng", "Do it", &[], "daily", 100)
            .unwrap();

        for task in [&once, &daily] {
            store.claim_due_board_task(&task.id, 100).unwrap();
            store.start_board_task(&task.id, 101).unwrap();
            store.complete_board_task(&task.id, 102).unwrap();
        }

        let tasks = store.board_tasks().unwrap();
        let once = tasks.iter().find(|task| task.id == once.id).unwrap();
        let daily = tasks.iter().find(|task| task.id == daily.id).unwrap();
        assert_eq!(once.state, "done");
        assert_eq!(once.next_run_at, None);
        assert_eq!(daily.state, "scheduled");
        assert_eq!(daily.next_run_at, Some(100 + 24 * 60 * 60));
        assert_eq!(store.board_runs(&daily.id).unwrap()[0].state, "completed");
    }

    #[test]
    fn schedules_weekdays_weekly_and_monthly_with_utc_timestamp_cadence() {
        const MONDAY: i64 = 4 * 24 * 60 * 60;
        assert_eq!(
            next_board_run_at("daily", MONDAY).unwrap(),
            Some(MONDAY + 24 * 60 * 60)
        );
        assert_eq!(
            next_board_run_at("weekdays", MONDAY + 4 * 24 * 60 * 60).unwrap(),
            Some(MONDAY + 7 * 24 * 60 * 60)
        );
        assert_eq!(
            next_board_run_at("weekdays", MONDAY + 5 * 24 * 60 * 60).unwrap(),
            Some(MONDAY + 7 * 24 * 60 * 60)
        );
        assert_eq!(
            next_board_run_at("weekdays", MONDAY + 6 * 24 * 60 * 60).unwrap(),
            Some(MONDAY + 7 * 24 * 60 * 60)
        );
        assert_eq!(
            next_board_run_at("weekly", MONDAY).unwrap(),
            Some(MONDAY + 7 * 24 * 60 * 60)
        );
        assert_eq!(
            next_board_run_at("monthly", MONDAY).unwrap(),
            Some(MONDAY + 30 * 24 * 60 * 60)
        );
        assert!(next_board_run_at("once", MONDAY).unwrap().is_none());
    }

    #[test]
    fn retrying_a_blocked_task_returns_it_to_scheduled() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let task = store
            .create_board_task("owner", "Retry", "channel:eng", "Do it", &[], "once", 100)
            .unwrap();
        store.claim_due_board_task(&task.id, 100).unwrap();
        store.start_board_task(&task.id, 101).unwrap();
        store.block_board_task(&task.id, "failed").unwrap();

        store.retry_board_task(&task.id, 200).unwrap();
        let task = store.board_tasks().unwrap().pop().unwrap();
        assert_eq!(task.state, "scheduled");
        assert_eq!(task.next_run_at, Some(200));
    }

    #[test]
    fn corrupt_board_folder_scope_fails_closed() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let task = store
            .create_board_task("owner", "Scope", "channel:eng", "Do it", &[], "once", 100)
            .unwrap();
        store
            .conn
            .execute(
                "UPDATE workspace_board_tasks SET folder_scope_json = 'not-json' WHERE id = ?1",
                [&task.id],
            )
            .unwrap();

        assert!(store.board_tasks().is_err());
    }

    #[test]
    fn invalid_unlinked_scheduled_task_can_be_blocked_without_affecting_other_tasks() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let invalid = store
            .create_board_task("owner", "Invalid", "channel:bad", "Do it", &[], "once", 1)
            .unwrap();
        let valid = store
            .create_board_task("owner", "Valid", "channel:good", "Do it", &[], "once", 1)
            .unwrap();

        store
            .block_scheduled_board_task(&invalid.id, "Task blocked: invalid target")
            .unwrap();

        assert_eq!(
            store
                .claim_due_board_task(&valid.id, 1)
                .unwrap()
                .unwrap()
                .state,
            "queued"
        );
        assert_eq!(
            store
                .board_tasks()
                .unwrap()
                .into_iter()
                .find(|task| task.id == invalid.id)
                .unwrap()
                .state,
            "blocked"
        );
    }

    #[test]
    fn persists_thread_agent_routing_on_the_root_message() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let root = store
            .add_channel_message("owner", &channel.id, "hello", &[], &[], None)
            .unwrap();

        assert_eq!(store.thread_agent_routing_enabled(&root.id).unwrap(), None);
        store.set_thread_agent_routing(&root.id, false).unwrap();
        assert_eq!(
            store.thread_agent_routing_enabled(&root.id).unwrap(),
            Some(false),
        );
        store.set_thread_agent_routing(&root.id, true).unwrap();
        assert_eq!(
            store.thread_agent_routing_enabled(&root.id).unwrap(),
            Some(true),
        );
    }

    #[test]
    fn deletes_only_the_selected_conversation() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let deleted_channel = store.create_channel("engineering", "owner").unwrap();
        let retained_channel = store.create_channel("general", "owner").unwrap();
        store
            .add_channel_message("owner", &deleted_channel.id, "delete me", &[], &[], None)
            .unwrap();
        store
            .add_channel_message("owner", &retained_channel.id, "keep me", &[], &[], None)
            .unwrap();
        store
            .add_direct_message("owner", "member", "delete this too", &[], &[], None)
            .unwrap();

        store.delete_channel(&deleted_channel.id).unwrap();
        store.delete_direct_conversation("owner", "member").unwrap();

        assert!(!store.has_channel(&deleted_channel.id).unwrap());
        assert!(store.has_channel(&retained_channel.id).unwrap());
        assert_eq!(
            store.channel_messages(&retained_channel.id).unwrap().len(),
            1
        );
        assert!(store.direct_messages("owner", "member").unwrap().is_empty());
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
    fn edits_and_tombstones_author_messages_and_cancels_native_turns() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        store.add_channel_member(&channel.id, "member").unwrap();
        let message = store
            .add_channel_message("member", &channel.id, "original", &[], &[], None)
            .unwrap();
        store.queue_native_turn(&message.id).unwrap();

        let edited = store
            .edit_message("member", &message.id, "revised")
            .unwrap();
        assert_eq!(edited.body, "revised");
        assert!(edited.edited_at.is_some());
        assert!(store.edit_message("owner", &message.id, "blocked").is_err());

        let deleted = store.delete_message("member", &message.id).unwrap();
        assert!(deleted.deleted_at.is_some());
        assert!(deleted.body.is_empty());
        assert!(!store.pending_native_turns().unwrap().contains(&message.id));
    }

    #[test]
    fn persists_reactions_and_thread_main_visibility() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        store.add_channel_member(&channel.id, "member").unwrap();
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
        store.add_channel_member(&channel.id, "member").unwrap();
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
    fn persists_per_channel_membership_and_creator_admin_role() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        store.add_member("other").unwrap();
        let channel = store.create_channel("private", "owner").unwrap();
        assert!(store.is_channel_member(&channel.id, "owner").unwrap());
        assert!(store.is_channel_admin(&channel.id, "owner").unwrap());
        assert!(!store.is_channel_member(&channel.id, "member").unwrap());
        store.add_channel_member(&channel.id, "member").unwrap();
        drop(store);

        let store = WorkspaceStore::open(path.path()).unwrap();
        assert_eq!(
            store.channels_for_member("member").unwrap(),
            vec![channel.clone()]
        );
        assert!(store.channels_for_member("other").unwrap().is_empty());
        assert_eq!(store.channel_members(&channel.id).unwrap().len(), 2);
        assert!(store
            .remove_channel_member(&channel.id, "owner", "owner")
            .is_err());
        store
            .remove_channel_member(&channel.id, "member", "owner")
            .unwrap();
        assert!(!store.is_channel_member(&channel.id, "member").unwrap());
    }

    #[test]
    fn transfers_conversation_creator_when_an_admin_removes_them() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("creator").unwrap();
        store.add_member("admin").unwrap();
        let channel = store.create_channel("private", "creator").unwrap();

        store
            .remove_channel_member(&channel.id, "creator", "admin")
            .unwrap();

        let transferred = store
            .channels()
            .unwrap()
            .into_iter()
            .find(|item| item.id == channel.id)
            .unwrap();
        assert_eq!(transferred.created_by, "admin");
        assert!(!store.is_channel_member(&channel.id, "creator").unwrap());
        assert!(store.is_channel_admin(&channel.id, "admin").unwrap());
    }

    #[test]
    fn migrates_existing_channels_with_existing_member_access() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let conn = Connection::open(path.path()).unwrap();
        conn.execute_batch("CREATE TABLE workspace_members (pubkey TEXT PRIMARY KEY, display_name TEXT NOT NULL DEFAULT '', is_admin INTEGER NOT NULL DEFAULT 0, joined_at INTEGER NOT NULL); CREATE TABLE workspace_channels (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, created_by TEXT NOT NULL, created_at INTEGER NOT NULL); INSERT INTO workspace_members VALUES ('owner', '', 0, 1), ('member', '', 0, 1); INSERT INTO workspace_channels VALUES ('channel', 'general', 'owner', 1);").unwrap();
        drop(conn);
        let store = WorkspaceStore::open(path.path()).unwrap();
        assert!(store.is_channel_member("channel", "member").unwrap());
        assert!(store.is_channel_admin("channel", "owner").unwrap());
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
                joined_at: reopened.members().unwrap()[0].joined_at,
            }]
        );
    }

    #[test]
    fn removes_workspace_members() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();

        store.remove_member("member").unwrap();

        assert!(store.is_member("owner").unwrap());
        assert!(!store.is_member("member").unwrap());
        assert!(store.remove_member("member").is_err());
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
    fn accepts_native_opencode_agent_mentions() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let mentions = vec![WorkspaceMentionPayload {
            kind: "agent".to_string(),
            id: "native-opencode".to_string(),
            label: "Agent".to_string(),
        }];

        store
            .add_channel_message("owner", &channel.id, "Please help", &[], &mentions, None)
            .unwrap();
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
    fn persists_and_reassigns_a_thread_agent_within_its_conversation() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let first = store
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
        let second = store
            .create_agent(
                "Guide",
                "Reviewer",
                "",
                &[],
                None,
                None,
                "failed",
                None,
                "owner",
            )
            .unwrap();
        store
            .add_conversation_agent(&first.id, Some(&channel.id), None, None, &[])
            .unwrap();
        store
            .add_conversation_agent(&second.id, Some(&channel.id), None, None, &[])
            .unwrap();
        let root = store
            .add_channel_message("owner", &channel.id, "help", &[], &[], None)
            .unwrap();
        store
            .assign_thread_agent(&first.id, &root.id, Some(&channel.id), None, None)
            .unwrap();
        store
            .assign_thread_agent(&second.id, &root.id, Some(&channel.id), None, None)
            .unwrap();
        drop(store);

        let store = WorkspaceStore::open(path.path()).unwrap();
        assert_eq!(
            store
                .thread_agent(&root.id, Some(&channel.id), None, None)
                .unwrap()
                .unwrap()
                .id,
            second.id
        );
        assert!(store
            .assign_thread_agent(&second.id, "missing", Some(&channel.id), None, None)
            .is_err());
        assert_eq!(store.latest_thread_message_id(&root.id).unwrap(), root.id);
        assert!(store
            .validate_related_thread(&root.id, &root.id, Some(&channel.id), None, None)
            .is_err());
    }

    #[test]
    fn coordinator_is_not_a_conversation_or_thread_participant() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let coordinator = store
            .create_agent(
                "R1",
                "Round-robin coordinator",
                "",
                &[],
                None,
                Some("ses_coordinator"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        let worker = store
            .create_agent(
                "A1",
                "Round-robin worker",
                "",
                &[],
                None,
                Some("ses_worker"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        let second_worker = store
            .create_agent(
                "A2",
                "Round-robin worker",
                "",
                &[],
                None,
                Some("ses_second"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        let third_worker = store
            .create_agent(
                "A3",
                "Round-robin worker",
                "",
                &[],
                None,
                Some("ses_third"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        for worker in [&worker, &second_worker, &third_worker] {
            store
                .add_conversation_agent(&worker.id, Some(&channel.id), None, None, &[])
                .unwrap();
        }
        let root = store
            .add_channel_message("owner", &channel.id, "Investigate this", &[], &[], None)
            .unwrap();
        assert_eq!(
            store
                .assign_oldest_available_thread_agent(&root.id, Some(&channel.id), None, None)
                .unwrap()
                .unwrap()
                .id,
            worker.id
        );

        assert!(!store
            .agents_for_conversation(Some(&channel.id), None, None)
            .unwrap()
            .iter()
            .any(|agent| agent.id == coordinator.id));
        store
            .set_conversation_coordinator(&coordinator.id, Some(&channel.id), None, None)
            .unwrap();
        store
            .assign_thread_agent(&coordinator.id, &root.id, Some(&channel.id), None, None)
            .unwrap();
        assert_eq!(
            store
                .thread_agent(&root.id, Some(&channel.id), None, None)
                .unwrap()
                .unwrap()
                .id,
            coordinator.id
        );
    }

    #[test]
    fn persists_one_non_participant_coordinator_per_conversation() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let channel_a1 = store
            .create_agent(
                "A1",
                "Project coordinator",
                "",
                &[],
                None,
                Some("channel-a1"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        let direct_a1 = store
            .create_agent(
                "A1",
                "Project coordinator",
                "",
                &[],
                None,
                Some("direct-a1"),
                "ready",
                None,
                "owner",
            )
            .unwrap();

        assert!(store
            .set_conversation_coordinator(&channel_a1.id, Some(&channel.id), None, None)
            .unwrap());
        assert!(!store
            .set_conversation_coordinator(&direct_a1.id, Some(&channel.id), None, None)
            .unwrap());
        assert!(store
            .set_conversation_coordinator(&direct_a1.id, None, Some("owner"), Some("member"))
            .unwrap());
        drop(store);

        let store = WorkspaceStore::open(path.path()).unwrap();
        assert_eq!(
            store
                .conversation_coordinator(Some(&channel.id), None, None)
                .unwrap()
                .unwrap()
                .id,
            channel_a1.id
        );
        assert_eq!(
            store
                .conversation_coordinator(None, Some("member"), Some("owner"))
                .unwrap()
                .unwrap()
                .id,
            direct_a1.id
        );
        assert!(store
            .agents_for_conversation(Some(&channel.id), None, None)
            .unwrap()
            .is_empty());
        let directory_ids = store
            .conversation_agents()
            .unwrap()
            .into_iter()
            .map(|membership| membership.agent_id)
            .collect::<Vec<_>>();
        assert!(directory_ids.contains(&channel_a1.id));
        assert!(directory_ids.contains(&direct_a1.id));
    }

    #[test]
    fn independent_threads_keep_their_assigned_workers() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let first_worker = store
            .create_agent(
                "A2",
                "First topic worker",
                "",
                &[],
                None,
                Some("ses_first"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        let second_worker = store
            .create_agent(
                "A3",
                "Second topic worker",
                "",
                &[],
                None,
                Some("ses_second"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        for worker in [&first_worker, &second_worker] {
            store
                .add_conversation_agent(&worker.id, Some(&channel.id), None, None, &[])
                .unwrap();
        }
        let first_root = store
            .add_channel_message("owner", &channel.id, "First task", &[], &[], None)
            .unwrap();
        store
            .assign_thread_agent(
                &first_worker.id,
                &first_root.id,
                Some(&channel.id),
                None,
                None,
            )
            .unwrap();
        let second_root = store
            .add_channel_message("owner", &channel.id, "Second task", &[], &[], None)
            .unwrap();
        store
            .assign_thread_agent(
                &second_worker.id,
                &second_root.id,
                Some(&channel.id),
                None,
                None,
            )
            .unwrap();
        store
            .add_channel_message(
                "owner",
                &channel.id,
                "More detail for the first task",
                &[],
                &[],
                Some(&first_root.id),
            )
            .unwrap();

        assert_eq!(
            store
                .thread_agent(&first_root.id, Some(&channel.id), None, None)
                .unwrap()
                .unwrap()
                .id,
            first_worker.id
        );
        assert_eq!(
            store
                .thread_agent(&second_root.id, Some(&channel.id), None, None)
                .unwrap()
                .unwrap()
                .id,
            second_worker.id
        );
    }

    #[test]
    fn assigns_workers_round_robin_and_reuses_workers_after_completion() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let first = store
            .create_agent(
                "A1",
                "Round-robin worker",
                "",
                &[],
                None,
                Some("ses_1"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        let second = store
            .create_agent(
                "A2",
                "Round-robin worker",
                "",
                &[],
                None,
                Some("ses_2"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        let third = store
            .create_agent(
                "A3",
                "Round-robin worker",
                "",
                &[],
                None,
                Some("ses_3"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        for worker in [&first, &second, &third] {
            store
                .add_conversation_agent(&worker.id, Some(&channel.id), None, None, &[])
                .unwrap();
        }
        let one = store
            .add_channel_message("owner", &channel.id, "one", &[], &[], None)
            .unwrap();
        let two = store
            .add_channel_message("owner", &channel.id, "two", &[], &[], None)
            .unwrap();
        let three = store
            .add_channel_message("owner", &channel.id, "three", &[], &[], None)
            .unwrap();
        assert_eq!(
            store
                .assign_oldest_available_thread_agent(&one.id, Some(&channel.id), None, None)
                .unwrap()
                .unwrap()
                .id,
            first.id
        );
        assert_eq!(
            store
                .assign_oldest_available_thread_agent(&two.id, Some(&channel.id), None, None)
                .unwrap()
                .unwrap()
                .id,
            second.id
        );
        assert_eq!(
            store
                .assign_oldest_available_thread_agent(&three.id, Some(&channel.id), None, None)
                .unwrap()
                .unwrap()
                .id,
            third.id
        );
        assert!(store
            .complete_thread("owner", &one.id, Some(&channel.id), None)
            .is_err());
        store
            .add_channel_message(
                &format!("agent:{}", first.id),
                &channel.id,
                "done",
                &[],
                &[],
                Some(&one.id),
            )
            .unwrap();
        assert!(store
            .complete_thread("owner", &one.id, Some(&channel.id), None)
            .unwrap()
            .is_some());
        assert!(store.has_completed_thread_agent(&one.id).unwrap());
        let reopened = store
            .reopen_thread("owner", &one.id, Some(&channel.id), None)
            .unwrap()
            .unwrap();
        assert_eq!(reopened.body, "[[THREAD_REOPENED]]");
        assert_eq!(
            store
                .thread_agent(&one.id, Some(&channel.id), None, None)
                .unwrap()
                .unwrap()
                .id,
            first.id
        );
        assert!(!store.has_completed_thread_agent(&one.id).unwrap());
        assert!(store
            .channel_messages(&channel.id)
            .unwrap()
            .iter()
            .any(|message| message.body == "[[THREAD_REOPENED]]"));
        let four = store
            .add_channel_message("owner", &channel.id, "four", &[], &[], None)
            .unwrap();
        assert_eq!(
            store
                .assign_oldest_available_thread_agent(&four.id, Some(&channel.id), None, None)
                .unwrap()
                .unwrap()
                .id,
            first.id
        );
        assert!(!store.has_completed_thread_agent(&one.id).unwrap());
        drop(store);
        assert!(WorkspaceStore::open(path.path())
            .unwrap()
            .channel_messages(&channel.id)
            .unwrap()
            .iter()
            .any(|message| message.body == "[[THREAD_COMPLETED]]"));
    }

    #[test]
    fn skips_related_thread_markers_when_selecting_a_reactivation_trigger() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let root = store
            .add_channel_message("owner", &channel.id, "help", &[], &[], None)
            .unwrap();
        let reply = store
            .add_channel_message("owner", &channel.id, "details", &[], &[], Some(&root.id))
            .unwrap();
        store
            .add_channel_message(
                "owner",
                &channel.id,
                "[[RELATED_THREAD: earlier]]",
                &[],
                &[],
                Some(&root.id),
            )
            .unwrap();

        assert_eq!(store.latest_thread_message_id(&root.id).unwrap(), reply.id);
    }

    #[test]
    fn tracks_one_active_related_thread_with_append_only_markers() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let first = store
            .add_channel_message("owner", &channel.id, "first", &[], &[], None)
            .unwrap();
        let second = store
            .add_channel_message("owner", &channel.id, "second", &[], &[], None)
            .unwrap();
        let third = store
            .add_channel_message("owner", &channel.id, "third", &[], &[], None)
            .unwrap();

        store
            .add_channel_message(
                "owner",
                &channel.id,
                &format!("[[RELATED_THREAD:{}]]", first.id),
                &[],
                &[],
                Some(&third.id),
            )
            .unwrap();
        store
            .add_channel_message(
                "owner",
                &channel.id,
                "ordinary reply",
                &[],
                &[],
                Some(&third.id),
            )
            .unwrap();
        assert_eq!(
            store.active_related_thread(&third.id).unwrap(),
            Some(first.id.clone())
        );

        store
            .add_channel_message(
                "owner",
                &channel.id,
                &format!("[[RELATED_THREAD:{}]]", second.id),
                &[],
                &[],
                Some(&third.id),
            )
            .unwrap();
        assert_eq!(
            store.active_related_thread(&third.id).unwrap(),
            Some(second.id)
        );

        store
            .add_channel_message(
                "owner",
                &channel.id,
                "[[RELATED_THREAD:CLEAR]]",
                &[],
                &[],
                Some(&third.id),
            )
            .unwrap();
        assert_eq!(store.active_related_thread(&third.id).unwrap(), None);
    }

    #[test]
    fn rejects_self_direct_messages_from_another_direct_conversation() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let self_direct = store
            .add_direct_message("owner", "owner", "private", &[], &[], None)
            .unwrap();
        let member_direct = store
            .add_direct_message("owner", "member", "shared", &[], &[], None)
            .unwrap();

        assert!(store
            .validate_related_thread(
                &member_direct.id,
                &self_direct.id,
                None,
                Some("owner"),
                Some("member"),
            )
            .is_err());
    }

    #[test]
    fn persists_channel_and_direct_conversation_preprompts() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        store
            .set_conversation_preprompt(
                Some(&channel.id),
                None,
                None,
                "Review carefully.",
                &[],
                Some(true),
                None,
            )
            .unwrap();
        store
            .set_conversation_preprompt(
                None,
                Some("member"),
                Some("owner"),
                "Be concise.",
                &[],
                None,
                None,
            )
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
        assert!(preprompts[1].agent_routing_enabled);

        let store = WorkspaceStore::open(path.path()).unwrap();
        store
            .set_conversation_preprompt(Some(&channel.id), None, None, "", &[], Some(false), None)
            .unwrap();
        assert_eq!(store.conversation_preprompts().unwrap().len(), 1);
    }

    #[test]
    fn persists_workspace_default_agent_prompt_separately() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store
            .set_default_agent_prompt("Use concise updates.")
            .unwrap();
        drop(store);

        let store = WorkspaceStore::open(path.path()).unwrap();
        assert_eq!(
            store.default_agent_prompt().unwrap().as_deref(),
            Some("Use concise updates.")
        );
        let default = store
            .conversation_preprompts()
            .unwrap()
            .into_iter()
            .find(|prompt| prompt.channel_id.as_deref() == Some(""))
            .unwrap();
        assert_eq!(default.preprompt, "Use concise updates.");

        store.set_default_agent_prompt("").unwrap();
        assert_eq!(store.default_agent_prompt().unwrap(), None);
    }

    #[test]
    fn persists_one_native_session_per_conversation() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        store.add_member("member").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        store
            .upsert_conversation_session(
                Some(&channel.id),
                None,
                None,
                "/work/phone",
                "ses_first",
                "ready",
                None,
            )
            .unwrap();
        store
            .upsert_conversation_session(
                Some(&channel.id),
                None,
                None,
                "/work/phone",
                "ses_second",
                "failed",
                Some("offline"),
            )
            .unwrap();
        drop(store);

        let store = WorkspaceStore::open(path.path()).unwrap();
        let channel_session = store
            .conversation_session(Some(&channel.id), None, None)
            .unwrap()
            .unwrap();
        assert_eq!(channel_session.opencode_session_id, "ses_second");
        assert_eq!(channel_session.session_error.as_deref(), Some("offline"));
        assert_eq!(channel_session.session_context, None);
        store
            .set_conversation_session_context(Some(&channel.id), None, None, "scope-17-abcdef")
            .unwrap();
        assert_eq!(
            store
                .conversation_session(Some(&channel.id), None, None)
                .unwrap()
                .unwrap()
                .session_context
                .as_deref(),
            Some("scope-17-abcdef")
        );
        store
            .upsert_conversation_session(
                Some(&channel.id),
                None,
                None,
                "/work/other",
                "ses_first_reused",
                "ready",
                None,
            )
            .unwrap();
        assert!(store
            .conversation_session(Some(&channel.id), None, None)
            .unwrap()
            .is_some_and(|session| session.opencode_session_id == "ses_first_reused"));
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

    #[test]
    fn persists_one_board_task_workstream_across_reopen() {
        let path = tempfile::NamedTempFile::new().unwrap();
        let store = WorkspaceStore::open(path.path()).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let task = store
            .create_board_task(
                "owner",
                "Implement workstream",
                &format!("channel:{}", channel.id),
                "Implement the workstream.",
                &["/tmp".to_string()],
                "once",
                1,
            )
            .unwrap();
        let root = store
            .add_channel_message(
                "owner",
                &channel.id,
                "Implement the workstream.",
                &[],
                &[],
                None,
            )
            .unwrap();
        let agent = store
            .create_agent(
                "Task agent",
                "Board task worker",
                "",
                &[],
                None,
                Some("ses_task"),
                "ready",
                None,
                "owner",
            )
            .unwrap();

        store
            .link_board_task_workstream(&task.id, &root.id, &agent.id)
            .unwrap();
        assert!(store
            .link_board_task_workstream(&task.id, &root.id, &agent.id)
            .is_err());
        drop(store);

        let reopened = WorkspaceStore::open(path.path()).unwrap();
        assert_eq!(
            reopened.board_task_workstream(&task.id).unwrap(),
            Some(WorkspaceBoardTaskWorkstream {
                task_id: task.id,
                root_message_id: root.id,
                agent_id: agent.id,
            })
        );
    }

    #[test]
    fn board_integrations_are_fifo_and_cancellation_removes_queued_work() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let make_task = |title: &str| {
            let task = store
                .create_board_task(
                    "owner",
                    title,
                    &format!("channel:{}", channel.id),
                    "Implement it.",
                    &[],
                    "once",
                    1,
                )
                .unwrap();
            let root = store
                .add_channel_message("owner", &channel.id, title, &[], &[], None)
                .unwrap();
            let proposal = store
                .add_channel_message("owner", &channel.id, "Proposal", &[], &[], Some(&root.id))
                .unwrap();
            let agent = store
                .create_agent(
                    "Task agent",
                    "Board task worker",
                    "",
                    &[],
                    None,
                    Some("ses_task"),
                    "ready",
                    None,
                    "owner",
                )
                .unwrap();
            store
                .link_board_task_workstream(&task.id, &root.id, &agent.id)
                .unwrap();
            (task, proposal)
        };
        let (first, first_proposal) = make_task("first");
        let (second, second_proposal) = make_task("second");
        let first_integration = store
            .enqueue_board_integration(&first.id, &first_proposal.id)
            .unwrap();
        store
            .enqueue_board_integration(&second.id, &second_proposal.id)
            .unwrap();

        assert_eq!(
            store
                .claim_next_board_integration(&first.conversation_key)
                .unwrap()
                .unwrap()
                .id,
            first_integration.id
        );
        store.cancel_board_task(&second.id).unwrap();
        assert!(store
            .claim_next_board_integration(&first.conversation_key)
            .unwrap()
            .is_none());
    }

    #[test]
    fn completed_board_integration_records_its_private_head_result() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let task = store
            .create_board_task(
                "owner",
                "first",
                &format!("channel:{}", channel.id),
                "Implement it.",
                &[],
                "once",
                1,
            )
            .unwrap();
        let root = store
            .add_channel_message("owner", &channel.id, "first", &[], &[], None)
            .unwrap();
        let proposal = store
            .add_channel_message("owner", &channel.id, "Proposal", &[], &[], Some(&root.id))
            .unwrap();
        let agent = store
            .create_agent(
                "Task agent",
                "Board task worker",
                "",
                &[],
                None,
                Some("ses_task"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        store
            .link_board_task_workstream(&task.id, &root.id, &agent.id)
            .unwrap();
        store.claim_due_board_task(&task.id, 1).unwrap();
        store.start_board_task(&task.id, 1).unwrap();
        let integration = store
            .enqueue_board_integration(&task.id, &proposal.id)
            .unwrap();
        store
            .claim_next_board_integration(&task.conversation_key)
            .unwrap()
            .unwrap();

        assert!(store
            .finish_board_integration(&integration.id, Ok("Applied the proposal."))
            .unwrap());

        assert!(store
            .claim_next_board_integration(&task.conversation_key)
            .unwrap()
            .is_none());
        assert!(store
            .board_timeline(&task.id)
            .unwrap()
            .iter()
            .any(|entry| entry.detail == "Applied the proposal."));
    }

    #[test]
    fn board_proposal_is_enqueued_once_and_completion_finishes_the_task_run() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let task = store
            .create_board_task(
                "owner",
                "first",
                &format!("channel:{}", channel.id),
                "Implement it.",
                &[],
                "once",
                1,
            )
            .unwrap();
        let root = store
            .add_channel_message("owner", &channel.id, "first", &[], &[], None)
            .unwrap();
        let proposal = store
            .add_channel_message(
                "agent:task",
                &channel.id,
                "Proposal",
                &[],
                &[],
                Some(&root.id),
            )
            .unwrap();
        let agent = store
            .create_agent(
                "Task agent",
                "Board task worker",
                "",
                &[],
                None,
                Some("ses_task"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        store
            .link_board_task_workstream(&task.id, &root.id, &agent.id)
            .unwrap();
        store.claim_due_board_task(&task.id, 1).unwrap();
        store.start_board_task(&task.id, 1).unwrap();

        let integration = store
            .mark_board_proposal_ready(&task.id, &proposal.id)
            .unwrap()
            .unwrap();
        assert!(store
            .mark_board_proposal_ready(&task.id, &proposal.id)
            .unwrap()
            .is_none());
        store
            .claim_next_board_integration(&task.conversation_key)
            .unwrap()
            .unwrap();
        assert!(store
            .finish_board_integration(&integration.id, Ok("Applied."))
            .unwrap());
        assert!(store
            .mark_board_proposal_ready(&task.id, &proposal.id)
            .unwrap()
            .is_none());

        assert_eq!(store.board_tasks().unwrap()[0].state, "done");
        assert_eq!(store.board_runs(&task.id).unwrap()[0].state, "completed");
    }

    #[test]
    fn recurring_task_keeps_integration_history_across_runs_and_retries() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let task = store
            .create_board_task(
                "owner",
                "daily",
                &format!("channel:{}", channel.id),
                "Implement it.",
                &[],
                "daily",
                1,
            )
            .unwrap();
        let root = store
            .add_channel_message("owner", &channel.id, "daily", &[], &[], None)
            .unwrap();
        let agent = store
            .create_agent(
                "Task agent",
                "Board task worker",
                "",
                &[],
                None,
                Some("ses_task"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        store
            .link_board_task_workstream(&task.id, &root.id, &agent.id)
            .unwrap();

        let first = store
            .add_channel_message(
                "agent:task",
                &channel.id,
                "First proposal",
                &[],
                &[],
                Some(&root.id),
            )
            .unwrap();
        store.claim_due_board_task(&task.id, 1).unwrap();
        store.start_board_task(&task.id, 1).unwrap();
        let first_integration = store
            .mark_board_proposal_ready(&task.id, &first.id)
            .unwrap()
            .unwrap();
        store
            .claim_next_board_integration(&task.conversation_key)
            .unwrap();
        store
            .finish_board_integration(&first_integration.id, Ok("Applied first."))
            .unwrap();

        let second = store
            .add_channel_message(
                "agent:task",
                &channel.id,
                "Second proposal",
                &[],
                &[],
                Some(&root.id),
            )
            .unwrap();
        store
            .claim_due_board_task(&task.id, 24 * 60 * 60 + 1)
            .unwrap();
        store.start_board_task(&task.id, 24 * 60 * 60 + 1).unwrap();
        let second_integration = store
            .mark_board_proposal_ready(&task.id, &second.id)
            .unwrap()
            .unwrap();
        store
            .claim_next_board_integration(&task.conversation_key)
            .unwrap();
        store
            .finish_board_integration(&second_integration.id, Err(anyhow!("head failed")))
            .unwrap();

        store
            .retry_board_task(&task.id, 2 * 24 * 60 * 60 + 1)
            .unwrap();
        let retried = store
            .add_channel_message(
                "agent:task",
                &channel.id,
                "Retried proposal",
                &[],
                &[],
                Some(&root.id),
            )
            .unwrap();
        store
            .claim_due_board_task(&task.id, 2 * 24 * 60 * 60 + 1)
            .unwrap();
        store
            .start_board_task(&task.id, 2 * 24 * 60 * 60 + 1)
            .unwrap();
        assert!(store
            .mark_board_proposal_ready(&task.id, &retried.id)
            .unwrap()
            .is_some());
    }

    #[test]
    fn cancelling_running_task_cancels_active_integration_and_prevents_finish() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let task = store
            .create_board_task(
                "owner",
                "first",
                &format!("channel:{}", channel.id),
                "Implement it.",
                &[],
                "once",
                1,
            )
            .unwrap();
        let root = store
            .add_channel_message("owner", &channel.id, "first", &[], &[], None)
            .unwrap();
        let proposal = store
            .add_channel_message(
                "agent:task",
                &channel.id,
                "Proposal",
                &[],
                &[],
                Some(&root.id),
            )
            .unwrap();
        let agent = store
            .create_agent(
                "Task agent",
                "Board task worker",
                "",
                &[],
                None,
                Some("ses_task"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        store
            .link_board_task_workstream(&task.id, &root.id, &agent.id)
            .unwrap();
        store.claim_due_board_task(&task.id, 1).unwrap();
        store.start_board_task(&task.id, 1).unwrap();
        let integration = store
            .mark_board_proposal_ready(&task.id, &proposal.id)
            .unwrap()
            .unwrap();
        store
            .claim_next_board_integration(&task.conversation_key)
            .unwrap();

        store.cancel_board_task(&task.id).unwrap();

        assert_eq!(store.board_tasks().unwrap()[0].state, "cancelled");
        assert_eq!(store.board_runs(&task.id).unwrap()[0].state, "cancelled");
        assert!(!store
            .finish_board_integration(&integration.id, Ok("too late"))
            .unwrap());
    }

    #[test]
    fn linked_board_task_cannot_change_conversation_or_scope() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let other = store.create_channel("design", "owner").unwrap();
        let task = store
            .create_board_task(
                "owner",
                "first",
                &format!("channel:{}", channel.id),
                "Implement it.",
                &["/tmp".to_string()],
                "once",
                1,
            )
            .unwrap();
        let root = store
            .add_channel_message("owner", &channel.id, "first", &[], &[], None)
            .unwrap();
        let agent = store
            .create_agent(
                "Task agent",
                "Board task worker",
                "",
                &[],
                None,
                Some("ses_task"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        store
            .link_board_task_workstream(&task.id, &root.id, &agent.id)
            .unwrap();

        assert!(store
            .update_board_task(
                &task.id,
                "first",
                &format!("channel:{}", other.id),
                "Implement it.",
                &["/tmp".to_string()],
                "once",
                1
            )
            .is_err());
        assert!(store
            .update_board_task(
                &task.id,
                "first",
                &format!("channel:{}", channel.id),
                "Implement it.",
                &["/var/tmp".to_string()],
                "once",
                1
            )
            .is_err());
    }

    #[test]
    fn restart_preserves_queued_integrations_until_they_complete() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let task = store
            .create_board_task(
                "owner",
                "first",
                &format!("channel:{}", channel.id),
                "Implement it.",
                &[],
                "once",
                1,
            )
            .unwrap();
        let root = store
            .add_channel_message("owner", &channel.id, "first", &[], &[], None)
            .unwrap();
        let proposal = store
            .add_channel_message(
                "agent:task",
                &channel.id,
                "Proposal",
                &[],
                &[],
                Some(&root.id),
            )
            .unwrap();
        let agent = store
            .create_agent(
                "Task agent",
                "Board task worker",
                "",
                &[],
                None,
                Some("ses_task"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        store
            .link_board_task_workstream(&task.id, &root.id, &agent.id)
            .unwrap();
        store.claim_due_board_task(&task.id, 1).unwrap();
        store.start_board_task(&task.id, 1).unwrap();
        let integration = store
            .mark_board_proposal_ready(&task.id, &proposal.id)
            .unwrap()
            .unwrap();

        store.recover_board_integrations().unwrap();
        store.recover_board_task_workstreams().unwrap();

        assert_eq!(store.board_tasks().unwrap()[0].state, "running");
        assert_eq!(
            store
                .claim_next_board_integration(&task.conversation_key)
                .unwrap()
                .unwrap()
                .id,
            integration.id
        );
        assert!(store
            .finish_board_integration(&integration.id, Ok("Applied after restart."))
            .unwrap());
        assert_eq!(store.board_tasks().unwrap()[0].state, "done");
    }

    #[test]
    fn restart_blocks_running_task_workstreams_without_an_integration() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let task = store
            .create_board_task(
                "owner",
                "first",
                &format!("channel:{}", channel.id),
                "Implement it.",
                &[],
                "once",
                1,
            )
            .unwrap();
        let root = store
            .add_channel_message("owner", &channel.id, "first", &[], &[], None)
            .unwrap();
        let agent = store
            .create_agent(
                "Task agent",
                "Board task worker",
                "",
                &[],
                None,
                Some("ses_task"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        store
            .link_board_task_workstream(&task.id, &root.id, &agent.id)
            .unwrap();
        store.claim_due_board_task(&task.id, 1).unwrap();
        store.start_board_task(&task.id, 1).unwrap();

        store.recover_board_task_workstreams().unwrap();

        assert_eq!(store.board_tasks().unwrap()[0].state, "blocked");
        assert_eq!(store.board_runs(&task.id).unwrap()[0].state, "blocked");
        assert!(store
            .board_timeline(&task.id)
            .unwrap()
            .iter()
            .any(|entry| entry.detail.contains("Task worker interrupted")));
    }

    #[test]
    fn agent_handoffs_survive_store_reopen() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let (reply_id, agent_id) = {
            let store = WorkspaceStore::open(file.path()).unwrap();
            store.add_member("owner").unwrap();
            let channel = store.create_channel("engineering", "owner").unwrap();
            let agent = store
                .create_agent(
                    "A0",
                    "Coordinator",
                    "",
                    &[],
                    None,
                    Some("session"),
                    "ready",
                    None,
                    "owner",
                )
                .unwrap();
            let mentions = vec![WorkspaceMentionPayload {
                kind: "agent".to_string(),
                id: agent.id.clone(),
                label: "Coordinator".to_string(),
            }];
            let reply = store
                .add_channel_message(
                    "agent:a1",
                    &channel.id,
                    "@Coordinator",
                    &[],
                    &mentions,
                    None,
                )
                .unwrap();
            store.queue_agent_handoffs(&reply.id, &mentions).unwrap();
            (reply.id, agent.id)
        };

        let store = WorkspaceStore::open_existing(file.path()).unwrap();
        assert_eq!(
            store.pending_agent_handoffs().unwrap(),
            vec![WorkspaceAgentHandoffOutboxEntry {
                reply_message_id: reply_id,
                agent_id,
                member_pubkey: None,
                peer_pubkey: None,
            }]
        );
    }

    #[test]
    fn incoming_handoff_completion_is_atomic_with_reply_after_reopen() {
        for direct in [false, true] {
            for rollback in [false, true] {
                let file = tempfile::NamedTempFile::new().unwrap();
                let store = WorkspaceStore::open(file.path()).unwrap();
                store.add_member("alice").unwrap();
                store.add_member("bob").unwrap();
                let channel = store.create_channel("engineering", "alice").unwrap();
                let agent = store
                    .create_agent(
                        "A0",
                        "Coordinator",
                        "",
                        &[],
                        None,
                        Some("session"),
                        "ready",
                        None,
                        "alice",
                    )
                    .unwrap();
                let mentions = [WorkspaceMentionPayload {
                    kind: "agent".to_string(),
                    id: agent.id.clone(),
                    label: "Coordinator".to_string(),
                }];
                let incoming = store
                    .add_channel_message("alice", &channel.id, "implement", &[], &mentions, None)
                    .unwrap();
                store.queue_agent_handoffs(&incoming.id, &mentions).unwrap();
                let revision = store.revision().unwrap();
                if rollback {
                    store.conn.execute_batch(
                        "CREATE TRIGGER fail_handoff_completion BEFORE DELETE ON workspace_agent_handoff_outbox
                         BEGIN SELECT RAISE(ABORT, 'simulated completion failure'); END;",
                    ).unwrap();
                }
                let result = if direct {
                    store.add_direct_agent_reply_with_handoffs(
                        "agent:a0",
                        "bob",
                        "completed",
                        &mentions,
                        None,
                        false,
                        "alice",
                        "bob",
                        Some(&(incoming.id.clone(), agent.id.clone())),
                    )
                } else {
                    store.add_channel_agent_reply_with_handoffs(
                        "agent:a0",
                        &channel.id,
                        "completed",
                        &mentions,
                        None,
                        false,
                        Some(&(incoming.id.clone(), agent.id.clone())),
                    )
                };
                if rollback {
                    assert!(result.is_err());
                } else {
                    assert!(result.is_ok());
                }
                let reply_id = result.ok().map(|(reply, _)| reply.id);
                drop(store);
                let store = WorkspaceStore::open_existing(file.path()).unwrap();
                let pending = store.pending_agent_handoffs().unwrap();
                assert_eq!(pending.len(), 1);
                if rollback {
                    assert_eq!(pending[0].reply_message_id, incoming.id);
                    assert_eq!(store.revision().unwrap(), revision);
                    assert_eq!(store.channel_messages(&channel.id).unwrap().len(), 1);
                    assert!(store.direct_messages("agent:a0", "bob").unwrap().is_empty());
                } else {
                    assert_eq!(pending[0].reply_message_id, reply_id.unwrap());
                    assert_eq!(
                        store
                            .message_by_id(&pending[0].reply_message_id)
                            .unwrap()
                            .unwrap()
                            .body,
                        "completed"
                    );
                }
            }
        }
    }

    #[test]
    fn agent_reply_handoff_transaction_rolls_back_both_writes() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let invalid_mention = [WorkspaceMentionPayload {
            kind: "agent".to_string(),
            id: "missing".to_string(),
            label: "Coordinator".to_string(),
        }];

        assert!(store
            .add_channel_agent_reply_with_handoffs(
                "agent:a1",
                &channel.id,
                "@Coordinator",
                &invalid_mention,
                None,
                false,
                None,
            )
            .is_err());
        assert!(store.channel_messages(&channel.id).unwrap().is_empty());
        assert!(store.pending_agent_handoffs().unwrap().is_empty());
    }

    #[test]
    fn direct_agent_handoff_retains_human_conversation() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("alice").unwrap();
        store.add_member("bob").unwrap();
        let coordinator = store
            .create_agent(
                "A0",
                "Coordinator",
                "",
                &[],
                None,
                Some("session"),
                "ready",
                None,
                "alice",
            )
            .unwrap();
        let mentions = [WorkspaceMentionPayload {
            kind: "agent".to_string(),
            id: coordinator.id.clone(),
            label: "Coordinator".to_string(),
        }];

        let (_, handoffs) = store
            .add_direct_agent_reply_with_handoffs(
                &format!("agent:{}", coordinator.id),
                "bob",
                "@Coordinator",
                &mentions,
                None,
                false,
                "alice",
                "bob",
                None,
            )
            .unwrap();

        assert_eq!(handoffs[0].member_pubkey, Some("alice".to_string()));
        assert_eq!(handoffs[0].peer_pubkey, Some("bob".to_string()));
    }

    #[test]
    fn deleting_target_agent_cancels_pending_handoff() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let agent = store
            .create_agent(
                "A0",
                "Coordinator",
                "",
                &[],
                None,
                Some("session"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        let mentions = [WorkspaceMentionPayload {
            kind: "agent".to_string(),
            id: agent.id.clone(),
            label: "Coordinator".to_string(),
        }];
        store
            .add_channel_agent_reply_with_handoffs(
                "agent:a1",
                &channel.id,
                "@Coordinator",
                &mentions,
                None,
                false,
                None,
            )
            .unwrap();

        store.delete_agent(&agent.id).unwrap();

        assert!(store.pending_agent_handoffs().unwrap().is_empty());
    }

    #[test]
    fn tombstoning_handoff_reply_cancels_pending_handoff() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let agent = store
            .create_agent(
                "A0",
                "Coordinator",
                "",
                &[],
                None,
                Some("session"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        let mentions = [WorkspaceMentionPayload {
            kind: "agent".to_string(),
            id: agent.id,
            label: "Coordinator".to_string(),
        }];
        let reply = store
            .add_channel_message("owner", &channel.id, "@Coordinator", &[], &mentions, None)
            .unwrap();
        store.queue_agent_handoffs(&reply.id, &mentions).unwrap();

        store.delete_message("owner", &reply.id).unwrap();

        assert!(store.pending_agent_handoffs().unwrap().is_empty());
    }

    #[test]
    fn tombstoning_thread_root_cancels_child_handoff() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let agent = store
            .create_agent(
                "A0",
                "Coordinator",
                "",
                &[],
                None,
                Some("session"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        let root = store
            .add_channel_message("owner", &channel.id, "Root", &[], &[], None)
            .unwrap();
        let mentions = [WorkspaceMentionPayload {
            kind: "agent".to_string(),
            id: agent.id,
            label: "Coordinator".to_string(),
        }];
        let (child, _) = store
            .add_channel_agent_reply_with_handoffs(
                "agent:a1",
                &channel.id,
                "@Coordinator",
                &mentions,
                Some(&root.id),
                false,
                None,
            )
            .unwrap();

        store.delete_message("owner", &root.id).unwrap();

        assert!(store.pending_agent_handoffs().unwrap().is_empty());
        assert!(store.message(&child.id).unwrap().deleted_at.is_none());
    }

    #[test]
    fn migrates_handoff_outbox_without_direct_participant_columns() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let connection = Connection::open(file.path()).unwrap();
        connection.execute_batch("CREATE TABLE workspace_agent_handoff_outbox (reply_message_id TEXT NOT NULL, agent_id TEXT NOT NULL, PRIMARY KEY (reply_message_id, agent_id));").unwrap();
        drop(connection);

        let store = WorkspaceStore::open(file.path()).unwrap();
        let columns = store
            .conn
            .prepare("PRAGMA table_info(workspace_agent_handoff_outbox)")
            .unwrap()
            .query_map([], |row| row.get::<_, String>(1))
            .unwrap()
            .collect::<rusqlite::Result<Vec<_>>>()
            .unwrap();

        assert!(columns.contains(&"member_pubkey".to_string()));
        assert!(columns.contains(&"peer_pubkey".to_string()));
    }

    #[test]
    fn completed_thread_agent_turn_is_not_requeued_after_restart() {
        let store = WorkspaceStore::open(Path::new(":memory:")).unwrap();
        store.add_member("owner").unwrap();
        let channel = store.create_channel("engineering", "owner").unwrap();
        let root = store
            .add_channel_message("owner", &channel.id, "Task", &[], &[], None)
            .unwrap();
        let agent = store
            .create_agent(
                "A1",
                "Conversation worker",
                "",
                &[],
                None,
                Some("session-1"),
                "ready",
                None,
                "owner",
            )
            .unwrap();
        store
            .add_conversation_agent(&agent.id, Some(&channel.id), None, None, &[])
            .unwrap();
        store
            .assign_thread_agent(&agent.id, &root.id, Some(&channel.id), None, None)
            .unwrap();
        store
            .add_channel_message(
                &format!("agent:{}", agent.id),
                &channel.id,
                "Done",
                &[],
                &[],
                Some(&root.id),
            )
            .unwrap();

        assert!(store.pending_thread_agent_turns().unwrap().is_empty());
    }
}
