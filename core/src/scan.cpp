// pd_scan: run every discovery method concurrently and merge by IP.
#include <algorithm>
#include <map>
#include <mutex>
#include <thread>
#include <vector>

#include "parsers.hpp"
#include "platform.hpp"

using namespace pd;

namespace {

// Fills an empty field; existing values win so the first source to name a
// device keeps it stable across updates.
bool fill(char* dst, size_t cap, const char* src) {
    if (!src[0] || dst[0]) return false;
    copy_str(dst, cap, src);
    return true;
}

// A randomized-MAC placeholder loses to any real vendor name.
bool fill_vendor(char* dst, size_t cap, const char* src) {
    if (!src[0] || std::strcmp(dst, src) == 0) return false;
    bool placeholder = std::strncmp(dst, "Private", 7) == 0;
    if (dst[0] && !placeholder) return false;
    if (placeholder && std::strncmp(src, "Private", 7) == 0) return false;
    copy_str(dst, cap, src);
    return true;
}

struct Shared {
    std::mutex mu;
    DeviceMerger merger;
    pd_device_cb cb;
    void* user;

    static void on_device(const pd_device* d, void* self) {
        auto* s = static_cast<Shared*>(self);
        std::lock_guard<std::mutex> lock(s->mu);
        pd_device merged;
        if (s->merger.add(*d, &merged) && s->cb) s->cb(&merged, s->user);
    }
};

}  // namespace

namespace pd {

bool DeviceMerger::add(const pd_device& in, pd_device* out) {
    auto [it, inserted] = devices_.try_emplace(in.ip, in);
    pd_device& d = it->second;
    bool changed = inserted;
    if (!inserted) {
        changed |= fill(d.mac, sizeof(d.mac), in.mac);
        changed |= fill(d.hostname, sizeof(d.hostname), in.hostname);
        changed |= fill_vendor(d.vendor, sizeof(d.vendor), in.vendor);
        changed |= fill(d.model, sizeof(d.model), in.model);
        std::string before = d.services;
        std::string svc = in.services;
        size_t start = 0;
        while (start < svc.size()) {
            size_t end = svc.find(',', start);
            if (end == std::string::npos) end = svc.size();
            append_csv(d.services, sizeof(d.services), svc.substr(start, end - start));
            start = end + 1;
        }
        changed |= before != d.services;
        if (d.rtt_ms < 0 && in.rtt_ms >= 0) d.rtt_ms = in.rtt_ms, changed = true;
        if (d.ttl < 0 && in.ttl >= 0) d.ttl = in.ttl, changed = true;
        changed |= fill(d.server, sizeof(d.server), in.server);
        if ((d.sources | in.sources) != d.sources) d.sources |= in.sources, changed = true;
    }
    if (changed && out) *out = d;
    return changed;
}

}  // namespace pd

extern "C" int pd_scan(const char* cidr, int timeout_ms, uint32_t flags, pd_device_cb cb, void* user) {
    if (timeout_ms <= 0) return PD_ERR_INVALID_ARG;
    pd_init();
    CancelToken tok;

    std::string range;
    if (cidr) {
        range = cidr;
    } else {
        pd_interface f{};
        if (pd_default_interface(&f) != PD_OK) return PD_ERR_NOT_FOUND;
        range = std::string(f.ip) + "/" + std::to_string(f.prefix_len < 16 ? 16 : f.prefix_len);
    }

    Shared m;
    m.cb = cb;
    m.user = user;
    std::atomic<int> first_error{PD_OK};
    auto record = [&](int rc) {
        int expected = PD_OK;
        if (rc < 0 && rc != PD_ERR_UNSUPPORTED) first_error.compare_exchange_strong(expected, rc);
    };

    std::vector<std::thread> jobs;
    if (flags & PD_SCAN_ICMP) {
        uint32_t sweep_flags = ((flags & PD_SCAN_DNS) ? PD_SWEEP_RESOLVE_DNS : 0) |
                               ((flags & PD_SCAN_ARP_CACHE) ? PD_SWEEP_ARP_CACHE : 0);
        jobs.emplace_back([&, sweep_flags] {
            record(pd_sweep(range.c_str(), std::min(timeout_ms, 1000), 0, sweep_flags, &Shared::on_device, &m));
        });
    }
    if (flags & PD_SCAN_MDNS)
        jobs.emplace_back([&] { record(pd_mdns_discover(timeout_ms, &Shared::on_device, &m)); });
    if (flags & PD_SCAN_SSDP)
        jobs.emplace_back([&] { record(pd_ssdp_discover(timeout_ms, &Shared::on_device, &m)); });
    if (flags & PD_SCAN_ARP)
        jobs.emplace_back([&] { record(pd_arp_scan(nullptr, range.c_str(), std::min(timeout_ms, 2000), &Shared::on_device, &m)); });
    for (auto& t : jobs) t.join();

    // A cancel wins over partial results so callers can tell the two apart.
    if (tok.cancelled()) return PD_ERR_CANCELLED;
    // Otherwise partial results beat an error: only fail if nothing was found.
    if (m.merger.size() == 0 && first_error != PD_OK) return first_error;
    return static_cast<int>(m.merger.size());
}
