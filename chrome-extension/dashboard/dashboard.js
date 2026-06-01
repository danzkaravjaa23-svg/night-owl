/**
 * Night Owl UB — Admin Dashboard
 * Supabase REST client-тэй ажиллана
 */
import {
  signIn, signOut, getSession, refreshSession, from
} from '../lib/supabase-client.js';

// ─── Constants ───────────────────────────────────────────────────────────────
const PAGE_SIZE = 20;

// ─── State ───────────────────────────────────────────────────────────────────
let currentPage   = 'overview';
let usersPage     = 0;
let postsPage     = 0;
let postsFilter   = 'all';
let notifFilter   = 'unread';
let userSearch    = '';
let editingVenue  = null;
let session       = null;

// ─── Init ────────────────────────────────────────────────────────────────────
(async () => {
  session = await getSession();
  if (!session?.access_token) {
    // Try refresh
    session = await refreshSession();
  }
  if (session?.access_token) {
    showApp();
  } else {
    showGate();
  }
})();

// ─── Auth gate ────────────────────────────────────────────────────────────────
document.getElementById('gate-btn').addEventListener('click', async () => {
  const email = document.getElementById('gate-email').value.trim();
  const pass  = document.getElementById('gate-pass').value;
  const errEl = document.getElementById('gate-error');
  const btn   = document.getElementById('gate-btn');

  if (!email || !pass) { errEl.textContent = 'И-мэйл болон нууц үгээ оруулна уу'; errEl.style.display = 'block'; return; }

  btn.disabled = true; btn.textContent = 'Нэвтэрч байна…';
  errEl.style.display = 'none';

  try {
    session = await signIn(email, pass);
    showApp();
  } catch (e) {
    errEl.textContent = e.message || 'Нэвтрэх амжилтгүй'; errEl.style.display = 'block';
  } finally {
    btn.disabled = false; btn.textContent = 'Нэвтрэх';
  }
});

document.getElementById('gate-pass').addEventListener('keydown', e => {
  if (e.key === 'Enter') document.getElementById('gate-btn').click();
});

document.getElementById('app-logout').addEventListener('click', async () => {
  await signOut();
  location.reload();
});

// ─── App setup ────────────────────────────────────────────────────────────────
function showGate() {
  document.getElementById('login-gate').style.display = 'flex';
  document.getElementById('app').style.display = 'none';
}

function showApp() {
  document.getElementById('login-gate').style.display = 'none';
  document.getElementById('app').style.display = 'flex';

  const email = session?.user?.email || session?.email || '';
  document.getElementById('sidebar-email').textContent = email;
  document.getElementById('sidebar-initials').textContent = email ? email[0].toUpperCase() : 'A';

  loadPage('overview');
}

// ─── Navigation ───────────────────────────────────────────────────────────────
document.querySelectorAll('.nav-item').forEach(el => {
  el.addEventListener('click', () => {
    const page = el.dataset.page;
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    el.classList.add('active');
    loadPage(page);
  });
});

document.getElementById('refresh-btn').addEventListener('click', () => loadPage(currentPage));

function loadPage(page) {
  currentPage = page;
  document.querySelectorAll('.page-section').forEach(s => s.classList.remove('active'));
  document.getElementById(`page-${page}`).classList.add('active');

  const titles = {
    overview: 'Тойм', users: 'Хэрэглэгчид', posts: 'Постууд',
    venues: 'Venues', notifications: 'Мэдэгдлүүд', broadcast: 'Broadcast'
  };
  document.getElementById('topbar-title').textContent = titles[page] || page;

  switch (page) {
    case 'overview':     loadOverview();     break;
    case 'users':        loadUsers();        break;
    case 'posts':        loadPosts();        break;
    case 'venues':       loadVenues();       break;
    case 'notifications': loadNotifications(); break;
    case 'broadcast':    loadBroadcastHistory(); break;
  }
}

