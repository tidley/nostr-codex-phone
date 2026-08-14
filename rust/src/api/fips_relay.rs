use std::net::{IpAddr, SocketAddr};
use std::time::{SystemTime, UNIX_EPOCH};

use ::rand::{rngs::OsRng, RngCore};
use anyhow::{anyhow, bail, Context, Result};
use nostr_sdk::prelude::*;
use serde::{Deserialize, Serialize};

const RELAY_OFFER_KIND: u16 = 31_960;
const RELAY_OFFER_VERSION: u8 = 2;
const RELAY_OFFER_TTL_SECS: u64 = 60;
const MAX_LAN_ENDPOINTS: usize = 4;

#[derive(Debug, Clone)]
pub(super) struct VerifiedRelayOffer {
    pub(super) session_id: String,
    pub(super) tunnel_npub: String,
    pub(super) expires_at: u64,
    pub(super) peer_tunnel_npub: Option<String>,
}

pub(super) struct CreatedRelayOffer {
    pub(super) signed_offer: String,
    pub(super) expires_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RelayOfferPayload {
    version: u8,
    #[serde(rename = "type")]
    message_type: String,
    session_id: String,
    role: String,
    tunnel_npub: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    peer_tunnel_npub: Option<String>,
    device_name: String,
    lan_endpoints: Vec<String>,
    issued_at: u64,
    expires_at: u64,
}

pub(super) fn create_offer(
    profile_secret: &str,
    session_id: &str,
    role: &str,
    tunnel_npub: &str,
    peer_tunnel_npub: Option<&str>,
    expires_at: Option<u64>,
    device_name: &str,
    lan_endpoints: &[String],
) -> Result<CreatedRelayOffer> {
    validate_session_id(session_id)?;
    validate_role(role)?;
    validate_device_name(device_name)?;
    let lan_endpoints = validate_lan_endpoints(lan_endpoints)?;
    PublicKey::parse(tunnel_npub.trim()).context("invalid relay tunnel public key")?;
    let peer_tunnel_npub = peer_tunnel_npub
        .map(|peer| {
            PublicKey::parse(peer.trim())
                .context("invalid relay peer tunnel public key")
                .and_then(|peer| peer.to_bech32().map_err(Into::into))
        })
        .transpose()?;
    if role == "requester" && peer_tunnel_npub.is_some() {
        bail!("requester relay offers must not name a peer tunnel");
    }
    if role == "relay" && peer_tunnel_npub.is_none() {
        bail!("relay offers must bind the requester tunnel");
    }

    let keys = Keys::parse(profile_secret.trim()).context("invalid profile secret key")?;
    let issued_at = now_secs();
    let expires_at = expires_at.unwrap_or_else(|| issued_at.saturating_add(RELAY_OFFER_TTL_SECS));
    if expires_at <= issued_at || expires_at > issued_at.saturating_add(RELAY_OFFER_TTL_SECS) {
        bail!("relay offer has an invalid lifetime");
    }
    let payload = RelayOfferPayload {
        version: RELAY_OFFER_VERSION,
        message_type: "fips_profile_relay_offer".to_string(),
        session_id: session_id.to_string(),
        role: role.to_string(),
        tunnel_npub: PublicKey::parse(tunnel_npub.trim())?.to_bech32()?,
        peer_tunnel_npub,
        device_name: device_name.trim().to_string(),
        lan_endpoints,
        issued_at,
        expires_at,
    };
    let event = EventBuilder::new(
        Kind::Custom(RELAY_OFFER_KIND),
        serde_json::to_string(&payload)?,
    )
    .finalize(&keys)?;
    Ok(CreatedRelayOffer {
        signed_offer: event.as_json(),
        expires_at,
    })
}

pub(super) fn verify_offer(
    signed_offer: &str,
    profile_secret: &str,
    expected_role: &str,
) -> Result<VerifiedRelayOffer> {
    validate_role(expected_role)?;
    let expected_profile = Keys::parse(profile_secret.trim())
        .context("invalid profile secret key")?
        .public_key();
    let event = Event::from_json(signed_offer).context("invalid signed relay offer")?;
    if event.kind != Kind::Custom(RELAY_OFFER_KIND) || !event.verify_signature() {
        bail!("relay offer signature is invalid");
    }
    if event.pubkey != expected_profile {
        bail!("relay offer is not signed by this profile");
    }
    let payload: RelayOfferPayload =
        serde_json::from_str(&event.content).context("invalid relay offer payload")?;
    if payload.version != RELAY_OFFER_VERSION
        || payload.message_type != "fips_profile_relay_offer"
        || payload.role != expected_role
    {
        bail!("relay offer protocol is invalid");
    }
    validate_session_id(&payload.session_id)?;
    validate_device_name(&payload.device_name)?;
    validate_lan_endpoints(&payload.lan_endpoints)?;
    let tunnel_npub = PublicKey::parse(payload.tunnel_npub.trim())
        .context("invalid relay tunnel public key")?
        .to_bech32()?;
    let peer_tunnel_npub = payload
        .peer_tunnel_npub
        .as_deref()
        .map(|peer| {
            PublicKey::parse(peer.trim())
                .context("invalid relay peer tunnel public key")
                .and_then(|peer| peer.to_bech32().map_err(Into::into))
        })
        .transpose()?;
    if expected_role == "requester" && peer_tunnel_npub.is_some() {
        bail!("requester relay offer names an unexpected peer tunnel");
    }
    if expected_role == "relay" && peer_tunnel_npub.is_none() {
        bail!("relay offer does not bind the requester tunnel");
    }
    let now = now_secs();
    if payload.issued_at > now.saturating_add(5)
        || payload.expires_at <= now
        || payload.expires_at > payload.issued_at.saturating_add(RELAY_OFFER_TTL_SECS)
    {
        bail!("relay offer is expired or has an invalid lifetime");
    }
    Ok(VerifiedRelayOffer {
        session_id: payload.session_id,
        tunnel_npub,
        expires_at: payload.expires_at,
        peer_tunnel_npub,
    })
}

pub(super) fn new_session_id() -> String {
    let mut bytes = [0u8; 16];
    let mut rng = OsRng;
    rng.fill_bytes(&mut bytes);
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn validate_session_id(value: &str) -> Result<()> {
    if value.len() != 32 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("relay session id is invalid");
    }
    Ok(())
}

fn validate_role(value: &str) -> Result<()> {
    if matches!(value, "requester" | "relay") {
        Ok(())
    } else {
        Err(anyhow!("relay offer role is invalid"))
    }
}

fn validate_device_name(value: &str) -> Result<()> {
    let value = value.trim();
    if value.is_empty()
        || value.len() > 64
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_graphic() || byte == b' ')
    {
        bail!("relay device name is invalid");
    }
    Ok(())
}

