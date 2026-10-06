# PingDuck Roadmap

Companion to [PRD.md](PRD.md). Each phase has a goal, its work items, and an exit
criterion that defines "done". Phases overlap where noted; nothing here is dated
yet. Size estimates are rough engineering effort for one developer.

**Legend:** ✅ done · 🟡 in progress / partially done · ⬜ not started

---

## Where we are (2026-10-05)

| Phase | State | Summary |
| --- | --- | --- |
| 1. Core engine | 🟡 ~95% | Unit tests, fuzzing, cancellation and /16 stress tests, and the single-socket ICMP sweep are done. CI is written but has not run yet. Two checks remain: the ARP scan against `arp-scan` on the LAN, and a first iOS build. |
| 2. FFI & mobile setup | 🟡 ~85% | Scan works end to end on Android (Chromecast, Android 14): 24 devices stream into the app in ~5s. iOS is configured but has never been built. |
| 3. UI/UX | 🟡 ~80% | The "Precision Editorial Recon" design is built across 4 tabs (Discovery, Topology, Tools, Account) plus onboarding. Tools holds Node Inspect and the Homelab Agent screen; the list is titled with the Wi-Fi name. Drift cache and real diagnostics are in. Not done: app icon/splash, and timing on a real mid-range phone. |
| 4. Agent & cloud sync | ⬜ | Dockerfile runs a one-shot CLI scan only. |
| 5. Subscriptions | ⬜ | Not started. The tiers below are a proposal. |
| 6. Launch readiness | ⬜ | |

Measured so far: a full /24 scan takes ~3.5s on Windows and ~3.1s on Android
(PRD target: under 15s). A /16 ICMP sweep takes ~14s on Android and ~4 min on
Windows, which has no single-socket path.

---

## Phase 1: Finish the core engine

**Goal:** `pingduck-core` is correct, tested and safe on every target platform.

| | Item | Size | Notes |
| --- | --- | --- | --- |
| 🟡 | Build and validate the libpcap ARP scan on Linux | S | CI builds it with `PINGDUCK_PCAP=ON`, runs a smoke scan of the runner's gateway, and builds the agent image. Frame building and reply parsing are unit-tested and fuzzed. **Still needed:** run the agent image on the Proxmox host and compare its results against `arp-scan`. |
| ✅ | Unit tests (`ctest`) | M | `core/tests`: DNS/mDNS, NBSTAT, SSDP headers, UPnP XML, ICMP and ARP frames, procfs tables, OUI CSV, CIDR/MAC parsing, the scan merger and API argument checks. Fixtures are synthetic packets shaped like the test LAN's devices. Captured packets stay out of git because they contain device names. |
| ✅ | Fuzz the packet parsers | M | `core/fuzz`: four libFuzzer targets cover every parser that reads LAN input. 15 min each locally (MSVC + ASan, seeded from real LAN captures) found nothing. CI adds Clang ASan + UBSan, 2 min per target per push. The review behind this fixed a quadratic `xml_tag`, double XML unescaping, unbounded mDNS/SSDP memory and threads, and an SSDP `LOCATION` that could point the scanner at any host. |
| 🟡 | iOS build (static library / xcframework) | M | `core/scripts/build-xcframework.sh` builds `PingDuckCore.xcframework` (device + simulator), and CI runs it on macOS. It has not been compiled yet (no Mac here). **Still needed:** on an iPhone, check that `SOCK_DGRAM` ICMP strips IP headers as expected. The parser accepts both forms. |
| ✅ | Cancellation and stress tests | S | `pingduck_live_tests` (ctest label `network`): `pd_cancel()` during each method, a cancel not leaking into the next scan, 5 back-to-back scans, and an opt-in /16 sweep (`PINGDUCK_STRESS=1`). All pass on Windows and Android 14. |
| ✅ | Single-socket async ICMP sweep (POSIX) | M | One non-blocking socket, paced bursts, one retry pass. On Android it is faster than the 128-thread pool it replaces (sweep 1.6s vs 2.0s, full scan 3.1s vs 3.6s) and uses ~35% less kernel CPU. Windows keeps the `IcmpSendEcho` thread pool. |
| ✅ | OUI database format | S | Decided: keep CSV (see Decisions). The loader now reads only the needed columns: 0.36s on the Chromecast (was 0.48s), ~0.1s on desktop. |
| 🟡 | CI | M | `.github/workflows/core.yml`: Windows MSVC, Linux GCC + libpcap, Clang ASan/UBSan, fuzzing, Android NDK (3 ABIs), macOS, iOS xcframework and the agent image. **Has not run yet.** |

**Exit:** green CI on all four targets, the ARP scan validated on Linux, and the parsers fuzzed with no findings.
Fuzzing is done. The rest waits on the first CI run and the Proxmox comparison.

---

## Phase 2: FFI bridge and mobile setup

**Goal:** the app runs a real scan on a phone and streams devices into Riverpod state.

