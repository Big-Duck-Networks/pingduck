// ICMP echo (ping), subnet sweep, and OS ARP-cache lookup.
//
// Windows: IcmpSendEcho (no admin needed) on a thread pool.
// Linux/Android/Apple: unprivileged SOCK_DGRAM ICMP "ping sockets" first,
// falling back to SOCK_RAW when running as root (agent mode). Sweeps use a
// single non-blocking socket.
#include <algorithm>
#include <fstream>
#include <mutex>
#include <sstream>
#include <thread>
#include <vector>

#include "dns.hpp"
#include "parsers.hpp"
#include "platform.hpp"

#if defined(_WIN32)
#  include <iphlpapi.h>
#  include <icmpapi.h>
#endif

using namespace pd;

namespace pd {

bool parse_echo_reply(const uint8_t* buf, size_t n, uint16_t* id, uint16_t* seq, int* ttl) {
    const uint8_t* icmp = buf;
    int header_ttl = -1;
    if (n > 0 && (buf[0] >> 4) == 4) {
        size_t ihl = static_cast<size_t>(buf[0] & 0x0F) * 4;
        if (ihl < 20 || n < ihl + 8) return false;
        header_ttl = buf[8];
        icmp = buf + ihl;
        n -= ihl;
    }
    if (n < 8 || icmp[0] != 0 /* echo reply */ || icmp[1] != 0) return false;
    *id = static_cast<uint16_t>(icmp[4] << 8 | icmp[5]);
    *seq = static_cast<uint16_t>(icmp[6] << 8 | icmp[7]);
    if (ttl && header_ttl >= 0) *ttl = header_ttl;
    return true;
}

std::string proc_arp_lookup(std::istream& in, const std::string& ip) {
    std::string line;
    std::getline(in, line);  // header
    while (std::getline(in, line)) {
        std::istringstream ss(line);
        std::string rip, hwtype, flags, hw;
        if (!(ss >> rip >> hwtype >> flags >> hw)) continue;
        uint8_t mac[6];
        if (rip != ip || flags == "0x0" || !parse_mac(hw.c_str(), mac)) continue;
        if (std::all_of(mac, mac + 6, [](uint8_t b) { return b == 0; })) continue;
        return mac_to_string(mac);
    }
    return {};
}

}  // namespace pd

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

// Unprivileged "ping socket" first; raw when running as root (agent mode).
pd_socket open_icmp_socket(bool* raw) {
    *raw = false;
    pd_socket fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (fd == PD_INVALID_SOCKET) {
        fd = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
        *raw = true;
    }
#if defined(IP_RECVTTL)
    // Linux/Android ping sockets strip the IP header; the TTL comes as a cmsg.
    int on = 1;
    if (fd != PD_INVALID_SOCKET && !*raw) setsockopt(fd, IPPROTO_IP, IP_RECVTTL, &on, sizeof(on));
#endif
    return fd;
}

// recvfrom plus the reply's TTL: from the IP_TTL cmsg on ping sockets that
// strip the header; parse_echo_reply reads it from the header otherwise.
ssize_t recv_echo(pd_socket fd, uint8_t* buf, size_t cap, sockaddr_in* from, int* ttl) {
    iovec iov{buf, cap};
    alignas(cmsghdr) uint8_t control[64];
    msghdr msg{};
    msg.msg_name = from;
    msg.msg_namelen = sizeof(*from);
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = control;
    msg.msg_controllen = sizeof(control);
    ssize_t n = recvmsg(fd, &msg, 0);
    *ttl = -1;
    if (n <= 0) return n;
    for (cmsghdr* c = CMSG_FIRSTHDR(&msg); c; c = CMSG_NXTHDR(&msg, c)) {
        if (c->cmsg_level != IPPROTO_IP) continue;
#if defined(IP_TTL)
        if (c->cmsg_type == IP_TTL && c->cmsg_len >= CMSG_LEN(sizeof(int))) {
            int v;
            std::memcpy(&v, CMSG_DATA(c), sizeof(v));
            *ttl = v;
        }
#endif
#if defined(IP_RECVTTL) && defined(__APPLE__)
        if (c->cmsg_type == IP_RECVTTL && c->cmsg_len >= CMSG_LEN(1)) *ttl = *CMSG_DATA(c);
#endif
    }
    return n;
}

int socket_error() { return (errno == EPERM || errno == EACCES) ? PD_ERR_PERMISSION : PD_ERR_SOCKET; }

void build_echo(uint8_t pkt[32], uint16_t id, uint16_t seq) {
    std::memset(pkt, 0, 32);
    pkt[0] = 8;  // echo request
    pkt[4] = static_cast<uint8_t>(id >> 8);
    pkt[5] = static_cast<uint8_t>(id);
    pkt[6] = static_cast<uint8_t>(seq >> 8);
    pkt[7] = static_cast<uint8_t>(seq);
    std::memcpy(pkt + 8, "pingduck-quack!!", 16);
    uint16_t cs = checksum(pkt, 32);
    pkt[2] = static_cast<uint8_t>(cs >> 8);
    pkt[3] = static_cast<uint8_t>(cs);
}