fn validate_lan_endpoints(values: &[String]) -> Result<Vec<String>> {
    if values.len() > MAX_LAN_ENDPOINTS {
        bail!("too many relay LAN endpoints");
    }
    let mut endpoints = Vec::with_capacity(values.len());
    for value in values {
        let address: SocketAddr = value.trim().parse().context("invalid relay LAN endpoint")?;
        if !is_private_or_loopback(address.ip()) {
            bail!("relay LAN endpoint must use a private or loopback address");
        }
        let canonical = address.to_string();
        if !endpoints.contains(&canonical) {
            endpoints.push(canonical);
        }
    }
    Ok(endpoints)
}

fn is_private_or_loopback(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ip) => ip.is_private() || ip.is_loopback() || ip.is_link_local(),
        IpAddr::V6(ip) => ip.is_loopback() || ip.is_unicast_link_local() || ip.is_unique_local(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn signed_offer_requires_the_same_profile_and_is_short_lived() {
        let profile = Keys::generate();
        let profile_secret = profile.secret_key().to_bech32().unwrap();
        let tunnel = Keys::generate().public_key().to_bech32().unwrap();
        let offer = create_offer(
            &profile_secret,
            &new_session_id(),
            "relay",
            &tunnel,
            Some(&Keys::generate().public_key().to_bech32().unwrap()),
            None,
            "Home laptop",
            &["192.168.1.10:41000".to_string()],
        )
        .unwrap();
        assert_eq!(
            verify_offer(&offer.signed_offer, &profile_secret, "relay")
                .unwrap()
                .tunnel_npub,
            tunnel
        );
        assert!(verify_offer(
            &offer.signed_offer,
            &Keys::generate().secret_key().to_bech32().unwrap(),
            "relay"
        )
        .is_err());
    }

    #[test]
    fn rejects_public_and_non_endpoint_hints() {
        let profile = Keys::generate().secret_key().to_bech32().unwrap();
        let tunnel = Keys::generate().public_key().to_bech32().unwrap();
        assert!(create_offer(
            &profile,
            &new_session_id(),
            "relay",
            &tunnel,
            Some(&Keys::generate().public_key().to_bech32().unwrap()),
            None,
            "Home laptop",
            &["8.8.8.8:41000".to_string()],
        )
        .is_err());
        assert!(create_offer(
            &profile,
            &new_session_id(),
            "relay",
            &tunnel,
            Some(&Keys::generate().public_key().to_bech32().unwrap()),
            None,
            "Home laptop",
            &["00:11:22:33:44:55".to_string()],
        )
        .is_err());
    }

    #[test]
    fn relay_offer_must_bind_the_requester_tunnel() {
        let profile = Keys::generate().secret_key().to_bech32().unwrap();
        let tunnel = Keys::generate().public_key().to_bech32().unwrap();
        assert!(create_offer(
            &profile,
            &new_session_id(),
            "relay",
            &tunnel,
            None,
            None,
            "Home laptop",
            &[],
        )
        .is_err());
        assert!(create_offer(
            &profile,
            &new_session_id(),
            "requester",
            &tunnel,
            Some(&Keys::generate().public_key().to_bech32().unwrap()),
            None,
            "Phone",
            &[],
        )
        .is_err());
    }

    #[test]
    fn relay_response_preserves_the_requester_expiration() {
        let profile = Keys::generate().secret_key().to_bech32().unwrap();
        let requester_tunnel = Keys::generate().public_key().to_bech32().unwrap();
        let relay_tunnel = Keys::generate().public_key().to_bech32().unwrap();
        let requester = create_offer(
            &profile,
            &new_session_id(),
            "requester",
            &requester_tunnel,
            None,
            None,
            "Phone",
            &[],
        )
        .unwrap();
        let requester = verify_offer(&requester.signed_offer, &profile, "requester").unwrap();
        let relay = create_offer(
            &profile,
            &requester.session_id,
            "relay",
            &relay_tunnel,
            Some(&requester.tunnel_npub),
            Some(requester.expires_at),
            "Home laptop",
            &[],
        )
        .unwrap();

        assert_eq!(relay.expires_at, requester.expires_at);
        assert_eq!(
            verify_offer(&relay.signed_offer, &profile, "relay")
                .unwrap()
                .expires_at,
            requester.expires_at
        );
    }

    #[test]
    fn offers_reject_wrong_roles_tampering_and_invalid_expirations() {
        let profile = Keys::generate().secret_key().to_bech32().unwrap();
        let requester_tunnel = Keys::generate().public_key().to_bech32().unwrap();
        let relay_tunnel = Keys::generate().public_key().to_bech32().unwrap();
        let requester = create_offer(
            &profile,
            &new_session_id(),
            "requester",
            &requester_tunnel,
            None,
            None,
            "Phone",
            &[],
        )
        .unwrap();

        assert!(verify_offer(&requester.signed_offer, &profile, "relay").is_err());
        assert!(verify_offer(
            &format!("{}x", requester.signed_offer),
            &profile,
            "requester"
        )
        .is_err());
        assert!(create_offer(
            &profile,
            &new_session_id(),
            "relay",
            &relay_tunnel,
            Some(&requester_tunnel),
            Some(now_secs()),
            "Home laptop",
            &[],
        )
        .is_err());
        assert!(create_offer(
            &profile,
            &new_session_id(),
            "relay",
            &relay_tunnel,
            Some(&requester_tunnel),
            Some(now_secs().saturating_add(RELAY_OFFER_TTL_SECS + 1)),
            "Home laptop",
            &[],
        )
        .is_err());
    }

    #[test]
    fn lan_hints_are_canonical_deduplicated_and_bounded() {
        let profile = Keys::generate().secret_key().to_bech32().unwrap();
        let tunnel = Keys::generate().public_key().to_bech32().unwrap();
        let peer = Keys::generate().public_key().to_bech32().unwrap();
        let offer = create_offer(
            &profile,
            &new_session_id(),
            "relay",
            &tunnel,
            Some(&peer),
            None,
            "Home laptop",
            &[
                "192.168.1.10:41000".to_string(),
                "192.168.1.10:41000".to_string(),
                "[fd00::1]:41000".to_string(),
            ],
        )
        .unwrap();
        let event = Event::from_json(&offer.signed_offer).unwrap();
        let payload: RelayOfferPayload = serde_json::from_str(&event.content).unwrap();

        assert_eq!(
            payload.lan_endpoints,
            ["192.168.1.10:41000", "[fd00::1]:41000"]
        );
        assert!(create_offer(
            &profile,
            &new_session_id(),
            "relay",
            &tunnel,
            Some(&peer),
            None,
            "Home laptop",
            &vec!["127.0.0.1:41000".to_string(); MAX_LAN_ENDPOINTS + 1],
        )
        .is_err());
    }
}
