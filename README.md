# PingDuck

Hybrid LAN discovery and monitoring: a Flutter mobile app plus an optional
headless Docker agent, both driven by the same C++ scanning engine. See
[docs/PRD.md](docs/PRD.md) for the product requirements and
[docs/ROADMAP.md](docs/ROADMAP.md) for the plan.

```text
pingduck/
├── core/           pingduck-core: C++17 engine with a plain C ABI (pingduck.h) + CLI
├── pingduck_app/   Flutter app (iOS / Android), feature-first layout
├── agent/          Docker image for the headless agent (libpcap ARP mode)
├── supabase/       Database migrations and schema tests (Phase 4)
├── tools/          Build number and version generator utilities
└── docs/           PRD, technical specifications (IEC/IEEE 82079-1), and design notes
```

## Status

As of 2026-10-12. Details, the proposed timeline and what's next are in
[docs/ROADMAP.md](docs/ROADMAP.md).

| Phase | Scope | State |
| ----- | ----- | ----- |
| 1 | Core engine: ICMP, mDNS, SSDP/UPnP, ARP, port scan, WoL, OUI | Done: tested, fuzzed, CI on all targets; libpcap ARP matches `arp-scan` |
| 2 | Dart FFI bridge, Riverpod state, mobile setup | Done on Android; the app has not run on an iPhone yet |
| 3 | Radar UI, device details, local cache | Done |
| 4 | Accounts, Rust agent, cloud sync, intrusion alerts | In progress: accounts and agent pairing work, the agent scans and syncs; Realtime sync and alerts are next |
| 5 | Subscriptions | Tiers decided; billing not started |
| 6 | Network tools (traceroute, DNS, speed test) | Not started |
| 7 | Device recognition and security checks | Not started |
| 8 | Launch readiness | CI and branch protection done; audit, beta and store listings not started |

## pingduck-core

One public header, [`core/include/pingduck/pingduck.h`](core/include/pingduck/pingduck.h).
Everything is fixed-size C structs and C callbacks so Dart FFI can bind it
directly. The main entry point is `pd_scan()`. It runs every discovery method in
parallel, merges results by IP, and fires the callback whenever a device appears
or gains information, so consumers just upsert by IP.

| Method        | How                                                                                                       | Works in mobile sandbox?              |
| ------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| ICMP sweep    | `IcmpSendEcho` (Windows), unprivileged `SOCK_DGRAM` ping sockets (Linux/Android/iOS), raw socket fallback | Yes                                   |
| mDNS / DNS-SD | Legacy-unicast PTR queries + follow-up on enumerated service types; resolves instance → SRV → A           | Yes                                   |
| SSDP / UPnP   | M-SEARCH, then fetches each device's description XML (friendlyName, manufacturer, model)                  | Yes                                   |
| Reverse names | Parallel DNS PTR + unicast mDNS + NetBIOS node status, hard 1.5 s cap                                     | Yes                                   |
| OS ARP cache  | `GetIpNetTable2` / `/proc/net/arp`                                                                        | No (blocked on Android 10+ / iOS 14+) |
| ARP sniffing  | libpcap who-has injection + reply capture                                                                 | Agent only (root / `CAP_NET_RAW`)     |
| OUI vendor    | IEEE MA-L/MA-M/MA-S CSV, plus QEMU/KVM, Docker, Hyper-V and randomized-MAC detection                      | Yes                                   |

### Build

Windows (MSVC, with the CMake that ships in VS Build Tools):

```sh
cmake -S core -B core/build -G "Visual Studio 17 2022" -A x64
cmake --build core/build --config Release
core/build/bin/Release/pingduck_cli.exe scan
```

Linux (agent, with ARP sniffing):

```sh
sudo apt install build-essential cmake libpcap-dev
cmake -S core -B core/build -DCMAKE_BUILD_TYPE=Release -DPINGDUCK_PCAP=ON
cmake --build core/build -j
sudo core/build/pingduck_cli scan --arp
```

Android (NDK cross-compile):

```sh
cmake -S core -B core/build-android -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24
cmake --build core/build-android
```

Vendor names need the IEEE registry (not committed):

```sh
mkdir -p core/data && curl -fsSL -o core/data/oui.csv https://standards-oui.ieee.org/oui/oui.csv
pingduck_cli scan --oui core/data/oui.csv
```

### CLI

