# Product Requirements Document (PRD): PingDuck

**Document Owner:** Carl Nieves, Webcap Media Group

**Product Name:** PingDuck (formerly OmniScan)

**Target Platforms:** iOS & Android (Flutter Frontend), Linux/Proxmox (Docker Agent)

**Date:** October 2026

---

## 1. Executive Summary & Vision

PingDuck is a hybrid network discovery and cybersecurity monitoring platform designed to provide total visibility into local area networks. By pairing an accessible mobile frontend with a robust, optional headless scanning agent, PingDuck circumvents modern mobile OS sandbox restrictions. It allows both everyday consumers and advanced homelab users to identify connected devices, monitor performance, and detect unauthorized network access in real-time.

## 2. Brand Identity & UI/UX Strategy

* **Brand Name:** PingDuck
* **Visual Theme:** Tech Dark background paired with "Duck Yellow" accents for high-contrast, modern readability.
* **Brand Voice:** Playful and approachable on the surface, but highly technical and capable under the hood.
* **UI Core:** Mascot-driven interfaces and smooth, animated state transitions to prevent static loading screens. The primary view is a "Radar" or "Cortex Map" where cached devices are instantly displayed in a dimmed offline state, illuminating in real-time as they respond to active network sweeps.

## 3. System Architecture

```
Document Identifier: DOC-PRD-PINGDUCK-001
Standard Compliance: IEC/IEEE 82079-1:2019 Edition 2.0
Document Version:    1.1.0
Status:              Approved
Date of Issue:       2026-10-06
Product:             PingDuck Network Discovery & Reconnaissance Platform
```

PingDuck utilizes a "Write Once, Run Anywhere" architecture, ensuring the heavy networking logic is unified across all platforms.

| Component                     | Technology              | Role & Functionality                                                                                                                                                    |
| ----------------------------- | ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Core Scanning Engine**      | C/C++ (`pingduck-core`) | The low-level brain handling socket connections, ICMP packets, mDNS broadcasts, UPnP XML parsing, and raw ARP packet sniffing (`libpcap`).                              |
| **Mobile Frontend**           | Flutter & Dart FFI      | The consumer-facing UI for iOS and Android. Dart FFI binds directly to the C++ binary in-memory for native execution speeds without writing Kotlin/Swift bridging code. |
| **Headless Agent**            | Docker / Linux          | The same C++ engine wrapped in a headless daemon deployed on homelab servers (e.g., Proxmox) for 24/7 continuous network monitoring.                                    |
| **Cloud Sync & Auth**         | Supabase                | Handles user authentication, PostgreSQL database syncing between the mobile app and the Docker agent, and routing push notifications.                                   |
| **Local Cache**               | Drift (SQLite)          | Stores previously discovered networks and devices locally on the mobile device for instant UI rendering upon app launch.                                                  |

## 4. Technical Constraints & Sandboxing Strategy

Modern operating systems (iOS 14+ and Android 10+) strictly prohibit mobile applications from reading the system ARP table, preventing native MAC address resolution. PingDuck employs a dual-mode strategy to solve this:

* **Mobile Sandbox Mode (On-the-go):** When scanning from the phone, the C++ engine relies on concurrent ICMP ping sweeps across the local `/24` subnet. It then immediately fires mDNS (Bonjour/Zeroconf) and UPnP multicasts to the active IPs to extract hostnames, services, and hardware vendors.
* **Docker Agent Mode (At-home):** When deployed on a local server, the agent runs with elevated root privileges. It bypasses the sandboxed ICMP limitations by utilizing `libpcap` to sniff raw ARP replies, capturing exact MAC addresses. It then cross-references an embedded SQLite database of IEEE OUI assignments to identify the exact device manufacturer (e.g., Apple, Netgear, Synology) and syncs this enriched data back to the mobile app via Supabase.

## 5. MVP Feature Scope

1. **Active Network Discovery:** Sub-15-second ping sweeps of local subnets to detect active IPv4 devices.
2. **Device Identification:** Multi-layered recognition utilizing MAC OUI lookups (Agent) and mDNS/UPnP broadcast parsing (Mobile).
3. **Real-Time Radar UI:** A sortable device inventory displaying IP addresses, hostnames, detected vendors, and historical connection statuses.
4. **Intrusion Alerts (Agent Required):** 24/7 background monitoring that triggers push notifications when a new or unrecognized MAC address joins the network.
5. **Device Diagnostics:** A single-device detail view containing a Wake-on-LAN trigger, continuous ping latency charts, and lightweight port scanning for common vulnerabilities (ports 21, 22, 80, 443, 3389).

## 6. Directory Structure

The Flutter application follows a feature-first architecture to keep the UI decoupled from the native C++ engine and cloud sync logic.

```text
pingduck_app/
├── android/
├── ios/
├── assets/
│   ├── icons/               # PingDuck logos and mascot SVGs
│   └── oui_database/        # Local SQLite fallback DB for offline MAC lookups
├── lib/
│   ├── core/
│   │   ├── constants/       # Supabase keys, API endpoints, styling variables
│   │   ├── ffi/             # The C++ Bridge (scanner_bridge.dart)
│   │   ├── network/         # IP calculation and mDNS utility classes
│   │   ├── storage/         # Drift database tables and schema
│   │   └── theme/           # PingDuck brand colors (Duck Yellow, Tech Dark)
│   ├── features/
│   │   ├── auth/            # Supabase login and session state
│   │   ├── scanner/
│   │   │   ├── application/ # Riverpod controllers (scan state, ping orchestration)
│   │   │   ├── domain/      # DiscoveredDevice models
│   │   │   └── presentation/# The main Cortex Map / Radar UI
│   │   ├── device_details/
│   │   │   ├── application/ # Port scanning and wake-on-lan triggers
│   │   │   └── presentation/# Single device view (IP, MAC, Vendor, Ping history)
│   │   └── settings/        # Agent pairing, cloud sync toggles, push notifications
│   ├── services/
│   │   ├── supabase_sync.dart  # Supabase Realtime: agent devices and events into Drift
│   │   └── local_storage.dart  # Drift/SQLite store for instant caching
│   └── main.dart            # Riverpod ProviderScope and App Initialization
└── pubspec.yaml
```

## 7. Development Milestones

* **Phase 1 (Core Engine):** Develop `pingduck-core` in C++ and validate ICMP, mDNS, and libpcap ARP sniffing via terminal outputs.
* **Phase 2 (FFI & Mobile Setup):** Implement the Dart FFI bridge, map the C++ structs to Dart objects, and configure Riverpod state management.
* **Phase 3 (UI/UX Construction):** Build the Radar device list, device detail screens, and implement local caching for instant UI loading.
* **Phase 4 (Agent & Cloud Sync):** Deploy the Supabase PostgreSQL database, build the headless Docker wrapper for the C++ engine, and implement real-time synchronization.
