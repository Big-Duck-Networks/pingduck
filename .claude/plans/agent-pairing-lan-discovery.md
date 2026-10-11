# Feature: Agent pairing with LAN discovery (Fing-style "Add monitoring unit")

The following plan should be complete, but its important that you validate documentation and codebase patterns and task sanity before you start implementing.

Pay special attention to naming of existing utils types and models. Import from the right files etc.

## Feature Description

A PingDuck user adds a homelab agent the way Fing users add a Fing Agent: Account → **Add monitoring unit**,
pick the platform, follow numbered install steps (or email them to yourself), then the app **finds the
agent on the LAN by itself** and activates it with one tap. No code to copy.

Under the hood the phone still uses the existing short-lived pairing code (`create_pairing_code`), but hands
it to the agent over the LAN instead of making the person type it. The agent redeems it directly with
Supabase (`claim_pairing_code`), so the long-lived token never crosses the LAN and the agent never holds the
service-role key. A `PINGDUCK_PAIRING_CODE` env var stays as a manual fallback for networks where SSDP
can't reach the phone (VLANs, VPN).

The flow and structure copy Fing's (screenshots from the user, 2026-10-10: "Boost your network scanning
power" → "Select a device for … installation" → "Get … on <platform>" stepper). Every screen is drawn with
PingDuck's own design system (`PdPanel`, `PdButton`, `PdChip`, Space Grotesk / Inter, square edges), not
Fing's look. The screens after the install steps (search, unit list, activate, activated) have no Fing
reference and are designed here in the same structure.

## User Story

As a PingDuck Premium user with a homelab box
I want to install the agent and have the app find and activate it on my Wi-Fi with one tap
So that I get MAC addresses, 24/7 monitoring and alerts without copying codes or tokens around

## Problem Statement

The server half of pairing exists and is tested, but nothing uses it. The app's Homelab Agent screen is a
placeholder (`agent_screen.dart:87`, "Pair agent · coming soon"), the app never creates the remote
`networks` row that `create_pairing_code` needs, and the agent image only runs a one-shot CLI scan with no
HTTP client. Fing users expect the agent to show up in the app by itself, so a type-the-code flow would
compare badly.

## Solution Statement

1. **Agent** (`agent/`, new C++ executable `pingduck-agent`, Linux only): keeps a state file on a volume,
   advertises itself over **SSDP/UPnP** (answers M-SEARCH, serves a UPnP description XML), runs a tiny HTTP
   listener on **port 44480** (`GET /pingduck/v1/info`, `POST /pingduck/v1/pair`), claims codes with
   libcurl, and checks in every 60s through a new `agent_heartbeat` RPC so it learns when it is revoked.
2. **Server** (one migration): `agent_heartbeat(p_token)`, and `email_agent_instructions(p_platform)`
   which mails the install steps through the existing pg_net + Resend path, rate-limited.
3. **App** (`features/agent/`): the 5-screen flow, LAN discovery through the core's existing SSDP scan
   (`pd_ssdp_discover` already fetches the description XML and fills `vendor` and `services`), remote
   network registration on demand, agent status and revoke on the Homelab Agent screen, and the Account
   tab entry point.
4. **Image**: multi-arch (amd64 + arm64) published to `ghcr.io/big-duck-networks/pingduck-agent`, so the
   Raspberry Pi and NAS instructions point at something real.

## Out of Scope / Non-Goals

- Not included: the scan loop and `agent_sync` reporting (the **Agent daemon** ticket). After pairing, this
  ticket's agent only heartbeats. Devices appear once the daemon ticket lands.
- Not included: Realtime sync into Drift, intrusion alerts / push, the Settings screen (separate Phase 4 items).
- Not included: billing, paywall, RevenueCat (Phase 5). The plan gate shows a plain "Premium required"
  screen; testing uses a `source = 'manual'` entitlement.
- Not included: a desktop app. Fing's "Fing Desktop" group (Windows/macOS) is **omitted**, not shown disabled.
- Not included: Fing's "Block unwanted devices" benefit (Phase 7 rules blocking out) and "vulnerability
  checks" (Phase 7). The intro lists only what the agent really does.
- Not included: mDNS advertising (`_pingduck._tcp`). SSDP matches Fing and the core already reads it.
- Not changing: `create_pairing_code`, `claim_pairing_code`, `revoke_agent`, `agent_sync` signatures, the
  core library (`core/src`), the `pingduck` CLI (stays in the image for debugging).
- Not changing: scan quota. The agent search uses `pd_ssdp_discover` only and does **not** call `claim_scan`.

## Feature Metadata

**Feature Type**: New Capability
**Estimated Complexity**: High (three codebases: C++ agent, SQL, Flutter; plus CI publishing)
**Primary Systems Affected**: `agent/`, `supabase/migrations`, `pingduck_app/lib/features/agent`, `account`, `tools`, `services/local_storage.dart`, `core/ffi/scanner_bridge.dart`, `.github/workflows/core.yml`
**Dependencies**: libcurl (`libcurl4-openssl-dev`), nlohmann/json (`nlohmann-json3-dev`, header-only), Docker buildx + QEMU in CI. No new Dart packages (`dart:io` `HttpClient` is enough).

## Related Work

**Implements**: `docs/ROADMAP.md` Phase 4 → "Agent pairing" · **Epic**: Phase 4 "Agent and cloud sync"

