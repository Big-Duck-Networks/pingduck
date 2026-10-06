// Minimal test harness: TEST registers a case, CHECK/CHECK_EQ record failures
// without stopping the case, REQUIRE stops it. No external dependencies, so
// the tests build on every CI target including the Android NDK.
#pragma once

#include <cstdio>
#include <cstring>
#include <functional>
#include <sstream>
#include <string>
#include <vector>

namespace check {

struct Case {
    const char* name;
    std::function<void()> fn;
};

inline std::vector<Case>& registry() {
    static std::vector<Case> cases;
    return cases;
}

inline int& failures() {
    static int n = 0;
    return n;
}

struct Register {
    Register(const char* name, std::function<void()> fn) { registry().push_back({name, std::move(fn)}); }
};

struct Abort {};

template <typename T>
std::string show(const T& v) {
    std::ostringstream ss;
    ss << v;
    return ss.str();
}
inline std::string show(const std::string& v) { return "\"" + v + "\""; }
inline std::string show(const char* v) { return v ? "\"" + std::string(v) + "\"" : "(null)"; }
inline std::string show(unsigned char v) { return std::to_string(v); }

inline void fail(const char* file, int line, const std::string& what) {
    std::printf("  %s:%d: %s\n", file, line, what.c_str());
    ++failures();
}

// Runs every case whose name contains `filter` (all when empty).
inline int run(int argc, char** argv) {
    const char* filter = argc > 1 ? argv[1] : "";
    int ran = 0, failed = 0;
    for (auto& c : registry()) {
        if (!std::strstr(c.name, filter)) continue;
        int before = failures();
        try {
            c.fn();
        } catch (const Abort&) {
        } catch (const std::exception& e) {
            fail(__FILE__, __LINE__, std::string("uncaught exception: ") + e.what());
        }
        ++ran;
        bool ok = failures() == before;
        if (!ok) ++failed;
        std::printf("[%s] %s\n", ok ? " ok " : "FAIL", c.name);
    }
    std::printf("%d/%d passed\n", ran - failed, ran);
    return failed == 0 && ran > 0 ? 0 : 1;
}

}  // namespace check

#define CHECK_CAT2(a, b) a##b
#define CHECK_CAT(a, b) CHECK_CAT2(a, b)
#define TEST(name)                                                                  \
    static void CHECK_CAT(test_fn_, __LINE__)();                                    \
    static check::Register CHECK_CAT(test_reg_, __LINE__)(name, &CHECK_CAT(test_fn_, __LINE__)); \
    static void CHECK_CAT(test_fn_, __LINE__)()

#define CHECK(cond) \
    do { if (!(cond)) check::fail(__FILE__, __LINE__, "CHECK(" #cond ")"); } while (0)

#define REQUIRE(cond) \
    do { if (!(cond)) { check::fail(__FILE__, __LINE__, "REQUIRE(" #cond ")"); throw check::Abort{}; } } while (0)

#define CHECK_EQ(a, b)                                                                     \
    do {                                                                                   \
        auto&& check_a_ = (a);                                                             \
        auto&& check_b_ = (b);                                                             \
        if (!(check_a_ == check_b_))                                                       \
            check::fail(__FILE__, __LINE__, std::string("CHECK_EQ(" #a ", " #b "): ") +   \
                                                check::show(check_a_) + " != " + check::show(check_b_)); \
    } while (0)
