// Local IPv4 interface enumeration and "which one is the LAN" selection.
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <mutex>
#include <sstream>
#include <vector>

#include "parsers.hpp"
#include "platform.hpp"

#if defined(_WIN32)
#  include <iphlpapi.h>
#else
#  include <ifaddrs.h>
#  include <net/if.h>
#  if defined(__linux__) || defined(__ANDROID__)
#    include <linux/if_packet.h>
#  elif defined(__APPLE__)
#    include <net/if_dl.h>
#  endif
#endif

using namespace pd;

namespace pd {

// /proc/net/route: Iface Destination Gateway ... (hex, in network byte order
// as the kernel stores it, printed as a native-endian integer).
std::string proc_route_gateway(std::istream& in, const std::string& iface) {
    std::string line;
    std::getline(in, line);  // header
    while (std::getline(in, line)) {
        std::istringstream ss(line);
        std::string name, dest, gw;
        if (!(ss >> name >> dest >> gw)) continue;
        if (name != iface || dest != "00000000" || gw.size() != 8) continue;
        char* end = nullptr;
        unsigned long v = std::strtoul(gw.c_str(), &end, 16);
        if (*end != '\0' || v == 0) continue;
        in_addr a{};
        a.s_addr = static_cast<uint32_t>(v);
        return ipv4_to_string(ntohl(a.s_addr));
    }
    return {};
}

}  // namespace pd

namespace {

void finish_iface(pd_interface& f, uint32_t ip, uint8_t prefix) {
    uint32_t mask = prefix == 0 ? 0 : 0xFFFFFFFFu << (32 - prefix);
    f.prefix_len = prefix;
    copy_str(f.ip, sizeof(f.ip), ipv4_to_string(ip));
    copy_str(f.netmask, sizeof(f.netmask), ipv4_to_string(mask));
    copy_str(f.broadcast, sizeof(f.broadcast), ipv4_to_string((ip & mask) | ~mask));
}

bool is_private(uint32_t ip) {
    return (ip >> 24) == 10 || (ip >> 20) == 0xAC1 /* 172.16/12 */ || (ip >> 16) == 0xC0A8;
}

bool is_link_local(uint32_t ip) { return (ip >> 16) == 0xA9FE; }

#if defined(_WIN32)

std::string narrow(const wchar_t* w) {
    if (!w) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
    if (n <= 1) return {};
    std::string s(static_cast<size_t>(n - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, w, -1, s.data(), n, nullptr, nullptr);
    return s;
}

std::vector<pd_interface> enumerate() {
    std::vector<pd_interface> result;
    ULONG size = 16 * 1024;
    std::vector<uint8_t> buf;
    ULONG rc;
    do {
        buf.resize(size);
        rc = GetAdaptersAddresses(AF_INET, GAA_FLAG_INCLUDE_GATEWAYS, nullptr,
                                  reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buf.data()), &size);
    } while (rc == ERROR_BUFFER_OVERFLOW);
    if (rc != NO_ERROR) return result;

    for (auto* a = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buf.data()); a; a = a->Next) {
        if (a->OperStatus != IfOperStatusUp || a->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;

        std::string gateway;
        for (auto* g = a->FirstGatewayAddress; g; g = g->Next) {
            if (g->Address.lpSockaddr->sa_family == AF_INET) {
                auto* sin = reinterpret_cast<sockaddr_in*>(g->Address.lpSockaddr);
                gateway = ipv4_to_string(ntohl(sin->sin_addr.s_addr));
                break;
            }
        }

        std::string dns;
        for (auto* d = a->FirstDnsServerAddress; d; d = d->Next) {
            if (d->Address.lpSockaddr->sa_family == AF_INET) {
                auto* sin = reinterpret_cast<sockaddr_in*>(d->Address.lpSockaddr);
                dns = ipv4_to_string(ntohl(sin->sin_addr.s_addr));
                break;
            }
        }

        for (auto* u = a->FirstUnicastAddress; u; u = u->Next) {
            if (u->Address.lpSockaddr->sa_family != AF_INET) continue;
            pd_interface f{};
            auto* sin = reinterpret_cast<sockaddr_in*>(u->Address.lpSockaddr);
            finish_iface(f, ntohl(sin->sin_addr.s_addr), u->OnLinkPrefixLength);
            copy_str(f.name, sizeof(f.name), narrow(a->FriendlyName));
            copy_str(f.gateway, sizeof(f.gateway), gateway);
            copy_str(f.dns, sizeof(f.dns), dns);
            if (a->PhysicalAddressLength == 6) copy_str(f.mac, sizeof(f.mac), mac_to_string(a->PhysicalAddress));
            result.push_back(f);
        }
    }
    return result;
}

#else

std::vector<pd_interface> enumerate() {
    std::vector<pd_interface> result;
    ifaddrs* list = nullptr;
    if (getifaddrs(&list) != 0) return result;

    for (ifaddrs* i = list; i; i = i->ifa_next) {
        if (!i->ifa_addr || i->ifa_addr->sa_family != AF_INET) continue;
        if (!(i->ifa_flags & IFF_UP) || (i->ifa_flags & IFF_LOOPBACK)) continue;

        uint32_t ip = ntohl(reinterpret_cast<sockaddr_in*>(i->ifa_addr)->sin_addr.s_addr);
        uint32_t mask = i->ifa_netmask ? ntohl(reinterpret_cast<sockaddr_in*>(i->ifa_netmask)->sin_addr.s_addr) : 0;
        uint8_t prefix = 0;
        while (prefix < 32 && (mask & (0x80000000u >> prefix))) ++prefix;

        pd_interface f{};
        finish_iface(f, ip, prefix);
        copy_str(f.name, sizeof(f.name), i->ifa_name);
#if defined(__linux__) || defined(__ANDROID__)
        {
            std::ifstream route("/proc/net/route");
            copy_str(f.gateway, sizeof(f.gateway), proc_route_gateway(route, i->ifa_name));
        }
#endif
        // Hardware address lives in a sibling entry of a link-layer family.
        for (ifaddrs* j = list; j; j = j->ifa_next) {
            if (!j->ifa_addr || std::strcmp(j->ifa_name, i->ifa_name) != 0) continue;
#if defined(__linux__) || defined(__ANDROID__)
            if (j->ifa_addr->sa_family == AF_PACKET) {
                auto* ll = reinterpret_cast<sockaddr_ll*>(j->ifa_addr);
                if (ll->sll_halen == 6) copy_str(f.mac, sizeof(f.mac), mac_to_string(ll->sll_addr));
            }
#elif defined(__APPLE__)
            if (j->ifa_addr->sa_family == AF_LINK) {
                auto* dl = reinterpret_cast<sockaddr_dl*>(j->ifa_addr);
                if (dl->sdl_alen == 6)
                    copy_str(f.mac, sizeof(f.mac), mac_to_string(reinterpret_cast<uint8_t*>(LLADDR(dl))));
            }
#endif
        }
        result.push_back(f);
    }
    freeifaddrs(list);
    return result;
}

#endif

// Host-app hints (pd_set_lan_hints), host order; 0 = unset.
std::mutex g_hint_mu;
uint32_t g_hint_gateway = 0, g_hint_dns = 0;

// Fills an empty gateway/DNS with a hint inside that interface's subnet.
std::vector<pd_interface> with_hints(std::vector<pd_interface> all) {
    std::lock_guard<std::mutex> lock(g_hint_mu);
    for (auto& f : all) {
        uint32_t ip = 0;
        parse_ipv4(f.ip, &ip);
        uint32_t mask = f.prefix_len == 0 ? 0 : 0xFFFFFFFFu << (32 - f.prefix_len);
        if (!f.gateway[0] && g_hint_gateway && (g_hint_gateway & mask) == (ip & mask))
            copy_str(f.gateway, sizeof(f.gateway), ipv4_to_string(g_hint_gateway));
        // The DNS server may live off-subnet (e.g. 1.1.1.1), so it only
        // needs an interface that routes somewhere.
        if (!f.dns[0] && g_hint_dns && f.gateway[0]) copy_str(f.dns, sizeof(f.dns), ipv4_to_string(g_hint_dns));
    }
    return all;
}

}  // namespace

