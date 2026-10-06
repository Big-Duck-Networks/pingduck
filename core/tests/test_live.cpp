// Tests against the real LAN: cancellation of every discovery method, and
// back-to-back scans. Labelled "network" in ctest; CI runners skip them
// (`ctest -LE network`) because their networks are not representative.
//
// PINGDUCK_STRESS=1 adds a full /16 sweep (several minutes on Windows).
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <functional>
#include <set>
#include <string>
#include <thread>

#include "check.hpp"
#include "pingduck/pingduck.h"

namespace {

using Clock = std::chrono::steady_clock;

long long elapsed_ms(Clock::time_point since) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - since).count();
}

std::string lan_cidr() {
    pd_interface f{};
    if (pd_default_interface(&f) != PD_OK) return {};
    return std::string(f.ip) + "/" + std::to_string(f.prefix_len < 16 ? 16 : f.prefix_len);
}

// Starts `fn`, cancels after `cancel_after_ms`, and returns {rc, ms from cancel to return}.
std::pair<int, long long> cancel_during(const std::function<int()>& fn, int cancel_after_ms) {
    std::atomic<int> rc{1};
    Clock::time_point cancelled_at;
    std::thread t([&] { rc = fn(); });
    std::this_thread::sleep_for(std::chrono::milliseconds(cancel_after_ms));
    cancelled_at = Clock::now();
    pd_cancel();
    t.join();
    return {rc.load(), elapsed_ms(cancelled_at)};
}

}  // namespace

TEST("live: default interface looks like a LAN") {
    pd_interface f{};
    REQUIRE(pd_default_interface(&f) == PD_OK);
    CHECK(f.ip[0] != '\0');
    CHECK(f.prefix_len >= 8 && f.prefix_len <= 30);
}

// Bounds: a cancel is noticed between pings / poll ticks (<= 100 ms), but an
// in-flight blocking ping (Windows) or reverse lookup can take its timeout.
TEST("live: pd_cancel stops a sweep") {
    std::string cidr = lan_cidr();
    REQUIRE(!cidr.empty());
    auto [rc, ms] = cancel_during([&] { return pd_sweep(cidr.c_str(), 1000, 0, PD_SWEEP_RESOLVE_DNS, nullptr, nullptr); }, 150);
    CHECK_EQ(rc, PD_ERR_CANCELLED);
    CHECK(ms < 1700);
}

TEST("live: pd_cancel stops mDNS") {
    auto [rc, ms] = cancel_during([] { return pd_mdns_discover(5000, nullptr, nullptr); }, 300);
    CHECK_EQ(rc, PD_ERR_CANCELLED);
    CHECK(ms < 300);
}

TEST("live: pd_cancel stops SSDP") {
    auto [rc, ms] = cancel_during([] { return pd_ssdp_discover(5000, nullptr, nullptr); }, 300);
    CHECK_EQ(rc, PD_ERR_CANCELLED);
    CHECK(ms < 300);
}

TEST("live: pd_cancel stops a combined scan") {
    auto [rc, ms] = cancel_during([] { return pd_scan(nullptr, 5000, PD_SCAN_DEFAULT, nullptr, nullptr); }, 400);
    CHECK_EQ(rc, PD_ERR_CANCELLED);
    CHECK(ms < 2500);
}

TEST("live: pd_cancel stops a port scan") {
    // TEST-NET-1 is never routed, so every connect hangs until its timeout.
    uint16_t ports[256];
    for (int i = 0; i < 256; ++i) ports[i] = static_cast<uint16_t>(40000 + i);
    uint8_t open[256];
    auto [rc, ms] = cancel_during([&] { return pd_port_scan("192.0.2.1", ports, 256, 1500, open); }, 200);
    CHECK_EQ(rc, PD_ERR_CANCELLED);
    CHECK(ms < 1700);
}

TEST("live: a cancel does not leak into the next scan") {
    pd_cancel();
    std::string cidr = lan_cidr();
    int rc = pd_sweep(cidr.c_str(), 500, 0, 0, nullptr, nullptr);
    CHECK(rc > 0);
}

TEST("live: back-to-back scans stay consistent") {
    std::set<std::string> first;
    int counts[5];
    for (int run = 0; run < 5; ++run) {
        std::set<std::string> seen;
        auto collect = [](const pd_device* d, void* user) { static_cast<std::set<std::string>*>(user)->insert(d->ip); };
        auto start = Clock::now();
        counts[run] = pd_scan(nullptr, 2000, PD_SCAN_DEFAULT, collect, &seen);
        long long ms = elapsed_ms(start);
        std::printf("  run %d: %d devices in %lld ms\n", run, counts[run], ms);
        CHECK(counts[run] > 0);
        CHECK_EQ(static_cast<size_t>(counts[run]), seen.size());
        CHECK(ms < 15000);  // PRD: full scan under 15 s
        if (run == 0) first = seen;
    }
    // Phones and sleepy IoT come and go; the bulk of the LAN must not.
    for (int run = 1; run < 5; ++run) CHECK(counts[run] >= counts[0] * 8 / 10);
}

TEST("live: /16 sweep (PINGDUCK_STRESS=1)") {
    const char* stress = std::getenv("PINGDUCK_STRESS");
    if (!stress || std::string(stress) != "1") {
        std::printf("  skipped; set PINGDUCK_STRESS=1\n");
        return;
    }
    pd_interface f{};
    REQUIRE(pd_default_interface(&f) == PD_OK);
    std::string cidr = std::string(f.ip) + "/16";
    std::atomic<int> callbacks{0};
    auto count = [](const pd_device*, void* user) { ++*static_cast<std::atomic<int>*>(user); };
    auto start = Clock::now();
    int rc = pd_sweep(cidr.c_str(), 400, 0, 0, count, &callbacks);
    std::printf("  /16: %d live hosts in %lld ms\n", rc, elapsed_ms(start));
    CHECK(rc > 0);
    CHECK_EQ(rc, callbacks.load());
}

int main(int argc, char** argv) {
    pd_init();
    return check::run(argc, argv);
}
