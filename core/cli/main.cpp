// pingduck CLI - exercises pingduck-core from the terminal (PRD Phase 1).
#include <pingduck/pingduck.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <tuple>
#include <vector>

namespace {

struct Options {
    std::vector<std::string> positional;
    int timeout_ms = -1;
    bool json = false;
    bool no_dns = false;
    bool arp = false;
    std::string iface;
    std::string oui;
};

void usage() {
    std::puts(
        "PingDuck core CLI\n"
        "\n"
        "usage: pingduck <command> [args] [options]\n"
        "\n"
        "commands:\n"
        "  info                     show interfaces and the chosen LAN interface\n"
        "  scan [cidr]              full scan: ICMP + mDNS + SSDP (+ ARP with --arp)\n"
        "  sweep [cidr]             ICMP ping sweep only\n"
        "  mdns                     mDNS / DNS-SD discovery only\n"
        "  ssdp                     SSDP / UPnP discovery only\n"
        "  arp [cidr]               raw ARP sweep via libpcap (root, Linux)\n"
        "  ping <ip> [count]        ping a single host\n"
        "  ports <ip> [port ...]    TCP connect scan (default: 21 22 80 443 3389)\n"
        "  wol <mac> [broadcast]    send a Wake-on-LAN magic packet\n"
        "  oui <mac>                vendor lookup (needs --oui)\n"
        "\n"
        "options:\n"
        "  -t, --timeout <ms>       per-method timeout\n"
        "  -j, --json               JSON lines output\n"
        "      --no-dns             skip reverse DNS during sweeps\n"
        "      --arp                include libpcap ARP in `scan`\n"
        "  -i, --iface <name>       interface for `arp`\n"
        "      --oui <oui.csv>      load IEEE OUI registry for vendor names");
}

std::string json_escape(const char* s) {
    std::string out;
    for (; *s; ++s) {
        unsigned char c = static_cast<unsigned char>(*s);
        if (c == '"' || c == '\\') out += '\\', out += static_cast<char>(c);
        else if (c < 0x20) {
            char buf[8];
            std::snprintf(buf, sizeof(buf), "\\u%04x", c);
            out += buf;
        } else out += static_cast<char>(c);
    }
    return out;
}

std::string sources_str(uint32_t s) {
    std::string out;
    auto add = [&](uint32_t bit, const char* name) {
        if (!(s & bit)) return;
        if (!out.empty()) out += '+';
        out += name;
    };
    add(PD_SRC_ICMP, "icmp");
    add(PD_SRC_ARP, "arp");
    add(PD_SRC_MDNS, "mdns");
    add(PD_SRC_SSDP, "ssdp");
    add(PD_SRC_DNS, "dns");
    return out;
}

struct Printer {
    bool json;
    bool live;  // print each callback immediately (otherwise collect + table)
    std::vector<pd_device> devices;

    static void on_device(const pd_device* d, void* self) {
        auto* p = static_cast<Printer*>(self);
        auto it = std::find_if(p->devices.begin(), p->devices.end(),
                               [&](const pd_device& x) { return std::strcmp(x.ip, d->ip) == 0; });
        bool is_new = it == p->devices.end();
        if (is_new) p->devices.push_back(*d);
        else *it = *d;
        if (p->json) p->print_json(*d);
        else if (p->live) std::printf("  %c %-15s %s\n", is_new ? '+' : '~', d->ip, d->hostname);
        std::fflush(stdout);
    }

    void print_json(const pd_device& d) const {
        std::printf(
            "{\"ip\":\"%s\",\"mac\":\"%s\",\"hostname\":\"%s\",\"vendor\":\"%s\",\"model\":\"%s\","
            "\"services\":\"%s\",\"rtt_ms\":%d,\"sources\":\"%s\"}\n",
            d.ip, d.mac, json_escape(d.hostname).c_str(), json_escape(d.vendor).c_str(),
            json_escape(d.model).c_str(), json_escape(d.services).c_str(), d.rtt_ms, sources_str(d.sources).c_str());
    }

