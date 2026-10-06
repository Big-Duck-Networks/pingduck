// Smaller parsers: ICMP echo replies, ARP frames, procfs tables, CSV lines,
// MAC/CIDR strings, and the scan merger. The first byte picks the target.
#include <cstdlib>
#include <sstream>

#include "parsers.hpp"

namespace {

// Builds a device whose string fields come from the input but are always
// NUL-terminated, as the public API guarantees.
pd_device device_from(const uint8_t* data, size_t size) {
    pd_device d = pd::make_device(size > 0 && (data[0] & 1) ? "10.42.0.1" : "10.42.0.2");
    std::vector<std::string> parts;
    std::istringstream ss(std::string(reinterpret_cast<const char*>(data), size));
    for (std::string p; std::getline(ss, p, '|');) parts.push_back(p);
    parts.resize(6);
    pd::copy_str(d.mac, sizeof(d.mac), parts[1]);
    pd::copy_str(d.hostname, sizeof(d.hostname), parts[2]);
    pd::copy_str(d.vendor, sizeof(d.vendor), parts[3]);
    pd::copy_str(d.model, sizeof(d.model), parts[4]);
    pd::copy_str(d.services, sizeof(d.services), parts[5]);
    d.sources = size > 1 ? data[1] : 0;
    d.rtt_ms = size > 2 ? data[2] - 1 : -1;
    return d;
}

}  // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 1) return 0;
    uint8_t which = data[0];
    ++data, --size;
    std::vector<uint8_t> buf(data, data + size);  // exact-size copy for ASan
    std::string text(reinterpret_cast<const char*>(data), size);

    switch (which % 7) {
        case 0: {
            uint16_t id, seq;
            pd::parse_echo_reply(buf.data(), buf.size(), &id, &seq);
            break;
        }
        case 1: {
            uint32_t ip;
            uint8_t mac[6];
            pd::parse_arp_reply(buf.data(), buf.size(), &ip, mac);
            break;
        }
        case 2:
            pd::split_csv(text);
            break;
        case 3: {
            uint8_t mac[6];
            uint32_t net;
            uint8_t prefix;
            pd::parse_mac(text.c_str(), mac);
            pd::parse_cidr(text.c_str(), &net, &prefix);
            break;
        }
        case 4: {
            std::istringstream in(text);
            pd::proc_arp_lookup(in, "10.42.0.1");
            break;
        }
        case 5: {
            std::istringstream in(text);
            pd::proc_route_gateway(in, "eth0");
            break;
        }
        case 6: {
            // Records separated by newlines, fields by '|'.
            pd::DeviceMerger m;
            std::istringstream in(text);
            std::string line;
            pd_device out;
            while (std::getline(in, line)) {
                pd_device d = device_from(reinterpret_cast<const uint8_t*>(line.data()), line.size());
                if (m.add(d, &out) && !std::memchr(out.services, 0, sizeof(out.services))) std::abort();
            }
            break;
        }
    }
    return 0;
}
