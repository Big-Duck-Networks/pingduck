# PingDuck Roadmap

Companion to [PRD.md](PRD.md). Each phase has a goal, its work items, and an exit
criterion that defines "done". Phases overlap where noted; nothing here is dated
yet. Size estimates are rough engineering effort for one developer.

**Legend:** ✅ done · 🟡 in progress / partially done · ⬜ not started

---

## Where we are (2026-10-05)

| Phase | State | Summary |
| --- | --- | --- |
| 1. Core engine | 🟡 ~80% | ICMP, mDNS, SSDP/UPnP, name lookup, port scan, WoL and OUI work on Windows and Android 14. libpcap ARP is written but has never been compiled. There are no automated tests. |
| 2. FFI & mobile setup | 🟡 ~10% | Flutter app scaffolded with Riverpod, theme, folder structure and `DiscoveredDevice` model. |
| 3. UI/UX | ⬜ | Placeholder Radar screen only. |
| 4. Agent & cloud sync | ⬜ | Dockerfile runs a one-shot CLI scan only. |

Measured so far: a full /24 scan takes ~3.4s on Windows and ~3.6s on Android
(PRD target: under 15s).

---

## Phase 1: Finish the core engine

**Goal:** `pingduck-core` is correct, tested and safe on every target platform.

| | Item | Size | Notes |
| --- | --- | --- | --- |
| ⬜ | Build and validate the libpcap ARP scan on Linux | S | Run `agent/Dockerfile` on the Proxmox host. Compare its results against `arp-scan`. |
| ⬜ | Unit tests (`ctest`) | M | Cover the DNS/mDNS parser, NetBIOS NBSTAT parser, SSDP headers, UPnP XML extraction, OUI CSV, CIDR/MAC parsing and the scan merger. Use captured packets from the test LAN as fixtures. |
| ⬜ | Fuzz the packet parsers | M | Every parser reads untrusted bytes from the LAN. Run libFuzzer and ASan/UBSan on `Reader`, `parse_nbstat`, `xml_tag` and the SSDP parser. **This is a security requirement before shipping.** |
| ⬜ | iOS build (static library / xcframework) | M | Needs a Mac. Check that `SOCK_DGRAM` ICMP strips IP headers as expected on iOS. |
| ⬜ | Cancellation and stress tests | S | `pd_cancel()` during each method, repeated back-to-back scans, /16 sweeps. |
| ⬜ | Single-socket async ICMP sweep (POSIX) | M | Replace the 128-thread pool on mobile with one socket that sends all echoes and collects replies. This cuts thread and battery cost. |
| ⬜ | OUI database format | S | The PRD calls for embedded SQLite; it's currently a CSV loader. Decide and convert (see Decisions). |
| ⬜ | CI | M | GitHub Actions matrix: Windows MSVC, Linux with pcap, Android NDK and macOS/iOS. |

**Exit:** green CI on all four targets, the ARP scan validated on Linux, and the parsers fuzzed with no findings.

---

## Phase 2: FFI bridge and mobile setup

**Goal:** the app runs a real scan on a phone and streams devices into Riverpod state.

