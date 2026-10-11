// Builds pingduck-core from ../../../core as a static library and links it.
use std::path::PathBuf;

fn main() {
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    // Not canonicalize(): on Windows that yields a \\?\ path MSVC can't open.
    let repo = manifest.ancestors().nth(3).expect("agent/crates/<crate> inside the repo");
    let core = repo.join("core");
    assert!(core.join("CMakeLists.txt").exists(), "core/ not found at {}", core.display());
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();

    // Always Release: the MSVC runtime must match Rust's (/MD), and the
    // scanner is the hot path either way.
    let mut cfg = cmake::Config::new(&core);
    cfg.profile("Release")
        .define("PINGDUCK_BUILD_SHARED", "OFF")
        .define("PINGDUCK_BUILD_CLI", "OFF")
        .define("PINGDUCK_BUILD_TESTS", "OFF")
        .define("PINGDUCK_PCAP", if target_os == "linux" { "ON" } else { "OFF" })
        .build_target("pingduck");
    let dst = cfg.build();

    // The test shim reaches the core's internal SSDP parser, so the agent's
    // tests can check that the phone will understand what the agent sends.
    // Compiled first: GNU ld needs it before the library it calls into.
    let mut shim = cc::Build::new();
    shim.cpp(true)
        .std("c++17")
        .file(manifest.join("shim/shim.cpp"))
        .include(core.join("include"))
        .include(core.join("src"));
    if target_os == "windows" {
        shim.flag("/utf-8");
    }
    shim.compile("pingduck_shim");

    let build = dst.join("build");
    println!("cargo:rustc-link-search=native={}", build.display());
    println!("cargo:rustc-link-search=native={}", build.join("Release").display());
    println!("cargo:rustc-link-lib=static=pingduck");

    match target_os.as_str() {
        "windows" => {
            println!("cargo:rustc-link-lib=ws2_32");
            println!("cargo:rustc-link-lib=iphlpapi");
        }
        "linux" => {
            println!("cargo:rustc-link-lib=pcap");
            println!("cargo:rustc-link-lib=stdc++");
        }
        "macos" => println!("cargo:rustc-link-lib=c++"),
        _ => {}
    }

    println!("cargo:rerun-if-changed=shim/shim.cpp");
    for dir in ["src", "include", "CMakeLists.txt"] {
        println!("cargo:rerun-if-changed={}", core.join(dir).display());
    }
}
