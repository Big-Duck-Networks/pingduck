// Unit tests for the packet, text and file parsers. No network access.
#include <chrono>
#include <sstream>

#include "check.hpp"
#include "dns.hpp"
#include "dns_builder.hpp"
#include "parsers.hpp"

using namespace pd;
using testdns::Message;

namespace {

std::vector<pd_device> mdns_devices(const std::vector<std::pair<Message, std::string>>& packets) {
    mdns::Collector c;
    for (auto& [m, src] : packets) c.parse(m.bytes.data(), m.bytes.size(), src);
    return c.devices();
}

}  // namespace

// ---- DNS wire format -------------------------------------------------------

TEST("dns: query round-trips through Reader") {
    auto q = dns::build_query({"_http._tcp.local", "_ssh._tcp.local"}, dns::kTypePTR, 0x1234, true);
    dns::Reader r{q.data(), q.size()};
    uint16_t id, flags, qd, an, ns, ar;
    REQUIRE(r.u16(id) && r.u16(flags) && r.u16(qd) && r.u16(an) && r.u16(ns) && r.u16(ar));
    CHECK_EQ(id, 0x1234);
    CHECK_EQ(qd, 2);
    std::string name;
    uint16_t type, cls;
    REQUIRE(r.name(name) && r.u16(type) && r.u16(cls));
    CHECK_EQ(name, std::string("_http._tcp.local"));
    CHECK_EQ(type, dns::kTypePTR);
    CHECK_EQ(cls, 0x8001);  // QU bit + IN
    REQUIRE(r.name(name));
    CHECK_EQ(name, std::string("_ssh._tcp.local"));
}

TEST("dns: compressed names follow pointers") {
    // "foo.local" at offset 0, then "bar" + pointer to "local" (offset 4).
    std::vector<uint8_t> msg = {3, 'f', 'o', 'o', 5, 'l', 'o', 'c', 'a', 'l', 0, 3, 'b', 'a', 'r', 0xC0, 4};
    dns::Reader r{msg.data(), msg.size()};
    size_t pos = 11;
    std::string out;
    REQUIRE(r.name_at(pos, out));
    CHECK_EQ(out, std::string("bar.local"));
    CHECK_EQ(pos, msg.size());  // advanced past the pointer only
}

TEST("dns: pointer loops and overruns are rejected") {
    std::vector<uint8_t> loop = {0xC0, 0x00};
    dns::Reader r{loop.data(), loop.size()};
    std::string out;
    CHECK(!r.name(out));

    std::vector<uint8_t> past = {0xC0, 0x40};
    dns::Reader r2{past.data(), past.size()};
    CHECK(!r2.name(out));

    std::vector<uint8_t> label = {10, 'a', 'b'};
    dns::Reader r3{label.data(), label.size()};
    CHECK(!r3.name(out));

    std::vector<uint8_t> half = {0xC0};
    dns::Reader r4{half.data(), half.size()};
    CHECK(!r4.name(out));
}

TEST("dns: ptr_name reverses octets") {
    CHECK_EQ(dns::ptr_name("10.42.0.5"), std::string("5.0.42.10.in-addr.arpa"));
    CHECK_EQ(dns::ptr_name("not an ip"), std::string());
}

TEST("dns: find_ptr_answer matches the question") {
    Message m(0x8580);
    m.question("5.0.42.10.in-addr.arpa", dns::kTypePTR);
    m.ptr("5.0.42.10.in-addr.arpa", "nas.lan");
    CHECK_EQ(dns::find_ptr_answer(m.bytes.data(), m.bytes.size(), "5.0.42.10.in-addr.arpa"), std::string("nas.lan"));
    CHECK_EQ(dns::find_ptr_answer(m.bytes.data(), m.bytes.size(), "6.0.42.10.in-addr.arpa"), std::string());

    Message query(0x0100);  // QR clear: a query, not an answer
    query.ptr("5.0.42.10.in-addr.arpa", "nas.lan");
    CHECK_EQ(dns::find_ptr_answer(query.bytes.data(), query.bytes.size(), "5.0.42.10.in-addr.arpa"), std::string());

    auto cut = m.bytes;
    cut.resize(cut.size() - 3);
    CHECK_EQ(dns::find_ptr_answer(cut.data(), cut.size(), "5.0.42.10.in-addr.arpa"), std::string());
}

