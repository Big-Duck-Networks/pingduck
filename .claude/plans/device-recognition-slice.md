# Device recognition: Brand, Model, Family and OS (Phase 7 slice)

Status: proposed 2026-10-13. Pulled forward from Phase 7 at the owner's request, before the Android launch.
Target: Fing's Device Detail cards (Device: Brand / Model / Family; Operating System: Brand / Name / Version,
each with a logo), filled only from real signals and marked when they are a guess.

## Goal and non-goals

**Goal:** Node Inspect gains a **Device** card and an **Operating system** card. A Lenovo PC on Windows shows
"Lenovo · ThinkCentre M70q · ThinkCentre series" and "Windows (Microsoft)"; an HP printer shows "HP ·
OfficeJet Pro 9010 · OfficeJet Pro series"; a phone with a private MAC shows only what is known.

**Not in this slice** (stays in Phase 7): exact OS versions from DHCP fingerprints (agent only), user corrections,
crowd data, router/security checks. Fing's "Product class" is skipped: it comes from Fing's own database.

## Design decisions

1. **The core collects signals; the app recognizes.** Recognition runs in Dart, in one place, from raw signals.
   The agent forwards the same signals to Supabase, so devices synced from the agent are recognized by the same
   code. One recognizer, no C++ rules engine, and rules can change without rebuilding the core or the agent.
2. **Store signals, not conclusions.** The Drift cache and `devices` keep the raw signals (TTL, SSDP server
   string, WS-Discovery maker/model). Brand, Family and OS are computed when shown, so a rules update re-labels
   every cached device at once.
3. **Rules ship as an asset** (`assets/recognition/rules.json`), like the OUI CSV: vendor-name aliases,
   model-to-family patterns and OS signatures. Updated in app releases for now; remote updates later.
4. **Confidence is shown.** Each field is `known` (the device said so: mDNS TXT, UPnP, WS-Discovery) or
   `guessed` (inferred: OUI, TTL, ports, hostname). Guesses are labelled "likely". Nothing is invented: a field
   with no signal is hidden, matching `DeviceKind`'s rule.
5. **Logos are bundled, small and optional.** A few dozen brand and OS marks from Simple Icons (CC0 SVGs), shown
   in a neutral tint so they sit in the Precision Editorial style. No logo, no gap: the card works without one.

## Signals

