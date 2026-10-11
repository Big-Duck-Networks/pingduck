# Feature: PingDuck for Windows (Fing Desktop parity) and the Rust agent

Builds on `.claude/plans/agent-pairing-lan-discovery.md` (LAN pairing, done 2026-10-10). Read it first.

## Feature Description

PingDuck on a Windows PC, 1:1 with Fing Desktop on Windows: one installer from pingduck.app/agent puts the
**PingDuck desktop app** (the Flutter app, built for Windows: Overview, device list, Tools, Account) and an
always-on **PingDuck Agent service** on the PC. The app lives in the tray, starts with Windows, and after you
sign in it offers to use the PC as a monitoring unit. The phone's Add monitoring unit flow gets Fing's
Windows path ("Go to your PC now → type pingduck.app/agent → install → sign in").

At the same time the agent is rewritten in **Rust** (decided 2026-10-10, reversing "C++ agent"), so one
agent codebase runs as the Docker image on Linux/Pi/NAS and as a Windows service. The scanner stays in C++
(pingduck-core, fuzzed and tested) and is called over FFI.

## User Story

As someone whose always-on computer is a Windows PC
I want to install PingDuck on it like Fing Desktop, sign in, and have it monitor my network
So that I get MACs, 24/7 monitoring and alerts without Docker or a Linux box

## Decisions (user, 2026-10-10)

- Agent language: **Rust**, replacing the C++ agent (no two agents).
- Windows: **full desktop app + tray**, like Fing Desktop (option B), not a tray-only agent.
- Installer download lives at **pingduck.app/agent**, unlisted until launch (page built; TODO in ROADMAP Phase 8).

## Defaults taken (from the options I proposed; confirm if any is wrong)

- pingduck-core stays C++; Rust builds it with the `cmake` crate and binds the ~10 `pd_*` functions by hand.
- No Npcap on Windows (OEM licence needed to bundle). MACs come from the core's existing Windows path
  (`GetIpNetTable2` / `SendARP` after the ICMP sweep, `core/src/icmp.cpp:278-295`).
- Desktop UI = the existing Flutter app with a Windows target, not a Rust GUI.
- macOS desktop is out (Fing has it; we show only what exists).

## Architecture

```
 Windows PC
 ┌──────────────────────────────┐        ┌──────────────────────────────────┐
 │ PingDuck.exe (Flutter)       │        │ PingDuckAgent service (Rust)     │
 │  Overview / Tools / Account  │ HTTP   │  same code as the Docker agent   │
 │  tray icon, start with Win   │──────▶ │  SSDP + :44480 LAN API           │
 │  "Monitor this network"      │127.0.0.1│  pingduck-core (C++, static)     │
 └──────────────┬───────────────┘        └──────────────┬───────────────────┘
                │ Supabase (user session)               │ Supabase (agent token)
                ▼                                       ▼
        create_pairing_code ──code──▶ POST /pingduck/v1/pair ──▶ claim_pairing_code
```

The desktop app pairs its own PC exactly the way the phone pairs a LAN agent, only against `127.0.0.1`.
No new server RPCs; the activate path in `AgentPairingController` is reused with the loopback address.

## Phases

### Phase 1 — Rust agent, Linux parity (replaces `agent/src` C++)

- `agent/` becomes a Cargo workspace:
  - `crates/pingduck-core-sys`: `build.rs` runs CMake on `../core` (`PINGDUCK_BUILD_SHARED=OFF`, CLI/tests off,
    `PINGDUCK_PCAP=ON` on Linux, OFF on Windows), links `pingduck` static + `pcap` (Linux) / `ws2_32 iphlpapi`
    (Windows). Hand-written `extern "C"` for `pd_version, pd_default_interface, pd_scan, pd_cancel,
    pd_oui_load, pd_set_lan_hints` and the `pd_device` / `pd_interface` structs (`#[repr(C)]`, sizes asserted
    in a test against `core/include/pingduck/pingduck.h`).
  - `crates/pingduck-agent` (bin + lib): port of `config, state, agent (routes/pairing/heartbeat),
    http_server, ssdp_responder, supabase_client, main` with the **same wire contract** (port 44480, JSON
    shapes, error codes, UPnP description, SSDP replies). Crates: `ureq` (rustls) for Supabase, `serde_json`,
    `socket2` (SO_REUSEADDR/PORT, multicast join), `uuid`, `rand`. HTTP server hand-rolled on `std::net`
    with the same limits (4 KB headers, 1 KB body, 2 s, 8 connections) — no framework.
