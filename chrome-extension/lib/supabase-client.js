/**
 * NightOwl Admin — Lightweight Supabase REST client
 * supabase-js bundle шаардлагагүй, Chrome Extension-д тохиромжтой
 */

const SUPABASE_URL  = 'https://jbbdnpsvstwxtgtjoeru.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpiYmRucHN2c3R3eHRndGpvZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwNzg1ODIsImV4cCI6MjA5NTY1NDU4Mn0.90qjYby2XNwierEh9XORoP2FEs2LPlRqBC6W74_2oqE';

// ─── Session store (chrome.storage.local) ───────────────────────────────────
const SESSION_KEY = 'no_admin_session';

async function getSession() {
  return new Promise(resolve => {
    chrome.storage.local.get(SESSION_KEY, r => resolve(r[SESSION_KEY] ?? null));
  });
}

async function saveSession(session) {
  return new Promise(resolve => {
    chrome.storage.local.set({ [SESSION_KEY]: session }, resolve);
  });
}

async function clearSession() {
  return new Promise(resolve => {
    chrome.storage.local.remove(SESSION_KEY, resolve);
  });
}

// ─── Base fetch helpers ──────────────────────────────────────────────────────
async function _headers(withAuth = true) {
  const h = {
    'Content-Type': 'application/json',
    'apikey': SUPABASE_ANON,
    'Prefer': 'return=representation',
  };
  if (withAuth) {
    const session = await getSession();
    if (session?.access_token) {
      h['Authorization'] = `Bearer ${session.access_token}`;
    } else {
      h['Authorization'] = `Bearer ${SUPABASE_ANON}`;
    }
  }
  return h;
}

async function _fetch(url, options = {}) {
  const res = await fetch(url, options);
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = text; }
  if (!res.ok) {
    const msg = data?.message || data?.error_description || data?.msg || text;
    throw new Error(msg || `HTTP ${res.status}`);
  }
  return data;
}

// ─── AUTH ────────────────────────────────────────────────────────────────────
export async function signIn(email, password) {
  const data = await _fetch(
    `${SUPABASE_URL}/auth/v1/token?grant_type=password`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SUPABASE_ANON,
      },
      body: JSON.stringify({ email, password }),
    }
  );
  await saveSession(data);
  return data;
}

export async function signOut() {
  const session = await getSession();
  if (session?.access_token) {
    await fetch(`${SUPABASE_URL}/auth/v1/logout`, {
      method: 'POST',
      headers: { 'apikey': SUPABASE_ANON, 'Authorization': `Bearer ${session.access_token}` },
    }).catch(() => {});
  }
  await clearSession();
}

export async function refreshSession() {
  const session = await getSession();
  if (!session?.refresh_token) return null;
  try {
    const data = await _fetch(
      `${SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'apikey': SUPABASE_ANON },
        body: JSON.stringify({ refresh_token: session.refresh_token }),
      }
    );
    await saveSession(data);
    return data;
  } catch {
    await clearSession();
    return null;
  }
}

export { getSession };

// ─── QUERY BUILDER ───────────────────────────────────────────────────────────
class Query {
  constructor(table) {
    this._table  = table;
    this._params = new URLSearchParams();
    this._select = '*';
    this._order  = null;
    this._limit  = null;
    this._method = 'GET';
    this._body   = null;
    this._single = false;
  }

  select(cols = '*') { this._select = cols; return this; }
  eq(col, val)       { this._params.append(col, `eq.${val}`); return this; }
  neq(col, val)      { this._params.append(col, `neq.${val}`); return this; }
  gt(col, val)       { this._params.append(col, `gt.${val}`); return this; }
  gte(col, val)      { this._params.append(col, `gte.${val}`); return this; }
  lt(col, val)       { this._params.append(col, `lt.${val}`); return this; }
  lte(col, val)      { this._params.append(col, `lte.${val}`); return this; }
  ilike(col, val)    { this._params.append(col, `ilike.*${val}*`); return this; }
  order(col, { ascending = true } = {}) {
    this._params.append('order', `${col}.${ascending ? 'asc' : 'desc'}`);
    return this;
  }
  limit(n)  { this._params.append('limit', n); return this; }
  range(from, to) {
    this._params.append('offset', from);
    this._params.append('limit', to - from + 1);
    return this;
  }
  single() { this._single = true; this._params.append('limit', 1); return this; }

  insert(body)  { this._method = 'POST';  this._body = body;  return this; }
  update(body)  { this._method = 'PATCH'; this._body = body;  return this; }
  upsert(body)  {
    this._method = 'POST';
    this._body   = body;
    this._upsert = true;
    return this;
  }
  delete()      { this._method = 'DELETE'; return this; }

  async execute() {
    this._params.set('select', this._select);
    const url = `${SUPABASE_URL}/rest/v1/${this._table}?${this._params}`;
    const headers = await _headers();

    // Count header for GET
    if (this._method === 'GET') {
      headers['Prefer'] = 'count=exact';
    }
    if (this._upsert) {
      headers['Prefer'] = 'resolution=merge-duplicates,return=representation';
    }

    const options = { method: this._method, headers };
    if (this._body) options.body = JSON.stringify(this._body);

    const res = await fetch(url, options);
    const text = await res.text();
    let data;
    try { data = JSON.parse(text); } catch { data = text; }

    if (!res.ok) {
      return { data: null, error: { message: data?.message || data?.error || text } };
    }

    // Parse count from Content-Range
    const range = res.headers.get('Content-Range');
    const count = range ? parseInt(range.split('/')[1]) : null;

    if (this._single) {
      return { data: Array.isArray(data) ? data[0] ?? null : data, count, error: null };
    }
    return { data, count, error: null };
  }
}

export function from(table) {
  return new Query(table);
}

// ─── RPC (stored procedures) ─────────────────────────────────────────────────
export async function rpc(fn, params = {}) {
  const headers = await _headers();
  return _fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(params),
  });
}

// ─── STORAGE ─────────────────────────────────────────────────────────────────
export async function getPublicUrl(bucket, path) {
  return `${SUPABASE_URL}/storage/v1/object/public/${bucket}/${path}`;
}

// ─── AUTH ADMIN (service_role key шаардлагатай) ───────────────────────────────
// Хэрэглэгч устгах, хориглох зэрэг admin action-уудад
export async function adminListUsers(page = 1, perPage = 50) {
  const headers = await _headers();
  return _fetch(
    `${SUPABASE_URL}/auth/v1/admin/users?page=${page}&per_page=${perPage}`,
    { headers }
  );
}