// ─── OVERVIEW ────────────────────────────────────────────────────────────────
async function loadOverview() {
  const [usersR, postsR, likesR, venuesR, msgsR, notifsR] = await Promise.allSettled([
    from('profiles').select('id').execute(),
    from('posts').select('id').execute(),
    from('likes').select('id').execute(),
    from('venues').select('id').execute(),
    from('messages').select('id').execute(),
    from('notifications').select('id').eq('is_read', false).execute(),
  ]);

  const set = (id, r) => {
    const el = document.getElementById(id);
    const count = r.value?.count ?? r.value?.data?.length;
    el.textContent = count != null ? fmtNum(count) : '—';
  };

  set('ov-users',  usersR);
  set('ov-posts',  postsR);
  set('ov-likes',  likesR);
  set('ov-venues', venuesR);
  set('ov-msgs',   msgsR);
  set('ov-notifs', notifsR);

  // Update badges
  const notifCount = notifsR.value?.count ?? notifsR.value?.data?.length ?? 0;
  setBadge('nav-notif-badge', notifCount);

  // Recent posts table
  loadRecentPosts();
}

async function loadRecentPosts() {
  const wrap = document.getElementById('ov-recent-posts');
  const { data, error } = await from('posts')
    .select('id,caption,media_url,likes_count,created_at,user_id')
    .order('created_at', { ascending: false })
    .limit(8)
    .execute();

  if (error || !data?.length) {
    wrap.innerHTML = `<div class="empty-state"><div class="empty-icon">📭</div><p>${error?.message || 'Пост байхгүй'}</p></div>`;
    return;
  }

  wrap.innerHTML = `
    <table><thead><tr>
      <th>Медиа</th><th>Тайлбар</th><th>Like</th><th>Огноо</th>
    </tr></thead>
    <tbody>
      ${data.map(p => `
        <tr>
          <td>
            <div class="post-thumb">
              ${p.media_url ? `<img src="${esc(p.media_url)}" loading="lazy" />` : '📷'}
            </div>
          </td>
          <td style="max-width:260px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">
            ${esc(p.caption || '—')}
          </td>
          <td>❤️ ${p.likes_count ?? 0}</td>
          <td style="color:var(--muted)">${fmtDate(p.created_at)}</td>
        </tr>`).join('')}
    </tbody></table>`;
}

// ─── USERS ───────────────────────────────────────────────────────────────────
async function loadUsers(page = 0) {
  usersPage = page;
  const tbody = document.getElementById('users-tbody');
  tbody.innerHTML = skeletonRows(5, 5);

  const search = document.getElementById('user-search').value.trim();
  let query = from('profiles')
    .select('id,username,full_name,avatar_url,is_verified,is_business,created_at')
    .order('created_at', { ascending: false })
    .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);

  if (search) query = query.ilike('username', search);

  const { data, count, error } = await query.execute();

  if (error) { tbody.innerHTML = errorRow(5, error.message); return; }

  const total = count ?? 0;
  document.getElementById('users-count').textContent = `${total} хэрэглэгч`;
  document.getElementById('users-prev').disabled = page === 0;
  document.getElementById('users-next').disabled = (page + 1) * PAGE_SIZE >= total;

  if (!data?.length) { tbody.innerHTML = emptyRow(5); return; }

  tbody.innerHTML = data.map(u => `
    <tr>
      <td>
        <div class="tbl-avatar">
          <div class="tbl-avatar-img">
            ${u.avatar_url ? `<img src="${esc(u.avatar_url)}" loading="lazy" />` : esc((u.username || 'U')[0].toUpperCase())}
          </div>
          <div>
            <div class="tbl-name">${esc(u.username || '—')}</div>
            <div class="tbl-email">${esc(u.full_name || '')}</div>
          </div>
        </div>
      </td>
      <td style="color:var(--muted)">${fmtDate(u.created_at)}</td>
      <td>
        ${u.is_verified
          ? '<span class="badge badge-teal">✓ Verified</span>'
          : '<span class="badge badge-gray">Unverified</span>'}
      </td>
      <td>
        ${u.is_business
          ? '<span class="badge badge-purple">Business</span>'
          : '<span class="badge badge-gray">Personal</span>'}
      </td>
      <td style="display:flex;gap:6px;flex-wrap:wrap;">
        <button class="action-btn ${u.is_verified ? 'unverify' : 'verify'}"
          onclick="toggleVerify('${u.id}', ${u.is_verified})">
          ${u.is_verified ? 'Unverify' : 'Verify'}
        </button>
        <button class="action-btn ban" onclick="banUser('${u.id}', '${esc(u.username)}')">
          Ban
        </button>
      </td>
    </tr>`).join('');
}

