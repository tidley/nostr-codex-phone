use anyhow::{anyhow, Context, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use chacha20poly1305::aead::{Aead, Payload};
use chacha20poly1305::{KeyInit, XChaCha20Poly1305, XNonce};
use rand::rngs::OsRng;
use rand::RngCore;
use sha2::{Digest, Sha256};

use crate::protocol::{AudioEncryption, AUDIO_ENCRYPTION_ALGORITHM};

const AUDIO_AAD: &[u8] = b"nostr-codex-phone/audio/v1";
const KEY_LEN: usize = 32;
const NONCE_LEN: usize = 24;

pub fn encrypt_audio_payload(
    plaintext: &[u8],
    media_type: &str,
) -> Result<(Vec<u8>, AudioEncryption)> {
    if plaintext.is_empty() {
        return Err(anyhow!("audio payload is empty"));
    }

    let mut key = [0u8; KEY_LEN];
    let mut nonce = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut key);
    OsRng.fill_bytes(&mut nonce);

    let cipher = XChaCha20Poly1305::new_from_slice(&key)
        .context("failed to initialize audio encryption cipher")?;
    let ciphertext = cipher
        .encrypt(
            XNonce::from_slice(&nonce),
            Payload {
                msg: plaintext,
                aad: AUDIO_AAD,
            },
        )
        .map_err(|_| anyhow!("failed to encrypt audio payload"))?;

    Ok((
        ciphertext,
        AudioEncryption {
            algorithm: AUDIO_ENCRYPTION_ALGORITHM.to_string(),
            key: URL_SAFE_NO_PAD.encode(key),
            nonce: URL_SAFE_NO_PAD.encode(nonce),
            plaintext_sha256: sha256_hex(plaintext),
            plaintext_size: plaintext.len() as u64,
            plaintext_media_type: media_type.to_string(),
        },
    ))
}

pub fn decrypt_audio_payload(ciphertext: &[u8], encryption: &AudioEncryption) -> Result<Vec<u8>> {
    if encryption.algorithm != AUDIO_ENCRYPTION_ALGORITHM {
        return Err(anyhow!(
            "unsupported audio encryption algorithm `{}`",
            encryption.algorithm
        ));
    }

    let key = decode_exact("audio.encryption.key", &encryption.key, KEY_LEN)?;
    let nonce = decode_exact("audio.encryption.nonce", &encryption.nonce, NONCE_LEN)?;
    let cipher = XChaCha20Poly1305::new_from_slice(&key)
        .context("failed to initialize audio decryption cipher")?;
    let plaintext = cipher
        .decrypt(
            XNonce::from_slice(&nonce),
            Payload {
                msg: ciphertext,
                aad: AUDIO_AAD,
            },
        )
        .map_err(|_| anyhow!("failed to decrypt audio payload"))?;

    if plaintext.len() as u64 != encryption.plaintext_size {
        return Err(anyhow!(
            "decrypted audio size mismatch: expected {} bytes, got {} bytes",
            encryption.plaintext_size,
            plaintext.len()
        ));
    }

    let actual_hash = sha256_hex(&plaintext);
    if actual_hash != encryption.plaintext_sha256.to_lowercase() {
        return Err(anyhow!(
            "decrypted audio sha256 mismatch: expected {}, got {actual_hash}",
            encryption.plaintext_sha256
        ));
    }

    Ok(plaintext)
}

fn decode_exact(field: &str, value: &str, expected_len: usize) -> Result<Vec<u8>> {
    let decoded = URL_SAFE_NO_PAD
        .decode(value)
        .with_context(|| format!("field `{field}` is not valid base64url"))?;
    if decoded.len() != expected_len {
        return Err(anyhow!(
            "field `{field}` must decode to {expected_len} bytes, got {} bytes",
            decoded.len()
        ));
    }
    Ok(decoded)
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encrypts_and_decrypts_audio_payload() {
        let plaintext = b"RIFF test wav bytes";
        let (ciphertext, encryption) = encrypt_audio_payload(plaintext, "audio/wav").unwrap();

        assert_ne!(ciphertext, plaintext);
        assert_eq!(encryption.algorithm, AUDIO_ENCRYPTION_ALGORITHM);
        assert_eq!(encryption.plaintext_size, plaintext.len() as u64);
        assert_eq!(encryption.plaintext_media_type, "audio/wav");

        let decrypted = decrypt_audio_payload(&ciphertext, &encryption).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn rejects_tampered_ciphertext() {
        let plaintext = b"voice";
        let (mut ciphertext, encryption) = encrypt_audio_payload(plaintext, "audio/wav").unwrap();
        ciphertext[0] ^= 0xff;

        assert!(decrypt_audio_payload(&ciphertext, &encryption).is_err());
    }
}
