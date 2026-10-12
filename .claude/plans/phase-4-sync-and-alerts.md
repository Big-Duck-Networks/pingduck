# Feature: Phase 4 completion (agent sync into the app, new-device alerts, Settings rows, Proxmox guide)

The following plan should be complete, but its important that you validate documentation and codebase patterns and task sanity before you start implementing.

Pay special attention to naming of existing utils types and models. Import from the right files etc.

## Feature Description

Everything left in Phase 4 of `docs/ROADMAP.md` (timeline weeks 3–4, Oct 26 – Nov 8):

1. **Realtime sync.** The agent already writes devices (with MACs and vendors) to Supabase through `agent_sync`. The app starts reading them: an initial fetch plus a Supabase Realtime subscription, merged into the Drift cache. The UI keeps reading only from the cache.
2. **New-device alerts.** When `agent_sync` sees a new MAC on a network that already had devices, the server sends a **data-only FCM message** (no device details) to the owner's Android phones. The app wakes, reads the new devices from Supabase itself, and shows a local notification. Gated on the plan's `notifications` flag, and skipping devices the user marked as known.
3. **Settings rows.** The "Cloud & alerts" placeholders become real: agent status, Cloud sync switch, New-device alerts switch. Plus the `agents.version` bug: `agent_heartbeat` now records the version, so an upgraded agent stops showing its pairing-time version.
4. **Proxmox deployment guide** in `docs/PROXMOX.md`.

## User Story

As a homelab owner with a PingDuck agent on my LAN
I want the app to show the agent's devices (with MACs and vendors) and to alert me when an unknown device joins
So that I know what is on my network even when my phone isn't scanning, and hear about intruders within minutes

## Problem Statement

The agent scans every 5 minutes and syncs to Supabase, but nothing reads that data: the app still only knows what the phone itself can see (no MACs on Android), `device_events` rows pile up unseen, Settings shows three disabled "coming soon" rows, and an upgraded agent keeps reporting its old version.

## Solution Statement

- A `SupabaseSync` service fetches and subscribes to `devices` for each local network linked to Supabase (`Networks.remoteId`) and merges rows into the cache **by IP** (the cache key stays `(networkId, ip)`), filling `mac`/`vendor`/`hostname`/`model` and adding agent-only devices with a new app-only `DiscoverySource.agent` bit.
- `agent_sync` collects the ids of new devices; when the network already had devices before this sync (so the first, baseline sync after pairing never alerts), it calls `private.queue_new_device_alert`, which applies the plan and known-device rules and posts **one** request per sync through `pg_net` to a new Edge Function. The function sends a data-only FCM HTTP v1 message `{kind: "new_devices", network_id}` with Android high priority to every token in `push_tokens` for the owner.
- The app (Android only) registers its FCM token in `push_tokens` when the user turns alerts on, and handles messages in a background isolate: it reads the last 15 minutes of `new_device` events for that network from Supabase and shows one local notification per network.
- `agent_heartbeat` gains `p_version text default null`; the agent sends its version.

## Out of Scope / Non-Goals