extern "C" {

int pd_set_lan_hints(const char* gateway, const char* dns) {
    uint32_t gw = 0, ns = 0;
    if (gateway && gateway[0] && !parse_ipv4(gateway, &gw)) return PD_ERR_INVALID_ARG;
    if (dns && dns[0] && !parse_ipv4(dns, &ns)) return PD_ERR_INVALID_ARG;
    std::lock_guard<std::mutex> lock(g_hint_mu);
    g_hint_gateway = gw;
    g_hint_dns = ns;
    return PD_OK;
}

int pd_list_interfaces(pd_interface* out, int max) {
    if (!out || max <= 0) return PD_ERR_INVALID_ARG;
    pd_init();
    auto all = with_hints(enumerate());
    int n = 0;
    for (auto& f : all) {
        if (n >= max) break;
        out[n++] = f;
    }
    return n;
}

int pd_default_interface(pd_interface* out) {
    if (!out) return PD_ERR_INVALID_ARG;
    pd_init();
    auto all = with_hints(enumerate());
    const pd_interface* best = nullptr;
    int best_score = -1;
    for (auto& f : all) {
        uint32_t ip = 0;
        parse_ipv4(f.ip, &ip);
        if (is_link_local(ip) || f.prefix_len == 32) continue;
        int score = 0;
        if (f.gateway[0]) score += 4;
        if (is_private(ip)) score += 2;
        if (f.prefix_len >= 16 && f.prefix_len <= 30) score += 1;
        if (score > best_score) {
            best_score = score;
            best = &f;
        }
    }
    if (!best) return PD_ERR_NOT_FOUND;
    *out = *best;
    return PD_OK;
}

}  // extern "C"
