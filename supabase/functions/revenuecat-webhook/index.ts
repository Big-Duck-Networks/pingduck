// RevenueCat webhook: keeps public.entitlements in step with the store. It
// never trusts the event's own state. For every PingDuck user the event
// mentions it re-reads the subscriber from RevenueCat's REST API and writes
// the row, so duplicate or out-of-order deliveries are harmless. Rows with
// source 'manual' (comps, test accounts) are left alone.
//
// Secrets: REVENUECAT_WEBHOOK_AUTH (the exact Authorization header value set
// on the RevenueCat webhook) and REVENUECAT_SECRET_KEY (v1 secret API key).
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the platform.
// Deploy with --no-verify-jwt: RevenueCat sends no Supabase JWT, the
// Authorization header is checked here instead.

import { createClient } from "npm:@supabase/supabase-js@2";
import { sameSecret } from "../_shared/secret.ts";
import { entitlementRow, PLAN, type Subscriber, userIdsIn } from "./entitlement.ts";

function reply(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function fetchSubscriber(id: string, key: string): Promise<Subscriber> {
  const res = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(id)}`,
    { headers: { Authorization: `Bearer ${key}` } },
  );
  if (!res.ok) throw new Error(`revenuecat subscriber: ${res.status}`);
  return (await res.json()).subscriber ?? {};
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply(405, { error: "method" });
  if (!sameSecret(req.headers.get("authorization"), Deno.env.get("REVENUECAT_WEBHOOK_AUTH"))) {
    return reply(401, { error: "unauthorized" });
  }

  let event: Record<string, unknown>;
  try {
    event = (await req.json()).event;
  } catch {
    return reply(400, { error: "body" });
  }
  if (!event || typeof event !== "object") return reply(400, { error: "body" });

  const key = Deno.env.get("REVENUECAT_SECRET_KEY");
  if (!key) {
    console.error("revenuecat-webhook: REVENUECAT_SECRET_KEY missing");
    return reply(500, { error: "config" });
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const written: string[] = [];
  const skipped: string[] = [];
  try {
    for (const id of userIdsIn(event)) {
      const row = entitlementRow(await fetchSubscriber(id, key), new Date());

      const { data: existing, error: readError } = await db
        .from("entitlements")
        .select("source, period_ends_at")
        .eq("user_id", id)
        .maybeSingle();
      if (readError) throw new Error(`entitlements read: ${readError.message}`);
      if (existing?.source === "manual" || (row === null && !existing)) {
        skipped.push(id);
        continue;
      }

      const { error } = await db.from("entitlements").upsert({
        user_id: id,
        plan_code: PLAN,
        ...(row ?? { status: "expired", period_ends_at: existing!.period_ends_at }),
        source: "revenuecat",
        updated_at: new Date().toISOString(),
      });
      if (error?.code === "23503") {
        // Not (or no longer) a user here, e.g. a deleted account.
        skipped.push(id);
        continue;
      }
      if (error) throw new Error(`entitlements write: ${error.message}`);
      written.push(id);
    }
  } catch (e) {
    // A 500 makes RevenueCat retry later.
    console.error("revenuecat-webhook:", (e as Error).message);
    return reply(500, { error: "sync" });
  }

  console.log(
    `revenuecat-webhook: ${event.type} (${event.environment}) written=${written.length} skipped=${skipped.length}`,
  );
  return reply(200, { ok: true, written, skipped });
});
