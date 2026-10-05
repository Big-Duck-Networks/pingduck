// UDP / multicast helpers shared by mDNS and SSDP discovery.
#pragma once

#include "platform.hpp"

namespace pd {

// Opens a UDP socket bound to INADDR_ANY:`port` (0 = ephemeral).
pd_socket open_udp_socket(uint16_t port, bool reuse);

// TTL + outgoing interface = the LAN interface, so multicast does not leave
// through a VPN or Hyper-V adapter on multi-homed machines.
void set_multicast_defaults(pd_socket s);

bool join_multicast(pd_socket s, const char* group);

// TCP connect with a timeout. Returns a connected, blocking socket or PD_INVALID_SOCKET.
pd_socket tcp_connect(const sockaddr_in& addr, int timeout_ms);

}  // namespace pd
