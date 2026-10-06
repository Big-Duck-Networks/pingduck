// SSDP replies and UPnP device description XML (ssdp.cpp). The input is
// split at the first NUL: before it is an SSDP datagram, after it the XML body.
#include <cstdlib>

#include "parsers.hpp"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    const uint8_t* nul = static_cast<const uint8_t*>(std::memchr(data, 0, size));
    size_t msg_len = nul ? static_cast<size_t>(nul - data) : size;
    std::string msg(reinterpret_cast<const char*>(data), msg_len);
    std::string xml = nul ? std::string(reinterpret_cast<const char*>(nul + 1), size - msg_len - 1) : std::string();

    pd::ssdp::parse_headers(msg);
    pd::ssdp::Responder r;
    pd::ssdp::note_response(msg, r);
    pd::ssdp::short_type(msg);

    pd_device d = pd::make_device("10.42.0.1");
    pd::ssdp::apply_description(xml, r, d);
    if (!std::memchr(d.hostname, 0, sizeof(d.hostname)) || !std::memchr(d.model, 0, sizeof(d.model)) ||
        !std::memchr(d.services, 0, sizeof(d.services)))
        std::abort();
    return 0;
}
