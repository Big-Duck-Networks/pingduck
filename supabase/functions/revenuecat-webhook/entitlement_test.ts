import { assertEquals } from "jsr:@std/assert@1";
import { entitlementRow, userIdsIn } from "./entitlement.ts";

const A = "0b6f4c1e-2d3a-4b5c-8d9e-0f1a2b3c4d5e";
const B = "1c7a5d2f-3e4b-4c6d-9e0f-1a2b3c4d5e6f";
const now = new Date("2026-10-12T12:00:00Z");
const future = "2026-10-19T12:00:00.000Z";
const past = "2026-10-05T12:00:00.000Z";

Deno.test("user ids come from every field, lower-cased, deduped, UUIDs only", () => {
  const ids = userIdsIn({
    app_user_id: A.toUpperCase(),
    original_app_user_id: "$RCAnonymousID:abc123",
    aliases: [A, "$RCAnonymousID:abc123"],
    transferred_from: [B],
    transferred_to: [A],
  });
  assertEquals(ids.sort(), [A, B].sort());
});

Deno.test("a trial in progress is trialing", () => {
  const row = entitlementRow({
    entitlements: { premium: { expires_date: future, product_identifier: "premium:annual" } },
    subscriptions: { "premium:annual": { period_type: "trial" } },
  }, now);
  assertEquals(row, { plan_code: "premium", status: "trialing", period_ends_at: future });
});

Deno.test("a paid period in progress is active", () => {
  const row = entitlementRow({
    entitlements: { premium: { expires_date: future, product_identifier: "premium:monthly" } },
    subscriptions: { "premium:monthly": { period_type: "normal" } },
  }, now);
  assertEquals(row, { plan_code: "premium", status: "active", period_ends_at: future });
});

Deno.test("past expiry inside the grace period is grace, ending with it", () => {
  const row = entitlementRow({
    entitlements: { premium: { expires_date: past, grace_period_expires_date: future } },
  }, now);
  assertEquals(row, { plan_code: "premium", status: "grace", period_ends_at: future });
});

Deno.test("past expiry and grace is expired", () => {
  const row = entitlementRow({
    entitlements: { premium: { expires_date: past, grace_period_expires_date: past } },
  }, now);
  assertEquals(row, { plan_code: "premium", status: "expired", period_ends_at: past });
});

Deno.test("no premium entitlement maps to no row", () => {
  assertEquals(entitlementRow({ entitlements: {} }, now), null);
  assertEquals(entitlementRow({}, now), null);
});

Deno.test("a non-expiring entitlement is active with no end", () => {
  const row = entitlementRow({ entitlements: { premium: { expires_date: null } } }, now);
  assertEquals(row, { plan_code: "premium", status: "active", period_ends_at: null });
});
