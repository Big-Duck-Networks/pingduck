// Lifecycle, shared helpers, and small diagnostics (WoL, port scan, rDNS).
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <mutex>
#include <new>
#include <thread>
#include <vector>

#include "dns.hpp"
#include "net_util.hpp"
#include "platform.hpp"

#ifndef PINGDUCK_VERSION
#define PINGDUCK_VERSION "0.0.0-dev"
#endif

namespace pd {

std::atomic<uint32_t> g_cancel_gen{0};

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

bool parse_ipv4(const char* ip, uint32_t* out) {
    if (!ip) return false;
    in_addr a{};
    if (inet_pton(AF_INET, ip, &a) != 1) return false;
    *out = ntohl(a.s_addr);
    return true;
}

std::string ipv4_to_string(uint32_t host_order) {
    in_addr a{};
    a.s_addr = htonl(host_order);
    char buf[INET_ADDRSTRLEN] = {0};
    inet_ntop(AF_INET, &a, buf, sizeof(buf));
    return buf;
}

bool parse_cidr(const char* cidr, uint32_t* network, uint8_t* prefix) {
    if (!cidr) return false;
    std::string s(cidr);
    size_t slash = s.find('/');
    std::string ip = s.substr(0, slash);
    int p = 32;
    if (slash != std::string::npos) {
        std::string bits = s.substr(slash + 1);
        if (bits.empty() || bits.size() > 2 || bits.find_first_not_of("0123456789") != std::string::npos) return false;
        p = std::atoi(bits.c_str());
    }
    if (p > 32) return false;
    uint32_t addr;
    if (!parse_ipv4(ip.c_str(), &addr)) return false;
    uint32_t mask = p == 0 ? 0 : 0xFFFFFFFFu << (32 - p);
    *network = addr & mask;
    *prefix = static_cast<uint8_t>(p);
    return true;
}

bool parse_mac(const char* mac, uint8_t out[6]) {
    if (!mac) return false;
    int n = 0;
    for (const char* p = mac; *p; ++p) {
        char c = *p;
        int v;
        if (c >= '0' && c <= '9') v = c - '0';
        else if (c >= 'a' && c <= 'f') v = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') v = c - 'A' + 10;
        else if (c == ':' || c == '-' || c == '.') continue;
        else return false;
        if (n == 12) return false;  // more than six bytes of hex
        if (n % 2 == 0) out[n / 2] = static_cast<uint8_t>(v << 4);
        else out[n / 2] |= static_cast<uint8_t>(v);
        ++n;
    }
    return n == 12;
}

std::string mac_to_string(const uint8_t m[6]) {
    char buf[PD_MAC_LEN];
    std::snprintf(buf, sizeof(buf), "%02x:%02x:%02x:%02x:%02x:%02x", m[0], m[1], m[2], m[3], m[4], m[5]);
    return buf;
}

void append_csv(char* dst, size_t cap, const std::string& item) {
    if (item.empty()) return;
    std::string cur(dst);
    size_t start = 0;
    while (start <= cur.size()) {
        size_t end = cur.find(',', start);
        if (end == std::string::npos) end = cur.size();
        if (cur.compare(start, end - start, item) == 0 && end - start == item.size()) return;
        start = end + 1;
    }
    std::string next = cur.empty() ? item : cur + "," + item;
    if (next.size() < cap) copy_str(dst, cap, next);
}

pd_device make_device(const std::string& ip) {
    pd_device d;
    std::memset(&d, 0, sizeof(d));
    copy_str(d.ip, sizeof(d.ip), ip);
    d.rtt_ms = -1;
    return d;
}

}  // namespace pd

using namespace pd;

extern "C" {

const char* pd_version(void) { return PINGDUCK_VERSION; }

int pd_init(void) {
#if defined(_WIN32)
    static std::once_flag once;
    static int result = PD_OK;
    std::call_once(once, [] {
        WSADATA wsa;
        if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) result = PD_ERR_SOCKET;
    });
    return result;
#else
    return PD_OK;
#endif
}

void pd_shutdown(void) {
    // Winsock stays initialised for the process lifetime; WSACleanup while
    // another thread (e.g. a Dart isolate) still scans would break it.
}