document.getElementById('users-prev').addEventListener('click', () => loadUsers(usersPage - 1));
document.getElementById('users-next').addEventListener('click', () => loadUsers(usersPage + 1));
document.getElementById('user-search').addEventListener('input', debounce(() => loadUsers(0), 400));

window.toggleVerify = async (id, current) => {
  const { error } = await from('profiles').update({ is_verified: !current }).eq('id', id).execute();
  if (error) { toast(error.message, 'error'); return; }
  toast(current ? 'Verify цуцлагдлаа' : 'Verified болголоо', 'success');
  loadUsers(usersPage);
};

window.banUser = async (id, username) => {
  if (!confirm(`"${username}" хэрэглэгчийг хориглох уу?\n(profile устгагдана)`)) return;
  const { error } = await from('profiles').delete().eq('id', id).execute();
  if (error) { toast(error.message, 'error'); return; }
  toast(`${username} хориглогдлоо`, 'success');
  loadUsers(usersPage);
};

// ─── POSTS ───────────────────────────────────────────────────────────────────
async function loadPosts(page = 0) {
  postsPage = page;
  const tbody = document.getElementById('posts-tbody');
  tbody.innerHTML = skeletonRows(6, 6);

  let query = from('posts')
    .select('id,caption,media_url,likes_count,created_at,user_id')
    .order('created_at', { ascending: false })
    .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);

  if (postsFilter === 'recent') {
    const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
    query = query.gte('created_at', since);
  }

  const { data, count, error } = await query.execute();

  if (error) { tbody.innerHTML = errorRow(6, error.message); return; }

  const total = count ?? 0;
  document.getElementById('posts-count').textContent = `${total} пост`;
  document.getElementById('posts-prev').disabled = page === 0;
  document.getElementById('posts-next').disabled = (page + 1) * PAGE_SIZE >= total;

  if (!data?.length) { tbody.innerHTML = emptyRow(6); return; }

  tbody.innerHTML = data.map(p => `
    <tr>
      <td>
        <div class="post-thumb">
          ${p.media_url ? `<img src="${esc(p.media_url)}" loading="lazy" />` : '<span style="font-size:20px;">📷</span>'}
        </div>
      </td>
      <td style="color:var(--muted);font-size:11px;">${p.user_id?.slice(0,8)}…</td>
      <td style="max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">
        ${esc(p.caption || '—')}
      </td>
      <td>❤️ ${p.likes_count ?? 0}</td>
      <td style="color:var(--muted)">${fmtDate(p.created_at)}</td>
      <td>
        <button class="action-btn delete" onclick="deletePost('${p.id}')">🗑 Устгах</button>
      </td>
    </tr>`).join('');
}

document.getElementById('posts-prev').addEventListener('click', () => loadPosts(postsPage - 1));
document.getElementById('posts-next').addEventListener('click', () => loadPosts(postsPage + 1));

document.getElementById('posts-filter').addEventListener('click', e => {
  const tab = e.target.closest('.sub-tab');
  if (!tab) return;
  document.querySelectorAll('#posts-filter .sub-tab').forEach(t => t.classList.remove('active'));
  tab.classList.add('active');
  postsFilter = tab.dataset.filter;
  loadPosts(0);
});