- **iOS push (APNs) and the iOS app.** Android only. `firebase_messaging` stays unconfigured for iOS; APNs needs the Apple account and the first iPhone run.
- **Windows tray alerts.** The Windows app gets sync (it's the same Dart code) but no notifications. `firebase_messaging` does not support Windows; guard every Firebase call with `Platform.isAndroid`.
- **Rekeying the cache to MAC** (roadmap "Device identity" decision). Stays IP-keyed; separate ticket.
- **Pulling networks this install never scanned** ("Cloud sync across devices"). Only networks with a local `remoteId` sync.
- **Alerts for anything but new devices** (offline, IP changed). The events exist; alerting on them is later.
- **Any other Firebase product.** No Analytics, Crashlytics, Remote Config, no `google-services` Gradle plugin. Only `firebase_core` + `firebase_messaging`.
- **Alert email.** Not now.
- Not changing: scan flow, scan quota, the pairing flow, existing RLS policies.

## Feature Metadata

**Feature Type**: New Capability
**Estimated Complexity**: High
**Primary Systems Affected**: `supabase/migrations`, new `supabase/functions/notify-new-devices`, `agent/` (heartbeat), `pingduck_app` (cache, sync service, push service, Settings, Inspector), `docs/`
**Dependencies**: `firebase_core`, `firebase_messaging`, `flutter_local_notifications` (new, app); a Firebase project (user); FCM service-account secret (user); Supabase Edge Functions + `pg_net` + Vault (already used for Resend)

## Related Work

**Implements**: `docs/ROADMAP.md` Phase 4 rows "Intrusion alerts", "Realtime sync in the app", "Settings", "Proxmox deployment guide"; exit criterion "a new device joining the home LAN triggers a push notification within 2 minutes, and the app shows agent-sourced MACs and vendors".

**Back-references**:
- `.claude/plans/agent-pairing-lan-discovery.md` — the pairing flow, `Networks.remoteId`, `agent_heartbeat`.
- `.claude/plans/windows-desktop-and-rust-agent.md` — the agent daemon (`monitor.rs`) that calls `agent_sync`.

**Forward-references**: (none yet)

---

## DECISIONS (from the planning conversation, 2026-10-12)

| # | Decision |
|---|---|
| 1 | One plan, four phases; alerts last. |
| 2 | Merge agent devices **by IP** into the existing cache; agent-only devices are inserted with `DiscoverySource.agent`. No rekey. |
| 3 | Sync only local networks that have a `remoteId`. |
| 4 | **FCM, data-only messages.** The payload carries only `kind` and `network_id`; the app fetches details from Supabase. Google sees nothing about devices. Android only. |
| 5 | Locally administered MAC + a known device on the same network with the same hostname → no alert (event still recorded). Inspector gets an "is known" switch; Settings gets "Mark all current devices as known". |
| 6 | Settings rows as below; preferences stored locally / as presence of a push token; guide in `docs/PROXMOX.md`. |

---

## CONTEXT REFERENCES

### Relevant Codebase Files IMPORTANT: YOU MUST READ THESE FILES BEFORE IMPLEMENTING!

Database
- `supabase/migrations/20261006120000_initial_schema.sql` lines 18–33 (`plans`, incl. `notifications`), 45–60 (`plan_for`), 126–140 (`agents`), 226–253 (`devices`, `device_events`), 255–336 (`agent_sync` — **copied whole and extended in Task A2**), 338–362 (state-event trigger), 368–376 (`push_tokens`), 404–466 (RLS, grants, Realtime publication — `devices` and `device_events` are already published).
- `supabase/migrations/20261010120000_agent_pairing.sql` lines 20–45 (`agent_heartbeat`, replaced in Task A1); also line ~262 (its later `create or replace` of `prune_history`). `agent_sync` is defined only in the initial schema.
- `supabase/migrations/20261008120000_goodbye_email.sql` lines 1–50 — **the pattern for pg_net + Vault**: guard on `to_regproc('net.http_post')` / `to_regclass('vault.decrypted_secrets')`, read the secret with dynamic SQL, warn and return when missing. Mirror exactly.
- `supabase/tests/schema_test.sql` (runs in `begin; … rollback;`), `supabase/tests/run_tests.sh`, `supabase/tests/supabase_stub.sql` (stubs `auth.uid()` etc.; plain Postgres 15 without pg_net — the alert path must degrade to a warning there).

Agent
- `agent/crates/pingduck-agent/src/agent.rs` lines 251–275 (`heartbeat`), ~463 (`heartbeat_does_nothing_while_unpaired` — test pattern with the fake Supabase client).
- `agent/Cargo.toml` line 14 (`version = "0.3.0"`).

App
- `pingduck_app/lib/services/local_storage.dart` — whole file (217 lines): tables, `schemaVersion => 3` + `onUpgrade` pattern (lines 81–90), `_fromRow`/`_toRow` (186–217), `saveDevices` (`insertAllOnConflictUpdate`).
- `pingduck_app/lib/features/scanner/domain/discovered_device.dart` lines 1–20 (`DiscoverySource` mirrors `PD_SRC_*`, bits 0–4 used in `core/include/pingduck/pingduck.h:44-48`), `copyWith`, `id => mac ?? ip`.
- `pingduck_app/lib/features/scanner/application/scan_controller.dart` lines 95–135 (providers, `localStoreProvider`, `restoreLastScan`), 180–215 (scan merges cache by IP), 270–292 (`_upsert`, persisting). Sync must update `scanControllerProvider` state for the current network after merging (add a small public `reloadFromCache()` method there).
- `pingduck_app/lib/features/agent/data/agent_repository.dart` — the interface + Supabase implementation + provider pattern to mirror for `SyncRepository`; `signedInClient()` from `lib/features/auth/session.dart`.
- `pingduck_app/lib/features/agent/application/agent_status.dart` (`myAgentsProvider`) and `lib/features/agent/domain/agent_unit.dart` (`PairedAgent` with `version`, `lastSeenAt`).
- `pingduck_app/lib/features/settings/presentation/settings_screen.dart` lines 27–30 (`isPremiumProvider`), 140–168 (Auto-scan switch: the pattern for a Premium-gated switch), 171–190 (the "Cloud & alerts" `PdPanel` to replace), 335–350 (`_ComingRow`, delete when unused).
- `pingduck_app/lib/features/device_details/presentation/inspector_screen.dart` (~line 662 "Forget" action; add the known switch near rename/notes).
- `pingduck_app/lib/main.dart` — startup order (cache before first frame, `Supabase.initialize` reads disk only). Firebase init must not block the first frame.
- `pingduck_app/test/fakes.dart` (`memoryStore()`, `FakeQuota`, fake repositories) — add `FakeSyncRepository`, `FakePushAlerts` here.
- `pingduck_app/test/agent_pairing_controller_test.dart`, `test/scan_controller_test.dart` — test style.
- `pingduck_app/android/app/build.gradle.kts` (`applicationId = "app.webcap.pingduck"`), `android/app/src/main/AndroidManifest.xml`.

### New Files to Create

- `supabase/migrations/20261012120000_agent_version_and_alerts.sql` — heartbeat version, `agent_sync` with alert queueing, `private.queue_new_device_alert`.
- `supabase/functions/notify-new-devices/index.ts` — Edge Function sending FCM HTTP v1.
- `supabase/functions/notify-new-devices/fcm.ts` — pure helpers (message body, JWT claim set) so they can be unit-tested.
- `supabase/functions/notify-new-devices/fcm_test.ts` — `deno test`.
- `pingduck_app/lib/services/supabase_sync.dart` — `SyncRepository` interface, `SupabaseSyncRepository`, `SupabaseSync` controller + providers.
- `pingduck_app/lib/services/push_alerts.dart` — `PushAlerts` (token registration, permission, message handling, local notification).
- `pingduck_app/lib/firebase_options.dart` — generated by `flutterfire configure --platforms=android` (user step; Android options only).
- `pingduck_app/test/supabase_sync_test.dart`, `pingduck_app/test/local_storage_merge_test.dart`, `pingduck_app/test/settings_cloud_rows_test.dart`.
- `docs/PROXMOX.md`.

### Relevant Documentation YOU SHOULD READ THESE BEFORE IMPLEMENTING!

- [FCM HTTP v1 send](https://firebase.google.com/docs/cloud-messaging/send/v1-api) — message shape; `android.priority: "HIGH"` is required for data-only messages to wake a dozing device.
- [FCM data messages on Android](https://firebase.google.com/docs/cloud-messaging/android/receive-messages) — data-only messages always go to the app's handler, never auto-display.
- [FlutterFire Messaging: background messages](https://firebase.google.com/docs/cloud-messaging/flutter/receive) — `onBackgroundMessage` must be a top-level function annotated `@pragma('vm:entry-point')`; it runs in its own isolate, so it must initialise Firebase and Supabase itself.
- [Supabase: push notifications with Edge Functions](https://supabase.com/docs/guides/functions/examples/push-notifications) — FCM from Deno, service-account auth.
- [Supabase Realtime: Postgres changes, filters](https://supabase.com/docs/guides/realtime/postgres-changes) — `filter: network_id=eq.<uuid>`; RLS applies to Realtime for `authenticated`.
- [Supabase Edge Functions: secrets](https://supabase.com/docs/guides/functions/secrets).
- [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) — Android channel setup, `POST_NOTIFICATIONS` (Android 13+).
- [Android notification runtime permission](https://developer.android.com/develop/ui/views/notifications/notification-permission).

### Patterns to Follow

**Repository + provider (mirror `agent_repository.dart`):**
```dart
abstract interface class SyncRepository { Future<List<RemoteDevice>> devicesOf(String remoteNetworkId); … }
class SupabaseSyncRepository implements SyncRepository { … (await signedInClient()).from('devices')… }
final syncRepositoryProvider = Provider<SyncRepository>((ref) => SupabaseSyncRepository());
```
Tests override the provider with a fake from `test/fakes.dart`.

**Drift migrations:** bump `schemaVersion`, add `if (from < N) await m.addColumn(table, table.column);` in `onUpgrade`; regenerate with `dart run build_runner build --delete-conflicting-outputs`.

**pg_net + Vault (from `goodbye_email.sql`):**
```sql
if to_regproc('net.http_post') is null or to_regclass('vault.decrypted_secrets') is null then
    raise warning '… skipped: pg_net or vault not available'; return …;
end if;
execute $q$select decrypted_secret from vault.decrypted_secrets where name = '…'$q$ into v_key;
```

**Security-definer functions:** `language plpgsql … security definer set search_path = ''`, fully-qualified names, `revoke execute … from public` then grant only what's needed. `private` schema functions get no grants.

**Errors from RPCs:** server raises `'<code>'` messages, app maps `PostgrestException.message.startsWith(...)` to typed exceptions (see `createCode`).

**Comments:** short "why" comments in the codebase's voice; no narration of obvious code.

---

## IMPLEMENTATION PLAN

### Phase A: Database and agent

Migration (heartbeat version, alert queueing) and the agent's version report. Everything else reads from what this phase writes.

### Phase B: Realtime sync into the cache

**Depends on:** nothing in Phase A (reads existing tables). **Independent of:** Phase A, Phase D.

### Phase C: Settings rows and the known switch

**Depends on:** Phase B (Cloud sync switch drives `SupabaseSync`; `isKnown` column comes from Phase B's cache change). Alerts switch is wired in Phase E.

### Phase D: Proxmox guide

**Independent of:** all other phases.

### Phase E: FCM alerts

**Depends on:** Phase A (queueing), Phase C (the switch), and the user's Firebase setup (Task E0).

---

## STEP-BY-STEP TASKS

### Phase A

#### A1. CREATE `supabase/migrations/20261012120000_agent_version_and_alerts.sql` — heartbeat version

- **IMPLEMENT**: `drop function public.agent_heartbeat(text);` then `create function public.agent_heartbeat(p_token text, p_version text default null)` with the same body plus `version = coalesce(left(nullif(p_version, ''), 32), version)` in the `update`. Re-apply `revoke … from public; grant execute … to anon, authenticated;` with the new signature.
- **GOTCHA**: Do **not** `create or replace` with the extra argument: that creates an overload, and PostgREST then can't choose between `(text)` and `(text, text)` for a call with only `p_token` (ambiguous function error). Drop first. Old agents (0.3.0) keep working because `p_version` has a default.
- **GOTCHA**: Deploy order: this migration must be applied **before** an agent sending `p_version` runs, or that agent's heartbeats get 404 from PostgREST (the agent treats that as `Heartbeat::Error` and retries, so it's not destructive, but `last_seen_at` stops moving).
- **VALIDATE**: `sh supabase/tests/run_tests.sh` (on `pingduck-vm`: Docker is there) after A3's tests are added.
- **SATISFIES**: AC 6.

#### A2. ADD to the same migration — `agent_sync` collects new devices and queues one alert

- **IMPLEMENT**: `create or replace function public.agent_sync(...)` with the **identical signature** and the current body (take the latest definition across migrations), plus:
  - `v_new_ids uuid[] := '{}'` and `v_existing int`.
  - Before the loop: `select count(*) into v_existing from public.devices where network_id = v_agent.network_id;`
  - In the `if v_new then` branch: `v_new_ids := v_new_ids || v_row.id;`
  - After the offline update: `if v_existing > 0 and cardinality(v_new_ids) > 0 then perform private.queue_new_device_alert(v_agent.network_id, v_agent.owner_id, v_new_ids); end if;`
- **GOTCHA**: `v_existing = 0` means this is the baseline sync right after pairing (every device is "new"); alerting there would fire 20 notifications. That's the whole reason for the check.
- **GOTCHA**: `queue_new_device_alert` must never raise: an alert failure must not fail the sync. Wrap the `perform` in `begin … exception when others then raise warning …; end;`.
- **SATISFIES**: AC 3, AC 4.

#### A3. ADD to the same migration — `private.queue_new_device_alert`

- **IMPLEMENT**: `create function private.queue_new_device_alert(p_network uuid, p_owner uuid, p_devices uuid[]) returns int` (number of devices that will be alerted; 0 = nothing sent):
  1. If `not (public.plan_for(p_owner)).notifications` → return 0.
  2. Count devices in `p_devices` that are **not suppressed**. Suppressed: `d.is_known`, or the MAC is locally administered (`(get_byte(macaddr_send(d.mac), 0) & 2) <> 0` — verify this expression in psql; alternative: `substr(d.mac::text, 2, 1) in ('2','3','6','7','a','b','e','f')`) **and** another device on the same network with `is_known` and the same non-null `lower(hostname)` exists.
  3. If 0 → return 0. If `not exists (select 1 from public.push_tokens where user_id = p_owner)` → return 0.
  4. pg_net/Vault guard exactly as in `goodbye_email.sql`; read Vault secrets `notify_url` (the Edge Function URL) and `notify_secret` (shared secret). Missing → `raise warning` and return the count (so tests can still assert it).
  5. `net.http_post(url := v_url, headers := jsonb_build_object('Content-Type','application/json','x-pingduck-hook', v_secret), body := jsonb_build_object('user_id', p_owner, 'network_id', p_network, 'count', v_count))`.
  - `security definer set search_path = ''`, no grants (lives in `private`).
- **PATTERN**: `supabase/migrations/20261008120000_goodbye_email.sql:26-50`.
- **GOTCHA**: `pg_net` only sends after commit — good: a rolled-back sync sends nothing.
- **VALIDATE**: add to `supabase/tests/schema_test.sql` (inside the existing transaction):
  - heartbeat with `p_version => '0.3.1'` updates `agents.version`; heartbeat with only `p_token` leaves it unchanged.
  - `agent_sync` on an empty network → no alert queued (call `queue_new_device_alert` indirectly: assert by making the function's effect observable — simplest: a test-only check that `private.queue_new_device_alert(net, owner, array[...])` returns 0 for a Free owner, N for a Premium owner (insert an `entitlements` row with `source='manual'`) with a push token, and excludes `is_known` devices and the private-MAC-with-known-hostname case).
  - Run: `sh supabase/tests/run_tests.sh` on pingduck-vm (`scp -r supabase pingduck-vm:` then run).
- **SATISFIES**: AC 3, AC 4, AC 5.

#### A4. UPDATE `agent/crates/pingduck-agent/src/agent.rs` — send the version

- **IMPLEMENT**: In `heartbeat()`, body becomes `json!({ "p_token": s.token, "p_version": env!("CARGO_PKG_VERSION") })`. Bump `agent/Cargo.toml` to `0.3.1` (run `cargo build` so `Cargo.lock` updates).
- **PATTERN**: test near `agent.rs:463`: add a test asserting the fake Supabase client received `p_version` equal to `env!("CARGO_PKG_VERSION")`.
- **VALIDATE**: `cd agent && cargo clippy --workspace --all-targets --locked -- -D warnings && cargo test --workspace --locked`
- **SATISFIES**: AC 6.

### Phase B

#### B1. UPDATE `pingduck_app/lib/features/scanner/domain/discovered_device.dart` — `agent` source and `isKnown`

- **IMPLEMENT**: `DiscoverySource.agent(1 << 8)` with a comment: app-only, never set by the core (`PD_SRC_*` uses bits 0–4); keep a gap so the core can grow. Add `final bool isKnown;` (default `false`) to `DiscoveredDevice`, its constructor and `copyWith`.
- **GOTCHA**: `fromMask`/`toMask` iterate `values`, so the new bit round-trips through the cache's `sources` int with no other change. Check every `switch` over `DiscoverySource` (e.g. source chips in `device_card.dart`, `inspector_screen.dart`) for exhaustiveness; give `agent` the label "Agent".
- **VALIDATE**: `cd pingduck_app && flutter analyze`
- **SATISFIES**: AC 1.

#### B2. UPDATE `pingduck_app/lib/services/local_storage.dart` — schema v4 and the merge

- **IMPLEMENT**:
  - `Devices`: `BoolColumn get isKnown => boolean().withDefault(const Constant(false))();`. `schemaVersion => 4`; `if (from < 4) await m.addColumn(devices, devices.isKnown);`. Map in `_fromRow`/`_toRow`.
  - `Future<int?> networkIdForRemote(String remoteId)` and `Future<List<({int id, String remoteId})>> linkedNetworks()`.
  - `Future<int> mergeRemoteDevices(int networkId, List<RemoteDevice> remote)` in one `transaction`, returns rows changed. For each remote device with a non-null IP:
    - local row with the same IP → update `mac` (always: the agent's MAC is authoritative for that IP now), `vendor`/`hostname`/`model` only where local is null (local `customName`/`notes` never touched), `isKnown` from remote, `sources |= agent.bit`, `lastSeen = max(local, remote.lastSeenAt)`.
    - else, a local row with the same MAC but another IP → leave it (IP-keyed cache; the next phone scan reconciles) **and** insert nothing, to avoid two rows for one device.
    - else insert a new row: `sources = agent.bit`, `firstSeen = remote.firstSeenAt`, `lastSeen = remote.lastSeenAt`, `isKnown`.
  - `RemoteDevice` is a small value class in `supabase_sync.dart` (mac, ip, hostname, vendor, model, isKnown, online, firstSeenAt, lastSeenAt) with `fromRow(Map)`. Import it here (or put it in `lib/features/scanner/domain/` if the import direction feels wrong — `local_storage.dart` already imports the scanner domain).
- **GOTCHA**: Remote `online` is the agent's view; do **not** map it to `isOnline` (that means "answered this phone's current sweep" and drives the radar). Not stored.
- **GOTCHA**: Regenerate `local_storage.g.dart`: `dart run build_runner build --delete-conflicting-outputs`.
- **VALIDATE**: `flutter test test/local_storage_merge_test.dart` (new): fills MAC by IP; keeps `customName`; adds agent-only device; does not duplicate on MAC with a different IP; migration from v3 (open a v3 schema file? — simpler: assert `schemaVersion == 4` and that a fresh store has the column; drift's `SchemaVerifier` is not set up in this repo, don't add it).
- **SATISFIES**: AC 1.

#### B3. CREATE `pingduck_app/lib/services/supabase_sync.dart`

- **IMPLEMENT**:
  - `abstract interface class SyncRepository { Future<List<RemoteDevice>> devicesOf(String remoteNetworkId); Stream<void> changesOf(String remoteNetworkId); Future<void> setKnown(String remoteNetworkId, String mac, bool known); Future<void> markAllKnown(String remoteNetworkId); }`
  - `SupabaseSyncRepository`: `devicesOf` = `from('devices').select('mac, ip, hostname, vendor, model, is_known, online, first_seen_at, last_seen_at').eq('network_id', id)`. `changesOf` = a `RealtimeChannel` on `postgres_changes` (event `all`, schema `public`, table `devices`, `filter: PostgresChangeFilter(type: eq, column: 'network_id', value: id)`) whose callbacks add to a `StreamController`; cancel → `removeChannel`. Debounce isn't needed here; the controller debounces.
  - `setKnown` / `markAllKnown` = `update({'is_known': …})` filtered by `network_id` (and `mac`). RLS (`devices_own_update`) and the column grant already allow this.
  - `SupabaseSync` (`Notifier<SyncStatus>`; `SyncStatus` = idle / syncing / live / off / error + `lastSyncedAt`): `start()` — if signed in with an email account (`accountEmailProvider`), the `cloud_sync` setting is not `'0'`, and `linkedNetworks()` is non-empty: for each, fetch → `mergeRemoteDevices` → subscribe; on each change event, debounce 2 s then re-fetch and merge (a full re-fetch of ≤ a few hundred rows is simpler and self-healing vs applying row payloads). After every merge, if the merged network is the scan controller's current network, call `ref.read(scanControllerProvider.notifier).reloadFromCache()`. `stop()` unsubscribes. Restart on `AppLifecycleState.resumed` (Realtime sockets die in background).
  - Providers: `syncRepositoryProvider`, `supabaseSyncProvider`.
- **GOTCHA**: Never start sync for an anonymous user — anonymous installs can't pair, and RLS would return nothing anyway; avoid opening sockets for nothing.
- **GOTCHA**: Supabase Realtime with RLS requires the client's JWT; `supabase_flutter` sets it automatically after sign-in. Call `signedInClient()` before subscribing.
- **VALIDATE**: `flutter test test/supabase_sync_test.dart` with `FakeSyncRepository` (in `test/fakes.dart`; `changesOf` returns a `StreamController` the test drives): initial merge happens; a change event triggers a re-fetch after the debounce (use `fakeAsync` or a 0-ms debounce injected via constructor); `cloud_sync = '0'` → no fetch; anonymous → no fetch.
- **SATISFIES**: AC 1, AC 2.

#### B4. UPDATE `scan_controller.dart` and `main.dart` / `app_shell.dart` — wire it in

- **IMPLEMENT**: `ScanController.reloadFromCache()`: re-reads `devicesOf(currentNetworkId)` and merges into `state.devices`, keeping each device's current `isOnline`/`rttMs` (a live scan must not be reset). Start `supabaseSyncProvider.notifier.start()` after the first frame (same `addPostFrameCallback` place as auto-scan in `main.dart`), and again after pairing succeeds (`agent_pairing_controller.dart`, where `myAgentsProvider` is invalidated).
- **GOTCHA**: Don't block launch on the network: fire and forget, errors → `SyncStatus.error`, logged with `debugPrint`.
- **VALIDATE**: `flutter test` (whole suite) and `flutter analyze`.
- **SATISFIES**: AC 1.

### Phase C

#### C1. UPDATE `settings_screen.dart` — real Cloud & alerts rows

- **IMPLEMENT**: Replace the panel's three `_ComingRow`s (and drop the `PHASE 4` chip; delete `_ComingRow` if unused):
  - **Homelab Agent**: from `myAgentsProvider`. None → subtitle "Not set up · Add a monitoring unit", taps into the add-unit flow (`AddUnitIntroScreen`). One or more → "<name> · Online" when `lastSeenAt` is within 3 minutes (heartbeat is every 60 s) else "Last seen <relative time>", plus "v<version>"; taps into `AgentScreen`.
  - **Cloud sync**: `Switch` bound to the `cloud_sync` local setting (default on). Disabled with subtitle "Needs a monitoring unit" when there's no agent. Subtitle when on shows `SyncStatus` ("Live", "Synced 2 min ago", "Couldn't sync"). Toggling calls `start()`/`stop()`.
  - **New-device alerts**: `Switch`, enabled only when Android **and** `isPremiumProvider` **and** an agent exists; otherwise disabled with the reason ("Premium plan required" / "Needs a monitoring unit" / "Android only for now"). Wired to `PushAlerts` in Phase E; until then leave it disabled with "Coming soon" so Phase C can ship alone.
  - **Mark all current devices as known**: a `TextButton` row under the alerts switch, visible when an agent exists; calls `markAllKnown` for each linked network, then re-syncs; confirmation snack/toast in the existing toast style from #20.
- **PATTERN**: Auto-scan switch at `settings_screen.dart:140-168`; toasts as used in `sign_in_screen.dart`.
- **VALIDATE**: `flutter test test/settings_cloud_rows_test.dart` (new; override `myAgentsProvider`, `isPremiumProvider`, `supabaseSyncProvider` with fakes): no agent → rows show setup text and disabled switches; agent seen 30 s ago → "Online"; Free → alerts disabled with "Premium plan required".
- **SATISFIES**: AC 2, AC 6, AC 7.

#### C2. UPDATE `inspector_screen.dart` — "Known device" switch

- **IMPLEMENT**: A `SwitchListTile`-style row "Known device — no alerts when it reconnects with a new address" (copy should stay short; run it past the brand voice), visible only when the device has a MAC and its network has a `remoteId`. Writes through `SyncRepository.setKnown`, then updates the cache row's `isKnown`. On failure, revert and show an error toast.
- **VALIDATE**: `flutter analyze` + extend an Inspector widget test if one exists (otherwise cover via `supabase_sync_test.dart` for `setKnown`).
- **SATISFIES**: AC 5.

### Phase D

#### D1. CREATE `docs/PROXMOX.md`

- **IMPLEMENT**: Sections: (1) Pick a host: Docker in a VM (recommended) vs privileged LXC; why an unprivileged LXC can't open raw sockets. (2) VM: bridge the VM's NIC onto the LAN bridge (`vmbr0`), no NAT; install Docker; the `docker run` line from `agent/Dockerfile` (`--net=host --cap-add=NET_RAW --cap-add=NET_ADMIN -v pingduck:/var/lib/pingduck`); or `agent/compose.yaml`. (3) LXC: `features: nesting=1`, privileged, Docker inside; note the security trade-off. (4) **Network filters** — Proxmox firewall "MAC filter" / "IP filter" on the VM NIC and libvirt `clean-traffic` drop the agent's ARP sweep and the phone's discovery traffic; how to check (`tcpdump -ni eth0 arp` on the guest while the phone runs Find my agent — 0 packets means a filter), how to turn them off for that NIC. Reference the Risks row in `docs/ROADMAP.md`. (5) VLANs/VPN: `PINGDUCK_PAIRING_CODE`, `PINGDUCK_SCAN_CIDR`. (6) Verify: `docker logs pingduck-agent` shows the first scan; the app's Homelab Agent screen shows Online.
- **VALIDATE**: Read-through; every command copied from `agent/Dockerfile` / `compose.yaml` verbatim. Optional: follow it on `pingduck-vm` (KVM, not Proxmox — note that).
- **SATISFIES**: AC 8.

### Phase E

#### E0. USER STEPS (block the rest of Phase E)

1. Create a Firebase project (Analytics **off** at creation). Add an Android app with package `app.webcap.pingduck`.
2. `dart pub global activate flutterfire_cli` then in `pingduck_app/`: `flutterfire configure --platforms=android` → writes `lib/firebase_options.dart`. If it also adds the `google-services` Gradle plugin or `google-services.json`, remove them: the app initialises from `firebase_options.dart` only. The options are not secrets (they ship in every APK) but keep the file in git.
3. Firebase console → Project settings → Service accounts → generate a key. `supabase secrets set FCM_SERVICE_ACCOUNT="$(cat key.json)"` (or Dashboard → Edge Functions → Secrets). Delete the local key file.
4. Pick a random hook secret: `supabase secrets set NOTIFY_SECRET=<random>` and in the SQL editor `select vault.create_secret('<same random>', 'notify_secret'); select vault.create_secret('https://rumwtzzyrhzudguolasq.supabase.co/functions/v1/notify-new-devices', 'notify_url');`
5. Deploy: `supabase functions deploy notify-new-devices --no-verify-jwt` (the function authenticates the hook secret itself; Postgres has no user JWT), and apply the Phase A migration.

#### E1. CREATE `supabase/functions/notify-new-devices/fcm.ts` and `index.ts`

- **IMPLEMENT**:
  - `fcm.ts`: `buildMessage(token: string, networkId: string)` → `{ message: { token, data: { kind: "new_devices", network_id: networkId }, android: { priority: "HIGH", ttl: "600s" } } }` — **no `notification` block** (that would make it a display message and put text through Google). `jwtClaims(clientEmail, now)` for the OAuth assertion (`scope: https://www.googleapis.com/auth/firebase.messaging`, `aud: https://oauth2.googleapis.com/token`, 1 h expiry).
  - `index.ts`: `Deno.serve`: reject unless `req.headers.get('x-pingduck-hook') === Deno.env.get('NOTIFY_SECRET')` (constant-time compare). Parse `{user_id, network_id}`. Service-role Supabase client (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` are injected automatically) → `push_tokens` for `user_id`. Get an access token: sign the JWT with the service account's private key via `jose` (`npm:jose`, `importPKCS8` + `SignJWT`, RS256), exchange at `https://oauth2.googleapis.com/token`. Send to `https://fcm.googleapis.com/v1/projects/${project_id}/messages:send` per token. On 404 or `UNREGISTERED` → delete that token; on success → update `last_used_at`. Respond `{sent, removed}`.
- **GOTCHA**: Never log tokens or the request body beyond counts.
- **VALIDATE**: `deno test supabase/functions/notify-new-devices/` (asserts the message has no `notification` key, has `android.priority === "HIGH"`, data values are strings) and `deno check supabase/functions/notify-new-devices/index.ts`. If Deno isn't installed locally: `winget install DenoLand.Deno`.
- **SATISFIES**: AC 3, AC 4.

#### E2. ADD dependencies and Android config

- **IMPLEMENT**: `cd pingduck_app && flutter pub add firebase_core firebase_messaging flutter_local_notifications` (record the resolved versions in the PR). `AndroidManifest.xml`: `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>`; a default notification channel id meta-data `com.google.firebase.messaging.default_notification_channel_id` = `new_devices`. A monochrome small icon (`@drawable/ic_stat_duck`) generated from the duck mark (extend `tool/make_brand_assets.py` if simple; otherwise reuse the launcher's themed-icon vector).
- **GOTCHA**: `flutter_local_notifications` needs core library desugaring on Android (`isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring` dependency) — check its README for the current requirement. `app ci` builds a debug APK, so a Gradle break fails the PR (#19).
- **GOTCHA**: Windows build must still compile: `firebase_messaging` has no Windows implementation; never call it unless `Platform.isAndroid`. `flutter build windows` locally to confirm.
- **VALIDATE**: `flutter build apk --debug` and `flutter build windows --debug`.
- **SATISFIES**: AC 3.

#### E3. CREATE `pingduck_app/lib/services/push_alerts.dart`

- **IMPLEMENT**:
  - `PushAlerts.enable()`: Android only. Request notification permission (`FirebaseMessaging.instance.requestPermission()` covers Android 13's runtime prompt). Denied → throw `NotificationsDeniedException` (Settings shows a toast with a link to system settings). Get the token; `upsert` into `push_tokens` `{token, platform: 'android'}` with `onConflict: 'token'`. Store `alerts_enabled = '1'` locally. Listen to `onTokenRefresh` → upsert.
  - `PushAlerts.disable()`: delete this token's row, `deleteToken()`, store `'0'`.
  - `isEnabled()`: local setting.
  - Message handling, shared by foreground (`onMessage`) and background: `@pragma('vm:entry-point') Future<void> onBackgroundMessage(RemoteMessage m)` top-level: `WidgetsFlutterBinding.ensureInitialized()`, `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`, `Supabase.initialize(...)` (same URL/key as `main.dart`; reads the saved session from disk), then `showNewDeviceAlert(networkId)`: query `device_events` `kind = 'new_device'`, `network_id = <id>`, `created_at > now - 15 min`, joined to `devices(hostname, vendor, mac)` (PostgREST embed `devices(hostname,vendor,mac)` via the FK), and `networks(name, ssid)`. Show **one** notification per network (notification id = `networkId.hashCode`, so a second alert replaces the first): title "New device on <ssid or name>", body = up to 3 display names (hostname → vendor → MAC) + "and N more". Channel `new_devices`, importance high.
  - Foreground: also trigger `supabaseSyncProvider` re-fetch.
  - Tap → opens the app on Overview (default route); no deep link yet.
  - Register `FirebaseMessaging.onBackgroundMessage(onBackgroundMessage)` in `main()` **before** `runApp`, Android only; `Firebase.initializeApp` there too, but don't `await` anything network-bound before the first frame.
- **GOTCHA**: The background isolate has no Riverpod and no Drift instance; keep `showNewDeviceAlert` dependent only on Supabase + `flutter_local_notifications`. Don't open the Drift DB from the background isolate (two isolates writing one SQLite file without `shareAcrossIsolates`).
- **GOTCHA**: If the session can't be restored in the background (signed out), show nothing.
- **GOTCHA**: Privacy copy: update `docs/` / website privacy policy mention later (Phase 8 row) — note in the PR that FCM is now a provider, carrying only `network_id`.
- **VALIDATE**: unit-test the notification text builder (`newDeviceAlertText(List<…>, networkName)`) in `test/domain_test.dart` style; `flutter analyze`.
- **SATISFIES**: AC 3, AC 4.

#### E4. UPDATE `settings_screen.dart` — wire the alerts switch

- **IMPLEMENT**: Replace C1's "Coming soon" with `PushAlerts.isEnabled()` state; `onChanged` → `enable()`/`disable()`, errors → toast. Add `pushAlertsProvider` with a fake in tests.
- **VALIDATE**: extend `test/settings_cloud_rows_test.dart`: Premium + agent + Android-flag → switch enabled; toggling calls the fake.
- **SATISFIES**: AC 3, AC 7.

#### E5. UPDATE docs

- **IMPLEMENT**: `docs/ROADMAP.md` Phase 4 rows (sync, alerts, Settings, Proxmox) → state and test evidence; the "Device identity" decision row stays open. Phase 8 "Privacy policy" row: add "name FCM as the alert channel; payload is a network id only". This plan's AMENDMENTS with anything that changed.
- **SATISFIES**: AC 9.

---

## TESTING STRATEGY

### Unit Tests
- **Dart** (`flutter test`): cache merge (B2), sync controller with a fake repository and a driven change stream (B3), Settings rows states (C1/E4), alert text builder (E3).
- **SQL** (`supabase/tests/schema_test.sql`): heartbeat version, `queue_new_device_alert` rules (plan, known, private MAC + known hostname, no tokens), `agent_sync` baseline (no alert on first sync) — all inside the existing rolled-back transaction, plain Postgres (pg_net absent → warning path).
- **Rust**: heartbeat sends `p_version`.
- **Deno**: message shape is data-only and high priority.

### Integration / Live
- Realtime against the live project with the Windows agent (already syncing 20 devices): app on the Pixel shows MACs/vendors within one sync.
- End-to-end alert (Level 4 below).

### Edge Cases
- First sync after pairing (all devices new) → no alert.
- A sync with 5 new devices → one FCM message, one notification listing 3 + "and 2 more".
- Device marked known, then reappears with the same MAC → no new event at all (not new). Private-MAC phone reconnects with a fresh MAC and the same hostname as a known device → event recorded, no alert.
- Free user → no alert, no error.
- Expired FCM token → function deletes it.
- User revokes the agent → sync shows no agent; alerts switch disables (no agent) but the token row stays until toggled off (acceptable; agent_sync can't run for a revoked agent anyway).
- App killed / phone in Doze → high-priority data message still wakes the handler (verify on the Pixel).
- Windows build: no Firebase calls, sync still works.
- Anonymous user → no sync, no sockets.

---

## VALIDATION COMMANDS

### Level 1: Syntax & Style
```
cd pingduck_app && flutter analyze
cd agent && cargo clippy --workspace --all-targets --locked -- -D warnings
deno check supabase/functions/notify-new-devices/index.ts
C:/Users/cnieves.wmg/go/bin/actionlint   # only if workflows change
```

### Level 2: Unit Tests
```
cd pingduck_app && flutter test
cd agent && cargo test --workspace --locked
deno test supabase/functions/notify-new-devices/
```

### Level 3: Integration Tests
```
# Schema tests on the VM (has Docker)
scp -r supabase pingduck-vm:~/pd-supabase && ssh pingduck-vm 'cd ~/pd-supabase && sh tests/run_tests.sh'
cd pingduck_app && flutter build apk --debug && flutter build windows --debug
```

### Level 4: Manual Validation (live project, Pixel 8 Pro, Windows agent)
1. User applies the migration and deploys the function (E0). Restart the Windows agent service on 0.3.1 → `select version from agents where id = '<id>'` returns `0.3.1` within a minute.
2. Pixel signed into the agent's account: Overview shows the ~20 devices with vendors, agent-only ones included; Inspector shows MACs.
3. Give the account Premium for the test: `insert into entitlements (user_id, plan_code, status, source) values ('<uid>', 'premium', 'active', 'manual');`
4. Settings → New-device alerts on → `push_tokens` has one android row.
5. Close the app (swipe away). Join a never-seen device to the LAN (e.g. a phone with a fresh private MAC, or a VM with a new MAC). Within the agent's interval (set `PINGDUCK_SCAN_INTERVAL=60` on the service for the test) a notification "New device on <SSID>" appears. **Time it: ≤ 2 minutes from join** (roadmap exit criterion).
6. Mark that device known in the Inspector; forget/rejoin with a new private MAC and the same hostname → event recorded, no notification.
7. Delete the manual entitlement afterwards.

---

## ACCEPTANCE CRITERIA

- [ ] AC 1: Devices the agent reports appear in the app's cache and UI for networks linked to Supabase, with MACs and vendors filled in by IP; agent-only devices appear with an "Agent" source; user names and notes are never overwritten.
- [ ] AC 2: Changes reach an open app through Realtime within ~5 s of `agent_sync` committing; Cloud sync can be turned off and then nothing is fetched or subscribed.
- [ ] AC 3: A new device on a monitored network (not the first sync) produces exactly one data-only FCM message per sync to each of the owner's Android tokens, and one local notification on the phone, including when the app is closed.
- [ ] AC 4: No alert for Free users, for the baseline sync, for devices marked known, or for private-MAC devices whose hostname matches a known device. The FCM payload contains only `kind` and `network_id`.
- [ ] AC 5: Inspector "Known device" and Settings "Mark all current devices as known" write `devices.is_known` and are reflected in the cache.
- [ ] AC 6: `agents.version` updates on the next heartbeat after an agent upgrade; 0.3.0 agents keep working.
- [ ] AC 7: Settings' Cloud & alerts panel shows real agent status, the sync switch and the alerts switch with correct disabled reasons.
- [ ] AC 8: `docs/PROXMOX.md` covers VM and LXC setups and hypervisor network filters.
- [ ] AC 9: Roadmap updated; Phase 4 exit criterion met on the Pixel (≤ 2 min push) or the gap documented.
- [ ] All validation commands pass; `app ci`, `agent ci`, `database ci`, `CodeQL` green; Windows build unaffected.

---

## COMPLETION CHECKLIST

- [ ] All tasks completed in order (Phases B and D can run in parallel with A)
- [ ] Each task validation passed immediately
- [ ] All validation commands executed successfully
- [ ] Full test suite passes (unit + integration)
- [ ] No linting or type checking errors
- [ ] Manual testing confirms feature works (Level 4)
- [ ] Acceptance criteria all met
- [ ] Code reviewed for quality and maintainability

---

## OPEN QUESTIONS / ASSUMPTIONS

- Assumed: one PR per phase (A, B+C, D, E) rather than one large PR; each is shippable alone (C ships the alerts switch as "Coming soon").
- Assumed: the user does the Firebase project, service-account secret, Vault secrets, migration apply and function deploy (Supabase MCP has no write access to this project).
- Assumed: `ttl: 600s` on FCM — an alert older than 10 minutes is dropped rather than delivered late. Confirm.
- Assumed: notification shows device names (hostname/vendor) on the lock screen. They come from Supabase, not FCM, but they are visible on the lock screen; set the channel's lock-screen visibility to `private` (shows "New device on <network>" only when locked). Confirm.
- Open: the exact locally-administered-MAC SQL expression — verify in psql during A3.
- Resolved: only `20261006120000_initial_schema.sql` defines `agent_sync`; A2 starts from that body.

## NOTES (open canvas)

**Why the server queues one request per sync, not a trigger per event.** `agent_sync` inserts `new_device` events one row at a time inside a loop; a row trigger would fire one HTTP call (and one push) per device. Doing it at the end of `agent_sync` gives one push per sync and knows whether this was the baseline sync. Other writers of `new_device` events don't exist.

**Why data-only + fetch.** The user ruled out sending device data through Google. A data-only message with `android.priority: HIGH` is delivered to the app's handler even when it's killed (not force-stopped) and in Doze; the handler then reads details over the user's own authenticated Supabase session, so RLS still applies. Cost: the handler needs network and a valid session, and Android gives it ~20 s. A 15-minute event window is generous for that.

**Why IP merge is good enough now.** On Android the phone never sees MACs, so the only join key between the phone's scan and the agent's rows is the IP, which both observe at the same moment. DHCP churn makes this wrong for a few minutes at a time, and the next sync or scan corrects it. Rekeying to MAC touches every screen and the radar; it's the "Device identity" decision and gets its own ticket once this is live.

**Sequencing.** A (migration + agent) and B/D can go in parallel. C needs B. E needs A, C and the user's Firebase setup — start E0 early since it's the user's long pole.

## AMENDMENTS


- 2026-10-12 — Phase E built. Background alerts hand off to the app's main isolate (IsolateNameServer port, 3 s ack) when it is alive, because a second isolate refreshing the Supabase token would rotate the refresh token under the main isolate and could trip reuse detection; only when no main isolate answers does the background isolate restore and re-save the session. The notification's small icon reuses `ic_launcher_monochrome` instead of a new `ic_stat_duck`. Sign-out unregisters the phone's token, and an alert for a network the signed-in account can't see shows nothing. Deno check and tests run in `database.yml`.