| Signal | Collected by | Status | Feeds |
| --- | --- | --- | --- |
| OUI vendor | core `oui.cpp` | have | Brand (guessed) |
| mDNS TXT `usb_MFG`/`manufacturer`/`mfg`, `ty`/`md`/`model`/`usb_MDL`/`am` | core `mdns.cpp` → `vendor`, `model` | have | Brand, Model (known) |
| mDNS service types (`_airplay`, `_companion-link`, `_googlecast`, `_ipp`…) | core → `services` | have | OS, Brand (guessed) |
| Apple model identifiers in TXT (`model=MacBookPro18,1`, `am=AppleTV11,1`) | core → `model` | have | Brand Apple, OS macOS/iOS/tvOS (known) |
| UPnP `<manufacturer>`, `<modelName>` | core `ssdp.cpp` → `vendor`, `model` | have | Brand, Model (known) |
| SSDP `SERVER:` header ("Linux/4.9 UPnP/1.0", "Microsoft-Windows/10.0 UPnP/1.0") | core `ssdp.cpp` | parsed, but only used as a model fallback | **new field** `server` → OS (known when it names one) |
| ICMP reply TTL | core `icmp.cpp` | **new** `ttl` | OS family (guessed: ≤64 Unix-like, ≤128 Windows, ≤255 network gear) |
| WS-Discovery (UDP 3702 probe, then the device's metadata over HTTP 5357) | **new** core `wsd.cpp` | **new**, needs a spike | Brand, Model of Windows PCs and many printers (known) |
| Hostname patterns (`DESKTOP-…`, `iPhone`, `Galaxy-S23`, `android-…`) | have | have | OS, Brand (guessed) |
| Open ports (3389, 445, 62078, 5000/5001…) | inspector port scan, on demand | have, not stored | OS (guessed), only when a port scan has run |

### WS-Discovery spike: done 2026-10-13, dropped

Result on the test LAN: this Windows PC (Gigabyte B650 EAGLE AX, domain network) answered a unicast Probe, and
its metadata was generic: `Manufacturer: Microsoft Corporation`, `ModelName: Microsoft Publication Service`,
plus `Computer: WEBCAP-717/Domain:wmg`. No firmware maker or model. It did not answer the multicast Probe. The HP
OfficeJet did not answer at all; only an ONVIF camera (10.42.0.58) answered the multicast Probe, with no model
fields. So Fing's PC models ("ThinkCentre M70q") come from its crowd-sourced database, not from the wire.
WS-Discovery is out of this slice; Windows is recognized from TTL, hostname patterns and SSDP instead. PCs get
Brand from the OUI (often the NIC or board maker, so marked "likely") and no Model.

### WS-Discovery spike (original plan)

The bet: Windows' Function Discovery Resource Publication service answers a WS-Discovery Probe, and its
metadata (`ThisModel`: `Manufacturer`, `ModelName`) carries the PC's firmware maker and model, which is
likely where Fing's "Lenovo / ThinkCentre M70q" comes from. Check against this Windows PC and the HP printer:
send a Probe to 239.255.255.250:3702, follow the `XAddrs` with a WS-Transfer Get, read `ThisModel`.
It only answers on networks marked Private with network discovery on; note how often that holds.
If the fields are generic ("Microsoft Corporation"), drop WS-Discovery from the slice and rely on the rest.

## Changes by layer

### Core (C++)
- `pd_device` gains `int16_t ttl` (-1 unknown) and `char server[96]`. ABI change: bump `pd_version`,
  update the Dart FFI struct and `pingduck-core-sys`.
- `icmp.cpp`: record the TTL of the echo reply (IP header on raw sockets; `IP_RECVTTL`/`IP_TTL` cmsg on
  Android's `SOCK_DGRAM` ICMP; Windows `IcmpSendEcho` reply options).
- `ssdp.cpp`: copy the `SERVER` header into `server` and stop using it as a model fallback.
- `wsd.cpp` (if the spike passes): Probe plus metadata Get, merged into `vendor`/`model` with a new
  `PD_SRC_WSD` source bit. Hard limits on response size, fuzzed like the other parsers.
- Tests: parser unit tests and fuzz targets for the SSDP server line and WS-Discovery XML.

### Agent (Rust) and Supabase
- Migration: `devices` gains `ttl smallint` and `server text` (and nothing derived).
- `agent_sync` accepts and stores them; the agent sends them. `RemoteDevice.columns` reads them.
- Schema test updated.

### App (Dart)
- `DiscoveredDevice` gains `ttl` and `server`; the Drift cache adds both columns (migration step, using the
  existing `_addColumn` guard); `mergeRemoteDevices` fills them from the agent.
- New `features/recognition/`: `Recognizer.of(device, kind)` → `Recognition { brand, model, family, os }`,
  each a `(value, confidence)`; loads `rules.json` once at startup next to the OUI table.
- Node Inspect: a **Device** card and an **Operating system** card under the header, rows only for known
  fields, "likely" on guesses, logo on the right when bundled. The header subtitle uses the recognized
  Brand · Model. The device list keeps its current line, using the clean brand name.
- `DeviceKind` gains inputs from the recognizer where they help (an OS of iOS or Android implies mobile).

## Tests
- Recognizer unit tests from real captures: this Windows PC, the HP OfficeJet, the Chromecast, an iPhone, the
  Pixel, the router, a private-MAC phone (shows almost nothing, and says so).
- Widget tests for both cards (all fields, guesses, nothing known).
- Live check on the Pixel and Windows against the test LAN; agent-synced devices get the same labels.

## Order of work
1. WS-Discovery spike (keep or drop).
2. Core: TTL and SSDP server (+ WS-Discovery if kept), tests and fuzzing.
3. Bindings: Dart FFI struct, `pingduck-core-sys`, agent payload, migration.
4. App: model and cache, recognizer and rules, the two cards.
5. Device check, roadmap update.

Estimate: about a week, as one PR per layer (core, agent + database, app).

## Open questions
- Logos: Simple Icons covers most brands and OSes under CC0; brand owners' guidelines still apply to how marks
  are shown. Fine for nominative use in a network tool, but confirm before the store listing shows them.
- Should the agent's DHCP listener (Phase 7) land in this slice for exact Windows/Android versions? Proposed: no.