void pd_cancel(void) { ++g_cancel_gen; }

void pd_forward_copy(const pd_device* dev, void* owned_cb) {
    if (!dev || !owned_cb) return;
    auto* copy = new (std::nothrow) pd_device(*dev);
    if (copy) reinterpret_cast<pd_device_owned_cb>(owned_cb)(copy);
}

void pd_device_free(pd_device* dev) { delete dev; }

const char* pd_strerror(int code) {
    switch (code) {
        case PD_OK: return "ok";
        case PD_ERR_INVALID_ARG: return "invalid argument";
        case PD_ERR_SOCKET: return "socket error";
        case PD_ERR_UNSUPPORTED: return "not supported on this build/platform";
        case PD_ERR_PERMISSION: return "permission denied (needs root / CAP_NET_RAW)";
        case PD_ERR_NOT_FOUND: return "not found";
        case PD_ERR_TIMEOUT: return "timed out";
        case PD_ERR_CANCELLED: return "cancelled";
        default: return "unknown error";
    }
}

int pd_reverse_dns(const char* ip, char* out, int out_len) {
    uint32_t tmp;
    if (!parse_ipv4(ip, &tmp) || !out || out_len <= 0) return PD_ERR_INVALID_ARG;
    pd_init();
    std::string name;
    if (!dns::reverse_lookup(ip, dns::lan_dns_server(), 1500, name)) return PD_ERR_NOT_FOUND;
    copy_str(out, static_cast<size_t>(out_len), name);
    return PD_OK;
}

int pd_wake_on_lan(const char* mac, const char* broadcast) {
    uint8_t m[6];
    if (!parse_mac(mac, m)) return PD_ERR_INVALID_ARG;
    pd_init();

    uint8_t packet[102];
    std::memset(packet, 0xFF, 6);
    for (int i = 0; i < 16; ++i) std::memcpy(packet + 6 + i * 6, m, 6);

    Socket s(socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP));
    if (!s.valid()) return PD_ERR_SOCKET;
    int yes = 1;
    setsockopt(s.fd, SOL_SOCKET, SO_BROADCAST, reinterpret_cast<const char*>(&yes), sizeof(yes));

    sockaddr_in dst{};
    dst.sin_family = AF_INET;
    if (inet_pton(AF_INET, broadcast ? broadcast : "255.255.255.255", &dst.sin_addr) != 1)
        return PD_ERR_INVALID_ARG;

    // Ports 9 (discard) and 7 (echo) are both used by WoL implementations.
    for (uint16_t port : {uint16_t{9}, uint16_t{7}}) {
        dst.sin_port = htons(port);
        if (sendto(s.fd, reinterpret_cast<const char*>(packet), sizeof(packet), 0,
                   reinterpret_cast<sockaddr*>(&dst), sizeof(dst)) < 0)
            return PD_ERR_SOCKET;
    }
    return PD_OK;
}

int pd_port_scan(const char* ip, const uint16_t* ports, int count, int timeout_ms, uint8_t* open_out) {
    if (!ip || !ports || !open_out || count <= 0 || timeout_ms <= 0) return PD_ERR_INVALID_ARG;
    std::memset(open_out, 0, static_cast<size_t>(count));
    pd_init();

    sockaddr_in base{};
    base.sin_family = AF_INET;
    if (inet_pton(AF_INET, ip, &base.sin_addr) != 1) return PD_ERR_INVALID_ARG;

    CancelToken tok;
    std::atomic<int> next{0}, open{0};
    int workers = std::min(count, 32);
    std::vector<std::thread> pool;
    pool.reserve(workers);
    for (int w = 0; w < workers; ++w) {
        pool.emplace_back([&] {
            for (int i = next++; i < count && !tok.cancelled(); i = next++) {
                sockaddr_in a = base;
                a.sin_port = htons(ports[i]);
                pd_socket c = tcp_connect(a, timeout_ms);
                bool ok = c != PD_INVALID_SOCKET;
                close_socket(c);
                open_out[i] = ok ? 1 : 0;
                if (ok) ++open;
            }
        });
    }
    for (auto& t : pool) t.join();
    if (tok.cancelled()) return PD_ERR_CANCELLED;
    return open.load();
}

}  // extern "C"
