//! The monitoring loop: while paired, scan the LAN every
//! `PINGDUCK_SCAN_INTERVAL` and report each scan through agent_sync, which
//! diffs it against the stored devices and records the events.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use pingduck_core_sys::{Device, ScanError, PD_SCAN_ARP, PD_SCAN_DEFAULT};

use crate::agent::{Agent, SyncOutcome};

/// Per-method reply window, as the app's default scan.
const SCAN_TIMEOUT_MS: i32 = 3000;

pub trait Scanner: Send + Sync {
    fn scan(&self) -> Result<Vec<Device>, ScanError>;
    /// Ends a running scan early (shutdown).
    fn cancel(&self);
}

/// pingduck-core's combined scan: ICMP, mDNS, SSDP, reverse DNS, the OS
/// neighbour table and, on Linux, a raw libpcap ARP sweep.
pub struct CoreScanner {
    pub cidr: Option<String>,
    /// Shown as this host's name.
    pub host_name: String,
}

impl Scanner for CoreScanner {
    fn scan(&self) -> Result<Vec<Device>, ScanError> {
        let mut devices = pingduck_core_sys::scan(self.cidr.as_deref(), SCAN_TIMEOUT_MS, PD_SCAN_DEFAULT | PD_SCAN_ARP)?;
        if let Some(lan) = pingduck_core_sys::default_interface() {
            add_this_host(&mut devices, &lan.ip.to_string(), &lan.mac, &self.host_name);
        }
        Ok(devices)
    }

    fn cancel(&self) {
        pingduck_core_sys::cancel();
    }
}

/// The agent's own host: no ARP entry for itself, so the scan has no MAC
/// for it (or misses it). Fill it from the interface.
pub fn add_this_host(devices: &mut Vec<Device>, ip: &str, mac: &str, name: &str) {
    if mac.is_empty() {
        return;
    }
    match devices.iter_mut().find(|d| d.ip == ip) {
        Some(d) => {
            if d.mac.is_empty() {
                d.mac = mac.to_string();
            }
            if d.hostname.is_empty() {
                d.hostname = name.to_string();
            }
        }
        None => devices.push(Device { ip: ip.into(), mac: mac.into(), hostname: name.into(), rtt_ms: 0, ..Device::default() }),
    }
}

/// How long a device may go unseen before agent_sync marks it offline:
/// two missed scans, and never under the server's 10-minute default.
pub fn offline_after(every: Duration) -> Duration {
    (every * 2 + every / 2).max(Duration::from_secs(600))
}

/// What one round did; the loop logs only changes in it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Round {
    Unpaired,
    Cancelled,
    ScanFailed(String),
    Scanned { found: usize, with_mac: usize, sync: SyncOutcome },
}

pub struct Monitor {
    agent: Arc<Agent>,
    scanner: Arc<dyn Scanner>,
    every: Duration,
    last: Option<Round>,
}

impl Monitor {
    pub fn new(agent: Arc<Agent>, scanner: Arc<dyn Scanner>, every: Duration) -> Self {
        Monitor { agent, scanner, every, last: None }
    }

    /// One scan and report.
    pub fn round(&mut self) -> Round {
        if !self.agent.paired() {
            return Round::Unpaired;
        }
        let round = match self.scanner.scan() {
            Err(ScanError::Cancelled) => Round::Cancelled,
            Err(e) => Round::ScanFailed(e.to_string()),
            Ok(devices) => Round::Scanned {
                found: devices.len(),
                with_mac: devices.iter().filter(|d| !d.mac.is_empty()).count(),
                sync: self.agent.sync(&devices, offline_after(self.every)),
            },
        };
        self.report(&round);
        self.last = Some(round.clone());
        round
    }