namespace {

// NBSTAT response with the given (name, suffix, flags) entries.
std::vector<uint8_t> nbstat_response(const std::vector<std::tuple<std::string, int, int>>& names) {
    std::vector<uint8_t> m = {0x12, 0x34, 0x84, 0x00, 0, 0, 0, 1, 0, 0, 0, 0, 0x20, 'C', 'K'};
    m.insert(m.end(), 30, 'A');
    m.insert(m.end(), {0, 0x00, 0x21, 0x00, 0x01, 0, 0, 0, 0});
    size_t rdlen_at = m.size();
    m.insert(m.end(), {0, 0});
    size_t rd_start = m.size();
    m.push_back(static_cast<uint8_t>(names.size()));
    for (auto& [name, suffix, flags] : names) {
        std::string padded = name;
        padded.resize(15, ' ');
        m.insert(m.end(), padded.begin(), padded.end());
        m.push_back(static_cast<uint8_t>(suffix));
        m.push_back(static_cast<uint8_t>(flags));
        m.push_back(0);
    }
    m.insert(m.end(), 6, 0xAB);  // unit id (MAC)
    size_t rdlen = m.size() - rd_start;
    m[rdlen_at] = static_cast<uint8_t>(rdlen >> 8);
    m[rdlen_at + 1] = static_cast<uint8_t>(rdlen);
    return m;
}

}  // namespace

TEST("nbstat: first unique workstation name wins") {
    auto m = nbstat_response({{"WORKGROUP", 0x00, 0x80}, {"DESKTOP-7Q2", 0x20, 0x00}, {"DESKTOP-7Q2", 0x00, 0x00}});
    CHECK_EQ(dns::parse_nbstat(m.data(), m.size()), std::string("DESKTOP-7Q2"));

    auto groups = nbstat_response({{"WORKGROUP", 0x00, 0x80}});
    CHECK_EQ(dns::parse_nbstat(groups.data(), groups.size()), std::string());
}

TEST("nbstat: name count beyond the buffer is safe") {
    auto m = nbstat_response({{"HOST", 0x00, 0x00}});
    size_t count_at = m.size() - 6 - 18 - 1;
    m[count_at] = 200;
    CHECK_EQ(dns::parse_nbstat(m.data(), m.size()), std::string("HOST"));
    m.resize(count_at + 10);
    CHECK_EQ(dns::parse_nbstat(m.data(), m.size()), std::string());
}

// ---- mDNS ------------------------------------------------------------------

TEST("mdns: chromecast-style announcement resolves via SRV and A") {
    Message m;
    m.ptr("_googlecast._tcp.local", "Chromecast-6c1d._googlecast._tcp.local");
    m.srv("Chromecast-6c1d._googlecast._tcp.local", "6c1d2f3a-9b8e-4c5d-a6b7-c8d9e0f1a2b3.local", 8009);
    m.txt("Chromecast-6c1d._googlecast._tcp.local", {"id=6c1d", "md=Chromecast HD", "fn=Living Room TV", "ca="});
    m.a("6c1d2f3a-9b8e-4c5d-a6b7-c8d9e0f1a2b3.local", "10.42.0.20");
    auto devs = mdns_devices({{m, "10.42.0.20"}});
    REQUIRE(devs.size() == 1);
    CHECK_EQ(std::string(devs[0].ip), std::string("10.42.0.20"));
    CHECK_EQ(std::string(devs[0].hostname), std::string("Living Room TV"));
    CHECK_EQ(std::string(devs[0].model), std::string("Chromecast HD"));
    CHECK_EQ(std::string(devs[0].services), std::string("_googlecast._tcp"));
    CHECK_EQ(devs[0].sources, PD_SRC_MDNS);
}

