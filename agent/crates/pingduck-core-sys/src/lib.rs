//! The parts of pingduck-core's C ABI (`core/include/pingduck/pingduck.h`)
//! that the agent uses, with safe wrappers. Struct layouts mirror the header.

use std::collections::BTreeMap;
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::net::Ipv4Addr;
use std::path::Path;

pub const PD_OK: c_int = 0;
pub const PD_ERR_CANCELLED: c_int = -7;
pub const PD_IP_LEN: usize = 16;
pub const PD_MAC_LEN: usize = 18;

pub const PD_SCAN_ICMP: u32 = 1 << 0;
pub const PD_SCAN_MDNS: u32 = 1 << 1;
pub const PD_SCAN_SSDP: u32 = 1 << 2;
/// libpcap raw ARP; the core skips it where unsupported (Windows).
pub const PD_SCAN_ARP: u32 = 1 << 3;
pub const PD_SCAN_DNS: u32 = 1 << 4;
pub const PD_SCAN_ARP_CACHE: u32 = 1 << 5;
pub const PD_SCAN_DEFAULT: u32 = PD_SCAN_ICMP | PD_SCAN_MDNS | PD_SCAN_SSDP | PD_SCAN_DNS | PD_SCAN_ARP_CACHE;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct PdDevice {
    pub ip: [c_char; PD_IP_LEN],
    pub mac: [c_char; PD_MAC_LEN],
    pub hostname: [c_char; 256],
    pub vendor: [c_char; 128],
    pub model: [c_char; 128],
    pub services: [c_char; 512],
    pub rtt_ms: i32,
    pub sources: u32,
}

type PdDeviceCb = extern "C" fn(dev: *const PdDevice, user: *mut c_void);

#[repr(C)]
#[derive(Clone, Copy)]
pub struct PdInterface {
    pub name: [c_char; 64],
    pub ip: [c_char; PD_IP_LEN],
    pub netmask: [c_char; PD_IP_LEN],
    pub broadcast: [c_char; PD_IP_LEN],
    pub gateway: [c_char; PD_IP_LEN],
    pub dns: [c_char; PD_IP_LEN],
    pub mac: [c_char; PD_MAC_LEN],
    pub prefix_len: u8,
}

extern "C" {
    pub fn pd_version() -> *const c_char;
    pub fn pd_default_interface(out: *mut PdInterface) -> c_int;
    pub fn pd_strerror(code: c_int) -> *const c_char;
    pub fn pd_cancel();
    pub fn pd_oui_load(csv_path: *const c_char) -> c_int;
    fn pd_scan(cidr: *const c_char, timeout_ms: c_int, flags: u32, cb: PdDeviceCb, user: *mut c_void) -> c_int;

    fn pdsys_describe(
        xml: *const c_char,
        vendor: *mut c_char,
        model: *mut c_char,
        hostname: *mut c_char,
        services: *mut c_char,
        cap: c_int,
    );
    fn pdsys_note_response(msg: *const c_char, location: *mut c_char, types: *mut c_char, cap: c_int) -> c_int;
}

fn field(buf: &[c_char]) -> String {
    // SAFETY: the core always NUL-terminates its fixed-size fields.
    let bytes: Vec<u8> = buf.iter().take_while(|&&c| c != 0).map(|&c| c as u8).collect();
    String::from_utf8_lossy(&bytes).into_owned()
}

/// The core's version string, e.g. "0.1.0".
pub fn version() -> String {
    // SAFETY: returns a static NUL-terminated string.
    unsafe { CStr::from_ptr(pd_version()) }.to_string_lossy().into_owned()
}

/// The interface the core treats as "the LAN".
#[derive(Debug, Clone)]
pub struct LanInterface {
    pub name: String,
    pub ip: Ipv4Addr,
    pub prefix_len: u8,
    pub mac: String,
}

pub fn default_interface() -> Option<LanInterface> {
    let mut out: PdInterface = unsafe { std::mem::zeroed() };
    // SAFETY: `out` is a valid, writable pd_interface.
    if unsafe { pd_default_interface(&mut out) } != PD_OK {
        return None;
    }
    Some(LanInterface {
        name: field(&out.name),
        ip: field(&out.ip).parse().ok()?,
        prefix_len: out.prefix_len,
        mac: field(&out.mac),
    })
}

/// One device as the core's merged scan reports it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Device {
    pub ip: String,
    /// "aa:bb:cc:dd:ee:ff", or empty when no method learned it.
    pub mac: String,
    pub hostname: String,
    pub vendor: String,
    pub model: String,
    /// Comma-separated, e.g. "_airplay._tcp,upnp:MediaRenderer".
    pub services: String,
    /// ICMP round trip, -1 if unknown.
    pub rtt_ms: i32,
}

impl Device {
    fn from_raw(d: &PdDevice) -> Self {
        Device {
            ip: field(&d.ip),
            mac: field(&d.mac),
            hostname: field(&d.hostname),
            vendor: field(&d.vendor),
            model: field(&d.model),
            services: field(&d.services),
            rtt_ms: d.rtt_ms,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ScanError {
    Cancelled,
    Failed { code: i32, message: String },
}

impl std::fmt::Display for ScanError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ScanError::Cancelled => f.write_str("cancelled"),
            ScanError::Failed { code, message } => write!(f, "{message} ({code})"),
        }
    }
}

