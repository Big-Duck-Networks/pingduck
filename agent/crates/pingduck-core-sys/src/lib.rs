//! The parts of pingduck-core's C ABI (`core/include/pingduck/pingduck.h`)
//! that the agent uses, with safe wrappers. Struct layouts mirror the header.

use std::ffi::{c_char, c_int, CStr, CString};
use std::net::Ipv4Addr;

pub const PD_OK: c_int = 0;
pub const PD_IP_LEN: usize = 16;
pub const PD_MAC_LEN: usize = 18;

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
    fn version_is_set() {
        assert!(!version().is_empty());
    }
}
