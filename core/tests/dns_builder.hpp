// Builds DNS / mDNS response messages for tests, laid out the way real
// responders send them (answers first, then additional records).
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "dns.hpp"

namespace testdns {

struct Message {
    std::vector<uint8_t> bytes;
    uint16_t answers = 0;

    explicit Message(uint16_t flags = 0x8400, uint16_t id = 0) {
        bytes = {static_cast<uint8_t>(id >> 8), static_cast<uint8_t>(id), static_cast<uint8_t>(flags >> 8),
                 static_cast<uint8_t>(flags), 0, 0, 0, 0, 0, 0, 0, 0};
    }

    void u16(uint16_t v) {
        bytes.push_back(static_cast<uint8_t>(v >> 8));
        bytes.push_back(static_cast<uint8_t>(v));
    }

    void question(const std::string& name, uint16_t type) {
        pd::dns::put_name(bytes, name);
        u16(type);
        u16(1);
        ++bytes[5];
    }

    // Appends a resource record; rdata is written raw.
    void record(const std::string& owner, uint16_t type, const std::vector<uint8_t>& rdata) {
        pd::dns::put_name(bytes, owner);
        u16(type);
        u16(0x8001);  // IN, cache-flush
        u16(0);
        u16(120);  // TTL
        u16(static_cast<uint16_t>(rdata.size()));
        bytes.insert(bytes.end(), rdata.begin(), rdata.end());
        ++answers;
        bytes[6] = static_cast<uint8_t>(answers >> 8);
        bytes[7] = static_cast<uint8_t>(answers);
    }

    void a(const std::string& owner, const std::string& ip) {
        std::vector<uint8_t> rd;
        size_t start = 0;
        for (int i = 0; i < 4; ++i) {
            size_t dot = ip.find('.', start);
            rd.push_back(static_cast<uint8_t>(std::stoi(ip.substr(start, dot - start))));
            start = dot + 1;
        }
        record(owner, pd::dns::kTypeA, rd);
    }

    void ptr(const std::string& owner, const std::string& target) {
        std::vector<uint8_t> rd;
        pd::dns::put_name(rd, target);
        record(owner, pd::dns::kTypePTR, rd);
    }

    void srv(const std::string& owner, const std::string& target, uint16_t port) {
        std::vector<uint8_t> rd = {0, 0, 0, 0, static_cast<uint8_t>(port >> 8), static_cast<uint8_t>(port)};
        pd::dns::put_name(rd, target);
        record(owner, pd::dns::kTypeSRV, rd);
    }

    void txt(const std::string& owner, const std::vector<std::string>& entries) {
        std::vector<uint8_t> rd;
        for (auto& e : entries) {
            rd.push_back(static_cast<uint8_t>(e.size()));
            rd.insert(rd.end(), e.begin(), e.end());
        }
        record(owner, pd::dns::kTypeTXT, rd);
    }
};

}  // namespace testdns