TEST("mdns: records announced by a proxy go to the real host") {
    Message m;  // the router answers on behalf of a sleeping Mac
    m.ptr("_smb._tcp.local", "studio._smb._tcp.local");
    m.srv("studio._smb._tcp.local", "studio.local", 445);
    m.a("studio.local", "10.42.0.30");
    auto devs = mdns_devices({{m, "10.42.0.1"}});
    REQUIRE(devs.size() == 1);
    CHECK_EQ(std::string(devs[0].ip), std::string("10.42.0.30"));
    CHECK_EQ(std::string(devs[0].hostname), std::string("studio"));
}

TEST("mdns: link-local addresses lose to routable ones") {
    Message m;
    m.ptr("_ipp._tcp.local", "Office Printer._ipp._tcp.local");
    m.srv("Office Printer._ipp._tcp.local", "printer.local", 631);
    m.txt("Office Printer._ipp._tcp.local", {"usb_MFG=Brother", "usb_MDL=HL-L2350DW"});
    m.a("printer.local", "169.254.10.11");
    m.a("printer.local", "10.42.0.40");
    auto devs = mdns_devices({{m, "10.42.0.99"}});
    REQUIRE(devs.size() == 1);
    CHECK_EQ(std::string(devs[0].ip), std::string("10.42.0.40"));
    CHECK_EQ(std::string(devs[0].vendor), std::string("Brother"));
    CHECK_EQ(std::string(devs[0].model), std::string("HL-L2350DW"));
}

TEST("mdns: uuid host names fall back to the instance name") {
    Message m;
    m.ptr("_hap._tcp.local", "Hallway Sensor._hap._tcp.local");
    m.srv("Hallway Sensor._hap._tcp.local", "0a1b2c3d4e5f60718293a4b5c6d7e8f9.local", 80);
    m.a("0a1b2c3d4e5f60718293a4b5c6d7e8f9.local", "10.42.0.41");
    auto devs = mdns_devices({{m, "10.42.0.41"}});
    REQUIRE(devs.size() == 1);
    CHECK_EQ(std::string(devs[0].hostname), std::string("Hallway Sensor"));
}

TEST("mdns: service enumeration queues follow-up types") {
    Message m;
    m.ptr("_services._dns-sd._udp.local", "_sonos._tcp.local");
    m.ptr("_services._dns-sd._udp.local", "_spotify-connect._tcp.local");
    mdns::Collector c;
    c.parse(m.bytes.data(), m.bytes.size(), "10.42.0.50");
    CHECK_EQ(c.new_types.size(), size_t{2});
    CHECK(c.new_types.count("_sonos._tcp.local") == 1);
}

TEST("mdns: reverse PTR names hosts, junk arpa names are dropped") {
    Message m;
    m.ptr("51.0.42.10.in-addr.arpa", "pve.local");
    m.ptr("1.2.3.4.5.in-addr.arpa", "junk.local");
    m.ptr("x.y.z.w.in-addr.arpa", "junk2.local");
    mdns::Collector c;
    c.parse(m.bytes.data(), m.bytes.size(), "10.42.0.51");
    CHECK_EQ(c.rdns.size(), size_t{1});
    auto devs = c.devices();
    REQUIRE(devs.size() == 1);
    CHECK_EQ(std::string(devs[0].ip), std::string("10.42.0.51"));
    CHECK_EQ(std::string(devs[0].hostname), std::string("pve"));
}

TEST("mdns: queries are ignored") {
    Message q(0x0000);
    q.ptr("_http._tcp.local", "x._http._tcp.local");
    CHECK(mdns_devices({{q, "10.42.0.2"}}).empty());
}

TEST("mdns: flooding stops at the record cap") {
    mdns::Collector c;
    for (int batch = 0; batch < 200; ++batch) {
        Message m;
        for (int i = 0; i < 60; ++i)
            m.ptr("_http._tcp.local", "host" + std::to_string(batch) + "-" + std::to_string(i) + "._http._tcp.local");
        c.parse(m.bytes.data(), m.bytes.size(), "10.42.0.66");
    }
    CHECK(c.instances.size() <= 8192 + 60);
}

