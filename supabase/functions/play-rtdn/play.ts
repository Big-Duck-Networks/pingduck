// Pure helpers for play-rtdn: reading a Pub/Sub push of a Play notification,
// and mapping a Play Developer API subscription (subscriptionsv2) to an
// entitlements row. Kept free of I/O so they can be unit-tested.

export const PACKAGE = "app.webcap.pingduck";
export const PRODUCT = "premium";
export const PLAN = "premium";
export const PLAY_SCOPE = "https://www.googleapis.com/auth/androidpublisher";
export const GOOGLE_ISSUERS = ["https://accounts.google.com", "accounts.google.com"];

// voidedPurchaseNotification.productType for subscriptions.
const VOIDED_SUBSCRIPTION = 1;

export type Notification =
  | { kind: "test"; packageName: string }
  | { kind: "subscription"; packageName: string; purchaseToken: string; notificationType: number }
  | { kind: "voided"; packageName: string; purchaseToken: string }
  | { kind: "other"; packageName: string };

// The Play notification inside a Pub/Sub push body, or null if it isn't one.
export function readPush(body: unknown): { messageId: string | null; notification: Notification } | null {
  const message = (body as { message?: { data?: string; messageId?: string } })?.message;
  if (typeof message?.data !== "string") return null;
  let n: Record<string, unknown>;
  try {
    n = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(message.data), (c) => c.charCodeAt(0))));
  } catch {
    return null;
  }
  const packageName = typeof n.packageName === "string" ? n.packageName : "";
  const sub = n.subscriptionNotification as { purchaseToken?: string; notificationType?: number } | undefined;
  const voided = n.voidedPurchaseNotification as { purchaseToken?: string; productType?: number } | undefined;
  const notification: Notification = n.testNotification
    ? { kind: "test", packageName }
    : typeof sub?.purchaseToken === "string"
    ? { kind: "subscription", packageName, purchaseToken: sub.purchaseToken, notificationType: sub.notificationType ?? 0 }
    : typeof voided?.purchaseToken === "string" && voided.productType === VOIDED_SUBSCRIPTION
    ? { kind: "voided", packageName, purchaseToken: voided.purchaseToken }
    : { kind: "other", packageName };
  return { messageId: message.messageId ?? null, notification };
}

// The OIDC token must come from the service account the push subscription
// authenticates as. Issuer, audience and signature are checked by jose.
export function pusherOk(claims: Record<string, unknown>, pusher: string | undefined): boolean {
  return !!pusher && claims.email === pusher && claims.email_verified === true;
}

export type PlaySubscription = {
  subscriptionState?: string;
  linkedPurchaseToken?: string;
  externalAccountIdentifiers?: { obfuscatedExternalAccountId?: string };
  lineItems?: {
    productId?: string;
    expiryTime?: string;
    offerPhase?: { freeTrial?: unknown };
  }[];
};

export type Row = {
  plan_code: string;
  status: "active" | "trialing" | "grace" | "expired" | "revoked";
  period_ends_at: string | null;
};

// States in which Play still gives the user the subscription.
const ENTITLED = new Set(["SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_CANCELED"]);

// The row for the subscription's premium line item, or null if it has none.
// Canceled means auto-renew is off: still entitled until the period ends.
// In a grace period Play's expiryTime is the end of the grace period.
export function playEntitlement(sub: PlaySubscription, now: Date, voided = false): Row | null {
  const item = (sub.lineItems ?? [])
    .filter((l) => l.productId === PRODUCT && l.expiryTime)
    .sort((a, b) => Date.parse(b.expiryTime!) - Date.parse(a.expiryTime!))[0];
  if (!item) return null;
  const expires = new Date(item.expiryTime!);
  const ends = expires.toISOString();

  if (voided) return { plan_code: PLAN, status: "revoked", period_ends_at: now.toISOString() };
  const state = sub.subscriptionState ?? "";
  if (ENTITLED.has(state) && expires > now) {
    return { plan_code: PLAN, status: item.offerPhase?.freeTrial ? "trialing" : "active", period_ends_at: ends };
  }
  if (state === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" && expires > now) {
    return { plan_code: PLAN, status: "grace", period_ends_at: ends };
  }
  // Expired, on hold, paused, pending, or past its end.
  return { plan_code: PLAN, status: "expired", period_ends_at: expires < now ? ends : now.toISOString() };
}

// A short, non-reversible reference to a token for the notifications log.
export async function tokenRef(token: string): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 16);
}
