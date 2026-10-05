// Minimal DNS wire-format helpers shared by mDNS discovery and reverse lookups.
#pragma once

#include <string>
#include <vector>

#include "platform.hpp"

namespace pd::dns {

constexpr uint16_t kTypeA = 1, kTypePTR = 12, kTypeTXT = 16, kTypeSRV = 33;

void put_name(std::vector<uint8_t>& out, const std::string& name);

// One question per name, all of `type`, class IN. `unicast_response` sets the
// mDNS QU bit; `recursion` sets RD for queries to a regular DNS server.
std::vector<uint8_t> build_query(const std::vector<std::string>& names, uint16_t type, uint16_t id = 0,
                                 bool unicast_response = false, bool recursion = false);

struct Reader {
    const uint8_t* msg;
    size_t len;
    size_t off = 0;

    bool u16(uint16_t& v);
    // Reads a (possibly compressed) name at `pos`, advancing `pos` past the
    // in-place portion only.
    bool name_at(size_t& pos, std::string& out) const;
    bool name(std::string& out) { return name_at(off, out); }
};

// "10.0.0.5" -> "5.0.0.10.in-addr.arpa"
std::string ptr_name(const std::string& ip);

// The DNS resolver to use for the LAN: the default interface's configured
// server, falling back to its gateway (home routers run a DNS forwarder).
std::string lan_dns_server();

// PTR lookup with a hard deadline. Queries `dns_server` (if non-empty) and, via
// unicast mDNS and NetBIOS, the host itself; the first answer wins. Unlike getnameinfo
// this never stalls on NetBIOS/LLMNR fallbacks.
bool reverse_lookup(const std::string& ip, const std::string& dns_server, int timeout_ms, std::string& out);

}  // namespace pd::dns