**Back-references**:
- `supabase/migrations/20261006120000_initial_schema.sql:110-220` — pairing RPCs this builds on (inherit, don't change)
- `supabase/migrations/20261008120000_goodbye_email.sql` — email-through-pg_net pattern to mirror
- ROADMAP Decisions: **Agent daemon language → C++** (this ticket settles it), **Device identity** (unchanged)

**Forward-references**:
- Agent daemon (scan loop + `agent_sync`) — reuses `agent/src/state.*`, `supabase_client.*`, the main loop
- Proxmox deployment guide — reuses the Linux install steps written here
- Realtime sync — reuses `networks.remote_id`

---

## CONTEXT REFERENCES

### Relevant Codebase Files IMPORTANT: YOU MUST READ THESE FILES BEFORE IMPLEMENTING!

- `supabase/migrations/20261006120000_initial_schema.sql` (lines 110-220, 255-290, 400-460) — networks/agents/pairing_codes tables, the pairing RPCs, `agent_sync`'s token lookup (`token_hash = extensions.digest(p_token,'sha256') and revoked_at is null`), RLS (`networks_own` allows insert by owner; `agents_own` select only), grants.
- `supabase/migrations/20261008120000_goodbye_email.sql` — `private` schema, `private.send_goodbye_email`, Vault key lookup, pg_net guard, how the HTML template is inlined from `supabase/email-templates/`.
- `supabase/tests/schema_test.sql` (lines 30-160) — `pg_temp.check` / `pg_temp.expect_error` / `vars` helpers; extend here.
- `supabase/tests/run_tests.sh`, `supabase/tests/supabase_stub.sql` — how tests run on plain Postgres 15 (no pg_net → emails skipped with a warning).
- `core/src/ssdp.cpp` (lines 60-110 `http_get`, 150-170 `note_response`/`apply_description`, 185-200 M-SEARCH) — what the phone sends and parses: ST `ssdp:all` and `upnp:rootdevice`, MX 1-5, LOCATION must be the responder's own IP, HTTP/1.0, body ≤256 KB, fields `friendlyName`→hostname, `manufacturer`→vendor, `modelName`(+`modelNumber`)→model, `deviceType`→`services` as `upnp:<Type>`.
- `core/cli/main.cpp` — option parsing and `json_escape` style to mirror in the agent.
- `core/CMakeLists.txt` (lines 15-100) — options, `PINGDUCK_PCAP`, target names (`pingduck`, `pingduck_objects`, `pingduck_cli`).
- `agent/Dockerfile` — current two-stage build to extend.
- `.github/workflows/core.yml` (lines 127-135) — `agent` job to extend with buildx + GHCR push.
- `packages/pingduck_core/lib/pingduck_core.dart` (line 231) — `ssdp({timeout})` returns a `ScanSession` of `PdDevice`.
- `pingduck_app/lib/core/ffi/scanner_bridge.dart` (lines 60-80 interface, `FfiScannerBridge`) — add `findAgents()`.
- `pingduck_app/lib/core/network/network_context.dart` (lines 110-120) — `MulticastLock.acquire/release`; Android needs it held while listening for SSDP replies.
- `pingduck_app/lib/features/scanner/application/scan_controller.dart` (lines 95-105 `claim_scan` via `signedInClient()`, ~199 lock usage) — RPC call and lock pattern.
- `pingduck_app/lib/features/auth/account_auth.dart` — `AccountAuth.email` is null while anonymous; `accountAuthProvider`.
- `pingduck_app/lib/features/auth/session.dart` — `signedInClient()`.
- `pingduck_app/lib/features/agent/presentation/agent_screen.dart` — placeholder to turn into the status screen; keep its visual vocabulary (icon tile 44×44, `PdChip('OFFLINE')`, `PdPanel` sections, code block on `surface2`).
- `pingduck_app/lib/features/account/presentation/account_screen.dart` (lines 40-90) — the Settings nav row to mirror for "Add monitoring unit"; line 207 pushes `SignInScreen` and awaits `bool`.
- `pingduck_app/lib/features/tools/presentation/tools_screen.dart` — `Tool.agent`, `_ToolsHub` status string (`'not paired'` hard-coded), `ToolBreadcrumb`.
- `pingduck_app/lib/core/widgets/pd_widgets.dart` — `PdPanel`, `PdField`, `PdChip`/`PdTone`, `PdButton`/`PdButtonStyle`, `PdSectionHeader`, `DuckLogo`.
- `pingduck_app/lib/core/theme/pingduck_colors.dart`, `pingduck_theme.dart` — tokens and `PdText` styles. No new colors.
- `pingduck_app/lib/services/local_storage.dart` (lines 10-35 tables, 78-85 `schemaVersion`/`onUpgrade`) — add `remoteId`, bump to 3.
- `pingduck_app/test/fakes.dart` — `FakeAuth`, `FakeQuota`, `memoryStore()`, `testLan`; add `FakeAgentRepository`, `FakeAgentLanClient`, extend the fake bridge.
- `pingduck_app/test/scan_quota_test.dart`, `widget_test.dart` — unit and widget test style.

### New Files to Create

**Agent (C++)**
- `agent/CMakeLists.txt` — builds `pingduck-agent`; `add_subdirectory(../core core)` with `PINGDUCK_BUILD_SHARED=OFF`, `PINGDUCK_PCAP=ON`; links `pingduck_objects`, `CURL::libcurl`, `nlohmann_json::nlohmann_json`.
- `agent/src/main.cpp` — config from env, signal handling, main loop.
- `agent/src/config.hpp/.cpp` — env vars and defaults.
- `agent/src/state.hpp/.cpp` — `agent.json` load/save (atomic, 0600), instance id.
- `agent/src/ssdp_responder.hpp/.cpp` — multicast listener, M-SEARCH replies, NOTIFY alive/byebye.
- `agent/src/http_server.hpp/.cpp` — minimal single-threaded HTTP/1.0 server.
- `agent/src/supabase_client.hpp/.cpp` — libcurl RPC calls.
- `agent/src/pairing.hpp/.cpp` — the pair handler (validation, mutex, state transitions), independent of sockets so it is unit-testable.
- `agent/tests/agent_tests.cpp` — unit tests (pair handler with a fake Supabase client, state round-trip, M-SEARCH matching, HTTP request parsing, description XML parsed by `pd::ssdp::apply_description`).
- `agent/compose.yaml` — the NAS / Compose install (`network_mode: host`, caps, volume).

**Server**
- `supabase/migrations/20261010120000_agent_pairing.sql` — `agent_heartbeat`, `email_sends`, `email_agent_instructions`, `private.send_agent_instructions_email`.
- `supabase/email-templates/agent_instructions.html` — template, same shell as `account_deleted.html`.

**App**
- `pingduck_app/lib/features/agent/domain/agent_platform.dart` — `AgentPlatform` enum: title, steps, install command.
- `pingduck_app/lib/features/agent/domain/agent_unit.dart` — `FoundAgent`, `PairedAgent`, `AgentAvailability`.
- `pingduck_app/lib/features/agent/data/agent_lan_client.dart` — `AgentLanClient` + `HttpAgentLanClient`.
- `pingduck_app/lib/features/agent/data/agent_repository.dart` — `AgentRepository` + `SupabaseAgentRepository`.
- `pingduck_app/lib/features/agent/application/agent_pairing_controller.dart` — search/activate state machine.
- `pingduck_app/lib/features/agent/application/agent_status.dart` — `myAgentsProvider` for the status screen and Tools hub.
- `pingduck_app/lib/features/agent/presentation/add_unit_intro_screen.dart` — screen 1.
- `pingduck_app/lib/features/agent/presentation/select_platform_screen.dart` — screen 2.
- `pingduck_app/lib/features/agent/presentation/install_steps_screen.dart` — screen 3.
- `pingduck_app/lib/features/agent/presentation/find_agent_screen.dart` — screen 4 (search / list / activate / errors / manual code).
- `pingduck_app/lib/features/agent/presentation/agent_activated_screen.dart` — screen 5.
- `pingduck_app/lib/features/agent/presentation/flow_scaffold.dart` — shared layout for screens 1-3 (back arrow, headline, body, bottom primary + "Maybe later").
- `pingduck_app/test/agent_pairing_controller_test.dart`, `pingduck_app/test/agent_flow_widget_test.dart`, `pingduck_app/test/agent_lan_client_test.dart`.

### Relevant Documentation YOU SHOULD READ THESE BEFORE IMPLEMENTING!

- [UPnP Device Architecture 2.0, §1 Discovery](https://openconnectivity.org/upnp-specs/UPnP-arch-DeviceArchitecture-v2.0-20200417.pdf) — M-SEARCH response headers (`CACHE-CONTROL`, `EXT`, `LOCATION`, `SERVER`, `ST`, `USN`, `BOOTID.UPNP.ORG`), MX random delay, NOTIFY `ssdp:alive`/`ssdp:byebye`; §2 Description — minimal root device XML.
- [libcurl easy interface](https://curl.se/libcurl/c/libcurl-tutorial.html) — `CURLOPT_POSTFIELDS`, `CURLOPT_HTTPHEADER`, `CURLOPT_TIMEOUT_MS`, `CURLOPT_WRITEFUNCTION`; `curl_global_init` once.
- [PostgREST RPC](https://docs.postgrest.org/en/stable/references/api/functions.html) — `POST /rest/v1/rpc/<fn>` with a JSON body of named args; errors return `{"code","message",...}` with HTTP 400/401/404. Supabase needs the `apikey` header (publishable key).
- [Supabase API keys](https://supabase.com/docs/guides/api/api-keys) — publishable key is safe to ship; the agent uses it like the app.
- [nlohmann/json](https://json.nlohmann.me/) — `json::parse(s, nullptr, false)` (no exceptions) and `is_discarded()`.
- [Docker build-push-action multi-platform](https://docs.docker.com/build/ci/github-actions/multi-platform/) and [publishing to GHCR](https://docs.github.com/en/packages/managing-github-packages-using-github-packages-actions-workflows/publishing-and-installing-a-package-with-github-actions) — `docker/setup-qemu-action`, `docker/setup-buildx-action`, `docker/login-action`, `permissions: packages: write`.
- [Synology Container Manager](https://kb.synology.com/en-global/DSM/help/ContainerManager/docker_project?version=7) — Projects take a compose file; host network mode is supported.
- [Fing Agent Docker install](https://help.fing.com/hc/en-us/articles/16874649602588) and [activation](https://help.fing.com/hc/en-us/articles/25770040027292) — the UX being matched.

### Patterns to Follow

**SQL RPCs** (from `initial_schema.sql`): `language plpgsql volatile security definer set search_path = ''`, fully qualified names (`public.agents`, `extensions.digest`), errors as `raise exception '<snake_reason> ...' using errcode = '28000' | 'P0001' | 'P0002' | '22023'`, return `jsonb_build_object(...)`, explicit `grant execute ... to <role>` after `revoke` (the schema revokes from public by default at the end).

```sql
select * into v_agent from public.agents
where token_hash = extensions.digest(p_token, 'sha256') and revoked_at is null;
if v_agent.id is null then
    raise exception 'invalid agent token' using errcode = '28000';
end if;
```

**Email** (from `goodbye_email.sql`): a `private.` function that guards `to_regproc('net.http_post')` and the Vault secret, warns and returns when missing, and calls `net.http_post` through `execute ... using`. The template HTML lives in `supabase/email-templates/` and is pasted into the function.

**Dart interfaces + fakes**: narrow `abstract interface class` with one Supabase-backed impl and a `Provider` (see `AccountAuth` / `accountAuthProvider`, `ScannerBridge`). Tests swap the provider with a fake from `test/fakes.dart`.

**RPC calls**: `await (await signedInClient()).rpc('fn', params: {...})`; map `PostgrestException.message` prefixes (`plan_limit`, `network not found`) to typed results, as `ScanQuota` maps answers.

**Errors**: never fake data. Unknown fields are left out (`inspector_screen` rule). Error copy follows the brand voice (short, plain, says what to do next).

**Navigation**: `Navigator.of(context).push(MaterialPageRoute<T>(builder: ...))` (see `account_screen.dart:55`, `:207`). The flow is pushed on top of the shell; "Maybe later" pops to the first route of the flow (`Navigator.popUntil(context, (r) => r.settings.name == AddUnitIntroScreen.routeName || r.isFirst)` then pop once). Give the intro route a `RouteSettings(name: ...)`.

**C++** (from `core/`): `snake_case` functions, `namespace pd::agent`, no exceptions across module boundaries (return `bool`/`std::optional`), RAII `Socket`-style wrappers, `std::snprintf` not iostreams in hot paths, every recv bounded.

**Comments**: short, explain why (match `ssdp.cpp`: "Only fetch from the responder itself, so a LAN device cannot point the scanner at an arbitrary host.").

---

## UI / UX SPEC

Shared layout for screens 1-3 (`flow_scaffold.dart`), mirroring Fing's structure:

```
┌──────────────────────────────┐
│ ←                            │  IconButton(arrow_back, 20) top-left, no app bar title
│                              │
│  [illustration / none]       │
│                              │
│  Headline                    │  PdText.headlineLg (Space Grotesk 700), 2 lines max
│  Supporting line             │  PdText.bodyMd, inkSecondary
│                              │
│  body (list / cards / steps) │
│                              │
│ ┌──────────────────────────┐ │
│ │       PRIMARY ACTION     │ │  PdButton full width (hard offset shadow)
│ └──────────────────────────┘ │
│         MAYBE LATER          │  TextButton, PdText.labelLg, ink
└──────────────────────────────┘
```
Canvas background, 24px side padding, bottom actions pinned (`SafeArea` + `Column` with `Expanded(SingleChildScrollView)` above them).

**Screen 1 — Intro** (`AddUnitIntroScreen`, route `agent/intro`)
- Illustration: a 120px-tall row drawn with existing icons on square tiles: phone tile (`Icons.smartphone`) ⟷ dashed `partition` line ⟷ server tile (`Icons.dns_outlined`), with a `DuckLogo` (32px) on the server tile. Static, no animation.
- Headline: **"Watch your network around the clock"**
- Line: "A PingDuck agent on an always-on box can:"
- Checklist (icon `Icons.check` in `PingDuckColors.live`, `PdText.bodyLg`):
  - "Get every device's MAC address and maker, which phones can't see"
  - "Scan around the clock, even when your phone is away"
  - "Alert you when an unknown device joins"
- Primary: **LET'S START**. Secondary: **MAYBE LATER** (pops the flow).
- On LET'S START, in order: (a) not signed in to an email account → push `SignInScreen`; continue only if it returns `true`. (b) `my_plan().max_monitored_networks == 0` → push the **Premium required** state (below). (c) otherwise → screen 2.

**Premium required** (a variant of the flow scaffold, no new route class needed)
- Headline: "Monitoring is a Premium feature". Line: "Premium includes the agent on up to 2 networks, full history and alerts."
- Primary: disabled `PdButton('SUBSCRIPTIONS COMING SOON')` until Phase 5. Secondary: MAYBE LATER.

**Screen 2 — Select platform** (`SelectPlatformScreen`)
- Headline: **"Where will the agent run?"** Line: "Pick the always-on box on this network."
- Group label `PdText.labelSm` "PINGDUCK AGENT", then radio cards (full width, 64px tall, 12px gap):
  - **Linux or Proxmox** · sub "Docker on any 64-bit Linux box or VM"
  - **Raspberry Pi** · sub "Pi 3, 4 or 5 with 64-bit Raspberry Pi OS"
  - **Synology / QNAP NAS** · sub "Container Manager or Container Station"
- Card: `Container` with 1px `partition` border, `canvas` fill; selected: 2px `ink` border, `surface1` fill, filled `Radio`. Whole card is the tap target; `Semantics(selected:, inRadioGroup: true)`.
- First card preselected (Fing preselects). Primary: **NEXT**. Secondary: MAYBE LATER.

**Screen 3 — Install steps** (`InstallStepsScreen(platform)`)
- Headline: **"Install the agent on <platform title>"**. Line: per platform (e.g. Linux: "One container. It finds devices your phone can't and keeps watching when you leave.").
- Vertical stepper: 32×32 **square** markers (1px `ink` border, number in `PdText.labelLg`), connected by a 1px dashed `partition` line (CustomPainter, 4px dash). Step text `PdText.bodyLg`. Steps that include a command show a code block under the text (`surface2`, `PdText.code`, selectable) with a copy `IconButton` (`Icons.copy`, tooltip "Copy command"; `Clipboard.setData`, snackbar "Copied").
- Steps per platform (source of truth: `AgentPlatform.steps`):
  - **Linux/Proxmox**: 1 "Open a terminal on the box" · 2 "Run:" + `docker run -d --name pingduck-agent --restart unless-stopped --net=host --cap-add=NET_RAW --cap-add=NET_ADMIN -v pingduck:/var/lib/pingduck ghcr.io/big-duck-networks/pingduck-agent:latest` · 3 "Keep this phone on the same Wi-Fi" · 4 "Tap Find my agent".
  - **Raspberry Pi**: 1 "Install Docker: `curl -fsSL https://get.docker.com | sh`" · 2 same run command · 3, 4 as above.
  - **NAS**: 1 "Open Container Manager (Synology) or Container Station (QNAP)" · 2 "Create a project from this compose file:" + contents of `agent/compose.yaml` · 3, 4 as above.
- Primary: **FIND MY AGENT** → screen 4. Secondary row (replaces Fing's primary): `PdButton(style: secondary)` **EMAIL ME THESE STEPS** → `email_agent_instructions(platform)`; snackbar "Sent to <email>" / "Couldn't send. Try again in a few minutes." Then MAYBE LATER.
  - **GOTCHA**: Fing makes email the primary. Ours is FIND MY AGENT because the person is often already at the box; email stays one tap away. Same structure, one swapped emphasis — flagged in Open Questions.

**Screen 4 — Find my agent** (`FindAgentScreen`), uses `ToolBreadcrumb`-style header "←  ADD MONITORING UNIT"
States from `AgentPairingState`:
- **searching**: `PdPanel(title: 'SEARCHING', icon: Icons.wifi_find)`: "Looking for PingDuck agents on <SSID or CIDR>…" + `LinearProgressIndicator` (ink on surface2, square). Lasts the SSDP window (4s) plus `info` lookups.
- **found** (one or more): list of agent cards: 44×44 icon tile (`Icons.dns_outlined`), name (`PdText.headlineSm`), `"<ip> · v<version>"` (`PdText.bodySm`), chip right:
  - `AVAILABLE` (`PdTone.live`) → card tappable → bottom primary **ACTIVATE <NAME>**
  - `YOURS` (`PdTone.neutral`) → tap goes to the Homelab Agent screen
  - `TAKEN` (`PdTone.warning`) → sub "Activated by another account. Revoke it there, or reset the agent's volume." Not tappable.
  Below: **SEARCH AGAIN** (secondary) and a "Not finding it?" link.
- **none**: `PdPanel(title: 'NO AGENT FOUND', accent: warning)` with the checklist: "The container is running (`docker ps`)" · "It uses `--net=host`" · "The phone is on the same Wi-Fi, not a guest network" · "Port 44480 isn't blocked by the box's firewall". Buttons: **SEARCH AGAIN**, **USE A PAIRING CODE**.
- **activating**: checklist panel with three rows that tick as they finish: "Registering this network" → "Sending the code to <name>" → "Waiting for <name> to confirm". Each row: 16px spinner while active, `Icons.check` (live) when done, `Icons.close` (critical) on failure.
- **manualCode** (from "Use a pairing code"): big code in `PdText.displayMd` monospace, grouped `ABCD 2345`, countdown "Expires in 9:41", the env command `docker run ... -e PINGDUCK_PAIRING_CODE=ABCD2345 ...` with copy button, and "Waiting for the agent…" (polls `myAgents` every 3s). Expired → **NEW CODE**.
- **failed(reason)**: panel with critical accent, one line per reason (see Failure behavior), **TRY AGAIN**.
- Leaving the screen cancels the SSDP session and stops polling.

**Screen 5 — Activated** (`AgentActivatedScreen`)
- Flow scaffold, no back arrow (`PopScope(canPop: false)`), illustration: 64px server tile with `Icons.check` in `live`.
- Headline: **"<name> is on watch"**. Line: "It's paired with <SSID or CIDR>."
- `PdField`s: AGENT (name), NETWORK (SSID / CIDR), VERSION.
- Primary: **DONE** → pops the whole flow and opens Tools → Homelab Agent (`activeToolProvider.open(Tool.agent)` + switch the shell to the Tools tab — read `app_shell.dart` for the tab index provider).

**Homelab Agent screen (rework of `agent_screen.dart`)**
- No agent: keep today's "What the agent adds" panel; replace the "Run it" panel's disabled button with **ADD MONITORING UNIT** (starts the flow at screen 1).
- Agents (from `myAgentsProvider`, non-revoked, newest first): per agent a status panel: name, network label, chip `ONLINE` (live) if `last_seen_at` < 3 min ago else `OFFLINE`; `PdField`s LAST SEEN (relative), VERSION, PAIRED (date); **REVOKE** (`PdButtonStyle.destructive`) with an `AlertDialog` in the style of `_confirmClear` ("REVOKE AGENT?" / "It stops reporting at once. To use it again, add it as a new monitoring unit."). Then **ADD MONITORING UNIT** for another network.
- Tools hub status: `'not paired'` → `'<n> paired'` / `'not paired'` from the provider.

**Account tab**: new `PdPanel(title: 'Monitoring', icon: Icons.dns_outlined)` between Identity and Settings, containing one nav row identical in build to the Settings row: title "Add monitoring unit", sub "Run the agent on an always-on box", chevron. When agents exist, sub becomes "<n> agent(s) paired" and the row opens the Homelab Agent tool instead.

---

## AGENT SPEC

**Env vars** (`config.cpp`; all optional):

| Var | Default | Notes |
| --- | --- | --- |
| `PINGDUCK_SUPABASE_URL` | `https://rumwtzzyrhzudguolasq.supabase.co` | Same default as `supabase_config.dart` |
| `PINGDUCK_SUPABASE_KEY` | `sb_publishable_eWbf9jGpxBWQ6t7Vtz8r5A_mWfdmVrK` | Publishable key only |
| `PINGDUCK_STATE_DIR` | `/var/lib/pingduck` | Must be a volume |
| `PINGDUCK_AGENT_NAME` | `gethostname()` trimmed to 64 | Shown in the app |
| `PINGDUCK_HTTP_PORT` | `44480` | |
| `PINGDUCK_PAIRING_CODE` | — | Manual fallback; used once at start while unpaired |

**State file** `$STATE_DIR/agent.json`: `{"instance_id": "<uuid v4>", "agent_id": "...", "network_id": "...", "token": "<64 hex>"}`. `instance_id` is created on first start and kept for the life of the volume (it is the UPnP UDN). Writes go to `agent.json.tmp`, `fsync`, `rename`, mode `0600`. Unreadable/corrupt file → log and treat as unpaired, keep the bad file as `agent.json.bad`.

**SSDP responder** (`ssdp_responder.cpp`):
- UDP socket bound to `0.0.0.0:1900` with `SO_REUSEADDR` (and `SO_REUSEPORT` on Linux, other UPnP daemons may hold 1900), join `239.255.255.250` on the LAN interface (`pd_default_interface` from the core).
- Answer `M-SEARCH` whose `MAN` is `"ssdp:discover"` and `ST` is one of `ssdp:all`, `upnp:rootdevice`, `urn:pingduck-app:device:PingDuckAgent:1`, `uuid:<instance_id>`. Unicast reply to the sender after a random delay in `[0, min(MX,5)*1000)` ms, capped at 1000 ms (the phone's window is short). For `ssdp:all` send two replies (rootdevice and the device type).
- Reply headers: `HTTP/1.1 200 OK`, `CACHE-CONTROL: max-age=1800`, `EXT:`, `LOCATION: http://<lan ip>:<port>/description.xml`, `SERVER: Linux/1 UPnP/1.1 PingDuckAgent/<version>`, `ST`, `USN: uuid:<instance_id>::<ST>`, `BOOTID.UPNP.ORG: <start epoch>`.
- `NOTIFY ssdp:alive` ×2 at start and every 15 min; `ssdp:byebye` on SIGTERM.
- Bounded: recv buffer 2048, ignore datagrams over that, at most 20 replies/second total (token bucket) so the agent can't be used as an amplifier.

**HTTP server** (`http_server.cpp`): one thread, `poll()`, at most 8 concurrent connections, 2 s per request, request line + headers ≤ 4 KB, body ≤ 1 KB, `Connection: close`, HTTP/1.0 responses with `Content-Length`. Routes:
- `GET /description.xml` → UPnP root description: `deviceType urn:pingduck-app:device:PingDuckAgent:1`, `friendlyName` = agent name, `manufacturer` **PingDuck**, `modelName` **PingDuck Agent** (no `modelNumber`, so the core's `model` stays exactly "PingDuck Agent"), `UDN uuid:<instance_id>`, `presentationURL /pingduck/v1/info`. XML-escape the name.
- `GET /pingduck/v1/info` → `{"app":"pingduck-agent","api":1,"instance_id":"...","name":"...","version":"...","paired":bool,"agent_id":"<uuid>|null"}`.
- `POST /pingduck/v1/pair` (`Content-Type: application/json`, body `{"code":"ABCD2345"}`) → handled by `pairing.cpp`:
  - already paired → `409 {"error":"already_paired"}`
  - a pair already in flight → `429 {"error":"busy"}`
  - code not `^[A-HJ-KM-NP-Z2-9]{8}$` after upper/trim (alphabet from `create_pairing_code`) → `400 {"error":"bad_code"}`
  - `claim_pairing_code` → PostgREST 4xx with message `invalid or expired pairing code` → `400 {"error":"invalid_code"}`; network / 5xx / timeout (10 s) → `502 {"error":"upstream"}`
  - success → save state, `200 {"agent_id":"...","network_id":"..."}`. The token is **never** in a response.
  - per-IP limit: 5 POSTs/minute → `429`.
- Anything else → 404. No CORS headers (browsers on the LAN can't read responses; a browser `POST` with `text/plain` is rejected because `Content-Type` must be `application/json`, which forces a preflight the server doesn't answer).

**Supabase client**: `POST {url}/rest/v1/rpc/claim_pairing_code` body `{"p_code","p_name","p_version"}`; `POST {url}/rest/v1/rpc/agent_heartbeat` body `{"p_token"}`. Headers `apikey: <key>`, `Content-Type: application/json`. TLS verification on (CA bundle from `ca-certificates`). Timeout 10 s.

**Main loop**: load config/state → if unpaired and `PINGDUCK_PAIRING_CODE` set → claim (log success or the error; don't exit on failure) → start SSDP + HTTP threads → every 60 s while paired call `agent_heartbeat`; `{"status":"revoked"}` → delete `token`/`agent_id` from state (keep `instance_id`), log "revoked from the app; waiting to be added again". Network errors → keep state, retry next tick. SIGTERM/SIGINT → byebye, stop threads, exit 0. Logs are plain lines to stdout (`docker logs`), never the token or code.

---

## IMPLEMENTATION PLAN

### Phase 1: Server

Migration + tests. Unblocks the agent's heartbeat and the app's email button.

### Phase 2: Agent

**Depends on:** Phase 1 (`agent_heartbeat`)
**Independent of:** Phase 3 (the app only needs the HTTP contract above; fakes cover it)

### Phase 3: App

**Depends on:** Phase 1 (`email_agent_instructions`, `agent_heartbeat` updating `last_seen_at`)
**Independent of:** Phase 2 until the end-to-end test

### Phase 4: Image publishing + end-to-end

**Depends on:** Phases 2 and 3

---

## STEP-BY-STEP TASKS

### CREATE supabase/migrations/20261010120000_agent_pairing.sql

- **IMPLEMENT**:
  - `public.agent_heartbeat(p_token text) returns jsonb`: look up the agent by `token_hash` **without** the `revoked_at is null` filter; not found or revoked → `{"status":"revoked"}` (do not raise, so the agent can tell revoked from broken). Active → `update ... set last_seen_at = now()` and return `{"status":"active","agent_id":...,"network_id":...}`. `grant execute ... to anon, authenticated`.
  - `public.email_sends (user_id uuid references auth.users on delete cascade, kind text, sent_at timestamptz default now())`, index `(user_id, kind, sent_at desc)`, RLS on, no policies, revoked from anon/authenticated. Add `delete from public.email_sends where sent_at < now() - interval '7 days'` to `prune_history` with `create or replace` (copy its current body first).
  - `public.email_agent_instructions(p_platform text) returns jsonb`: `auth.uid()` required; address from `auth.users.email` where `is_anonymous` is false, else raise `'account_required'` (`28000`); `p_platform in ('linux','raspberry_pi','nas')` else `22023`; more than 3 sends in the last hour → raise `'rate_limited'` (`P0001`); insert into `email_sends`; call `private.send_agent_instructions_email(email, p_platform)`; return `{"sent_to": email}`. `grant execute ... to authenticated`.
  - `private.send_agent_instructions_email(p_email, p_platform)` mirroring `private.send_goodbye_email`: same guards; subject "Set up your PingDuck agent"; HTML from the template with the platform's steps substituted via `replace(v_html, '{{steps}}', v_steps)` where `v_steps` is a `case p_platform` of pre-escaped `<ol>` HTML.
- **PATTERN**: `20261008120000_goodbye_email.sql` (whole file); RPC style `initial_schema.sql:150-220`.
- **GOTCHA**: `auth.users.is_anonymous` exists on Supabase; check `supabase/tests/supabase_stub.sql` has it, add it to the stub if not. Keep the install command in the email identical to `AgentPlatform.steps` (copy-paste, single source in the plan above).
- **GOTCHA**: `create or replace function public.prune_history()` — read the current body in `initial_schema.sql` (~line 382) and keep every existing delete.
- **VALIDATE**: `bash supabase/tests/run_tests.sh` (needs Docker — not on this Windows box; run on `ssh pingduck-vm`, which has Docker: `ssh pingduck-vm 'cd pingduck && git pull && bash supabase/tests/run_tests.sh'`), or paste `schema_test.sql` into the Supabase SQL editor after the user applies the migration.
- **SATISFIES**: AC 5, 6, 9

### CREATE supabase/email-templates/agent_instructions.html

- **IMPLEMENT**: copy `account_deleted.html`'s shell (header, card, footer); title "Set up your PingDuck agent"; preview line "Three steps to put a PingDuck agent on your network."; body: `{{steps}}` placeholder, then "Then open PingDuck on the same Wi-Fi and tap **Find my agent**." Footer: why you got this ("You asked PingDuck to email these steps.").
- **PATTERN**: `supabase/email-templates/account_deleted.html`, `supabase/email-templates/README.md`.
- **VALIDATE**: open in a browser; the inlined copy in the migration matches the file (diff by eye or `grep -c`).
- **SATISFIES**: AC 6

### UPDATE supabase/tests/schema_test.sql

- **IMPLEMENT**: after the existing pairing section: `agent_heartbeat(token)->>'status' = 'active'` and bumps `last_seen_at`; `agent_heartbeat('deadbeef')->>'status' = 'revoked'`; after the existing `revoke_agent` step, heartbeat with the old token returns `revoked`. Email: as an anonymous user `expect_error(... 'account_required')`; as a signed-in user 3 calls succeed (email skipped with a warning on plain Postgres), the 4th → `rate_limited`; bad platform → error. Anon role cannot select `email_sends`.
- **PATTERN**: `schema_test.sql:61-160` (`set local role`, `request.jwt.claims` setup, `vars`).
- **VALIDATE**: `bash supabase/tests/run_tests.sh` → all checks pass.
- **SATISFIES**: AC 5, 6, 9

### CREATE agent/CMakeLists.txt, agent/src/config.*, agent/src/state.*

- **IMPLEMENT**: CMake project `pingduck_agent`, C++17, `set(PINGDUCK_BUILD_SHARED OFF CACHE BOOL "" FORCE)`, `set(PINGDUCK_BUILD_CLI ON ...)`, `set(PINGDUCK_PCAP ON ...)`, `add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../core core)`, `find_package(CURL REQUIRED)`, `find_package(nlohmann_json 3 REQUIRED)`, target `pingduck-agent` (output name) linking `pingduck_objects CURL::libcurl nlohmann_json::nlohmann_json Threads::Threads`; option `PINGDUCK_AGENT_TESTS` builds `agent_tests` + `add_test`. `if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux") message(FATAL_ERROR ...)`.
  Config and state as in the Agent spec; uuid v4 from `/dev/urandom` (16 bytes, set version/variant bits).
- **PATTERN**: `core/CMakeLists.txt` style; `core/cli/main.cpp` for small helpers.
- **GOTCHA**: `pingduck_objects` must be linkable from outside (it is an OBJECT/STATIC lib in core — check its type; if OBJECT, use `$<TARGET_OBJECTS:...>` or link the static `pingduck`). Core's include dir is `core/include` + private `core/src` (the tests need `parsers.hpp` for `pd::ssdp::apply_description`; add `core/src` as a private include for `agent_tests` only).
- **VALIDATE**: on `pingduck-vm`: `sudo apt-get install -y libcurl4-openssl-dev nlohmann-json3-dev && cmake -S agent -B build-agent -DPINGDUCK_AGENT_TESTS=ON && cmake --build build-agent -j && ctest --test-dir build-agent --output-on-failure`
- **SATISFIES**: AC 1, 8

### CREATE agent/src/supabase_client.*, agent/src/pairing.*

- **IMPLEMENT**: `struct RpcResult { int http; std::string body; bool network_error; }`; `class SupabaseClient { virtual RpcResult call(const std::string& fn, const nlohmann::json& args) = 0; }` with `CurlSupabaseClient`. `class Pairing { PairResponse handle(const std::string& peer_ip, std::string_view body); }` holding `State&`, `SupabaseClient&`, a mutex, the per-IP limiter and the busy flag; returns `{status, json}` exactly as specified. Name/version passed to `claim_pairing_code` from config and `pd_version()`.
- **GOTCHA**: hold the state mutex only around the state write, not across the 10 s network call (the busy flag guards concurrent pairs). Never log `body` or the token.
- **VALIDATE**: unit tests in `agent/tests/agent_tests.cpp` with a fake client: success saves state and hides token; second pair → 409; bad code → 400 without calling the client; invalid → 400; network error → 502 and state unchanged; 6th POST in a minute from one IP → 429.
- **SATISFIES**: AC 1, 3, 7

### CREATE agent/src/http_server.*, agent/src/ssdp_responder.*

- **IMPLEMENT**: as in the Agent spec. Request parsing in a pure function (`parse_request(std::string_view) -> std::optional<Request>`) and M-SEARCH matching in a pure function (`match_msearch(msg, instance_id) -> std::vector<std::string> sts`) so both are unit-tested without sockets.
- **PATTERN**: `core/src/ssdp.cpp` (`parse_headers`, socket helpers in `core/src/net_util.hpp`, `platform.hpp` `Socket`) — reuse these headers rather than rewriting.
- **GOTCHA**: The phone's `http_get` rejects a LOCATION whose host differs from the UDP sender's IP (`ssdp.cpp:79`). With `--net=host` and several interfaces, reply from and advertise the same LAN IP (bind the reply socket to the interface address from `pd_default_interface`).
- **GOTCHA**: Port 1900 may already be bound by `minidlna`/`miniupnpd` on the host. `SO_REUSEPORT` + multicast join works alongside them on Linux; log clearly if bind still fails, and keep the HTTP listener and the manual code path working.
- **VALIDATE**: unit tests: description XML fed through `pd::ssdp::apply_description` gives vendor `PingDuck`, model `PingDuck Agent`, services containing `upnp:PingDuckAgent`; M-SEARCH for `ssdp:all`/`upnp:rootdevice`/device type/uuid match, other STs and non-`ssdp:discover` don't; oversize request → rejected. Then live on `pingduck-vm`: run the binary, and from the Windows box `build\pingduck_cli ssdp` (or `pingduck ssdp` in core's CLI) lists the agent with vendor PingDuck; `curl http://10.42.0.170:44480/pingduck/v1/info` returns the JSON.
- **SATISFIES**: AC 1, 2, 7

### CREATE agent/src/main.cpp

- **IMPLEMENT**: main loop per spec; `curl_global_init` once; `signal`/`sigaction` for SIGTERM/SIGINT setting an atomic; threads join on exit. `--version` prints `pd_version()`.
- **VALIDATE**: on `pingduck-vm` with a manual entitlement on a test user: get a code from the SQL editor (`select create_pairing_code(...)` as that user, or from the app), `PINGDUCK_PAIRING_CODE=XXXXXXXX ./pingduck-agent` pairs; restart without the env var stays paired; `select revoke_agent(...)`, within 60 s logs "revoked" and `/info` shows `paired:false`.
- **SATISFIES**: AC 3, 4, 7

### UPDATE agent/Dockerfile, CREATE agent/compose.yaml

- **IMPLEMENT**: build stage adds `libcurl4-openssl-dev nlohmann-json3-dev`, copies `agent/` too, builds `cmake -S agent -B build -DCMAKE_BUILD_TYPE=Release`. Runtime adds `libcurl4 ca-certificates`, copies `pingduck-agent` and `pingduck_cli` (as `pingduck`), `VOLUME /var/lib/pingduck`, `EXPOSE 44480`, `ENTRYPOINT ["pingduck-agent"]`. Update the header comment's run command to the new one. `compose.yaml`: service `pingduck-agent`, image `ghcr.io/big-duck-networks/pingduck-agent:latest`, `network_mode: host`, `cap_add: [NET_RAW, NET_ADMIN]`, `volumes: [pingduck:/var/lib/pingduck]`, `restart: unless-stopped`.
- **GOTCHA**: the CI `agent` job runs `--entrypoint pingduck ... oui ...`; keep the CLI at `/usr/local/bin/pingduck` so it still passes.
- **VALIDATE**: on `pingduck-vm`: `docker build -f agent/Dockerfile -t pingduck-agent . && docker run --rm pingduck-agent --version && docker run --rm --entrypoint pingduck pingduck-agent oui 50:c7:bf:00:00:01 --oui /usr/share/pingduck/oui.csv`
- **SATISFIES**: AC 8

### UPDATE .github/workflows/core.yml (agent job)

- **IMPLEMENT**: `permissions: { contents: read, packages: write }`; steps `docker/setup-qemu-action@v3`, `docker/setup-buildx-action@v3`; build `linux/amd64` with `load: true` and run the existing smoke test plus `--version`; then on `push` to `main` only, `docker/login-action@v3` (ghcr.io, `${{ github.actor }}`, `${{ secrets.GITHUB_TOKEN }}`) and `docker/build-push-action@v6` with `platforms: linux/amd64,linux/arm64`, tags `ghcr.io/big-duck-networks/pingduck-agent:latest` and `:sha-${{ github.sha }}`, `cache-from/to: type=gha`. Add `agent_tests` (ctest) to the existing Linux GCC job or a step inside the agent build.
- **GOTCHA**: arm64 under QEMU compiles slowly (~10-20 min); keep `timeout-minutes: 45`. The GHCR package must be made **public** once, by hand, in the org's package settings (user action) or Pi/NAS pulls fail with `unauthorized`.
- **VALIDATE**: `gh workflow run core.yml` / push, then `gh run watch`; `docker pull ghcr.io/big-duck-networks/pingduck-agent:latest` on `pingduck-vm` (amd64) works anonymously.
- **SATISFIES**: AC 8

### UPDATE pingduck_app/lib/services/local_storage.dart

- **IMPLEMENT**: `TextColumn get remoteId => text().nullable()();` on `Networks` (doc: "Supabase `networks.id`, set when the person pairs an agent on this network."); `schemaVersion => 3`; `if (from < 3) await m.addColumn(networks, networks.remoteId);`; `Future<String?> remoteNetworkId(int networkId)` and `Future<void> setRemoteNetworkId(int networkId, String id)`. Regenerate.
- **PATTERN**: the `ssid` column added at v2 (`local_storage.dart:83`, `:97-103`).
- **VALIDATE**: `cd pingduck_app && dart run build_runner build --delete-conflicting-outputs && flutter test`
- **SATISFIES**: AC 2

### UPDATE pingduck_app/lib/core/ffi/scanner_bridge.dart

- **IMPLEMENT**: add `Stream<DiscoveredDevice> findAgents({Duration timeout = const Duration(seconds: 4)})` to `ScannerBridge`; `FfiScannerBridge` runs `core.ssdp(timeout:)`, maps like scan results, filters `vendor == 'PingDuck' && services.contains('upnp:PingDuckAgent')`. Update the fake bridge in `test/fakes.dart` (or wherever it lives) with a settable list.
- **GOTCHA**: hold the Android `MulticastLock` for the duration (mirror `scan_controller.dart:~199`: acquire before, release in `finally`). Without it Android drops the SSDP replies and the search always finds nothing.
- **VALIDATE**: `flutter analyze && flutter test`
- **SATISFIES**: AC 2

### CREATE pingduck_app/lib/features/agent/domain/*.dart, data/*.dart

- **IMPLEMENT**:
  - `AgentPlatform { linux, raspberryPi, nas }` with `title`, `subtitle`, `serverValue` (`linux`/`raspberry_pi`/`nas`), `List<InstallStep> steps` (`InstallStep(text, {command})`), and `const agentImage = 'ghcr.io/big-duck-networks/pingduck-agent:latest'`, `const agentPort = 44480`.
  - `FoundAgent { ip, instanceId, name, version, bool paired, String? agentId }`, `enum AgentAvailability { available, yours, taken }`, `PairedAgent { id, networkId, name, version, lastSeenAt, createdAt }` (`fromRow`).
  - `AgentLanClient { Future<FoundAgent?> info(String ip); Future<PairOutcome> pair(String ip, String code); }`, `HttpAgentLanClient` using `HttpClient` with `connectionTimeout` 3 s and a 12 s overall timeout for `pair` (agent waits up to 10 s on Supabase); validate `app == 'pingduck-agent' && api == 1`; `PairOutcome` = `paired(agentId) | alreadyPaired | invalidCode | busy | upstream | unreachable`.
  - `AgentRepository { Future<String> ensureRemoteNetwork(int localNetworkId, LanInfo lan); Future<({String code, DateTime expiresAt})> createCode(String networkId); Future<List<PairedAgent>> myAgents(); Future<void> revoke(String agentId); Future<String> emailInstructions(AgentPlatform p); Future<int> maxMonitoredNetworks(); }`. `ensureRemoteNetwork`: return the stored `remoteId` if the row still exists (`select id from networks where id = ...`), else `select` by `cidr` + `gateway_ip`, else `insert({cidr, gateway_ip, ssid, name: ssid}).select('id').single()`; store it. `createCode` maps `plan_limit` → `PlanLimitException`, `network not found` → clears `remoteId` and retries once. `myAgents` = `from('agents').select().is_('revoked_at', null).order('created_at', ascending: false)`.
  - Providers: `agentLanClientProvider`, `agentRepositoryProvider`.
- **PATTERN**: `account_auth.dart` (interface + Supabase impl + provider), `scan_quota.dart` (timeouts, typed results).
- **GOTCHA**: uploading SSID/CIDR happens **only** inside `ensureRemoteNetwork`, which only the Activate and Manual Code paths call (decision 2). Don't call it from scans.
- **VALIDATE**: `flutter test test/agent_lan_client_test.dart` (a local `HttpServer.bind('127.0.0.1', 0)` playing the agent: good info, wrong `app`, 409, 400, timeout).
- **SATISFIES**: AC 2, 3, 7

### CREATE pingduck_app/lib/features/agent/application/agent_pairing_controller.dart, agent_status.dart

- **IMPLEMENT**: `AgentPairingController` (Riverpod `Notifier<AgentPairingState>`), sealed state: `Searching`, `Found(List<(FoundAgent, AgentAvailability)>)`, `NoneFound`, `Activating(agent, step)`, `ManualCode(code, expiresAt)`, `Activated(PairedAgent, networkLabel)`, `Failed(PairingFailure)`.
  - `search()`: `bridge.findAgents()` → `lanClient.info(ip)` for each (parallel, dedupe by `instanceId`) → classify against `repo.myAgents()` ids: `!paired` → available, `agentId ∈ mine` → yours, else taken.
  - `activate(agent)`: `ensureRemoteNetwork` → `createCode` → `lanClient.pair(ip, code)` → poll `myAgents()` every 1 s up to 10 s for `agentId` → `Activated`. `invalidCode` → one retry with a new code, then fail.
  - `startManualCode()`: `ensureRemoteNetwork` → `createCode` → poll every 3 s until a new agent for that network appears or `expiresAt`.
  - `PairingFailure { notOnLan, planRequired, accountRequired, takenByOther, agentUnreachable, serverUnreachable, codeRejected }` each with a copy string.
  - `myAgentsProvider` (`FutureProvider`, invalidated after activate/revoke) in `agent_status.dart`.
- **PATTERN**: `scan_controller.dart` (Notifier, bridge via provider, cancellation on dispose).
- **VALIDATE**: `flutter test test/agent_pairing_controller_test.dart` — search classifies available/yours/taken; activate happy path; plan limit → `planRequired`; agent 409 → `takenByOther`; invalid code retries once; agent unreachable; manual code expiry; no `lan` → `notOnLan`; `ensureRemoteNetwork` not called by `search()`.
- **SATISFIES**: AC 2, 3, 5, 7

### CREATE pingduck_app/lib/features/agent/presentation/* (flow screens)

- **IMPLEMENT**: exactly the UI/UX spec above. Strings in the widgets (the app has no l10n layer yet). Every tappable card has `Semantics`. Screens read state only through providers.
- **PATTERN**: `agent_screen.dart` and `account_screen.dart` widget vocabulary; `onboarding_screen.dart` for a full-screen flow page with bottom actions (read it first).
- **GOTCHA**: no new colors or text styles; if a style is missing (e.g. `PdText.headlineLg` / `displayMd`), use the nearest existing one and don't add to the theme in this ticket.
- **VALIDATE**: `flutter test test/agent_flow_widget_test.dart` — intro → (anonymous) pushes SignInScreen; Free plan → Premium required; platform selection changes the steps; copy button writes the command; FIND MY AGENT with a fake bridge showing one available agent → ACTIVATE → Activated screen; TAKEN card not tappable; NO AGENT FOUND → USE A PAIRING CODE shows a code. Then `flutter analyze`.
- **SATISFIES**: AC 2, 3, 5, 6, 10

### UPDATE pingduck_app/lib/features/agent/presentation/agent_screen.dart, tools_screen.dart, account_screen.dart

- **IMPLEMENT**: status panels + Revoke per spec; Tools hub status from `myAgentsProvider`; Account "Monitoring" panel with the nav row.
- **VALIDATE**: widget tests: revoke shows dialog and calls `repo.revoke`; hub shows "1 paired"; Account row opens the intro when no agents and the Homelab Agent tool when there are. `flutter test && flutter analyze`.
- **SATISFIES**: AC 4, 10

### UPDATE docs/ROADMAP.md

- **IMPLEMENT**: Agent pairing row → ✅ with what was tested; Decisions: "Agent daemon language" → **Decided: C++** (libcurl, nlohmann/json); Beta row: note the GHCR image now exists; add the GHCR-public step and port 44480 to the Proxmox guide notes.
- **VALIDATE**: read it.
- **SATISFIES**: AC 11

---

## TESTING STRATEGY

### Unit Tests

- **SQL** (`schema_test.sql`): heartbeat active/revoked/unknown; email account/platform/rate-limit; `email_sends` hidden.
- **C++** (`agent/tests`, plain asserts in the style of `core/tests`): pairing handler outcomes, state round-trip and corrupt-file recovery, M-SEARCH matching, HTTP parsing limits, description XML through the core's own parser (proves the phone will recognise it).
- **Dart**: controller state machine with fakes; LAN client against a loopback `HttpServer`; drift migration v2 → v3 keeps rows (open a v2 DB file, upgrade, read).

### Integration Tests

- `pingduck-vm` (Ubuntu 22.04, Docker): image build, `--version`, CLI smoke, live pair via env var and via `POST /pair` with `curl`, revoke detection.
- Windows dev box: `pingduck ssdp` from the core CLI sees the agent on the LAN.

### Edge Cases

- Two agents on one LAN, one yours and one someone else's → YOURS + TAKEN.
- Agent restarted mid-activation → `agentUnreachable`, retry works, no duplicate `agents` rows (claim is single-use).
- Re-adding an agent to a network that already has one → `claim_pairing_code` revokes the old one (existing behaviour); the old agent's next heartbeat → revoked → unpaired.
- Pairing code expires while the manual-code screen is open → NEW CODE.
- Phone on a guest Wi-Fi / different VLAN → NO AGENT FOUND → manual code works.
- Local `remoteId` points at a deleted remote network (account deleted and recreated) → `network not found` → re-register once.
- Agent name with `<&>` → escaped in XML, intact in the app.
- Port 1900 already taken on the host → agent logs, HTTP + manual code still work.
- Free user tries → Premium required; anonymous user → sign-in first.

---

## VALIDATION COMMANDS

### Level 1: Syntax & Style

- `cd pingduck_app && flutter analyze`
- `cd pingduck_app && dart format --output=none --set-exit-if-changed lib test`
- Agent: compiles with `-Wall -Wextra` clean on `pingduck-vm`.

### Level 2: Unit Tests

- `cd pingduck_app && flutter test`
- `ssh pingduck-vm 'cd pingduck && cmake -S agent -B build-agent -DPINGDUCK_AGENT_TESTS=ON && cmake --build build-agent -j && ctest --test-dir build-agent --output-on-failure'`
- `ssh pingduck-vm 'cd pingduck && bash supabase/tests/run_tests.sh'`
- Core unchanged: `cmake --build build && ctest --test-dir build` (Windows) still green.

### Level 3: Integration Tests

- `ssh pingduck-vm 'cd pingduck && docker build -f agent/Dockerfile -t pingduck-agent . && docker run -d --name pda --net=host --cap-add=NET_RAW --cap-add=NET_ADMIN -v pda:/var/lib/pingduck pingduck-agent'`
- `curl -s http://10.42.0.170:44480/pingduck/v1/info` → `"paired":false`
- `build/pingduck_cli ssdp` (Windows) → a line with vendor `PingDuck`, model `PingDuck Agent`
- `curl -s -X POST -H 'Content-Type: application/json' -d '{"code":"BAD"}' http://10.42.0.170:44480/pingduck/v1/pair` → 400 `bad_code`
- CI: push → `gh run watch` → all jobs green, image on GHCR.

### Level 4: Manual Validation (live project, user + agent)

1. User applies `20261010120000_agent_pairing.sql` in the SQL editor and gives their account Premium:
   `insert into public.entitlements (user_id, plan_code, status, source) select id, 'premium', 'active', 'manual' from auth.users where email = '<their email>' on conflict (user_id) do update set plan_code = 'premium', status = 'active';`
2. Pixel 8 Pro / Chromecast on the test Wi-Fi, signed in: Account → Add monitoring unit → Let's start → Linux → Find my agent → the `pingduck-vm` agent shows AVAILABLE → Activate → Activated.
3. Homelab Agent shows the agent ONLINE, last seen < 1 min; `agents` row has `last_seen_at` moving every ~60 s.
4. `docker restart pda` → stays paired (no code needed).
5. Search again → the agent shows YOURS.
6. Revoke in the app → within 60 s `docker logs pda` says revoked; `/info` → `paired:false`; search → AVAILABLE again.
7. Email me these steps → email arrives with the right platform's steps; 4th try within an hour → "Couldn't send…".
8. Sign out, sign in as a second Premium test account → the agent (re-paired by account 1) shows TAKEN.
9. Free account → Premium required. Anonymous → sign-in prompt.
10. Manual code: on a phone hotspot (agent unreachable) → NO AGENT FOUND → Use a pairing code → `docker run ... -e PINGDUCK_PAIRING_CODE=...` on the VM → app shows Activated.

### Level 5: Additional Validation (Optional)

- Run the `vibe-security` skill on the new migration and `agent/src` (the HTTP listener is new attack surface).
- `docker run --rm -it --net=host nicolaka/netshoot` + `tcpdump -i any udp port 1900` on the VM to watch the SSDP exchange if discovery misbehaves.

---

## ACCEPTANCE CRITERIA

- [ ] 1. `pingduck-agent` builds in the Docker image, starts unpaired, answers SSDP and serves `description.xml` and `/pingduck/v1/info` on port 44480.
- [ ] 2. On the test LAN, the app's Find my agent lists the `pingduck-vm` agent within 6 s, without using a daily scan and without uploading anything before Activate.
- [ ] 3. One tap on Activate pairs it: an `agents` row exists for the user's network, the agent's state file holds the token, and the token never appears in any LAN response or log.
- [ ] 4. The Homelab Agent screen shows name, ONLINE/OFFLINE from `last_seen_at`, version, and Revoke; revoking unpairs the agent within 60 s and the old token fails `agent_sync` and `agent_heartbeat`.
- [ ] 5. Free accounts see Premium required; anonymous users are sent to sign in first; `plan_limit` from the server shows the same Premium screen.
- [ ] 6. Email me these steps sends the selected platform's instructions to the account address; more than 3 in an hour is refused.
- [ ] 7. A paired agent refuses `/pair` with 409, and the app shows it as TAKEN to other accounts.
- [ ] 8. CI publishes `ghcr.io/big-duck-networks/pingduck-agent` for amd64 and arm64 on pushes to main; the existing agent smoke test still passes.
- [ ] 9. `schema_test.sql` passes with the new checks; all existing SQL, core, plugin and app tests still pass.
- [ ] 10. Screens 1-5 follow Fing's flow and structure, built only from existing PingDuck widgets and tokens; widget tests cover each state.
- [ ] 11. ROADMAP updated (pairing ✅, daemon language decided, GHCR note).

---

## COMPLETION CHECKLIST

- [ ] All tasks completed in order
- [ ] Each task validation passed immediately
- [ ] All validation commands executed successfully
- [ ] Full test suite passes (unit + integration)
- [ ] No linting or type checking errors
- [ ] Manual testing confirms feature works
- [ ] Acceptance criteria all met
- [ ] Code reviewed for quality and maintainability

---

## OPEN QUESTIONS / ASSUMPTIONS

- Assumed (decision 7, user moved on without objecting) — anyone on the LAN who reaches an **unpaired** agent first can claim it, like Fing; a paired agent refuses until revoked or its volume is wiped; the app shows TAKEN. Confirm before execution.
- Assumed (decision 8) — port **44480**, not Fing's 44444. Confirm.
- Assumed (decision 9) — `PINGDUCK_PAIRING_CODE` manual fallback is kept and reachable from NO AGENT FOUND. Confirm.
- Assumed (decision 2) — the network's CIDR, gateway and SSID go to Supabase only when the person taps Activate / Use a pairing code.
- Assumed (decision 4) — an email account is required; anonymous users are sent to sign in.
- Assumed — on screen 3 the primary is **FIND MY AGENT** and email is secondary (Fing has email as primary). One-word swap if the user wants it identical.
- Assumed — the activated screen's copy ("is on watch") describes the finished feature; until the Agent daemon ticket lands, a paired agent heartbeats but reports no devices. Ship both tickets together before any beta.
- Needs the user — making the GHCR package public once (org package settings); applying the migration on the live project; the manual entitlement SQL for testing; a second test account for the TAKEN check.
- Open — the LAN HTTP is plain HTTP. The pairing code crosses it (8 chars, 10-minute life, single use); someone sniffing the Wi-Fi in that window could redeem it first and register a rogue agent on the victim's network (it could write fake devices but can't read anything). Accepted for parity with Fing; revisit with the security audit.

## NOTES (open canvas)

**Why SSDP, not mDNS.** Fing's agent advertises over UPnP. More importantly, the core's `pd_ssdp_discover` already sends `ssdp:all`, fetches LOCATION from the responder only, parses `manufacturer`/`modelName`/`deviceType`, and is fuzzed. Advertising over SSDP means zero core changes and the agent also shows up (with its name and "PingDuck Agent" model) in normal scans, which is a nice touch. mDNS would need a new TXT-record path in the app.

**Why the phone pushes the code instead of the agent pulling a claim.** Alternative: the agent creates a "claim secret" and the phone redeems it with a new `claim_agent(secret)` RPC. Same LAN trust model, but it needs a new server RPC and lets the agent exist server-side before an owner does. Pushing the existing short-lived code reuses tested RPCs and keeps the token only between agent and Supabase.

**Why heartbeat now.** Without it the agent can't learn it was revoked until the daemon's first `agent_sync` fails, and the app would have no `last_seen_at` for the status chip. The daemon ticket will call `agent_sync` instead on scan ticks and can keep heartbeat for idle periods.

**Why no instance-status RPC.** The agent's `/info` returns its `agent_id`; the app compares it to its own `agents` rows (RLS). "Taken" needs no server lookup, so nothing new is exposed about other people's agents.

**Sequencing risk.** QEMU arm64 builds can push CI over its timeout; if so, switch to the `ubuntu-24.04-arm` runner for the arm64 leg and merge manifests (`docker buildx imagetools create`).

**Confidence.** 7/10 for one pass. The SSDP-on-multi-homed-host and Android multicast details are the likeliest to need a second round on real hardware; everything else follows existing patterns.

## AMENDMENTS

- 2026-10-10 — Built. Changes from the plan: `POST /pair` returns `agent_id` and the app confirms by that id rather than by network/name; `AgentLanClient.pair` returns a `PairResult` record. `agent/` builds as its own CMake project with a `pingduck_agent_lib` static library shared by the binary and `agent_tests`; the image also runs the agent tests during `docker build`. The Account tab row says "Monitoring units" and opens the Homelab Agent tool once agents exist. Each new snackbar replaces the current one (copy then email queued them 4 s apart).
- 2026-10-10 — Not yet run: `supabase/tests/run_tests.sh` and the Docker build (the Linux VM's SSH timed out all session). The agent was compile-checked with the NDK's clang and its 20 unit tests ran on a Pixel 8 Pro (Android/bionic, so no libcurl or live SSDP there).
