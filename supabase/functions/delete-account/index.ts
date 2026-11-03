// Deploy/enable only after isolated and hosted staging validation. Never test
// erasure against an existing production user. Secrets remain server-only.
import { createClient, type SupabaseClient, type User } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { AppleRevoker, AppleRevocationFailure, digest, randomReceipt, type AppleConfiguration } from "./apple_revocation.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {status, headers: {...cors, "Content-Type": "application/json", "Cache-Control": "no-store"}});
}
const apple = new AppleRevoker();
const boundedFetch: typeof fetch = (input, init) => fetch(input, {...init, signal: AbortSignal.timeout(15000)});
const uuid = (value: unknown): value is string => typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const receipt = (value: unknown): value is string => typeof value === "string" && /^[A-Za-z0-9_-]{43}$/.test(value);
function appleCheckpointCurrent(state: Record<string, unknown>, user: User): boolean {
  const revoked = Date.parse(String(state.apple_revoked_at ?? ""));
  const signedIn = Date.parse(user.last_sign_in_at ?? "");
  const identities = user.identities?.filter((identity) => identity.provider === "apple") ?? [];
  return Number.isFinite(revoked) && Number.isFinite(signedIn) && signedIn <= revoked && identities.length > 0 &&
    identities.every((identity) => identity.identity_data?.sub === state.apple_subject &&
      (!identity.last_sign_in_at || Date.parse(identity.last_sign_in_at) <= revoked));
}
function appleConfiguration(platform: string): AppleConfiguration {
  const clientId = Deno.env.get(platform === "web" ? "APPLE_WEB_CLIENT_ID" : "APPLE_CLIENT_ID") ?? "";
  const redirectUri = platform === "web" ? Deno.env.get("APPLE_WEB_REDIRECT_URI") : undefined;
  if (!clientId || (platform === "web" && (!redirectUri || new URL(redirectUri).protocol !== "https:"))) {
    throw new AppleRevocationFailure("apple_not_configured");
  }
  const config = {clientId, redirectUri, teamId: Deno.env.get("APPLE_TEAM_ID") ?? "", keyId: Deno.env.get("APPLE_KEY_ID") ?? "", privateKey: Deno.env.get("APPLE_PRIVATE_KEY") ?? ""};
  if (!config.teamId || !config.keyId || !config.privateKey) throw new AppleRevocationFailure("apple_not_configured");
  return config;
}
async function requestBody(req: Request): Promise<Record<string, unknown>> {
  const length = req.headers.get("Content-Length");
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > 32768)) throw new Error("Invalid body length");
  if (!req.body) throw new Error("Missing body");
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const {done, value} = await reader.read();
    if (done) break;
    size += value.length;
    if (size > 32768) { await reader.cancel(); throw new Error("Body too large"); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  const value = JSON.parse(new TextDecoder().decode(bytes));
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid body");
  return value;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", {headers: cors});
  if (req.method !== "POST") return new Response("Method not allowed", {status: 405, headers: cors});
  if (Deno.env.get("ACCOUNT_DELETION_ENABLED") !== "true") return json({error: "Account deletion unavailable", code: "deletion_unavailable"}, 503);
  let cleanupStarted = false;
  let claimed = false;
  let admin: SupabaseClient | undefined;
  let userId: string | undefined;
  let receiptHash: string | undefined;
  const lease = crypto.randomUUID();
  async function control(action: string, extra: Record<string, unknown> = {}): Promise<Record<string, unknown>> {
    const {data, error} = await admin!.rpc("account_erasure_control", {p_action: action, p_user: userId ?? null, p_receipt_hash: receiptHash ?? null, p_lease: lease, ...extra});
    if (error) throw error;
    if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("Invalid erasure journal response");
    return data;
  }
  try {
    let body: Record<string, unknown>;
    try {
      body = await requestBody(req);
    } catch { return json({error: "Confirmation required", code: "confirmation_required"}, 400); }
    if (body.confirmation !== "DELETE") return json({error: "Confirmation required", code: "confirmation_required"}, 400);
    const action = body.action ?? "delete";
    if (!["prepare", "delete", "status"].includes(String(action))) return json({error: "Invalid action", code: "confirmation_required"}, 400);
    if (body.action !== undefined && action !== "prepare" && !receipt(body.receipt_token)) return json({error: "Invalid erasure receipt", code: "confirmation_required"}, 400);
    // Recovery is capability-bound to a random 256-bit receipt, not a supplied
    // user ID or an expired/deleted Auth session. It can only inspect/reconcile
    // completion; it cannot start deleting an account.
    if (action === "status") {
      receiptHash = await digest(body.receipt_token as string);
      admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {global: {fetch: boundedFetch}, auth: {persistSession: false, autoRefreshToken: false}});
      const state = await control("reconcile");
      if (state.state === "completed" && uuid(state.user_id)) return json({ok: true, user_id: state.user_id});
      return json({ok: false, processing: state.state === "running", code: "deletion_incomplete"}, 202);
    }
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !/^Bearer\s+\S+$/i.test(authHeader)) return json({error: "Unauthorized"}, 401);
    const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: {headers: {Authorization: authHeader}, fetch: boundedFetch}, auth: {persistSession: false, autoRefreshToken: false},
    });
    const {data: {user}, error: authError} = await userClient.auth.getUser();
    if (authError || !user || !uuid(user.id)) return json({error: "Unauthorized"}, 401);
    userId = user.id;
    const identities = user.identities?.filter((identity) => identity.provider === "apple") ?? [];
    const appleLinked = identities.length > 0 || user.app_metadata?.provider === "apple" || user.app_metadata?.providers?.includes("apple");
    // Compatibility for old clients: a missing proof is still fail-closed.
    // New clients use prepare -> reauthorize -> delete and can complete it.
    if (appleLinked && body.action === undefined) return json({error: "Apple reauthorization required", code: "apple_revocation_required"}, 409);
    admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {global: {fetch: boundedFetch}, auth: {persistSession: false, autoRefreshToken: false}});
    let state: Record<string, unknown>;
    if (action === "prepare" || body.action === undefined) {
      const previous = await control("lookup");
      const knownSubjects = identities.map((identity) => identity.identity_data?.sub).filter((value) => typeof value === "string" && value.length > 0);
      // A checkpoint for one Apple ID cannot authorize erasure after another
      // Apple identity is linked through the separate Auth API.
      const previousSubject = typeof previous.apple_subject === "string" ? previous.apple_subject : undefined;
      const subject = knownSubjects.includes(previousSubject) ? previousSubject : knownSubjects[0] ?? previousSubject;
      const needsApple = appleLinked || (previousSubject != null && previous.apple_revoked_at == null);
      const alreadyRevoked = subject === previousSubject && appleCheckpointCurrent(previous, user);
      const platform = body.client_platform === "web" ? "web" : "native";
      const nonce = needsApple && !alreadyRevoked ? randomReceipt() : undefined;
      if (needsApple && !alreadyRevoked && typeof subject !== "string") return json({error: "Apple identity unavailable", code: "apple_identity_unavailable"}, 409);
      const config = nonce ? appleConfiguration(platform) : undefined;
      const token = randomReceipt();
      receiptHash = await digest(token);
      state = await control("prepare", {p_nonce_hash: nonce ? await digest(nonce) : null, p_audience: config?.clientId ?? null, p_subject: subject ?? null});
      if (action === "prepare") return json({ok: true, user_id: userId, receipt_token: token,
        apple_required: !!nonce, ...(nonce ? {nonce, client_id: config!.clientId, redirect_uri: config!.redirectUri ?? null} : {})});
    } else {
      receiptHash = await digest(body.receipt_token as string);
      state = await control("status");
    }
    if (state.user_id !== userId) throw new Error("Erasure owner mismatch");
    if (state.state === "completed") return json({ok: true, user_id: userId});
    let config: AppleConfiguration | undefined;
    if (appleLinked && state.apple_revoked_at != null && !appleCheckpointCurrent(state, user)) {
      return json({error: "Apple identity changed", code: "apple_reauthorization_required"}, 409);
    }
    if ((appleLinked || state.apple_subject != null) && state.apple_revoked_at == null) {
      const subjects = identities.map((identity) => identity.identity_data?.sub);
      if (typeof state.apple_subject !== "string" || (subjects.length > 0 && !subjects.includes(state.apple_subject)) ||
        typeof state.nonce_hash !== "string" || typeof state.nonce_expires_at !== "string" || !Number.isFinite(Date.parse(state.nonce_expires_at)) || Date.parse(state.nonce_expires_at) <= Date.now() ||
        typeof body.apple_code !== "string" || typeof body.apple_identity_token !== "string") {
        return json({error: "Apple reauthorization required", code: "apple_reauthorization_required"}, 409);
      }
      config = appleConfiguration(body.client_platform === "web" ? "web" : "native");
      if (config.clientId !== state.apple_audience) throw new AppleRevocationFailure("apple_reauthorization_failed");
      await apple.verifyIdentity(body.apple_identity_token, config.clientId, state.apple_subject, state.nonce_hash);
    }
    await control("claim");
    claimed = true;
    if (config) {
      await apple.revoke(config, {code: body.apple_code as string, identityToken: body.apple_identity_token as string,
        subject: state.apple_subject as string, nonceHash: state.nonce_hash as string});
      cleanupStarted = true;
      // The irreversible provider step has its own durable checkpoint. Later
      // retries skip reauthorization/revocation once this marker commits.
      state = await control("apple_revoked");
    }
    const plans: { bucket: string; paths: string[] }[] = [];
    const owned = await control("storage_inventory");
    if (!Array.isArray(owned.objects)) throw new Error("Invalid ownership inventory");
    const legacyPaths = new Map<string, Set<string>>();
    for (const entry of owned.objects) {
      if (!entry || typeof entry !== "object" || !["avatars", "posts", "stories", "venues"].includes(entry.bucket_id) ||
        typeof entry.name !== "string" || !entry.name || entry.name.includes("\\") || entry.name.split("/").some((part: string) => !part || part === "." || part === "..")) throw new Error("Unreviewed legacy Storage ownership");
      const paths = legacyPaths.get(entry.bucket_id) ?? new Set<string>();
      if (paths.size >= 20000 || paths.has(entry.name)) throw new Error("Invalid legacy Storage inventory");
      paths.add(entry.name);
      legacyPaths.set(entry.bucket_id, paths);
    }
    for (const bucket of ["avatars", "posts", "stories", "venues"]) {
      const paths: string[] = [];
      const visited = new Set<string>();
      async function collect(prefix: string, depth = 0): Promise<void> {
        if (depth > 8) throw new Error("Storage cleanup requires support");
        for (let offset = 0; ; offset += 100) {
          await control("renew");
          const { data, error } = await admin!.storage.from(bucket)
            .list(prefix, { limit: 100, offset, sortBy: { column: "name", order: "asc" } });
          if (error) throw error;
          // An unexpected SDK/proxy response is not evidence of an empty
          // directory. Never proceed to Auth erasure with an incomplete plan.
          if (!Array.isArray(data) || data.length > 100) {
            throw new Error("Invalid storage listing");
          }
          for (const entry of data) {
            if (!entry || typeof entry.name !== "string" ||
              !entry.name || entry.name === "." || entry.name === ".." ||
              /[\\/]/.test(entry.name)) throw new Error("Invalid storage entry");
            const path = `${prefix}/${entry.name}`;
            // Bound folders as well as files, and reject repeating pages.
            if (visited.has(path) || visited.size >= 30000) {
              throw new Error("Storage cleanup requires support");
            }
            visited.add(path);
            if (entry.id == null) await collect(path, depth + 1);
            else {
              if (typeof entry.id !== "string" || !entry.id) {
                throw new Error("Invalid storage object");
              }
              if (paths.length >= 20000) throw new Error("Storage cleanup requires support");
              paths.push(path);
            }
          }
          if (data.length < 100) break;
        }
      }
      await collect(user.id);
      // Metadata ownership, never a caller's media URL, proves scope for
      // historical files outside the modern UUID-prefix convention.
      const seenPaths = new Set(paths);
      for (const path of legacyPaths.get(bucket) ?? []) {
        if (!seenPaths.has(path)) { paths.push(path); seenPaths.add(path); }
      }
      if (paths.length > 20000) throw new Error("Storage cleanup requires support");
      plans.push({ bucket, paths });
    }
    // Storage ownership can prevent Auth deletion. Retrying re-lists what remains;
    // failures after this point cannot promise rollback across Storage and Auth.
    for (const { bucket, paths } of plans) {
      for (let index = 0; index < paths.length; index += 100) {
        await control("renew");
        cleanupStarted = true;
        const { data, error } = await admin.storage.from(bucket).remove(paths.slice(index, index + 100));
        if (error) throw error;
        if (!Array.isArray(data)) throw new Error("Invalid storage removal response");
      }
    }
    // A successful remove can be an idempotent no-op. Confirm that nothing
    // remains (including uploads observed since enumeration) before Auth erasure.
    // This is a final check, not a lock against later concurrent uploads.
    for (const { bucket } of plans) {
      await control("renew");
      const { data, error } = await admin.storage.from(bucket)
        .list(user.id, { limit: 100, offset: 0, sortBy: { column: "name", order: "asc" } });
      if (error) throw error;
      if (!Array.isArray(data) || data.length !== 0) {
        throw new Error("Storage cleanup could not be confirmed");
      }
    }
    const remaining = await control("storage_inventory");
    if (!Array.isArray(remaining.objects) || remaining.objects.length !== 0) throw new Error("Owned Storage objects remain");
    await control("storage_cleared");
    cleanupStarted = true;
    await control("cleanup");
    await control("renew");
    // Supabase Auth linking is a separate service and does not take our DB
    // profile lock. Re-check immediately before erasure; a new Apple identity
    // needs its own bound reauthorization/revocation. This narrows, but cannot
    // claim atomicity across, the Auth/provider/Storage service boundary.
    const {data: fresh, error: freshError} = await userClient.auth.getUser();
    if (freshError || fresh.user?.id !== user.id) throw new Error("Account authentication changed");
    const currentApple = fresh.user.identities?.filter((identity) => identity.provider === "apple") ?? [];
    const revokedSubject = state.apple_subject;
    if (currentApple.some((identity) => typeof identity.identity_data?.sub !== "string" || identity.identity_data.sub !== revokedSubject) ||
      (currentApple.length > 0 && !appleCheckpointCurrent(state, fresh.user)) ||
      (currentApple.length === 0 && (fresh.user.app_metadata?.provider === "apple" || fresh.user.app_metadata?.providers?.includes("apple")))) {
      throw new AppleRevocationFailure("apple_reauthorization_required");
    }
    cleanupStarted = true;
    const {data: deleted, error} = await admin.auth.admin.deleteUser(user.id, false);
    if (error) throw error;
    if (deleted?.user?.id !== user.id) throw new Error("Invalid account deletion response");
    await control("completed");
    return json({ok: true, user_id: user.id});
  } catch (error) {
    if (claimed) { try { await control("failed"); } catch { /* A newer worker may own the lease. */ } }
    if (error instanceof AppleRevocationFailure) return json({error: "Apple reauthorization unavailable", code: error.code, cleanup_started: cleanupStarted}, error.code === "apple_not_configured" ? 503 : 409);
    if (error && typeof error === "object" && "code" in error && error.code === "55P03") return json({error: "Erasure already running", code: "deletion_busy"}, 409);
    if (error && typeof error === "object" && "code" in error && error.code === "P0002") return json({error: "Erasure receipt unavailable", code: "deletion_unavailable"}, 404);
    return json({error: "Account deletion failed", code: cleanupStarted ? "deletion_incomplete" : "deletion_failed", cleanup_started: cleanupStarted}, 500);
  }
});