```text
pingduck_cli info                  interfaces + chosen LAN interface
pingduck_cli scan [cidr] [--arp]   full merged scan
pingduck_cli sweep|mdns|ssdp|arp   one method at a time
pingduck_cli ping <ip> [count]
pingduck_cli ports <ip> [ports]    default 21 22 80 443 3389
pingduck_cli wol <mac> [bcast]
pingduck_cli oui <mac> --oui oui.csv
  -t <ms> timeout   -j JSON lines   --no-dns
```

### Measured (home LAN, /24, ~25 devices)

- Windows desktop: full scan in ~3.4 s, all MACs resolved via the ARP cache.
- Android 14 (Chromecast w/ Google TV, `adb shell`): 20 devices in 3.6 s.

## Agent

```sh
docker build -f agent/Dockerfile -t pingduck-agent .
docker run --rm --net=host --cap-add=NET_RAW --cap-add=NET_ADMIN pingduck-agent
```

## Versioning & Build Generator

The Flutter app version in [`pingduck_app/pubspec.yaml`](pingduck_app/pubspec.yaml) is managed by [`tools/build_number_gen.dart`](tools/build_number_gen.dart). It automatically synchronizes the version, build number, and Git commit hash into a compile-time constant file at [`pingduck_app/lib/core/constants/app_version.dart`](pingduck_app/lib/core/constants/app_version.dart).

```sh
# Standard build increment (1.0.0+1 -> 1.0.0+2)
dart run tools/build_number_gen.dart

# Semantic version releases
dart run tools/build_number_gen.dart --patch      # 1.0.0+1 -> 1.0.1+2
dart run tools/build_number_gen.dart --minor      # 1.0.0+1 -> 1.1.0+2
dart run tools/build_number_gen.dart --major      # 1.0.0+1 -> 2.0.0+2
dart run tools/build_number_gen.dart --calver     # Date-based (YYYY.MM.DD)

# CI/CD & Inspection
dart run tools/build_number_gen.dart --sync       # Read current version (e.g. 1.0.0+1)
dart run tools/build_number_gen.dart --sync --json # Machine-readable JSON output
dart run tools/build_number_gen.dart --dry-run    # Preview changes without modifying files
dart run tools/build_number_gen.dart --git        # Use Git commit count as build number
dart run tools/build_number_gen.dart --github-output # Export to $GITHUB_OUTPUT for CI
```

Flutter widgets can access compile-time version metadata with zero async overhead:

```dart
import 'package:pingduck_app/core/constants/app_version.dart';

Text(AppVersion.display);     // "v1.0.0 (2)"
Text(AppVersion.gitCommit);   // "5c826f2"
```

## Mobile App & Flavors

PingDuck supports multiple flavors so development builds run side-by-side with production releases on the same device:

| Flavor | Application ID | App Name | Branding & Theme |
| ------ | -------------- | -------- | ---------------- |
| `dev` | `app.webcap.pingduck.dev` | PingDuck Dev | Amber duck (`#D97706`), Emerald beak/badge, `[dev]` tag in version |
| `prod` | `app.webcap.pingduck` | PingDuck | Canonical Emerald duck (`#059669`), Amber beak, production release |

### Running Locally

```sh
# Run dev build (installs side-by-side as PingDuck Dev)
flutter run --flavor dev -t lib/main.dart

# Run production build
flutter run --flavor prod -t lib/main.dart
```

### Packaging & Builds

Using [`tools/build.ps1`](tools/build.ps1):

```powershell
# Build signed Android App Bundle (AAB) for production
.\tools\build.ps1 -Platform android -Flavor prod

# Build Dev APK for testing
.\tools\build.ps1 -Platform android -Flavor dev
```

### Brand Assets & Icons

All launcher icons and native splash screens are rendered programmatically from vector math in [`pingduck_app/tool/make_brand_assets.py`](pingduck_app/tool/make_brand_assets.py):

```sh
cd pingduck_app
uv run --with pillow python tool/make_brand_assets.py
dart run flutter_launcher_icons && dart run flutter_launcher_icons:main -f flutter_launcher_icons-dev.yaml
dart run flutter_native_splash:create -F dev,prod
```

## License

PingDuck is source-available, with an open-source agent:

- **`agent/` and `core/`** (the monitoring agent and the scanning engine): [Apache License 2.0](agent/LICENSE). Use, audit, modify and ship them freely.
- **Everything else** (the app, backend, installer, branding and docs): [Functional Source License 1.1](LICENSE.md) (FSL-1.1-ALv2). You can read, run and modify it for any purpose except offering a competing product or service. Each version becomes Apache-2.0 two years after its release.

"PingDuck" and the duck logo are trademarks of Big Duck Networks and aren't covered by either licence.