int ping_posix(uint32_t target, int timeout_ms, int* ttl) {
    bool raw;
    Socket s(open_icmp_socket(&raw));
    if (!s.valid()) return socket_error();

    sockaddr_in dst{};
    dst.sin_family = AF_INET;
    dst.sin_addr.s_addr = htonl(target);

    const uint16_t seq = g_seq++;
    const uint16_t id = static_cast<uint16_t>(getpid() ^ (seq << 3));
    uint8_t pkt[32];
    build_echo(pkt, id, seq);

    int64_t start = now_ms();
    if (sendto(s.fd, pkt, sizeof(pkt), 0, reinterpret_cast<sockaddr*>(&dst), sizeof(dst)) < 0)
        return PD_ERR_SOCKET;

    uint8_t buf[1500];
    for (;;) {
        int remaining = static_cast<int>(timeout_ms - (now_ms() - start));
        if (remaining <= 0) return PD_ERR_TIMEOUT;
        if (wait_readable(s.fd, remaining) <= 0) return PD_ERR_TIMEOUT;

        sockaddr_in from{};
        ssize_t n = recv_echo(s.fd, buf, sizeof(buf), &from, ttl);
        if (n <= 0 || from.sin_addr.s_addr != dst.sin_addr.s_addr) continue;
        uint16_t rid, rseq;
        if (!parse_echo_reply(buf, static_cast<size_t>(n), &rid, &rseq, ttl) || rseq != seq) continue;
        // DGRAM ping sockets get their id rewritten by the kernel; only check it for raw.
        if (raw && rid != id) continue;
        return static_cast<int>(now_ms() - start);
    }
}

// Sweeps [first, first + count) from one non-blocking ICMP socket: echoes go
// out in paced bursts while replies are drained, and hosts that stay silent
// get one retry. Costs one thread instead of a 128-thread pool, which matters
// on phones. `on_reply(addr, rtt, ttl)` runs on the calling thread.
template <typename OnReply>
int sweep_posix(uint32_t first, uint32_t count, int timeout_ms, const CancelToken& tok, OnReply on_reply) {
    bool raw;
    Socket s(open_icmp_socket(&raw));
    if (!s.valid()) return socket_error();
    set_nonblocking(s.fd, true);
    int rcvbuf = 1 << 20;  // a /24 answering at once must not overflow the queue
    setsockopt(s.fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf));

    // seq = index + 1 (a /16 has 65534 hosts, so it fits); id only matters for raw.
    const uint16_t id = static_cast<uint16_t>(getpid());
    std::vector<int64_t> sent_at(count, 0);
    std::vector<uint8_t> answered(count, 0);
    uint32_t pending = count;

    auto drain = [&] {
        uint8_t buf[1500];
        for (;;) {
            sockaddr_in from{};
            int ttl;
            ssize_t n = recv_echo(s.fd, buf, sizeof(buf), &from, &ttl);
            if (n <= 0) return;
            uint16_t rid, rseq;
            if (!parse_echo_reply(buf, static_cast<size_t>(n), &rid, &rseq, &ttl)) continue;
            if (raw && rid != id) continue;
            uint32_t addr = ntohl(from.sin_addr.s_addr);
            if (addr < first || addr - first >= count) continue;
            uint32_t i = addr - first;
            if (static_cast<uint16_t>(i + 1) != rseq || answered[i] || !sent_at[i]) continue;
            answered[i] = 1;
            --pending;
            on_reply(addr, static_cast<int>(now_ms() - sent_at[i]), ttl);
        }
    };

    // Sends one echo to every host not yet answered, draining as it goes.
    // Per-destination failures (EACCES for addresses the kernel treats as
    // broadcast, EHOSTUNREACH, a firewall's EPERM) skip that host; the sweep
    // only fails if no echo at all could be sent.
    //
    // A full send queue (ENOBUFS/EAGAIN) normally clears within milliseconds,
    // so we wait briefly and retry. But echoes to on-link hosts that never
    // answer ARP sit in the queue for seconds; once several hosts in a row
    // stay blocked, the queue is stuck and the rest of the pass is skipped.
    // Those hosts already have an echo queued that goes out if ARP resolves.
    uint32_t sent_ok = 0;
    int last_errno = 0;
    auto send_pass = [&] {
        uint8_t pkt[32];
        int blocked_run = 0;
        for (uint32_t i = 0; i < count && !tok.cancelled(); ++i) {
            if (answered[i]) continue;
            sockaddr_in dst{};
            dst.sin_family = AF_INET;
            dst.sin_addr.s_addr = htonl(first + i);
            build_echo(pkt, id, static_cast<uint16_t>(i + 1));
            bool ok = false, blocked = false;
            for (int attempt = 0; attempt < 3; ++attempt) {
                if (sendto(s.fd, pkt, sizeof(pkt), 0, reinterpret_cast<sockaddr*>(&dst), sizeof(dst)) >= 0) {
                    ok = true;
                    break;
                }
                last_errno = errno;
                blocked = errno == EAGAIN || errno == EWOULDBLOCK || errno == ENOBUFS;
                if (!blocked) break;
                wait_readable(s.fd, 2);  // let replies and the NIC catch up
                drain();
            }
            if (!ok) {
                if (blocked && ++blocked_run >= 8) return;
                continue;
            }
            blocked_run = 0;
            ++sent_ok;
            sent_at[i] = now_ms();
            // Pace bursts so the neighbour table and NIC queue keep up.
            if ((i & 31) == 31) {
                wait_readable(s.fd, 1);
                drain();
            }
        }
    };

    auto wait_until = [&](int64_t deadline) {
        while (pending > 0 && !tok.cancelled()) {
            int left = static_cast<int>(deadline - now_ms());
            if (left <= 0) return;
            if (wait_readable(s.fd, std::min(left, 50)) > 0) drain();
        }
    };

    send_pass();
    if (sent_ok == 0 && !tok.cancelled())
        return (last_errno == EPERM || last_errno == EACCES) ? PD_ERR_PERMISSION : PD_ERR_SOCKET;
    wait_until(now_ms() + timeout_ms / 2);
    if (pending > 0 && !tok.cancelled()) {
        send_pass();
        wait_until(now_ms() + timeout_ms);
    }
    return PD_OK;
}

