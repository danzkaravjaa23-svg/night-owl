import { signIn, signOut, getSession, from } from '../lib/supabase-client.js';

// ─── DOM refs ────────────────────────────────────────────────────────────────
const loginView   = document.getElementById('login-view');
const dashView    = document.getElementById('dash-view');
const loginBtn    = document.getElementById('login-btn');
const logoutBtn   = document.getElementById('logout-btn');
const emailInput  = document.getElementById('email');
const passInput   = document.getElementById('password');
const loginError  = document.getElementById('login-error');
const openDash    = document.getElementById('open-dashboard');

// ─── Init ────────────────────────────────────────────────────────────────────
(async () => {
  const session = await getSession();
  if (session?.access_token) {
    showDash(session);
    loadStats();
  } else {
    showLogin();
  }
})();

// ─── Auth handlers ───────────────────────────────────────────────────────────
loginBtn.addEventListener('click', async () => {
  const email = emailInput.value.trim();
  const pass  = passInput.value;
  if (!email || !pass) return showError('И-мэйл болон нууц үгээ оруулна уу');

  loginBtn.disabled = true;
  loginBtn.textContent = 'Нэвтэрч байна…';
  hideError();

  try {
    const session = await signIn(email, pass);
    showDash(session);
    loadStats();
  } catch (e) {
    showError(e.message || 'Нэвтрэх амжилтгүй');
  } finally {
    loginBtn.disabled = false;
    loginBtn.textContent = 'Нэвтрэх';
  }
});

passInput.addEventListener('keydown', e => { if (e.key === 'Enter') loginBtn.click(); });

logoutBtn.addEventListener('click', async () => {
  await signOut();
  showLogin();
});

openDash.addEventListener('click', () => {
  chrome.runtime.openOptionsPage();
});

// ─── View helpers ────────────────────────────────────────────────────────────
function showLogin() {
  loginView.style.display = 'block';
  dashView.style.display  = 'none';
  emailInput.focus();
}

function showDash(session) {
  loginView.style.display = 'none';
  dashView.style.display  = 'block';

  const email = session?.user?.email || session?.email || '';
  document.getElementById('user-email-display').textContent = email;
  document.getElementById('user-initials').textContent = email ? email[0].toUpperCase() : 'A';
}

function showError(msg) {
  loginError.textContent = msg;
  loginError.classList.add('show');
}
function hideError() { loginError.classList.remove('show'); }

// ─── Stats loader ─────────────────────────────────────────────────────────────
async function loadStats() {
  document.getElementById('last-refresh').textContent =
    new Date().toLocaleTimeString('mn-MN', { hour: '2-digit', minute: '2-digit' });

  const [usersRes, postsRes, venuesRes, notifsRes] = await Promise.allSettled([
    from('profiles').select('id').execute(),
    from('posts').select('id').execute(),
    from('venues').select('id').execute(),
    from('notifications').select('id').eq('is_read', false).execute(),
  ]);

  setStat('stat-users',  usersRes);
  setStat('stat-posts',  postsRes);
  setStat('stat-venues', venuesRes);
  setStat('stat-notifs', notifsRes);
}

function setStat(id, result) {
  const el = document.getElementById(id);
  el.classList.remove('stat-loading');
  if (result.status === 'fulfilled' && result.value.count !== null) {
    el.textContent = fmtNum(result.value.count);
  } else if (result.status === 'fulfilled' && Array.isArray(result.value.data)) {
    el.textContent = fmtNum(result.value.data.length);
  } else {
    el.textContent = '—';
  }
}

function fmtNum(n) {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
  if (n >= 1_000)     return (n / 1_000).toFixed(1) + 'K';
  return String(n);
}
