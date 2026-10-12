import { assert, assertEquals } from "jsr:@std/assert@1";
import { buildMessage, FCM_SCOPE, isDeadToken, jwtClaims, sameSecret, TOKEN_URL } from "./fcm.ts";

Deno.test("the message is data-only, high priority, string values", () => {
  const { message } = buildMessage("tok", "net-1");
  assert(!("notification" in message));
  assertEquals(message.android.priority, "HIGH");
  assertEquals(message.data, { kind: "new_devices", network_id: "net-1" });
  for (const v of Object.values(message.data)) assertEquals(typeof v, "string");
});

Deno.test("jwt claims ask for the messaging scope for an hour", () => {
  const c = jwtClaims("svc@x.iam.gserviceaccount.com", 1000);
  assertEquals(c.scope, FCM_SCOPE);
  assertEquals(c.aud, TOKEN_URL);
  assertEquals(c.exp - c.iat, 3600);
});

Deno.test("dead tokens are 404 or UNREGISTERED only", () => {
  assert(isDeadToken(404, null));
  assert(isDeadToken(400, { error: { details: [{ errorCode: "UNREGISTERED" }] } }));
  assert(!isDeadToken(500, { error: { details: [{ errorCode: "INTERNAL" }] } }));
  assert(!isDeadToken(429, null));
});

Deno.test("the hook secret must match exactly and not be empty", () => {
  assert(sameSecret("abc", "abc"));
  assert(!sameSecret("abc", "abd"));
  assert(!sameSecret("abc", "abcd"));
  assert(!sameSecret(null, "abc"));
  assert(!sameSecret("", ""));
  assert(!sameSecret("abc", undefined));
});