- Port all 20 C++ tests to `cargo test`, keeping the cross-check that the description XML parses through the
  core's own `pd::ssdp::apply_description` (exposed via a tiny test-only C shim in `core/tests`, or replaced
  by an integration test that runs `pingduck_cli ssdp` against a live agent on Linux CI).
- Dockerfile: Rust builder stage (`rust:1-bookworm`), runtime unchanged (`libpcap0.8`, no libcurl).
- CI: `cargo test` + `cargo clippy -D warnings` on Linux and Windows; image build/publish as before.
- Delete `agent/src`, `agent/tests`, `agent/CMakeLists.txt` (C++), keep `agent/compose.yaml`.
- **Exit:** Docker agent on `pingduck-vm` is found by `pingduck_cli ssdp` and passes the same live checks as
  the C++ one (info, bad code 400, pair via env var, revoke → unpaired within 60 s).

### Phase 2 — Agent as a Windows service

- `windows-service` crate: `pingduck-agent.exe service` runs under SCM as `PingDuckAgent` (LocalSystem,
  auto start, restart on failure). `pingduck-agent.exe` without args runs in the console for debugging.
- State in `%ProgramData%\PingDuck\agent.json`, ACL'd to SYSTEM + Administrators (the token file).
- SSDP on Windows: bind 1900 with `SO_REUSEADDR` alongside the built-in SSDP Discovery service; if Windows
  refuses, fall back to answering only on the HTTP port and rely on loopback pairing + manual code (log it).
- Interval scan loop is still the Agent daemon ticket; this phase ships pairing + heartbeat like Linux.
- **Exit:** service installed by hand on this PC (10.42.0.193) is found by the Pixel's Find my agent, pairs,
  survives a reboot, and unpairs on revoke.

### Phase 3 — PingDuck desktop app (Flutter Windows)

- `flutter create --platforms=windows .` in `pingduck_app`; the FFI plugin already builds `core/` on Windows.
- Desktop shell: at ≥ 900 px wide, `NavigationRail` + content instead of the bottom bar; window min size;
  keyboard shortcuts (Ctrl+R scan). Phone layout unchanged.
- Platform gaps to fill on Windows: `network_info_plus` (Wi-Fi name; wired PCs have none → show the
  adapter/subnet), `permission_handler` and `MulticastLock` no-ops, notification permission prompt skipped.
- Tray (`tray_manager`) + window (`window_manager`): close hides to tray; tray menu "Open PingDuck",
  "Scan now", "Monitoring: on/off", "Quit". `launch_at_startup` with a `--minimized` flag.
- Account → **Use this PC as a monitoring unit** (signed in + Premium): registers the network, gets a code
  and posts it to `http://127.0.0.1:44480/pingduck/v1/pair` (reuse `AgentPairingController.activate` with a
  loopback `FoundAgent`). Shows the service status (not installed / waiting / paired / revoked).
- Deep links: `pingduck://` registered by the installer, so the email confirmation page opens the desktop app.
- **Exit:** on this PC the desktop app scans the LAN, shows devices with MACs, sits in the tray, starts with
  Windows, and pairs its own service in one click after sign-in.

### Phase 4 — Installer and releases