window.deletePost = async (id) => {
  if (!confirm('Энэ постыг устгах уу?')) return;
  const { error } = await from('posts').delete().eq('id', id).execute();
  if (error) { toast(error.message, 'error'); return; }
  toast('Пост устгагдлаа', 'success');
  loadPosts(postsPage);
};

// ─── VENUES ──────────────────────────────────────────────────────────────────
async function loadVenues() {
  const tbody = document.getElementById('venues-tbody');
  tbody.innerHTML = skeletonRows(5, 5);

  const { data, error } = await from('venues')
    .select('id,name,venue_type,district,checkin_count,description,cover_url,lat,lng')
    .order('name', { ascending: true })
    .execute();

  if (error) { tbody.innerHTML = errorRow(5, error.message); return; }
  if (!data?.length) { tbody.innerHTML = emptyRow(5); return; }

  tbody.innerHTML = data.map(v => `
    <tr>
      <td>
        <div class="tbl-avatar">
          <div class="tbl-avatar-img" style="border-radius:8px;">
            ${v.cover_url ? `<img src="${esc(v.cover_url)}" loading="lazy" />` : '📍'}
          </div>
          <span style="font-weight:600;">${esc(v.name)}</span>
        </div>
      </td>
      <td><span class="badge badge-purple">${esc(v.venue_type || '—')}</span></td>
      <td style="color:var(--muted)">${esc(v.district || '—')}</td>
      <td>🔑 ${v.checkin_count ?? 0}</td>
      <td style="display:flex;gap:6px;">
        <button class="action-btn edit" onclick="openEditVenue(${JSON.stringify(v).replace(/'/g, '&#39;')})">✏️ Edit</button>
        <button class="action-btn delete" onclick="deleteVenue('${v.id}', '${esc(v.name)}')">🗑</button>
      </td>
    </tr>`).join('');
}

// Venue modal
document.getElementById('add-venue-btn').addEventListener('click', () => openVenueModal(null));
document.getElementById('venue-modal-cancel').addEventListener('click', closeVenueModal);
document.getElementById('venue-modal').addEventListener('click', e => {
  if (e.target === e.currentTarget) closeVenueModal();
});

function openVenueModal(venue) {
  editingVenue = venue;
  document.getElementById('venue-modal-title').textContent = venue ? 'Venue засах' : 'Venue нэмэх';
  document.getElementById('venue-id').value      = venue?.id || '';
  document.getElementById('venue-name').value    = venue?.name || '';
  document.getElementById('venue-type').value    = venue?.venue_type || 'bar';
  document.getElementById('venue-desc').value    = venue?.description || '';
  document.getElementById('venue-district').value = venue?.district || '';
  document.getElementById('venue-cover').value   = venue?.cover_url || '';
  document.getElementById('venue-lat').value     = venue?.lat || '';
  document.getElementById('venue-lng').value     = venue?.lng || '';
  document.getElementById('venue-modal').classList.add('open');
}

window.openEditVenue = (venue) => openVenueModal(venue);

function closeVenueModal() {
  document.getElementById('venue-modal').classList.remove('open');
  editingVenue = null;
}

document.getElementById('venue-modal-save').addEventListener('click', async () => {
  const name = document.getElementById('venue-name').value.trim();
  if (!name) { toast('Нэрийг оруулна уу', 'error'); return; }

  const payload = {
    name,
    venue_type:  document.getElementById('venue-type').value,
    description: document.getElementById('venue-desc').value.trim() || null,
    district:    document.getElementById('venue-district').value.trim() || null,
    cover_url:   document.getElementById('venue-cover').value.trim() || null,
    lat:         parseFloat(document.getElementById('venue-lat').value) || null,
    lng:         parseFloat(document.getElementById('venue-lng').value) || null,
  };

  const btn = document.getElementById('venue-modal-save');
  btn.disabled = true; btn.textContent = 'Хадгалж байна…';

  let error;
  if (editingVenue) {
    ({ error } = await from('venues').update(payload).eq('id', editingVenue.id).execute());
  } else {
    ({ error } = await from('venues').insert(payload).execute());
  }

  btn.disabled = false; btn.textContent = '💾 Хадгалах';

  if (error) { toast(error.message, 'error'); return; }
  toast(editingVenue ? 'Venue шинэчлэгдлээ' : 'Venue нэмэгдлээ', 'success');
  closeVenueModal();
  loadVenues();
});

