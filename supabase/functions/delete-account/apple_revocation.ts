// Apple endpoints are fixed; no caller-controlled issuer, audience or redirect.
// Only opaque receipt/nonce hashes are persisted by the handler. Never log JWTs,
// authorization codes, client secrets or Apple refresh/access tokens.
export class AppleRevocationFailure extends Error {
  readonly code: string;
  constructor(code: string) { super(code); this.code = code; }
}
export type AppleConfiguration = {
  clientId: string;
  teamId: string;
  keyId: string;
  privateKey: string;
  redirectUri?: string;
};
const encoder = new TextEncoder();
const fail = (code = "apple_reauthorization_failed"): never => { throw new AppleRevocationFailure(code); };
function bytes(value: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) return fail();
  const decoded = atob(value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "="));
  return Uint8Array.from(decoded, (c) => c.charCodeAt(0));
}
function base64(value: Uint8Array): string {
  return btoa(String.fromCharCode(...value)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return fail();
  return value as Record<string, unknown>;
}
export async function digest(value: string): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
export function randomReceipt(): string { return base64(crypto.getRandomValues(new Uint8Array(32))); }
async function readJson(response: Response): Promise<Record<string, unknown>> {
  if (!response.ok || !response.body) return fail();
  const reader = response.body.getReader();
  let length = 0;
  const parts: Uint8Array[] = [];
  for (;;) {
    const {done, value} = await reader.read();
    if (done) break;
    length += value.length;
    if (length > 65536) { await reader.cancel(); return fail(); }
    parts.push(value);
  }
  const all = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) { all.set(part, offset); offset += part.length; }
  return object(JSON.parse(new TextDecoder().decode(all)));
}

export class AppleRevoker {
  private keys: Record<string, JsonWebKey> = Object.create(null);
  private keysExpireAt = 0;
  private lastKeyFetch = 0;
  private readonly request: typeof fetch;
  private readonly clock: () => number;
  constructor(request: typeof fetch = fetch, clock = () => Date.now()) { this.request = request; this.clock = clock; }

  private async appleFetch(url: string, init: RequestInit = {}): Promise<Response> {
    return await this.request(url, {...init, redirect: "error", signal: AbortSignal.timeout(12000)});
  }
  private async key(kid: string): Promise<JsonWebKey> {
    const now = this.clock();
    if (now >= this.keysExpireAt || !this.keys[kid]) {
      // Bounded refresh supports key rotation without fetching per bogus kid.
      if (this.lastKeyFetch && now - this.lastKeyFetch < 30000) return fail();
      this.lastKeyFetch = now;
      const data = await readJson(await this.appleFetch("https://appleid.apple.com/auth/keys"));
      if (!Array.isArray(data.keys) || data.keys.length < 1 || data.keys.length > 8) return fail();
      const keys: Record<string, JsonWebKey> = Object.create(null);
      for (const entry of data.keys) {
        const key = object(entry);
        if (key.kty !== "RSA" || key.alg !== "RS256" || key.use !== "sig" ||
          typeof key.kid !== "string" || key.kid.length > 100 ||
          typeof key.n !== "string" || typeof key.e !== "string" || keys[key.kid]) return fail();
        keys[key.kid] = key as JsonWebKey;
      }
      this.keys = keys;
      this.keysExpireAt = now + 15 * 60000;
    }
    return this.keys[kid] ?? fail();
  }
  async verifyIdentity(token: string, audience: string, subject: string, nonce?: string): Promise<void> {
    if (typeof token !== "string" || token.length > 16384) return fail();
    const segments = token.split(".");
    if (segments.length !== 3) return fail();
    const header = object(JSON.parse(new TextDecoder().decode(bytes(segments[0]))));
    const claim = object(JSON.parse(new TextDecoder().decode(bytes(segments[1]))));
    if (header.alg !== "RS256" || typeof header.kid !== "string" || header.kid.length > 100 || header.crit !== undefined) return fail();
    const key = await crypto.subtle.importKey("jwk", await this.key(header.kid), {name: "RSASSA-PKCS1-v1_5", hash: "SHA-256"}, false, ["verify"]);
    if (!await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, bytes(segments[2]), encoder.encode(segments[0] + "." + segments[1]))) return fail();
    const now = Math.floor(this.clock() / 1000);
    if (claim.iss !== "https://appleid.apple.com" || claim.aud !== audience || claim.sub !== subject ||
      !Number.isInteger(claim.exp) || Number(claim.exp) <= now || !Number.isInteger(claim.iat) ||
      Number(claim.iat) > now + 60 || Number(claim.iat) < now - 600 ||
      (nonce !== undefined && claim.nonce !== nonce)) return fail();
  }
  private async clientSecret(config: AppleConfiguration): Promise<string> {
    if (!/^[A-Z0-9]{10}$/.test(config.teamId) || !/^[A-Z0-9]{10}$/.test(config.keyId) ||
      !/^[A-Za-z0-9][A-Za-z0-9.-]{2,199}$/.test(config.clientId) || config.privateKey.length > 8192) return fail("apple_not_configured");
    const pem = config.privateKey.replace(/\\n/g, "\n").trim();
    if (!pem.startsWith("-----BEGIN PRIVATE KEY-----") || !pem.endsWith("-----END PRIVATE KEY-----")) return fail("apple_not_configured");
    const pkcs8 = Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "")), (c) => c.charCodeAt(0));
    const key = await crypto.subtle.importKey("pkcs8", pkcs8, {name: "ECDSA", namedCurve: "P-256"}, false, ["sign"]);
    const now = Math.floor(this.clock() / 1000);
    const head = base64(encoder.encode(JSON.stringify({alg: "ES256", kid: config.keyId})));
    const payload = base64(encoder.encode(JSON.stringify({iss: config.teamId, iat: now, exp: now + 300, aud: "https://appleid.apple.com", sub: config.clientId})));
    const input = head + "." + payload;
    return input + "." + base64(new Uint8Array(await crypto.subtle.sign({name: "ECDSA", hash: "SHA-256"}, key, encoder.encode(input))));
  }
  async revoke(config: AppleConfiguration, input: {code: string; identityToken: string; subject: string; nonceHash: string}): Promise<void> {
    if (!input.code || input.code.length > 4096 || !/^[a-f0-9]{64}$/.test(input.nonceHash)) return fail();
    await this.verifyIdentity(input.identityToken, config.clientId, input.subject, input.nonceHash);
    const secret = await this.clientSecret(config);
    const form = new URLSearchParams({client_id: config.clientId, client_secret: secret, code: input.code, grant_type: "authorization_code"});
    if (config.redirectUri) form.set("redirect_uri", config.redirectUri);
    const token = await readJson(await this.appleFetch("https://appleid.apple.com/auth/token", {
      method: "POST", headers: {"Content-Type": "application/x-www-form-urlencoded"}, body: form,
    }));
    if (typeof token.id_token !== "string" || typeof token.refresh_token !== "string" || !token.refresh_token || token.refresh_token.length > 16384) return fail();
    // A correct nonce token cannot be paired with a code for another Apple ID.
    await this.verifyIdentity(token.id_token, config.clientId, input.subject);
    const response = await this.appleFetch("https://appleid.apple.com/auth/revoke", {
      method: "POST", headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: new URLSearchParams({client_id: config.clientId, client_secret: secret, token: token.refresh_token, token_type_hint: "refresh_token"}),
    });
    if (response.status !== 200) return fail("apple_revocation_failed");
    // Apple explicitly defines a 200 empty body as success/idempotent revocation.
  }
}