TEST("mdns: TXT with an oversized length byte is contained") {
    Message m;
    m.ptr("_http._tcp.local", "web._http._tcp.local");
    m.record("web._http._tcp.local", dns::kTypeTXT, {200, 'a', '=', 'b'});
    auto devs = mdns_devices({{m, "10.42.0.7"}});
    REQUIRE(devs.size() == 1);
    CHECK_EQ(std::string(devs[0].services), std::string("_http._tcp"));
}

// ---- SSDP / UPnP -----------------------------------------------------------

TEST("ssdp: headers are case-insensitive and trimmed") {
    auto h = ssdp::parse_headers(
        "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nLocation:  http://10.42.0.1:1900/igd.xml \r\n"
        "st: upnp:rootdevice\r\n\r\n");
    CHECK_EQ(h["location"], std::string("http://10.42.0.1:1900/igd.xml"));
    CHECK_EQ(h["st"], std::string("upnp:rootdevice"));
    CHECK_EQ(h["cache-control"], std::string("max-age=1800"));
}

TEST("ssdp: short_type") {
    CHECK_EQ(ssdp::short_type("urn:schemas-upnp-org:device:MediaRenderer:1"), std::string("upnp:MediaRenderer"));
    CHECK_EQ(ssdp::short_type("urn:dial-multiscreen-org:service:dial:1"), std::string("upnp:dial"));
    CHECK_EQ(ssdp::short_type("upnp:rootdevice"), std::string());
}

TEST("ssdp: xml_tag handles prefixes, entities and lookalikes") {
    std::string xml =
        "<?xml version=\"1.0\"?><root xmlns=\"urn:schemas-upnp-org:device-1-0\">"
        "<device><deviceType>urn:schemas-upnp-org:device:InternetGatewayDevice:1</deviceType>"
        "<myfriendlyName>wrong</myfriendlyName>"
        "<dev:friendlyName> Archer &amp; Co &amp;lt;3 </dev:friendlyName>"
        "<manufacturer>TP-Link</manufacturer><modelName attr=\"x\">skipped</modelName></device></root>";
    CHECK_EQ(ssdp::xml_tag(xml, "friendlyName"), std::string("Archer & Co &lt;3"));
    CHECK_EQ(ssdp::xml_tag(xml, "manufacturer"), std::string("TP-Link"));
    CHECK_EQ(ssdp::xml_tag(xml, "modelName"), std::string());
    CHECK_EQ(ssdp::xml_tag(xml, "missing"), std::string());
    CHECK_EQ(ssdp::xml_tag("<a>unterminated", "a"), std::string());
    CHECK_EQ(ssdp::xml_tag("", "a"), std::string());
}

TEST("ssdp: xml_tag stays linear on hostile input") {
    std::string hostile;
    while (hostile.size() < 256 * 1024) hostile += "friendlyName>";
    std::string many_lt(256 * 1024, '<');
    auto start = std::chrono::steady_clock::now();
    CHECK_EQ(ssdp::xml_tag(hostile, "friendlyName"), std::string());
    CHECK_EQ(ssdp::xml_tag(many_lt, "friendlyName"), std::string());
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
    CHECK(ms < 500);
}

TEST("ssdp: note_response prefers the root device location") {
    ssdp::Responder r;
    CHECK(ssdp::note_response("HTTP/1.1 200 OK\r\nST: urn:schemas-upnp-org:service:WANIPConnection:1\r\n"
                              "LOCATION: http://10.42.0.1/wan.xml\r\nSERVER: Linux UPnP/1.0\r\n\r\n", r));
    CHECK(ssdp::note_response("HTTP/1.1 200 OK\r\nST: upnp:rootdevice\r\nLOCATION: http://10.42.0.1/root.xml\r\n\r\n", r));
    CHECK(ssdp::note_response("NOTIFY * HTTP/1.1\r\nNT: urn:schemas-upnp-org:device:WANDevice:1\r\n"
                              "LOCATION: http://10.42.0.1/other.xml\r\n\r\n", r));
    CHECK(!ssdp::note_response("M-SEARCH * HTTP/1.1\r\nST: ssdp:all\r\n\r\n", r));
    CHECK_EQ(r.location, std::string("http://10.42.0.1/root.xml"));
    CHECK_EQ(r.server, std::string("Linux UPnP/1.0"));
    CHECK_EQ(r.types.size(), size_t{2});
}

