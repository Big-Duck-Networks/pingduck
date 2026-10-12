// Pure helpers for revenuecat-webhook: which PingDuck users an event touches,
// and what entitlements row a RevenueCat subscriber maps to. Kept free of
// I/O so they can be unit-tested.

export const ENTITLEMENT = "premium";
export const PLAN = "premium";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// Every Supabase user id an event mentions. RevenueCat's own anonymous ids
// ($RCAnonymousID:...) are skipped: they are never PingDuck users.
export function userIdsIn(event: Record<string, unknown>): string[] {
  const out = new Set<string>();
  const add = (v: unknown) => {
    if (typeof v !== "string") return;
    const id = v.toLowerCase();
    if (UUID.test(id)) out.add(id);
  };
  add(event.app_user_id);
  add(event.original_app_user_id);
  for (const key of ["aliases", "transferred_from", "transferred_to"]) {
    const list = event[key];
    if (Array.isArray(list)) list.forEach(add);
  }
  return [...out];
}

export type Subscriber = {
  entitlements?: Record<string, {
    expires_date?: string | null;
    grace_period_expires_date?: string | null;
    product_identifier?: string;
  }>;
  subscriptions?: Record<string, { period_type?: string }>;
};

export type Row = {
  plan_code: string;
  status: "active" | "trialing" | "grace" | "expired";
  period_ends_at: string | null;
};

// The row for the subscriber's "premium" entitlement, or null when they never
// had it. Mirrors plan_for: a row counts while period_ends_at is in the future.
export function entitlementRow(subscriber: Subscriber, now: Date): Row | null {
  const e = subscriber.entitlements?.[ENTITLEMENT];
  if (!e) return null;
  const expires = e.expires_date ? new Date(e.expires_date) : null;
  const grace = e.grace_period_expires_date ? new Date(e.grace_period_expires_date) : null;

  if (expires === null) return { plan_code: PLAN, status: "active", period_ends_at: null };
  if (expires > now) {
    const periodType = e.product_identifier
      ? subscriber.subscriptions?.[e.product_identifier]?.period_type
      : undefined;
    return {
      plan_code: PLAN,
      status: periodType === "trial" ? "trialing" : "active",
      period_ends_at: expires.toISOString(),
    };
  }
  if (grace && grace > now) {
    return { plan_code: PLAN, status: "grace", period_ends_at: grace.toISOString() };
  }
  return { plan_code: PLAN, status: "expired", period_ends_at: expires.toISOString() };
}
