use anyhow::Result;
use nostr_sdk::prelude::*;

fn main() -> Result<()> {
    let keys = Keys::generate();
    println!("NOSTR_SECRET_KEY={}", keys.secret_key().to_bech32()?);
    println!("NOSTR_PUBLIC_KEY={}", keys.public_key().to_bech32()?);
    println!("NOSTR_PUBLIC_KEY_HEX={}", keys.public_key().to_hex());
    Ok(())
}
