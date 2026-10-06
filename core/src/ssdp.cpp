// SSDP (UPnP) discovery: M-SEARCH multicast, then fetch each responder's
// device description XML for friendlyName / manufacturer / modelName.
//
// Timing: replies are collected for `timeout_ms`, then description fetches
// run on a small worker pool, each capped at min(timeout_ms, 2000) ms.
#include <algorithm>
#include <cctype>
#include <map>
#include <thread>
#include <vector>

#include "net_util.hpp"
#include "parsers.hpp"
#include "platform.hpp"

using namespace pd;
using pd::ssdp::Responder;

namespace {

// More responders than this on one LAN means someone is spoofing replies.
constexpr size_t kMaxResponders = 512;
constexpr size_t kFetchWorkers = 16;

std::string lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

std::string trim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos) return {};
    size_t b = s.find_last_not_of(" \t\r\n");
    return s.substr(a, b - a + 1);
}

// Single pass, so "&amp;lt;" stays "&lt;".
std::string xml_unescape(const std::string& s) {
    static const std::pair<const char*, char> ents[] = {
        {"&amp;", '&'}, {"&lt;", '<'}, {"&gt;", '>'}, {"&quot;", '"'}, {"&apos;", '\''}};
    std::string out;
    out.reserve(s.size());
    for (size_t i = 0; i < s.size();) {
        bool matched = false;
        if (s[i] == '&') {
            for (auto& [from, to] : ents) {
                size_t len = std::strlen(from);
                if (s.compare(i, len, from) == 0) {
                    out += to;
                    i += len;
                    matched = true;
                    break;
                }
            }
        }
        if (!matched) out += s[i++];
    }
    return out;
}

// Minimal HTTP/1.0 GET for http:// URLs on `expected_host`. Returns the body or "".
std::string http_get(const std::string& url, const std::string& expected_host, int timeout_ms) {
    const std::string scheme = "http://";
    if (url.compare(0, scheme.size(), scheme) != 0) return {};
    std::string rest = url.substr(scheme.size());
    size_t slash = rest.find('/');
    std::string hostport = rest.substr(0, slash);
    std::string path = slash == std::string::npos ? "/" : rest.substr(slash);
    std::string host = hostport;
    uint16_t port = 80;
    size_t colon = hostport.find(':');
    if (colon != std::string::npos) {
        host = hostport.substr(0, colon);
        port = static_cast<uint16_t>(std::atoi(hostport.c_str() + colon + 1));
    }

    // Only fetch from the responder itself, so a LAN device cannot point the
    // scanner at an arbitrary host.
    if (host != expected_host) return {};

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    if (inet_pton(AF_INET, host.c_str(), &addr.sin_addr) != 1) return {};

    int64_t deadline = now_ms() + timeout_ms;
    Socket s(tcp_connect(addr, timeout_ms));
    if (!s.valid()) return {};

    std::string req = "GET " + path + " HTTP/1.0\r\nHost: " + hostport +
                      "\r\nUser-Agent: PingDuck/1.0 UPnP/1.1\r\nConnection: close\r\n\r\n";
    if (send(s.fd, req.data(), static_cast<int>(req.size()), 0) < 0) return {};

    std::string resp;
    char buf[4096];
    while (resp.size() < 256 * 1024) {
        int remaining = static_cast<int>(deadline - now_ms());
        if (remaining <= 0 || wait_readable(s.fd, remaining) <= 0) break;
        int n = static_cast<int>(recv(s.fd, buf, sizeof(buf), 0));
        if (n <= 0) break;
        resp.append(buf, static_cast<size_t>(n));
    }
    size_t body = resp.find("\r\n\r\n");
    return body == std::string::npos ? std::string() : resp.substr(body + 4);
}

}  // namespace