    void print_table() {
        if (json) return;
        std::sort(devices.begin(), devices.end(), [](const pd_device& a, const pd_device& b) {
            unsigned a1, a2, a3, a4, b1, b2, b3, b4;
            std::sscanf(a.ip, "%u.%u.%u.%u", &a1, &a2, &a3, &a4);
            std::sscanf(b.ip, "%u.%u.%u.%u", &b1, &b2, &b3, &b4);
            return std::make_tuple(a1, a2, a3, a4) < std::make_tuple(b1, b2, b3, b4);
        });
        std::printf("\n%-15s  %-17s  %6s  %-28s  %-24s  %-22s  %s\n", "IP", "MAC", "RTT", "HOSTNAME", "VENDOR",
                    "MODEL", "SOURCES / SERVICES");
        for (auto& d : devices) {
            char rtt[16] = "-";
            if (d.rtt_ms >= 0) std::snprintf(rtt, sizeof(rtt), "%dms", d.rtt_ms);
            std::printf("%-15s  %-17s  %6s  %-28.28s  %-24.24s  %-22.22s  %s %s\n", d.ip, d.mac[0] ? d.mac : "-", rtt,
                        d.hostname[0] ? d.hostname : "-", d.vendor[0] ? d.vendor : "-", d.model[0] ? d.model : "-",
                        sources_str(d.sources).c_str(), d.services);
        }
    }
};

int fail(int rc) {
    std::fprintf(stderr, "error: %s (%d)\n", pd_strerror(rc), rc);
    return 1;
}

const char* opt_cidr(const Options& o, size_t idx) {
    return o.positional.size() > idx ? o.positional[idx].c_str() : nullptr;
}

std::string default_cidr() {
    pd_interface f{};
    if (pd_default_interface(&f) != PD_OK) return {};
    return std::string(f.ip) + "/" + std::to_string(f.prefix_len < 16 ? 16 : f.prefix_len);
}

double seconds_since(std::chrono::steady_clock::time_point t) {
    return std::chrono::duration<double>(std::chrono::steady_clock::now() - t).count();
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2) {
        usage();
        return 1;
    }
    std::string cmd = argv[1];
    Options o;
    for (int i = 2; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : ""; };
        if (a == "-t" || a == "--timeout") o.timeout_ms = std::atoi(next().c_str());
        else if (a == "-j" || a == "--json") o.json = true;
        else if (a == "--no-dns") o.no_dns = true;
        else if (a == "--arp") o.arp = true;
        else if (a == "-i" || a == "--iface") o.iface = next();
        else if (a == "--oui") o.oui = next();
        else o.positional.push_back(a);
    }

    if (pd_init() != PD_OK) return fail(PD_ERR_SOCKET);
    if (!o.oui.empty()) {
        int n = pd_oui_load(o.oui.c_str());
        if (n < 0) return fail(n);
        if (!o.json) std::fprintf(stderr, "loaded %d OUI entries\n", n);
    }

    auto t0 = std::chrono::steady_clock::now();
    Printer pr{o.json, !o.json};

    if (cmd == "info") {
        std::printf("pingduck-core %s\n\n", pd_version());
        pd_interface list[32];
        int n = pd_list_interfaces(list, 32);
        for (int i = 0; i < n; ++i)
            std::printf("  %-36.36s %s/%u  gw=%s  dns=%s  mac=%s\n", list[i].name, list[i].ip, list[i].prefix_len,
                        list[i].gateway[0] ? list[i].gateway : "-", list[i].dns[0] ? list[i].dns : "-",
                        list[i].mac[0] ? list[i].mac : "-");
        pd_interface f{};
        if (pd_default_interface(&f) == PD_OK)
            std::printf("\nLAN interface: %s (%s/%u, broadcast %s)\n", f.name, f.ip, f.prefix_len, f.broadcast);
        return 0;
    }

    if (cmd == "scan" || cmd == "sweep" || cmd == "mdns" || cmd == "ssdp" || cmd == "arp") {
        int rc;
        std::string cidr = opt_cidr(o, 0) ? opt_cidr(o, 0) : default_cidr();
        if (cmd == "scan") {
            uint32_t flags = PD_SCAN_DEFAULT | (o.arp ? PD_SCAN_ARP : 0u);
            if (o.no_dns) flags &= ~PD_SCAN_DNS;
            if (!o.json) std::printf("scanning %s (icmp+mdns+ssdp%s)...\n", cidr.c_str(), o.arp ? "+arp" : "");
            rc = pd_scan(cidr.c_str(), o.timeout_ms > 0 ? o.timeout_ms : 3000, flags, &Printer::on_device, &pr);
        } else if (cmd == "sweep") {
            uint32_t flags = PD_SWEEP_ARP_CACHE | (o.no_dns ? 0u : PD_SWEEP_RESOLVE_DNS);
            if (!o.json) std::printf("sweeping %s...\n", cidr.c_str());
            rc = pd_sweep(cidr.c_str(), o.timeout_ms > 0 ? o.timeout_ms : 1000, 0, flags, &Printer::on_device, &pr);
        } else if (cmd == "mdns") {
            rc = pd_mdns_discover(o.timeout_ms > 0 ? o.timeout_ms : 3000, &Printer::on_device, &pr);
        } else if (cmd == "ssdp") {
            rc = pd_ssdp_discover(o.timeout_ms > 0 ? o.timeout_ms : 3000, &Printer::on_device, &pr);
        } else {
            rc = pd_arp_scan(o.iface.empty() ? nullptr : o.iface.c_str(), opt_cidr(o, 0),
                             o.timeout_ms > 0 ? o.timeout_ms : 2000, &Printer::on_device, &pr);
        }
        if (rc < 0) return fail(rc);
        pr.print_table();
        if (!o.json) std::printf("\n%d device(s) in %.2fs\n", rc, seconds_since(t0));
        return 0;
    }

    if (cmd == "ping") {
        if (o.positional.empty()) return usage(), 1;
        int count = o.positional.size() > 1 ? std::atoi(o.positional[1].c_str()) : 4;
        int ok = 0;
        for (int i = 0; i < count; ++i) {
            int rtt = pd_ping(o.positional[0].c_str(), o.timeout_ms > 0 ? o.timeout_ms : 1000);
            if (rtt >= 0) ++ok, std::printf("reply from %s: time=%dms\n", o.positional[0].c_str(), rtt);
            else std::printf("%s: %s\n", o.positional[0].c_str(), pd_strerror(rtt));
        }
        return ok ? 0 : 1;
    }

    if (cmd == "ports") {
        if (o.positional.empty()) return usage(), 1;
        std::vector<uint16_t> ports;
        for (size_t i = 1; i < o.positional.size(); ++i)
            ports.push_back(static_cast<uint16_t>(std::atoi(o.positional[i].c_str())));
        if (ports.empty()) ports = {21, 22, 80, 443, 3389};
        std::vector<uint8_t> open(ports.size());
        int rc = pd_port_scan(o.positional[0].c_str(), ports.data(), static_cast<int>(ports.size()),
                              o.timeout_ms > 0 ? o.timeout_ms : 800, open.data());
        if (rc < 0) return fail(rc);
        for (size_t i = 0; i < ports.size(); ++i) std::printf("  %5u/tcp  %s\n", ports[i], open[i] ? "open" : "closed");
        std::printf("%d open\n", rc);
        return 0;
    }

    if (cmd == "wol") {
        if (o.positional.empty()) return usage(), 1;
        int rc = pd_wake_on_lan(o.positional[0].c_str(), opt_cidr(o, 1));
        if (rc < 0) return fail(rc);
        std::printf("magic packet sent to %s\n", o.positional[0].c_str());
        return 0;
    }

    if (cmd == "oui") {
        if (o.positional.empty()) return usage(), 1;
        char vendor[PD_VENDOR_LEN];
        int rc = pd_oui_lookup(o.positional[0].c_str(), vendor, sizeof(vendor));
        if (rc < 0) return fail(rc);
        std::printf("%s\n", vendor);
        return 0;
    }

    usage();
    return 1;
}
