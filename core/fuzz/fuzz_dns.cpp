// Unicast DNS PTR answers and NetBIOS node status replies (dns.cpp).
#include "dns.hpp"
#include "parsers.hpp"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    pd::dns::find_ptr_answer(data, size, "5.0.42.10.in-addr.arpa");
    pd::dns::parse_nbstat(data, size);

    // Walk every name in the buffer the way the record loops do.
    pd::dns::Reader r{data, size};
    std::string name;
    for (int i = 0; i < 64 && r.off < size && r.name(name); ++i) {
    }
    return 0;
}
