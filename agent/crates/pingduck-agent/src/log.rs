//! One log line per event: to stdout (docker logs, a console run) and, once
//! [to_file] is called, appended to a file (the Windows service has no
//! console). The file is capped at 1 MB, keeping one previous copy.

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;

static FILE: Mutex<Option<PathBuf>> = Mutex::new(None);
const MAX_BYTES: u64 = 1024 * 1024;

pub fn to_file(path: PathBuf) {
    *FILE.lock().unwrap() = Some(path);
}

pub fn line(msg: &str) {
    println!("{msg}");
    let guard = FILE.lock().unwrap();
    let Some(path) = guard.as_ref() else { return };
    if fs::metadata(path).is_ok_and(|m| m.len() > MAX_BYTES) {
        let _ = fs::rename(path, path.with_extension("log.old"));
    }
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(path) {
        let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        let _ = writeln!(f, "{secs} {msg}");
    }
}

/// `println!`-style logging through [line].
#[macro_export]
macro_rules! log {
    ($($arg:tt)*) => { $crate::log::line(&format!($($arg)*)) };
}
