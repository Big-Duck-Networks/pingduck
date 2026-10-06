// mDNS / DNS-SD responses (mdns.cpp). The input is a sequence of datagrams,
// each as [source host byte][u16 length][bytes], so the fuzzer can explore
// records that refer to each other across packets and responders.
#include <cstdlib>

#include "parsers.hpp"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    pd::mdns::Collector c;
    size_t off = 0;
    while (off + 3 <= size) {
        std::string src = "10.42.0." + std::to_string(data[off]);
        size_t len = static_cast<size_t>(data[off + 1] << 8 | data[off + 2]);
        off += 3;
        if (len > size - off) len = size - off;
        // Copy so ASan catches reads past the datagram, not just the input.
        std::vector<uint8_t> pkt(data + off, data + off + len);
        c.parse(pkt.data(), pkt.size(), src);
        off += len;
    }
    for (auto& d : c.devices()) {
        // Every field the public API hands out must be NUL-terminated.
        if (!std::memchr(d.ip, 0, sizeof(d.ip)) || !std::memchr(d.hostname, 0, sizeof(d.hostname)) ||
            !std::memchr(d.model, 0, sizeof(d.model)) || !std::memchr(d.vendor, 0, sizeof(d.vendor)) ||
            !std::memchr(d.services, 0, sizeof(d.services)))
            std::abort();
    }
    return 0;
}
