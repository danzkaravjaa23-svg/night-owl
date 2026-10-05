// Night Owl UB — Данс бүрмөсөн устгах (service role)
// auth.users мөрийг устгаснаар FK cascade-ээр profiles + бүх контент устана,
// posts устахад storage trigger файлуудыг цэвэрлэнэ.
//
// Deploy:  supabase functions deploy delete-account
// (SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY автоматаар
//  edge function-д тарьдаг — тусдаа тохируулах шаардлагагүй.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: cors });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...cors, "Content-Type": "application/json" } });
    }

    // 1) Дуудаж буй хэрэглэгчийг JWT-ээр тодорхойлох
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...cors, "Content-Type": "application/json" } });
    }

    // 2) Service role-оор auth хэрэглэгчийг устгах → бүх дата cascade-ээр устана
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    // Remove only this authenticated user's storage prefix before auth deletion.
    // Storage ownership can otherwise prevent deleting auth.users.
    for (const bucket of ["avatars", "posts", "stories", "venues"]) {
      const paths: string[] = [];
      async function collect(prefix: string, depth = 0): Promise<void> {
        if (depth > 8 || paths.length > 20000) throw new Error("Storage cleanup requires support");
        for (let offset = 0; ; offset += 100) {
          const { data, error } = await admin.storage.from(bucket)
            .list(prefix, { limit: 100, offset, sortBy: { column: "name", order: "asc" } });
          if (error) throw error;
          for (const entry of data ?? []) {
            const path = `${prefix}/${entry.name}`;
            if (entry.id == null) await collect(path, depth + 1);
            else paths.push(path);
          }
          if ((data?.length ?? 0) < 100) break;
        }
      }
      await collect(user.id);
      for (let index = 0; index < paths.length; index += 100) {
        const { error } = await admin.storage.from(bucket).remove(paths.slice(index, index + 100));
        if (error) throw error;
      }
    }
    const { error } = await admin.auth.admin.deleteUser(user.id);
    if (error) {
      return new Response(JSON.stringify({ error: error.message }),
        { status: 500, headers: { ...cors, "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({ ok: true }),
      { headers: { ...cors, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } });
  }
});