- **Inno Setup** (one `PingDuckSetup.exe`, like Fing's): installs the Flutter release folder to
  `%ProgramFiles%\PingDuck`, `pingduck-agent.exe` beside it, registers and starts the service, adds firewall
  rules (`netsh advfirewall`: TCP 44480 in, UDP 1900 in, private profile only), Start menu + optional
  desktop shortcut, `pingduck://` protocol, uninstaller that stops/removes the service and rules (keeps
  `%ProgramData%\PingDuck` unless "remove my data" is ticked).
- CI `windows-release.yml` on tags `desktop-v*`: Flutter build windows, cargo build --release, Inno compile,
  upload to GitHub Releases as `PingDuckSetup.exe` (stable URL: `releases/latest/download/PingDuckSetup.exe`).
- Code signing: not in v1 (SmartScreen will warn); tracked in ROADMAP Phase 8.
- **Exit:** fresh Windows VM: install from the release asset, sign in, monitor; uninstall leaves nothing running.

### Phase 5 — Phone app + email + website

- Select platform screen gets Fing's grouping: **PingDuck Desktop** → Windows; **PingDuck Agent** → Linux or
  Proxmox, Raspberry Pi, Synology / QNAP NAS.
- Windows steps, Fing's wording: 1 Go to your PC now · 2 Type pingduck.app/agent in your browser · 3 Install
  PingDuck · 4 Sign in to get your data in sync. Primary stays Find my agent (also finds the PC).
- New migration (`20261011120000_agent_instructions_windows.sql`) adding `'windows'` to
  `email_agent_instructions` (don't edit the applied one).
- Website `/agent` already lists Windows; update copy once the installer exists. Stays unlisted.

## Risks

| Risk | Mitigation |
| --- | --- |
| Rust toolchain absent on this PC | Install rustup (MSVC host) before Phase 1. |
| Windows SSDP Discovery service holds UDP 1900 | SO_REUSEADDR; else loopback pairing + manual code; log clearly. |
| Windows Firewall blocks 44480/1900 by default | Installer adds private-profile rules; Find my agent's "can't connect" panel already names firewalls. |
| Unsigned installer / SmartScreen | Accept for beta; sign before launch. |
| Wired PCs have no SSID | Network label falls back to subnet (already how `networkTitle` works). |
| Flutter desktop plugin gaps | Each plugin call behind the existing interfaces; Windows impls or no-ops. |

## Validation per phase

- P1: `cargo test`, `cargo clippy`, `docker build` + live checks on `pingduck-vm` (when reachable from the phone).
- P2: install service on this PC, Pixel Find my agent → Activate → Homelab Agent shows it ONLINE.
- P3: `flutter test`, `flutter build windows`, manual run on this PC.
- P4: install on a clean Windows VM, uninstall check.
- P5: `flutter test`, schema tests.

## AMENDMENTS

- 2026-10-10 — Phases 1-5 built in one session. Status:
  - P1 done: Rust workspace replaces the C++ agent (deleted; it was never committed). 25 agent + 2 FFI tests pass on Windows and Linux; clippy clean; image built and running on pingduck-vm, found over SSDP from Windows. The FFI test shim (`crates/pingduck-core-sys/shim`) runs the agent's UPnP output through the core's own parser.
  - P2 code done: `pingduck-agent install|uninstall [--purge]|service` (windows-service crate), log file in %ProgramData%\PingDuck, icacls lock to SYSTEM+Administrators, firewall rules (private+domain profiles). Console run verified on this PC (shares UDP 1900 with Windows' SSDP service; found over SSDP). **Not run as a service yet** (needs elevation).
  - P3 done: `windows/` target, exe `PingDuck.exe`, wide layout (NavigationRail ≥ 900 px), close-to-tray + tray menu (Open, Scan now, Quit), single instance (named mutex), `--minimized` start, Start with Windows (HKCU Run via reg.exe; `launch_at_startup` conflicts with our deps), Account › This PC panel pairing the local service over 127.0.0.1. `isDesktop` is off under `flutter test` unless `debugDesktopOverride`.
  - P4 done: `installer/windows/pingduck.iss` (Inno Setup) builds `PingDuckSetup.exe` (13.6 MB); `windows-release.yml` publishes it on `desktop-v*` tags. **Not installed on a machine yet.**
  - P5 done: Fing's grouping (PINGDUCK DESKTOP / PINGDUCK AGENT), Windows first with Fing's four steps; `20261011120000_agent_instructions_windows.sql`; website /agent copy.
  - Fixes found on the way: the FFI plugin's CMake couldn't find core/ through `.plugin_symlinks`; core install() rules broke the Flutter Windows install step (now top-level only).
  - Deferred: `pingduck://` protocol + forwarding a second instance's URL (app_links) — email confirmation links still open the browser page; code signing.
