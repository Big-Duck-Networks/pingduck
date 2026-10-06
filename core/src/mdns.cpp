// mDNS / DNS-SD discovery (Bonjour, Zeroconf).
//
// Queries are sent from an ephemeral port, which RFC 6762 §6.7 treats as a
// "legacy unicast" query: responders answer directly to us. As a best effort
// we also join 224.0.0.251:5353 to pick up multicast answers, which may fail
// if the OS mDNS responder holds the port exclusively.
#include <algorithm>
#include <cctype>
#include <map>
#include <set>
#include <vector>

#include "dns.hpp"
#include "net_util.hpp"
#include "parsers.hpp"
#include "platform.hpp"

using namespace pd;
using namespace pd::dns;
using pd::mdns::Collector;

namespace {

constexpr const char* kServicesEnum = "_services._dns-sd._udp.local";
constexpr size_t kMaxRecords = 8192;
constexpr size_t kMaxServiceTypes = 256;

// Service types that commonly identify consumer/homelab hardware.
const char* const kCommonServices[] = {
    "_http._tcp.local",          "_workstation._tcp.local", "_device-info._tcp.local",
    "_airplay._tcp.local",       "_raop._tcp.local",        "_googlecast._tcp.local",
    "_ipp._tcp.local",           "_printer._tcp.local",     "_pdl-datastream._tcp.local",
    "_smb._tcp.local",           "_afpovertcp._tcp.local",  "_ssh._tcp.local",
    "_hap._tcp.local",           "_homekit._tcp.local",     "_spotify-connect._tcp.local",
    "_companion-link._tcp.local", "_sonos._tcp.local",      "_amzn-wplay._tcp.local",
    "_hue._tcp.local",           "_matter._tcp.local",      "_esphomelib._tcp.local",
};

std::string strip_local(std::string s) {
    const std::string suffix = ".local";
    if (s.size() > suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0)
        s.resize(s.size() - suffix.size());
    return s;
}

bool ends_with(const std::string& s, const std::string& suffix) {
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

bool is_link_local(const std::string& ip) { return ip.rfind("169.254.", 0) == 0; }

// "176.52.254.169.in-addr.arpa" -> "169.254.52.176"
std::string ip_from_arpa(const std::string& name) {
    std::string labels = name.substr(0, name.size() - std::strlen(".in-addr.arpa"));
    std::string out;
    size_t end = labels.size();
    while (end > 0) {
        size_t dot = labels.rfind('.', end - 1);
        size_t start = dot == std::string::npos ? 0 : dot + 1;
        if (!out.empty()) out += '.';
        out += labels.substr(start, end - start);
        if (dot == std::string::npos) break;
        end = dot;
    }
    return out;
}

struct Record {
    std::string hostname;    // from SRV / A / reverse PTR
    std::string instance;    // DNS-SD instance label
    std::string friendly;    // TXT fn= (Chromecast / Nest user-assigned name)
    std::string model, vendor;
    std::set<std::string> services;
};

// Picks the address for `host`, preferring the announcer's own IP, and
// anything over link-local (printers often announce a 169.254.x too).
std::string resolve(const Collector& c, const std::string& host, const std::string& fallback) {
    const auto& host_ips = c.host_ips;
    auto it = host_ips.find(host);
    if (it == host_ips.end() || it->second.empty()) return fallback;
    const auto& ips = it->second;
    if (std::find(ips.begin(), ips.end(), fallback) != ips.end()) return fallback;
    for (auto& ip : ips)
        if (!is_link_local(ip)) return ip;
    return ips.front();
}

std::map<std::string, Record> build(const Collector& c) {
    std::map<std::string, Record> out;
    for (auto& [name, inst] : c.instances) {
        std::string ip = inst.host.empty() ? inst.src_ip : resolve(c, inst.host, inst.src_ip);
        if (ip.empty()) continue;
        Record& rec = out[ip];
        if (!inst.type.empty()) {
            rec.services.insert(inst.type);
            std::string suffix = "." + inst.type + ".local";
            if (rec.instance.empty() && ends_with(name, suffix))
                rec.instance = name.substr(0, name.size() - suffix.size());
        }
        if (rec.hostname.empty() && !inst.host.empty()) rec.hostname = strip_local(inst.host);
        for (auto& [k, v] : inst.txt) {
            if ((k == "md" || k == "model" || k == "am" || k == "usb_MDL" || k == "ty") && rec.model.empty())
                rec.model = v;
            else if ((k == "manufacturer" || k == "usb_MFG" || k == "mfg") && rec.vendor.empty())
                rec.vendor = v;
            else if (k == "fn" && rec.friendly.empty())
                rec.friendly = v;
        }
    }
    for (auto& [host, ips] : c.host_ips) {
        auto src = c.host_src.find(host);
        Record& rec = out[resolve(c, host, src == c.host_src.end() ? std::string() : src->second)];
        if (rec.hostname.empty()) rec.hostname = strip_local(host);
    }
    for (auto& [ip, host] : c.rdns) {
        Record& rec = out[ip];
        if (rec.hostname.empty()) rec.hostname = strip_local(host);
    }
    return out;
}

// Google Cast and some IoT devices use a UUID as their mDNS host name.
bool looks_like_uuid(const std::string& s) {
    if (s.size() < 32) return false;
    for (char c : s)
        if (!std::isxdigit(static_cast<unsigned char>(c)) && c != '-') return false;
    return true;
}

std::string display_name(const Record& rec) {
    if (!rec.friendly.empty()) return rec.friendly;
    if (!rec.hostname.empty() && !looks_like_uuid(rec.hostname)) return rec.hostname;
    if (!rec.instance.empty() && !looks_like_uuid(rec.instance)) return rec.instance;
    return rec.hostname;
}

}  // namespace

namespace pd::mdns {

void Collector::parse(const uint8_t* buf, size_t n, const std::string& src_ip) {
    Reader r{buf, n};
    uint16_t id, flags, qd, an, ns, ar;
    if (!r.u16(id) || !r.u16(flags) || !r.u16(qd) || !r.u16(an) || !r.u16(ns) || !r.u16(ar)) return;
    if (!(flags & 0x8000)) return;  // a query, not a response

    for (int i = 0; i < qd; ++i) {
        std::string q;
        uint16_t t, c;
        if (!r.name(q) || !r.u16(t) || !r.u16(c)) return;
    }

    int total = an + ns + ar;
    for (int i = 0; i < total; ++i) {
        // A busy LAN has a few hundred records; anything far beyond that is a
        // flood, and further records would only grow memory.
        if (instances.size() + host_ips.size() + rdns.size() > kMaxRecords) return;
        std::string owner;
        uint16_t type, cls, rdlen, ttl_hi, ttl_lo;
        if (!r.name(owner) || !r.u16(type) || !r.u16(cls) || !r.u16(ttl_hi) || !r.u16(ttl_lo) || !r.u16(rdlen))
            return;
        size_t rd = r.off;
        if (rd + rdlen > n) return;
        r.off += rdlen;

        switch (type) {
            case kTypeA: {
                if (rdlen != 4) break;
                uint32_t a = static_cast<uint32_t>(buf[rd] << 24 | buf[rd + 1] << 16 | buf[rd + 2] << 8 | buf[rd + 3]);
                std::string ip = ipv4_to_string(a);
                auto& ips = host_ips[owner];
                if (std::find(ips.begin(), ips.end(), ip) == ips.end()) ips.push_back(ip);
                host_src.emplace(owner, src_ip);
                break;
            }
            case kTypePTR: {
                std::string target;
                size_t p = rd;
                if (!r.name_at(p, target)) break;
                if (ends_with(owner, ".in-addr.arpa")) {
                    uint32_t tmp;
                    std::string ip = ip_from_arpa(owner);
                    if (parse_ipv4(ip.c_str(), &tmp)) rdns.emplace(ip, target);
                } else if (ends_with(owner, ".ip6.arpa")) {
                    // IPv6 reverse mappings add nothing to an IPv4 inventory.
                } else if (owner == kServicesEnum) {
                    if (new_types.size() < kMaxServiceTypes) new_types.insert(target);
                } else if (owner.find("._sub.") == std::string::npos) {
                    Instance& inst = instances[target];
                    inst.type = strip_local(owner);
                    if (inst.src_ip.empty()) inst.src_ip = src_ip;
                }
                break;
            }
            case kTypeSRV: {
                if (rdlen < 7) break;
                std::string target;
                size_t p = rd + 6;
                if (!r.name_at(p, target)) break;
                Instance& inst = instances[owner];
                inst.host = target;
                if (inst.src_ip.empty()) inst.src_ip = src_ip;
                break;
            }
            case kTypeTXT: {
                Instance& inst = instances[owner];
                if (inst.src_ip.empty()) inst.src_ip = src_ip;
                size_t p = rd, end = rd + rdlen;
                while (p < end) {
                    size_t l = buf[p++];
                    if (p + l > end) break;
                    std::string kv(reinterpret_cast<const char*>(buf + p), l);
                    p += l;
                    size_t eq = kv.find('=');
                    if (eq == std::string::npos || eq + 1 == kv.size()) continue;
                    inst.txt.emplace(kv.substr(0, eq), kv.substr(eq + 1));
                }
                break;
            }
            default:
                break;
        }
    }
}

std::vector<pd_device> Collector::devices() const {
    std::vector<pd_device> out;
    for (auto& [ip, rec] : build(*this)) {
        if (ip.empty() || is_link_local(ip)) continue;
        if (rec.hostname.empty() && rec.instance.empty() && rec.friendly.empty() && rec.services.empty()) continue;
        pd_device d = make_device(ip);
        d.sources = PD_SRC_MDNS;
        copy_str(d.hostname, sizeof(d.hostname), display_name(rec));
        copy_str(d.model, sizeof(d.model), rec.model);
        copy_str(d.vendor, sizeof(d.vendor), rec.vendor);
        for (auto& s : rec.services) append_csv(d.services, sizeof(d.services), s);
        out.push_back(d);
    }
    return out;
}

}  // namespace pd::mdns

extern "C" int pd_mdns_discover(int timeout_ms, pd_device_cb cb, void* user) {
    if (timeout_ms <= 0) return PD_ERR_INVALID_ARG;
    pd_init();
    CancelToken tok;

    Socket uni(open_udp_socket(0, false));
    if (!uni.valid()) return PD_ERR_SOCKET;
    set_multicast_defaults(uni.fd);

    // Best-effort listener on the well-known port for multicast replies.
    Socket multi(open_udp_socket(5353, true));
    if (multi.valid() && !join_multicast(multi.fd, "224.0.0.251")) close_socket(multi.fd), multi.fd = PD_INVALID_SOCKET;

    sockaddr_in group{};
    group.sin_family = AF_INET;
    group.sin_port = htons(5353);
    inet_pton(AF_INET, "224.0.0.251", &group.sin_addr);

    std::vector<std::string> initial = {kServicesEnum};
    for (auto* s : kCommonServices) initial.emplace_back(s);
    auto send_query = [&](const std::vector<std::string>& names) {
        // Keep packets well under the 1500-byte MTU.
        for (size_t i = 0; i < names.size(); i += 12) {
            std::vector<std::string> chunk(names.begin() + static_cast<long>(i),
                                           names.begin() + static_cast<long>(std::min(i + 12, names.size())));
            auto q = build_query(chunk, kTypePTR, 0, /*unicast_response=*/true);
            sendto(uni.fd, reinterpret_cast<const char*>(q.data()), static_cast<int>(q.size()), 0,
                   reinterpret_cast<sockaddr*>(&group), sizeof(group));
        }
    };

    Collector col;
    std::set<std::string> queried(initial.begin(), initial.end());
    send_query(initial);

    int64_t start = now_ms();
    bool resent = false;
    uint8_t buf[9000];
    for (;;) {
        if (tok.cancelled()) return PD_ERR_CANCELLED;
        int64_t elapsed = now_ms() - start;
        if (elapsed >= timeout_ms) break;
        if (!resent && elapsed >= timeout_ms / 3) {  // UDP is lossy; ask twice
            send_query(initial);
            resent = true;
        }

        fd_set rf;
        FD_ZERO(&rf);
        FD_SET(uni.fd, &rf);
        pd_socket maxfd = uni.fd;
        if (multi.valid()) {
            FD_SET(multi.fd, &rf);
            if (multi.fd > maxfd) maxfd = multi.fd;
        }
        timeval tv{0, 100 * 1000};
        if (select(static_cast<int>(maxfd) + 1, &rf, nullptr, nullptr, &tv) <= 0) continue;

        for (pd_socket fd : {uni.fd, multi.fd}) {
            if (fd == PD_INVALID_SOCKET || !FD_ISSET(fd, &rf)) continue;
            sockaddr_in from{};
            socklen_t fl = sizeof(from);
            int n = static_cast<int>(recvfrom(fd, reinterpret_cast<char*>(buf), sizeof(buf), 0,
                                              reinterpret_cast<sockaddr*>(&from), &fl));
            if (n <= 12) continue;
            col.parse(buf, static_cast<size_t>(n), ipv4_to_string(ntohl(from.sin_addr.s_addr)));
        }

        // Follow up on service types we learned about from the enumeration.
        std::vector<std::string> follow;
        for (auto& t : col.new_types)
            if (queried.size() < kMaxServiceTypes && queried.insert(t).second) follow.push_back(t);
        col.new_types.clear();
        if (!follow.empty()) send_query(follow);
    }

    int count = 0;
    for (auto& d : col.devices()) {
        ++count;
        if (cb) cb(&d, user);
    }
    return count;
}