TEST("ssdp: apply_description builds name, vendor and model") {
    ssdp::Responder r;
    r.server = "Linux/4.9 UPnP/1.0 Roku/12";
    r.types = {"upnp:dial"};
    pd_device d = make_device("10.42.0.25");
    ssdp::apply_description(
        "<root><device><deviceType>urn:roku-com:device:player:1-0</deviceType><friendlyName>Bedroom Roku"
        "</friendlyName><manufacturer>Roku</manufacturer><modelName>Roku Express</modelName>"
        "<modelNumber>3930X</modelNumber></device></root>",
        r, d);
    CHECK_EQ(std::string(d.hostname), std::string("Bedroom Roku"));
    CHECK_EQ(std::string(d.vendor), std::string("Roku"));
    CHECK_EQ(std::string(d.model), std::string("Roku Express 3930X"));
    CHECK_EQ(std::string(d.services), std::string("upnp:dial,upnp:player"));

    pd_device bare = make_device("10.42.0.26");
    ssdp::apply_description("", r, bare);
    CHECK_EQ(std::string(bare.model), r.server);
}

// ---- ICMP / ARP / procfs ---------------------------------------------------

TEST("icmp: echo replies with and without an IP header") {
    uint8_t bare[8] = {0, 0, 0xAA, 0xBB, 0x12, 0x34, 0x00, 0x07};
    uint16_t id = 0, seq = 0;
    REQUIRE(parse_echo_reply(bare, sizeof(bare), &id, &seq));
    CHECK_EQ(id, 0x1234);
    CHECK_EQ(seq, 7);

    uint8_t with_ip[28] = {0x45};
    std::memcpy(with_ip + 20, bare, 8);
    REQUIRE(parse_echo_reply(with_ip, sizeof(with_ip), &id, &seq));
    CHECK_EQ(seq, 7);

    CHECK(!parse_echo_reply(with_ip, 27, &id, &seq));       // truncated
    uint8_t bad_ihl[28] = {0x41};
    CHECK(!parse_echo_reply(bad_ihl, sizeof(bad_ihl), &id, &seq));
    uint8_t request[8] = {8, 0, 0, 0, 0, 1, 0, 1};
    CHECK(!parse_echo_reply(request, sizeof(request), &id, &seq));
    uint8_t unreachable[8] = {3, 1, 0, 0, 0, 0, 0, 0};
    CHECK(!parse_echo_reply(unreachable, sizeof(unreachable), &id, &seq));
    CHECK(!parse_echo_reply(bare, 0, &id, &seq));
}

TEST("arp: request frame layout and reply parsing") {
    const uint8_t mac[6] = {0x02, 0x11, 0x22, 0x33, 0x44, 0x55};
    uint8_t frame[42];
    build_arp_request(frame, mac, 0x0A2A0005, 0x0A2A0001);
    for (int i = 0; i < 6; ++i) CHECK_EQ(frame[i], 0xFF);
    CHECK_EQ(frame[21], 1);
    CHECK_EQ(frame[41], 1);

    uint32_t ip;
    uint8_t got[6];
    CHECK(!parse_arp_reply(frame, sizeof(frame), &ip, got));  // a request, not a reply
    frame[21] = 2;
    REQUIRE(parse_arp_reply(frame, sizeof(frame), &ip, got));
    CHECK_EQ(ip, 0x0A2A0005u);
    CHECK(std::memcmp(got, mac, 6) == 0);
    CHECK(!parse_arp_reply(frame, 41, &ip, got));
    frame[13] = 0x00;  // IPv4 ethertype
    CHECK(!parse_arp_reply(frame, sizeof(frame), &ip, got));
}

