// ICMP echo (ping), concurrent subnet sweep, and OS ARP-cache lookup.
//
// Windows: IcmpSendEcho (no admin needed).
// Linux/Android/Apple: unprivileged SOCK_DGRAM ICMP "ping sockets" first,
// falling back to SOCK_RAW when running as root (agent mode).
#include <algorithm>
#include <fstream>
#include <mutex>
#include <sstream>
#include <thread>
#include <vector>

#include "dns.hpp"
#include "platform.hpp"

#if defined(_WIN32)
#  include <iphlpapi.h>
#  include <icmpapi.h>
#endif

using namespace pd;

namespace {

#if !defined(_WIN32)

uint16_t checksum(const uint8_t* data, size_t len) {
    uint32_t sum = 0;
    for (size_t i = 0; i + 1 < len; i += 2) sum += static_cast<uint32_t>(data[i] << 8 | data[i + 1]);
    if (len & 1) sum += static_cast<uint32_t>(data[len - 1] << 8);
    while (sum >> 16) sum = (sum & 0xFFFF) + (sum >> 16);
    return static_cast<uint16_t>(~sum);
}

std::atomic<uint16_t> g_seq{1};

int ping_posix(uint32_t target, int timeout_ms) {
    bool raw = false;
    pd_socket fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (fd == PD_INVALID_SOCKET) {
        fd = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
        raw = true;
    }
    if (fd == PD_INVALID_SOCKET) return (errno == EPERM || errno == EACCES) ? PD_ERR_PERMISSION : PD_ERR_SOCKET;
    Socket s(fd);

    sockaddr_in dst{};
    dst.sin_family = AF_INET;
    dst.sin_addr.s_addr = htonl(target);

    const uint16_t seq = g_seq++;
    const uint16_t id = static_cast<uint16_t>(getpid() ^ (seq << 3));
    uint8_t pkt[32] = {0};
    pkt[0] = 8;  // echo request
    pkt[4] = static_cast<uint8_t>(id >> 8);
    pkt[5] = static_cast<uint8_t>(id);
    pkt[6] = static_cast<uint8_t>(seq >> 8);
    pkt[7] = static_cast<uint8_t>(seq);
    std::memcpy(pkt + 8, "pingduck-quack!!", 16);
    uint16_t cs = checksum(pkt, sizeof(pkt));
    pkt[2] = static_cast<uint8_t>(cs >> 8);
    pkt[3] = static_cast<uint8_t>(cs);

    int64_t start = now_ms();
    if (sendto(s.fd, pkt, sizeof(pkt), 0, reinterpret_cast<sockaddr*>(&dst), sizeof(dst)) < 0)
        return PD_ERR_SOCKET;

    uint8_t buf[1500];
    for (;;) {
        int remaining = static_cast<int>(timeout_ms - (now_ms() - start));
        if (remaining <= 0) return PD_ERR_TIMEOUT;
        if (wait_readable(s.fd, remaining) <= 0) return PD_ERR_TIMEOUT;

        sockaddr_in from{};
        socklen_t fl = sizeof(from);
        ssize_t n = recvfrom(s.fd, buf, sizeof(buf), 0, reinterpret_cast<sockaddr*>(&from), &fl);
        if (n <= 0) continue;
        if (from.sin_addr.s_addr != dst.sin_addr.s_addr) continue;

        // Raw sockets (and Apple's DGRAM ICMP) deliver the IP header too.
        const uint8_t* icmp = buf;
        if ((buf[0] >> 4) == 4) {
            size_t ihl = static_cast<size_t>(buf[0] & 0x0F) * 4;
            if (static_cast<size_t>(n) < ihl + 8) continue;
            icmp = buf + ihl;
            n -= static_cast<ssize_t>(ihl);
        }
        if (n < 8 || icmp[0] != 0 /* echo reply */) continue;
        uint16_t rseq = static_cast<uint16_t>(icmp[6] << 8 | icmp[7]);
        if (rseq != seq) continue;
        // DGRAM ping sockets get their id rewritten by the kernel; only check it for raw.
        if (raw && static_cast<uint16_t>(icmp[4] << 8 | icmp[5]) != id) continue;
        return static_cast<int>(now_ms() - start);
    }
}

#endif

int ping_host(uint32_t target, int timeout_ms) {
#if defined(_WIN32)
    HANDLE h = IcmpCreateFile();
    if (h == INVALID_HANDLE_VALUE) return PD_ERR_SOCKET;
    char payload[] = "pingduck-quack!!";
    uint8_t reply[sizeof(ICMP_ECHO_REPLY) + sizeof(payload) + 8 + 64];
    DWORD n = IcmpSendEcho(h, htonl(target), payload, sizeof(payload) - 1, nullptr, reply, sizeof(reply),
                           static_cast<DWORD>(timeout_ms));
    int rc = PD_ERR_TIMEOUT;
    if (n > 0) {
        auto* r = reinterpret_cast<ICMP_ECHO_REPLY*>(reply);
        if (r->Status == IP_SUCCESS && r->Address == htonl(target)) rc = static_cast<int>(r->RoundTripTime);
    }
    IcmpCloseHandle(h);
    return rc;
#else
    return ping_posix(target, timeout_ms);
#endif
}

}  // namespace