namespace pd::ssdp {

std::map<std::string, std::string> parse_headers(const std::string& msg) {
    std::map<std::string, std::string> h;
    size_t pos = msg.find("\r\n");
    while (pos != std::string::npos && pos + 2 < msg.size()) {
        size_t end = msg.find("\r\n", pos + 2);
        std::string line = msg.substr(pos + 2, end == std::string::npos ? std::string::npos : end - pos - 2);
        size_t colon = line.find(':');
        if (colon != std::string::npos) h[lower(trim(line.substr(0, colon)))] = trim(line.substr(colon + 1));
        pos = end;
    }
    return h;
}

std::string short_type(const std::string& st) {
    for (const char* kind : {":device:", ":service:"}) {
        size_t p = st.find(kind);
        if (p == std::string::npos) continue;
        std::string rest = st.substr(p + std::strlen(kind));
        size_t colon = rest.find(':');
        return "upnp:" + rest.substr(0, colon);
    }
    return {};
}

std::string xml_tag(const std::string& xml, const std::string& tag) {
    // One forward pass over '<' positions keeps this linear on hostile input.
    for (size_t open = xml.find('<'); open != std::string::npos; open = xml.find('<', open + 1)) {
        size_t name_end = xml.find_first_of("<> \t\r\n/", open + 1);
        if (name_end == std::string::npos) return {};
        if (xml[name_end] != '>' || name_end == open + 1) continue;
        size_t name_start = name_end;
        while (name_start > open + 1 && xml[name_start - 1] != ':') --name_start;
        if (xml.compare(name_start, name_end - name_start, tag) != 0 || name_end - name_start != tag.size()) continue;
        size_t start = name_end + 1;
        size_t close = xml.find("</", start);
        if (close == std::string::npos) return {};
        return trim(xml_unescape(xml.substr(start, close - start)));
    }
    return {};
}

bool note_response(const std::string& msg, Responder& r) {
    if (msg.compare(0, 8, "HTTP/1.1") != 0 && msg.compare(0, 6, "NOTIFY") != 0) return false;
    auto h = parse_headers(msg);
    std::string st = h.count("st") ? h["st"] : h["nt"];
    // Prefer the root device description; any LOCATION is better than none.
    if (h.count("location") && (r.location.empty() || st == "upnp:rootdevice")) r.location = h["location"];
    if (r.server.empty() && h.count("server")) r.server = h["server"];
    std::string t = short_type(st);
    if (!t.empty() && r.types.size() < 32 && std::find(r.types.begin(), r.types.end(), t) == r.types.end())
        r.types.push_back(t);
    return true;
}

void apply_description(const std::string& xml, const Responder& r, pd_device& d) {
    for (auto& t : r.types) append_csv(d.services, sizeof(d.services), t);
    std::string model = xml_tag(xml, "modelName");
    std::string number = xml_tag(xml, "modelNumber");
    if (!number.empty() && model.find(number) == std::string::npos) model += model.empty() ? number : " " + number;
    copy_str(d.hostname, sizeof(d.hostname), xml_tag(xml, "friendlyName"));
    copy_str(d.vendor, sizeof(d.vendor), xml_tag(xml, "manufacturer"));
    copy_str(d.model, sizeof(d.model), model.empty() ? r.server : model);
    append_csv(d.services, sizeof(d.services), short_type(xml_tag(xml, "deviceType")));
}

}  // namespace pd::ssdp

extern "C" int pd_ssdp_discover(int timeout_ms, pd_device_cb cb, void* user) {
    if (timeout_ms <= 0) return PD_ERR_INVALID_ARG;
    pd_init();
    CancelToken tok;

    Socket s(open_udp_socket(0, false));
    if (!s.valid()) return PD_ERR_SOCKET;
    set_multicast_defaults(s.fd);

    sockaddr_in group{};
    group.sin_family = AF_INET;
    group.sin_port = htons(1900);
    inet_pton(AF_INET, "239.255.255.250", &group.sin_addr);

    int mx = std::clamp(timeout_ms / 1000, 1, 5);
    auto msearch = [&](const char* st) {
        std::string m = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: " +
                        std::to_string(mx) + "\r\nST: " + st + "\r\nUSER-AGENT: PingDuck/1.0 UPnP/1.1\r\n\r\n";
        sendto(s.fd, m.data(), static_cast<int>(m.size()), 0, reinterpret_cast<sockaddr*>(&group), sizeof(group));
    };
    msearch("ssdp:all");
    msearch("upnp:rootdevice");

    std::map<std::string, Responder> found;
    int64_t start = now_ms();
    bool resent = false;
    char buf[2048];
    for (;;) {
        if (tok.cancelled()) return PD_ERR_CANCELLED;
        int64_t elapsed = now_ms() - start;
        if (elapsed >= timeout_ms) break;
        if (!resent && elapsed >= timeout_ms / 3) {
            msearch("ssdp:all");
            resent = true;
        }
        if (wait_readable(s.fd, 100) <= 0) continue;

        sockaddr_in from{};
        socklen_t fl = sizeof(from);
        int n = static_cast<int>(recvfrom(s.fd, buf, sizeof(buf) - 1, 0, reinterpret_cast<sockaddr*>(&from), &fl));
        if (n <= 0) continue;
        std::string ip = ipv4_to_string(ntohl(from.sin_addr.s_addr));
        if (found.size() >= kMaxResponders && !found.count(ip)) continue;
        Responder r = found.count(ip) ? found[ip] : Responder{};
        if (ssdp::note_response(std::string(buf, static_cast<size_t>(n)), r)) found[ip] = std::move(r);
    }

    // Fetch device descriptions in parallel.
    std::vector<std::pair<std::string, Responder>> list(found.begin(), found.end());
    std::vector<pd_device> devices(list.size());
    std::atomic<size_t> next{0};
    std::vector<std::thread> pool;
    int fetch_ms = std::min(timeout_ms, 2000);
    for (size_t w = 0; w < std::min(list.size(), kFetchWorkers); ++w) {
        pool.emplace_back([&] {
            for (size_t i = next++; i < list.size() && !tok.cancelled(); i = next++) {
                const auto& [ip, r] = list[i];
                pd_device& d = devices[i];
                d = make_device(ip);
                d.sources = PD_SRC_SSDP;
                std::string xml = r.location.empty() ? std::string() : http_get(r.location, ip, fetch_ms);
                ssdp::apply_description(xml, r, d);
            }
        });
    }
    for (auto& t : pool) t.join();
    if (tok.cancelled()) return PD_ERR_CANCELLED;

    if (cb)
        for (auto& d : devices) cb(&d, user);
    return static_cast<int>(devices.size());
}
