# Feature: Phase 5 subscriptions (RevenueCat, Android first)

The following plan should be complete, but its important that you validate documentation and codebase patterns and task sanity before you start implementing.

Pay special attention to naming of existing utils types and models. Import from the right files etc.

## Feature Description

Sell PingDuck **Premium** as an auto-renewing Google Play subscription through **RevenueCat**, and make Supabase the only authority on who has it:

1. **Store and RevenueCat setup** (user steps): a Play subscription `premium` with base plans `monthly` and `annual`, both with a 7-day free trial; a RevenueCat entitlement `premium` and offering `default`.
2. **Server:** a new Edge Function `revenuecat-webhook`. On any RevenueCat event it re-reads the subscriber from RevenueCat's REST API and writes `public.entitlements` (`source = 'revenuecat'`). `plan_for()` / `my_plan()` / `claim_scan` already read that table, so agent pairing, sync, alerts and the scan quota follow automatically.
3. **App:** `purchases_flutter` on Android, identified by the Supabase user id. A paywall in the design system, a Plan panel on the Account tab (state, renewal, Manage subscription, Restore purchases), the existing upgrade points wired to the paywall, a warning before Delete account while subscribed, and the plan read directly from `my_plan()` so Premium appears seconds after purchase.
4. **Docs:** privacy policy names RevenueCat; roadmap decisions updated.

## User Story

As a homelab owner using PingDuck Free
I want to start a Premium trial from inside the app and see my plan, renewal date and a way to manage or restore it
So that I can unlock monitoring, alerts and unlimited scans, and keep them on any phone I sign in on

## Problem Statement

Premium exists in the schema (`plans`, `entitlements`, `plan_for`) but nothing can grant it except a manual SQL insert. The app has upgrade points that lead nowhere ("Subscriptions coming soon" in `add_unit_intro_screen.dart:147`), and it only learns its plan from the next `claim_scan` answer (`scan_quota.dart:73-78`), so even a working purchase would look like nothing happened until the next scan.

## Solution Statement

- **Identity:** RevenueCat `appUserID` = Supabase `auth.uid()`. **Buying requires an email account** (decision 1): an anonymous user is sent to sign-up first. On sign-in/sign-up the app calls `Purchases.logIn(uid)`; on sign-out `Purchases.logOut()`. RevenueCat's default transfer behaviour ("transfer to new App User ID") handles a Play account restoring onto another PingDuck account; the webhook re-syncs both sides.
- **Server is authoritative:** the webhook never trusts the event body's state. It collects every PingDuck user id the event mentions (`app_user_id`, `original_app_user_id`, `aliases`, `transferred_from`, `transferred_to`; UUIDs only, so `$RCAnonymousID:…` is skipped), calls `GET https://api.revenuecat.com/v1/subscribers/{id}` with the secret key, maps entitlement `premium` to an `entitlements` row, and upserts it. Re-reading makes duplicates and out-of-order delivery harmless. Rows with `source = 'manual'` are never overwritten (test accounts, comps).
- **App reads the plan from the server:** a `PlanRepository` calls `my_plan()`; `currentPlanProvider` refreshes on launch, resume, auth change and after purchase/restore (polling every 2 s for up to 30 s until the webhook lands). The SDK's `CustomerInfo` is only used for display (renewal date, will-renew, trial), never for gating.
- **Paywall:** custom screen (decision 4), one entitlement, two packages (annual pre-selected), trial terms, Restore, Terms and Privacy links.

## Out of Scope / Non-Goals

- **iOS / App Store.** No App Store Connect products, no StoreKit config, no `appl_` key. `purchases_flutter` is only configured on Android; every call is behind `billingSupported`. The design keeps iOS a config-only addition later.
- **Pro tier.** Stays in `plans`; not sold (decision 2). No upgrade/downgrade between tiers.
- **Windows / desktop purchases.** The desktop app shows the plan (it reads `my_plan()`), never sells.
- **RevenueCat Paywalls / `purchases_ui_flutter`.** Not used, so `MainActivity` stays `FlutterActivity`.
- **Web checkout / Stripe.** Not allowed for in-app digital goods.
- **Promo codes, family sharing, win-back offers, price experiments.** Later.
- **Server-side enforcement changes.** `plan_for` and every RPC that checks the plan stay as they are.
- **Play Console automation.** Products are created by hand; CI still never uploads to Play (see memory/plan `ci-cd-overhaul.md` Task 17).
- Not changing: `claim_scan`, the `plans` rows, RLS on `entitlements` (select own, writes service role only).

## Feature Metadata

**Feature Type**: New Capability
**Estimated Complexity**: High
**Primary Systems Affected**: `supabase/functions` (new `revenuecat-webhook`, shared secret helper), `pingduck_app` (billing service, plan provider, paywall, Account, Settings, agent flow, overview banner), `docs/ROADMAP.md`, `pingduck_website` (privacy policy)
**Dependencies**: `purchases_flutter` ^10.15.2 (app); RevenueCat project (user has an account); Google Play Console subscription + payments profile (user); Supabase Edge Functions

## Related Work

**Implements**: `docs/ROADMAP.md` Phase 5 rows "Billing integration", "Server-side entitlements", "Paywall and upgrade points", "Account tab: subscription state", "Legal", "Store setup", "Tests" (Android half). Exit (Android half): a sandbox user subscribes on Android, Premium unlocks within a minute, cancelling/refunding revokes it on the server.

**Back-references**:
- `.claude/plans/phase-4-sync-and-alerts.md` — Edge Function + secret-header pattern (`notify-new-devices`), Settings "Premium plan required" rows.
- `.claude/plans/ci-cd-overhaul.md` — signed AAB artifacts from `main` (Task 17); Play uploads stay manual.
- PR #20 — Premium only from the server; nothing on the device may grant it.

**Forward-references**: (none yet; iOS billing will extend this)

---

## DECISIONS (planning conversation, 2026-10-12)

| # | Decision |
|---|---|
| 1 | An **email account is required to subscribe**. Anonymous users are routed to sign-up first. |
| 2 | **Premium only** at launch. Pro stays in `plans`, unsold. |
| 3 | Prices: **$4.99/month, $34.99/year**, **7-day free trial on both**. (Fing: $7.99 / $69.99.) |
| 4 | **Custom paywall** in the design system, not RevenueCat Paywalls. |
| 5 | **Delete account warns** when a store subscription is active and links to Play's subscription page; deleting does not cancel billing. |
| 6 | **Free users may turn Auto-scan on launch off (and on)**; the 30-minute limit on Free automatic scans stays (`ServerScanQuota.automaticInterval`). Closes the roadmap's "Free launch scan" decision. |
| 7 | RevenueCat account already exists; setup starts from the user's project. |
| 8 | Phase 6 is post-launch; Phase 5 + Phase 8 gate launch (roadmap "Launch scope" to be corrected). |