| | Item | Size | Notes |
| --- | --- | --- | --- |
| ✅ | Package the core as a Flutter FFI plugin | M | `packages/pingduck_core` builds `core/` through CMake on Android, Windows and Linux. The iOS/macOS podspecs compile it through `Classes/` forwarders, which have not been built yet. |
| ✅ | Generate bindings with `ffigen` from `pingduck.h` | S | `lib/src/bindings.g.dart`, wrapped by the idiomatic `PingDuckCore` API in the plugin. The app talks to it through the narrow `ScannerBridge` interface (`lib/core/ffi/scanner_bridge.dart`), so it can be faked in tests. |
| ✅ | Background execution | M | Blocking calls run on helper isolates. The new core trampoline `pd_forward_copy` hands each device to a `NativeCallable.listener` as a heap copy, and an end marker keeps the listener open until the last core callback. Plugin tests cover cancel mid-scan and 20 rapid sessions. |
| ✅ | `ScanController` (Riverpod `Notifier`) | M | Upserts by IP and keeps names from earlier scans. Phases are idle/scanning/done/cancelled/failed: the core does not report sweep vs. enrichment, so those two were dropped. 6 unit tests with a fake bridge. |
| ✅ | Network context from the platform | S | `network_info_plus` provides the Wi-Fi subnet and gateway, passed to the core through the new `pd_set_lan_hints()`. The DNS server is not exposed by the plugin, so the gateway stands in for it. |
| 🟡 | Platform permissions and config | M | Android: permissions plus a `MulticastLock` in `MainActivity`, held only during scans. iOS: `NSLocalNetworkUsageDescription` and `NSBonjourServices` are added. **Still needed:** the multicast entitlement, which must wait for Apple's approval (adding it early breaks signing). |
| ✅ | Bundle the OUI database as an asset | S | `assets/oui_database/oui.csv` (MA-L + MA-M + MA-S, 54k entries, 1.9 MB), refreshed by `dart run tool/update_oui.dart`. Loaded from memory through the new `pd_oui_load_buffer()`, off the UI isolate, on the first scan. |

**Exit:** on a physical Android phone and iPhone, tapping "Scan" streams the same devices the CLI finds.
Android passes (`integration_test/scan_test.dart` on the Chromecast: 24 devices, the same set the CLI finds). The app gets no MACs
on Android because the OS hides the ARP table, which is expected (see Phase 4). Still needed: an iPhone run.

---

## Phase 3: UI/UX

**Goal:** the PRD's Radar experience. Cached devices appear instantly and light up as they respond.

| | Item | Size | Notes |
| --- | --- | --- | --- |
| ✅ | Local cache (`services/local_storage.dart`) | M | drift/SQLite: networks keyed by subnet + gateway (the gateway MAC is hidden on Android), and devices keyed by IP with first/last seen, RTT history, rename and notes. The last network loads before the first frame. |
| ✅ | Radar / Cortex Map view | L | Square scope on latency rings (5/15/50 ms) with a sweep arm. Cached devices are dimmed and pulse as they answer, and labels avoid overlapping. The ticker stops when idle (a battery bug found in testing). |
| ✅ | Device inventory list | M | The Target Ledger: sort by latency/IP/name/vendor/last seen, filter all/online/offline, source and service chips, RTT sparkline, and long-press to rename. |
| ✅ | Device type icons | S | `DeviceKind`, inferred only from real signals (mDNS/UPnP types, vendor, model, hostname). |
| ✅ | Device details screen | M | The Inspector: identity, rename and notes, first/last seen, sources, mDNS services, UPnP fields, JSON export, and forget. Fields the app cannot observe (uptime, OS, link speed) are left out rather than faked. |
| ✅ | Diagnostics | M | 60-sample live ping with min/avg/max/jitter/loss, quick (18 ports) and deep (1-1024) TCP scans with risk hints, and Wake-on-LAN (needs a MAC, so in practice the agent). |
| ✅ | Mascot and brand assets | M | Duck mark (vector) plus Space Grotesk and Inter bundled (OFL). Launcher icons (iOS, Android adaptive and Android 13 themed) and native splash (including Android 12+) are generated from `assets/branding/` by `tool/make_brand_assets.py`. Empty and error states follow the brand voice. |
| ✅ | Onboarding | S | First launch explains scanning, local network access and why MACs need the agent, then starts the first scan. |

**Exit:** cold launch shows cached devices in under 1s, and a full scan updates the radar live with no jank on a mid-range Android phone.
Measured with `integration_test/perf_test.dart` on the emulator: 7 cached devices on the first frame 185 ms after launch.
During a scan, raster time is 3.4 ms median. That is after splitting the radar into a cached static layer and an animated
layer (it was 11.9 ms), but the emulator renders in software, so its 23% over-budget frames are not representative.
**Still needed:** the same test on a physical phone. Topology shows latency rings only; physical links need the agent.

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

## Phase 5: Subscriptions

