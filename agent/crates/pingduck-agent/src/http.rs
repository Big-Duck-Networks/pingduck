//! A deliberately small HTTP/1.0 server for the agent's LAN endpoints.
//! Every request is bounded in size and time; anything unusual is dropped.

use std::collections::HashMap;
use std::io::{ErrorKind, Read, Write};
use std::net::{Shutdown, SocketAddr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

pub const MAX_HEADER_BYTES: usize = 4096;
pub const MAX_BODY_BYTES: usize = 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(2);
const MAX_CONNECTIONS: usize = 8;

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct HttpRequest {
    pub method: String,
    /// Without the query string.
    pub path: String,
    /// Lower-cased names.
    pub headers: HashMap<String, String>,
    pub body: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpReply {
    pub status: u16,
    pub body: String,
    pub content_type: &'static str,
}

impl HttpReply {
    pub fn json(status: u16, body: String) -> Self {
        HttpReply { status, body, content_type: "application/json" }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum Parse {
    Complete(HttpRequest),
    /// Read more.
    Incomplete,
    /// Close the connection.
    Invalid,
}

/// Parses one request from the bytes read so far.
pub fn parse_request(raw: &[u8]) -> Parse {
    let Some(end) = raw.windows(4).position(|w| w == b"\r\n\r\n") else {
        return if raw.len() > MAX_HEADER_BYTES { Parse::Invalid } else { Parse::Incomplete };
    };
    if end > MAX_HEADER_BYTES {
        return Parse::Invalid;
    }
    let Ok(head) = std::str::from_utf8(&raw[..end]) else { return Parse::Invalid };
    let mut lines = head.split("\r\n");
    let start: Vec<&str> = lines.next().unwrap_or_default().splitn(3, ' ').collect();
    let [method, target, version] = start[..] else { return Parse::Invalid };
    if version != "HTTP/1.0" && version != "HTTP/1.1" || !target.starts_with('/') || method.is_empty() {
        return Parse::Invalid;
    }

    let mut req = HttpRequest {
        method: method.into(),
        path: target.split('?').next().unwrap_or("/").into(),
        ..HttpRequest::default()
    };
    for line in lines {
        let Some((name, value)) = line.split_once(':') else { return Parse::Invalid };
        if name.is_empty() || req.headers.len() >= 32 {
            return Parse::Invalid;
        }
        req.headers.insert(name.trim().to_ascii_lowercase(), value.trim().to_string());
    }
    if req.headers.contains_key("transfer-encoding") {
        return Parse::Invalid;
    }
    let length = match req.headers.get("content-length") {
        None => 0,
        Some(v) if !v.is_empty() && v.len() <= 6 && v.bytes().all(|b| b.is_ascii_digit()) => v.parse().unwrap_or(0),
        Some(_) => return Parse::Invalid,
    };
    if length > MAX_BODY_BYTES {
        return Parse::Invalid;
    }
    let body = &raw[end + 4..];
    if body.len() < length {
        return Parse::Incomplete;
    }
    req.body = String::from_utf8_lossy(&body[..length]).into_owned();
    Parse::Complete(req)
}

fn reason(status: u16) -> &'static str {
    match status {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        409 => "Conflict",
        415 => "Unsupported Media Type",
        429 => "Too Many Requests",
        502 => "Bad Gateway",
        _ => "Error",
    }
}

pub fn format_reply(r: &HttpReply) -> Vec<u8> {
    format!(
        "HTTP/1.0 {} {}\r\nContent-Type: {}\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n{}",
        r.status,
        reason(r.status),
        r.content_type,
        r.body.len(),
        r.body
    )
    .into_bytes()
}

pub type Handler = Arc<dyn Fn(&HttpRequest, &str) -> HttpReply + Send + Sync>;

fn handle_connection(mut stream: TcpStream, peer: String, handler: &Handler) {
    let deadline = Instant::now() + REQUEST_TIMEOUT;
    let mut raw = Vec::new();
    let mut buf = [0u8; 1024];
    let parsed = loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() || stream.set_read_timeout(Some(left)).is_err() {
            break Parse::Incomplete;
        }
        match stream.read(&mut buf) {
            Ok(0) | Err(_) => break Parse::Incomplete,
            Ok(n) => raw.extend_from_slice(&buf[..n]),
        }
        match parse_request(&raw) {
            Parse::Incomplete => continue,
            other => break other,
        }
    };
    let reply = match parsed {
        Parse::Complete(req) => Some(handler(&req, &peer)),
        Parse::Invalid => Some(HttpReply::json(400, r#"{"error":"bad_request"}"#.into())),
        Parse::Incomplete => None,
    };
    if let Some(r) = reply {
        let _ = stream.set_write_timeout(Some(REQUEST_TIMEOUT));
        let _ = stream.write_all(&format_reply(&r));
    }
    let _ = stream.shutdown(Shutdown::Both);
}

/// Accepts on 0.0.0.0:`port` until `stop` is set. Each connection gets its
/// own short-lived thread (at most 8 at once), so a slow pair call doesn't
/// block /info.
pub fn serve(port: u16, handler: Handler, stop: Arc<AtomicBool>) -> std::io::Result<()> {
    let listener = TcpListener::bind(SocketAddr::from(([0, 0, 0, 0], port)))?;
    listener.set_nonblocking(true)?;
    let active = Arc::new(AtomicUsize::new(0));
    while !stop.load(Ordering::Relaxed) {
        match listener.accept() {
            Ok((stream, addr)) => {
                if active.load(Ordering::Relaxed) >= MAX_CONNECTIONS {
                    continue; // dropped: closes the socket
                }
                let _ = stream.set_nonblocking(false);
                active.fetch_add(1, Ordering::Relaxed);
                let (handler, active) = (handler.clone(), active.clone());
                std::thread::spawn(move || {
                    handle_connection(stream, addr.ip().to_string(), &handler);
                    active.fetch_sub(1, Ordering::Relaxed);
                });
            }
            Err(e) if e.kind() == ErrorKind::WouldBlock => std::thread::sleep(Duration::from_millis(100)),
            Err(_) => std::thread::sleep(Duration::from_millis(100)),
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_request_with_a_body() {
        let raw = b"POST /pingduck/v1/pair?x=1 HTTP/1.1\r\nHost: a\r\nContent-Type: application/json\r\nContent-Length: 19\r\n\r\n{\"code\":\"ABCD2345\"}";
        let Parse::Complete(r) = parse_request(raw) else { panic!("not parsed") };
        assert_eq!(r.method, "POST");
        assert_eq!(r.path, "/pingduck/v1/pair");
        assert_eq!(r.headers["content-type"], "application/json");
        assert_eq!(r.body, "{\"code\":\"ABCD2345\"}");
        assert_eq!(parse_request(&raw[..raw.len() - 3]), Parse::Incomplete);
    }

    #[test]
    fn rejects_oversized_and_odd_requests() {
        assert_eq!(parse_request(&[b'A'; 5000]), Parse::Invalid);
        assert_eq!(parse_request(b"GET / HTTP/1.1\r\nContent-Length: 99999\r\n\r\n"), Parse::Invalid);
        assert_eq!(parse_request(b"GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"), Parse::Invalid);
        assert_eq!(parse_request(b"GET http://x/ HTTP/1.1\r\n\r\n"), Parse::Invalid);
        assert_eq!(parse_request(b"GET / SPDY/3\r\n\r\n"), Parse::Invalid);
        assert_eq!(parse_request(b"GET / HTTP/1.1\r\nno colon\r\n\r\n"), Parse::Invalid);
        assert_eq!(parse_request(b"GET / HTTP/1.1\r\nContent-Length: -1\r\n\r\n"), Parse::Invalid);
    }

    #[test]
    fn serves_over_tcp() {
        let stop = Arc::new(AtomicBool::new(false));
        let port = {
            let l = TcpListener::bind("127.0.0.1:0").unwrap();
            l.local_addr().unwrap().port()
        };
        let handler: Handler = Arc::new(|r, peer| HttpReply::json(200, format!("{{\"path\":\"{}\",\"peer\":\"{}\"}}", r.path, peer)));
        let s = stop.clone();
        let t = std::thread::spawn(move || serve(port, handler, s));
        std::thread::sleep(Duration::from_millis(200));
        let mut c = TcpStream::connect(("127.0.0.1", port)).unwrap();
        c.write_all(b"GET /x HTTP/1.0\r\n\r\n").unwrap();
        let mut out = String::new();
        c.read_to_string(&mut out).unwrap();
        assert!(out.starts_with("HTTP/1.0 200 OK"), "{out}");
        assert!(out.ends_with(r#"{"path":"/x","peer":"127.0.0.1"}"#), "{out}");
        stop.store(true, Ordering::Relaxed);
        t.join().unwrap().unwrap();
    }
}