#endif

int ping_host(uint32_t target, int timeout_ms, int* ttl) {
    *ttl = -1;
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
        if (r->Status == IP_SUCCESS && r->Address == htonl(target)) {
            rc = static_cast<int>(r->RoundTripTime);
            *ttl = r->Options.Ttl;
        }
    }
    IcmpCloseHandle(h);
    return rc;
#else
    return ping_posix(target, timeout_ms, ttl);
#endif
}

}  // namespace

extern "C" {

int pd_ping(const char* ip, int timeout_ms) {
    uint32_t addr;
    if (!parse_ipv4(ip, &addr) || timeout_ms <= 0) return PD_ERR_INVALID_ARG;
    pd_init();
    int ttl;
    return ping_host(addr, timeout_ms, &ttl);
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
    std::string mac = proc_arp_lookup(f, ip);
    if (mac.empty()) return PD_ERR_NOT_FOUND;
    copy_str(mac_out, PD_MAC_LEN, mac);
    return PD_OK;
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

    CancelToken tok;
    std::vector<pd_device> live;  // guarded by cb_mutex
    std::mutex cb_mutex;  // callbacks are serialised so consumers need no locking

    auto report = [&](uint32_t addr, int rtt, int ttl) {
        pd_device d = make_device(ipv4_to_string(addr));
        d.rtt_ms = rtt;
        d.ttl = ttl;
        d.sources = PD_SRC_ICMP;
        if ((flags & PD_SWEEP_ARP_CACHE) && pd_arp_cache_lookup(d.ip, d.mac) == PD_OK) {
            d.sources |= PD_SRC_ARP;
            pd_oui_lookup(d.mac, d.vendor, sizeof(d.vendor));
        }
        std::lock_guard<std::mutex> lock(cb_mutex);
        live.push_back(d);
        if (cb) cb(&d, user);
    };

#if defined(_WIN32)
    // IcmpSendEcho blocks per host, so a thread pool provides the concurrency.
    if (concurrency <= 0) concurrency = PD_SWEEP_DEFAULT_CONCURRENCY;
    int workers = static_cast<int>(std::min<uint32_t>(count, static_cast<uint32_t>(concurrency)));
    std::atomic<uint32_t> next{0};
    std::atomic<int> fatal{PD_OK};
    std::vector<std::thread> pool;
    pool.reserve(static_cast<size_t>(workers));
    for (int w = 0; w < workers; ++w) {
        pool.emplace_back([&] {
            for (uint32_t i = next++; i < count && !tok.cancelled() && fatal == PD_OK; i = next++) {
                uint32_t addr = first + i;
                int ttl;
                int rtt = ping_host(addr, timeout_ms, &ttl);
                if (rtt == PD_ERR_PERMISSION || rtt == PD_ERR_SOCKET) {
                    fatal = rtt;
                    break;
                }
                if (rtt >= 0) report(addr, rtt, ttl);
            }
        });
    }
    for (auto& t : pool) t.join();
#else
    (void)concurrency;  // one socket does the whole sweep
    int fatal = sweep_posix(first, count, timeout_ms, tok, report);
#endif

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