**Goal:** a paid tier sold through the App Store and Google Play, unlocked across the user's devices and
enforced by the backend, not just the app.

Store rules shape this phase. On iOS and Android, digital features must be sold through Apple and Google
in-app purchase; Stripe (or any web checkout) cannot unlock them inside the app. A web checkout only makes
sense for a later desktop or web product.

| | Item | Size | Notes |
| --- | --- | --- | --- |
| ⬜ | Tier definition | S | Decide what is free and what is Pro (proposal under Decisions). Settle this before the Phase 4 schema, because entitlements gate agent pairing and sync. |
| ⬜ | Billing integration | M | RevenueCat (recommended) or native StoreKit 2 + Play Billing. Monthly and annual products, intro trial, family sharing on iOS. |
| ⬜ | Server-side entitlements | M | Store webhooks (RevenueCat, or App Store Server Notifications and Play RTDN) write the entitlement to Supabase. RLS and Edge Functions check it, so agent pairing and sync are enforced on the server. |
| ⬜ | Paywall and upgrade points | M | One paywall in the design system, reached from the gated features (pair agent, enable sync, alerts, deep scan) and from the Account tab. No dark patterns: clear price, period and trial terms. |
| ⬜ | Account tab: subscription state | S | Current plan, renewal date, Manage subscription (opens the store's own page), Restore purchases. Apple requires Restore. |
| ⬜ | Legal | S | Privacy Policy and Terms of Use (EULA) URLs, linked from the paywall and the About footer. Apple rejects subscription apps without them. Confirm the legal entity name (the app currently says "Big Duck Networks"). |
| ⬜ | Store setup | M | App Store Connect and Play Console products, subscription groups, tax and banking, sandbox testers. |
| ⬜ | Tests | M | Sandbox purchases, renewals, cancellation, grace period, billing retry, refunds, restore on a new device. |

**Exit:** a sandbox user subscribes on Android and iOS, Pro features unlock on both platforms within a minute,
and cancelling or refunding revokes access on the server.

---

## Phase 6: Launch readiness

| | Item | Notes |
| --- | --- | --- |
| ⬜ | Beta | TestFlight and Play internal testing, plus a published agent image (GHCR). |
| ⬜ | Crash reporting and analytics | Opt-in. Never upload device lists without cloud sync enabled. |
| ⬜ | Privacy policy and store listings | App Store review notes explaining local network scanning, location (Wi-Fi name only) and the subscription. The policy itself is drafted in Phase 5. |
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
| ~~Local cache~~ | **Decided: drift** (SQLite). | | ✅ |
| ~~OUI storage~~ | **Decided: CSV.** The app looks vendors up through `pd_oui_lookup` over FFI, so it never reads the table itself. SQLite would add a C dependency to the core for no gain. Load it off the UI thread at startup (0.36s on the slowest test device). | | ✅ |
| Agent daemon language | C++ with libcurl · thin Go/Rust wrapper around `libpingduck` | **C++**: one toolchain, matches the PRD | Phase 4 |
| Auth providers | Email magic link · Apple/Google sign-in | Magic link first; Apple sign-in is required on iOS if any social login ships | Phase 4 |
| Device identity | MAC · IP · MAC with hostname fallback | **IP for now** (the app sees no MACs on Android). Switch to MAC with a hostname fallback when the agent supplies MACs. | Phase 4 |
| Free vs Pro | What stays free · what is paid | **Free:** on-device scans, radar, topology, device list, Node Inspect (ping, quick port scan), one remembered network. **Pro:** Homelab Agent (MACs, 24/7 monitoring), intrusion alerts, cloud sync across devices, unlimited networks with history, deep port scans, export. The free tier must be useful on its own: it is the store listing's first impression. | Phase 4 (shapes the schema) |
| Billing provider | RevenueCat · native StoreKit 2 + Play Billing | **RevenueCat**: one SDK for both stores, receipt validation, and webhooks into Supabase. It costs a share of revenue above a threshold. Native avoids that cost but means building receipt validation for two stores. | Phase 5 |
| Pricing | Monthly · annual · lifetime | Monthly + annual (annual about 40% cheaper) with a 7-day trial. Skip lifetime: it does not pay for a hosted backend. Set prices from comparable network tools. | Phase 5 |
| Monorepo package layout | Core as an FFI plugin package · core built inside the app | **FFI plugin package** (`packages/pingduck_core`) | Phase 2 |

---

## Suggested next steps

1. Push and get the core CI green (the first run covers the Linux libpcap, macOS and iOS builds).
2. Decide Free vs Pro and the billing provider. Both shape the Phase 4 schema and agent pairing.
3. Apply for the iOS multicast entitlement, and set up App Store Connect and Play Console early. Both have long lead times.
4. Finish Phase 3: app icon, splash, and a timing pass on a physical phone.
5. Run the agent image on the Proxmox host and compare its results against `arp-scan`, which closes Phase 1.
6. Start Phase 4 with the Supabase schema, designed with entitlements in mind.
