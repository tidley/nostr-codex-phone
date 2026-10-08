use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

use anyhow::{anyhow, Result};
use futures_util::future::LocalBoxFuture;
use herdr::{
    AgentSession, LogicalTarget, RuntimeConfig, RuntimeError, RuntimeHandle, RuntimeSubscription,
    TargetExecutionConfig, TurnId, TurnResult,
};

use crate::workspace::WorkspaceStore;

#[derive(Clone, Debug)]
pub struct EmbeddedAgentSession {
    agent: AgentSession,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EmbeddedTurnResult {
    pub turn_id: String,
    pub status: EmbeddedTurnStatus,
    pub text: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum EmbeddedTurnStatus {
    Completed,
    Interrupted,
    Failed(String),
    Unavailable,
    TimedOut,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EmbeddedTargetStatus {
    Ready,
    Unavailable,
}

/// Worker-local runtime seam. Its futures deliberately do not require `Send`.
pub trait EmbeddedRuntime {
    fn open_conversation<'a>(
        &'a self,
        conversation_id: &'a str,
        execution: TargetExecutionConfig,
    ) -> LocalBoxFuture<'a, Result<EmbeddedTargetStatus>>;
    fn open_thread<'a>(
        &'a self,
        conversation_id: &'a str,
        thread_id: &'a str,
        execution: TargetExecutionConfig,
    ) -> LocalBoxFuture<'a, Result<EmbeddedTargetStatus>>;
    fn submit_turn<'a>(
        &'a self,
        conversation_id: &'a str,
        thread_id: Option<&'a str>,
        execution: TargetExecutionConfig,
        turn_id: &'a str,
        text: &'a str,
        timeout: Duration,
    ) -> LocalBoxFuture<'a, Result<EmbeddedTurnResult>>;
    fn interrupt_turn<'a>(
        &'a self,
        conversation_id: &'a str,
        thread_id: Option<&'a str>,
        turn_id: &'a str,
    ) -> LocalBoxFuture<'a, Result<EmbeddedTurnResult>>;
    fn subscribe<'a>(&'a self) -> LocalBoxFuture<'a, Result<RuntimeSubscription>>;
    fn shutdown<'a>(&'a self) -> LocalBoxFuture<'a, Result<()>>;
    fn close_thread<'a>(
        &'a self,
        conversation_id: &'a str,
        thread_id: &'a str,
    ) -> LocalBoxFuture<'a, Result<()>>;
    fn invalidate_target(&self, target: &LogicalTarget) -> Result<()>;
    fn invalidate_all_targets(&self) -> Result<()>;
}


pub struct EmbeddedHerdrRuntime {
    runtime: RuntimeHandle,
    sessions: Mutex<HashMap<LogicalTarget, EmbeddedAgentSession>>,
}

