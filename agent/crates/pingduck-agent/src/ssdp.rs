//! Advertises the agent over SSDP so the app's normal UPnP discovery finds
//! it: answers M-SEARCH, and sends NOTIFY alive/byebye on the multicast group.

use std::collections::HashMap;
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, UdpSocket};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use socket2::{Domain, Protocol, Socket, Type};

use crate::agent::DEVICE_TYPE;

const GROUP: Ipv4Addr = Ipv4Addr::new(239, 255, 255, 250);
/// Never an amplifier for spoofed searches.
const MAX_REPLIES_PER_SECOND: f64 = 20.0;
const NOTIFY_EVERY: Duration = Duration::from_secs(15 * 60);

/// Lower-cased header name to trimmed value; the start line is skipped
/// (same rules as the core's `pd::ssdp::parse_headers`).
pub fn parse_headers(msg: &str) -> HashMap<String, String> {
    msg.split("\r\n")
        .skip(1)
        .filter_map(|line| line.split_once(':'))
        .map(|(k, v)| (k.trim().to_ascii_lowercase(), v.trim().to_string()))
        .collect()
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct SearchMatch {
    /// STs to answer; empty if the search isn't for us.
    pub targets: Vec<String>,
    /// Seconds the searcher waits (clamped 1..5).
    pub mx: u64,
}

fn all_targets(instance_id: &str) -> Vec<String> {
    vec!["upnp:rootdevice".into(), format!("uuid:{instance_id}"), DEVICE_TYPE.into()]
}

/// Which of our search targets an M-SEARCH asks for.
pub fn match_msearch(msg: &str, instance_id: &str) -> SearchMatch {
    let mut m = SearchMatch { targets: vec![], mx: 1 };
    if !msg.starts_with("M-SEARCH * HTTP/1.1") {
        return m;
    }
    let h = parse_headers(msg);
    if !h.get("man").is_some_and(|v| v.contains("ssdp:discover")) {
        return m;
    }
    m.mx = h.get("mx").and_then(|v| v.parse::<u64>().ok()).unwrap_or(1).clamp(1, 5);
    let st = h.get("st").map(String::as_str).unwrap_or("");
    let uuid = format!("uuid:{instance_id}");
    if st == "ssdp:all" {
        m.targets = all_targets(instance_id);
    } else if st == "upnp:rootdevice" || st == DEVICE_TYPE || st == uuid {
        m.targets = vec![st.to_string()];
    }
    m
}

#[derive(Debug, Clone)]
pub struct Advert {
    pub instance_id: String,
    /// http://<lan ip>:<port>/description.xml
    pub location: String,
    pub version: String,
    pub boot_id: u64,
}

impl Advert {
    fn usn(&self, st: &str) -> String {
        let uuid = format!("uuid:{}", self.instance_id);
        if st == uuid { uuid } else { format!("{uuid}::{st}") }
    }
}

pub fn format_search_reply(a: &Advert, st: &str) -> String {
    format!(
        "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nEXT:\r\nLOCATION: {}\r\n\
         SERVER: {} UPnP/1.1 PingDuckAgent/{}\r\nST: {st}\r\nUSN: {}\r\nBOOTID.UPNP.ORG: {}\r\n\r\n",
        a.location,
        if cfg!(windows) { "Windows/10" } else { "Linux/1" },
        a.version,
        a.usn(st),
        a.boot_id
    )
}

pub fn format_notify(a: &Advert, nt: &str, alive: bool) -> String {
    let mut m = String::from("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n");
    if alive {
        m += &format!("CACHE-CONTROL: max-age=1800\r\nLOCATION: {}\r\nSERVER: UPnP/1.1 PingDuckAgent/{}\r\n", a.location, a.version);
    }
    m += &format!(
        "NT: {nt}\r\nNTS: {}\r\nUSN: {}\r\nBOOTID.UPNP.ORG: {}\r\n\r\n",
        if alive { "ssdp:alive" } else { "ssdp:byebye" },
        a.usn(nt),
        a.boot_id
    );
    m
}

fn lan_ip() -> Option<Ipv4Addr> {
    pingduck_core_sys::default_interface().map(|i| i.ip)
}

fn location(ip: Option<Ipv4Addr>, port: u16) -> String {
    ip.map(|ip| format!("http://{ip}:{port}/description.xml")).unwrap_or_default()
}

fn open_socket(iface: Ipv4Addr) -> std::io::Result<UdpSocket> {
    // Other UPnP daemons (minidlna, the Windows SSDP Discovery service) may
    // hold 1900; address/port reuse lets us share it.
    let s = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    s.set_reuse_address(true)?;
    #[cfg(all(unix, not(target_os = "solaris")))]
    s.set_reuse_port(true)?;
    s.bind(&SocketAddr::from(([0, 0, 0, 0], 1900)).into())?;
    s.join_multicast_v4(&GROUP, &iface)?;
    s.set_multicast_if_v4(&iface)?;
    s.set_multicast_ttl_v4(4)?;
    Ok(s.into())
}

/// Runs until `stop` is set, re-reading the LAN address as it goes so a DHCP
/// change doesn't strand the advert.
pub fn run(instance_id: &str, version: &str, http_port: u16, stop: &AtomicBool) -> std::io::Result<()> {
    let iface = lan_ip().ok_or_else(|| std::io::Error::other("no LAN interface"))?;
    let sock = open_socket(iface)?;
    let group = SocketAddr::V4(SocketAddrV4::new(GROUP, 1900));
    let boot_id = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(1);
    let mut ad = Advert { instance_id: instance_id.into(), location: location(Some(iface), http_port), version: version.into(), boot_id };

    let notify_all = |ad: &Advert, alive: bool| {
        for nt in all_targets(instance_id) {
            let _ = sock.send_to(format_notify(ad, &nt, alive).as_bytes(), group);
        }
    };

    let mut pending: Vec<(Instant, SocketAddr, String)> = Vec::new();
    let mut tokens = MAX_REPLIES_PER_SECOND;
    let mut last_refill = Instant::now();
    let mut next_notify = Instant::now();
    let mut buf = [0u8; 2049];

    while !stop.load(Ordering::Relaxed) {
        let now = Instant::now();
        if now >= next_notify {
            ad.location = location(lan_ip(), http_port);
            if !ad.location.is_empty() {
                notify_all(&ad, true);
                notify_all(&ad, true); // UDP; send twice as the spec suggests
            }
            next_notify = now + NOTIFY_EVERY;
        }

        tokens = (tokens + now.duration_since(last_refill).as_secs_f64() * MAX_REPLIES_PER_SECOND).min(MAX_REPLIES_PER_SECOND);
        last_refill = now;
        pending.retain(|(due, to, st)| {
            if *due > now {
                return true;
            }
            if tokens >= 1.0 && !ad.location.is_empty() {
                let _ = sock.send_to(format_search_reply(&ad, st).as_bytes(), to);
                tokens -= 1.0;
            }
            false
        });

        let wait = pending
            .iter()
            .map(|(due, _, _)| due.saturating_duration_since(now))
            .min()
            .unwrap_or(Duration::from_millis(500))
            .clamp(Duration::from_millis(1), Duration::from_millis(500));
        let _ = sock.set_read_timeout(Some(wait));
        let Ok((n, from)) = sock.recv_from(&mut buf) else { continue };
        if n >= buf.len() {
            continue; // oversized: not a real M-SEARCH
        }
        let m = match_msearch(&String::from_utf8_lossy(&buf[..n]), instance_id);
        if m.targets.is_empty() || pending.len() > 64 {
            continue;
        }
        // Refresh the address before answering, in case DHCP moved us.
        ad.location = location(lan_ip(), http_port);
        // Spread replies over the searcher's MX window, but within 1 s: the
        // app only listens for a few seconds.
        let delay = Duration::from_millis(rand::random_range(0..(m.mx * 1000).min(1000)));
        let due = Instant::now() + delay;
        pending.extend(m.targets.into_iter().map(|st| (due, from, st)));
    }

    if !ad.location.is_empty() {
        notify_all(&ad, false);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const ID: &str = "4b5d7f1e-0000-4000-8000-000000000001";

    fn search(st: &str, man: &str) -> String {
        format!("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: {man}\r\nMX: 3\r\nST: {st}\r\n\r\n")
    }

    #[test]
    fn answers_searches_for_us_and_nothing_else() {
        let d = "\"ssdp:discover\"";
        assert_eq!(match_msearch(&search("ssdp:all", d), ID).targets.len(), 3);
        assert_eq!(match_msearch(&search("ssdp:all", d), ID).mx, 3);
        assert_eq!(match_msearch(&search("upnp:rootdevice", d), ID).targets.len(), 1);
        assert_eq!(match_msearch(&search(DEVICE_TYPE, d), ID).targets.len(), 1);
        assert_eq!(match_msearch(&search(&format!("uuid:{ID}"), d), ID).targets.len(), 1);
        assert!(match_msearch(&search("urn:schemas-upnp-org:device:MediaRenderer:1", d), ID).targets.is_empty());
        assert!(match_msearch(&search("ssdp:all", "\"nope\""), ID).targets.is_empty());
        assert!(match_msearch("NOTIFY * HTTP/1.1\r\nNT: ssdp:all\r\n\r\n", ID).targets.is_empty());
    }

    #[test]
    fn a_reply_is_something_the_cores_client_accepts() {
        let a = Advert { instance_id: ID.into(), location: "http://10.42.0.170:44480/description.xml".into(), version: "0.9.0".into(), boot_id: 7 };
        let (loc, types) = pingduck_core_sys::note_response(&format_search_reply(&a, DEVICE_TYPE)).expect("accepted");
        assert_eq!(loc, a.location);
        assert!(types.contains(&"upnp:PingDuckAgent".to_string()), "{types:?}");
        let h = parse_headers(&format_notify(&a, "upnp:rootdevice", true));
        assert_eq!(h["nts"], "ssdp:alive");
        assert_eq!(h["usn"], format!("uuid:{ID}::upnp:rootdevice"));
        assert_eq!(parse_headers(&format_notify(&a, &format!("uuid:{ID}"), false))["usn"], format!("uuid:{ID}"));
    }
}