TEST("procfs: /proc/net/arp lookup") {
    std::istringstream arp(
        "IP address       HW type     Flags       HW address            Mask     Device\n"
        "10.42.0.1        0x1         0x2         50:c7:bf:aa:bb:cc     *        eth0\n"
        "10.42.0.9        0x1         0x0         00:00:00:00:00:00     *        eth0\n"
        "10.42.0.10       0x1         0x2         00:00:00:00:00:00     *        eth0\n");
    CHECK_EQ(proc_arp_lookup(arp, "10.42.0.1"), std::string("50:c7:bf:aa:bb:cc"));
    arp.clear(), arp.seekg(0);
    CHECK_EQ(proc_arp_lookup(arp, "10.42.0.9"), std::string());
    arp.clear(), arp.seekg(0);
    CHECK_EQ(proc_arp_lookup(arp, "10.42.0.10"), std::string());
}

TEST("procfs: /proc/net/route default gateway") {
    std::istringstream route(
        "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n"
        "eth0\t00002A0A\t00000000\t0001\t0\t0\t0\t00FFFFFF\t0\t0\t0\n"
        "eth0\t00000000\t01002A0A\t0003\t0\t0\t0\t00000000\t0\t0\t0\n"
        "wlan0\t00000000\tzz002A0A\t0003\t0\t0\t0\t00000000\t0\t0\t0\n");
    // The kernel prints the address as a native-endian integer.
    uint32_t probe = 1;
    bool little = *reinterpret_cast<uint8_t*>(&probe) == 1;
    CHECK_EQ(proc_route_gateway(route, "eth0"), std::string(little ? "10.42.0.1" : "1.0.42.10"));
    route.clear(), route.seekg(0);
    CHECK_EQ(proc_route_gateway(route, "wlan0"), std::string());
}

// ---- Small helpers ----------------------------------------------------------

TEST("util: parse_cidr") {
    uint32_t net;
    uint8_t prefix;
    REQUIRE(parse_cidr("10.42.0.77/24", &net, &prefix));
    CHECK_EQ(ipv4_to_string(net), std::string("10.42.0.0"));
    CHECK_EQ(prefix, 24);
    REQUIRE(parse_cidr("10.42.0.77", &net, &prefix));
    CHECK_EQ(prefix, 32);
    REQUIRE(parse_cidr("0.0.0.0/0", &net, &prefix));
    CHECK_EQ(prefix, 0);
    CHECK(!parse_cidr("10.42.0.0/33", &net, &prefix));
    CHECK(!parse_cidr("10.42.0.0/", &net, &prefix));
    CHECK(!parse_cidr("10.42.0.0/24abc", &net, &prefix));
    CHECK(!parse_cidr("10.42.0.0/-1", &net, &prefix));
    CHECK(!parse_cidr("10.42.0/24", &net, &prefix));
    CHECK(!parse_cidr(nullptr, &net, &prefix));
}

TEST("util: parse_mac accepts common notations only") {
    uint8_t m[6];
    REQUIRE(parse_mac("AA:bb:CC:dd:EE:ff", m));
    CHECK_EQ(mac_to_string(m), std::string("aa:bb:cc:dd:ee:ff"));
    CHECK(parse_mac("aa-bb-cc-dd-ee-ff", m));
    CHECK(parse_mac("aabb.ccdd.eeff", m));
    CHECK(parse_mac("aabbccddeeff", m));
    CHECK(!parse_mac("aabbccddeeff00", m));
    CHECK(!parse_mac("aa:bb:cc:dd:ee", m));
    CHECK(!parse_mac("aa:bb:cc:dd:ee:fg", m));
    CHECK(!parse_mac("", m));
    CHECK(!parse_mac(nullptr, m));
}