    fn report(&self, round: &Round) {
        let same_kind = |a: &Round, b: &Round| match (a, b) {
            (Round::Scanned { sync: x, .. }, Round::Scanned { sync: y, .. }) => {
                std::mem::discriminant(x) == std::mem::discriminant(y)
            }
            _ => std::mem::discriminant(a) == std::mem::discriminant(b),
        };
        let changed = self.last.as_ref().is_none_or(|last| !same_kind(last, round));
        match round {
            Round::Scanned { found, with_mac, sync: SyncOutcome::Synced { new_devices, went_offline, .. } } => {
                if changed || *new_devices > 0 || *went_offline > 0 {
                    crate::log!(
                        "monitor: {found} devices ({with_mac} with a MAC) synced; \
                         {new_devices} new, {went_offline} went offline"
                    );
                }
            }
            Round::Scanned { sync, .. } if changed => match sync {
                SyncOutcome::SubscriptionRequired => {
                    crate::log!("monitor: the account's plan has no monitoring; scans resume after an upgrade")
                }
                SyncOutcome::Rejected => crate::log!("monitor: Supabase refused this agent's token"),
                _ => crate::log!("monitor: Supabase unreachable; will retry on the next scan"),
            },
            Round::ScanFailed(e) if changed => crate::log!("monitor: scan failed ({e}); will retry"),
            _ => {}
        }
    }

