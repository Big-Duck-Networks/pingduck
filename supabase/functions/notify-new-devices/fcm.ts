// FCM HTTP v1 helpers for notify-new-devices. Kept free of I/O so they can
// be unit-tested with `deno test`.

import { jwtClaims as googleClaims } from "../_shared/google.ts";

export { type ServiceAccount, TOKEN_URL } from "../_shared/google.ts";
export const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

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

// Claims for the OAuth JWT-bearer assertion that buys an FCM access token.
export function jwtClaims(clientEmail: string, nowSeconds: number) {
  return googleClaims(clientEmail, FCM_SCOPE, nowSeconds);
}

// True when FCM says the token will never work again, so it should be
// deleted rather than retried.
export function isDeadToken(status: number, body: unknown): boolean {
  if (status === 404) return true;
  const details = (body as { error?: { details?: { errorCode?: string }[] } })
    ?.error?.details ?? [];
  return details.some((d) => d.errorCode === "UNREGISTERED");
}

export { sameSecret } from "../_shared/secret.ts";
