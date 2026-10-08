# PingDuck Roadmap

```
Document Identifier: DOC-RDMP-PINGDUCK-001
Standard Compliance: IEC/IEEE 82079-1:2019 Edition 2.0
Document Version:    1.1.0
Status:              Approved
Date of Issue:       2026-10-06
Product:             PingDuck Network Discovery & Reconnaissance Platform
```

Companion to [PRD.md](PRD.md). Each phase has a goal, its work items, and an exit
criterion that defines "done". Phases overlap where noted; nothing here is dated
yet. Size estimates are rough engineering effort for one developer.

**Legend:** ✅ done · 🟡 in progress / partially done · ⬜ not started

---

## Where we are (2026-10-06)

| Phase | State | Summary |
| --- | --- | --- |
| 1. Core engine | ✅ | Unit tests, fuzzing, cancellation and /16 stress tests, and the single-socket ICMP sweep are done. CI is green on all targets, including the iOS xcframework. The libpcap ARP scan matches `arp-scan` on the LAN. |
| 2. FFI & mobile setup | 🟡 ~85% | Scan works end to end on Android (Chromecast, Android 14): 24 devices stream into the app in ~5s. The iOS core compiles in CI, but the app has never run on an iPhone. |
| 3. UI/UX | ✅ | The "Precision Editorial Recon" design is built across 3 tabs (Overview, Tools, Account) plus onboarding. Topology is built but parked off the tab bar. Tools holds Node Inspect and the Homelab Agent screen; the device list is titled with the Wi-Fi name. Drift cache, real diagnostics, icons and splash are in. On a Pixel 8 Pro: cached devices on the first frame in about 100 ms, and ~1% of frames over 16.7 ms during a scan. |
| 4. Agent & cloud sync | ⬜ | Dockerfile runs a one-shot CLI scan only. |
| 5. Subscriptions | ⬜ | Not started. The tiers below are a proposal. |
| 6. Network tools (Fing parity) | ⬜ | Traceroute, DNS lookup, network details and a speed test. |
| 7. Recognition & security (Fing parity) | ⬜ | Device fingerprinting and router/security checks. |
| 8. Launch readiness | ⬜ | |

Measured so far: a full /24 scan takes ~3.5s on Windows and ~3.1s on Android
(PRD target: under 15s). A /16 ICMP sweep takes ~14s on Android and ~4 min on
Windows, which has no single-socket path.

---

## Phase 1: Finish the core engine

**Goal:** `pingduck-core` is correct, tested and safe on every target platform.

| | Item | Size | Notes |
| --- | --- | --- | --- |
| ✅ | Build and validate the libpcap ARP scan on Linux | S | CI builds it with `PINGDUCK_PCAP=ON`, runs a smoke scan of the runner's gateway, and builds the agent image. Frame building and reply parsing are unit-tested and fuzzed. Compared against `arp-scan` 1.9.7 on the test LAN (2026-10-06, native build on an Ubuntu 22.04 KVM guest bridged onto the LAN): the first version found only 15–17 of ~22 hosts. Unpaced bursts made the AP drop broadcasts queued for power-saving Wi-Fi clients (`arp-scan -B 100M` lost the same hosts). Sends are now paced at 2 ms per frame, and the retry pass waits 500 ms and asks only hosts that have not answered. Over 6 alternating rounds, pingduck found 90.9% of the union of hosts against `arp-scan`'s 91.6%. A /24 takes ~3.6s; a /16 would take ~4–5 min. The scan also no longer reports the scanning host from its own ARP replies. The Docker image itself has not been run on the LAN. |
| ✅ | Unit tests (`ctest`) | M | `core/tests`: DNS/mDNS, NBSTAT, SSDP headers, UPnP XML, ICMP and ARP frames, procfs tables, OUI CSV, CIDR/MAC parsing, the scan merger and API argument checks. Fixtures are synthetic packets shaped like the test LAN's devices. Captured packets stay out of git because they contain device names. |
| ✅ | Fuzz the packet parsers | M | `core/fuzz`: four libFuzzer targets cover every parser that reads LAN input. 15 min each locally (MSVC + ASan, seeded from real LAN captures) found nothing. CI adds Clang ASan + UBSan, 2 min per target per push. The review behind this fixed a quadratic `xml_tag`, double XML unescaping, unbounded mDNS/SSDP memory and threads, and an SSDP `LOCATION` that could point the scanner at any host. |
| ✅ | iOS build (static library / xcframework) | M | `core/scripts/build-xcframework.sh` builds `PingDuckCore.xcframework` (device + simulator), and CI runs it on macOS. It compiles in CI (the first attempt failed; fixed in `9bcf82b` by switching to the Xcode generator). **Still needed:** on an iPhone, check that `SOCK_DGRAM` ICMP strips IP headers as expected. The parser accepts both forms. |
| ✅ | Cancellation and stress tests | S | `pingduck_live_tests` (ctest label `network`): `pd_cancel()` during each method, a cancel not leaking into the next scan, 5 back-to-back scans, and an opt-in /16 sweep (`PINGDUCK_STRESS=1`). All pass on Windows and Android 14. |
| ✅ | Single-socket async ICMP sweep (POSIX) | M | One non-blocking socket, paced bursts, one retry pass. On Android it is faster than the 128-thread pool it replaces (sweep 1.6s vs 2.0s, full scan 3.1s vs 3.6s) and uses ~35% less kernel CPU. Windows keeps the `IcmpSendEcho` thread pool. |
| ✅ | OUI database format | S | Decided: keep CSV (see Decisions). The loader now reads only the needed columns: 0.36s on the Chromecast (was 0.48s), ~0.1s on desktop. |
| ✅ | CI | M | `.github/workflows/core.yml`: Windows MSVC, Linux GCC + libpcap, Clang ASan/UBSan, fuzzing, Android NDK (3 ABIs), macOS, iOS xcframework and the agent image. All 10 jobs green since 2026-10-06. |

