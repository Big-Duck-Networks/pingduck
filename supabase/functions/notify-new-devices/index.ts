// Called by private.queue_new_device_alert (pg_net) after an agent sync finds
// devices worth an alert. Sends one data-only FCM message per registered
// phone of the network's owner; the phone fetches the details itself.
//
// Secrets: FCM_SERVICE_ACCOUNT (the Firebase service-account JSON) and
// NOTIFY_SECRET (same value as the Vault secret notify_secret).
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the platform.
// Deploy with --no-verify-jwt: Postgres has no user JWT, the hook secret is
// checked here instead.

import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";
import {
  buildMessage,
  isDeadToken,
  jwtClaims,
  sameSecret,
  type ServiceAccount,
  TOKEN_URL,
} from "./fcm.ts";

let cached: { token: string; expires: number } | null = null;

async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.expires - 60 > now) return cached.token;
  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT(jwtClaims(sa.client_email, now))
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .sign(key);
  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`oauth token: ${res.status}`);
  const json = await res.json();
  cached = { token: json.access_token, expires: now + (json.expires_in ?? 3600) };
  return cached.token;
}

function reply(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply(405, { error: "method" });
  if (!sameSecret(req.headers.get("x-pingduck-hook"), Deno.env.get("NOTIFY_SECRET"))) {
    return reply(401, { error: "unauthorized" });
  }

  let userId: string, networkId: string;
  try {
    const body = await req.json();
    userId = String(body.user_id ?? "");
    networkId = String(body.network_id ?? "");
  } catch {
    return reply(400, { error: "body" });
  }
  if (!userId || !networkId) return reply(400, { error: "body" });

  const sa: ServiceAccount = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");
  if (!sa.private_key || !sa.client_email || !sa.project_id) {
    console.error("notify-new-devices: FCM_SERVICE_ACCOUNT missing or incomplete");
    return reply(500, { error: "config" });
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
  const { data: tokens, error } = await db
    .from("push_tokens")
    .select("id, token")
    .eq("user_id", userId)
    .eq("platform", "android");
  if (error) {
    console.error("notify-new-devices: push_tokens", error.message);
    return reply(500, { error: "db" });
  }

  const bearer = await accessToken(sa);
  const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
  let sent = 0;
  const dead: string[] = [];
  const used: string[] = [];
  for (const t of tokens ?? []) {
    const res = await fetch(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: JSON.stringify(buildMessage(t.token, networkId)),
    });
    if (res.ok) {
      sent++;
      used.push(t.id);
      await res.body?.cancel();
      continue;
    }
    const body = await res.json().catch(() => null);
    if (isDeadToken(res.status, body)) {
      dead.push(t.id);
    } else {
      console.error("notify-new-devices: fcm", res.status);
    }
  }

  if (dead.length) await db.from("push_tokens").delete().in("id", dead);
  if (used.length) {
    await db.from("push_tokens").update({ last_used_at: new Date().toISOString() }).in("id", used);
  }
  return reply(200, { sent, removed: dead.length });
});
