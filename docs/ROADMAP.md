# PingDuck Roadmap

```
Document Identifier: DOC-RDMP-PINGDUCK-001
Standard Compliance: IEC/IEEE 82079-1:2019 Edition 2.0
Document Version:    1.5.1
Status:              Approved
Date of Issue:       2026-10-13
Product:             PingDuck Network Discovery & Reconnaissance Platform
```

Companion to [PRD.md](PRD.md). Each phase has a goal, its work items, and an exit
criterion that defines "done". Phases overlap where noted. Size estimates are rough
engineering effort for one developer (S ≈ 1–2 days, M ≈ 3–5 days, L ≈ 1–2 weeks);
the [Timeline](#timeline-proposed) turns them into a proposed schedule.

**Legend:** ✅ done · 🟡 in progress / partially done · ⬜ not started

---

## Where we are (2026-10-13)

| Phase | State | Summary |
| --- | --- | --- |
| 1. Core engine | ✅ | Unit tests, fuzzing, cancellation and /16 stress tests, and the single-socket ICMP sweep are done. CI is green on all targets, including the iOS xcframework. The libpcap ARP scan matches `arp-scan` on the LAN. |
| 2. FFI & mobile setup | 🟡 ~85% | Scan works end to end on Android: 24 devices in ~5s on a Chromecast (Android 14), and 21 devices on a Pixel 8 Pro (Android 17, 2026-10-11) including the location prompt. The iOS core compiles in CI, but the app has never run on an iPhone. |
| 3. UI/UX | ✅ | The "Precision Editorial Recon" design is built across 3 tabs (Overview, Tools, Account) plus onboarding. Topology is built but parked off the tab bar. Tools holds Node Inspect and the Homelab Agent screen; the device list is titled with the Wi-Fi name. Drift cache, real diagnostics, icons and splash are in. On a Pixel 8 Pro: cached devices on the first frame in about 100 ms, and ~1% of frames over 16.7 ms during a scan. |
| 4. Agent & cloud sync | 🟡 ~85% | Everything is built and merged: schema, accounts, the Rust agent, Realtime sync into the app, new-device alerts (the `notify-new-devices` function is deployed) and the Cloud & alerts rows in Settings. The Windows agent reports to Supabase (27 devices, all with MACs and vendors). Still open are live tests: a push on the Pixel (the exit criterion), Realtime sync on the Pixel, and pairing from the phone. |
| 5. Subscriptions | 🟡 ~85% | RevenueCat, Android first. Built, merged and live: the `revenuecat-webhook` function (#36), the app reading its plan from `my_plan()` and the RevenueCat billing service (#37), the paywall, Plan panel and upgrade points (#38, #40), the RevenueCat Android key in the app (#43), and `play-rtdn`, which keeps entitlements current from Google Play's own notifications (#44). Both functions are deployed with their secrets. A license tester's purchase on the Pixel unlocked Premium through `play-rtdn` on 2026-10-13, once its `PLAY_SERVICE_ACCOUNT` secret was fixed (it had been set without its JSON quotes, so every Play notification since 15:22 that day had failed). Cancel, renewal and refund are confirmed (a cancel keeps Premium until the period ends; a refund removes it within seconds of Play's voided-purchase notification). Restore is confirmed too (after a reinstall, signing in brought Premium back). Left: Play data safety, and the legal entity name. iOS follows with the iPhone. |
| 6. Network tools | ⬜ | Traceroute, DNS lookup, network details and a speed test. Ships after launch, as the first update. |
| 7. Recognition & security | 🟡 ~30% | Node Inspect shows Device and Operating system cards (brand, model, family, OS, with logos) from the MAC vendor, mDNS, the SSDP server string, the ping TTL and hostname patterns, and marks guesses LIKELY (#55–#57). Users can correct a card, and PingDuck reuses that answer for devices that look the same. The shared database, agent-side signals and the security checks are not started. |
| 8. Launch readiness | 🟡 ~20% | CI checks every PR and `main` is protected (CI/CD plan Phase 1). The first security audit is done (2026-10-13, nothing critical or high). The beta, store listings and the rest are not started. |

**Since 2026-10-06:** the agent was rewritten in Rust and gained its scan loop and a Windows
service; PingDuck for Windows and its installer were built; CI was split per component with
required checks on `main`; ten dependency updates were merged (including `ureq` 3 and `rand` 0.10
in the agent, and `permission_handler` 13, which needed Android SDK 37); and a client-side
Premium unlock was found and closed.

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
| ✅ | CI | M | `.github/workflows/core.yml`: Windows MSVC, Linux GCC + libpcap, Clang ASan/UBSan, fuzzing, Android NDK (3 ABIs), macOS and the iOS xcframework. Since 2026-10-11 the agent, app, database and iOS have their own workflows (see Phase 8, CI/CD). |

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
| 🟡 | Platform permissions and config | M | Android: permissions plus a `MulticastLock` in `MainActivity`, held only during scans. The location prompt and a full scan were checked on a Pixel 8 Pro running Android 17 (2026-10-11); the app compiles against SDK 37, which `permission_handler` 13 requires (`targetSdk` stays on Flutter's default). The deny path has not been tried on a device. iOS: `NSLocalNetworkUsageDescription` and `NSBonjourServices` are added. **Still needed:** the multicast entitlement, which must wait for Apple's approval (adding it early breaks signing). |
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
| ✅ | Supabase schema and RLS | M | `supabase/migrations/20261006120000_initial_schema.sql`: `plans` and `entitlements` (Fing-style tiers, limits as data), the daily scan quota (`claim_scan`), `networks`, `agents` with code pairing (`create_pairing_code`, `claim_pairing_code`, `revoke_agent`), `devices` and `device_events` written by `agent_sync`, `push_tokens`, `prune_history`, RLS on every table and Realtime on devices and events. Applied to the Supabase project; `supabase/tests/schema_test.sql` passes there (it runs in a rolled-back transaction, so it can be pasted into the SQL editor). `20261007120000_schedule_prune_history.sql` runs `prune_history` daily at 04:00 UTC with pg_cron. That migration had been skipped when migrations were pasted in by hand; it was applied on 2026-10-12, and the remote migration history was repaired the same day, so `supabase db push` now works from the CLI. |
| 🟡 | Auth in the app (`features/auth`) | M | Supabase Auth, enabled for anonymous and email sign-ins. The app signs in anonymously before its first scan, and `ScanQuota` claims each scan through `claim_scan` (Free: 3 a day), counting locally when offline. Scans the app starts itself (launch, Wi-Fi reconnect) do not count, but run at most once every 30 minutes on Free. The Overview banner shows when scans come back. The Account tab has email and password accounts. Creating one upgrades the anonymous user in place, so its id and data carry over, after the person clicks a link emailed to the address (it lands on `pingduck.app/confirmed`, which links back into the app through `pingduck://auth-callback`; the app also notices the confirmation by itself); there is also password reset by code, and Delete account (the `delete_account` RPC, which cascades to every user-owned row and emails a "Sorry to see you go" note through pg_net and Resend; Apple requires in-app deletion). Google, and Apple on iOS, are shown disabled. Widget-tested against a fake, and tested on the live project on 2026-10-08: sign-up, the confirmation email (sent through Resend) and its link, and sign-in all work. Delete account (`20261007130000_delete_account.sql` applied) was tested live on 2026-10-10. Password reset has not been tried live yet. Since #20 (2026-10-12) the sign-in screen reports server results as toasts (errors in red, plus link sent, code sent, signed in), and Delete account moves to Account › App settings › User settings. **Still needed:** try password reset on the live project, and wire up Google and Sign in with Apple. |
| 🟡 | Agent pairing | M | Built to match Fing's flow (plan: `.claude/plans/agent-pairing-lan-discovery.md`). Account → Add monitoring unit → platform (Linux/Proxmox, Raspberry Pi, Synology/QNAP) → numbered install steps, which can be emailed (`email_agent_instructions`, 3 an hour) → **Find my agent**. The new `pingduck-agent` (`agent/crates/pingduck-agent`, Rust around the C++ core) advertises itself over SSDP/UPnP and serves `GET /pingduck/v1/info` and `POST /pingduck/v1/pair` on port 44480. The app finds it with the core's existing SSDP discovery, registers the network in Supabase (only at this point), and hands the agent a `create_pairing_code` code over the LAN. The agent redeems it itself with `claim_pairing_code`, so the token never crosses the LAN, and keeps it in a 0600 file on its volume. A paired agent refuses new codes, and shows as Taken to other accounts. `agent_heartbeat` every 60 s keeps `last_seen_at` fresh and unpairs the agent within a minute of a revoke. `PINGDUCK_PAIRING_CODE` is the fallback for VLANs. The Homelab Agent screen shows status and Revoke. **The agent never holds the service-role key.** Tested: 25 Rust agent tests on Windows and Linux (they also run the agent's UPnP output through the core's own parser), 26 new app tests, schema tests pass, the image runs on `pingduck-vm` and Windows finds it over SSDP. Paired live on 2026-10-10 from the Windows app (Account › This PC, against the installed service; the first try found the app sending a chunked body, which the agent rejects, now fixed). The agent's Supabase client moved to `ureq` 3 on 2026-10-11 and was checked against the live project (HTTPS, a 200 and a 404 with their bodies). **Still needed:** the live test from the phone (the test VM's hypervisor filter blocks the phone; see Risks), then publishing the image again and making the GHCR package public (CI/CD plan Phase 2; CI stopped pushing the image when it was split per component). Windows: see `.claude/plans/windows-desktop-and-rust-agent.md`. |
| ✅ | Agent daemon | L | Built 2026-10-10 (`agent/crates/pingduck-agent/src/monitor.rs`, agent 0.3.0). While paired, the agent runs the core's combined scan (ICMP, mDNS, SSDP, reverse DNS, the OS neighbour table, and raw libpcap ARP on Linux) right after pairing and then every `PINGDUCK_SCAN_INTERVAL` (default 300 s, 60 s to 24 h). It reports each scan through `agent_sync`, with `p_offline_after` set to 2.5 scans (at least 10 min) so one missed reply doesn't flap a device offline. Only devices with a MAC are sent, since `agent_sync` keys on it; the agent fills in its own host's MAC, which the neighbour table never has. A failed or cancelled scan reports nothing, so it can't mark devices offline. Vendor names come from the bundled OUI registry (`pingduck_app/assets/oui_database/oui.csv`, the app's copy, shipped beside the Windows exe and in the image). `PINGDUCK_SCAN_CIDR` watches another subnet. The log records the first result, new and offline devices, and changes of state, not every scan. `pingduck-agent healthcheck` backs the image's Docker `HEALTHCHECK`; on stop, a running scan is cancelled. Tested: 33 agent and 5 core-binding tests, and a live scan on Windows (21 devices in 3.4 s, all with MACs and vendors). Confirmed 2026-10-12: the installed Windows agent (0.3.1) keeps `devices` current in Supabase (27 devices, all with MACs and vendors). |
| 🟡 | Intrusion alerts | M | Plan: `.claude/plans/phase-4-sync-and-alerts.md`. `agent_sync` collects the sync's new devices and calls `private.queue_new_device_alert` once (#24): no alert on the first sync after pairing, without the plan's `notifications` flag, for devices marked known, or for a private (rotating) MAC whose hostname matches a known device. It posts through pg_net to the `notify-new-devices` Edge Function (Phase E, 2026-10-12), which sends a **data-only** FCM message (`kind`, `network_id`, high priority) to the owner's Android tokens and deletes dead ones. The phone reads the details with the user's own session and shows one notification per network ("3 new devices on HomeWiFi": up to three names, then "and N more"), so no device data passes through Google. Only FCM is used from Firebase (no Analytics, no `google-services` plugin). Known-device allow-list: Inspector switch and "Mark all current devices as known" (#29). Settings › New-device alerts registers the phone; sign-out unregisters it. Tested: SQL rules in `schema_test.sql`, 4 Deno tests (message shape, dead tokens, hook secret), alert text and Settings switch widget tests. Deployed 2026-10-12: the function (JWT verification off; it rejects calls without the hook secret), its `FCM_SERVICE_ACCOUNT` and `NOTIFY_SECRET` secrets, and the Vault `notify_url` and `notify_secret`. The test account is Premium and the Pixel has registered a push token. **Still needed:** the live test (a new device joins, notification within 2 minutes; the agent scans every 5, so allow that); check the Vault `notify_secret` matches `NOTIFY_SECRET` if it fails with 401; iOS (APNs). |
| 🟡 | Realtime sync in the app (`services/supabase_sync.dart`) | M | Built in #25 (2026-10-12). For each local network linked to Supabase, the app fetches the agent's devices, merges them into the Drift cache by IP (filling MACs, vendors and missing names; agent-only devices are added with an Agent source; user names and notes are never overwritten) and re-fetches on Realtime changes (debounced 2 s). Starts after the first frame and on resume, restarts when an agent is paired or revoked, and Settings › Cloud sync turns it off. Tested with a fake repository and the real in-memory cache. **Still needed:** confirm on the Pixel against the live project. |
| 🟡 | PingDuck for Windows (Fing Desktop parity) | L | Plan: `.claude/plans/windows-desktop-and-rust-agent.md`. Built 2026-10-10: the Flutter app for Windows (`PingDuck.exe`: side rail, tray, single instance, start with Windows, Account › This PC pairs its own agent), the Rust agent as the `PingDuckAgent` service (`pingduck-agent install`), and `PingDuckSetup.exe` (Inno Setup; CI `windows-release.yml` on `desktop-v*` tags). **Still needed:** run the installer on a clean Windows VM, pair from the phone and from This PC, uninstall check; `pingduck://` links into the desktop app; code signing before launch. |
| 🟡 | Settings (`features/settings`) | S | Since #20 (2026-10-12), App settings has two tabs. **App** holds the reply timeout, Auto-scan on launch (Premium; the switch only saves the preference and is locked on Free) and the Cloud & alerts rows; **User settings** shows the profile and Delete account. Since Phase 4 C (2026-10-12), Cloud & alerts is real: the agent's status (online or last seen, version), a Cloud sync switch with its live state, "Mark all current devices as known", and the Inspector has a Known device switch. Since Phase E, the New-device alerts switch works on Android with Premium and an agent, and says why when it can't (no monitoring unit, Free plan, not Android). |
| ✅ | Proxmox deployment guide | S | `docs/PROXMOX.md` (2026-10-12): Docker in a VM (recommended) or LXC with nesting; the Proxmox firewall and libvirt `clean-traffic` filters that block discovery, with a `tcpdump`/`curl` check; logs and health check; pairing codes for VLANs; upgrades. The LXC path is untested. Moves to pingduck.app at launch. |

**Exit:** a new device joining the home LAN triggers a push notification within 2 minutes, and the app shows agent-sourced MACs and vendors.

---

## Phase 5: Subscriptions

**Goal:** a paid tier sold through the App Store and Google Play, unlocked across the user's devices and
enforced by the backend, not just the app.

Plan: `.claude/plans/phase-5-subscriptions.md`. Android first; the Play Console account exists, and the Apple Developer
account waits until there is an iPhone to test with.

Store rules shape this phase. On iOS and Android, digital features must be sold through Apple and Google
in-app purchase; Stripe (or any web checkout) cannot unlock them inside the app. A web checkout only makes
sense for a later desktop or web product.

| | Item | Size | Notes |
| --- | --- | --- | --- |
| ✅ | Tier definition | S | Free, Premium and Pro, mirroring Fing (see Decisions). Encoded in the `plans` table, which gates the scan quota, agent pairing and sync. |
| ✅ | App reads the plan from the server only | S | Done in #20 (2026-10-12). The Auto-scan switch used to write `isPremium` and `quotaLimit=none` on the device, which unlocked Premium for any free user; the auto-scan setting also counted as Premium and lifted the 30-minute limit on automatic scans. Now only `ServerScanQuota` caches the plan, from `claim_scan`, and nothing on the device can grant it. Store entitlements (below) will feed the same server answer. |
| ✅ | Billing integration (Android) | M | Built (#37) and switched on (#43, 1.0.0+12): `purchases_flutter` with RevenueCat, identified by the Supabase user id. Buying needs an email account, so Premium follows the user to a new phone. Premium only at launch, monthly and annual, 7-day trial on both. iOS later. |
| 🟡 | Server-side entitlements | M | Deployed (2026-10-13). `revenuecat-webhook` (#36) re-reads the subscriber from RevenueCat on every event and writes `entitlements` (`source = revenuecat`). RevenueCat sends webhooks only on its paid plans, so `play-rtdn` (#44) also takes Google Play's real-time notifications from Pub/Sub, checks the push's Google OIDC token, asks the Play Developer API for the subscription's state and writes `source = play`. It finds the user from RevenueCat's obfuscated account id (sha256 of the user id) or a purchase token seen before. Manual grants are never overwritten. `plan_for()` reads that table and ignores a period that has ended, so the scan quota, agent pairing, sync and alerts follow. Working end to end since 2026-10-13: a test purchase on the Pixel reached `entitlements` about 20 seconds after Play's notification got through. A `revenuecat` row can stay `active` past its period end when no later webhook arrives (test@webcap.cc's from 05:23 that day); that grants nothing, because `plan_for()` checks the period. Cancel confirmed (2026-10-13): the CANCELED notification kept Premium, and EXPIRED removed it 3 seconds after the period ended. Refund confirmed the same day: the voided-purchase notification removed Premium within seconds. |
| 🟡 | Paywall and upgrade points | M | Built (#38, #40): one paywall (yearly first, trial terms and renewal price before purchase, Restore, Terms, Privacy), opened from Add monitoring unit, the out-of-scans banner, the alerts row and the Account tab. Used for a real test purchase on the Pixel (2026-10-13). |
| 🟡 | Account tab: subscription state | S | Built (#38): the Plan panel shows Free or Premium, trial, renewal, cancelled or a payment problem, with Manage subscription (Google Play's page) and Restore purchases. Delete account warns while a subscription renews. |
| 🟡 | Legal | S | `/privacy` and `/terms` exist on pingduck.app and the paywall links to both. Updated for RevenueCat and Premium in the website repo (Pingduck.app #1). Still to confirm: the legal entity name (the app says "Big Duck Networks"). |
| 🟡 | Store setup | M | Play: the `premium` subscription (base plans `monthly` $4.99 and `annual` $34.99, a 7-day trial on each), license testers, and RevenueCat's service account and notifications. In progress, following the Phase 0 handoff doc. App Store Connect waits for the iPhone. |
| 🟡 | Tests | M | Unit and widget tests for both functions, the plan, paywall and Plan panel are in. A license tester's purchase unlocked Premium on the server (2026-10-13). Purchase, renewal, cancel, refund and restore after a reinstall all pass on the Pixel (2026-10-13). Not yet seen: a trial converting to paid. |

**Exit:** a license tester subscribes on Android, Premium unlocks on the server within a minute, and cancelling or
refunding revokes it. iOS repeats this once it has billing. **Met on Android on 2026-10-13.**

---

## Phase 6: Network tools 

After launch: the first update.

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

## Phase 7: Device recognition and security

**Goal:** close Fing's biggest advantage, which is naming what each device is (make, model, OS), and flag risky setups.

| | Item | Size | Notes |
| --- | --- | --- | --- |
| 🟡 | Fingerprint rules | L | First slice merged (#55–#57): brand, model, family and OS from the OUI, mDNS, UPnP model fields, the SSDP server string, the ping TTL and hostname patterns, with a LIKELY tag on guesses. The rules are Dart data (`recognition_rules.dart`), not a downloadable asset yet. Still to add: NetBIOS names, open ports and mDNS TXT records. Windows PCs can't be told apart by model from the phone (WS-Discovery only says "Microsoft Publication Service"). |
| ⬜ | Agent-side signals | M | The agent can see DHCP options (option 55 fingerprints) and HTTP banners the phone cannot. Feed them into the same rules. |
| ✅ | User corrections | S | Edit on the Device card sets brand, model and OS (SET BY YOU). Each answer is also remembered by the device's fingerprint (vendor, announced model and services, SSDP server without versions, initial TTL, hostname shape with names removed) and offered as a LIKELY guess for devices that look the same, on any network. All of it stays on the phone, like names and notes. |
| ⬜ | Shared recognition database | M | After launch. Corrections are counted by fingerprint in Supabase, and a label is shared only once at least 3 accounts agree. On by default with a "Device recognition" switch in Settings, like Fing (which sends full MACs and the public IP; we send only the fingerprint). Needs the privacy policy and the Play data safety form to cover it. Design: `.claude/plans/shared-recognition.md`. |
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
| 🟡 | CI/CD | Plan: `.claude/plans/ci-cd-overhaul.md`. **Phase 1 done** (2026-10-11): one workflow per component (core, agent, app, database, iOS weekly or on PRs labelled `apple`), each with a `<name> ci` job that reports on every PR; CodeQL; Dependabot; actions pinned to SHAs. `main` requires a PR and `core ci`, `agent ci`, `app ci`, `database ci` and `CodeQL` (no approvals, since the only maintainer can't approve their own PRs). `app ci` also builds a debug APK (added in #19, after an Android build break got through). **Phase 2 built** (2026-10-12): `agent.yml` pushes amd64 + arm64 images to GHCR on `main` as `:edge` and `:sha-<commit>`, signed with cosign (keyless) and carrying an SBOM and provenance; `release-agent.yml` (run by hand from `main`) re-tags that image as `:X.Y.Z`, `:X.Y` and `:latest` and tags `agent-vX.Y.Z`. Its tag and image checks are inline until the shared release guard (Phase 6). **Phase 3 done** (2026-10-12): release signing with an upload key (#32), and every `main` push builds a signed AAB kept as a workflow artifact for 30 days (#33). Uploads to Play stay manual; CI never uploads by itself. **Build numbers are the git commit count everywhere** (2026-10-13): CI stamps it for the AAB and the Windows installer, and `tools/build.ps1` (apk, appbundle, windows, installer) does the same locally and then restores the files, so the installer, the About screen and Play agree. Only the version name in `pubspec.yaml` is edited by hand; there are no more "bump app version" commits. **Phase 4 done** (2026-10-12): a Deploy database workflow, run by hand from `main` behind a required approval, shows a dry run of pending migrations before `supabase db push` (#34). **Next:** the Windows and release-guard phases, and `docs/RELEASING.md`. |
| 🟡 | Security audit | **First pass done** (2026-10-13), covering the migrations and live grants, the three Edge Functions, the app's keys and plan checks, and the agent's LAN endpoints. Nothing critical or high: every table has RLS, writes go through RPCs or the service role, and the webhooks check their callers. Three low findings, all addressed in PR #46. An unpaired agent can be paired by anyone on its LAN who has their own code; the pairing protocol is unchanged, but the app now explains a taken agent and shows how to reset it. The default TRUNCATE, TRIGGER and REFERENCES grants to `anon` and `authenticated` are revoked, now and for new tables. A new anonymous account no longer gets fresh Free scans: `claim_scan` also counts per Android device (stored hashed), and a scan the server can't confirm is refused. Still possible: a modified client, a factory reset, or Windows, which sends no device ID. Not covered yet: Supabase Auth settings, the website, and the Firebase API key's restrictions. Originally: run the `vibe-security` skill (`.claude/skills/vibe-security`) over the app, the `supabase/` migrations (RLS, the security-definer RPCs including `delete_account`, the `claim_scan` quota) and the website. Do it before the beta, and again once billing (Phase 5) and the agent (Phase 4) land. A manual review on 2026-10-12 already found one hole, a Premium unlock in Settings (fixed in PR #20), so look hard at anything else the app decides on its own. |
| ⬜ | Beta | TestFlight and Play internal testing. The agent image is at `ghcr.io/big-duck-networks/pingduck-agent` (amd64 + arm64): `:edge` follows `main`, and `:latest` moves only when `release-agent.yml` runs. The package is private until launch. |
| ⬜ | Crash reporting and analytics | PostHog (`posthog_flutter` in the app; optionally the website too). Opt-in. Product events only (scan started/finished, sign-up, paywall views); never IPs, MACs, hostnames, SSIDs or device lists. Before it ships, update the privacy policy, FAQ and homepage, which all say "no analytics", and add PostHog to the providers list. |
| ⬜ | **TODO at launch: publish `/agent`** | `pingduck_website/src/app/agent/page.tsx` (added 2026-10-10) is built but unlisted: `robots: noindex`, and nothing links to it. At launch: set `site.agentWindowsUrl` to the Windows installer's GitHub Releases URL, remove the `robots` line, link `/agent` from the nav, footer and FAQ, and make the GHCR image public. The app's Windows install steps already say "Go to pingduck.app/agent". |
| ⬜ | Privacy policy and store listings | App Store review notes explaining local network scanning, location (Wi-Fi name only) and the subscription. The policy itself is drafted in Phase 5; it must name Firebase Cloud Messaging as the alert channel (the payload is a network id only) and the Play data-safety form must list the FCM token. |
| ⬜ | Copy pass | Run the global `no-ai-slop` skill in Detect mode over the website (homepage, FAQ, privacy, terms), the store listings and the app's user-facing strings, then edit what it flags. |
| ⬜ | Dark mode | Follow the system setting, with Appearance: System / Light / Dark in App settings. The ~300 `PingDuckColors` uses (15 files, mostly `const`) and the colors baked into `PdText` become a `PdPalette` theme extension with light and dark values, read through the theme. The painters (radar, sparkline, topology, duck mark) take the palette as a parameter. Size M–L. |
| ⬜ | Performance and battery pass | Scan cost on older phones; agent CPU and memory on small hosts. |

---

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| **iOS multicast entitlement** (`com.apple.developer.networking.multicast`) needs Apple approval, which can take weeks | No mDNS/SSDP on iOS without it | Apply as soon as Phase 2 starts. Legacy-unicast mDNS replies may partly work without it; verify on a device. |
| **Randomized MACs** (iOS/Android private Wi-Fi addresses rotate) | "New MAC" alerts fire for known phones, causing alert fatigue | Treat locally administered MACs separately and match them on hostname/mDNS identity. Let users mark devices as known. |
| Android blocks multicast receive without a `MulticastLock` | mDNS/SSDP miss devices on some phones | Hold the lock during scans (Phase 2). |
| Parsers run on untrusted network input | Memory-safety bug becomes remote crash or exploit | Fuzz the parsers and run sanitizers in CI (Phase 1). |
| ~~Isar maintenance status is uncertain~~ | | Resolved: the cache uses drift (see Decisions). |
| Dependency updates raise platform requirements | `permission_handler` 13 required compiling against Android SDK 37 and a newer Android Gradle Plugin; it merged green because CI didn't build an APK, and broke Android builds until #19 | `app ci` now builds a debug APK, so a break like this fails the PR. Major updates still get a device check before release. |
| Docker host networking on Proxmox | Agent can't see the LAN from a default bridge network | Document the VM and privileged-LXC setups, and detect the bridge network at startup with a clear error. |
| Hypervisor traffic filters | During the ARP comparison, the KVM host's management layer (DuckStack) attached a libvirt MAC allowlist to the test VM, cutting it off from all but 3 hosts. It is not yet known whether the sweeps triggered it. It happened again on 2026-10-10 during the first pairing test: SSH to the VM dropped for hours, then the Pixel's ARP requests never reached the VM's NIC (tcpdump saw 0 packets) while the wired Windows box still got through, so the app found no agent. | Find out what triggered it before running the agent on that host. Cover hypervisor filters (libvirt `clean-traffic`, Proxmox firewall) in the deployment guide, and warn when an ARP sweep gets replies from almost none of the hosts that ICMP finds. Done in the app: Find my agent says "Found an agent, but can't connect" when an agent announces over SSDP but its port doesn't answer, and the No agent found checklist names VM network filters. A filter that drops all of the phone's traffic (as here) still looks like No agent found. |

---

## Decisions needed

| Decision | Options | Recommendation | Needed by |
| --- | --- | --- | --- |
| ~~Local cache~~ | **Decided: drift** (SQLite). | | ✅ |
| ~~Cloud sync engine~~ | **Decided: Supabase** (Postgres, Auth, Realtime) with the Drift cache on the phone. PowerSync was considered and dropped. | | ✅ |
| ~~OUI storage~~ | **Decided: CSV.** The app looks vendors up through `pd_oui_lookup` over FFI, so it never reads the table itself. SQLite would add a C dependency to the core for no gain. Load it off the UI thread at startup (0.36s on the slowest test device). | | ✅ |
| ~~Agent daemon language~~ | **Decided: Rust** (2026-10-10, replacing a short-lived C++ agent), for one agent on Linux/Docker and Windows. `agent/` is a Cargo workspace; `pingduck-core-sys` builds the C++ core with CMake and binds it over FFI, so the scanner stays C++. HTTP via `ureq` + rustls, no libcurl/OpenSSL. | | ✅ |
| Auth providers | Email password · Apple/Google sign-in | **Email and password shipped** (confirmed by an emailed link, reset by code), not the magic link first proposed. Still to decide: whether Google and Apple ship before launch. Apple sign-in is required on iOS if any social login ships. | Phase 4 |
| Device identity | MAC · IP · MAC with hostname fallback | **IP for now** (the app sees no MACs on Android). Switch to MAC with a hostname fallback when the agent supplies MACs. | Phase 4 |
| ~~Free vs Pro~~ | **Decided: mirror Fing's plans.** **Free:** 3 scans a day, the network tools, basic device recognition, no monitoring. **Premium** (Fing: $7.99/mo, $69.99/yr): unlimited scans, the Homelab Agent on up to 2 networks, full event history, push alerts, security checks, scheduled speed tests. **Pro** (Fing: $16.99/mo, $149.99/yr): 3 monitored networks; shared workspaces and multiple users come later. Limits live in the `plans` table. | | ✅ |
| ~~Billing provider~~ | **Decided: RevenueCat** (2026-10-12). One SDK for both stores, purchase validation, and a webhook into Supabase. It takes a share of revenue above a threshold. | | ✅ |
| ~~Pricing~~ | **Decided** (2026-10-12): Premium only at launch, **$4.99/month or $34.99/year** (about 42% less), with a **7-day free trial** on both. No lifetime option; Pro stays in `plans` but isn't sold yet. | | ✅ |
| ~~Monorepo package layout~~ | **Decided: FFI plugin package** (`packages/pingduck_core`). | | ✅ |
| ~~Launch scope~~ | **Decided** (2026-10-12): **Android first, after Phase 5 and Phase 8.** The network tools (Phase 6) ship after launch as the first update, and recognition (Phase 7) after that. iOS follows once there is an iPhone and a Mac for the first run, and Apple has granted the multicast entitlement. | | ✅ |
| ~~Free launch scan~~ | **Decided** (2026-10-12): Free users can switch Auto-scan on launch off and on; the server still runs Free automatic scans at most once every 30 minutes. | | ✅ |

---

## Timeline (proposed)

A plan, not a commitment: one developer, built from the size estimates above, assuming the
decided launch scope (Android first, after Phase 5 and Phase 8). Weeks start on Mondays. There is no
buffer beyond the holiday weeks, so any slip moves the launch.

| Weeks | Dates | Work | Done when |
| --- | --- | --- | --- |
| 1–2 | Oct 12 – Oct 25 | Pair from the phone (fix or replace the test VM's network filter first), try password reset live. Done early: agent rows land in `devices`, CI/CD Phase 2 (agent image). **Start the long-lead items:** Apple Developer account and the multicast entitlement request, Play Console and App Store Connect, the billing decision. | A phone-paired agent reports devices to Supabase |
| 3–4 | Oct 26 – Nov 8 | Built early (2026-10-12): Realtime sync into the app, intrusion alerts, the agent rows in Settings, the Proxmox guide. Left: the live tests on the Pixel. Spare time here can pull week 5 forward. | **Phase 4 exit:** a new device triggers a push within 2 minutes |
| 5 | Nov 9 – Nov 15 | Windows: installer on a clean VM, `pingduck://` links, code signing set up. CI/CD Phase 3 (signed Android builds as CI artifacts; Play uploads stay manual). | Every `main` push produces a signed AAB ready to upload |
| 6–9 | Nov 16 – Dec 13 | Phase 5, built early (2026-10-12): RevenueCat webhook, billing service, paywall, Plan panel, legal pages. Since done: Play and RevenueCat setup, both functions deployed, a test purchase unlocking Premium through `play-rtdn`. Left: data safety. Spare time can pull Phase 8 forward. | **Phase 5 exit:** a test subscription unlocks Premium on the server |
| 10–11 | Dec 14 – Dec 27 | Phase 8: security audit, copy pass, store listing and data safety, analytics. CI/CD release guard and `docs/RELEASING.md`. | Ready for a closed beta |
| 12–15 | Dec 28 – Jan 24, 2027 | Android closed beta, fixes, performance and battery pass; dark mode if time allows. | Beta feedback handled |
| 16 | Week of Jan 25, 2027 | **Android launch** (target). Publish `/agent` (Phase 8 TODO). | Live on Google Play |
| After | From Feb 2027 | Phase 6 (network tools, about 2 weeks) as the first update; then Phase 7 (recognition and security, about 4–5 weeks); Google and Apple sign-in; **iOS**, about 4 weeks after the first iPhone run, which needs a Mac and Apple's multicast approval. | |

## Suggested next steps

1. Finish the Phase 5 exit on the Pixel: as a license tester, a trial converting to paid (needs a tester account that hasn't used the trial). Purchase, renewal, cancel, refund and restore passed on 2026-10-13. Watch `entitlements` and `store_notifications` while doing it; the `play-rtdn` logs show failures that never reach the table. When setting a JSON secret, use `supabase secrets set --env-file`, since PowerShell strips the quotes from JSON passed on the command line.
2. Merge the legal page update (Pingduck.app #1), confirm the legal entity name, and fill in Play's data safety form (purchase history shared with RevenueCat, the FCM token, and the Android ID that `claim_scan` hashes, under "Device or other IDs").
3. Run the live push test (Phase 4 exit): with the Windows agent paired and the Pixel registered, have a new device join the LAN. Check Realtime sync on the Pixel at the same time.
4. Make the phone-to-agent pairing test possible: find what keeps attaching the hypervisor's MAC filter to `pingduck-vm`, or run the agent on another host.
5. Finish the security audit: Supabase Auth settings, the website, and the Firebase key restrictions.
6. First iPhone run once a Mac is available: app scan, `SOCK_DGRAM` ICMP check, and mDNS without the multicast entitlement.
