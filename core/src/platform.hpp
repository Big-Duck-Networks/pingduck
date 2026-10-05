// Internal cross-platform socket helpers. Not part of the public ABI.
#pragma once

#include <atomic>
#include <cstdint>
#include <cstring>
#include <string>

#include "pingduck/pingduck.h"

#if defined(_WIN32)
#  ifndef WIN32_LEAN_AND_MEAN
#    define WIN32_LEAN_AND_MEAN
#  endif
#  ifndef NOMINMAX
#    define NOMINMAX
#  endif
#  include <winsock2.h>
#  include <ws2tcpip.h>
using pd_socket = SOCKET;
#  define PD_INVALID_SOCKET INVALID_SOCKET
#else
#  include <arpa/inet.h>
#  include <errno.h>
#  include <fcntl.h>
#  include <netdb.h>
#  include <netinet/in.h>
#  include <sys/socket.h>
#  include <sys/time.h>
#  include <unistd.h>
using pd_socket = int;
#  define PD_INVALID_SOCKET (-1)
#endif

namespace pd {

// pd_cancel() bumps the generation; a discovery call captures the generation
// when it starts and stops once it changes, so a cancel never affects later scans.
extern std::atomic<uint32_t> g_cancel_gen;

struct CancelToken {
    uint32_t gen = g_cancel_gen.load();
    bool cancelled() const { return g_cancel_gen.load(std::memory_order_relaxed) != gen; }
};

inline void close_socket(pd_socket s) {
    if (s == PD_INVALID_SOCKET) return;
#if defined(_WIN32)
    closesocket(s);
#else
    close(s);
#endif
}

// RAII wrapper so early returns never leak sockets.
struct Socket {
    pd_socket fd = PD_INVALID_SOCKET;
    Socket() = default;
    explicit Socket(pd_socket s) : fd(s) {}
    ~Socket() { close_socket(fd); }
    Socket(const Socket&) = delete;
    Socket& operator=(const Socket&) = delete;
    bool valid() const { return fd != PD_INVALID_SOCKET; }
};

inline bool set_nonblocking(pd_socket s, bool on) {
#if defined(_WIN32)
    u_long mode = on ? 1 : 0;
    return ioctlsocket(s, FIONBIO, &mode) == 0;
#else
    int flags = fcntl(s, F_GETFL, 0);
    if (flags < 0) return false;
    flags = on ? (flags | O_NONBLOCK) : (flags & ~O_NONBLOCK);
    return fcntl(s, F_SETFL, flags) == 0;
#endif
}

inline void set_recv_timeout(pd_socket s, int ms) {
#if defined(_WIN32)
    DWORD t = static_cast<DWORD>(ms);
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&t), sizeof(t));
#else
    timeval tv{ms / 1000, (ms % 1000) * 1000};
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
#endif
}

// Waits until `s` is readable. Returns >0 readable, 0 timeout, <0 error.
inline int wait_readable(pd_socket s, int timeout_ms) {
    fd_set rf;
    FD_ZERO(&rf);
    FD_SET(s, &rf);
    timeval tv{timeout_ms / 1000, (timeout_ms % 1000) * 1000};
    return select(static_cast<int>(s) + 1, &rf, nullptr, nullptr, &tv);
}

int64_t now_ms();

bool parse_ipv4(const char* ip, uint32_t* host_order_out);
std::string ipv4_to_string(uint32_t host_order);
bool parse_cidr(const char* cidr, uint32_t* network, uint8_t* prefix);
bool parse_mac(const char* mac, uint8_t out[6]);
std::string mac_to_string(const uint8_t mac[6]);

// Bounded copy that always NUL-terminates.
inline void copy_str(char* dst, size_t cap, const std::string& src) {
    if (cap == 0) return;
    size_t n = src.size() < cap - 1 ? src.size() : cap - 1;
    std::memcpy(dst, src.data(), n);
    dst[n] = '\0';
}

// Appends `item` to a comma-separated list held in a fixed buffer, skipping duplicates.
void append_csv(char* dst, size_t cap, const std::string& item);

pd_device make_device(const std::string& ip);

}  // namespace pd
