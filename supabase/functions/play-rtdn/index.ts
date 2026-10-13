// Google Play real-time developer notifications, pushed by Pub/Sub. Keeps
// public.entitlements current without RevenueCat's (paid) webhook: for every
// subscription notification it asks the Play Developer API for the
// subscription's state and writes the row with source 'play'. Rows with
// source 'manual' are left alone.
//
// Pub/Sub signs each push with a Google OIDC token for the service account
// the push subscription authenticates as; anything else is refused.
//
// Secrets: PLAY_SERVICE_ACCOUNT (service-account JSON with access to the Play
// Developer API) and PLAY_RTDN_PUSHER (the email the push subscription
// authenticates as). PLAY_RTDN_AUDIENCE overrides the expected OIDC audience,
// which defaults to this function's URL. SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY are injected by the platform.
// Deploy with --no-verify-jwt: Google's token isn't a Supabase JWT.
//
// Replies 200 to anything handled or deliberately skipped, and 500 when a
// retry could help (Play or the database unreachable); Pub/Sub retries.

import { createClient } from "npm:@supabase/supabase-js@2";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5";
import { accessToken, serviceAccountFrom } from "../_shared/google.ts";
import {
  GOOGLE_ISSUERS,
  PACKAGE,
  PLAN,
  PLAY_SCOPE,
  type PlaySubscription,
  playEntitlement,
  PRODUCT,
  pusherOk,
  readPush,
  tokenRef,
} from "./play.ts";

const googleKeys = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"));

function reply(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function fromGoogle(req: Request): Promise<boolean> {
  const token = req.headers.get("authorization")?.replace(/^Bearer /, "");
  if (!token) return false;
  const audience = Deno.env.get("PLAY_RTDN_AUDIENCE") ??
    `${Deno.env.get("SUPABASE_URL")}/functions/v1/play-rtdn`;
  try {
    const { payload } = await jwtVerify(token, googleKeys, { issuer: GOOGLE_ISSUERS, audience });
    return pusherOk(payload, Deno.env.get("PLAY_RTDN_PUSHER"));
  } catch {
    return false;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply(405, { error: "method" });
  if (!(await fromGoogle(req))) return reply(401, { error: "unauthorized" });

  const push = readPush(await req.json().catch(() => null));
  if (!push) return reply(200, { skipped: "not a Play notification" });
  const n = push.notification;

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
  const log = async (fields: Record<string, unknown>) => {
    const { error } = await db.from("store_notifications").insert({
      message_id: push.messageId,
      kind: n.kind,
      notification_type: n.kind === "subscription" ? n.notificationType : null,
      ...fields,
    });
    if (error) console.error("play-rtdn: log", error.message);
  };

  if (n.packageName !== PACKAGE) {
    await log({ outcome: "other_package" });
    return reply(200, { skipped: "package" });
  }
  if (n.kind === "test" || n.kind === "other") {
    await log({ outcome: n.kind });
    console.log(`play-rtdn: ${n.kind} notification`);
    return reply(200, { ok: true, kind: n.kind });
  }

  const sa = serviceAccountFrom(Deno.env.get("PLAY_SERVICE_ACCOUNT"));
  if (!sa) {
    console.error("play-rtdn: PLAY_SERVICE_ACCOUNT missing or incomplete");
    return reply(500, { error: "config" });
  }
  const ref = await tokenRef(n.purchaseToken);

  try {
    const res = await fetch(
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}` +
        `/purchases/subscriptionsv2/tokens/${encodeURIComponent(n.purchaseToken)}`,
      { headers: { Authorization: `Bearer ${await accessToken(sa, PLAY_SCOPE)}` } },
    );
    if (res.status === 404 || res.status === 410) {
      await res.body?.cancel();
      await log({ token_ref: ref, outcome: "token_gone" });
      return reply(200, { skipped: "token" });
    }
    if (!res.ok) throw new Error(`play api: ${res.status}`);
    const sub: PlaySubscription = await res.json();

    // Who it belongs to: RevenueCat's tag, else a token seen before.
    const tag = sub.externalAccountIdentifiers?.obfuscatedExternalAccountId;
    let userId: string | null = null;
    if (tag) {
      const { data, error } = await db.rpc("user_id_for_store_tag", { p_tag: tag });
      if (error) throw new Error(`tag lookup: ${error.message}`);
      userId = data;
    }
    for (const token of [n.purchaseToken, sub.linkedPurchaseToken]) {
      if (userId || !token) continue;
      const { data, error } = await db.from("store_purchases").select("user_id")
        .eq("purchase_token", token).maybeSingle();
      if (error) throw new Error(`token lookup: ${error.message}`);
      userId = data?.user_id ?? null;
    }
    if (!userId) {
      await log({ token_ref: ref, state: sub.subscriptionState, outcome: tag ? "unknown_tag" : "no_user" });
      return reply(200, { skipped: "user" });
    }

    const { error: rememberError } = await db.from("store_purchases").upsert({
      purchase_token: n.purchaseToken,
      user_id: userId,
      product_id: PRODUCT,
      linked_token: sub.linkedPurchaseToken ?? null,
      updated_at: new Date().toISOString(),
    });
    if (rememberError?.code === "23503") {
      await log({ token_ref: ref, state: sub.subscriptionState, outcome: "deleted_user" });
      return reply(200, { skipped: "user" });
    }
    if (rememberError) throw new Error(`remember token: ${rememberError.message}`);

    const row = playEntitlement(sub, new Date(), n.kind === "voided");
    const { data: existing, error: readError } = await db.from("entitlements")
      .select("source").eq("user_id", userId).maybeSingle();
    if (readError) throw new Error(`entitlements read: ${readError.message}`);
    if (!row || existing?.source === "manual") {
      await log({ token_ref: ref, user_id: userId, state: sub.subscriptionState, outcome: row ? "manual" : "no_item" });
      return reply(200, { skipped: row ? "manual" : "item" });
    }

    const { error } = await db.from("entitlements").upsert({
      user_id: userId,
      ...row,
      plan_code: PLAN,
      source: "play",
      updated_at: new Date().toISOString(),
    });
    if (error) throw new Error(`entitlements write: ${error.message}`);

    await log({ token_ref: ref, user_id: userId, state: sub.subscriptionState, outcome: row.status });
    console.log(`play-rtdn: ${n.kind} ${n.kind === "subscription" ? n.notificationType : ""} -> ${row.status}`);
    return reply(200, { ok: true, status: row.status });
  } catch (e) {
    console.error("play-rtdn:", (e as Error).message);
    await log({ token_ref: ref, outcome: "retry" });
    return reply(500, { error: "retry" });
  }
});
