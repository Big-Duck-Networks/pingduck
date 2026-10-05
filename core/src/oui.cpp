// IEEE OUI -> vendor lookup, loaded from the public registry CSVs
// (MA-L oui.csv, and optionally MA-M mam.csv / MA-S oui36.csv).
#include <fstream>
#include <mutex>
#include <shared_mutex>
#include <unordered_map>
#include <vector>

#include "platform.hpp"

using namespace pd;

namespace {

// Keyed by prefix bit-length (24, 28, 36) -> prefix value -> vendor.
std::shared_mutex g_mu;
std::unordered_map<uint64_t, std::string> g_tables[3];
constexpr int kBits[3] = {36, 28, 24};  // longest match first

int table_index(int bits) {
    for (int i = 0; i < 3; ++i)
        if (kBits[i] == bits) return i;
    return -1;
}

// Splits one CSV line honouring double quotes ("" escapes).
std::vector<std::string> split_csv(const std::string& line) {
    std::vector<std::string> out(1);
    bool quoted = false;
    for (size_t i = 0; i < line.size(); ++i) {
        char c = line[i];
        if (quoted) {
            if (c == '"' && i + 1 < line.size() && line[i + 1] == '"') out.back() += '"', ++i;
            else if (c == '"') quoted = false;
            else out.back() += c;
        } else if (c == '"') {
            quoted = true;
        } else if (c == ',') {
            out.emplace_back();
        } else if (c != '\r') {
            out.back() += c;
        }
    }
    return out;
}

}  // namespace

extern "C" {

int pd_oui_load(const char* csv_path) {
    if (!csv_path) return PD_ERR_INVALID_ARG;
    std::ifstream f(csv_path);
    if (!f) return PD_ERR_NOT_FOUND;

    std::unique_lock<std::shared_mutex> lock(g_mu);
    int loaded = 0;
    std::string line;
    while (std::getline(f, line)) {
        auto cols = split_csv(line);
        if (cols.size() < 3) continue;
        const std::string& hex = cols[1];
        int bits = static_cast<int>(hex.size()) * 4;
        int idx = table_index(bits);
        if (idx < 0) continue;  // header row or malformed
        uint64_t prefix;
        try {
            prefix = std::stoull(hex, nullptr, 16);
        } catch (...) {
            continue;
        }
        g_tables[idx][prefix] = cols[2];
        ++loaded;
    }
    return loaded;
}

int pd_oui_lookup(const char* mac, char* out, int out_len) {
    uint8_t m[6];
    if (!parse_mac(mac, m) || !out || out_len <= 0) return PD_ERR_INVALID_ARG;

    // Well-known locally administered prefixes used by hypervisors/containers.
    static const struct { uint8_t p[3]; uint8_t len; const char* name; } kVirtual[] = {
        {{0x52, 0x54, 0x00}, 3, "QEMU/KVM virtual NIC"},
        {{0x02, 0x42, 0x00}, 2, "Docker container"},
        {{0x00, 0x15, 0x5d}, 3, "Microsoft Hyper-V"},
    };
    for (auto& v : kVirtual) {
        if (std::memcmp(m, v.p, v.len) == 0) {
            copy_str(out, static_cast<size_t>(out_len), v.name);
            return PD_OK;
        }
    }

    // Locally administered bit: phones/laptops using per-network random MACs.
    if (m[0] & 0x02) {
        copy_str(out, static_cast<size_t>(out_len), "Private (randomized MAC)");
        return PD_OK;
    }

    uint64_t v = 0;
    for (uint8_t b : m) v = (v << 8) | b;
    std::shared_lock<std::shared_mutex> lock(g_mu);
    for (int i = 0; i < 3; ++i) {
        auto it = g_tables[i].find(v >> (48 - kBits[i]));
        if (it != g_tables[i].end()) {
            copy_str(out, static_cast<size_t>(out_len), it->second);
            return PD_OK;
        }
    }
    return PD_ERR_NOT_FOUND;
}

}  // extern "C"
