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
const ENCRYPTED_PNG_CHUNK: &[u8; 4] = b"npCt";
const ENCRYPTED_PNG_MAGIC: &[u8; 4] = b"NCP1";
const PNG_SIGNATURE: &[u8; 8] = b"\x89PNG\r\n\x1a\n";
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

pub fn wrap_encrypted_payload_as_png(ciphertext: &[u8]) -> Vec<u8> {
    let mut png = Vec::new();
    png.extend_from_slice(PNG_SIGNATURE);

    let mut ihdr = Vec::new();
    ihdr.extend_from_slice(&1u32.to_be_bytes());
    ihdr.extend_from_slice(&1u32.to_be_bytes());
    ihdr.extend_from_slice(&[8, 6, 0, 0, 0]);
    write_png_chunk(&mut png, b"IHDR", &ihdr);

    let mut encrypted = Vec::with_capacity(ENCRYPTED_PNG_MAGIC.len() + ciphertext.len());
    encrypted.extend_from_slice(ENCRYPTED_PNG_MAGIC);
    encrypted.extend_from_slice(ciphertext);
    write_png_chunk(&mut png, ENCRYPTED_PNG_CHUNK, &encrypted);

    let transparent_pixel = [0u8; 5];
    write_png_chunk(&mut png, b"IDAT", &zlib_stored_block(&transparent_pixel));
    write_png_chunk(&mut png, b"IEND", &[]);
    png
}

pub fn unwrap_encrypted_payload(bytes: &[u8]) -> Result<Vec<u8>> {
    if !bytes.starts_with(PNG_SIGNATURE) {
        return Ok(bytes.to_vec());
    }

    let mut offset = PNG_SIGNATURE.len();
    while offset + 12 <= bytes.len() {
        let len = u32::from_be_bytes(bytes[offset..offset + 4].try_into().unwrap()) as usize;
        let chunk_type_start = offset + 4;
        let data_start = chunk_type_start + 4;
        let data_end = data_start + len;
        let next = data_end + 4;
        if next > bytes.len() {
            break;
        }
        let chunk_type = &bytes[chunk_type_start..data_start];
        let data = &bytes[data_start..data_end];
        if chunk_type == ENCRYPTED_PNG_CHUNK && data.starts_with(ENCRYPTED_PNG_MAGIC) {
            return Ok(data[ENCRYPTED_PNG_MAGIC.len()..].to_vec());
        }
        offset = next;
    }

    Ok(bytes.to_vec())
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

fn write_png_chunk(output: &mut Vec<u8>, chunk_type: &[u8; 4], data: &[u8]) {
    output.extend_from_slice(&(data.len() as u32).to_be_bytes());
    output.extend_from_slice(chunk_type);
    output.extend_from_slice(data);
    let mut crc_input = Vec::with_capacity(chunk_type.len() + data.len());
    crc_input.extend_from_slice(chunk_type);
    crc_input.extend_from_slice(data);
    output.extend_from_slice(&crc32(&crc_input).to_be_bytes());
}

fn zlib_stored_block(data: &[u8]) -> Vec<u8> {
    let mut zlib = vec![0x78, 0x01, 0x01];
    let len = data.len() as u16;
    zlib.extend_from_slice(&len.to_le_bytes());
    zlib.extend_from_slice(&(!len).to_le_bytes());
    zlib.extend_from_slice(data);
    zlib.extend_from_slice(&adler32(data).to_be_bytes());
    zlib
}

fn crc32(bytes: &[u8]) -> u32 {
    let mut crc = 0xffff_ffffu32;
    for byte in bytes {
        crc ^= *byte as u32;
        for _ in 0..8 {
            crc = if crc & 1 == 1 {
                (crc >> 1) ^ 0xedb8_8320
            } else {
                crc >> 1
            };
        }
    }
    !crc
}

fn adler32(bytes: &[u8]) -> u32 {
    let mut a = 1u32;
    let mut b = 0u32;
    for byte in bytes {
        a = (a + *byte as u32) % 65521;
        b = (b + a) % 65521;
    }
    (b << 16) | a
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
    fn wraps_and_unwraps_encrypted_payload_as_png() {
        let ciphertext = b"encrypted bytes";
        let wrapped = wrap_encrypted_payload_as_png(ciphertext);
        assert!(wrapped.starts_with(PNG_SIGNATURE));
        assert_eq!(unwrap_encrypted_payload(&wrapped).unwrap(), ciphertext);
        assert_eq!(unwrap_encrypted_payload(ciphertext).unwrap(), ciphertext);
    }

    #[test]
    fn rejects_tampered_ciphertext() {
        let plaintext = b"voice";
        let (mut ciphertext, encryption) = encrypt_audio_payload(plaintext, "audio/wav").unwrap();
        ciphertext[0] ^= 0xff;

        assert!(decrypt_audio_payload(&ciphertext, &encryption).is_err());
    }
}
