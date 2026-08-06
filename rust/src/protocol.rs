use anyhow::{anyhow, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::{json, Value};

pub const AUDIO_ENCRYPTION_ALGORITHM: &str = "xchacha20poly1305";
pub type AttachmentEncryption = AudioEncryption;
pub type AttachmentReference = MediaReference;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum WireMessage {
    Query {
        query: String,
    },
    Cancel {
        cancel_request: CancelRequest,
    },
    Audio {
        audio: AudioReference,
    },
    MediaBundle {
        media_bundle: MediaBundle,
    },
    AudioRetry {
        audio_retry: AudioRetryRequest,
    },
    CallInvite {
        call_invite: CallControl,
    },
    CallAnswer {
        call_answer: CallControl,
    },
    CallHangup {
        call_hangup: CallControl,
    },
    GroupCallInvite {
        group_call_invite: GroupCallControl,
    },
    GroupCallAnswer {
        group_call_answer: GroupCallControl,
    },
    GroupCallHangup {
        group_call_hangup: GroupCallControl,
    },
    TargetInvite {
        target_invite: TargetInvite,
    },
    CreateInvite {
        create_invite: CreateInvite,
    },
    InviteCreated {
        invite_created: InviteCreated,
    },
    RedeemInvite {
        redeem_invite: RedeemInvite,
    },
    InviteAccepted {
        invite_accepted: InviteAccepted,
    },
    InviteRejected {
        invite_rejected: InviteRejected,
    },
    WorkspaceRequest {
        workspace_request: WorkspaceRequest,
    },
    WorkspaceUpdate {
        workspace_update: WorkspaceUpdate,
    },
    RepoList {
        repo_list: RepoList,
    },
    OpenCodeSessionList {
        opencode_sessions: OpenCodeSessionList,
    },
    ToolResult {
        tool_result: ToolResult,
    },
    Transcript {
        transcript: String,
    },
    Status {
        status: String,
    },
    Response {
        response: String,
    },
    RoutedResponse {
        response: String,
        workdir: String,
    },
    Error {
        error: String,
    },
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
pub struct CallControl {
    pub call_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sender_pubkey: Option<String>,
}

/// Channel-call signaling. Media remains a direct FIPS connection between each
/// pair in `participant_pubkeys`; the worker only validates and forwards this.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GroupCallControl {
    pub call_id: String,
    pub channel_id: String,
    pub participant_pubkeys: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sender_pubkey: Option<String>,
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CancelRequest {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub event_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TargetInvite {
    #[serde(rename = "type")]
    pub target_type: String,
    pub version: u64,
    pub name: String,
    pub pubkey: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pubkey_hex: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workdir: Option<String>,
    #[serde(default)]
    pub relays: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent: Option<TargetParent>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreateInvite {
    #[serde(default)]
    pub expires_in_seconds: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InviteCreated {
    pub code: String,
    pub expires_at: i64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RedeemInvite {
    pub code: String,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InviteAccepted {
    pub recipient_pubkey: String,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InviteRejected {
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceRequest {
    pub action: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub channel_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub channel_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recipient_pubkey: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub attachments: Vec<MediaReference>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub mentions: Vec<WorkspaceMentionPayload>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_id: Option<String>,
    #[serde(default)]
    pub also_send_to_main: bool,
    /// Client supports FIPS reliable-stream workspace snapshot delivery.
    #[serde(default)]
    pub fips_snapshot: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reaction: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_role: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_traits: Option<String>,
    #[serde(default)]
    pub agent_skills: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_preset: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opencode_provider_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opencode_provider_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opencode_model_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opencode_model_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opencode_agent: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_workdir: Option<String>,
    #[serde(default = "default_restart_agent_session")]
    pub restart_agent_session_on_failure: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opencode_session_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expires_in_seconds: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub call_id: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub participant_pubkeys: Vec<String>,
    /// Canonical worker folders an agent may use for this conversation.
    /// A selected folder includes every repository below it.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub folder_scope: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceMentionPayload {
    pub kind: String,
    pub id: String,
    pub label: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceUpdate {
    pub action: String,
    #[serde(default)]
    pub channels: Vec<WorkspaceChannelPayload>,
    #[serde(default, deserialize_with = "deserialize_workspace_members")]
    pub members: Vec<WorkspaceMemberPayload>,
    #[serde(default)]
    pub messages: Vec<WorkspaceMessagePayload>,
    #[serde(default)]
    pub agents: Vec<WorkspaceAgentPayload>,
    #[serde(default)]
    pub conversation_agents: Vec<WorkspaceConversationAgentPayload>,
    #[serde(default)]
    pub conversation_preprompts: Vec<WorkspaceConversationPrepromptPayload>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub typing: Option<WorkspaceTypingPayload>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceTypingPayload {
    pub sender_pubkey: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stage: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub channel_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recipient_pubkey: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub member_pubkey: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub peer_pubkey: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_id: Option<String>,
    pub expires_at: i64,
}

fn default_agent_session_status() -> String {
    "failed".to_string()
}

fn default_restart_agent_session() -> bool {
    true
}

fn default_agent_availability() -> String {
    "unavailable".to_string()
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceAgentPayload {
    pub id: String,
    pub name: String,
    pub role: String,
    #[serde(default)]
    pub traits: String,
    #[serde(default)]
    pub skills: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub preset: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opencode_provider_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opencode_provider_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opencode_model_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opencode_model_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opencode_agent: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workdir: Option<String>,
    #[serde(default = "default_restart_agent_session")]
    pub restart_on_failure: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opencode_session_id: Option<String>,
    #[serde(default = "default_agent_session_status")]
    pub session_status: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_error: Option<String>,
    /// Current worker-side availability: available, busy, stuck, errored, or unavailable.
    #[serde(default = "default_agent_availability")]
    pub availability: String,
    /// Best-effort metrics for the active OpenCode systemd scope.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scope_memory_bytes: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scope_cpu_usage_nsec: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scope_task_count: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scope_started_at: Option<i64>,
    #[serde(default)]
    pub instance_id: String,
    pub created_by: String,
    pub created_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub initialized_at: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_tokens: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_tokens: Option<i64>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceConversationAgentPayload {
    pub agent_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub channel_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub member_pubkey: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub peer_pubkey: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub folder_scope: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceConversationPrepromptPayload {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub channel_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub member_pubkey: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub peer_pubkey: Option<String>,
    pub preprompt: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceMemberPayload {
    pub pubkey: String,
    #[serde(default)]
    pub display_name: String,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum WorkspaceMemberWire {
    Payload(WorkspaceMemberPayload),
    LegacyPubkey(String),
}

fn deserialize_workspace_members<'de, D>(
    deserializer: D,
) -> std::result::Result<Vec<WorkspaceMemberPayload>, D::Error>
where
    D: Deserializer<'de>,
{
    Vec::<WorkspaceMemberWire>::deserialize(deserializer).map(|members| {
        members
            .into_iter()
            .filter_map(|member| match member {
                WorkspaceMemberWire::Payload(member) => Some(member),
                WorkspaceMemberWire::LegacyPubkey(pubkey) => {
                    let pubkey = pubkey.trim().to_string();
                    (!pubkey.is_empty()).then_some(WorkspaceMemberPayload {
                        pubkey,
                        display_name: String::new(),
                    })
                }
            })
            .collect()
    })
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceChannelPayload {
    pub id: String,
    pub name: String,
    pub created_by: String,
    pub created_at: i64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceMessagePayload {
    pub id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub channel_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recipient_pubkey: Option<String>,
    pub sender_pubkey: String,
    pub body: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub attachments: Vec<MediaReference>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub mentions: Vec<WorkspaceMentionPayload>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_id: Option<String>,
    #[serde(default)]
    pub also_send_to_main: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub reactions: Vec<WorkspaceReactionPayload>,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceReactionPayload {
    pub emoji: String,
    pub sender_pubkey: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TargetParent {
    pub name: String,
    pub pubkey: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pubkey_hex: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workdir: Option<String>,
    #[serde(default)]
    pub relays: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RepoList {
    #[serde(default)]
    pub roots: Vec<RepoListRoot>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RepoListRoot {
    pub root: String,
    #[serde(default)]
    pub repos: Vec<RepoListEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RepoListEntry {
    pub name: String,
    pub path: String,
    pub relative_path: String,
    pub is_git_repo: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OpenCodeSessionList {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workdir: Option<String>,
    #[serde(default)]
    pub sessions: Vec<OpenCodeSessionListEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OpenCodeSessionListEntry {
    pub id: String,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub directory: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolResult {
    pub tool: String,
    pub request_id: String,
    pub workdir: String,
    pub data: Value,
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

    pub fn cancel(event_id: Option<String>) -> Self {
        Self::Cancel {
            cancel_request: CancelRequest { event_id },
        }
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
    pub fn call_invite(call_id: impl Into<String>) -> Self {
        Self::call_invite_with_sender(call_id, None)
    }
    fn call_invite_with_sender(call_id: impl Into<String>, sender_pubkey: Option<String>) -> Self {
        Self::CallInvite {
            call_invite: CallControl {
                call_id: call_id.into(),
                sender_pubkey,
            },
        }
    }
    pub fn call_invite_from(call_id: impl Into<String>, sender_pubkey: impl Into<String>) -> Self {
        Self::call_invite_with_sender(call_id, Some(sender_pubkey.into()))
    }
    pub fn call_answer(call_id: impl Into<String>) -> Self {
        Self::call_answer_with_sender(call_id, None)
    }
    fn call_answer_with_sender(call_id: impl Into<String>, sender_pubkey: Option<String>) -> Self {
        Self::CallAnswer {
            call_answer: CallControl {
                call_id: call_id.into(),
                sender_pubkey,
            },
        }
    }
    pub fn call_answer_from(call_id: impl Into<String>, sender_pubkey: impl Into<String>) -> Self {
        Self::call_answer_with_sender(call_id, Some(sender_pubkey.into()))
    }
    pub fn call_hangup(call_id: impl Into<String>) -> Self {
        Self::call_hangup_with_sender(call_id, None)
    }
    fn call_hangup_with_sender(call_id: impl Into<String>, sender_pubkey: Option<String>) -> Self {
        Self::CallHangup {
            call_hangup: CallControl {
                call_id: call_id.into(),
                sender_pubkey,
            },
        }
    }
    pub fn call_hangup_from(call_id: impl Into<String>, sender_pubkey: impl Into<String>) -> Self {
        Self::call_hangup_with_sender(call_id, Some(sender_pubkey.into()))
    }
    pub fn group_call_invite_from(
        call_id: impl Into<String>,
        channel_id: impl Into<String>,
        participants: Vec<String>,
        sender: impl Into<String>,
    ) -> Self {
        Self::GroupCallInvite {
            group_call_invite: GroupCallControl {
                call_id: call_id.into(),
                channel_id: channel_id.into(),
                participant_pubkeys: participants,
                sender_pubkey: Some(sender.into()),
            },
        }
    }
    pub fn group_call_answer_from(
        call_id: impl Into<String>,
        channel_id: impl Into<String>,
        participants: Vec<String>,
        sender: impl Into<String>,
    ) -> Self {
        Self::GroupCallAnswer {
            group_call_answer: GroupCallControl {
                call_id: call_id.into(),
                channel_id: channel_id.into(),
                participant_pubkeys: participants,
                sender_pubkey: Some(sender.into()),
            },
        }
    }
    pub fn group_call_hangup_from(
        call_id: impl Into<String>,
        channel_id: impl Into<String>,
        participants: Vec<String>,
        sender: impl Into<String>,
    ) -> Self {
        Self::GroupCallHangup {
            group_call_hangup: GroupCallControl {
                call_id: call_id.into(),
                channel_id: channel_id.into(),
                participant_pubkeys: participants,
                sender_pubkey: Some(sender.into()),
            },
        }
    }

    pub fn target_invite(target_invite: TargetInvite) -> Self {
        Self::TargetInvite { target_invite }
    }
    pub fn create_invite(create_invite: CreateInvite) -> Self {
        Self::CreateInvite { create_invite }
    }
    pub fn invite_created(invite_created: InviteCreated) -> Self {
        Self::InviteCreated { invite_created }
    }
    pub fn redeem_invite(redeem_invite: RedeemInvite) -> Self {
        Self::RedeemInvite { redeem_invite }
    }
    pub fn invite_accepted(invite_accepted: InviteAccepted) -> Self {
        Self::InviteAccepted { invite_accepted }
    }
    pub fn invite_rejected(invite_rejected: InviteRejected) -> Self {
        Self::InviteRejected { invite_rejected }
    }
    pub fn workspace_request(workspace_request: WorkspaceRequest) -> Self {
        Self::WorkspaceRequest { workspace_request }
    }
    pub fn workspace_update(workspace_update: WorkspaceUpdate) -> Self {
        Self::WorkspaceUpdate { workspace_update }
    }

    pub fn repo_list(repo_list: RepoList) -> Self {
        Self::RepoList { repo_list }
    }

    pub fn opencode_sessions(opencode_sessions: OpenCodeSessionList) -> Self {
        Self::OpenCodeSessionList { opencode_sessions }
    }

    pub fn tool_result(tool_result: ToolResult) -> Self {
        Self::ToolResult { tool_result }
    }

    pub fn response<S: Into<String>>(response: S) -> Self {
        Self::Response {
            response: response.into(),
        }
    }

    pub fn routed_response<S: Into<String>, W: Into<String>>(response: S, workdir: W) -> Self {
        Self::RoutedResponse {
            response: response.into(),
            workdir: workdir.into(),
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
            Self::Cancel { .. } => "cancel",
            Self::Audio { .. } => "audio",
            Self::MediaBundle { .. } => "media_bundle",
            Self::AudioRetry { .. } => "audio_retry",
            Self::CallInvite { .. } => "call_invite",
            Self::CallAnswer { .. } => "call_answer",
            Self::CallHangup { .. } => "call_hangup",
            Self::GroupCallInvite { .. } => "group_call_invite",
            Self::GroupCallAnswer { .. } => "group_call_answer",
            Self::GroupCallHangup { .. } => "group_call_hangup",
            Self::TargetInvite { .. } => "target_invite",
            Self::CreateInvite { .. } => "create_invite",
            Self::InviteCreated { .. } => "invite_created",
            Self::RedeemInvite { .. } => "redeem_invite",
            Self::InviteAccepted { .. } => "invite_accepted",
            Self::InviteRejected { .. } => "invite_rejected",
            Self::WorkspaceRequest { .. } => "workspace_request",
            Self::WorkspaceUpdate { .. } => "workspace_update",
            Self::RepoList { .. } => "repo_list",
            Self::OpenCodeSessionList { .. } => "opencode_sessions",
            Self::ToolResult { .. } => "tool_result",
            Self::Transcript { .. } => "transcript",
            Self::Status { .. } => "status",
            Self::Response { .. } | Self::RoutedResponse { .. } => "response",
            Self::Error { .. } => "error",
        }
    }

    pub fn text(&self) -> &str {
        match self {
            Self::Query { query } => query,
            Self::Cancel { .. } => "cancel request",
            Self::Audio { audio } => &audio.url,
            Self::MediaBundle { media_bundle } => {
                media_bundle.query.as_deref().unwrap_or("[media bundle]")
            }
            Self::AudioRetry { audio_retry } => &audio_retry.reason,
            Self::CallInvite { call_invite }
            | Self::CallAnswer {
                call_answer: call_invite,
            }
            | Self::CallHangup {
                call_hangup: call_invite,
            } => &call_invite.call_id,
            Self::GroupCallInvite { group_call_invite }
            | Self::GroupCallAnswer {
                group_call_answer: group_call_invite,
            }
            | Self::GroupCallHangup {
                group_call_hangup: group_call_invite,
            } => &group_call_invite.call_id,
            Self::TargetInvite { target_invite } => &target_invite.name,
            Self::CreateInvite { .. } => "create invite",
            Self::InviteCreated { invite_created } => &invite_created.code,
            Self::RedeemInvite { redeem_invite } => &redeem_invite.code,
            Self::InviteAccepted { invite_accepted } => &invite_accepted.recipient_pubkey,
            Self::InviteRejected { invite_rejected } => &invite_rejected.reason,
            Self::WorkspaceRequest { workspace_request } => &workspace_request.action,
            Self::WorkspaceUpdate { workspace_update } => &workspace_update.action,
            Self::RepoList { .. } => "repo list",
            Self::OpenCodeSessionList { .. } => "OpenCode sessions",
            Self::ToolResult { tool_result } => &tool_result.tool,
            Self::Transcript { transcript } => transcript,
            Self::Status { status } => status,
            Self::Response { response } | Self::RoutedResponse { response, .. } => response,
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
            Self::Cancel { cancel_request } => json!({ "cancel_request": cancel_request }),
            Self::Audio { audio } => json!({ "audio": audio }),
            Self::MediaBundle { media_bundle } => {
                json!({ "media_bundle": media_bundle })
            }
            Self::AudioRetry { audio_retry } => json!({ "audio_retry": audio_retry }),
            Self::CallInvite { call_invite } => json!({ "call_invite": call_invite }),
            Self::CallAnswer { call_answer } => json!({ "call_answer": call_answer }),
            Self::CallHangup { call_hangup } => json!({ "call_hangup": call_hangup }),
            Self::GroupCallInvite { group_call_invite } => {
                json!({ "group_call_invite": group_call_invite })
            }
            Self::GroupCallAnswer { group_call_answer } => {
                json!({ "group_call_answer": group_call_answer })
            }
            Self::GroupCallHangup { group_call_hangup } => {
                json!({ "group_call_hangup": group_call_hangup })
            }
            Self::TargetInvite { target_invite } => json!({ "target_invite": target_invite }),
            Self::CreateInvite { create_invite } => json!({ "create_invite": create_invite }),
            Self::InviteCreated { invite_created } => json!({ "invite_created": invite_created }),
            Self::RedeemInvite { redeem_invite } => json!({ "redeem_invite": redeem_invite }),
            Self::InviteAccepted { invite_accepted } => {
                json!({ "invite_accepted": invite_accepted })
            }
            Self::InviteRejected { invite_rejected } => {
                json!({ "invite_rejected": invite_rejected })
            }
            Self::WorkspaceRequest { workspace_request } => {
                json!({ "workspace_request": workspace_request })
            }
            Self::WorkspaceUpdate { workspace_update } => {
                json!({ "workspace_update": workspace_update })
            }
            Self::RepoList { repo_list } => json!({ "repo_list": repo_list }),
            Self::OpenCodeSessionList { opencode_sessions } => {
                json!({ "opencode_sessions": opencode_sessions })
            }
            Self::ToolResult { tool_result } => json!({ "tool_result": tool_result }),
            Self::Transcript { transcript } => json!({ "transcript": transcript }),
            Self::Status { status } => json!({ "status": status }),
            Self::Response { response } => json!({ "response": response }),
            Self::RoutedResponse { response, workdir } => {
                json!({ "workdir": workdir, "response": response })
            }
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

    if object.contains_key("attachments") {
        let media_bundle: MediaBundle = serde_json::from_value(value.clone())
            .map_err(|err| anyhow!("media_bundle is invalid: {err}"))?;
        validate_media_bundle(&media_bundle)?;
        return Ok(WireMessage::media_bundle(media_bundle));
    }

    if let Some(query) = object.get("query") {
        return query
            .as_str()
            .map(WireMessage::query)
            .ok_or_else(|| anyhow!("field `query` must be a string"));
    }

    if let Some(message) = object.get("message") {
        return message
            .as_str()
            .map(WireMessage::query)
            .ok_or_else(|| anyhow!("field `message` must be a string"));
    }

    if let Some(cancel_request) = object.get("cancel_request") {
        let cancel_request = parse_cancel_request_field(cancel_request)?;
        return Ok(WireMessage::cancel(cancel_request.event_id));
    }

    if let Some(cancel_request) = object.get("cancel_task").or_else(|| object.get("cancel")) {
        let cancel_request = parse_cancel_request_field(cancel_request)?;
        return Ok(WireMessage::cancel(cancel_request.event_id));
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
    for (field, constructor) in [
        (
            "call_invite",
            WireMessage::call_invite_with_sender as fn(String, Option<String>) -> WireMessage,
        ),
        (
            "call_answer",
            WireMessage::call_answer_with_sender as fn(String, Option<String>) -> WireMessage,
        ),
        (
            "call_hangup",
            WireMessage::call_hangup_with_sender as fn(String, Option<String>) -> WireMessage,
        ),
    ] {
        if let Some(value) = object.get(field) {
            let control: CallControl = serde_json::from_value(value.clone())
                .map_err(|err| anyhow!("field `{field}` is invalid: {err}"))?;
            validate_call_id(&control.call_id)?;
            return Ok(constructor(control.call_id, control.sender_pubkey));
        }
    }
    for field in [
        "group_call_invite",
        "group_call_answer",
        "group_call_hangup",
    ] {
        if let Some(value) = object.get(field) {
            let control: GroupCallControl = serde_json::from_value(value.clone())
                .map_err(|err| anyhow!("field `{field}` is invalid: {err}"))?;
            validate_group_call_control(&control)?;
            return Ok(match field {
                "group_call_invite" => WireMessage::GroupCallInvite {
                    group_call_invite: control,
                },
                "group_call_answer" => WireMessage::GroupCallAnswer {
                    group_call_answer: control,
                },
                _ => WireMessage::GroupCallHangup {
                    group_call_hangup: control,
                },
            });
        }
    }

    if let Some(target_invite) = object.get("target_invite") {
        let target_invite: TargetInvite = serde_json::from_value(target_invite.clone())
            .map_err(|err| anyhow!("field `target_invite` is invalid: {err}"))?;
        validate_target_invite(&target_invite)?;
        return Ok(WireMessage::target_invite(target_invite));
    }
    if let Some(value) = object.get("create_invite") {
        return Ok(WireMessage::create_invite(
            serde_json::from_value(value.clone())
                .map_err(|err| anyhow!("field `create_invite` is invalid: {err}"))?,
        ));
    }
    if let Some(value) = object.get("invite_created") {
        return Ok(WireMessage::invite_created(
            serde_json::from_value(value.clone())
                .map_err(|err| anyhow!("field `invite_created` is invalid: {err}"))?,
        ));
    }
    if let Some(value) = object.get("redeem_invite") {
        let redeem_invite: RedeemInvite = serde_json::from_value(value.clone())
            .map_err(|err| anyhow!("field `redeem_invite` is invalid: {err}"))?;
        validate_redeem_invite(&redeem_invite)?;
        return Ok(WireMessage::redeem_invite(redeem_invite));
    }
    if let Some(value) = object.get("invite_accepted") {
        return Ok(WireMessage::invite_accepted(
            serde_json::from_value(value.clone())
                .map_err(|err| anyhow!("field `invite_accepted` is invalid: {err}"))?,
        ));
    }
    if let Some(value) = object.get("invite_rejected") {
        return Ok(WireMessage::invite_rejected(
            serde_json::from_value(value.clone())
                .map_err(|err| anyhow!("field `invite_rejected` is invalid: {err}"))?,
        ));
    }
    if let Some(value) = object.get("workspace_request") {
        let request: WorkspaceRequest = serde_json::from_value(value.clone())
            .map_err(|err| anyhow!("field `workspace_request` is invalid: {err}"))?;
        validate_workspace_request(&request)?;
        return Ok(WireMessage::workspace_request(request));
    }
    if let Some(value) = object.get("workspace_update") {
        let update: WorkspaceUpdate = serde_json::from_value(value.clone())
            .map_err(|err| anyhow!("field `workspace_update` is invalid: {err}"))?;
        return Ok(WireMessage::workspace_update(update));
    }

    if let Some(repo_list) = object.get("repo_list") {
        let repo_list: RepoList = serde_json::from_value(repo_list.clone())
            .map_err(|err| anyhow!("field `repo_list` is invalid: {err}"))?;
        validate_repo_list(&repo_list)?;
        return Ok(WireMessage::repo_list(repo_list));
    }

    if let Some(opencode_sessions) = object.get("opencode_sessions") {
        let opencode_sessions: OpenCodeSessionList =
            serde_json::from_value(opencode_sessions.clone())
                .map_err(|err| anyhow!("field `opencode_sessions` is invalid: {err}"))?;
        validate_opencode_session_list(&opencode_sessions)?;
        return Ok(WireMessage::opencode_sessions(opencode_sessions));
    }

    if let Some(tool_result) = object.get("tool_result") {
        let tool_result: ToolResult = serde_json::from_value(tool_result.clone())
            .map_err(|err| anyhow!("field `tool_result` is invalid: {err}"))?;
        if tool_result.tool.trim().is_empty()
            || tool_result.request_id.trim().is_empty()
            || tool_result.workdir.trim().is_empty()
        {
            return Err(anyhow!(
                "tool_result requires non-empty `tool`, `request_id`, and `workdir`"
            ));
        }
        return Ok(WireMessage::tool_result(tool_result));
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
        "message must contain a string `query`, `message`, `transcript`, `status`, `response`, `error`, object `audio`, object `audio_retry`, object `target_invite`, object `repo_list`, object `opencode_sessions`, object `tool_result`, object `media_bundle`, object `cancel_request`, or object `attachments` field"
    ))
}

fn parse_cancel_request_field(value: &Value) -> Result<CancelRequest> {
    if value.as_bool() == Some(true) {
        return Ok(CancelRequest { event_id: None });
    }

    if let Some(event_id) = value.as_str() {
        return Ok(CancelRequest {
            event_id: non_empty_string(event_id),
        });
    }

    let object = value
        .as_object()
        .ok_or_else(|| anyhow!("field `cancel_request` must be true, a string, or an object"))?;
    let event_id = object
        .get("event_id")
        .or_else(|| object.get("eventId"))
        .and_then(Value::as_str)
        .and_then(non_empty_string);
    Ok(CancelRequest { event_id })
}

fn non_empty_string(value: &str) -> Option<String> {
    let value = value.trim();
    if value.is_empty() {
        None
    } else {
        Some(value.to_string())
    }
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
    validate_reference_fields(
        "audio",
        &audio.url,
        &audio.sha256,
        audio.size,
        &audio.media_type,
        audio.encryption.as_ref(),
    )?;
    if !audio.media_type.starts_with("audio/") {
        return Err(anyhow!("field `audio.type` must be an audio MIME type"));
    }
    if let Some(encryption) = &audio.encryption {
        validate_attachment_encryption(encryption)?;
        if !encryption.plaintext_media_type.starts_with("audio/") {
            return Err(anyhow!(
                "field `audio.encryption.plaintext_type` must be an audio MIME type"
            ));
        }
    }
    Ok(())
}

fn validate_attachment_reference(reference: &AttachmentReference) -> Result<()> {
    validate_reference_fields(
        "media.reference",
        &reference.url,
        &reference.sha256,
        reference.size,
        &reference.media_type,
        reference.encryption.as_ref(),
    )
}

fn validate_media_reference(reference: &MediaReference) -> Result<()> {
    validate_attachment_reference(reference)
}

fn validate_reference_fields(
    label: &str,
    url: &str,
    sha256: &str,
    size: u64,
    media_type: &str,
    encryption: Option<&AttachmentEncryption>,
) -> Result<()> {
    if !url.starts_with("https://") {
        return Err(anyhow!("field `{label}.url` must use HTTPS"));
    }
    if sha256.len() != 64 || !sha256.chars().all(|ch| ch.is_ascii_hexdigit()) {
        return Err(anyhow!(
            "field `{label}.sha256` must be a 64-character hex SHA-256"
        ));
    }
    if size == 0 {
        return Err(anyhow!("field `{label}.size` must be greater than zero"));
    }
    if !media_type.contains('/') {
        return Err(anyhow!(
            "field `{label}.type` must be a MIME type such as `image/jpeg`"
        ));
    }
    if let Some(encryption) = encryption {
        validate_attachment_encryption(encryption)?;
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

fn validate_media_encryption(encryption: &AudioEncryption) -> Result<()> {
    if encryption.algorithm != AUDIO_ENCRYPTION_ALGORITHM {
        return Err(anyhow!(
            "field `media.encryption.algorithm` must be `{AUDIO_ENCRYPTION_ALGORITHM}`"
        ));
    }
    validate_base64url_len("media.encryption.key", &encryption.key, 32)?;
    validate_base64url_len("media.encryption.nonce", &encryption.nonce, 24)?;
    if encryption.plaintext_sha256.len() != 64
        || !encryption
            .plaintext_sha256
            .chars()
            .all(|ch| ch.is_ascii_hexdigit())
    {
        return Err(anyhow!(
            "field `media.encryption.plaintext_sha256` must be a 64-character hex SHA-256"
        ));
    }
    if encryption.plaintext_size == 0 {
        return Err(anyhow!(
            "field `media.encryption.plaintext_size` must be greater than zero"
        ));
    }
    if !encryption.plaintext_media_type.contains('/') {
        return Err(anyhow!(
            "field `media.encryption.plaintext_type` must be a MIME type such as `image/jpeg`"
        ));
    }
    Ok(())
}

fn validate_attachment_encryption(encryption: &AudioEncryption) -> Result<()> {
    validate_media_encryption(encryption)
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

fn validate_call_id(call_id: &str) -> Result<()> {
    let call_id = call_id.trim();
    if call_id.is_empty()
        || call_id.len() > 128
        || !call_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
    {
        return Err(anyhow!("call_id must be 1-128 URL-safe characters"));
    }
    Ok(())
}

fn validate_target_invite(invite: &TargetInvite) -> Result<()> {
    if invite.target_type != "nostr_codex_target" && invite.target_type != "nostr-codex-target" {
        return Err(anyhow!(
            "field `target_invite.type` must be `nostr_codex_target`"
        ));
    }
    if invite.version == 0 {
        return Err(anyhow!(
            "field `target_invite.version` must be greater than zero"
        ));
    }
    if invite.pubkey.trim().is_empty() {
        return Err(anyhow!(
            "field `target_invite.pubkey` must be a non-empty string"
        ));
    }
    if invite.relays.iter().all(|relay| relay.trim().is_empty()) {
        return Err(anyhow!(
            "field `target_invite.relays` must contain at least one relay"
        ));
    }
    Ok(())
}

fn validate_redeem_invite(invite: &RedeemInvite) -> Result<()> {
    let secret = invite.code.trim();
    if secret.len() != 43
        || !secret
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_')
    {
        return Err(anyhow!("field `redeem_invite.code` is invalid"));
    }
    Ok(())
}

fn validate_workspace_request(request: &WorkspaceRequest) -> Result<()> {
    match request.action.as_str() {
        "list" => Ok(()),
        "typing"
            if request
                .expires_in_seconds
                .is_some_and(|seconds| (1..=30).contains(&seconds))
                && (request
                    .channel_id
                    .as_deref()
                    .is_some_and(|id| !id.trim().is_empty())
                    || request
                        .recipient_pubkey
                        .as_deref()
                        .is_some_and(|id| !id.trim().is_empty())) =>
        {
            Ok(())
        }
        "set_profile" => Ok(()),
        "rename_channel"
            if request
                .channel_id
                .as_deref()
                .is_some_and(|id| !id.trim().is_empty())
                && request
                    .channel_name
                    .as_deref()
                    .is_some_and(|name| !name.trim().is_empty()) =>
        {
            Ok(())
        }
        "delete_channel"
            if request
                .channel_id
                .as_deref()
                .is_some_and(|id| !id.trim().is_empty()) =>
        {
            Ok(())
        }
        "delete_direct_conversation"
            if request
                .recipient_pubkey
                .as_deref()
                .is_some_and(|id| !id.trim().is_empty()) =>
        {
            Ok(())
        }
        "set_conversation_preprompt"
            if request
                .body
                .as_ref()
                .is_some_and(|body| body.chars().count() <= 4_000)
                && (request
                    .channel_id
                    .as_deref()
                    .is_some_and(|id| !id.trim().is_empty())
                    || request
                        .recipient_pubkey
                        .as_deref()
                        .is_some_and(|id| !id.trim().is_empty())) =>
        {
            Ok(())
        }
        "list_agents" => Ok(()),
        "add_conversation_agent" | "remove_conversation_agent"
            if request
                .agent_id
                .as_deref()
                .is_some_and(|id| !id.trim().is_empty())
                && (request
                    .channel_id
                    .as_deref()
                    .is_some_and(|id| !id.trim().is_empty())
                    || request
                        .recipient_pubkey
                        .as_deref()
                        .is_some_and(|id| !id.trim().is_empty())) =>
        {
            Ok(())
        }
        "create_agent"
            if request
                .agent_name
                .as_deref()
                .is_some_and(|value| !value.trim().is_empty())
                && request
                    .agent_role
                    .as_deref()
                    .is_some_and(|value| !value.trim().is_empty()) =>
        {
            Ok(())
        }
        "rename_agent"
            if request
                .agent_id
                .as_deref()
                .is_some_and(|value| !value.trim().is_empty())
                && request
                    .agent_name
                    .as_deref()
                    .is_some_and(|value| !value.trim().is_empty()) =>
        {
            Ok(())
        }
        "restart_agent_session"
            if request
                .agent_id
                .as_deref()
                .is_some_and(|value| !value.trim().is_empty()) =>
        {
            Ok(())
        }
        "update_agent_profile"
            if request
                .agent_id
                .as_deref()
                .is_some_and(|value| !value.trim().is_empty()) =>
        {
            Ok(())
        }
        "delete_agent"
            if request
                .agent_id
                .as_deref()
                .is_some_and(|value| !value.trim().is_empty()) =>
        {
            Ok(())
        }
        "create_channel"
            if request
                .channel_name
                .as_deref()
                .is_some_and(|name| !name.trim().is_empty()) =>
        {
            Ok(())
        }
        "list_channel_messages"
            if request
                .channel_id
                .as_deref()
                .is_some_and(|id| !id.trim().is_empty()) =>
        {
            Ok(())
        }
        "list_direct_messages"
            if request
                .recipient_pubkey
                .as_deref()
                .is_some_and(|id| !id.trim().is_empty()) =>
        {
            Ok(())
        }
        "send_channel_message"
            if request
                .channel_id
                .as_deref()
                .is_some_and(|id| !id.trim().is_empty())
                && (request
                    .body
                    .as_deref()
                    .is_some_and(|body| !body.trim().is_empty())
                    || !request.attachments.is_empty()) =>
        {
            Ok(())
        }
        "toggle_reaction"
            if request
                .parent_id
                .as_deref()
                .is_some_and(|id| !id.trim().is_empty())
                && request.reaction.as_deref().is_some_and(|emoji| {
                    !emoji.trim().is_empty() && emoji.chars().count() <= 16
                }) =>
        {
            Ok(())
        }
        "send_direct_message"
            if request
                .recipient_pubkey
                .as_deref()
                .is_some_and(|id| !id.trim().is_empty())
                && (request
                    .body
                    .as_deref()
                    .is_some_and(|body| !body.trim().is_empty())
                    || !request.attachments.is_empty()) =>
        {
            Ok(())
        }
        "transcribe_workspace_voice"
            if !request.attachments.is_empty()
                && (request
                    .channel_id
                    .as_deref()
                    .is_some_and(|id| !id.trim().is_empty())
                    || request
                        .recipient_pubkey
                        .as_deref()
                        .is_some_and(|id| !id.trim().is_empty())) =>
        {
            Ok(())
        }
        "call_invite" | "call_answer" | "call_hangup"
            if request
                .recipient_pubkey
                .as_deref()
                .is_some_and(|id| !id.trim().is_empty())
                && request
                    .call_id
                    .as_deref()
                    .is_some_and(|id| validate_call_id(id).is_ok()) =>
        {
            Ok(())
        }
        "group_call_invite" | "group_call_answer" | "group_call_hangup"
            if request
                .channel_id
                .as_deref()
                .is_some_and(|id| !id.trim().is_empty())
                && request
                    .call_id
                    .as_deref()
                    .is_some_and(|id| validate_call_id(id).is_ok())
                && validate_group_call_participants(&request.participant_pubkeys).is_ok() =>
        {
            Ok(())
        }
        _ => Err(anyhow!(
            "workspace request is incomplete or has an unsupported action"
        )),
    }?;
    for attachment in &request.attachments {
        validate_media_reference(attachment)?;
    }
    if request.mentions.len() > 32
        || request.mentions.iter().any(|mention| {
            !matches!(mention.kind.as_str(), "member" | "agent")
                || mention.id.trim().is_empty()
                || mention.id.len() > 256
                || mention.label.trim().is_empty()
                || mention.label.len() > 100
        })
    {
        return Err(anyhow!("workspace mentions are invalid"));
    }
    Ok(())
}

fn validate_group_call_control(control: &GroupCallControl) -> Result<()> {
    validate_call_id(&control.call_id)?;
    if control.channel_id.trim().is_empty() {
        return Err(anyhow!("group call channel id must be non-empty"));
    }
    validate_group_call_participants(&control.participant_pubkeys)
}

fn validate_group_call_participants(participants: &[String]) -> Result<()> {
    if !(2..=4).contains(&participants.len())
        || participants
            .iter()
            .any(|participant| participant.trim().is_empty())
    {
        return Err(anyhow!("group calls require two to four participants"));
    }
    let unique = participants
        .iter()
        .collect::<std::collections::HashSet<_>>();
    if unique.len() != participants.len() {
        return Err(anyhow!("group call participants must be unique"));
    }
    Ok(())
}

fn validate_repo_list(repo_list: &RepoList) -> Result<()> {
    for root in &repo_list.roots {
        if root.root.trim().is_empty() {
            return Err(anyhow!("field `repo_list.roots[].root` must be non-empty"));
        }
        for repo in &root.repos {
            if repo.name.trim().is_empty() {
                return Err(anyhow!(
                    "field `repo_list.roots[].repos[].name` must be non-empty"
                ));
            }
            if repo.path.trim().is_empty() {
                return Err(anyhow!(
                    "field `repo_list.roots[].repos[].path` must be non-empty"
                ));
            }
            if repo.relative_path.trim().is_empty() {
                return Err(anyhow!(
                    "field `repo_list.roots[].repos[].relative_path` must be non-empty"
                ));
            }
        }
    }
    Ok(())
}

fn validate_opencode_session_list(session_list: &OpenCodeSessionList) -> Result<()> {
    for session in &session_list.sessions {
        if session.id.trim().is_empty() {
            return Err(anyhow!(
                "field `opencode_sessions.sessions[].id` must be non-empty"
            ));
        }
        if session.title.trim().is_empty() {
            return Err(anyhow!(
                "field `opencode_sessions.sessions[].title` must be non-empty"
            ));
        }
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
    fn parses_routed_message_contract() {
        let parsed = parse_wire_message(
            r#"{ "session_id": "session-1", "workdir": "/home/tom/code/phone", "message": "hello" }"#,
        )
        .unwrap();
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
    fn parses_media_bundle_payload_from_attachments_root() {
        let parsed = parse_wire_message(
            r#"{
                "query": "analyze file",
                "attachments": [
                    {
                        "url": "https://cdn.example.com/doc.pdf",
                        "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                        "size": 1234,
                        "type": "application/pdf",
                        "name": "doc.pdf"
                    }
                ]
            }"#,
        )
        .unwrap();
        assert_eq!(parsed.kind(), "media_bundle");
        assert_eq!(
            parsed
                .media_bundle_ref()
                .and_then(|bundle| bundle.query.clone()),
            Some("analyze file".to_string())
        );
    }

    #[test]
    fn parses_non_audio_attachment_in_media_bundle() {
        let parsed = parse_wire_message(
            r#"{
                "media_bundle": {
                    "query": "read this pdf",
                    "attachments": [
                        {
                            "url": "https://cdn.example.com/doc.pdf",
                            "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                            "size": 1234,
                            "type": "application/pdf",
                            "name": "doc.pdf",
                            "encryption": {
                                "algorithm": "xchacha20poly1305",
                                "key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                                "nonce": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                                "plaintext_sha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
                                "plaintext_size": 2048,
                                "plaintext_type": "application/pdf"
                            }
                        }
                    ]
                }
            }"#,
        )
        .unwrap();
        assert_eq!(parsed.kind(), "media_bundle");
    }

    #[test]
    fn serializes_response_contract() {
        assert_eq!(
            WireMessage::response("done").to_json().unwrap(),
            r#"{"response":"done"}"#
        );
    }

    #[test]
    fn serializes_routed_response_contract() {
        assert_eq!(
            WireMessage::routed_response("done", "/home/tom/code/phone")
                .to_json()
                .unwrap(),
            r#"{"response":"done","workdir":"/home/tom/code/phone"}"#
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
    fn parses_cancel_request_contract() {
        let parsed =
            parse_wire_message(r#"{ "cancel_request": { "event_id": "abc123" } }"#).unwrap();
        assert_eq!(parsed, WireMessage::cancel(Some("abc123".to_string())));
        assert_eq!(parsed.kind(), "cancel");
        assert_eq!(parsed.text(), "cancel request");
    }

    #[test]
    fn parses_cancel_request_bool_contract() {
        let parsed = parse_wire_message(r#"{ "cancel_request": true }"#).unwrap();
        assert_eq!(parsed, WireMessage::cancel(None));
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

        let parsed = parse_wire_message(
            r#"{ "transcript": "turn on the lights", "source_event_id": "voice-event", "workdir": "/home/tom/code/phone" }"#,
        )
        .unwrap();
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
    fn parses_target_invite_contract() {
        let parsed = parse_wire_message(
            r#"{
                "target_invite": {
                    "type": "nostr_codex_target",
                    "version": 1,
                    "name": "repo",
                    "pubkey": "npub123",
                    "pubkey_hex": "abc123",
                    "workdir": "/home/tom/code/repo",
                    "relays": ["wss://relay.damus.io", "wss://nos.lol"]
                }
            }"#,
        )
        .unwrap();

        assert_eq!(parsed.kind(), "target_invite");
        assert_eq!(parsed.text(), "repo");
        assert_eq!(
            parsed.to_json().unwrap(),
            r#"{"target_invite":{"name":"repo","pubkey":"npub123","pubkey_hex":"abc123","relays":["wss://relay.damus.io","wss://nos.lol"],"type":"nostr_codex_target","version":1,"workdir":"/home/tom/code/repo"}}"#
        );
    }

    #[test]
    fn parses_invite_protocol_contracts() {
        let created = parse_wire_message(
            r#"{ "invite_created": { "code": "A1B2C3D4E5", "expires_at": 42 } }"#,
        )
        .unwrap();
        assert_eq!(created.kind(), "invite_created");
        assert_eq!(created.text(), "A1B2C3D4E5");
        let redeem = parse_wire_message(
            r#"{ "redeem_invite": { "code": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }"#,
        )
        .unwrap();
        assert_eq!(redeem.kind(), "redeem_invite");
    }

    #[test]
    fn parses_workspace_request_contract() {
        let parsed = parse_wire_message(r#"{"workspace_request":{"action":"send_channel_message","channel_id":"c1","body":"hello","parent_id":"p1"}}"#).unwrap();
        assert_eq!(parsed.kind(), "workspace_request");
        assert!(parsed.to_json().unwrap().contains("parent_id"));
        assert!(parse_wire_message(
            r#"{"workspace_request":{"action":"send_direct_message","body":"missing recipient"}}"#
        )
        .is_err());
    }

    #[test]
    fn parses_direct_call_control_workspace_requests() {
        let parsed = parse_wire_message(
            r#"{"workspace_request":{"action":"call_invite","recipient_pubkey":"peer","call_id":"call_123"}}"#,
        )
        .unwrap();
        let WireMessage::WorkspaceRequest { workspace_request } = parsed else {
            panic!("expected workspace request");
        };
        assert_eq!(workspace_request.call_id.as_deref(), Some("call_123"));

        assert!(parse_wire_message(
            r#"{"workspace_request":{"action":"call_answer","recipient_pubkey":"peer","call_id":"invalid call"}}"#
        )
        .is_err());
    }

    #[test]
    fn preserves_original_sender_in_worker_forwarded_call_controls() {
        let forwarded = WireMessage::call_invite_from("call_123", "caller-pubkey");

        assert_eq!(
            forwarded.to_json().unwrap(),
            r#"{"call_invite":{"call_id":"call_123","sender_pubkey":"caller-pubkey"}}"#
        );
        let parsed = parse_wire_message(&forwarded.to_json().unwrap()).unwrap();
        let WireMessage::CallInvite { call_invite } = parsed else {
            panic!("expected call invite");
        };
        assert_eq!(call_invite.sender_pubkey.as_deref(), Some("caller-pubkey"));
    }

    #[test]
    fn parses_capped_channel_group_call_controls() {
        let parsed = parse_wire_message(
            r#"{"workspace_request":{"action":"group_call_invite","channel_id":"channel-1","call_id":"call_123","participant_pubkeys":["caller","peer"]}}"#,
        )
        .unwrap();
        let WireMessage::WorkspaceRequest { workspace_request } = parsed else {
            panic!("expected workspace request");
        };
        assert_eq!(workspace_request.participant_pubkeys, ["caller", "peer"]);

        assert!(parse_wire_message(
            r#"{"workspace_request":{"action":"group_call_invite","channel_id":"channel-1","call_id":"call_123","participant_pubkeys":["a","b","c","d","e"]}}"#,
        )
        .is_err());

        let forwarded = WireMessage::group_call_invite_from(
            "call_123",
            "channel-1",
            vec!["caller".to_string(), "peer".to_string()],
            "caller",
        );
        assert_eq!(forwarded.kind(), "group_call_invite");
        assert!(forwarded.to_json().unwrap().contains("channel-1"));
    }

    #[test]
    fn parses_reaction_and_main_thread_workspace_requests() {
        let reaction = parse_wire_message(r#"{"workspace_request":{"action":"toggle_reaction","parent_id":"message-1","reaction":"👍"}}"#).unwrap();
        assert_eq!(reaction.kind(), "workspace_request");
        let reply = parse_wire_message(r#"{"workspace_request":{"action":"send_channel_message","channel_id":"c1","body":"reply","parent_id":"message-1","also_send_to_main":true}}"#).unwrap();
        assert!(reply.to_json().unwrap().contains("also_send_to_main"));
    }

    #[test]
    fn validates_short_lived_workspace_typing_requests() {
        assert!(parse_wire_message(
            r#"{"workspace_request":{"action":"typing","channel_id":"c1","expires_in_seconds":6}}"#
        )
        .is_ok());
        assert!(parse_wire_message(
            r#"{"workspace_request":{"action":"typing","channel_id":"c1","expires_in_seconds":31}}"#
        )
        .is_err());
    }

    #[test]
    fn parses_agent_workspace_typing_identity_and_direct_scope() {
        let parsed = parse_wire_message(
            r#"{"workspace_update":{"action":"typing","typing":{"sender_pubkey":"agent:rev","agent_id":"rev","agent_name":"Rev","stage":"Inspecting code.","member_pubkey":"alice","peer_pubkey":"bob","expires_at":200}}}"#,
        )
        .unwrap();
        let WireMessage::WorkspaceUpdate { workspace_update } = parsed else {
            panic!("expected workspace update");
        };
        let typing = workspace_update.typing.unwrap();
        assert_eq!(typing.agent_id.as_deref(), Some("rev"));
        assert_eq!(typing.agent_name.as_deref(), Some("Rev"));
        assert_eq!(typing.stage.as_deref(), Some("Inspecting code."));
        assert_eq!(typing.member_pubkey.as_deref(), Some("alice"));
        assert_eq!(typing.peer_pubkey.as_deref(), Some("bob"));
    }

    #[test]
    fn parses_attachment_only_workspace_message() {
        let parsed = parse_wire_message(
            r#"{"workspace_request":{"action":"send_channel_message","channel_id":"c1","attachments":[{"url":"https://cdn.example/report","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":4,"type":"application/pdf","name":"report.pdf"}]}}"#,
        )
        .unwrap();
        let WireMessage::WorkspaceRequest { workspace_request } = parsed else {
            panic!("expected workspace request");
        };
        assert_eq!(workspace_request.attachments.len(), 1);
        assert_eq!(
            workspace_request.attachments[0].name.as_deref(),
            Some("report.pdf")
        );
    }

    #[test]
    fn parses_workspace_mentions_and_agent_management_requests() {
        let parsed = parse_wire_message(
            r#"{"workspace_request":{"action":"send_channel_message","channel_id":"c1","body":"@[Scout](agent:a1)","mentions":[{"kind":"agent","id":"a1","label":"Scout"}]}}"#,
        )
        .unwrap();
        let WireMessage::WorkspaceRequest { workspace_request } = parsed else {
            panic!("expected workspace request");
        };
        assert_eq!(workspace_request.mentions[0].id, "a1");
        assert!(parse_wire_message(
            r#"{"workspace_request":{"action":"rename_agent","agent_id":"a1","agent_name":"Navigator"}}"#
        )
        .is_ok());
        assert!(parse_wire_message(
            r#"{"workspace_request":{"action":"delete_agent","agent_id":"a1"}}"#
        )
        .is_ok());
    }

    #[test]
    fn parses_channel_created_workspace_update() {
        let parsed = parse_wire_message(
            r#"{"workspace_update":{"action":"channel_created","channels":[{"id":"channel-1","name":"engineering","created_by":"owner","created_at":42}]}}"#,
        )
        .unwrap();

        assert_eq!(parsed.kind(), "workspace_update");
        assert_eq!(parsed.text(), "channel_created");
    }

    #[test]
    fn parses_workspace_profile_update() {
        let parsed = parse_wire_message(
            r#"{"workspace_update":{"action":"profile_updated","members":[{"pubkey":"member","display_name":"Ada"}]}}"#,
        )
        .unwrap();

        assert_eq!(parsed.kind(), "workspace_update");
        assert_eq!(parsed.text(), "profile_updated");
    }

    #[test]
    fn parses_legacy_workspace_member_pubkeys() {
        let parsed = parse_wire_message(
            r#"{"workspace_update":{"action":"snapshot","members":["2fb895af9d059dba6e3ee29506f75ba4c03d7438835f2255924e94311d445b8e"]}}"#,
        )
        .unwrap();

        let WireMessage::WorkspaceUpdate { workspace_update } = parsed else {
            panic!("expected workspace update");
        };
        assert_eq!(
            workspace_update.members[0].pubkey,
            "2fb895af9d059dba6e3ee29506f75ba4c03d7438835f2255924e94311d445b8e"
        );
        assert!(workspace_update.members[0].display_name.is_empty());
    }

    #[test]
    fn parses_workspace_profile_request() {
        let parsed = parse_wire_message(
            r#"{"workspace_request":{"action":"set_profile","display_name":"Ada"}}"#,
        )
        .unwrap();

        assert_eq!(parsed.kind(), "workspace_request");
    }

    #[test]
    fn parses_agent_workspace_request_and_update() {
        let parsed = parse_wire_message(r#"{"workspace_request":{"action":"create_agent","agent_name":"Scout","agent_role":"Researcher","agent_skills":["Research"],"opencode_session_id":"ses_1"}}"#).unwrap();
        assert_eq!(parsed.kind(), "workspace_request");
        let update = parse_wire_message(r#"{"workspace_update":{"action":"agent_created","agents":[{"id":"agent-1","name":"Scout","role":"Researcher","traits":"Careful","skills":["Research"],"opencode_session_id":"ses_1","created_by":"owner","created_at":42,"initialized_at":43,"input_tokens":12,"output_tokens":3}]}}"#).unwrap();
        assert_eq!(update.kind(), "workspace_update");
    }

    #[test]
    fn parses_conversation_agent_membership_requests_and_updates() {
        let request = parse_wire_message(r#"{"workspace_request":{"action":"add_conversation_agent","channel_id":"channel-1","agent_id":"agent-1","folder_scope":["/work/apps"]}}"#).unwrap();
        let WireMessage::WorkspaceRequest { workspace_request } = request else {
            panic!("expected workspace request");
        };
        assert_eq!(workspace_request.folder_scope, ["/work/apps"]);
        let update = parse_wire_message(r#"{"workspace_update":{"action":"conversation_agents_updated","conversation_agents":[{"agent_id":"agent-1","channel_id":"channel-1","folder_scope":["/work/apps"]}]}}"#).unwrap();
        let WireMessage::WorkspaceUpdate { workspace_update } = update else {
            panic!("expected workspace update");
        };
        assert_eq!(
            workspace_update.conversation_agents[0].folder_scope,
            ["/work/apps"]
        );
    }

    #[test]
    fn parses_and_bounds_conversation_preprompt_requests() {
        let request = parse_wire_message(r#"{"workspace_request":{"action":"set_conversation_preprompt","channel_id":"channel-1","body":"Review carefully."}}"#).unwrap();
        assert_eq!(request.kind(), "workspace_request");

        let too_long = serde_json::json!({
            "workspace_request": {
                "action": "set_conversation_preprompt",
                "channel_id": "channel-1",
                "body": "x".repeat(4_001),
            }
        });
        assert!(parse_wire_message(&too_long.to_string()).is_err());
    }

    #[test]
    fn parses_repo_list_contract() {
        let parsed = parse_wire_message(
            r#"{
                "repo_list": {
                    "roots": [
                        {
                            "root": "/home/tom/code",
                            "repos": [
                                {
                                    "name": "phone",
                                    "path": "/home/tom/code/phone",
                                    "relative_path": "phone",
                                    "is_git_repo": true
                                }
                            ]
                        }
                    ]
                }
            }"#,
        )
        .unwrap();

        assert_eq!(parsed.kind(), "repo_list");
        assert_eq!(parsed.text(), "repo list");
        assert_eq!(
            parsed.to_json().unwrap(),
            r#"{"repo_list":{"roots":[{"repos":[{"is_git_repo":true,"name":"phone","path":"/home/tom/code/phone","relative_path":"phone"}],"root":"/home/tom/code"}]}}"#
        );
    }

    #[test]
    fn parses_opencode_session_list_contract() {
        let parsed = parse_wire_message(
            r#"{
                "opencode_sessions": {
                    "workdir": "/home/tom/code/phone",
                    "sessions": [
                        {
                            "id": "ses_123",
                            "title": "Fix APK release",
                            "directory": "/home/tom/code/phone",
                            "updated_at": "2026-07-09T12:00:00Z"
                        }
                    ]
                }
            }"#,
        )
        .unwrap();

        assert_eq!(parsed.kind(), "opencode_sessions");
        assert_eq!(parsed.text(), "OpenCode sessions");
        assert_eq!(
            parsed.to_json().unwrap(),
            r#"{"opencode_sessions":{"sessions":[{"directory":"/home/tom/code/phone","id":"ses_123","title":"Fix APK release","updated_at":"2026-07-09T12:00:00Z"}],"workdir":"/home/tom/code/phone"}}"#
        );
    }

    #[test]
    fn parses_tool_result_contract() {
        let parsed = parse_wire_message(
            r#"{
                "tool_result": {
                    "tool": "git_status",
                    "request_id": "request-1",
                    "workdir": "/repo",
                    "data": { "branch": "main", "files": [] }
                }
            }"#,
        )
        .unwrap();

        assert_eq!(parsed.kind(), "tool_result");
        assert_eq!(parsed.text(), "git_status");
        assert!(parsed.to_json().unwrap().contains("request-1"));
    }

    #[test]
    fn rejects_malformed_payloads() {
        assert!(parse_wire_message(r#"{ "query": 42 }"#).is_err());
        assert!(parse_wire_message(r#"{ "message": 42 }"#).is_err());
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
        assert!(parse_wire_message(r#"{ "target_invite": { "type": "nostr_codex_target", "version": 1, "name": "repo", "pubkey": "npub123", "relays": [] } }"#).is_err());
        assert!(parse_wire_message(
            r#"{ "repo_list": { "roots": [ { "root": "", "repos": [] } ] } }"#
        )
        .is_err());
        assert!(parse_wire_message(
            r#"{ "opencode_sessions": { "sessions": [ { "id": "", "title": "bad" } ] } }"#
        )
        .is_err());
        assert!(parse_wire_message("hello").is_err());
    }
}