**Exit:** green CI on all four targets, the ARP scan validated on Linux, and the parsers fuzzed with no findings.
Done: CI is green, fuzzing found nothing, and the ARP scan matches `arp-scan`. The on-device iOS ICMP check moves with the Phase 2 iPhone run.

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
| ✅ | Supabase schema and RLS | M | `supabase/migrations/20261006120000_initial_schema.sql`: `plans` and `entitlements` (Fing-style tiers, limits as data), the daily scan quota (`claim_scan`), `networks`, `agents` with code pairing (`create_pairing_code`, `claim_pairing_code`, `revoke_agent`), `devices` and `device_events` written by `agent_sync`, `push_tokens`, `prune_history`, RLS on every table and Realtime on devices and events. Applied to the Supabase project; `supabase/tests/schema_test.sql` passes there (it runs in a rolled-back transaction, so it can be pasted into the SQL editor). `20261007120000_schedule_prune_history.sql` runs `prune_history` daily at 04:00 UTC with pg_cron. |
| 🟡 | Auth in the app (`features/auth`) | M | Supabase Auth, enabled for anonymous and email sign-ins. The app signs in anonymously before its first scan, and `ScanQuota` claims each scan through `claim_scan` (Free: 3 a day), counting locally when offline. Scans the app starts itself (launch, Wi-Fi reconnect) do not count, but run at most once every 30 minutes on Free. The Overview banner shows when scans come back. The Account tab has email and password accounts. Creating one upgrades the anonymous user in place, so its id and data carry over, after a one-time emailed code confirms the address; there is also password reset by code, and Delete account (the `delete_account` RPC, which cascades to every user-owned row; Apple requires in-app deletion). Google, and Apple on iOS, are shown disabled. Widget-tested against a fake; not yet tried against the live project. **Still needed:** send auth email through Resend (custom SMTP as `hello@pingduck.app`), turn on "Confirm email" (with it off, an email is attached without proof of ownership), put `{{ .Token }}` in the Change Email Address and Reset Password templates, apply `20261007130000_delete_account.sql`, and wire up Google and Sign in with Apple. |
| ⬜ | Agent pairing | M | The app shows a short pairing code and the agent exchanges it for a scoped, revocable token. **The agent never holds the service-role key.** |
| ⬜ | Agent daemon | L | Scan on an interval with the ARP, ICMP, mDNS and SSDP methods, and report each scan through `agent_sync`, which diffs against the stored state and records events. Config via env vars; health check; graceful shutdown. |
| ⬜ | Intrusion alerts | M | A new MAC creates a `device_events` row. A database webhook or Edge Function sends the push through FCM/APNs to `push_tokens`, gated on the plan's `notifications` flag. "Known device" allow-list in the app. |
| ⬜ | Realtime sync in the app (`services/supabase_sync.dart`) | M | Subscribe to device and event changes with Supabase Realtime and write them into the Drift cache, so the UI keeps reading locally. The agent's data (with MACs) enriches what the phone can see. |
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
| ✅ | Tier definition | S | Free, Premium and Pro, mirroring Fing (see Decisions). Encoded in the `plans` table, which gates the scan quota, agent pairing and sync. |
| ⬜ | Billing integration | M | RevenueCat (recommended) or native StoreKit 2 + Play Billing. Monthly and annual products, intro trial, family sharing on iOS. |
| ⬜ | Server-side entitlements | M | Store webhooks (RevenueCat, or App Store Server Notifications and Play RTDN) write the entitlement to Supabase. RLS and the RPCs check it, so agent pairing and sync are enforced on the server. |
| ⬜ | Paywall and upgrade points | M | One paywall in the design system, reached from the gated features (pair agent, enable sync, alerts, deep scan) and from the Account tab. No dark patterns: clear price, period and trial terms. |
| ⬜ | Account tab: subscription state | S | Current plan, renewal date, Manage subscription (opens the store's own page), Restore purchases. Apple requires Restore. |
| ⬜ | Legal | S | Privacy Policy and Terms of Use (EULA) URLs, linked from the paywall and the About footer. Apple rejects subscription apps without them. Confirm the legal entity name (the app currently says "Big Duck Networks"). |
| ⬜ | Store setup | M | App Store Connect and Play Console products, subscription groups, tax and banking, sandbox testers. |
| ⬜ | Tests | M | Sandbox purchases, renewals, cancellation, grace period, billing retry, refunds, restore on a new device. |

**Exit:** a sandbox user subscribes on Android and iOS, Pro features unlock on both platforms within a minute,
and cancelling or refunding revokes access on the server.

---

## Phase 6: Network tools (Fing parity)

**Goal:** the everyday tools users expect from a network app like Fing, so PingDuck can replace it for
casual use. Each one is cheap and fits into Node Inspect or the Tools tab.

| | Item | Size | Notes |
| --- | --- | --- | --- |
| ⬜ | Traceroute | M | Add it to the core (TTL-limited ICMP on the existing socket path) and show hops with RTT in Node Inspect. Works on any host, not just LAN devices. |
| ⬜ | DNS lookup | S | A, AAAA, PTR, MX and TXT records against the system resolver or a chosen server. The core already has a DNS parser. |
| ⬜ | Network details screen | S | SSID, local IP, subnet, gateway, public IP, ISP. Android does not expose the DNS server to the app (see Phase 2), so show it only where the platform gives it. |
| ⬜ | Internet speed test | M | Download, upload and latency against a public endpoint (decide which: an M-Lab NDT7 server or a self-hosted endpoint). Keep the history per network. |

**Exit:** each tool works on Android and iOS against the test LAN and a public host, with results that match
the desktop tools (`tracert`/`traceroute`, `nslookup`, a reference speed test) to within normal variance.

---

## Phase 7: Device recognition and security (Fing parity)

**Goal:** close Fing's biggest advantage, which is naming what each device is (make, model, OS), and flag risky setups.

| | Item | Size | Notes |
| --- | --- | --- | --- |
| ⬜ | Fingerprint rules | L | Combine the signals the core already gathers (OUI, mDNS service types and TXT records, UPnP model fields, NetBIOS names, hostname patterns, open ports) into make/model/OS guesses, using a rules file shipped as an asset and updated like the OUI database. Keep `DeviceKind`'s rule: guess only from real signals and show the confidence. |
| ⬜ | Agent-side signals | M | The agent can see DHCP options (option 55 fingerprints) and HTTP banners the phone cannot. Feed them into the same rules. |
| ⬜ | User corrections | S | Let users fix a wrong guess. Later, opt-in sharing of corrections could build a crowd-sourced database (needs a privacy review first). |
| ⬜ | Router and security checks | M | Check the gateway for open admin ports, exposed UPnP/IGD, Telnet and similar. Reuse the port scan and UPnP data that already carry risk hints. Show it as one "network health" summary. |
| ⬜ | Exposed services report | S | List devices with risky open ports (Telnet, SMB, RDP, unauthenticated web admin) across the LAN, not one device at a time. |

Out of scope on purpose: **blocking or pausing devices.** Fingbox does this with ARP spoofing, which is fragile,
can break networks and looks like an attack to other tools. Revisit only if users ask for it strongly.

**Exit:** on the test LAN, most devices show a make or model that matches the real device, and the security
summary flags a deliberately opened test port.

---

## Phase 8: Launch readiness

| | Item | Notes |
| --- | --- | --- |
| ⬜ | Security audit | Run the `vibe-security` skill (`.claude/skills/vibe-security`) over the app, the `supabase/` migrations (RLS, the security-definer RPCs including `delete_account`, the `claim_scan` quota) and the website. Do it before the beta, and again once billing (Phase 5) and the agent (Phase 4) land. |
| ⬜ | Beta | TestFlight and Play internal testing, plus a published agent image (GHCR). |
| ⬜ | Crash reporting and analytics | Opt-in. Never upload device lists without cloud sync enabled. |
| ⬜ | Privacy policy and store listings | App Store review notes explaining local network scanning, location (Wi-Fi name only) and the subscription. The policy itself is drafted in Phase 5. |
| ⬜ | Copy pass | Run the global `no-ai-slop` skill in Detect mode over the website (homepage, FAQ, privacy, terms), the store listings and the app's user-facing strings, then edit what it flags. |
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
| Hypervisor traffic filters | During the ARP comparison, the KVM host's management layer (DuckStack) attached a libvirt MAC allowlist to the test VM, cutting it off from all but 3 hosts. It is not yet known whether the sweeps triggered it. | Find out what triggered it before running the agent on that host. Cover hypervisor filters (libvirt `clean-traffic`, Proxmox firewall) in the deployment guide, and warn when an ARP sweep gets replies from almost none of the hosts that ICMP finds. |

---

## Decisions needed

| Decision | Options | Recommendation | Needed by |
| --- | --- | --- | --- |
| ~~Local cache~~ | **Decided: drift** (SQLite). | | ✅ |
| ~~Cloud sync engine~~ | **Decided: Supabase** (Postgres, Auth, Realtime) with the Drift cache on the phone. PowerSync was considered and dropped. | | ✅ |
| ~~OUI storage~~ | **Decided: CSV.** The app looks vendors up through `pd_oui_lookup` over FFI, so it never reads the table itself. SQLite would add a C dependency to the core for no gain. Load it off the UI thread at startup (0.36s on the slowest test device). | | ✅ |
| Agent daemon language | C++ with libcurl · thin Go/Rust wrapper around `libpingduck` | **C++**: one toolchain, matches the PRD | Phase 4 |
| Auth providers | Email magic link · Apple/Google sign-in | Magic link first; Apple sign-in is required on iOS if any social login ships | Phase 4 |
| Device identity | MAC · IP · MAC with hostname fallback | **IP for now** (the app sees no MACs on Android). Switch to MAC with a hostname fallback when the agent supplies MACs. | Phase 4 |
| ~~Free vs Pro~~ | **Decided: mirror Fing's plans.** **Free:** 3 scans a day, the network tools, basic device recognition, no monitoring. **Premium** (Fing: $7.99/mo, $69.99/yr): unlimited scans, the Homelab Agent on up to 2 networks, full event history, push alerts, security checks, scheduled speed tests. **Pro** (Fing: $16.99/mo, $149.99/yr): 3 monitored networks; shared workspaces and multiple users come later. Limits live in the `plans` table. | | ✅ |
| Billing provider | RevenueCat · native StoreKit 2 + Play Billing | **RevenueCat**: one SDK for both stores, receipt validation, and webhooks into Supabase. It costs a share of revenue above a threshold. Native avoids that cost but means building receipt validation for two stores. | Phase 5 |
| Pricing | Monthly · annual · lifetime | Monthly + annual (annual about 40% cheaper) with a 7-day trial. Skip lifetime: it does not pay for a hosted backend. Set prices from comparable network tools. | Phase 5 |
| Monorepo package layout | Core as an FFI plugin package · core built inside the app | **FFI plugin package** (`packages/pingduck_core`) | Phase 2 |

---

## Suggested next steps

1. Decide the billing provider (RevenueCat recommended) and final prices.
2. Apply for the iOS multicast entitlement, and set up App Store Connect and Play Console early. Both have long lead times.
3. Run the schema tests against the new Supabase project, then build auth (anonymous first) and the scan quota in the app.
4. First iPhone run (needs a Mac): app scan, `SOCK_DGRAM` ICMP check, and mDNS without the multicast entitlement.
5. Decide whether launch waits for the Phase 6 tools. They are small, and a speed test and traceroute are what store reviewers and users compare against Fing.
