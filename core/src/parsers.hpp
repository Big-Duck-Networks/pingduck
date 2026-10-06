// Pure parsers for untrusted input (LAN packets, HTTP bodies, system files).
//
// Kept free of sockets and global state so unit tests and fuzz targets
// (core/tests, core/fuzz) can drive them directly. Not part of the public ABI.
#pragma once

#include <cstdint>
#include <istream>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "platform.hpp"

namespace pd {

// ---- DNS / NetBIOS (dns.cpp) ---------------------------------------------

namespace dns {
// Returns the PTR target answering `qname`, or "" if the message has none.
std::string find_ptr_answer(const uint8_t* buf, size_t n, const std::string& qname);
// First unique workstation (<00>) name in a NetBIOS node status response.
std::string parse_nbstat(const uint8_t* buf, size_t n);
}  // namespace dns

// ---- mDNS / DNS-SD (mdns.cpp) ----------------------------------------------

namespace mdns {

// Raw facts as announced. Responders (and mDNS/sleep proxies) may announce
// records for *other* hosts, so nothing is attributed to an IP until the end,
// when instance -> SRV host -> A record chains are resolved.
struct Instance {
    std::string type;    // "_airplay._tcp"
    std::string host;    // SRV target, "foo.local"
    std::string src_ip;  // who told us; fallback when no SRV/A is known
    std::map<std::string, std::string> txt;
};

struct Collector {
    std::map<std::string, Instance> instances;                 // full instance name -> facts
    std::map<std::string, std::vector<std::string>> host_ips;  // "foo.local" -> A records
    std::map<std::string, std::string> host_src;               // "foo.local" -> announcing ip
    std::map<std::string, std::string> rdns;                   // ip -> "foo.local"
    std::set<std::string> new_types;                           // to follow up with PTR queries

    // Feeds one received datagram. Malformed input is ignored from the first
    // bad record onward.
    void parse(const uint8_t* buf, size_t n, const std::string& src_ip);

    // One merged device per IP, link-local and empty records dropped.
    std::vector<pd_device> devices() const;
};

}  // namespace mdns

// ---- SSDP / UPnP (ssdp.cpp) ------------------------------------------------

namespace ssdp {

struct Responder {
    std::string location;
    std::string server;
    std::vector<std::string> types;  // short device/service types from ST
};

// Lower-cased header name -> trimmed value; the start line is skipped.
std::map<std::string, std::string> parse_headers(const std::string& msg);
// "urn:schemas-upnp-org:device:MediaRenderer:1" -> "upnp:MediaRenderer"
std::string short_type(const std::string& st);
// First <tag>value</tag>, tolerating namespace prefixes like <dev:tag>.
std::string xml_tag(const std::string& xml, const std::string& tag);
// Folds an M-SEARCH reply or NOTIFY into `r`. Returns false if `msg` is neither.
bool note_response(const std::string& msg, Responder& r);
// Fills name/vendor/model/services of `d` from a device description document.
void apply_description(const std::string& xml, const Responder& r, pd_device& d);

}  // namespace ssdp

// ---- ICMP / ARP (icmp.cpp, arp.cpp) ---------------------------------------

// Locates an ICMP echo reply in `buf`, skipping an IPv4 header when present
// (raw sockets and Apple's DGRAM ICMP sockets include it). Fills id and seq.
bool parse_echo_reply(const uint8_t* buf, size_t n, uint16_t* id, uint16_t* seq);

// Ethernet ARP who-has frame from `src_mac`/`src_ip` for `target_ip`.
void build_arp_request(uint8_t frame[42], const uint8_t src_mac[6], uint32_t src_ip, uint32_t target_ip);
// Parses an Ethernet ARP reply. Fills the sender's IP (host order) and MAC.
bool parse_arp_reply(const uint8_t* frame, size_t n, uint32_t* ip, uint8_t mac[6]);

// MAC for `ip` from /proc/net/arp contents, or "".
std::string proc_arp_lookup(std::istream& in, const std::string& ip);
// Gateway of `iface` from /proc/net/route contents, or "".
std::string proc_route_gateway(std::istream& in, const std::string& iface);

// ---- Scan merging (scan.cpp) -----------------------------------------------

// Merges per-method results into one record per IP. Not thread-safe.
class DeviceMerger {
public:
    // Returns true and stores the full merged record in `out` when `in` is a
    // new device or adds information to a known one.
    bool add(const pd_device& in, pd_device* out);
    size_t size() const { return devices_.size(); }

private:
    std::map<std::string, pd_device> devices_;
};

// ---- OUI registry (oui.cpp) ------------------------------------------------

// Splits one CSV line honouring double quotes ("" escapes), stopping after
// `max_fields` fields.
std::vector<std::string> split_csv(const std::string& line, size_t max_fields = SIZE_MAX);

}  // namespace pd