---

## CONTEXT REFERENCES

### Relevant Codebase Files IMPORTANT: YOU MUST READ THESE FILES BEFORE IMPLEMENTING!

Database
- `supabase/migrations/20261006120000_initial_schema.sql` (lines 15-65) — `plans`, `entitlements` (status `active|trialing|grace|expired|revoked`, `source revenuecat|manual`), `plan_for`, `my_plan`. Lines 400-445: RLS (`entitlements_own` select-only) and the revoke of writes.
- `supabase/tests/schema_test.sql` — how plan rules are tested (rolled-back transaction, `expect_error`).
- `supabase/tests/run_tests.sh` — the throwaway-Postgres runner CI uses.

Edge Functions
- `supabase/functions/notify-new-devices/index.ts` — Deno.serve shape, `reply()`, secret-header check, service-role client from injected `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`, header comment listing secrets and `--no-verify-jwt`.
- `supabase/functions/notify-new-devices/fcm.ts` — pure helpers split out for tests; `sameSecret` (constant-time compare) to move to `_shared`.
- `supabase/functions/notify-new-devices/fcm_test.ts` — `jsr:@std/assert@1` test style.
- `.github/workflows/database.yml` (Edge Functions step) — runs `deno check */index.ts` and `deno test` in `supabase/functions`.

App
- `pingduck_app/lib/main.dart` (lines 30-40 init; 95-115 launch auto-scan) — init order (`Supabase.initialize`, `initPushAlerts`), where to configure billing.
- `pingduck_app/lib/services/push_alerts.dart` (lines 40, 181-267) — platform guard (`alertsSupported`), `abstract interface class` + concrete impl + `Provider`/`FutureProvider` pattern to mirror for billing.
- `pingduck_app/lib/services/scan_quota.dart` (lines 73-78, 120-140) — `isPremiumKey` cache and `isPremiumUser`; keep the cache, now also written from `my_plan()`.
- `pingduck_app/lib/features/auth/session.dart` — anonymous sign-in (`signedInClient`).
- `pingduck_app/lib/features/auth/account_auth.dart` (lines 11-101) — `AccountAuth` interface, `emailChanges()`, `accountEmailProvider`; `email == null` means anonymous.
- `pingduck_app/lib/features/auth/sign_in_screen.dart` — the sign-up/sign-in screen the paywall routes anonymous users to.
- `pingduck_app/lib/features/account/presentation/account_screen.dart` (lines 45-125 panels, 154-230 `_IdentityPanel`, 329+ `_NavRow`) — where the Plan panel goes and the row widget to reuse.
- `pingduck_app/lib/features/settings/presentation/settings_screen.dart` (lines 34-37 `isPremiumProvider`; 140-175 Auto-scan row; 296+ `confirmDeleteAccount`; 335-350 alerts blocker) — premium gating to rewire.
- `pingduck_app/lib/features/agent/presentation/add_unit_intro_screen.dart` (lines 124-150) — `PremiumRequiredScreen` with the "Subscriptions coming soon" button.
- `pingduck_app/lib/features/scanner/presentation/overview_screen.dart` (lines 377-400) — quota banner "or go Premium for unlimited scans".
- `pingduck_app/lib/core/widgets/pd_widgets.dart` — `PdPanel`, `PdChip`, `PdButton`, `PdField`, `PdTone`, `PdText`; the only widgets the paywall may use.
- `pingduck_app/lib/core/constants/supabase_config.dart` — where public client keys live (mirror for the RevenueCat Android public key).
- `pingduck_app/test/fakes.dart` — fakes for every service (`FakeAuth`, `FakePushAlerts`…); add `FakeBilling`, `FakePlanRepository`.
- `pingduck_app/test/settings_cloud_rows_test.dart` — widget-test pattern with provider overrides.
- `pingduck_app/android/app/src/main/AndroidManifest.xml` (line 19) — `launchMode="singleTop"` already satisfies RevenueCat's requirement.

### New Files to Create

- `supabase/functions/_shared/secret.ts` — `sameSecret` moved here (both functions import it).
- `supabase/functions/revenuecat-webhook/index.ts` — the webhook.
- `supabase/functions/revenuecat-webhook/entitlement.ts` — pure helpers: `userIdsIn(event)`, `entitlementRow(subscriber, now)`.
- `supabase/functions/revenuecat-webhook/entitlement_test.ts` — Deno tests.
- `pingduck_app/lib/core/constants/revenuecat_config.dart` — `revenueCatAndroidKey` (public `goog_…` key), `premiumEntitlement = 'premium'`.
- `pingduck_app/lib/services/plan.dart` — `Plan` model, `PlanRepository` (`my_plan()`), `currentPlanProvider`.
- `pingduck_app/lib/services/billing.dart` — `Billing` interface, `RevenueCatBilling`, `billingProvider`, `billingSupported`.
- `pingduck_app/lib/features/subscription/presentation/paywall_screen.dart` — paywall + `openPaywall(context, ref)`.
- `pingduck_app/lib/features/subscription/presentation/plan_panel.dart` — Account tab Plan panel.
- `pingduck_app/test/plan_test.dart`, `pingduck_app/test/paywall_test.dart`, `pingduck_app/test/plan_panel_test.dart`.

### Relevant Documentation YOU SHOULD READ THESE BEFORE IMPLEMENTING!