impl EmbeddedRuntime for EmbeddedHerdrRuntime {
    fn open_conversation<'a>(
        &'a self,
        conversation_id: &'a str,
        execution: TargetExecutionConfig,
    ) -> LocalBoxFuture<'a, Result<EmbeddedTargetStatus>> {
        Box::pin(async move { self.open_conversation_status(conversation_id, execution).await })
    }

    fn open_thread<'a>(
        &'a self,
        conversation_id: &'a str,
        thread_id: &'a str,
        execution: TargetExecutionConfig,
    ) -> LocalBoxFuture<'a, Result<EmbeddedTargetStatus>> {
        Box::pin(async move { self.open_thread_status(conversation_id, thread_id, execution).await })
    }

    fn submit_turn<'a>(
        &'a self,
        conversation_id: &'a str,
        thread_id: Option<&'a str>,
        execution: TargetExecutionConfig,
        turn_id: &'a str,
        text: &'a str,
        timeout: Duration,
    ) -> LocalBoxFuture<'a, Result<EmbeddedTurnResult>> {
        Box::pin(async move {
            let session = match thread_id {
                Some(thread_id) => EmbeddedHerdrRuntime::open_thread(self, conversation_id, thread_id, execution).await?,
                None => EmbeddedHerdrRuntime::open_conversation(self, conversation_id, execution).await?,
            };
            EmbeddedHerdrRuntime::submit_turn(self, &session, turn_id, text, timeout).await
        })
    }

    fn interrupt_turn<'a>(
        &'a self,
        conversation_id: &'a str,
        thread_id: Option<&'a str>,
        turn_id: &'a str,
    ) -> LocalBoxFuture<'a, Result<EmbeddedTurnResult>> {
        Box::pin(async move {
            let target = match thread_id {
                Some(thread_id) => LogicalTarget::thread(conversation_id, thread_id)?,
                None => LogicalTarget::conversation(conversation_id)?,
            };
            let session = self.sessions
                .lock()
                .map_err(|_| anyhow!("embedded Herdr session registry is unavailable"))?
                .get(&target)
                .cloned()
                .ok_or(RuntimeError::Unavailable)?;
            EmbeddedHerdrRuntime::interrupt_turn(self, &session, turn_id).await
        })
    }

    fn subscribe<'a>(&'a self) -> LocalBoxFuture<'a, Result<RuntimeSubscription>> {
        Box::pin(async move { EmbeddedHerdrRuntime::subscribe(self).await })
    }

    fn shutdown<'a>(&'a self) -> LocalBoxFuture<'a, Result<()>> {
        Box::pin(async move { EmbeddedHerdrRuntime::shutdown(self).await })
    }

    fn close_thread<'a>(
        &'a self,
        conversation_id: &'a str,
        thread_id: &'a str,
    ) -> LocalBoxFuture<'a, Result<()>> {
        Box::pin(async move { EmbeddedHerdrRuntime::close_thread(self, conversation_id, thread_id).await })
    }

    fn invalidate_target(&self, target: &LogicalTarget) -> Result<()> {
        EmbeddedHerdrRuntime::invalidate_target(self, target)
    }

    fn invalidate_all_targets(&self) -> Result<()> {
        EmbeddedHerdrRuntime::invalidate_all_targets(self)
    }
}

impl EmbeddedHerdrRuntime {
    pub async fn start(config: RuntimeConfig) -> Result<Self> {
        Ok(Self::new(RuntimeHandle::start(config).await?))
    }

    pub fn new(runtime: RuntimeHandle) -> Self {
        Self {
            runtime,
            sessions: Mutex::new(HashMap::new()),
        }
    }

    pub async fn open_conversation(&self, conversation_id: &str, execution: TargetExecutionConfig) -> Result<EmbeddedAgentSession> {
        self.open(LogicalTarget::conversation(conversation_id)?, execution)
            .await
    }

    async fn open_conversation_status(
        &self,
        conversation_id: &str,
        execution: TargetExecutionConfig,
    ) -> Result<EmbeddedTargetStatus> {
        self.open_status(LogicalTarget::conversation(conversation_id)?, execution).await
    }

    pub async fn open_thread(
        &self,
        conversation_id: &str,
        thread_id: &str,
        execution: TargetExecutionConfig,
    ) -> Result<EmbeddedAgentSession> {
        self.open(LogicalTarget::thread(conversation_id, thread_id)?, execution)
            .await
    }

    async fn open_thread_status(
        &self,
        conversation_id: &str,
        thread_id: &str,
        execution: TargetExecutionConfig,
    ) -> Result<EmbeddedTargetStatus> {
        self.open_status(LogicalTarget::thread(conversation_id, thread_id)?, execution).await
    }

    pub async fn submit_turn(
        &self,
        session: &EmbeddedAgentSession,
        turn_id: &str,
        text: &str,
        timeout: Duration,
    ) -> Result<EmbeddedTurnResult> {
        let worker_turn_id = turn_id.to_string();
        let turn_id = TurnId::new(turn_id)?;
        let result = self
            .runtime
            .submit_turn(&session.agent, turn_id, text, timeout)
            .await?;
        Ok(worker_turn_result(worker_turn_id, result))
    }

    pub async fn interrupt_turn(
        &self,
        session: &EmbeddedAgentSession,
        turn_id: &str,
    ) -> Result<EmbeddedTurnResult> {
        let worker_turn_id = turn_id.to_string();
        let turn_id = TurnId::new(turn_id)?;
        let result = self
            .runtime
            .interrupt_turn(&session.agent, &turn_id)
            .await?;
        Ok(worker_turn_result(worker_turn_id, result))
    }

    pub async fn subscribe(&self) -> Result<RuntimeSubscription> {
        Ok(self.runtime.subscribe().await?)
    }

