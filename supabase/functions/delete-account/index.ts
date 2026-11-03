// Night Owl UB — Данс бүрмөсөн устгах (service role)
// Auth устгалын FK cascade-ийг live schema дээр тусад нь баталгаажуулна.
// Storage API cleanup болон Auth устгал нэг transaction биш.
// Apple grant revoke бэлэн болтол Apple-linked account-ыг устгахгүй.
// ACCOUNT_DELETION_ENABLED=true-г staging/recovery шалгалтын дараа л тохируулна.
//
// Deploy:  supabase functions deploy delete-account
// (SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY автоматаар
//  edge function-д тарьдаг — тусдаа тохируулах шаардлагагүй.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: cors });
  }

  if (Deno.env.get("ACCOUNT_DELETION_ENABLED") !== "true") {
    return json({ error: "Account deletion unavailable", code: "deletion_unavailable" }, 503);
  }

  let cleanupStarted = false;
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !/^Bearer\s+\S+$/i.test(authHeader)) {
      return json({ error: "Unauthorized" }, 401);
    }

    // 1) Дуудаж буй хэрэглэгчийг JWT-ээр тодорхойлох
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user || typeof user.id !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(user.id)) {
      return json({ error: "Unauthorized" }, 401);
    }
    let body;
    try {
      body = await req.json();
    } catch {
      return json({ error: "Confirmation required", code: "confirmation_required" }, 400);
    }
    if (body?.confirmation !== "DELETE") {
      return json({ error: "Confirmation required", code: "confirmation_required" }, 400);
    }
    if (user.identities?.some((identity) => identity.provider === "apple") ||
      user.app_metadata?.provider === "apple" ||
      user.app_metadata?.providers?.includes("apple")) {
      return json({ error: "Apple revocation required", code: "apple_revocation_required" }, 409);
    }

    // 2) Build every cleanup plan before making any irreversible request.
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const plans: { bucket: string; paths: string[] }[] = [];
    for (const bucket of ["avatars", "posts", "stories", "venues"]) {
      const paths: string[] = [];
      const visited = new Set<string>();
      async function collect(prefix: string, depth = 0): Promise<void> {
        if (depth > 8) throw new Error("Storage cleanup requires support");
        for (let offset = 0; ; offset += 100) {
          const { data, error } = await admin.storage.from(bucket)
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
      plans.push({ bucket, paths });
    }
    // Storage ownership can prevent Auth deletion. Retrying re-lists what remains;
    // failures after this point cannot promise rollback across Storage and Auth.
    for (const { bucket, paths } of plans) {
      for (let index = 0; index < paths.length; index += 100) {
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
      const { data, error } = await admin.storage.from(bucket)
        .list(user.id, { limit: 100, offset: 0, sortBy: { column: "name", order: "asc" } });
      if (error) throw error;
      if (!Array.isArray(data) || data.length !== 0) {
        throw new Error("Storage cleanup could not be confirmed");
      }
    }
    cleanupStarted = true;
    const { data: deleted, error } = await admin.auth.admin.deleteUser(user.id, false);
    if (error) throw error;
    if (deleted?.user?.id !== user.id) throw new Error("Invalid account deletion response");

    return json({ ok: true, user_id: user.id });
  } catch {
    return json({ error: "Account deletion failed",
      code: cleanupStarted ? "deletion_incomplete" : "deletion_failed",
      cleanup_started: cleanupStarted }, 500);
  }
});