TEST("util: append_csv dedupes and respects capacity") {
    char buf[16] = "";
    append_csv(buf, sizeof(buf), "_ssh._tcp");
    append_csv(buf, sizeof(buf), "_ssh._tcp");
    CHECK_EQ(std::string(buf), std::string("_ssh._tcp"));
    append_csv(buf, sizeof(buf), "_ssh");  // prefix of an existing item is still new
    CHECK_EQ(std::string(buf), std::string("_ssh._tcp,_ssh"));
    append_csv(buf, sizeof(buf), "_toolong");  // would overflow: dropped whole
    CHECK_EQ(std::string(buf), std::string("_ssh._tcp,_ssh"));
}

TEST("util: split_csv handles quotes") {
    auto cols = split_csv("MA-L,286FB9,\"Nokia Shanghai Bell Co., Ltd.\",\"Say \"\"hi\"\"\"\r");
    REQUIRE(cols.size() == 4);
    CHECK_EQ(cols[2], std::string("Nokia Shanghai Bell Co., Ltd."));
    CHECK_EQ(cols[3], std::string("Say \"hi\""));
    CHECK_EQ(split_csv("").size(), size_t{1});
    auto first3 = split_csv("MA-L,50C7BF,\"TP-LINK, LTD.\",\"Address, with, commas\"", 3);
    REQUIRE(first3.size() == 3);
    CHECK_EQ(first3[2], std::string("TP-LINK, LTD."));
}

// ---- Merger -----------------------------------------------------------------

TEST("merger: first sight and new facts trigger updates, repeats do not") {
    DeviceMerger m;
    pd_device out;
    pd_device icmp = make_device("10.42.0.20");
    icmp.rtt_ms = 3;
    icmp.sources = PD_SRC_ICMP;
    CHECK(m.add(icmp, &out));
    CHECK(!m.add(icmp, &out));

    pd_device mdns = make_device("10.42.0.20");
    mdns.sources = PD_SRC_MDNS;
    copy_str(mdns.hostname, sizeof(mdns.hostname), std::string("Living Room TV"));
    copy_str(mdns.services, sizeof(mdns.services), std::string("_googlecast._tcp"));
    REQUIRE(m.add(mdns, &out));
    CHECK_EQ(std::string(out.hostname), std::string("Living Room TV"));
    CHECK_EQ(out.rtt_ms, 3);
    CHECK_EQ(out.sources, PD_SRC_ICMP | PD_SRC_MDNS);

    pd_device ssdp = make_device("10.42.0.20");
    ssdp.sources = PD_SRC_SSDP;
    copy_str(ssdp.hostname, sizeof(ssdp.hostname), std::string("Chromecast"));
    copy_str(ssdp.services, sizeof(ssdp.services), std::string("upnp:dial,_googlecast._tcp"));
    REQUIRE(m.add(ssdp, &out));
    CHECK_EQ(std::string(out.hostname), std::string("Living Room TV"));  // first name sticks
    CHECK_EQ(std::string(out.services), std::string("_googlecast._tcp,upnp:dial"));
    CHECK_EQ(m.size(), size_t{1});
}

TEST("merger: randomized-MAC placeholder yields to a real vendor only") {
    DeviceMerger m;
    pd_device out;
    pd_device a = make_device("10.42.0.33");
    copy_str(a.vendor, sizeof(a.vendor), std::string("Private (randomized MAC)"));
    copy_str(a.hostname, sizeof(a.hostname), std::string("Private-Server"));
    m.add(a, &out);

    pd_device b = make_device("10.42.0.33");
    copy_str(b.vendor, sizeof(b.vendor), std::string("Apple, Inc."));
    copy_str(b.hostname, sizeof(b.hostname), std::string("other-name"));
    REQUIRE(m.add(b, &out));
    CHECK_EQ(std::string(out.vendor), std::string("Apple, Inc."));
    CHECK_EQ(std::string(out.hostname), std::string("Private-Server"));

    pd_device c = make_device("10.42.0.33");
    copy_str(c.vendor, sizeof(c.vendor), std::string("Someone Else"));
    CHECK(!m.add(c, &out));
}
