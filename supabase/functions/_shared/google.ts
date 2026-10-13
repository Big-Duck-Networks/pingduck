// Google service-account access tokens (OAuth JWT-bearer grant), shared by
// the functions that call Google APIs: FCM for alerts, the Play Developer
// API for subscriptions. Tokens are cached per scope until a minute before
// they expire.

import { importPKCS8, SignJWT } from "npm:jose@5";

export const TOKEN_URL = "https://oauth2.googleapis.com/token";

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

// Claims for the assertion that buys an access token for one scope.
export function jwtClaims(clientEmail: string, scope: string, nowSeconds: number) {
  return {
    iss: clientEmail,
    scope,
    aud: TOKEN_URL,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  };
}

const cache = new Map<string, { token: string; expires: number }>();

export async function accessToken(sa: ServiceAccount, scope: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const key = `${sa.client_email} ${scope}`;
  const hit = cache.get(key);
  if (hit && hit.expires - 60 > now) return hit.token;
  const assertion = await new SignJWT(jwtClaims(sa.client_email, scope, now))
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .sign(await importPKCS8(sa.private_key, "RS256"));
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
  cache.set(key, { token: json.access_token, expires: now + (json.expires_in ?? 3600) });
  return json.access_token;
}

// A service-account JSON from an env var, or null if it's missing a field.
export function serviceAccountFrom(raw: string | undefined): ServiceAccount | null {
  try {
    const sa = JSON.parse(raw ?? "");
    return sa?.private_key && sa?.client_email && sa?.project_id ? sa : null;
  } catch {
    return null;
  }
}
