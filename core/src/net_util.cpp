#include "net_util.hpp"

namespace pd {

static in_addr lan_address() {
    in_addr a{};
    a.s_addr = htonl(INADDR_ANY);
    pd_interface f{};
    if (pd_default_interface(&f) == PD_OK) inet_pton(AF_INET, f.ip, &a);
    return a;
}

pd_socket open_udp_socket(uint16_t port, bool reuse) {
    pd_socket s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s == PD_INVALID_SOCKET) return s;
    if (reuse) {
        int yes = 1;
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&yes), sizeof(yes));
#ifdef SO_REUSEPORT
        setsockopt(s, SOL_SOCKET, SO_REUSEPORT, reinterpret_cast<const char*>(&yes), sizeof(yes));
#endif
    }
    sockaddr_in a{};
    a.sin_family = AF_INET;
    a.sin_port = htons(port);
    a.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(s, reinterpret_cast<sockaddr*>(&a), sizeof(a)) != 0) {
        close_socket(s);
        return PD_INVALID_SOCKET;
    }
    return s;
}

void set_multicast_defaults(pd_socket s) {
    unsigned char ttl = 255;
    setsockopt(s, IPPROTO_IP, IP_MULTICAST_TTL, reinterpret_cast<const char*>(&ttl), sizeof(ttl));
    in_addr iface = lan_address();
    setsockopt(s, IPPROTO_IP, IP_MULTICAST_IF, reinterpret_cast<const char*>(&iface), sizeof(iface));
}

bool join_multicast(pd_socket s, const char* group) {
    ip_mreq m{};
    if (inet_pton(AF_INET, group, &m.imr_multiaddr) != 1) return false;
    m.imr_interface = lan_address();
    return setsockopt(s, IPPROTO_IP, IP_ADD_MEMBERSHIP, reinterpret_cast<const char*>(&m), sizeof(m)) == 0;
}

pd_socket tcp_connect(const sockaddr_in& addr, int timeout_ms) {
    Socket s(socket(AF_INET, SOCK_STREAM, IPPROTO_TCP));
    if (!s.valid() || !set_nonblocking(s.fd, true)) return PD_INVALID_SOCKET;

    if (connect(s.fd, reinterpret_cast<const sockaddr*>(&addr), sizeof(addr)) != 0) {
#if defined(_WIN32)
        if (WSAGetLastError() != WSAEWOULDBLOCK) return PD_INVALID_SOCKET;
#else
        if (errno != EINPROGRESS) return PD_INVALID_SOCKET;
#endif
        fd_set wf, ef;
        FD_ZERO(&wf);
        FD_ZERO(&ef);
        FD_SET(s.fd, &wf);
        FD_SET(s.fd, &ef);
        timeval tv{timeout_ms / 1000, (timeout_ms % 1000) * 1000};
        if (select(static_cast<int>(s.fd) + 1, nullptr, &wf, &ef, &tv) <= 0) return PD_INVALID_SOCKET;
        if (FD_ISSET(s.fd, &ef)) return PD_INVALID_SOCKET;
        int err = 0;
        socklen_t len = sizeof(err);
        getsockopt(s.fd, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&err), &len);
        if (err != 0) return PD_INVALID_SOCKET;
    }
    set_nonblocking(s.fd, false);
    pd_socket out = s.fd;
    s.fd = PD_INVALID_SOCKET;  // release ownership
    return out;
}

}  // namespace pd
