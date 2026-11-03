// Isolated browser regression: localhost, synthetic app scripts and no accounts.
// Verifies real service-worker control, offline fallback, and session preservation.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const html = (await readFile(path.join(root, 'web/index.html'), 'utf8'))
  .replace('$FLUTTER_BASE_HREF', '/');
const stale = "document.body.dataset.app = 'stale'; window.dispatchEvent(new Event('flutter-first-frame'));";
const fresh = stale.replace("'stale'", "'fresh'");
const oldWorker = `
self.addEventListener('install', event => event.waitUntil((async () => {
  const cache = await caches.open('flutter-app-cache');
  await cache.put('/', new Response(${JSON.stringify(html)}, {headers:{'Content-Type':'text/html'}}));
  await cache.put('/flutter_bootstrap.js', new Response(${JSON.stringify(stale)}, {headers:{'Content-Type':'application/javascript'}}));
  await self.skipWaiting();
})()));
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if(url.search || !['/','/flutter_bootstrap.js'].includes(url.pathname)) return;
  event.respondWith((async () => {
    const cache = await caches.open('flutter-app-cache');
    if(url.pathname === '/') {
      try { return await fetch(event.request); } catch (_) { return cache.match('/'); }
    }
    return await cache.match(url.pathname) || fetch(event.request);
  })());
});`;
const retirementWorker = await readFile(path.join(root, 'web/flutter_service_worker.js'), 'utf8');
let workerMode = 'legacy';
let indexRequests = 0;
const server = createServer((req, res) => {
  const url = new URL(req.url, 'http://fixture');
  res.setHeader('Cache-Control', 'no-store');
  if (url.pathname === '/seed') {
    res.setHeader('Content-Type', 'text/html');
    return res.end('<!doctype html><title>Legacy app fixture</title>');
  }
  if (url.pathname === '/') {
    indexRequests++;
    res.setHeader('Content-Type', 'text/html');
    return res.end(html);
  }
  if (url.pathname === '/flutter_service_worker.js') {
    res.setHeader('Content-Type', 'application/javascript');
    return res.end(workerMode === 'legacy' ? oldWorker : retirementWorker);
  }
  if (url.pathname === '/flutter_bootstrap.js') {
    res.setHeader('Content-Type', 'application/javascript');
    return res.end(fresh);
  }
  if (url.pathname === '/release.json') {
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify({ commit: 'a'.repeat(40) }));
  }
  res.statusCode = 404; res.end();
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
});
async function seededPage() {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  await page.goto(origin + '/seed');
  await page.evaluate(async () => {
    localStorage.setItem('fixture-auth-session', 'preserve-me');
    const saved = await caches.open('user-saved-items');
    await saved.put('/saved', new Response('preserve-me'));
    await navigator.serviceWorker.register('/flutter_service_worker.js');
    await navigator.serviceWorker.ready;
  });
  await page.waitForFunction(() => navigator.serviceWorker.controller);
  return { context, page };
}
try {
  const online = await seededPage();
  const before = indexRequests;
  await online.page.goto(origin + '/');
  await online.page.waitForFunction(() => document.body.dataset.app === 'fresh');
  assert.equal(indexRequests - before, 2, 'one startup refresh replaces the controlled document');
  assert.equal(await online.page.evaluate(() => navigator.serviceWorker.controller), null);
  assert.equal(await online.page.evaluate(() => localStorage.getItem('fixture-auth-session')), 'preserve-me');
  assert.deepEqual(await online.page.evaluate(() => caches.keys()), ['user-saved-items']);
  await online.context.close();

  const offline = await seededPage();
  await offline.context.setOffline(true);
  await offline.page.goto(origin + '/');
  await offline.page.waitForFunction(() => document.body.dataset.app === 'stale');
  assert.equal(await offline.page.evaluate(() => caches.has('flutter-app-cache')), true);
  assert.equal(await offline.page.evaluate(() => navigator.serviceWorker.getRegistrations().then(rs => rs.length)), 1);
  await offline.context.setOffline(false);
  await offline.page.reload();
  await offline.page.waitForFunction(() => document.body.dataset.app === 'fresh');
  assert.equal(await offline.page.evaluate(() => localStorage.getItem('fixture-auth-session')), 'preserve-me');
  await offline.context.close();
  const running = await seededPage();
  await running.page.setContent('<input aria-label="Draft" value="Keep my draft">');
  let navigations = 0;
  running.page.on('framenavigated', () => navigations++);
  workerMode = 'retirement';
  await running.page.evaluate(async () => {
    const registration = await navigator.serviceWorker.getRegistration();
    await registration.update();
  });
  await running.page.waitForFunction(async () => (await navigator.serviceWorker.getRegistrations()).length === 0);
  assert.equal(navigations, 0, 'worker activation cannot refresh an in-progress draft');
  assert.equal(await running.page.getByRole('textbox', { name: 'Draft' }).inputValue(), 'Keep my draft');
  await running.context.close();
  console.log('PASS: retirement worker preserves open drafts; real legacy worker retires with exactly one startup refresh; offline cached app survives; reconnect loads fresh app; Auth-like localStorage and unrelated cache preserved.');
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
