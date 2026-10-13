import { assert, assertEquals } from "jsr:@std/assert@1";
import { playEntitlement, pusherOk, readPush, tokenRef } from "./play.ts";

const now = new Date("2026-10-13T12:00:00Z");
const future = "2026-10-20T12:00:00.000Z";
const past = "2026-10-06T12:00:00.000Z";

function push(notification: unknown, messageId = "m-1") {
  return { message: { data: btoa(JSON.stringify(notification)), messageId }, subscription: "projects/p/subscriptions/s" };
}

const item = (expiryTime: string, extra: Record<string, unknown> = {}) => ({ productId: "premium", expiryTime, ...extra });

Deno.test("a subscription push yields its token and type", () => {
  const p = readPush(push({
    packageName: "app.webcap.pingduck",
    subscriptionNotification: { notificationType: 2, purchaseToken: "tok", subscriptionId: "premium" },
  }));
  assertEquals(p, {
    messageId: "m-1",
    notification: { kind: "subscription", packageName: "app.webcap.pingduck", purchaseToken: "tok", notificationType: 2 },
  });
});

Deno.test("test, voided and other notifications are told apart", () => {
  assertEquals(readPush(push({ packageName: "x", testNotification: { version: "1.0" } }))?.notification.kind, "test");
  assertEquals(
    readPush(push({ packageName: "x", voidedPurchaseNotification: { purchaseToken: "t", productType: 1 } }))?.notification,
    { kind: "voided", packageName: "x", purchaseToken: "t" },
  );
  // A voided one-time product isn't a subscription.
  assertEquals(
    readPush(push({ packageName: "x", voidedPurchaseNotification: { purchaseToken: "t", productType: 2 } }))?.notification.kind,
    "other",
  );
  assertEquals(readPush(push({ packageName: "x", oneTimeProductNotification: {} }))?.notification.kind, "other");
});

Deno.test("a body that isn't a Pub/Sub push of JSON is refused", () => {
  assertEquals(readPush(null), null);
  assertEquals(readPush({ message: {} }), null);
  assertEquals(readPush({ message: { data: btoa("not json") } }), null);
});

Deno.test("only the configured, verified service account may push", () => {
  assert(pusherOk({ email: "push@p.iam.gserviceaccount.com", email_verified: true }, "push@p.iam.gserviceaccount.com"));
  assert(!pusherOk({ email: "other@p.iam.gserviceaccount.com", email_verified: true }, "push@p.iam.gserviceaccount.com"));
  assert(!pusherOk({ email: "push@p.iam.gserviceaccount.com", email_verified: false }, "push@p.iam.gserviceaccount.com"));
  assert(!pusherOk({ email: "push@p.iam.gserviceaccount.com", email_verified: true }, undefined));
});

Deno.test("an active subscription is active until expiry; a free trial is trialing", () => {
  assertEquals(playEntitlement({ subscriptionState: "SUBSCRIPTION_STATE_ACTIVE", lineItems: [item(future)] }, now),
    { plan_code: "premium", status: "active", period_ends_at: future });
  assertEquals(
    playEntitlement({ subscriptionState: "SUBSCRIPTION_STATE_ACTIVE", lineItems: [item(future, { offerPhase: { freeTrial: {} } })] }, now)
      ?.status,
    "trialing",
  );
});

Deno.test("canceled stays entitled until the period ends", () => {
  assertEquals(playEntitlement({ subscriptionState: "SUBSCRIPTION_STATE_CANCELED", lineItems: [item(future)] }, now)?.status, "active");
  assertEquals(playEntitlement({ subscriptionState: "SUBSCRIPTION_STATE_CANCELED", lineItems: [item(past)] }, now),
    { plan_code: "premium", status: "expired", period_ends_at: past });
});

Deno.test("grace keeps access; on hold and expired don't", () => {
  assertEquals(playEntitlement({ subscriptionState: "SUBSCRIPTION_STATE_IN_GRACE_PERIOD", lineItems: [item(future)] }, now),
    { plan_code: "premium", status: "grace", period_ends_at: future });
  // On hold: the period hasn't formally ended but there is no access, so it ends now.
  assertEquals(playEntitlement({ subscriptionState: "SUBSCRIPTION_STATE_ON_HOLD", lineItems: [item(future)] }, now),
    { plan_code: "premium", status: "expired", period_ends_at: now.toISOString() });
  assertEquals(playEntitlement({ subscriptionState: "SUBSCRIPTION_STATE_EXPIRED", lineItems: [item(past)] }, now)?.status, "expired");
});

Deno.test("a refund revokes now", () => {
  assertEquals(playEntitlement({ subscriptionState: "SUBSCRIPTION_STATE_ACTIVE", lineItems: [item(future)] }, now, true),
    { plan_code: "premium", status: "revoked", period_ends_at: now.toISOString() });
});

Deno.test("the latest premium line item counts; other products are ignored", () => {
  const row = playEntitlement({
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    lineItems: [item(past), { productId: "pro", expiryTime: "2027-01-01T00:00:00.000Z" }, item(future)],
  }, now);
  assertEquals(row?.period_ends_at, future);
  assertEquals(playEntitlement({ subscriptionState: "SUBSCRIPTION_STATE_ACTIVE", lineItems: [{ productId: "pro", expiryTime: future }] }, now), null);
});

Deno.test("the token reference is short and stable", async () => {
  // sha256("tok") = 1a7674eb4ee78df7...; only the first 16 hex characters are kept.
  assertEquals(await tokenRef("tok"), "1a7674eb4ee78df7");
  assertEquals((await tokenRef("tok")).length, 16);
});
