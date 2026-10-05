#include "dns.hpp"

#include <algorithm>
#include <fstream>
#include <random>
#include <sstream>

#include "net_util.hpp"

namespace pd::dns {

void put_name(std::vector<uint8_t>& out, const std::string& name) {
    size_t start = 0;
    while (start < name.size()) {
        size_t dot = name.find('.', start);
        if (dot == std::string::npos) dot = name.size();
        size_t n = std::min<size_t>(dot - start, 63);
        out.push_back(static_cast<uint8_t>(n));
        out.insert(out.end(), name.begin() + static_cast<long>(start), name.begin() + static_cast<long>(start + n));
        start = dot + 1;
    }
    out.push_back(0);
}

std::vector<uint8_t> build_query(const std::vector<std::string>& names, uint16_t type, uint16_t id,
                                 bool unicast_response, bool recursion) {
    std::vector<uint8_t> q = {static_cast<uint8_t>(id >> 8), static_cast<uint8_t>(id),
                              static_cast<uint8_t>(recursion ? 0x01 : 0x00), 0,
                              0, static_cast<uint8_t>(names.size()), 0, 0, 0, 0, 0, 0};
    for (auto& n : names) {
        put_name(q, n);
        q.insert(q.end(), {static_cast<uint8_t>(type >> 8), static_cast<uint8_t>(type),
                           static_cast<uint8_t>(unicast_response ? 0x80 : 0x00), 0x01});
    }
    return q;
}

bool Reader::u16(uint16_t& v) {
    if (off + 2 > len) return false;
    v = static_cast<uint16_t>(msg[off] << 8 | msg[off + 1]);
    off += 2;
    return true;
}

bool Reader::name_at(size_t& pos, std::string& out) const {
    out.clear();
    size_t p = pos;
    bool jumped = false;
    for (int hops = 0; hops < 64; ++hops) {
        if (p >= len) return false;
        uint8_t b = msg[p];
        if (b == 0) {
            if (!jumped) pos = p + 1;
            return true;
        }
        if ((b & 0xC0) == 0xC0) {
            if (p + 1 >= len) return false;
            size_t target = static_cast<size_t>((b & 0x3F) << 8 | msg[p + 1]);
            if (!jumped) pos = p + 2;
            jumped = true;
            p = target;
            continue;
        }
        if (p + 1 + b > len) return false;
        if (!out.empty()) out += '.';
        out.append(reinterpret_cast<const char*>(msg + p + 1), b);
        p += 1 + b;
    }
    return false;
}

std::string ptr_name(const std::string& ip) {
    uint32_t a = 0;
    if (!parse_ipv4(ip.c_str(), &a)) return {};
    return std::to_string(a & 0xFF) + "." + std::to_string((a >> 8) & 0xFF) + "." +
           std::to_string((a >> 16) & 0xFF) + "." + std::to_string(a >> 24) + ".in-addr.arpa";
}

std::string lan_dns_server() {
    pd_interface f{};
    if (pd_default_interface(&f) != PD_OK) return {};
    if (f.dns[0]) return f.dns;
#if defined(__linux__) && !defined(__ANDROID__)
    std::ifstream rc("/etc/resolv.conf");
    std::string line;
    while (std::getline(rc, line)) {
        std::istringstream ss(line);
        std::string key, value;
        uint32_t tmp;
        if (ss >> key >> value && key == "nameserver" && parse_ipv4(value.c_str(), &tmp)) return value;
    }
#endif
    return f.gateway;
}

namespace {

// Returns the PTR target answering `qname`, or "" if the message has none.
std::string find_ptr_answer(const uint8_t* buf, size_t n, const std::string& qname) {
    Reader r{buf, n};
    uint16_t id, flags, qd, an, ns, ar;
    if (!r.u16(id) || !r.u16(flags) || !r.u16(qd) || !r.u16(an) || !r.u16(ns) || !r.u16(ar)) return {};
    if (!(flags & 0x8000)) return {};
    for (int i = 0; i < qd; ++i) {
        std::string q;
        uint16_t t, c;
        if (!r.name(q) || !r.u16(t) || !r.u16(c)) return {};
    }
    for (int i = 0; i < an; ++i) {
        std::string owner;
        uint16_t type, cls, ttl_hi, ttl_lo, rdlen;
        if (!r.name(owner) || !r.u16(type) || !r.u16(cls) || !r.u16(ttl_hi) || !r.u16(ttl_lo) || !r.u16(rdlen))
            return {};
        size_t rd = r.off;
        r.off += rdlen;
        if (r.off > n) return {};
        std::string target;
        if (type == kTypePTR && owner == qname && r.name_at(rd, target)) return target;
    }
    return {};
}

// NetBIOS node status request for the wildcard name "*" (RFC 1002 §4.2.17).
std::vector<uint8_t> nbstat_query(uint16_t id) {
    std::vector<uint8_t> q = {static_cast<uint8_t>(id >> 8), static_cast<uint8_t>(id), 0, 0, 0, 1, 0, 0, 0, 0, 0, 0,
                              0x20, 'C', 'K'};
    q.insert(q.end(), 30, 'A');  // 15 NUL bytes, first-level encoded
    q.insert(q.end(), {0x00, 0x00, 0x21 /* NBSTAT */, 0x00, 0x01});
    return q;
}

// First unique workstation (<00>) name in a node status response.
std::string parse_nbstat(const uint8_t* buf, size_t n) {
    Reader r{buf, n};
    uint16_t id, flags, qd, an, ns, ar;
    if (!r.u16(id) || !r.u16(flags) || !r.u16(qd) || !r.u16(an) || !r.u16(ns) || !r.u16(ar) || an == 0) return {};
    std::string owner;
    uint16_t type, cls, ttl_hi, ttl_lo, rdlen;
    if (!r.name(owner) || !r.u16(type) || !r.u16(cls) || !r.u16(ttl_hi) || !r.u16(ttl_lo) || !r.u16(rdlen)) return {};
    if (type != 0x21 || r.off >= n) return {};
    size_t count = buf[r.off++];
    for (size_t i = 0; i < count && r.off + 18 <= n; ++i, r.off += 18) {
        const uint8_t* e = buf + r.off;
        bool group = (e[16] & 0x80) != 0;
        if (e[15] != 0x00 || group) continue;
        std::string name(reinterpret_cast<const char*>(e), 15);
        name.erase(name.find_last_not_of(' ') + 1);
        if (!name.empty()) return name;
    }
    return {};
}

bool is_own_address(const std::string& ip) {
    pd_interface list[32];
    int n = pd_list_interfaces(list, 32);
    for (int i = 0; i < n; ++i)
        if (ip == list[i].ip) return true;
    return false;
}

}  // namespace

bool reverse_lookup(const std::string& ip, const std::string& dns_server, int timeout_ms, std::string& out) {
    std::string qname = ptr_name(ip);
    if (qname.empty()) return false;

    if (is_own_address(ip)) {
        char host[256] = {0};
        // Android reports "localhost"; that is worse than no name at all.
        if (gethostname(host, sizeof(host) - 1) == 0 && host[0] && std::strcmp(host, "localhost") != 0) {
            out = host;
            return true;
        }
    }

    Socket s(open_udp_socket(0, false));
    if (!s.valid()) return false;

    static thread_local std::mt19937 rng{std::random_device{}()};
    uint16_t id = static_cast<uint16_t>(rng());

    auto send_to = [&](const std::string& host, uint16_t port, const std::vector<uint8_t>& q) {
        sockaddr_in a{};
        a.sin_family = AF_INET;
        a.sin_port = htons(port);
        if (inet_pton(AF_INET, host.c_str(), &a.sin_addr) != 1) return false;
        return sendto(s.fd, reinterpret_cast<const char*>(q.data()), static_cast<int>(q.size()), 0,
                      reinterpret_cast<sockaddr*>(&a), sizeof(a)) >= 0;
    };

    bool dns_pending = !dns_server.empty() && send_to(dns_server, 53, build_query({qname}, kTypePTR, id, false, true));
    bool mdns_pending = send_to(ip, 5353, build_query({qname}, kTypePTR, 0));
    bool nbns_pending = send_to(ip, 137, nbstat_query(id));

    int64_t deadline = now_ms() + timeout_ms;
    uint8_t buf[1500];
    while (dns_pending || mdns_pending || nbns_pending) {
        int remaining = static_cast<int>(deadline - now_ms());
        if (remaining <= 0 || wait_readable(s.fd, remaining) <= 0) break;
        sockaddr_in from{};
        socklen_t fl = sizeof(from);
        int n = static_cast<int>(recvfrom(s.fd, reinterpret_cast<char*>(buf), sizeof(buf), 0,
                                          reinterpret_cast<sockaddr*>(&from), &fl));
        if (n < 12) continue;  // includes ICMP port-unreachable surfacing as an error

        uint16_t port = ntohs(from.sin_port);
        if (port == 137) {
            std::string name = parse_nbstat(buf, static_cast<size_t>(n));
            if (!name.empty()) return out = name, true;
            nbns_pending = false;
            continue;
        }
        std::string target = find_ptr_answer(buf, static_cast<size_t>(n), qname);
        if (!target.empty()) {
            if (target.size() > 6 && target.compare(target.size() - 6, 6, ".local") == 0) target.resize(target.size() - 6);
            out = target;
            return true;
        }
        // A negative answer ends that leg.
        if (port == 53) dns_pending = false;
        else mdns_pending = false;
    }
    return false;
}

}  // namespace pd::dns
