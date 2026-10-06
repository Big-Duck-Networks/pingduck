// Agent-mode ARP sweep: inject ARP who-has frames for every address in the
// subnet with libpcap and sniff the replies. Unlike ICMP this finds hosts that
// drop pings (most firewalled phones/IoT) and yields exact MAC addresses.
// Needs root or CAP_NET_RAW (the Docker agent runs with --net=host + NET_RAW).
#include "parsers.hpp"
#include "platform.hpp"

namespace pd {

void build_arp_request(uint8_t frame[42], const uint8_t src_mac[6], uint32_t src_ip, uint32_t target_ip) {
    std::memset(frame, 0xFF, 6);                 // broadcast
    std::memcpy(frame + 6, src_mac, 6);
    frame[12] = 0x08, frame[13] = 0x06;          // ethertype ARP
    const uint8_t hdr[8] = {0x00, 0x01, 0x08, 0x00, 6, 4, 0x00, 0x01};  // ethernet/IPv4, op=request
    std::memcpy(frame + 14, hdr, 8);
    std::memcpy(frame + 22, src_mac, 6);
    for (int i = 0; i < 4; ++i) frame[28 + i] = static_cast<uint8_t>(src_ip >> (24 - 8 * i));
    std::memset(frame + 32, 0, 6);
    for (int i = 0; i < 4; ++i) frame[38 + i] = static_cast<uint8_t>(target_ip >> (24 - 8 * i));
}

bool parse_arp_reply(const uint8_t* frame, size_t n, uint32_t* ip, uint8_t mac[6]) {
    if (n < 42) return false;
    if (frame[12] != 0x08 || frame[13] != 0x06) return false;            // ethertype ARP
    if (frame[14] != 0x00 || frame[15] != 0x01 || frame[16] != 0x08 ||  // ethernet / IPv4
        frame[17] != 0x00 || frame[18] != 6 || frame[19] != 4)
        return false;
    if (frame[20] != 0x00 || frame[21] != 0x02) return false;  // op = reply
    std::memcpy(mac, frame + 22, 6);
    *ip = static_cast<uint32_t>(frame[28]) << 24 | static_cast<uint32_t>(frame[29]) << 16 |
          static_cast<uint32_t>(frame[30]) << 8 | frame[31];
    return true;
}

}  // namespace pd

#if defined(PINGDUCK_WITH_PCAP)

#include <pcap/pcap.h>

#include <chrono>
#include <set>
#include <thread>
#include <vector>

using namespace pd;

namespace {

bool find_interface(const char* name, pd_interface* out) {
    if (!name) return pd_default_interface(out) == PD_OK;
    pd_interface list[32];
    int n = pd_list_interfaces(list, 32);
    for (int i = 0; i < n; ++i)
        if (std::strcmp(list[i].name, name) == 0) return *out = list[i], true;
    return false;
}

}  // namespace

extern "C" int pd_arp_scan(const char* iface, const char* cidr, int timeout_ms, pd_device_cb cb, void* user) {
    if (timeout_ms <= 0) return PD_ERR_INVALID_ARG;
    pd_init();
    CancelToken tok;

    pd_interface f{};
    if (!find_interface(iface, &f)) return PD_ERR_NOT_FOUND;
    uint8_t src_mac[6];
    uint32_t src_ip;
    if (!parse_mac(f.mac, src_mac) || !parse_ipv4(f.ip, &src_ip)) return PD_ERR_NOT_FOUND;

    uint32_t network;
    uint8_t prefix;
    std::string range = cidr ? cidr : std::string(f.ip) + "/" + std::to_string(f.prefix_len);
    if (!parse_cidr(range.c_str(), &network, &prefix) || prefix < 16) return PD_ERR_INVALID_ARG;
    uint32_t first = prefix >= 31 ? network : network + 1;
    uint32_t count = prefix >= 31 ? (1u << (32 - prefix)) : (1u << (32 - prefix)) - 2;

    char err[PCAP_ERRBUF_SIZE] = {0};
    pcap_t* p = pcap_create(f.name, err);
    if (!p) return PD_ERR_SOCKET;
    pcap_set_snaplen(p, 128);
    pcap_set_immediate_mode(p, 1);
    pcap_set_timeout(p, 50);
    int act = pcap_activate(p);
    if (act < 0) {
        pcap_close(p);
        return (act == PCAP_ERROR_PERM_DENIED) ? PD_ERR_PERMISSION : PD_ERR_SOCKET;
    }

    bpf_program prog{};
    if (pcap_compile(p, &prog, "arp and arp[6:2] = 2", 1, PCAP_NETMASK_UNKNOWN) == 0) {
        pcap_setfilter(p, &prog);
        pcap_freecode(&prog);
    }

    // Two passes of who-has so a single dropped frame does not hide a host.
    std::atomic<bool> sending{true};
    std::thread sender([&] {
        uint8_t frame[42];
        for (int pass = 0; pass < 2 && !tok.cancelled(); ++pass) {
            for (uint32_t i = 0; i < count && !tok.cancelled(); ++i) {
                uint32_t target = first + i;
                if (target == src_ip) continue;
                build_arp_request(frame, src_mac, src_ip, target);
                pcap_inject(p, frame, sizeof(frame));
                if ((i & 31) == 31) std::this_thread::sleep_for(std::chrono::milliseconds(2));
            }
        }
        sending = false;
    });

    std::set<uint32_t> seen;
    int64_t deadline = INT64_MAX;
    for (;;) {
        if (tok.cancelled()) break;
        if (!sending && deadline == INT64_MAX) deadline = now_ms() + timeout_ms;
        if (now_ms() >= deadline) break;

        pcap_pkthdr* hdr;
        const u_char* data;
        int rc = pcap_next_ex(p, &hdr, &data);
        if (rc < 0) break;
        if (rc == 0) continue;
        uint32_t ip;
        uint8_t mac[6];
        if (!parse_arp_reply(data, hdr->caplen, &ip, mac)) continue;
        if (ip < first || ip - first >= count || !seen.insert(ip).second) continue;

        pd_device d = make_device(ipv4_to_string(ip));
        d.sources = PD_SRC_ARP;
        copy_str(d.mac, sizeof(d.mac), mac_to_string(mac));
        pd_oui_lookup(d.mac, d.vendor, sizeof(d.vendor));
        if (cb) cb(&d, user);
    }

    sender.join();
    pcap_close(p);
    if (tok.cancelled()) return PD_ERR_CANCELLED;
    return static_cast<int>(seen.size());
}

#else

extern "C" int pd_arp_scan(const char*, const char*, int, pd_device_cb, void*) { return PD_ERR_UNSUPPORTED; }

#endif