window.deleteVenue = async (id, name) => {
  if (!confirm(`"${name}" venue-г устгах уу?`)) return;
  const { error } = await from('venues').delete().eq('id', id).execute();
  if (error) { toast(error.message, 'error'); return; }
  toast(`${name} устгагдлаа`, 'success');
  loadVenues();
};

// ─── NOTIFICATIONS ────────────────────────────────────────────────────────────
async function loadNotifications() {
  const wrap = document.getElementById('notif-list');
  wrap.innerHTML = `<div class="empty-state"><div class="empty-icon">⏳</div><p>Ачаалж байна…</p></div>`;

  let query = from('notifications')
    .select('id,type,message,actor_name,actor_avatar,is_read,created_at')
    .order('created_at', { ascending: false })
    .limit(50);

  if (notifFilter === 'unread') query = query.eq('is_read', false);

  const { data, error } = await query.execute();

  if (error) { wrap.innerHTML = errorDiv(error.message); return; }
  if (!data?.length) {
    wrap.innerHTML = `<div class="empty-state"><div class="empty-icon">🔔</div><p>Мэдэгдэл байхгүй</p></div>`;
    return;
  }

  const iconMap = { like: '❤️', comment: '💬', follow: '👤', system: '📣', event: '📅', promo: '🎁' };

  wrap.innerHTML = data.map(n => `
    <div class="notif-row" style="${n.is_read ? '' : 'background:rgba(124,58,237,.05);'}">
      <div class="notif-icon">${iconMap[n.type] || '🔔'}</div>
      <div class="notif-text">
        <strong>${esc(n.message)}</strong>
        <span>${fmtDate(n.created_at)} · ${n.actor_name || 'System'}</span>
      </div>
      <span class="badge ${n.is_read ? 'badge-gray' : 'badge-purple'}" style="margin-left:auto;flex-shrink:0;">
        ${n.is_read ? 'Read' : 'New'}
      </span>
    </div>`).join('');
}

document.getElementById('notif-filter').addEventListener('click', e => {
  const tab = e.target.closest('.sub-tab');
  if (!tab) return;
  document.querySelectorAll('#notif-filter .sub-tab').forEach(t => t.classList.remove('active'));
  tab.classList.add('active');
  notifFilter = tab.dataset.filter;
  loadNotifications();
});

// ─── BROADCAST ────────────────────────────────────────────────────────────────
async function loadBroadcastHistory() {
  const wrap = document.getElementById('broadcast-history');
  const { data } = await from('notifications')
    .select('id,message,type,created_at')
    .eq('type', 'system')
    .order('created_at', { ascending: false })
    .limit(10)
    .execute();

  if (!data?.length) {
    wrap.innerHTML = `<div class="empty-state"><div class="empty-icon">📭</div><p>Broadcast байхгүй</p></div>`;
    return;
  }
  wrap.innerHTML = data.map(n => `
    <div style="padding:10px 0;border-bottom:1px solid var(--border);font-size:12px;">
      <strong>${esc(n.message)}</strong>
      <span style="color:var(--muted);margin-left:8px;">${fmtDate(n.created_at)}</span>
    </div>`).join('');
}