| | Item | Size | Notes |
| --- | --- | --- | --- |
| ⬜ | Package the core as a Flutter FFI plugin | M | Use the `packages/pingduck_core` template from `flutter create --template=plugin_ffi`. It builds the CMake project for Android (Gradle `externalNativeBuild`) and iOS (podspec). |
| ⬜ | Generate bindings with `ffigen` from `pingduck.h` | S | Write `lib/core/ffi/scanner_bridge.dart` as a thin, idiomatic wrapper around the generated code. |
| ⬜ | Background execution | M | `pd_scan` blocks, so run it on a helper isolate. Deliver callbacks with `NativeCallable.listener` and map them into a `Stream<DiscoveredDevice>`. Wire cancellation to `pd_cancel()`. |
| ⬜ | `ScanController` (Riverpod `Notifier`) | M | Upsert devices by IP and track scan phases (idle/sweeping/enriching/done) and errors. |
| ⬜ | Network context from the platform | S | Wi-Fi subnet, gateway and DNS via `network_info_plus`. Android's policy routing hides the gateway from the core. |
| ⬜ | Platform permissions and config | M | **Android:** `INTERNET`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`, and a `MulticastLock` held during scans. **iOS:** `NSLocalNetworkUsageDescription`, `NSBonjourServices` list, and the multicast entitlement (see Risks). |
| ⬜ | Bundle the OUI database as an asset | S | Load it from `assets/oui_database/` at startup. |

**Exit:** on a physical Android phone and iPhone, tapping "Scan" streams the same devices the CLI finds.

---

## Phase 3: UI/UX

**Goal:** the PRD's Radar experience. Cached devices appear instantly and light up as they respond.

| | Item | Size | Notes |
| --- | --- | --- | --- |
| ⬜ | Local cache (`services/local_storage.dart`) | M | Store networks (keyed by gateway MAC + SSID) and devices with first/last seen. Load before the first frame. |
| ⬜ | Radar / Cortex Map view | L | Animated sweep; dimmed cached devices illuminate on response; smooth state transitions with no static spinners. |
| ⬜ | Device inventory list | M | Sortable by IP, name, vendor and last seen. Filter online/offline. Show source and service chips. |
| ⬜ | Device type icons | S | Infer from mDNS service types, UPnP device type and vendor (router, TV, speaker, printer, VM, phone…). |
| ⬜ | Device details screen | M | IP/MAC/vendor/model, rename and notes, connection history. |
| ⬜ | Diagnostics | M | Continuous ping latency chart, port scan of 21/22/80/443/3389 with risk hints, Wake-on-LAN button. Bindings already exist in the core. |
| ⬜ | Mascot and brand assets | M | Duck logo, app icon, splash, empty/error/permission-denied states with the brand voice. |
| ⬜ | Onboarding | S | Explain and request the local network permission, and explain why MACs need the agent. |

**Exit:** cold launch shows cached devices in under 1s, and a full scan updates the radar live with no jank on a mid-range Android phone.

---

## Phase 4: Agent and cloud sync

**Goal:** 24/7 monitoring on a homelab box, synced to the app, with intrusion alerts.

| | Item | Size | Notes |
| --- | --- | --- | --- |
| ⬜ | Supabase schema and RLS | M | Tables for `networks`, `devices`, `device_events`, `agents` and `push_tokens`, plus row-level security per user. Migrations live in `supabase/migrations/`. |
| ⬜ | Auth in the app (`features/auth`) | M | Supabase Auth (see Decisions). |
| ⬜ | Agent pairing | M | The app shows a short pairing code and the agent exchanges it for a scoped, revocable token. **The agent never holds the service-role key.** |
| ⬜ | Agent daemon | L | Scan on an interval with the ARP, ICMP, mDNS and SSDP methods, diff against the last state, and upsert changes to Supabase. Config via env vars; health check; graceful shutdown. |
| ⬜ | Intrusion alerts | M | A new MAC creates a `device_events` row. A database trigger or Edge Function sends the push through FCM/APNs. "Known device" allow-list in the app. |
| ⬜ | Realtime sync in the app (`services/supabase_sync.dart`) | M | Subscribe to device changes. The agent's data (with MACs) enriches what the phone can see. |
| ⬜ | Settings (`features/settings`) | S | Agent status, sync toggle, notification preferences. |
| ⬜ | Proxmox deployment guide | S | Docker in a VM, or a privileged LXC. `--net=host` and `NET_RAW` are required. |

**Exit:** a new device joining the home LAN triggers a push notification within 2 minutes, and the app shows agent-sourced MACs and vendors.

---

## Phase 5: Launch readiness

| | Item | Notes |
| --- | --- | --- |
| ⬜ | Beta | TestFlight and Play internal testing, plus a published agent image (GHCR). |
| ⬜ | Crash reporting and analytics | Opt-in. Never upload device lists without cloud sync enabled. |
| ⬜ | Privacy policy and store listings | App Store review notes explaining local network scanning. |
| ⬜ | Performance and battery pass | Scan cost on older phones; agent CPU and memory on small hosts. |

---

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| **iOS multicast entitlement** (`com.apple.developer.networking.multicast`) needs Apple approval, which can take weeks | No mDNS/SSDP on iOS without it | Apply as soon as Phase 2 starts. Legacy-unicast mDNS replies may partly work without it; verify on a device. |
| **Randomized MACs** (iOS/Android private Wi-Fi addresses rotate) | "New MAC" alerts fire for known phones, causing alert fatigue | Treat locally administered MACs separately and match them on hostname/mDNS identity. Let users mark devices as known. |
| Android blocks multicast receive without a `MulticastLock` | mDNS/SSDP miss devices on some phones | Hold the lock during scans (Phase 2). |
| Parsers run on untrusted network input | Memory-safety bug becomes remote crash or exploit | Fuzz the parsers and run sanitizers in CI (Phase 1). |
| Isar maintenance status is uncertain | Local cache built on a stalled dependency | Decide the local DB before Phase 3 (see Decisions). |
| Docker host networking on Proxmox | Agent can't see the LAN from a default bridge network | Document the VM and privileged-LXC setups, and detect the bridge network at startup with a clear error. |

---

## Decisions needed

| Decision | Options | Recommendation | Needed by |
| --- | --- | --- | --- |
| Local cache | Isar · drift (SQLite) · sqflite | **drift**: SQLite matches the PRD, is actively maintained and has typed queries | Phase 3 |
| OUI storage | CSV (current) · embedded SQLite | **SQLite** if the app shares it with drift; otherwise keep CSV (a 40k-row hash map loads fast) | Phase 2 |
| Agent daemon language | C++ with libcurl · thin Go/Rust wrapper around `libpingduck` | **C++**: one toolchain, matches the PRD | Phase 4 |
| Auth providers | Email magic link · Apple/Google sign-in | Magic link first; Apple sign-in is required on iOS if any social login ships | Phase 4 |
| Device identity | MAC · IP · MAC with hostname fallback | MAC, with a fallback for randomized MACs | Phase 3 |
| Monorepo package layout | Core as an FFI plugin package · core built inside the app | **FFI plugin package** (`packages/pingduck_core`) | Phase 2 |

---

## Suggested next steps

1. Validate the Linux ARP scan on the Proxmox host (closes the last untested core path).
2. Apply for the iOS multicast entitlement (long lead time; it doesn't block other work).
3. Start Phase 2 with the FFI plugin package and `ffigen` bindings, while parser tests and fuzzing finish in parallel.