- [RevenueCat webhooks](https://www.revenuecat.com/docs/integrations/webhooks) — Authorization header set in the dashboard; retries 5x (5/10/20/40/80 min) on non-200; at-least-once delivery; **recommended: call `GET /subscribers` after any webhook** instead of handling each event type.
- [RevenueCat webhook event types & fields](https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields) — `event.type`, `app_user_id`, `original_app_user_id`, `aliases`, `transferred_from`, `transferred_to`, `environment`, `id`.
- [RevenueCat REST API v1: GET subscriber](https://www.revenuecat.com/docs/api-v1#tag/customers/operation/subscribers) — `Authorization: Bearer <secret key>`, URL-encode the id; `subscriber.entitlements.<id>.{expires_date, grace_period_expires_date, product_identifier}`, `subscriber.subscriptions.<product>.{period_type, unsubscribe_detected_at, billing_issues_detected_at, is_sandbox, store}`.
- [purchases_flutter](https://pub.dev/packages/purchases_flutter) (10.15.2) — `Purchases.configure(PurchasesConfiguration(key)..appUserID = uid)`, `logIn`, `logOut`, `getOfferings`, `purchasePackage`, `restorePurchases`, `getCustomerInfo`, `addCustomerInfoUpdateListener`, `CustomerInfo.managementURL`; `PlatformException` with `PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError` for user cancel.
- [RevenueCat Flutter install](https://www.revenuecat.com/docs/getting-started/installation/flutter) — `launchMode` `standard`/`singleTop` (already `singleTop`); `FlutterFragmentActivity` only for RevenueCat Paywalls (not used).
- [Restore behaviour / transfer](https://www.revenuecat.com/docs/projects/restore-behavior) — keep the default "Transfer to new App User ID".
- [Google Play: create subscriptions](https://support.google.com/googleplay/android-developer/answer/140504) and [base plans and offers](https://support.google.com/googleplay/android-developer/answer/12154973) — one subscription, two base plans, a free-trial offer per base plan.
- [RevenueCat: Google Play service credentials](https://www.revenuecat.com/docs/service-credentials/creating-play-service-credentials) and [Play RTDN](https://www.revenuecat.com/docs/platform-resources/server-notifications/google-server-notifications).
- [Google Play: license testing](https://developer.android.com/google/play/billing/test) — testers buy with test cards; subscriptions renew every 5 minutes (monthly) and trials are shortened.

### Patterns to Follow

**Platform guard** (`push_alerts.dart:40`):
```dart
bool get alertsSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
```
Mirror as `bool get billingSupported => …android;` Use `defaultTargetPlatform`, not `dart:io Platform`, so widget tests can override it.

**Service shape** (`push_alerts.dart:181-267`): `abstract interface class PushAlerts {…}`, `class FcmPushAlerts implements PushAlerts`, `final pushAlertsProvider = Provider<PushAlerts>((ref) => FcmPushAlerts(...))`. Tests override the provider with a fake from `test/fakes.dart`.

**Edge Function** (`notify-new-devices/index.ts`): header comment naming secrets and `--no-verify-jwt`; `reply(status, body)`; reject non-POST 405, bad secret 401; service-role `createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)`. Pure logic in a sibling module with `_test.ts`.

**Never trust the device** (PR #20, `scan_quota.dart` doc comment on `isPremiumUser`): only server answers write `isPremiumKey`. The SDK's `CustomerInfo` must not gate anything.

**Toasts for server results** (sign-in screen since #20): errors in red, confirmations neutral. Reuse the same helper the sign-in screen uses for purchase errors and "Premium is active".

**Comment density:** short doc comments on public members explaining *why*, as in `scan_quota.dart`. No banner comments.

---

## IMPLEMENTATION PLAN

### Phase 0: Store and RevenueCat setup (user, guided)

**Independent of:** Phases 1-2 (code can be written and unit-tested before products exist). **Blocks:** Phase 4's live tests.

### Phase 1: Server entitlements

Shared secret helper, webhook function, its tests. Tasks 2-5.

### Phase 2: App plumbing

**Independent of:** Phase 1 (talks to `my_plan()`, which exists).

Plan repository and provider, billing service, identity wiring. Tasks 6-10.

### Phase 3: UI

**Depends on:** Phase 2.

Paywall, Plan panel, upgrade points, delete-account warning, Free auto-scan switch. Tasks 11-16.

### Phase 4: Docs, deploy, live tests

**Depends on:** Phases 0-3.

Roadmap, privacy policy, deploy (user runs), license-tester purchase. Tasks 17-21.

---

## STEP-BY-STEP TASKS

IMPORTANT: Execute every task in order, top to bottom. Each task is atomic and independently testable.

### Task 1: SETUP Play Console and RevenueCat (user checklist; agent guides one item at a time)

- **IMPLEMENT** (record each as done):
  1. **Play payments profile:** Play Console › Setup › Payments profile linked (merchant account). Needed before any paid product.
  2. **A build with Billing on a testing track:** Play only lets you create subscriptions once an AAB that declares `com.android.vending.BILLING` has been uploaded. `purchases_flutter` adds that permission, so this needs **Task 9 merged first**: download the `pingduck-1.0.0+<count>` artifact from that `main` run and upload it to **Internal testing** by hand.
  3. **Subscription:** Monetize › Subscriptions › Create `premium` ("PingDuck Premium"). Base plans: `monthly` (auto-renewing, 1 month, **$4.99**) and `annual` (1 year, **$34.99**); let Play convert prices for other countries. On each base plan, add an offer: **free trial, 7 days, new customers only**. Activate.
  4. **License testers:** Setup › License testing: add the Google account on the Pixel; set response to `RESPOND_NORMALLY`. Join the internal test from the Pixel with the same account.
  5. **RevenueCat service credentials:** follow RevenueCat's "Creating Play Service Credentials": a Google Cloud service account with the Pub/Sub + Android Publisher APIs, invited in Play Console with *View financial data* and *Manage orders and subscriptions*. Upload its JSON in RevenueCat › Project › Apps › Google Play app (`app.webcap.pingduck`). (Separate from the CI `PLAY_SERVICE_ACCOUNT_JSON`.) Credentials can take up to 36 h to work.
  6. **RTDN:** in the RevenueCat Play app, enable Google real-time developer notifications (RevenueCat creates the Pub/Sub topic); paste the topic in Play Console › Monetize › Monetization setup.
  7. **RevenueCat catalog:** import the products (`premium:monthly`, `premium:annual`); entitlement **`premium`** attached to both; offering **`default`** (current) with packages `$rc_monthly` → `premium:monthly`, `$rc_annual` → `premium:annual`.
  8. **Keys:** copy the **public Android SDK key** (`goog_…`) for Task 6 (it's public, like the Supabase publishable key; fine to paste). The **secret API key** (`sk_…`, v1) goes only into Supabase in Task 18; do **not** paste it into chat.
  9. **Restore behaviour:** Project settings › leave "Transfer to new App User ID".
- **GOTCHA**: Never ask the user to paste `sk_` keys or the webhook auth value into chat; they set them with the Supabase dashboard (Edge Functions › Secrets). Auto mode blocks the agent from writing secrets anyway.
- **VALIDATE**: RevenueCat dashboard shows the Play app "Valid credentials", offering `default` with two packages, entitlement `premium` with two products.
- **SATISFIES**: AC 1, AC 9.

### Task 2: CREATE `supabase/functions/_shared/secret.ts` and UPDATE `notify-new-devices`

- **IMPLEMENT**: Move `sameSecret` (and only it) from `notify-new-devices/fcm.ts` into `_shared/secret.ts`. In `fcm.ts`, `export { sameSecret } from "../_shared/secret.ts";` so `fcm_test.ts` and `index.ts` keep working unchanged.
- **PATTERN**: Supabase convention for shared code in `supabase/functions/_shared/`.
- **GOTCHA**: `database.yml` runs `deno check */index.ts`; `_shared` has no `index.ts`, so it is checked through its importers. Deploying `notify-new-devices` later must still bundle (relative imports into `_shared` are supported by the bundler).
- **VALIDATE**: `cd supabase/functions && deno check */index.ts && deno test`
- **SATISFIES**: AC 2.

### Task 3: CREATE `supabase/functions/revenuecat-webhook/entitlement.ts`

- **IMPLEMENT**:
  - `export const ENTITLEMENT = "premium"; export const PLAN = "premium";`
  - `export function userIdsIn(event: Record<string, unknown>): string[]` — union of `app_user_id`, `original_app_user_id`, `aliases[]`, `transferred_from[]`, `transferred_to[]`; keep only strings matching a UUID regex (lower-cased), dedupe.
  - `export type Row = { plan_code: string; status: "active" | "trialing" | "grace" | "expired"; period_ends_at: string | null }`
  - `export function entitlementRow(subscriber: Subscriber, now: Date): Row | null`:
    - `e = subscriber.entitlements?.[ENTITLEMENT]`; none → `null` (no entitlement ever: caller leaves the user on Free / marks an existing revenuecat row expired).
    - `expires = e.expires_date ? new Date(...) : null`; `grace = e.grace_period_expires_date ? new Date(...) : null`.
    - `expires === null` → `{active, null}` (non-expiring; not sold today but handle it).
    - `expires > now` → status `trialing` if `subscriber.subscriptions?.[e.product_identifier]?.period_type === "trial"` else `active`; `period_ends_at = expires`.
    - else `grace && grace > now` → `{grace, grace}`.
    - else `{expired, expires}`.
  - Minimal `Subscriber` type for the fields used.
- **PATTERN**: `notify-new-devices/fcm.ts` (pure, exported, no I/O).
- **GOTCHA**: `plan_for` already treats `period_ends_at <= now()` as Free, so `expired` rows need no cron. RevenueCat's Play `product_identifier` looks like `premium:monthly`; look it up in `subscriptions` by that exact key.
- **VALIDATE**: `cd supabase/functions && deno check revenuecat-webhook/entitlement.ts`
- **SATISFIES**: AC 3.

### Task 4: CREATE `supabase/functions/revenuecat-webhook/entitlement_test.ts`

- **IMPLEMENT** tests (`jsr:@std/assert@1`):
  1. `userIdsIn` keeps UUIDs from all five fields, lower-cases, dedupes, drops `$RCAnonymousID:abc`.
  2. Trial: expires in future + `period_type: "trial"` → `trialing`.
  3. Normal: future expiry + `period_type: "normal"` → `active`, `period_ends_at` = expiry ISO.
  4. Grace: expiry past, grace future → `grace`, ends at grace.
  5. Expired: both past → `expired`.
  6. No `premium` entitlement → `null`.
  7. Non-expiring (`expires_date: null`) → `active`, `null`.
- **PATTERN**: `notify-new-devices/fcm_test.ts`.
- **VALIDATE**: `cd supabase/functions && deno test revenuecat-webhook/`
- **SATISFIES**: AC 3.

### Task 5: CREATE `supabase/functions/revenuecat-webhook/index.ts`

- **IMPLEMENT**:
  - Header comment: purpose; secrets `REVENUECAT_WEBHOOK_AUTH` (the exact Authorization header value set in RevenueCat) and `REVENUECAT_SECRET_KEY` (v1 secret key); injected `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`; **deploy with `--no-verify-jwt`**.
  - `Deno.serve`: non-POST → 405. `sameSecret(req.headers.get("authorization"), Deno.env.get("REVENUECAT_WEBHOOK_AUTH"))` false → 401. Parse JSON; `event = body.event`; missing → 400.
  - `ids = userIdsIn(event)`; for each id:
    1. `GET https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(id)}` with `Authorization: Bearer ${REVENUECAT_SECRET_KEY}`. Non-2xx → throw (→ 500 so RevenueCat retries).
    2. `row = entitlementRow(json.subscriber, new Date())`.
    3. Read the existing row: `select source, status from entitlements where user_id = id`. If `source === "manual"` → skip (log). If `row === null` and no existing row → skip. If `row === null` and an existing revenuecat row → write `status: "expired"` with its current `period_ends_at`.
    4. Upsert `{ user_id: id, plan_code: PLAN, ...row, source: "revenuecat", updated_at: new Date().toISOString() }` on `user_id`.
    5. A foreign-key error (`23503`: id not in `auth.users`, e.g. a deleted account) → log and skip, not 500.
  - Log one line per event: `event.type`, `event.environment`, ids written, ids skipped. Never log the secret key or the whole body.
  - Respond 200 `{ ok: true, written: [...], skipped: [...] }`.
- **PATTERN**: `notify-new-devices/index.ts` (`reply`, secret check, client creation).
- **IMPORTS**: `createClient` from `npm:@supabase/supabase-js@2`; `sameSecret` from `../_shared/secret.ts`; helpers from `./entitlement.ts`.
- **GOTCHA**:
  - RevenueCat sends `Authorization` exactly as configured (e.g. `Bearer <random>`); compare the full header string.
  - Sandbox (license tester) events must grant Premium, or Task 21 can't pass. Log `environment`; don't filter on it.
  - `GET /subscribers` creates an empty subscriber if the id is unknown; harmless (returns no entitlements → skip).
  - Don't branch on `event.type`; re-reading covers every type, including `TRANSFER` (both sides are in the id list) and `TEST` (RevenueCat's dashboard test event, whose fake id yields `null` → skip).
- **VALIDATE**: `cd supabase/functions && deno check */index.ts && deno test`
- **SATISFIES**: AC 2, AC 3, AC 4.

### Task 6: CREATE `pingduck_app/lib/core/constants/revenuecat_config.dart`

- **IMPLEMENT**: `const revenueCatAndroidKey = 'goog_…';` (from Task 1.8; until then a `'goog_REPLACE_ME'` placeholder that makes `RevenueCatBilling.configure` a no-op with a debug print), `const premiumEntitlement = 'premium';`, `const playSubscriptionsUrl = 'https://play.google.com/store/account/subscriptions?package=app.webcap.pingduck';`.
- **PATTERN**: `lib/core/constants/supabase_config.dart` (public key committed, with a comment saying it's public).
- **VALIDATE**: `cd pingduck_app && flutter analyze lib/core/constants`
- **SATISFIES**: AC 5.

### Task 7: CREATE `pingduck_app/lib/services/plan.dart`

- **IMPLEMENT**:
  - `class Plan { code, name, dailyScanLimit (int?), maxMonitoredNetworks, notifications, …; bool get isPaid => code != 'free'; static const free = Plan(...) }` with `factory Plan.fromRow(Map<String, dynamic>)` matching `plans` columns.
  - `abstract interface class PlanRepository { Future<Plan> myPlan(); }`; `SupabasePlanRepository` calls `(await signedInClient()).rpc('my_plan')` (returns one row; handle both `Map` and single-element `List` shapes), and writes `isPremiumKey` (`'1'`/`'0'`) via `LocalStore` so offline launches and `isPremiumUser` agree.
  - `class CurrentPlan extends AsyncNotifier<Plan>`: `build()` fetches; on error falls back to the cached `isPremiumUser` (Premium → a `Plan` with code `premium` from constants, else `Plan.free`). `Future<void> refresh()`. `Future<bool> waitForPaid({Duration timeout = 30s, Duration every = 2s})` polls `myPlan()` until `isPaid` or timeout, updating state.
  - `final planRepositoryProvider = Provider<PlanRepository>(...)`, `final currentPlanProvider = AsyncNotifierProvider<CurrentPlan, Plan>(CurrentPlan.new)`.
  - Rebuild on auth change: `ref.listen(accountEmailProvider, (_, __) => refresh())` inside `build`.
- **PATTERN**: providers in `push_alerts.dart:265-267`; Supabase calls via `signedInClient()` (`session.dart`).
- **GOTCHA**: `my_plan()` returns a composite row; `supabase_flutter` returns it as a `Map` for a scalar composite function. Test both shapes in the fake/unit test.
- **VALIDATE**: `cd pingduck_app && flutter analyze && flutter test test/plan_test.dart`
- **SATISFIES**: AC 6.

### Task 8: UPDATE `isPremiumProvider` and refresh points

- **IMPLEMENT**:
  - `settings_screen.dart:34-37`: `isPremiumProvider` becomes `Provider<AsyncValue<bool>>`-free: `final isPremiumProvider = FutureProvider<bool>((ref) async => (await ref.watch(currentPlanProvider.future)).isPaid);` (keep the name so the existing call sites and tests keep compiling).
  - `main.dart` lifecycle observer: on `AppLifecycleState.resumed`, `ref.read(currentPlanProvider.notifier).refresh()` (next to the existing sync refresh).
- **GOTCHA**: existing tests override `isPremiumProvider`; keep that override working.
- **VALIDATE**: `cd pingduck_app && flutter test`
- **SATISFIES**: AC 6.

### Task 9: ADD `purchases_flutter` and CREATE `pingduck_app/lib/services/billing.dart`

- **IMPLEMENT**:
  - `flutter pub add purchases_flutter:^10.15.2`.
  - `bool get billingSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;`
  - Domain types (no SDK types leak out): `class PlanOffer { id, title, priceString, periodLabel ('month'/'year'), trialDays (int?), savingsPercent (int?) ; Object raw }`; `class SubscriptionDetails { bool active; bool willRenew; DateTime? expiresAt; bool inTrial; bool billingIssue; String? manageUrl }`; `enum PurchaseOutcome { purchased, cancelled, pending }`; `class BillingException(String message)`.
  - `abstract interface class Billing { Future<void> configure(String? userId); Future<void> identify(String? userId); Future<List<PlanOffer>> offers(); Future<PurchaseOutcome> buy(PlanOffer offer); Future<void> restore(); Future<SubscriptionDetails?> details(); }`.
  - `RevenueCatBilling`: `configure` → `Purchases.configure(PurchasesConfiguration(revenueCatAndroidKey)..appUserID = userId)` once; `identify(id)` → `id == null ? (if !await Purchases.isAnonymous) Purchases.logOut() : Purchases.logIn(id)`; `offers()` from `getOfferings().current` packages `$rc_annual` then `$rc_monthly`, trial from `storeProduct.defaultOption?.freePhase` (Play free-trial phase; days from its `billingPeriod`), `savingsPercent` = round(100·(1 − annual/(12·monthly))); `buy` → `Purchases.purchasePackage(raw)`, cancel error → `cancelled`, `paymentPendingError` → `pending`, others → `BillingException(friendly message)`; `restore` → `restorePurchases()`; `details` → `getCustomerInfo()` → `entitlements.all[premiumEntitlement]` (`isActive`, `willRenew`, `expirationDate`, `periodType == PeriodType.trial`, `billingIssueDetectedAt != null`), `managementURL ?? playSubscriptionsUrl`.
  - Every method returns early / empty when `!billingSupported`.
  - `final billingProvider = Provider<Billing>((ref) => RevenueCatBilling());`
- **PATTERN**: `push_alerts.dart` interface + impl + provider.
- **GOTCHA**:
  - `Purchases.logOut()` throws when the current RevenueCat user is already anonymous; check `Purchases.isAnonymous` first.
  - This is what adds `com.android.vending.BILLING` to the merged manifest; Task 1.2 needs this merged.
  - Windows build: `purchases_flutter` has no Windows implementation. Guard every call so no method channel is hit on Windows; `flutter build windows` must still compile (pub plugin registration on Windows ignores Android-only plugins).
- **VALIDATE**: `cd pingduck_app && flutter analyze && flutter test && flutter build apk --debug` then `grep -c "com.android.vending.BILLING" build/app/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml` ≥ 1 (path may differ by AGP version; search `build/app/intermediates` for the merged manifest).
- **SATISFIES**: AC 5, AC 9.

### Task 10: ADD billing identity wiring in `main.dart`

- **IMPLEMENT**: after `Supabase.initialize` and `initPushAlerts()`: `final user = Supabase.instance.client.auth.currentUser; await RevenueCatBilling().configure(user == null || user.isAnonymous ? null : user.id);` (wrap in try/catch; billing never blocks launch). In the root widget's `initState`, `ref.listenManual(accountEmailProvider, (_, next) => ref.read(billingProvider).identify(next.value == null ? null : Supabase.instance.client.auth.currentUser?.id));`.
- **PATTERN**: `initPushAlerts()` call at `main.dart:35`; `ref.read(pushAlertsProvider).listen(...)` at line 98.
- **GOTCHA**: The anonymous Supabase user must never be logged in to RevenueCat (decision 1). If RevenueCat already has an anonymous `$RCAnonymousID` with a purchase (shouldn't happen, buying requires an account), `logIn` merges it into the account — that's the desired outcome.
- **VALIDATE**: `cd pingduck_app && flutter analyze && flutter test`
- **SATISFIES**: AC 5.

### Task 11: CREATE `pingduck_app/lib/features/subscription/presentation/paywall_screen.dart`

- **IMPLEMENT**:
  - `Future<void> openPaywall(BuildContext context, WidgetRef ref)`: if `!billingSupported` → toast "Subscriptions are available in the Android app for now." and return. If `ref.read(accountEmailProvider).value == null` → push `SignInScreen` (sign-up mode) with a lead line "Create an account first, so Premium follows you to any phone." Return to the paywall only if an account now exists. Then push `PaywallScreen`.
  - `PaywallScreen` (ConsumerStatefulWidget): `FutureBuilder` on `billing.offers()`; loading spinner; error → panel with Retry. Header: "PingDuck Premium". Benefits panel (from `plans` premium row, hard-coded copy is fine): unlimited scans; Homelab Agent on up to 2 networks; full device history; new-device alerts; security checks & scheduled speed tests (marked "coming" if not built). Two selectable option tiles (annual first, pre-selected, `PdChip('SAVE ${savings}%')`): "$34.99 / year" / "$4.99 / month". Primary button: `trialDays != null ? 'Start ${trialDays}-day free trial' : 'Subscribe'`. Fine print under it: "${trialDays} days free, then ${price} per ${period}. Renews automatically until you cancel in Google Play, at least 24 hours before the period ends." Text buttons: "Restore purchases", "Terms", "Privacy" (open `https://pingduck.app/terms` / `/privacy` with `url_launcher`; add the dependency only if it isn't already in pubspec).
  - On buy: disable buttons; `purchased` → `final ok = await ref.read(currentPlanProvider.notifier).waitForPaid();` → `ok` ? toast "Premium is active" + pop : toast "Purchase received. Premium will turn on within a few minutes." + pop. `cancelled` → nothing. `pending` → toast "Payment pending. Premium turns on once Google Play confirms it." `BillingException` → red toast with its message.
  - Restore: `billing.restore()` then `waitForPaid(timeout: 15s)`; result toast "Premium restored" / "No active subscription found for this Google account."
- **PATTERN**: `FlowScaffold`/`PdPanel` layout as in `add_unit_intro_screen.dart`; toasts as in `sign_in_screen.dart`.
- **GOTCHA**: Show the store's `priceString` (localized), never hard-coded prices. Google requires the trial terms and renewal price to be clear before purchase; the fine print covers it. No dark patterns: no pre-checked extras, close button always visible.
- **VALIDATE**: `cd pingduck_app && flutter test test/paywall_test.dart`
- **SATISFIES**: AC 7.

### Task 12: CREATE `pingduck_app/lib/features/subscription/presentation/plan_panel.dart` and ADD it to the Account tab

- **IMPLEMENT**: `PlanPanel` (ConsumerWidget) reading `currentPlanProvider` and `FutureProvider` `subscriptionDetailsProvider` (`billing.details()`, refreshed with the plan):
  - Free: chip `FREE`, "3 scans a day, no monitoring." Button **Go Premium** → `openPaywall`. Text button **Restore purchases** (Android only).
  - Paid via store (`details?.active == true`): chip `PREMIUM` (`PdTone.live`), line by state: trial → "Free trial · ends {date}"; willRenew → "Renews {date}"; !willRenew → "Cancelled · Premium until {date}"; billingIssue → red "Payment problem · fix it in Google Play". Buttons **Manage subscription** (open `manageUrl` externally) and **Restore purchases**.
  - Paid without store details (manual entitlement or Windows): chip `PREMIUM`, "Premium is active on this account." No Manage button.
  - Insert in `account_screen.dart` right after `_IdentityPanel` (before Monitoring).
- **PATTERN**: `_IdentityPanel` (`account_screen.dart:154-230`), `PdField` rows.
- **VALIDATE**: `cd pingduck_app && flutter test test/plan_panel_test.dart`
- **SATISFIES**: AC 8.

### Task 13: UPDATE upgrade points to open the paywall

- **IMPLEMENT**:
  - `add_unit_intro_screen.dart` `PremiumRequiredScreen`: replace `FlowPrimaryButton(label: 'Subscriptions coming soon')` with `FlowPrimaryButton(label: 'See Premium', onPressed: () => openPaywall(context, ref))` (make it a ConsumerWidget). After returning, if the plan is now paid, pop back to continue pairing.
  - `overview_screen.dart` quota banner: add a `PdButton` "Go Premium" under the text when `failure.kind == quotaExceeded`.
  - `settings_screen.dart` alerts row: when the blocker is "Premium plan required", make the row tappable → `openPaywall`.
- **VALIDATE**: `cd pingduck_app && flutter test`
- **SATISFIES**: AC 7.

### Task 14: UPDATE `confirmDeleteAccount` with the subscription warning

- **IMPLEMENT**: in `settings_screen.dart:296+`, before the existing confirmation, `final d = await ref.read(billingProvider).details();` If `d?.active == true && d.willRenew`: the dialog adds a red line "Your Premium subscription keeps billing until you cancel it in Google Play. Deleting your account doesn't cancel it." and a "Open Google Play" button (`playSubscriptionsUrl`). The delete button stays available.
- **VALIDATE**: `cd pingduck_app && flutter test`
- **SATISFIES**: AC 10.

### Task 15: UPDATE the Auto-scan on launch row (decision 6)

- **IMPLEMENT**: `settings_screen.dart:140-175`: remove the `PREMIUM` chip and the Premium-only subtitle; `onChanged` always enabled. Subtitle: "Start a scan when the app opens. On Free, at most once every 30 minutes." when not Premium; current text when Premium. Update the `main.dart:99` comment (no longer "if they are Premium").
- **GOTCHA**: The 30-minute rule lives in `ServerScanQuota.claimAutomatic`; don't touch it. Update the test that asserts the switch is disabled on Free.
- **VALIDATE**: `cd pingduck_app && flutter test`
- **SATISFIES**: AC 11.

### Task 16: ADD fakes and widget tests

- **IMPLEMENT**:
  - `test/fakes.dart`: `FakeBilling` (configurable offers, outcome, details; records calls) and `FakePlanRepository` (queue of plans returned on each call).
  - `test/plan_test.dart`: fetch maps both row shapes; error falls back to cached premium; `waitForPaid` returns true when the 3rd poll is paid, false on timeout (use short durations).
  - `test/paywall_test.dart`: anonymous → sign-in pushed, paywall not shown; offers render annual first with SAVE chip and trial button text; purchased + paid → "Premium is active" and pop; cancelled → stays; BillingException → error toast; restore none → "No active subscription…".
  - `test/plan_panel_test.dart`: Free shows Go Premium; trial/renews/cancelled/billing-issue lines; manual Premium shows no Manage button.
  - Update `settings_cloud_rows_test.dart` / auto-scan tests for Task 15.
- **PATTERN**: `test/settings_cloud_rows_test.dart` provider overrides; override `debugDefaultTargetPlatformOverride = TargetPlatform.android` for billing-visible paths and reset in `tearDown`.
- **VALIDATE**: `cd pingduck_app && flutter analyze && flutter test`
- **SATISFIES**: AC 6, AC 7, AC 8, AC 11.

### Task 17: UPDATE `docs/ROADMAP.md`

- **IMPLEMENT**: Decisions: Billing provider → decided RevenueCat (strike-through style used by other decided rows); Pricing → decided $4.99/$34.99, 7-day trial on both, Premium only at launch; Free launch scan → decided (Free can switch it off; still rate-limited); Launch scope → Android first, **before** Phase 6 (Phase 6 moves after launch; adjust Timeline weeks so launch follows Phase 5 + Phase 8). Phase 5 rows: mark built items 🟡 with "Android built; iOS later" and link this plan.
- **VALIDATE**: `grep -n "Launch scope\|Pricing\|Billing provider\|Free launch scan" docs/ROADMAP.md`
- **SATISFIES**: AC 12.

### Task 18: DEPLOY the webhook (user runs; agent verifies)

- **IMPLEMENT**:
  1. User sets Edge Function secrets in the Supabase dashboard (Project › Edge Functions › Secrets): `REVENUECAT_SECRET_KEY` (the `sk_` v1 key), `REVENUECAT_WEBHOOK_AUTH` (a random string, e.g. from a password manager, prefixed `Bearer `).
  2. User runs `! npx --no-install supabase functions deploy revenuecat-webhook --no-verify-jwt` from the repo root (auto mode blocks the agent from deploying). Also redeploy `notify-new-devices` (Task 2 changed its imports): `! npx --no-install supabase functions deploy notify-new-devices --no-verify-jwt`.
  3. In RevenueCat › Integrations › Webhooks: URL `https://rumwtzzyrhzudguolasq.supabase.co/functions/v1/revenuecat-webhook`, Authorization header = the same value as `REVENUECAT_WEBHOOK_AUTH`, environment: both. Send the test event.
- **VALIDATE**: agent runs `npx --no-install supabase functions list` (both ACTIVE, `verify_jwt: false`); `curl -s -o /dev/null -w "%{http_code}" -X POST <url> -d '{}'` → `401`; RevenueCat's test event shows 200 in its webhook log.
- **SATISFIES**: AC 2.

### Task 19: UPDATE the privacy policy (website repo, separate PR)

- **IMPLEMENT**: In `pingduck_website/src/app/privacy/page.tsx` (~line 155-160), replace "Subscription payments, if offered, are processed by Apple or Google" with: purchases are processed by Google Play (and Apple later); PingDuck uses **RevenueCat** to validate purchases and track subscription status; shared with RevenueCat: the random account id and purchase records from the store (no payment card details, no network or device data). Add RevenueCat to the processors list if the page has one. Terms already cover auto-renewal, cancelling and refunds (`terms/page.tsx` §3); no change unless wording says "may offer".
- **PATTERN**: website repo is `Big-Duck-Networks/Pingduck.app`, local `../pingduck_website`, Hetzner deploy (see memory `website-repo`).
- **VALIDATE**: `cd ../pingduck_website && npm run lint && npm run build`
- **SATISFIES**: AC 12.

### Task 20: UPDATE Play data safety (user, Play Console)

- **IMPLEMENT**: Play Console › App content › Data safety: declare **Purchase history** (collected, shared with RevenueCat as a service provider, for app functionality) and the **User ID** (account id). Keep the FCM token declaration from Phase 4.
- **VALIDATE**: Play Console shows the form saved.
- **SATISFIES**: AC 12.

### Task 21: LIVE TEST with a license tester (user + agent)

- **IMPLEMENT** on the Pixel, installed from the Internal testing link (Play billing does not work in sideloaded debug builds signed with another key):
  1. Free account signed in → Account › Go Premium → paywall shows Play prices and "Start 7-day free trial".
  2. Buy annual with the test card → within ~30 s "Premium is active"; Account shows "Free trial · ends …".
  3. Agent checks: `npx --no-install supabase db query --linked "select plan_code, status, period_ends_at, source from public.entitlements where source = 'revenuecat'"` → `premium`, `trialing`.
  4. Pairing / alerts / unlimited scans unlocked without a scan first.
  5. Cancel in Play → Account shows "Cancelled · Premium until …" (after the webhook); test renewals are minutes long, so wait for expiry → row `expired`, app back to Free on resume.
  6. Restore: reinstall from Play, sign in to the same account → Restore purchases → "Premium restored" (or already Premium from the server).
  7. Anonymous install → Go Premium → routed to sign-up.
- **VALIDATE**: each step's observed result recorded in the PR.
- **SATISFIES**: AC 4, AC 6, AC 7, AC 8, AC 13.

---

## TESTING STRATEGY

### Unit Tests

- Deno (`entitlement_test.ts`): id extraction and the status mapping, all branches.
- Dart (`plan_test.dart`): plan fetch, fallback, polling.

### Widget Tests

- Paywall, Plan panel, upgrade points, delete-account warning, auto-scan switch, all with `FakeBilling`/`FakePlanRepository` overrides and `debugDefaultTargetPlatformOverride`.

### Integration / Live

- RevenueCat dashboard test webhook → 200.
- License-tester purchase, cancel, expiry, restore (Task 21). Play test subscriptions renew in minutes (monthly ≈ 5 min, annual ≈ 30 min; trial ≈ 3 min), so the whole lifecycle fits in one sitting.

### Edge Cases

- Webhook arrives before the app polls; app polls before webhook (30 s window, then "within a few minutes" message).
- Duplicate and out-of-order webhooks (re-read makes them idempotent).
- `TRANSFER` between two PingDuck accounts on one Google account: old account → expired, new → active.
- Manual entitlement exists (current test account): webhook leaves it alone.
- Deleted account still subscribed: webhook gets FK error → skip, 200.
- Payment pending (slow card): no Premium until confirmed.
- Billing grace period: still Premium, Account shows payment problem.
- Windows / desktop: no paywall, plan panel shows server plan only.
- Offline: plan falls back to cached `isPremiumKey`.

---

## VALIDATION COMMANDS

### Level 1: Syntax & Style

- `cd pingduck_app && flutter analyze`
- `cd supabase/functions && deno check */index.ts`
- `actionlint` (if any workflow changes)

### Level 2: Unit Tests

- `cd pingduck_app && flutter test`
- `cd supabase/functions && deno test`
- `sh supabase/tests/run_tests.sh` (schema unchanged; must still pass)

### Level 3: Build

- `cd pingduck_app && flutter build apk --debug`
- `cd pingduck_app && flutter build appbundle --release` (signed with `key.properties`)
- CI: `app ci`, `database ci` green on the PR.

### Level 4: Manual Validation

- Task 18 checks (function list, 401 probe, RevenueCat test event).
- Task 21 live test.

### Level 5: Additional

- `npx --no-install supabase db query --linked "select * from public.entitlements"` after each live step.
- Function logs: Supabase dashboard › Edge Functions › revenuecat-webhook › Logs.

---

## ACCEPTANCE CRITERIA

- [ ] AC 1: Play subscription `premium` (monthly $4.99, annual $34.99, 7-day trial each) is active; RevenueCat has entitlement `premium` and current offering `default` with both packages.
- [ ] AC 2: `revenuecat-webhook` is deployed with JWT verification off, rejects a wrong Authorization header with 401, and answers RevenueCat's test event with 200.
- [ ] AC 3: Webhook status mapping (trialing/active/grace/expired/none) is unit-tested and matches `plan_for`'s rules.
- [ ] AC 4: A license-tester purchase writes `entitlements` (`premium`, `trialing`, `source revenuecat`) within a minute; cancel + expiry turns it `expired`; manual rows are never overwritten.
- [ ] AC 5: The app configures RevenueCat only on Android, only with a non-anonymous Supabase user id, and logs out on sign-out.
- [ ] AC 6: Premium appears in the app from `my_plan()` without a scan, within 30 s of purchase in the normal case; device state never grants Premium.
- [ ] AC 7: Paywall shows store prices, trial and renewal terms, Restore, Terms and Privacy; anonymous users are sent to sign-up first; all three upgrade points open it.
- [ ] AC 8: Account tab shows Free / trial / renews / cancelled / payment problem / manual Premium correctly, with Manage subscription and Restore purchases.
- [ ] AC 9: Release AAB declares `com.android.vending.BILLING`; the Windows build still compiles.
- [ ] AC 10: Delete account warns while a store subscription will renew and links to Play.
- [ ] AC 11: Free users can switch Auto-scan on launch; Free automatic scans stay limited to one per 30 minutes.
- [ ] AC 12: Roadmap decisions updated; privacy policy names RevenueCat; Play data safety lists purchase history.
- [ ] AC 13: `flutter analyze`, `flutter test`, `deno test`, schema tests pass; CI green.

---

## COMPLETION CHECKLIST

- [ ] All tasks completed in order
- [ ] Each task validation passed immediately
- [ ] All validation commands executed successfully
- [ ] Full test suite passes (unit + widget + Deno + schema)
- [ ] No linting or type checking errors
- [ ] Live license-tester run recorded
- [ ] Acceptance criteria all met
- [ ] Code reviewed for quality and maintainability

---

## OPEN QUESTIONS / ASSUMPTIONS

- Assumed — RevenueCat **v1** secret key works for `GET /v1/subscribers` on the user's project (new projects may default to v2 keys; if only v2 is available, use `GET https://api.revenuecat.com/v2/projects/{project_id}/customers/{id}/active_entitlements` and adapt `entitlementRow`). Confirm in Task 1.8.
- Assumed — Google Play allows creating the subscription once the Billing-enabled AAB from Task 9 is on Internal testing; if Play requires a closed track for this account, upload there instead.
- Assumed — the current manually-granted Premium test account stays `manual`; to test real purchases, use a different account or delete that row first.
- Assumed — prices are USD base; Play's automatic local pricing is acceptable.
- Assumed — "security checks" and "scheduled speed tests" on the paywall are labelled as coming later (they are Phase 6/7 features); confirm the copy before release.

## NOTES (open canvas)

**Why re-read from REST instead of handling events.** RevenueCat itself recommends it, and it removes three classes of bugs: duplicate delivery (at-least-once), out-of-order delivery (an EXPIRATION processed after a later RENEWAL), and per-event-type branching. The cost is one HTTPS call per user id per event, trivial at this scale.

**Why an account is required.** With anonymous buyers, the purchase lives on an anonymous Supabase id. Signing in to an existing account (which `AccountAuth.signIn` does by leaving the anonymous user behind) or reinstalling strands it until a Restore transfers it, and the entitlement row would sit on an orphaned user. Requiring an account up front costs one screen and matches Fing.

**Why `my_plan()` polling instead of Realtime on `entitlements`.** RLS already allows select-own, so Realtime would work, but the app only cares right after a purchase/restore and on resume. A 30 s poll is simpler and avoids another channel.

**Why `period_ends_at` is enough without a cron.** `plan_for` compares with `now()`, so a missed EXPIRATION webhook still drops the user to Free at the right time. The webhook keeps statuses tidy for display and analytics.

**Later, iOS:** add the `appl_` key and App Store products in RevenueCat, attach them to entitlement `premium`; the webhook and app code need no change beyond `billingSupported` and a StoreKit-aware `manageUrl`.

## AMENDMENTS

- 2026-10-13: RevenueCat webhooks need a paid RevenueCat plan (Pro or higher); the project is on the free plan. Entitlements now come from Google Play's own real-time developer notifications instead: a second Pub/Sub push subscription on the RTDN topic RevenueCat created calls the new `play-rtdn` Edge Function, which reads the subscription from the Play Developer API and writes `entitlements` with source `play`. The user comes from RevenueCat's obfuscated account id on the purchase, `sha256(app user id)` (seen in `BillingWrapper` of the RevenueCat Android SDK 10.26), looked up by `user_id_for_store_tag`; tokens are remembered in `store_purchases` for linked (upgrade) tokens. `revenuecat-webhook` stays deployed for a later move to a paid plan.
- 2026-10-13: Live-test findings. Play billing only works in builds installed from Play (Internal testing), not sideloaded or `flutter run` builds (`BILLING_UNAVAILABLE`). Offerings must use Google Play products, not RevenueCat's Test Store. Free-trial eligibility belongs to the Google account, not the PingDuck account: once a Google account has subscribed, Play no longer offers it the trial.