    pub async fn shutdown(&self) -> Result<()> {
        self.runtime.shutdown().await?;
        self.sessions
            .lock()
            .map_err(|_| anyhow!("embedded Herdr session registry is unavailable"))?
            .clear();
        Ok(())
    }

    pub async fn close_conversation(&self, conversation_id: &str) -> Result<()> {
        self.close(LogicalTarget::conversation(conversation_id)?).await
    }

    pub async fn close_thread(&self, conversation_id: &str, thread_id: &str) -> Result<()> {
        self.close(LogicalTarget::thread(conversation_id, thread_id)?).await
    }

    pub fn invalidate_target(&self, target: &LogicalTarget) -> Result<()> {
        self.sessions
            .lock()
            .map_err(|_| anyhow!("embedded Herdr session registry is unavailable"))?
            .remove(target);
        Ok(())
    }

    pub fn invalidate_all_targets(&self) -> Result<()> {
        self.sessions
            .lock()
            .map_err(|_| anyhow!("embedded Herdr session registry is unavailable"))?
            .clear();
        Ok(())
    }

    async fn close(&self, target: LogicalTarget) -> Result<()> {
        self.runtime.close_target(&target).await?;
        self.invalidate_target(&target)
    }

    async fn open(&self, target: LogicalTarget, execution: TargetExecutionConfig) -> Result<EmbeddedAgentSession> {
        // Always delegate opening to RuntimeHandle: it reuses an identical launch
        // snapshot and replaces the target when the configuration changed.
        let session = EmbeddedAgentSession {
            agent: self.runtime.open_agent(target.clone(), execution).await?,
        };
        self.sessions
            .lock()
            .map_err(|_| anyhow!("embedded Herdr session registry is unavailable"))?
            .insert(target, session.clone());
        Ok(session)
    }

    async fn open_status(&self, target: LogicalTarget, execution: TargetExecutionConfig) -> Result<EmbeddedTargetStatus> {
        match self.open(target, execution).await {
            Ok(_) => Ok(EmbeddedTargetStatus::Ready),
            Err(error) if matches!(error.downcast_ref::<RuntimeError>(), Some(RuntimeError::Unavailable | RuntimeError::Closed)) => {
                Ok(EmbeddedTargetStatus::Unavailable)
            }
            Err(error) => Err(error),
        }
    }
}

pub fn embedded_target(
    workspace: &WorkspaceStore,
    conversation_id: &str,
    thread_id: Option<&str>,
) -> Result<Option<LogicalTarget>> {
    match thread_id {
        Some(thread_id) => Ok(workspace
            .embedded_thread_binding(conversation_id, thread_id)?
            .filter(|binding| binding.ready && binding.closed_at.is_none())
            .map(|_| LogicalTarget::thread(conversation_id, thread_id))
            .transpose()?),
        None => Ok(workspace
            .embedded_conversation_binding(conversation_id)?
            .filter(|binding| binding.ready && binding.closed_at.is_none())
            .map(|_| LogicalTarget::conversation(conversation_id))
            .transpose()?),
    }
}

fn worker_turn_result(turn_id: String, result: TurnResult) -> EmbeddedTurnResult {
    let (status, text) = match result {
        TurnResult::Completed { text, .. } => (EmbeddedTurnStatus::Completed, Some(text)),
        TurnResult::Interrupted { .. } => (EmbeddedTurnStatus::Interrupted, None),
        TurnResult::Failed { message, .. } => (EmbeddedTurnStatus::Failed(message), None),
        TurnResult::Unavailable { .. } => (EmbeddedTurnStatus::Unavailable, None),
        TurnResult::TimedOut { .. } => (EmbeddedTurnStatus::TimedOut, None),
    };
    EmbeddedTurnResult { turn_id, status, text }
}

#[cfg(test)]
mod tests {
    use herdr::{TurnId, TurnResult};

    use super::worker_turn_result;

    #[test]
    fn completed_turn_retains_typed_completion_text() {
        let result = worker_turn_result(
            "delivery-1".to_string(),
            TurnResult::Completed {
                turn_id: TurnId::new("delivery-1").unwrap(),
                text: "typed completion".to_string(),
            },
        );

        assert_eq!(result.text.as_deref(), Some("typed completion"));
    }

}