fn strerror(code: c_int) -> String {
    // SAFETY: returns a static NUL-terminated string for any code.
    unsafe { CStr::from_ptr(pd_strerror(code)) }.to_string_lossy().into_owned()
}

extern "C" fn on_device(dev: *const PdDevice, user: *mut c_void) {
    // The core calls this for one scan at a time, never concurrently, and
    // `user` is the map `scan` lent it. No panic may unwind into C++.
    let _ = std::panic::catch_unwind(|| {
        // SAFETY: both pointers are valid for the duration of the call.
        let (dev, seen) = unsafe { (&*dev, &mut *(user as *mut BTreeMap<String, Device>)) };
        let d = Device::from_raw(dev);
        seen.insert(d.ip.clone(), d);
    });
}

/// Runs the core's combined scan (blocking, ~timeout plus DNS lookups) and
/// returns each device's final merged record, sorted by IP. `cidr` None
/// scans the default interface's subnet.
pub fn scan(cidr: Option<&str>, timeout_ms: i32, flags: u32) -> Result<Vec<Device>, ScanError> {
    let cidr = cidr.map(CString::new).transpose().map_err(|_| ScanError::Failed { code: -1, message: "bad cidr".into() })?;
    let mut seen: BTreeMap<String, Device> = BTreeMap::new();
    // SAFETY: `seen` outlives the call, and the callback only runs during it.
    let rc = unsafe {
        pd_scan(
            cidr.as_ref().map_or(std::ptr::null(), |c| c.as_ptr()),
            timeout_ms,
            flags,
            on_device,
            &mut seen as *mut _ as *mut c_void,
        )
    };
    match rc {
        PD_ERR_CANCELLED => Err(ScanError::Cancelled),
        rc if rc < 0 => Err(ScanError::Failed { code: rc, message: strerror(rc) }),
        _ => Ok(seen.into_values().collect()),
    }
}

/// Makes a running [scan] return early with [ScanError::Cancelled].
pub fn cancel() {
    // SAFETY: no arguments; safe from any thread.
    unsafe { pd_cancel() }
}

/// Loads the IEEE OUI registry so scans fill in vendor names. Returns the
/// number of entries, or None if the file is missing or unreadable.
pub fn load_oui(csv: &Path) -> Option<usize> {
    let path = CString::new(csv.to_string_lossy().as_bytes()).ok()?;
    // SAFETY: a valid NUL-terminated path.
    let n = unsafe { pd_oui_load(path.as_ptr()) };
    (n > 0).then_some(n as usize)
}

/// What the phone reads from a UPnP device description.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Description {
    pub vendor: String,
    pub model: String,
    pub hostname: String,
    pub services: String,
}

/// Parses `xml` with the core's own UPnP parser (what the app runs).
pub fn describe(xml: &str) -> Description {
    const CAP: usize = 512;
    let xml = CString::new(xml).unwrap_or_default();
    let mut v = [0 as c_char; CAP];
    let mut m = [0 as c_char; CAP];
    let mut h = [0 as c_char; CAP];
    let mut s = [0 as c_char; CAP];
    // SAFETY: every buffer is CAP bytes and the shim writes at most CAP.
    unsafe {
        pdsys_describe(xml.as_ptr(), v.as_mut_ptr(), m.as_mut_ptr(), h.as_mut_ptr(), s.as_mut_ptr(), CAP as c_int)
    };
    Description { vendor: field(&v), model: field(&m), hostname: field(&h), services: field(&s) }
}

/// Feeds an SSDP reply to the core's client; returns (location, types) if accepted.
pub fn note_response(msg: &str) -> Option<(String, Vec<String>)> {
    const CAP: usize = 1024;
    let msg = CString::new(msg).ok()?;
    let mut loc = [0 as c_char; CAP];
    let mut types = [0 as c_char; CAP];
    // SAFETY: both buffers are CAP bytes.
    let ok = unsafe { pdsys_note_response(msg.as_ptr(), loc.as_mut_ptr(), types.as_mut_ptr(), CAP as c_int) };
    if ok == 0 {
        return None;
    }
    let types = field(&types);
    Some((field(&loc), types.split(',').filter(|t| !t.is_empty()).map(String::from).collect()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn interface_layout_matches_the_header() {
        // 64 + 5 * 16 + 18 + 1 = 163 bytes, no padding (all char arrays).
        assert_eq!(std::mem::size_of::<PdInterface>(), 163);
    }

    #[test]
    fn device_layout_matches_the_header() {
        // 16 + 18 + 256 + 128 + 128 + 512 = 1058, padded to 1060 for the
        // int32 fields, + 4 + 4.
        assert_eq!(std::mem::size_of::<PdDevice>(), 1068);
        assert_eq!(std::mem::offset_of!(PdDevice, rtt_ms), 1060);
    }

    #[test]
    fn bad_input_is_an_error_not_a_crash() {
        assert!(matches!(scan(Some("not-a-cidr"), 100, PD_SCAN_ICMP), Err(ScanError::Failed { .. })));
        assert!(matches!(scan(None, 0, PD_SCAN_ICMP), Err(ScanError::Failed { .. })));
        assert_eq!(load_oui(Path::new("no/such/oui.csv")), None);
    }

    #[test]
    fn loads_the_bundled_oui_registry() {
        let csv = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../core/data/oui.csv");
        assert!(load_oui(&csv).is_some_and(|n| n > 10_000));
    }

    #[test]
    fn version_is_set() {
        assert!(!version().is_empty());
    }
}