document.getElementById('broadcast-btn').addEventListener('click', async () => {
  const body = document.getElementById('broadcast-body').value.trim();
  const type = document.getElementById('broadcast-type').value;
  const resEl = document.getElementById('broadcast-result');

  if (!body) { toast('Мэдэгдлийн текст оруулна уу', 'error'); return; }

  const btn = document.getElementById('broadcast-btn');
  btn.disabled = true; btn.textContent = 'Илгээж байна…';
  resEl.style.display = 'none';

  // Get all profile IDs
  const { data: profiles, error: pErr } = await from('profiles').select('id').execute();
  if (pErr || !profiles?.length) {
    toast('Хэрэглэгчид олдсонгүй', 'error');
    btn.disabled = false; btn.textContent = '📣 Илгээх';
    return;
  }

  // Insert notification for each user (batch)
  const rows = profiles.map(p => ({
    user_id:      p.id,
    actor_id:     p.id,
    actor_name:   'Night Owl Admin',
    type:         type,
    message:      body,
    is_read:      false,
  }));

  // Insert in chunks of 100 to avoid request size limits
  const chunkSize = 100;
  let errorCount = 0;
  for (let i = 0; i < rows.length; i += chunkSize) {
    const chunk = rows.slice(i, i + chunkSize);
    const { error } = await from('notifications').insert(chunk).execute();
    if (error) errorCount++;
  }

  btn.disabled = false; btn.textContent = '📣 Илгээх';

  if (errorCount > 0) {
    toast(`${errorCount} chunk алдаатай байна`, 'error');
  } else {
    resEl.textContent = `✅ ${profiles.length} хэрэглэгчид амжилттай илгээгдлээ`;
    resEl.style.display = 'block';
    toast('Broadcast илгээгдлээ!', 'success');
    document.getElementById('broadcast-body').value = '';
    loadBroadcastHistory();
  }
});

// ─── Global search ────────────────────────────────────────────────────────────
document.getElementById('global-search').addEventListener('input', debounce(async (e) => {
  const q = e.target.value.trim();
  if (!q || q.length < 2) return;

  if (currentPage === 'users') {
    document.getElementById('user-search').value = q;
    loadUsers(0);
  }
}, 400));

// ─── Helpers ─────────────────────────────────────────────────────────────────
function fmtDate(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('mn-MN', { month: 'short', day: 'numeric', year: '2-digit' });
}

function fmtNum(n) {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
  if (n >= 1_000)     return (n / 1_000).toFixed(1) + 'K';
  return String(n ?? 0);
}

function esc(s) {
  if (s == null) return '';
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function setBadge(id, count) {
  const el = document.getElementById(id);
  if (count > 0) { el.textContent = count > 99 ? '99+' : count; el.style.display = 'flex'; }
  else { el.style.display = 'none'; }
}

function skeletonRows(cols, rows) {
  return Array(rows).fill(0).map(() =>
    `<tr>${Array(cols).fill(0).map(() =>
      `<td><div class="skeleton" style="height:14px;width:80%;border-radius:4px;"></div></td>`
    ).join('')}</tr>`
  ).join('');
}

function emptyRow(cols) {
  return `<tr><td colspan="${cols}"><div class="empty-state"><div class="empty-icon">📭</div><p>Өгөгдөл байхгүй</p></div></td></tr>`;
}

function errorRow(cols, msg) {
  return `<tr><td colspan="${cols}"><div class="empty-state"><div class="empty-icon">⚠️</div><p>${esc(msg)}</p></div></td></tr>`;
}

function errorDiv(msg) {
  return `<div class="empty-state"><div class="empty-icon">⚠️</div><p>${esc(msg)}</p></div>`;
}

function toast(msg, type = 'success') {
  const icons = { success: '✅', error: '❌' };
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.innerHTML = `<span>${icons[type]}</span><span>${esc(msg)}</span>`;
  document.getElementById('toast-container').appendChild(el);
  setTimeout(() => el.remove(), 3500);
}

function debounce(fn, ms) {
  let timer;
  return function(...args) {
    clearTimeout(timer);
    timer = setTimeout(() => fn.apply(this, args), ms);
  };
}
