// FCM HTTP v1 helpers for notify-new-devices. Kept free of I/O so they can
// be unit-tested with `deno test`.

export const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
export const TOKEN_URL = "https://oauth2.googleapis.com/token";

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

// A data-only message: no `notification` block, so Google never sees any
// text and the app decides what to show after fetching the details itself.
// HIGH priority wakes the app from Doze; the alert is stale after 10 min.
export function buildMessage(token: string, networkId: string) {
  return {
    message: {
      token,
      data: { kind: "new_devices", network_id: networkId },
      android: { priority: "HIGH", ttl: "600s" },
    },
  };
}

// Claims for the OAuth JWT-bearer assertion that buys an access token.
export function jwtClaims(clientEmail: string, nowSeconds: number) {
  return {
    iss: clientEmail,
    scope: FCM_SCOPE,
    aud: TOKEN_URL,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  };
}

// True when FCM says the token will never work again, so it should be
// deleted rather than retried.
export function isDeadToken(status: number, body: unknown): boolean {
  if (status === 404) return true;
  const details = (body as { error?: { details?: { errorCode?: string }[] } })
    ?.error?.details ?? [];
  return details.some((d) => d.errorCode === "UNREGISTERED");
}

// Constant-time string comparison for the hook secret.
export function sameSecret(a: string | null, b: string | undefined): boolean {
  if (a == null || b == null || b.length === 0) return false;
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  }
  return diff === 0;
}
