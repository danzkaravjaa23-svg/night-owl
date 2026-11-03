// Real Deno + pinned Supabase SDK, backed only by a loopback HTTP double.
const owner = "10000000-0000-0000-0000-000000000001";
const other = "10000000-0000-0000-0000-000000000002";
const buckets = ["avatars", "posts", "stories", "venues"];

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status, headers: { "Content-Type": "application/json" },
  });
}

Deno.test("delete-account: actual SDK HTTP contract without live data", async (t) => {
  let calls: { path: string; method: string }[] = [];
  const files = new Map<string, string[]>();
  let failure = "";
  let apple = false;
  let authAbsent = false;
  let job: Record<string, unknown> = {state: null};
  const api = Deno.serve({ hostname: "127.0.0.1", port: 0, onListen() {} }, async (req) => {
    const path = new URL(req.url).pathname;
    calls.push({ path, method: req.method });
    const user = { id: owner, aud: "authenticated", created_at: "2026-10-22T00:00:00Z",
      identities: apple ? [{ provider: "apple" }] : [], app_metadata: {} };
    if (path === "/auth/v1/user") {
      return req.headers.get("Authorization") === "Bearer fixture-user-session"
        ? json(user) : json({ message: "Invalid fixture token" }, 401);
    }
    assert(req.headers.get("Authorization") === "Bearer fixture-service", "Admin bearer must stay server-only");
    if (path === "/rest/v1/rpc/account_erasure_control") {
      const body = await req.json();
      if (body.p_action === "storage_inventory") return json({objects: []});
      if (body.p_action === "lookup") return json(job);
      if (body.p_action === "prepare") job = {user_id: owner, state: "prepared"};
      if (body.p_action === "claim") job.state = "running";
      if (body.p_action === "completed") {
        if (!authAbsent) return json({code: "22023", message: "Auth row still exists"}, 400);
        job.state = "completed";
      }
      if (body.p_action === "failed") job.state = "failed";
      return json(job);
    }
    if (path.startsWith("/storage/v1/object/list/")) {
      const bucket = path.split("/").at(-1)!;
      assert(buckets.includes(bucket), "Unexpected bucket");
      const body = await req.json();
      assert(body.prefix === owner && body.limit === 100, "List must stay caller-scoped");
      if (failure === "malformed-list") return json(null);
      if (failure === "verify-list" && calls.some((call) => call.method === "DELETE")) {
        return json({ message: "fixture-private-verification-error" }, 503);
      }
      if (failure === `${bucket}-list`) return json({ message: "fixture-private-storage-error" }, 403);
      return json((files.get(bucket) ?? []).slice(body.offset, body.offset + body.limit)
        .map((name) => ({ id: name, name })));
    }
    if (path.startsWith("/storage/v1/object/") && req.method === "DELETE") {
      const bucket = path.split("/").at(-1)!;
      const body = await req.json();
      assert(Array.isArray(body.prefixes) && body.prefixes.every((p: string) => p.startsWith(`${owner}/`)), "Remove must stay caller-scoped");
      if (failure === `${bucket}-remove`) return json({ message: "fixture-private-remove-error" }, 403);
      if (failure === "malformed-remove") return json(null);
      if (failure === "noop-remove") return json([]);
      files.set(bucket, (files.get(bucket) ?? []).filter((name) => !body.prefixes.includes(`${owner}/${name}`)));
      return json([]);
    }
    if (path === `/auth/v1/admin/users/${owner}` && req.method === "DELETE") {
      const body = await req.json();
      assert(body.should_soft_delete === false, "Account erasure must not silently become soft deletion");
      if (failure === "malformed-auth-delete") return json({});
      if (failure === "wrong-auth-delete") return json({ ...user, id: other });
      authAbsent = true;
      if (failure === "minimal-auth-delete") return json({message: "User deleted"});
      return json(user);
    }
    return json({ message: "Unexpected loopback API path" }, 404);
  });

  Deno.env.set("SUPABASE_URL", `http://127.0.0.1:${api.addr.port}`);
  Deno.env.set("SUPABASE_ANON_KEY", "fixture-anon");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fixture-service");
  let handler: ((request: Request) => Promise<Response>) | undefined;
  const descriptor = Object.getOwnPropertyDescriptor(Deno, "serve")!;
  try {
    // Capture the production entry point instead of opening its public listener.
    Object.defineProperty(Deno, "serve", { configurable: descriptor.configurable,
      enumerable: descriptor.enumerable, writable: true, value: (value: typeof handler) => {
      handler = value;
      return {};
    } });
    try {
      await import("../index.ts");
    } finally {
      Object.defineProperty(Deno, "serve", descriptor);
    }
    assert(handler, "Production entry point was not captured");
    const invoke = (body: unknown = { confirmation: "DELETE" }, token = "fixture-user-session") => handler!(
      new Request("http://127.0.0.1/delete-account", { method: "POST",
        headers: token ? { Authorization: `Bearer ${token}` } : {}, body: JSON.stringify(body) }));
    const step = async (name: string, run: () => Promise<void>) => {
      calls = [];
      files.clear();
      files.set("avatars", ["avatar.jpg"]);
      files.set("posts", ["post.jpg"]);
      failure = "";
      apple = false;
      authAbsent = false;
      job = {state: null};
      Deno.env.set("ACCOUNT_DELETION_ENABLED", "true");
      await t.step(name, run);
    };

    await step("disabled endpoint makes no SDK HTTP calls", async () => {
      Deno.env.delete("ACCOUNT_DELETION_ENABLED");
      assert((await invoke()).status === 503, "Missing enable flag must block deletion");
      assert(calls.length === 0, "Disabled endpoint must not call Auth/Storage");
    });
    await step("missing and invalid bearer cannot reach admin APIs", async () => {
      assert((await invoke(undefined, "")).status === 401, "Missing JWT must be rejected");
      assert((await invoke(undefined, "invalid")).status === 401, "Invalid JWT must be rejected");
      assert(calls.every((call) => call.path === "/auth/v1/user"), "Invalid caller reached privileged APIs");
    });
    await step("confirmation is required before privileged APIs", async () => {
      assert((await invoke({})).status === 400, "Confirmation must be explicit");
      assert(calls.every((call) => call.path === "/auth/v1/user"), "Unconfirmed call reached privileged APIs");
    });
    await step("Apple-linked account remains blocked before cleanup", async () => {
      apple = true;
      const response = await invoke();
      assert(response.status === 409 && (await response.json()).code === "apple_revocation_required", "Apple grant cannot be skipped");
      assert(calls.every((call) => call.path === "/auth/v1/user"), "Apple account reached cleanup");
    });
    await step("valid caller uses real SDK list/remove/hard-delete contracts", async () => {
      const response = await invoke({ confirmation: "DELETE", user_id: other });
      const result = await response.json();
      assert(response.status === 200 && result.ok === true && result.user_id === owner, "Wrong deletion result");
      assert(response.headers.get("Cache-Control") === "no-store", "Owner response must not be cached");
      const lists = calls.filter((call) => call.path.includes("/object/list/"));
      assert(lists.length === 8, "Every bucket must be checked before and after cleanup");
      assert(calls.slice(0, calls.findIndex((call) => call.method === "DELETE"))
        .filter((call) => call.path.includes("/object/list/")).length === 4, "Cleanup began before enumeration completed");
      assert(calls.filter((call) => !call.path.startsWith("/rest/v1/rpc/")).at(-1)?.path === `/auth/v1/admin/users/${owner}`, "Auth hard delete must be last destructive operation and caller-only");
    });
    await step("minimal real GoTrue acknowledgement requires authoritative Auth-row absence", async () => {
      failure = "minimal-auth-delete";
      const response = await invoke();
      const result = await response.json();
      assert(response.status === 200 && result.ok === true && result.user_id === owner, "Minimal acknowledgement was not reconciled through server absence");
      assert(calls.some(call => call.path === "/rest/v1/rpc/account_erasure_control"), "Missing completion invariant");
    });
    await step("late listing failure leaves all media untouched", async () => {
      failure = "posts-list";
      const response = await invoke();
      const result = await response.json();
      assert(response.status === 500 && result.code === "deletion_failed" && result.cleanup_started === false, "Unexpected failure phase");
      assert(!calls.some((call) => call.method === "DELETE"), "Listing failure deleted media");
      assert(files.get("avatars")?.length === 1, "Avatar disappeared before preflight finished");
    });
    await step("malformed successful Storage response cannot authorize erasure", async () => {
      failure = "malformed-list";
      const response = await invoke();
      const result = await response.json();
      assert(response.status === 500 && result.code === "deletion_failed", "Invalid listing was treated as empty");
      assert(!calls.some((call) => call.method === "DELETE"), "Malformed listing reached destructive APIs");
    });
    for (const mode of ["malformed-remove", "noop-remove", "verify-list"]) {
      await step(`${mode} prevents Auth erasure after incomplete cleanup`, async () => {
        failure = mode;
        const response = await invoke();
        const result = await response.json();
        assert(response.status === 500 && result.code === "deletion_incomplete", "Unverified cleanup looked successful");
        assert(!calls.some((call) => call.path.includes("/admin/users/")), "Unverified cleanup reached Auth deletion");
      });
    }
    for (const mode of ["malformed-auth-delete", "wrong-auth-delete"]) {
      await step(`${mode} cannot report a confirmed account erasure`, async () => {
        failure = mode;
        const response = await invoke();
        const result = await response.json();
        assert(response.status === 500 && result.code === "deletion_incomplete", "Invalid Auth response looked successful");
        assert(calls.filter((call) => !call.path.startsWith("/rest/v1/rpc/")).at(-1)?.path === `/auth/v1/admin/users/${owner}`, "Only the caller can be erased");
      });
    }
    await step("partial cleanup is explicit and a deliberate retry resumes", async () => {
      failure = "posts-remove";
      const first = await invoke();
      const result = await first.json();
      assert(first.status === 500 && result.code === "deletion_incomplete" && result.cleanup_started === true, "Partial cleanup must not look successful");
      assert(!calls.some((call) => call.path.includes("/admin/users/")), "Failed cleanup reached Auth deletion");
      assert(!JSON.stringify(result).includes("fixture-private"), "Internal API error leaked");
      failure = "";
      assert((await invoke()).status === 200, "Retry must handle already removed media");
      assert(calls.filter((call) => call.path.endsWith("/avatars") && call.method === "DELETE").length === 1, "Retry re-deleted the removed avatar");
    });
  } finally {
    Object.defineProperty(Deno, "serve", descriptor);
    await api.shutdown();
  }
});
