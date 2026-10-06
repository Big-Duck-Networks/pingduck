// Public C API: argument validation and the OUI registry. No network access.
#include <cstdio>
#include <fstream>
#include <string>

#include "check.hpp"
#include "pingduck/pingduck.h"

TEST("api: invalid arguments are rejected before any I/O") {
    CHECK_EQ(pd_ping("10.42.0.300", 100), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_ping("10.42.0.1", 0), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_ping(nullptr, 100), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_sweep("10.0.0.0/8", 100, 0, 0, nullptr, nullptr), PD_ERR_INVALID_ARG);  // wider than /16
    CHECK_EQ(pd_sweep("bogus", 100, 0, 0, nullptr, nullptr), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_sweep("10.42.0.0/24", 0, 0, 0, nullptr, nullptr), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_mdns_discover(0, nullptr, nullptr), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_ssdp_discover(-5, nullptr, nullptr), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_scan(nullptr, 0, PD_SCAN_DEFAULT, nullptr, nullptr), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_wake_on_lan("not-a-mac", nullptr), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_wake_on_lan("aa:bb:cc:dd:ee:ff", "300.1.1.1"), PD_ERR_INVALID_ARG);
    char buf[64];
    CHECK_EQ(pd_reverse_dns("nope", buf, sizeof(buf)), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_reverse_dns("10.42.0.1", buf, 0), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_arp_cache_lookup("nope", buf), PD_ERR_INVALID_ARG);
    uint16_t ports[1] = {80};
    uint8_t open[1];
    CHECK_EQ(pd_port_scan("10.42.0.1", ports, 0, 100, open), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_port_scan("10.42.0.1", ports, 1, 0, open), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_port_scan("host", ports, 1, 100, open), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_list_interfaces(nullptr, 4), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_default_interface(nullptr), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_oui_load(nullptr), PD_ERR_INVALID_ARG);
    CHECK_EQ(pd_oui_lookup("zz", buf, sizeof(buf)), PD_ERR_INVALID_ARG);
}

TEST("api: version and error strings") {
    CHECK(std::string(pd_version()).size() > 0);
    CHECK_EQ(std::string(pd_strerror(PD_ERR_CANCELLED)), std::string("cancelled"));
    CHECK_EQ(std::string(pd_strerror(12345)), std::string("unknown error"));
}

#if !defined(__ANDROID__)  // no writable temp dir guaranteed under adb
TEST("oui: longest prefix wins across MA-L, MA-M and MA-S") {
    std::string path = "pingduck_test_oui.csv";
    {
        std::ofstream f(path);
        f << "Registry,Assignment,Organization Name,Organization Address\n"
          << "MA-L,50C7BF,\"TP-LINK TECHNOLOGIES CO.,LTD.\",Shenzhen CN\n"
          << "MA-M,70B3D51,Small Maker,Somewhere\n"
          << "MA-S,70B3D5123,Tiny Maker,Elsewhere\n"
          << "MA-L,ZZZZZZ,Malformed,Nowhere\n"
          << "MA-L,-00001,Signed,Nowhere\n"
          << "MA-L,0x0001,Prefixed,Nowhere\n"
          << "garbage line\n";
    }
    CHECK_EQ(pd_oui_load(path.c_str()), 3);
    std::remove(path.c_str());

    char out[PD_VENDOR_LEN];
    REQUIRE(pd_oui_lookup("50:c7:bf:01:02:03", out, sizeof(out)) == PD_OK);
    CHECK_EQ(std::string(out), std::string("TP-LINK TECHNOLOGIES CO.,LTD."));
    REQUIRE(pd_oui_lookup("70:b3:d5:12:34:56", out, sizeof(out)) == PD_OK);
    CHECK_EQ(std::string(out), std::string("Tiny Maker"));
    REQUIRE(pd_oui_lookup("70:b3:d5:1f:00:00", out, sizeof(out)) == PD_OK);
    CHECK_EQ(std::string(out), std::string("Small Maker"));
    CHECK_EQ(pd_oui_lookup("00:11:22:33:44:55", out, sizeof(out)), PD_ERR_NOT_FOUND);

    REQUIRE(pd_oui_lookup("52:54:00:12:34:56", out, sizeof(out)) == PD_OK);
    CHECK_EQ(std::string(out), std::string("QEMU/KVM virtual NIC"));
    REQUIRE(pd_oui_lookup("da:a1:19:00:00:01", out, sizeof(out)) == PD_OK);
    CHECK_EQ(std::string(out), std::string("Private (randomized MAC)"));

    char tiny[5];
    REQUIRE(pd_oui_lookup("50:c7:bf:01:02:03", tiny, sizeof(tiny)) == PD_OK);
    CHECK_EQ(std::string(tiny), std::string("TP-L"));
    CHECK_EQ(pd_oui_load("does/not/exist.csv"), PD_ERR_NOT_FOUND);
}
#endif

int main(int argc, char** argv) { return check::run(argc, argv); }
