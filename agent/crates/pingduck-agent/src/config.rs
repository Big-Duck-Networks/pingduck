//! Agent settings, all from environment variables with working defaults.

use std::path::PathBuf;
use std::time::Duration;

/// Same project and key the app ships with
/// (pingduck_app/lib/core/constants/supabase_config.dart).
const DEFAULT_URL: &str = "https://rumwtzzyrhzudguolasq.supabase.co";
const DEFAULT_KEY: &str = "sb_publishable_eWbf9jGpxBWQ6t7Vtz8r5A_mWfdmVrK";
pub const DEFAULT_PORT: u16 = 44480;
pub const DEFAULT_SCAN_EVERY: Duration = Duration::from_secs(300);
const MIN_SCAN_EVERY: Duration = Duration::from_secs(60);
const MAX_SCAN_EVERY: Duration = Duration::from_secs(24 * 3600);

#[derive(Debug, Clone)]
pub struct Config {
    pub supabase_url: String,
    /// Publishable key only; RLS and the RPCs decide what it can do.
    pub supabase_key: String,
    pub state_dir: PathBuf,
    /// Shown in the app.
    pub name: String,
    /// Manual fallback, redeemed once at start while unpaired.
    pub pairing_code: String,
    pub http_port: u16,
    /// Time between scans while paired.
    pub scan_every: Duration,
    /// Subnet to scan (e.g. a VLAN); None for the default interface's.
    pub scan_cidr: Option<String>,
    /// IEEE OUI registry for vendor names.
    pub oui_path: PathBuf,
}

/// oui.csv beside the executable (the Windows install), else the image's copy.
fn default_oui_path() -> PathBuf {
    let beside = std::env::current_exe().ok().and_then(|exe| exe.parent().map(|d| d.join("oui.csv")));
    match beside {
        Some(p) if p.exists() => p,
        _ => PathBuf::from("/usr/share/pingduck/oui.csv"),
    }
}

fn default_state_dir() -> PathBuf {
    if cfg!(windows) {
        let base = std::env::var_os("ProgramData").unwrap_or_else(|| "C:\\ProgramData".into());
        PathBuf::from(base).join("PingDuck")
    } else {
        PathBuf::from("/var/lib/pingduck")
    }
}

fn host_name() -> String {
    let name = if cfg!(windows) {
        std::env::var("COMPUTERNAME").ok()
    } else {
        std::fs::read_to_string("/proc/sys/kernel/hostname").ok().or_else(|| std::env::var("HOSTNAME").ok())
    };
    name.map(|n| n.trim().to_string()).filter(|n| !n.is_empty()).unwrap_or_else(|| "pingduck-agent".into())
}

impl Config {
    /// Reads `PINGDUCK_*` through `get`, so tests needn't touch the process env.
    pub fn load(get: impl Fn(&str) -> Option<String>) -> Self {
        let env = |name: &str| get(name).filter(|v| !v.is_empty());
        let port = env("PINGDUCK_HTTP_PORT").and_then(|p| p.parse::<u16>().ok()).filter(|&p| p > 0);
        Config {
            supabase_url: env("PINGDUCK_SUPABASE_URL").unwrap_or_else(|| DEFAULT_URL.into()).trim_end_matches('/').into(),
            supabase_key: env("PINGDUCK_SUPABASE_KEY").unwrap_or_else(|| DEFAULT_KEY.into()),
            state_dir: env("PINGDUCK_STATE_DIR").map(PathBuf::from).unwrap_or_else(default_state_dir),
            name: env("PINGDUCK_AGENT_NAME").unwrap_or_else(host_name).chars().take(64).collect(),
            pairing_code: env("PINGDUCK_PAIRING_CODE").unwrap_or_default(),
            http_port: port.unwrap_or(DEFAULT_PORT),
            scan_every: env("PINGDUCK_SCAN_INTERVAL")
                .and_then(|v| v.parse::<u64>().ok())
                .map(|secs| Duration::from_secs(secs).clamp(MIN_SCAN_EVERY, MAX_SCAN_EVERY))
                .unwrap_or(DEFAULT_SCAN_EVERY),
            scan_cidr: env("PINGDUCK_SCAN_CIDR"),
            oui_path: env("PINGDUCK_OUI_PATH").map(PathBuf::from).unwrap_or_else(default_oui_path),
        }
    }

    pub fn from_env() -> Self {
        Self::load(|k| std::env::var(k).ok())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn defaults_and_overrides() {
        let c = Config::load(|_| None);
        assert_eq!(c.http_port, 44480);
        assert!(c.supabase_url.starts_with("https://"));
        assert!(!c.name.is_empty());
        assert_eq!(c.scan_every, DEFAULT_SCAN_EVERY);
        assert_eq!(c.scan_cidr, None);

        let env: HashMap<&str, &str> = [
            ("PINGDUCK_SUPABASE_URL", "http://localhost:54321/"),
            ("PINGDUCK_HTTP_PORT", "9000"),
            ("PINGDUCK_AGENT_NAME", "lab"),
            ("PINGDUCK_STATE_DIR", "/tmp/x"),
            ("PINGDUCK_SCAN_INTERVAL", "120"),
            ("PINGDUCK_SCAN_CIDR", "10.0.20.0/24"),
            ("PINGDUCK_OUI_PATH", "/data/oui.csv"),
        ]
        .into();
        let c = Config::load(|k| env.get(k).map(|v| v.to_string()));
        assert_eq!(c.supabase_url, "http://localhost:54321");
        assert_eq!(c.http_port, 9000);
        assert_eq!(c.name, "lab");
        assert_eq!(c.state_dir, PathBuf::from("/tmp/x"));
        assert_eq!(c.scan_every, Duration::from_secs(120));
        assert_eq!(c.scan_cidr.as_deref(), Some("10.0.20.0/24"));
        assert_eq!(c.oui_path, PathBuf::from("/data/oui.csv"));
    }

    #[test]
    fn scan_interval_is_kept_sane() {
        let every = |v: &str| Config::load(|k| (k == "PINGDUCK_SCAN_INTERVAL").then(|| v.to_string())).scan_every;
        assert_eq!(every("5"), Duration::from_secs(60), "no faster than a minute");
        assert_eq!(every("9999999"), Duration::from_secs(86400));
        assert_eq!(every("soon"), DEFAULT_SCAN_EVERY);
    }

    #[test]
    fn bad_port_falls_back() {
        let c = Config::load(|k| (k == "PINGDUCK_HTTP_PORT").then(|| "99999".to_string()));
        assert_eq!(c.http_port, 44480);
    }
}
