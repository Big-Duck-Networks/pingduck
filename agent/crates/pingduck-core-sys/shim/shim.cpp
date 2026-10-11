// C entry points into pingduck-core internals that the public ABI doesn't
// expose. Used by the agent's tests to run the agent's UPnP output through
// the exact parser the phone uses (core/src/ssdp.cpp).
#include <cstring>
#include <string>

#include "parsers.hpp"

namespace {

void put(char* dst, int cap, const std::string& s) {
    if (!dst || cap <= 0) return;
    size_t n = s.size() < static_cast<size_t>(cap - 1) ? s.size() : static_cast<size_t>(cap - 1);
    std::memcpy(dst, s.data(), n);
    dst[n] = '\0';
}

}  // namespace

// Parses a UPnP device description the way the phone does.
extern "C" void pdsys_describe(const char* xml, char* vendor, char* model, char* hostname, char* services, int cap) {
    pd::ssdp::Responder r;
    pd_device d{};
    pd::ssdp::apply_description(xml ? xml : "", r, d);
    put(vendor, cap, d.vendor);
    put(model, cap, d.model);
    put(hostname, cap, d.hostname);
    put(services, cap, d.services);
}

// Folds an M-SEARCH reply the way the phone does; returns 1 if accepted.
extern "C" int pdsys_note_response(const char* msg, char* location, char* types, int cap) {
    pd::ssdp::Responder r;
    if (!pd::ssdp::note_response(msg ? msg : "", r)) return 0;
    std::string joined;
    for (auto& t : r.types) joined += (joined.empty() ? "" : ",") + t;
    put(location, cap, r.location);
    put(types, cap, joined);
    return 1;
}
