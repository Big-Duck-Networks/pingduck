# Technical Specification: PowerSync Integration and Local-First Data Synchronization

```
Document Identifier: DOC-TECH-PDSYNC-001
Standard Compliance: IEC/IEEE 82079-1:2019 Edition 2.0
Document Version:    1.0.0
Status:              Approved
Date of Issue:       2026-10-06
Organization:        Big Duck Networks
Product:             PingDuck Network Reconnaissance & Monitoring System
Target Audience:     Mobile Engineers, Backend Architects, DevOps Personnel
```

---

## 1. Document Overview and Scope

### 1.1 Purpose
This document establishes the technical specification and operational instructions for integrating **PowerSync** as the core data synchronization and cloud persistence engine for the PingDuck product ecosystem. It governs the transition from generic BaaS endpoints to a deterministic, local-first synchronization model.

### 1.2 Scope
This specification applies to:
* **PingDuck Mobile Application** (`pingduck_app`): Flutter frontend on iOS and Android.
* **PingDuck Headless Agent** (`agent`): Dockerized network reconnaissance daemon.
* **Upstream Data Layer**: PostgreSQL operational database and PowerSync replication service.
* **Authentication & Entitlement Boundary**: JWT token validation, user partitioning, and access control.

### 1.3 Audience and Qualifications
This document is prepared for qualified software engineers and systems administrators with competence in:
* Flutter mobile development and Dart FFI runtime.
* Relational database design (PostgreSQL and SQLite/Drift).
* Local-first synchronization protocols and cryptographic token (JWT) verification.

---

## 2. Normative References and Definitions

### 2.1 Normative References
* **IEC/IEEE 82079-1:2019**: *Preparation of information for use (instructions for use) of products — Part 1: Principles and general requirements*.
* **RFC 7519**: *JSON Web Token (JWT)*.
* **RFC 8446**: *The Transport Layer Security (TLS) Protocol Version 1.3*.

### 2.2 Definitions
* **Local-First Architecture**: Software architecture where client applications maintain a fully functioning local database (SQLite via Drift) and execute all read/write operations against the local store without blocking on network availability.
* **Replication Bucket**: A discrete, queryable unit of data defined in PowerSync sync rules, partitioned by user or organizational scope.
* **Drift**: A type-safe persistence and query library for Dart and Flutter built on SQLite.

---

## 3. System Architecture and Principles of Operation

### 3.1 Architectural Overview
PingDuck employs a decoupled, local-first topology:

```
┌─────────────────────────────────────────────────────────────┐
│                       PingDuck Client                       │
│  ┌───────────────────────┐        ┌──────────────────────┐  │
│  │ Flutter Presentation  │        │   C++ Scanning Core  │  │
│  └───────────┬───────────┘        └──────────┬───────────┘  │
│              │                               │              │
│  ┌───────────▼───────────────────────────────▼───────────┐  │
│  │          Local Store: Drift + SQLite Engine           │  │
│  └───────────────────────────▲───────────────────────────┘  │
│                              │                              │
│              ┌───────────────▼──────────────┐               │
│              │     PowerSync Client SDK     │               │
│              └───────────────▲──────────────┘               │
└──────────────────────────────┼──────────────────────────────┘
                               │ TLS 1.3 WebSockets / HTTPS
                               │
               ┌───────────────▼──────────────┐
               │       PowerSync Service      │
               └───────────────▲──────────────┘
                               │ Logical Replication
                               │
               ┌───────────────▼──────────────┐
               │     PostgreSQL Database      │
               │   (Operational Single-Source)│
               └───────────────▲──────────────┘
                               │
               ┌───────────────┴──────────────┐
               │    Headless Homelab Agent    │
               │     (Direct / Ingestion API) │
               └──────────────────────────────┘
```

### 3.2 Principles of Operation
1. **Unconditional Local Availability**: The client UI reads exclusively from the local Drift SQLite database. No UI state transition blocks on remote server round-trips.
2. **Deterministic Background Sync**: The PowerSync client maintains a persistent stream with the PowerSync service. Mutations made on the mobile device are captured locally and sent upstream via write checkpoints.
3. **Upstream Enrichment Streaming**: Enriched device metadata collected by the 24/7 Homelab Agent (e.g., physical MAC addresses resolved via `libpcap` ARP sniffing) is written upstream to PostgreSQL and replicated downstream to the user's mobile device.
4. **Partitioned Replication Rules**: Data distribution is governed by server-side sync rules ensuring strict multi-tenant isolation based on authenticated `user_id`.

---

## 4. Technical Specifications and Data Architecture

### 4.1 Schema Definitions

#### 4.1.1 Upstream PostgreSQL Schema
The upstream PostgreSQL database maintains the canonical state:

| Table | Primary Key | Description |
| :--- | :--- | :--- |
| `networks` | `id` (UUID) | Discovered LAN segments and SSIDs belonging to a user. |
| `devices` | `id` (UUID) | Physical and virtual network nodes (IP, MAC, vendor, hostname). |
| `device_events` | `id` (UUID) | Audit log of state transitions (new MAC detected, offline, online). |
| `agents` | `id` (UUID) | Paired homelab agent daemons and connection telemetry. |
| `user_entitlements` | `user_id` (UUID) | Plan status (Free vs. Pro tier entitlements). |

#### 4.1.2 Client Drift SQLite Schema
The client-side Drift schema directly matches the PowerSync-replicated tables:

```dart
// Location: pingduck_app/lib/core/storage/schema.dart

class Networks extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get ssid => text().nullable()();
  TextColumn get gatewayIp => text().named('gateway_ip')();
  TextColumn get cidr => text()();
  DateTimeColumn get lastScannedAt => dateTime().named('last_scanned_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class Devices extends Table {
  TextColumn get id => text()();
  TextColumn get networkId => text().named('network_id')();
  TextColumn get ip => text()();
  TextColumn get mac => text().nullable()();
  TextColumn get vendor => text().nullable()();
  TextColumn get hostname => text().nullable()();
  BoolColumn get isOnline => boolean().named('is_online')();
  IntColumn get lastRttMs => integer().nullable().named('last_rtt_ms')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}
```

### 4.2 PowerSync Sync Rules (`sync_rules.yaml`)

```yaml
# PowerSync Replication Rules
bucket_definitions:
  user_data:
    parameters:
      - select request.user_id() as user_id
    data:
      - select * from networks where user_id = bucket.user_id
      - select * from devices where network_id in (
          select id from networks where user_id = bucket.user_id
        )
      - select * from device_events where network_id in (
          select id from networks where user_id = bucket.user_id
        )
      - select * from agents where user_id = bucket.user_id
```

---

## 5. Implementation Procedures

### 5.1 Step 1: Client Dependency Configuration
Add the required dependencies to `pingduck_app/pubspec.yaml`:

```yaml
dependencies:
  powersync: ^1.11.0
  drift: ^2.24.0
  sqlite3_flutter_libs: ^0.5.28
```

### 5.2 Step 2: Database Initialization and Drift Integration
Instantiate the `PowerSyncDatabase` and attach it to Drift using `powersync`:

```dart
import 'package:powersync/powersync.dart';
import 'package:drift/drift.dart';

Future<PowerSyncDatabase> initializeSyncDatabase() async {
  final db = PowerSyncDatabase(
    schema: powerSyncSchema,
    path: await getDatabasePath('pingduck_powersync.db'),
  );
  await db.initialize();
  return db;
}
```

### 5.3 Step 3: Connector and Backend Ingestion Setup
Implement the `PowerSyncBackendConnector` interface to provide authentication tokens and handle mutation uploads:

```dart
class PingDuckSyncConnector extends PowerSyncBackendConnector {
  PingDuckSyncConnector({required this.authService});

  final AuthService authService;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final token = await authService.getValidJwtToken();
    if (token == null) return null;
    return PowerSyncCredentials(
      endpoint: 'https://sync.pingduck.net',
      token: token,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;

    try {
      // POST batch mutations to upstream backend API
      await authService.postBatchCrud(transaction.crud);
      await transaction.complete();
    } catch (e) {
      // Retry automatically on connection re-establishment
      rethrow;
    }
  }
}
```

---

## 6. Verification and Acceptance Testing

### 6.1 Acceptance Criteria
| ID | Requirement | Verification Method | Acceptance Threshold |
| :--- | :--- | :--- | :--- |
| **VER-01** | Offline Read Latency | Local Query Benchmark | Query execution < 10 ms from local SQLite. |
| **VER-02** | Synchronization Recovery | Test Network Interruption | Queued mutations sync within 3 seconds of reconnection. |
| **VER-03** | Data Isolation | Multi-tenant Sync Audit | Zero cross-tenant data leakage across distinct user JWTs. |
| **VER-04** | Agent Ingestion Propagation | End-to-End Latency Test | Agent MAC updates reflect in mobile UI within 2 seconds of ingestion. |

---

## 7. Maintenance, Security, and Diagnostics

### 7.1 Security & Cryptography
* All sync transmissions MUST utilize TLS 1.3 with mandatory certificate verification.
* Client JWTs MUST be signed using RS256 or ES256 with an expiration period not exceeding 3600 seconds (1 hour).
* Local SQLite files on client devices MUST reside within protected application sandboxes (`NSApplicationSupportDirectory` / Android Internal Storage).

### 7.2 Diagnostics
Diagnostic sync metrics are accessible through `PowerSyncDatabase.currentStatus`:
* `connected`: Boolean indicator of active synchronization stream.
* `lastSyncedAt`: Timestamp of the latest completed replication batch.
* `hasUnsyncedData`: Boolean indicating pending client-side mutations.
