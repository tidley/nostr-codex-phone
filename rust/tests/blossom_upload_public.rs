use std::env;
use std::time::{Duration, Instant};

use nostr_sdk::prelude::Keys;
use rand::RngCore;
use rust_lib_nostr_codex_phone::blossom::{upload_audio, BlossomUploadConfig};
use tempfile::NamedTempFile;

fn should_run_live_blossom_tests() -> bool {
    matches!(
        env::var("RUN_PUBLIC_BLOSSOM_UPLOAD_TESTS").ok().as_deref(),
        Some(value) if value == "1"
    )
}

fn get_public_secret_key() -> String {
    env::var("BLOSSOM_SECRET_KEY")
        .or_else(|_| env::var("NOSTR_SECRET_KEY"))
        .unwrap_or_else(|_| Keys::generate().secret_key().to_secret_hex())
}

fn public_blossom_candidates() -> Vec<String> {
    env::var("BLOSSOM_TEST_SERVER_URL")
        .map(|server| vec![server])
        .unwrap_or_else(|_| {
            vec![
                "https://blossom.nostr.build".to_string(),
                "https://blossom.primal.net".to_string(),
            ]
        })
}

fn create_random_file(bytes: usize) -> std::io::Result<NamedTempFile> {
    let mut file = NamedTempFile::new()?;
    let mut payload = vec![0u8; bytes];
    rand::thread_rng().fill_bytes(&mut payload);
    use std::io::Write as _;
    file.write_all(&payload)?;
    file.flush()?;
    Ok(file)
}

#[tokio::test]
async fn uploads_random_300kb_blobs_to_public_blossom_server() {
    if !should_run_live_blossom_tests() {
        eprintln!(
            "Skipping public Blossom test. Set RUN_PUBLIC_BLOSSOM_UPLOAD_TESTS=1 and provide \
             BLOSSOM_SECRET_KEY/NOSTR_SECRET_KEY to run against live servers."
        );
        return;
    }

    let secret_key = get_public_secret_key();
    let servers = public_blossom_candidates();
    let mut last_error: Option<String> = None;

    const SIZE: usize = 300 * 1024;
    const CASES: &[(&str, &str)] = &[
        ("text/plain; charset=utf-8", "note.txt"),
        ("audio/ogg", "voice-note.ogg"),
    ];
    const ATTEMPTS: usize = 3;

    for server in &servers {
        let started_server = Instant::now();
        let mut uploads_ok = true;

        for attempt in 1..=ATTEMPTS {
            for (content_type, file_name) in CASES {
                let file = create_random_file(SIZE).unwrap_or_else(|err| {
                    panic!("failed to create test payload: {err}");
                });
                let path = file.path().to_string_lossy().to_string();

                let started = Instant::now();
                let attachment = match upload_audio(BlossomUploadConfig {
                    secret_key: secret_key.clone(),
                    server_url: server.clone(),
                    file_path: path,
                    content_type: (*content_type).to_string(),
                    file_name: Some((*file_name).to_string()),
                })
                .await
                {
                    Ok(attachment) => attachment,
                    Err(err) => {
                        uploads_ok = false;
                        last_error = Some(format!(
                            "server={server}, attempt={attempt}, type={content_type}: {err:#}"
                        ));
                        break;
                    }
                };
                let elapsed = started.elapsed();

                assert!(
                    !attachment.sha256.trim().is_empty(),
                    "server={server}, attempt={attempt}, type={content_type} returned missing sha256"
                );
                assert!(
                    attachment.size > 0,
                    "server={server}, attempt={attempt}, type={content_type} returned zero size"
                );
                assert!(
                    elapsed < Duration::from_secs(90),
                    "server={server}, attempt={attempt}, type={content_type} upload took too long: {elapsed:?}"
                );
                println!(
                    "upload success [server={server}] [attempt={attempt}] [type={content_type}] in {elapsed:?}: size={} sha={}",
                    attachment.size,
                    attachment.sha256
                );
            }

            if !uploads_ok {
                break;
            }
        }

        if uploads_ok {
            println!(
                "public Blossom upload test succeeded for {server} in {:?}",
                started_server.elapsed()
            );
            return;
        }
    }

    panic!(
        "all Blossom upload attempts failed. last_error={}",
        last_error.unwrap_or_else(|| "none".to_string())
    );
}
