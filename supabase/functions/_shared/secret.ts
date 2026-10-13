// Constant-time string comparison for shared secrets (hook and webhook
// headers). An unset or empty expected value never matches.
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