    /// Scans right away whenever the agent becomes paired, then every
    /// `every`, until `stop`.
    pub fn run(mut self, stop: &AtomicBool) {
        let mut next = Instant::now();
        let mut was_paired = false;
        while !stop.load(Ordering::Relaxed) {
            let paired = self.agent.paired();
            if paired && !was_paired {
                next = Instant::now(); // just added in the app: show devices now
            }
            was_paired = paired;
            if paired && Instant::now() >= next {
                self.round();
                next = Instant::now() + self.every;
            }
            std::thread::sleep(Duration::from_millis(500));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::agent::tests::{dev, fixture, post_pair, Fixture, IP};
    use std::sync::Mutex;

    /// Scripted scan results, one per round.
    struct FakeScanner {
        results: Mutex<Vec<Result<Vec<Device>, ScanError>>>,
        scans: Mutex<usize>,
    }

    impl FakeScanner {
        fn new(results: Vec<Result<Vec<Device>, ScanError>>) -> Arc<Self> {
            Arc::new(FakeScanner { results: Mutex::new(results), scans: Mutex::new(0) })
        }
    }

    impl Scanner for FakeScanner {
        fn scan(&self) -> Result<Vec<Device>, ScanError> {
            *self.scans.lock().unwrap() += 1;
            let mut r = self.results.lock().unwrap();
            if r.is_empty() { Ok(vec![]) } else { r.remove(0) }
        }
        fn cancel(&self) {}
    }

    fn paired() -> (Arc<Agent>, Arc<crate::agent::tests::FakeSupabase>, tempfile::TempDir) {
        let f = fixture();
        post_pair(&f, r#"{"code":"ABCD2345"}"#, IP);
        let Fixture { agent, supabase, _dir, .. } = f;
        (Arc::new(agent), supabase, _dir)
    }

    #[test]
    fn no_scans_while_unpaired() {
        let Fixture { agent, supabase, _dir, .. } = fixture();
        let scanner = FakeScanner::new(vec![]);
        let mut m = Monitor::new(Arc::new(agent), scanner.clone(), DEFAULT_EVERY);
        assert_eq!(m.round(), Round::Unpaired);
        assert_eq!(*scanner.scans.lock().unwrap(), 0);
        assert!(supabase.calls().is_empty());
    }

    const DEFAULT_EVERY: Duration = Duration::from_secs(300);

    #[test]
    fn a_round_scans_then_syncs() {
        let (agent, supabase, _dir) = paired();
        supabase.answer(200, r#"{"devices":1,"new_devices":1,"went_offline":0}"#);
        let scanner = FakeScanner::new(vec![Ok(vec![dev("10.42.0.1", "b8:fb:b3:00:00:01"), dev("10.42.0.50", "")])]);
        let mut m = Monitor::new(agent, scanner, DEFAULT_EVERY);
        assert_eq!(
            m.round(),
            Round::Scanned { found: 2, with_mac: 1, sync: SyncOutcome::Synced { devices: 1, new_devices: 1, went_offline: 0 } }
        );
        let (function, body) = supabase.calls().last().cloned().unwrap();
        assert_eq!(function, "agent_sync");
        assert!(body.contains("b8:fb:b3:00:00:01"));
        assert!(body.contains("\"750 seconds\""), "2.5 scans at 5 minutes: {body}");
    }

    #[test]
    fn a_failed_scan_reports_nothing() {
        let (agent, supabase, _dir) = paired();
        let before = supabase.calls().len();
        let scanner = FakeScanner::new(vec![
            Err(ScanError::Failed { code: -2, message: "socket error".into() }),
            Err(ScanError::Cancelled),
        ]);
        let mut m = Monitor::new(agent, scanner, DEFAULT_EVERY);
        assert_eq!(m.round(), Round::ScanFailed("socket error (-2)".into()));
        assert_eq!(m.round(), Round::Cancelled);
        assert_eq!(supabase.calls().len(), before, "an empty or partial report would mark devices offline");
    }

    #[test]
    fn run_scans_as_soon_as_paired_and_stops() {
        let Fixture { agent, supabase, store, _dir, .. } = fixture();
        let agent = Arc::new(agent);
        let scanner = FakeScanner::new(vec![]);
        let stop = Arc::new(AtomicBool::new(false));
        let m = Monitor::new(agent.clone(), scanner.clone(), Duration::from_secs(3600));
        let t = {
            let stop = stop.clone();
            std::thread::spawn(move || m.run(&stop))
        };
        std::thread::sleep(Duration::from_millis(700));
        assert_eq!(*scanner.scans.lock().unwrap(), 0, "unpaired: idle");

        let mut s = store.get();
        s.token = crate::agent::tests::token();
        s.agent_id = "agent-1".into();
        store.set(s);
        supabase.answer(200, r#"{"devices":0,"new_devices":0,"went_offline":0}"#);
        let deadline = Instant::now() + Duration::from_secs(5);
        while *scanner.scans.lock().unwrap() == 0 && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(50));
        }
        assert_eq!(*scanner.scans.lock().unwrap(), 1, "first scan right after pairing, not an hour later");

        stop.store(true, Ordering::Relaxed);
        t.join().unwrap();
    }

    #[test]
    fn this_host_gets_its_own_mac() {
        let mut devices = vec![dev("10.42.0.193", ""), dev("10.42.0.1", "b8:fb:b3:00:00:01")];
        add_this_host(&mut devices, "10.42.0.193", "00:15:5d:01:02:03", "WEBCAP-717");
        assert_eq!(devices[0].mac, "00:15:5d:01:02:03");
        assert_eq!(devices[0].hostname, "WEBCAP-717");

        let mut missed = vec![dev("10.42.0.1", "b8:fb:b3:00:00:01")];
        add_this_host(&mut missed, "10.42.0.193", "00:15:5d:01:02:03", "WEBCAP-717");
        assert_eq!(missed.len(), 2);
        assert_eq!(missed[1].ip, "10.42.0.193");
    }

    #[test]
    fn offline_takes_a_couple_of_missed_scans() {
        assert_eq!(offline_after(Duration::from_secs(60)), Duration::from_secs(600));
        assert_eq!(offline_after(Duration::from_secs(300)), Duration::from_secs(750));
        assert_eq!(offline_after(Duration::from_secs(3600)), Duration::from_secs(9000));
    }
}

/// `cargo test -p pingduck-agent --release -- --ignored --nocapture live_scan`
/// on a machine with a LAN: what the agent would sync, without Supabase.
#[cfg(test)]
mod live {
    use super::*;

    #[test]
    #[ignore = "scans the real network"]
    fn live_scan() {
        let oui = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../core/data/oui.csv");
        pingduck_core_sys::load_oui(&oui);
        let devices = CoreScanner { cidr: None, host_name: "this-host".into() }.scan().expect("scan");
        for d in &devices {
            println!("{:<15} {:<17} {:<28} {}", d.ip, d.mac, d.vendor, d.hostname);
        }
        let entries: Vec<_> = devices.iter().filter_map(crate::agent::sync_entry).collect();
        println!("{} devices, {} would sync (with a MAC)", devices.len(), entries.len());
        assert!(!entries.is_empty(), "no MACs: the neighbour table (Windows) or libpcap (Linux) path failed");
    }
}
