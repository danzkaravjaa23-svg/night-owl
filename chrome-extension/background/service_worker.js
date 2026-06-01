/**
 * Night Owl Admin — MV3 Service Worker
 * - Session auto-refresh (every 50 min)
 * - Unread notification badge
 * - Alarm scheduling
 */

const SUPABASE_URL  = 'https://jbbdnpsvstwxtgtjoeru.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpiYmRucHN2c3R3eHRndGpvZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwNzg1ODIsImV4cCI6MjA5NTY1NDU4Mn0.90qjYby2XNwierEh9XORoP2FEs2LPlRqBC6W74_2oqE';
const SESSION_KEY   = 'no_admin_session';
const ALARM_REFRESH = 'session-refresh';
const ALARM_BADGE   = 'badge-update';

// ─── Install ─────────────────────────────────────────────────────────────────
self.addEventListener('install', () => {
  self.skipWaiting();
  setupAlarms();
});

self.addEventListener('activate', e => {
  e.waitUntil(clients.claim());
  setupAlarms();
});

// ─── Alarms ──────────────────────────────────────────────────────────────────
function setupAlarms() {
  chrome.alarms.create(ALARM_REFRESH, { periodInMinutes: 50 });
  chrome.alarms.create(ALARM_BADGE,   { periodInMinutes: 5  });
}

chrome.alarms.onAlarm.addListener(async alarm => {
  if (alarm.name === ALARM_REFRESH) await refreshSession();
  if (alarm.name === ALARM_BADGE)   await updateBadge();
});

// ─── Session refresh ─────────────────────────────────────────────────────────
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

async function refreshSession() {
  const session = await getSession();
  if (!session?.refresh_token) return;

  try {
    const res = await fetch(
      `${SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'apikey': SUPABASE_ANON },
        body: JSON.stringify({ refresh_token: session.refresh_token }),
      }
    );
    if (res.ok) {
      const data = await res.json();
      await saveSession(data);
    } else {
      // Token expired — clear
      await chrome.storage.local.remove(SESSION_KEY);
      chrome.action.setBadgeText({ text: '' });
    }
  } catch {
    // Network error — silently ignore
  }
}

// ─── Badge (unread notification count) ───────────────────────────────────────
async function updateBadge() {
  const session = await getSession();
  if (!session?.access_token) {
    chrome.action.setBadgeText({ text: '' });
    return;
  }

  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/notifications?is_read=eq.false&select=id`,
      {
        headers: {
          'apikey': SUPABASE_ANON,
          'Authorization': `Bearer ${session.access_token}`,
          'Prefer': 'count=exact',
        }
      }
    );

    if (!res.ok) return;

    const range = res.headers.get('Content-Range');
    const count = range ? parseInt(range.split('/')[1]) : 0;

    if (count > 0) {
      const label = count > 99 ? '99+' : String(count);
      chrome.action.setBadgeText({ text: label });
      chrome.action.setBadgeBackgroundColor({ color: '#7c3aed' });
    } else {
      chrome.action.setBadgeText({ text: '' });
    }
  } catch {
    // silently ignore
  }
}

// ─── On extension startup ─────────────────────────────────────────────────────
updateBadge();