extern "C" {

int pd_ping(const char* ip, int timeout_ms) {
    uint32_t addr;
    if (!parse_ipv4(ip, &addr) || timeout_ms <= 0) return PD_ERR_INVALID_ARG;
    pd_init();
    return ping_host(addr, timeout_ms);
}

int pd_arp_cache_lookup(const char* ip, char* mac_out) {
    uint32_t addr;
    if (!parse_ipv4(ip, &addr) || !mac_out) return PD_ERR_INVALID_ARG;
    mac_out[0] = '\0';
#if defined(_WIN32)
    // Read the neighbour table first (a ping just populated it); SendARP is the
    // fallback because it is unreliable when many lookups run concurrently.
    MIB_IPNET_TABLE2* table = nullptr;
    if (GetIpNetTable2(AF_INET, &table) == NO_ERROR) {
        bool found = false;
        for (ULONG i = 0; i < table->NumEntries && !found; ++i) {
            const MIB_IPNET_ROW2& row = table->Table[i];
            if (row.Address.Ipv4.sin_addr.s_addr != htonl(addr) || row.PhysicalAddressLength != 6) continue;
            if (row.State == NlnsUnreachable || row.State == NlnsIncomplete) continue;
            copy_str(mac_out, PD_MAC_LEN, mac_to_string(row.PhysicalAddress));
            found = true;
        }
        FreeMibTable(table);
        if (found) return PD_OK;
    }
    ULONG mac[2];
    ULONG len = 6;
    if (SendARP(htonl(addr), 0, mac, &len) != NO_ERROR || len != 6) return PD_ERR_NOT_FOUND;
    copy_str(mac_out, PD_MAC_LEN, mac_to_string(reinterpret_cast<uint8_t*>(mac)));
    return PD_OK;
#elif defined(__linux__) || defined(__ANDROID__)
    // Readable on desktop Linux / Docker; SELinux blocks it on Android 10+.
    std::ifstream f("/proc/net/arp");
    if (!f) return PD_ERR_PERMISSION;
    std::string line;
    std::getline(f, line);  // header
    while (std::getline(f, line)) {
        std::istringstream ss(line);
        std::string rip, hwtype, flags, hw;
        if (!(ss >> rip >> hwtype >> flags >> hw)) continue;
        if (rip != ip || flags == "0x0" || hw == "00:00:00:00:00:00") continue;
        copy_str(mac_out, PD_MAC_LEN, hw);
        return PD_OK;
    }
    return PD_ERR_NOT_FOUND;
#else
    return PD_ERR_UNSUPPORTED;
#endif
}

int pd_sweep(const char* cidr, int timeout_ms, int concurrency, uint32_t flags, pd_device_cb cb, void* user) {
    uint32_t network;
    uint8_t prefix;
    if (!parse_cidr(cidr, &network, &prefix) || prefix < 16 || timeout_ms <= 0) return PD_ERR_INVALID_ARG;
    pd_init();

    // Skip network and broadcast addresses except for /31 and /32.
    uint32_t count = prefix >= 31 ? (1u << (32 - prefix)) : (1u << (32 - prefix)) - 2;
    uint32_t first = prefix >= 31 ? network : network + 1;
    if (concurrency <= 0) concurrency = PD_SWEEP_DEFAULT_CONCURRENCY;
    int workers = static_cast<int>(std::min<uint32_t>(count, static_cast<uint32_t>(concurrency)));

    CancelToken tok;
    std::atomic<uint32_t> next{0};
    std::atomic<int> fatal{PD_OK};
    std::vector<pd_device> live;  // guarded by cb_mutex
    std::mutex cb_mutex;  // callbacks are serialised so consumers need no locking

    std::vector<std::thread> pool;
    pool.reserve(static_cast<size_t>(workers));
    for (int w = 0; w < workers; ++w) {
        pool.emplace_back([&] {
            for (uint32_t i = next++; i < count && !tok.cancelled() && fatal == PD_OK; i = next++) {
                uint32_t addr = first + i;
                int rtt = ping_host(addr, timeout_ms);
                if (rtt == PD_ERR_PERMISSION || rtt == PD_ERR_SOCKET) {
                    fatal = rtt;
                    break;
                }
                if (rtt < 0) continue;

                pd_device d = make_device(ipv4_to_string(addr));
                d.rtt_ms = rtt;
                d.sources = PD_SRC_ICMP;
                if ((flags & PD_SWEEP_ARP_CACHE) && pd_arp_cache_lookup(d.ip, d.mac) == PD_OK) {
                    d.sources |= PD_SRC_ARP;
                    pd_oui_lookup(d.mac, d.vendor, sizeof(d.vendor));
                }

                std::lock_guard<std::mutex> lock(cb_mutex);
                live.push_back(d);
                if (cb) cb(&d, user);
            }
        });
    }
    for (auto& t : pool) t.join();

    if (fatal != PD_OK) return fatal;
    if (tok.cancelled()) return PD_ERR_CANCELLED;

    // Enrichment runs as a second, fully parallel phase so it never holds up
    // the ping workers: retry MACs the neighbour cache had not settled yet,
    // and do reverse lookups (each capped at 1.5s).
    if (flags & (PD_SWEEP_RESOLVE_DNS | PD_SWEEP_ARP_CACHE)) {
        const std::string server = (flags & PD_SWEEP_RESOLVE_DNS) ? dns::lan_dns_server() : std::string();
        std::atomic<size_t> idx{0};
        std::vector<std::thread> enrich;
        size_t n = std::min<size_t>(live.size(), 64);
        for (size_t w = 0; w < n; ++w) {
            enrich.emplace_back([&] {
                for (size_t i = idx++; i < live.size() && !tok.cancelled(); i = idx++) {
                    pd_device d = live[i];
                    bool changed = false;
                    if ((flags & PD_SWEEP_ARP_CACHE) && !d.mac[0] && pd_arp_cache_lookup(d.ip, d.mac) == PD_OK) {
                        d.sources |= PD_SRC_ARP;
                        pd_oui_lookup(d.mac, d.vendor, sizeof(d.vendor));
                        changed = true;
                    }
                    std::string name;
                    if ((flags & PD_SWEEP_RESOLVE_DNS) && dns::reverse_lookup(d.ip, server, 1500, name)) {
                        copy_str(d.hostname, sizeof(d.hostname), name);
                        d.sources |= PD_SRC_DNS;
                        changed = true;
                    }
                    if (!changed) continue;
                    std::lock_guard<std::mutex> lock(cb_mutex);
                    if (cb) cb(&d, user);
                }
            });
        }
        for (auto& t : enrich) t.join();
        if (tok.cancelled()) return PD_ERR_CANCELLED;
    }
    return static_cast<int>(live.size());
}

}  // extern "C"
