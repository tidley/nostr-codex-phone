use std::collections::HashMap;
use std::io;
use std::sync::Arc;
use std::time::{Duration, Instant};

use nostr_sdk::prelude::Keys;
use rand::RngCore;
use rust_lib_nostr_codex_phone::blossom::{upload_audio, BlossomUploadConfig};
use tempfile::NamedTempFile;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::Mutex;

#[derive(Debug, Clone)]
struct UploadCapture {
    path: String,
    content_length: usize,
    content_type: Option<String>,
    x_sha256: Option<String>,
}

async fn read_http_request(
    mut socket: TcpStream,
    port: u16,
    captures: Arc<Mutex<Vec<UploadCapture>>>,
) -> io::Result<()> {
    let mut buffer = vec![0u8; 8192];
    let mut data: Vec<u8> = Vec::new();

    loop {
        let n = socket.read(&mut buffer).await?;
        if n == 0 {
            return Ok(());
        }
        data.extend_from_slice(&buffer[..n]);
        if data.windows(4).any(|window| window == b"\r\n\r\n") {
            break;
        }
    }

    let header_end = match data.windows(4).position(|window| window == b"\r\n\r\n") {
        Some(pos) => pos + 4,
        None => return Ok(()),
    };

    let header_text = String::from_utf8_lossy(&data[..header_end]);
    let mut lines = header_text.split("\r\n");
    let start_line = lines.next().unwrap_or_default();
    let path = start_line
        .split_whitespace()
        .nth(1)
        .unwrap_or("/")
        .to_string();

    let headers: HashMap<String, String> = lines
        .take_while(|line| !line.is_empty())
        .filter_map(|line| {
            let mut parts = line.splitn(2, ':');
            let key = parts.next()?.trim().to_ascii_lowercase();
            let value = parts.next()?.trim().to_string();
            Some((key, value))
        })
        .collect();

    let content_length = headers
        .get("content-length")
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(0);

    let mut body = data[header_end..].to_vec();
    while body.len() < content_length {
        let n = socket.read(&mut buffer).await?;
        if n == 0 {
            break;
        }
        body.extend_from_slice(&buffer[..n]);
    }

    let x_sha256 = headers.get("x-sha-256").cloned();
    let content_type = headers.get("content-type").cloned();

    captures.lock().await.push(UploadCapture {
        path,
        content_length,
        content_type,
        x_sha256: x_sha256.clone(),
    });

    let descriptor = match x_sha256 {
        Some(sha) => format!(
            "{{\"url\":\"http://127.0.0.1:{port}/blob/{sha}\",\"sha256\":\"{sha}\",\"size\":{size},\"type\":\"{media_type}\"}}",
            port = port,
            sha = sha,
            size = body.len(),
            media_type = "application/octet-stream"
        ),
        None => return Ok(()),
    };

    let mut response = Vec::new();
    response.extend_from_slice(b"HTTP/1.1 200 OK\r\n");
    response.extend_from_slice(b"content-type: application/json\r\n");
    response.extend_from_slice(format!("content-length: {}\r\n", descriptor.len()).as_bytes());
    response.extend_from_slice(b"\r\n");
    response.extend_from_slice(descriptor.as_bytes());
    socket.write_all(&response).await?;

    Ok(())
}

async fn spawn_mock_blossom_server(
    expected_uploads: usize,
) -> io::Result<(
    u16,
    Arc<Mutex<Vec<UploadCapture>>>,
    tokio::task::JoinHandle<()>,
)> {
    let listener = TcpListener::bind(("127.0.0.1", 0)).await?;
    let port = listener.local_addr()?.port();
    let captures = Arc::new(Mutex::new(Vec::new()));
    let captures_task = captures.clone();

    let handle = tokio::spawn(async move {
        for _ in 0..expected_uploads {
            let accepted = listener.accept().await;
            let Ok((socket, _)) = accepted else {
                return;
            };
            read_http_request(socket, port, captures_task.clone())
                .await
                .unwrap_or_default();
        }
    });

    Ok((port, captures, handle))
}

fn create_random_file(bytes: usize) -> io::Result<NamedTempFile> {
    let mut file = NamedTempFile::new()?;
    let mut payload = vec![0u8; bytes];
    rand::thread_rng().fill_bytes(&mut payload);
    use std::io::Write as _;
    file.write_all(&payload)?;
    file.flush()?;
    Ok(file)
}

fn generated_secret_key_hex() -> String {
    Keys::generate().secret_key().to_secret_hex()
}

#[tokio::test]
async fn uploads_random_300kb_blobs_for_text_and_audio_notes() {
    const SIZE: usize = 300 * 1024;

    let (port, captures, server) = spawn_mock_blossom_server(2)
        .await
        .expect("start mock server");

    let secret_key = generated_secret_key_hex();
    let server_url = format!("http://127.0.0.1:{port}");

    let cases = [
        ("text/plain; charset=utf-8", "note.txt", "text note"),
        ("audio/ogg", "voice-note.ogg", "audio note"),
    ];

    for (content_type, file_name, label) in cases {
        let file = create_random_file(SIZE).expect("create random blob");
        let path = file.path().to_string_lossy().to_string();

        let started = Instant::now();
        let attachment = upload_audio(BlossomUploadConfig {
            secret_key: secret_key.clone(),
            server_url: server_url.clone(),
            file_path: path,
            content_type: content_type.to_string(),
            file_name: Some(file_name.to_string()),
        })
        .await
        .expect("upload succeeds");
        let elapsed = started.elapsed();

        assert!(!attachment.sha256.is_empty(), "{label}: missing sha256");
        assert!(attachment.size > 0, "{label}: expected non-empty upload");
        assert!(
            elapsed < Duration::from_secs(10),
            "{label} upload took too long: {elapsed:?}"
        );
        println!(
            "{label} upload success in {elapsed:?}: size={} name={} sha={}",
            attachment.size,
            attachment.name.as_deref().unwrap_or("<none>"),
            attachment.sha256,
        );
    }

    let observed = captures.lock().await;
    assert_eq!(observed.len(), 2, "expected two uploads");
    assert_eq!(observed[0].path, "/upload");
    assert_eq!(observed[1].path, "/upload");
    assert_eq!(observed[0].content_type.as_deref(), Some("text/plain"));
    assert_eq!(observed[1].content_type.as_deref(), Some("audio/ogg"));
    assert!(observed[0].content_length >= SIZE);
    assert!(observed[1].content_length >= SIZE);
    assert_ne!(observed[0].x_sha256, None);
    assert_ne!(observed[1].x_sha256, None);

    server.abort();
}
