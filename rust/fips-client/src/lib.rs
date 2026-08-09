use anyhow::Result;
use fips_mobile::{
    Config, FipsMobileClient, FipsMobileConfig, FipsMobileQuicSession, FipsMobileQuicSessionConfig,
    Identity,
};

/// Connection settings shared by mobile, desktop, and server-side FIPS clients.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FipsClientConfig {
    pub secret_key: String,
    pub relays: Vec<String>,
    pub stun_servers: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FipsCallStatus {
    pub state: String,
    pub max_datagram_bytes: Option<u32>,
}

impl FipsClientConfig {
    pub fn quic_session(&self) -> Result<FipsMobileQuicSession> {
        let identity = Identity::from_secret_str(self.secret_key.trim())?;
        let mut config = FipsMobileQuicSessionConfig::default();
        let relays = clean_endpoints(&self.relays);
        if !relays.is_empty() {
            config.discovery.advert_relays = relays.clone();
            config.discovery.dm_relays = relays;
        }
        let stun_servers = clean_endpoints(&self.stun_servers);
        if !stun_servers.is_empty() {
            config.discovery.stun_servers = stun_servers;
        }
        Ok(FipsMobileQuicSession::new(identity, config))
    }

    /// Starts an ephemeral application-frame transport without a TUN, DNS, or
    /// control service. Each client supplies its local response port and queue.
    pub async fn application_client(
        &self,
        response_port: u16,
        queue_depth: usize,
    ) -> Result<FipsMobileClient> {
        let mut config = Config::default();
        config.node.identity.nsec = Some(self.secret_key.trim().to_string());
        config.node.identity.persistent = false;
        config.tun.enabled = false;
        config.dns.enabled = false;
        config.node.control.enabled = false;
        config.node.discovery.nostr.enabled = true;
        config.node.discovery.nostr.advertise = true;
        config.node.discovery.nostr.share_local_candidates = true;
        let relays = clean_endpoints(&self.relays);
        if !relays.is_empty() {
            config.node.discovery.nostr.advert_relays = relays.clone();
            config.node.discovery.nostr.dm_relays = relays;
        }
        let stun_servers = clean_endpoints(&self.stun_servers);
        if !stun_servers.is_empty() {
            config.node.discovery.nostr.stun_servers = stun_servers;
        }
        Ok(FipsMobileClient::start(FipsMobileConfig {
            config,
            response_port,
            queue_depth,
        })
        .await?)
    }
}

pub fn call_status(session: &FipsMobileQuicSession) -> FipsCallStatus {
    FipsCallStatus {
        state: format!("{:?}", session.status()).to_lowercase(),
        max_datagram_bytes: session
            .max_datagram_size()
            .ok()
            .and_then(|size| u32::try_from(size).ok()),
    }
}

pub fn clean_endpoints(endpoints: &[String]) -> Vec<String> {
    endpoints
        .iter()
        .map(|endpoint| endpoint.trim().to_string())
        .filter(|endpoint| !endpoint.is_empty())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn removes_blank_endpoints_without_reordering_the_rest() {
        assert_eq!(
            clean_endpoints(&[
                " wss://relay.example ".to_string(),
                " ".to_string(),
                "stun:stun.example:3478".to_string(),
            ]),
            vec!["wss://relay.example", "stun:stun.example:3478"],
        );
    }
}
