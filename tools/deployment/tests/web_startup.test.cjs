const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

const root = resolve(__dirname, '../../..');
const index = readFileSync(resolve(root, 'web/index.html'), 'utf8');
const controller = index.match(/<script id="night-owl-startup-controller">([\s\S]*?)<\/script>/)[1];
const bootstrap = readFileSync(resolve(root, 'web/flutter_bootstrap.js'), 'utf8')
  .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '');

function fixture() {
  const nodes = new Map();
  for (const id of ['night-owl-startup', 'startup-message', 'startup-detail', 'startup-status', 'startup-retry']) {
    nodes.set(id, {
      dataset: { state: 'loading' }, hidden: id === 'startup-retry',
      removed: false, listeners: new Map(), attributes: new Map(),
      setAttribute(name, value) { this.attributes.set(name, value); },
      addEventListener(name, fn) { this.listeners.set(name, fn); },
      remove() { this.removed = true; },
    });
  }
  const listeners = new Map();
  let reloads = 0;
  const window = {
    location: { reload() { reloads++; } },
    addEventListener(name, callback) { listeners.set(name, callback); },
    removeEventListener(name, callback) {
      if (listeners.get(name) === callback) listeners.delete(name);
    },
  };
  const context = vm.createContext({
    window, URL, Promise,
    document: { baseURI: 'https://nightowl.example/app/', getElementById: id => nodes.get(id) },
    _flutter: { loader: {} },
  });
  vm.runInContext(controller, context);
  return {
    window, nodes, context,
    emit(name, event = {}) { listeners.get(name)?.(event); },
    load(fn) { context._flutter.loader.load = fn; vm.runInContext(bootstrap, context); },
    get reloads() { return reloads; },
    get listensForErrors() { return listeners.has('error'); },
  };
}

function assertRetry(state) {
  assert.equal(state.nodes.get('night-owl-startup').dataset.state, 'error');
  assert.equal(state.nodes.get('startup-retry').hidden, false);
  assert.equal(state.nodes.get('startup-status').attributes.get('aria-busy'), 'false');
  assert.equal(state.nodes.get('startup-message').textContent, 'Аппыг ачаалж чадсангүй');
}

test('loader stays until a real first frame, then removes itself and its error listener', async () => {
  const state = fixture();
  let callback;
  state.load(options => { callback = options.onEntrypointLoaded; });
  let ran = false;
  await callback({ initializeEngine: async () => ({ runApp: async () => { ran = true; } }) });
  assert.equal(ran, true);
  assert.equal(state.nodes.get('night-owl-startup').removed, false);
  assert.equal(state.nodes.get('startup-message').textContent, 'Аппыг нээж байна');
  const fail = state.window.nightOwlStartup.fail;
  state.emit('flutter-first-frame');
  assert.equal(state.nodes.get('night-owl-startup').removed, true);
  assert.equal(state.listensForErrors, false);
  assert.equal(state.window.nightOwlStartup, undefined);
  fail();
  assert.equal(state.nodes.get('startup-retry').hidden, true);
});

for (const filename of ['flutter_bootstrap.js', 'main.dart.js']) {
  test(`failed ${filename} resource exposes retry without displaying internal error details`, () => {
    const state = fixture();
    state.emit('error', { target: { tagName: 'SCRIPT', src: `https://nightowl.example/app/${filename}` } });
    assertRetry(state);
    state.nodes.get('startup-retry').listeners.get('click')();
    assert.equal(state.reloads, 1);
  });
}

test('unrelated image errors and scripts do not stop startup; broken app script does', () => {
  const state = fixture();
  state.emit('error', { target: { tagName: 'IMG', src: 'icons/Icon-192.png' } });
  state.emit('error', { target: { tagName: 'SCRIPT', src: 'https://other.example/main.dart.js' } });
  assert.equal(state.nodes.get('startup-retry').hidden, true);
  state.emit('error', { filename: 'https://nightowl.example/app/main.dart.js' });
  assertRetry(state);
});

for (const phase of ['engine', 'runApp']) {
  test(`${phase} rejection exposes retry and cannot be overwritten by later stage text`, async () => {
    const state = fixture();
    let callback;
    state.load(options => { callback = options.onEntrypointLoaded; });
    await callback({ initializeEngine: async () => {
      if (phase === 'engine') throw new Error('Private engine detail');
      return { runApp: async () => { throw new Error('Private app detail'); } };
    } });
    assertRetry(state);
    state.window.nightOwlStartup.stage('Next');
    assertRetry(state);
  });
}

test('loader rejection or synchronous bootstrap failure exposes retry', async () => {
  for (const synchronous of [false, true]) {
    const state = fixture();
    state.load(() => {
      if (synchronous) throw new Error('Unsupported browser');
      return Promise.reject(new Error('Renderer unavailable'));
    });
    await new Promise(resolve => setImmediate(resolve));
    assertRetry(state);
  }
});

const updater = index.match(/<script id="night-owl-update-controller">([\s\S]*?)<\/script>/)[1];
const releaseCommit = 'a'.repeat(40);
const worker = { scriptURL: 'https://nightowl.example/app/flutter_service_worker.js?v=old' };

function updateFixture(options = {}) {
  const events = [];
  const cacheNames = options.cacheNames || [
    'flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest', 'user-saved-items'
  ];
  const storage = options.storage || new Map();
  const registrations = options.registrations || [{
    scope: 'https://nightowl.example/app/', active: worker,
    async unregister() { events.push('unregister'); return true; },
  }];
  const serviceWorker = {
    controller: options.controlled === false ? null : worker,
    getRegistrations: async () => registrations,
  };
  const appended = [];
  const window = {
    caches: {
      keys: async () => cacheNames,
      async delete(key) { events.push('delete:' + key); return true; },
    },
    sessionStorage: options.storageBlocked ? {
      getItem() { throw new Error('Storage blocked'); },
    } : {
      getItem: key => storage.get(key),
      setItem(key, value) { storage.set(key, value); },
    },
    location: { reload() { events.push('reload'); } },
    nightOwlStartup: { stage(label) { events.push('stage:' + label); }, fail() { events.push('failed'); } },
  };
  const timers = new Map();
  const context = vm.createContext({
    window, URL, Promise, Date, AbortController,
    navigator: options.noServiceWorker ? {} : { serviceWorker, onLine: options.online !== false },
    document: {
      baseURI: 'https://nightowl.example/app/', createElement: () => ({}),
      body: { appendChild(script) { appended.push(script); events.push('bootstrap'); } },
    },
    setTimeout(fn) { timers.set(1, fn); return 1; },
    clearTimeout(id) { timers.delete(id); },
    async fetch(url, settings) {
      events.push('fetch');
      assert.equal(settings.cache, 'no-store');
      assert.equal(settings.credentials, 'omit');
      assert.equal(new URL(url).pathname, '/app/release.json');
      assert.ok(new URL(url).searchParams.has('night_owl_probe'));
      if (options.fetch) return options.fetch(url, settings);
      return { ok: true, redirected: false, json: async () => ({ commit: releaseCommit }) };
    },
  });
  vm.runInContext(updater, context);
  return {
    events, storage, appended, timers,
    async flush() { await new Promise(resolve => setImmediate(resolve)); },
  };
}

test('clean browser starts immediately without a network update probe', async () => {
  for (const options of [{ noServiceWorker: true }, { controlled: false, registrations: [] }]) {
    const state = updateFixture(options);
    await state.flush();
    assert.deepEqual(state.events, ['bootstrap']);
    assert.equal(state.appended[0].src, 'https://nightowl.example/app/flutter_bootstrap.js');
  }
});

test('controlled old-worker navigation retires before Flutter boots and refreshes once', async () => {
  let finishUnregister;
  const state = updateFixture({ registrations: [{
    scope: 'https://nightowl.example/app/', active: worker,
    unregister: () => new Promise(resolve => { finishUnregister = resolve; }),
  }] });
  await state.flush();
  assert.equal(state.events.includes('bootstrap'), false);
  assert.equal(state.events.includes('reload'), false);
  finishUnregister(true);
  await state.flush();
  assert.deepEqual(state.events, [
    'fetch', 'stage:Шинэ хувилбарыг нээж байна',
    'delete:flutter-app-cache', 'delete:flutter-temp-cache', 'delete:flutter-app-manifest', 'reload'
  ]);
  // Even an anomalous second controlled navigation cannot create a reload loop.
  const repeated = updateFixture({ storage: state.storage });
  await repeated.flush();
  assert.equal(repeated.events.includes('reload'), false);
  assert.equal(repeated.events.at(-1), 'bootstrap');
});

test('an already unregistered controller still receives one safe online navigation', async () => {
  const state = updateFixture({ registrations: [] });
  await state.flush();
  assert.equal(state.events.at(-1), 'reload');
  assert.equal(state.events.includes('bootstrap'), false);
});

test('offline or failed network preserves cached fallback and starts the app', async () => {
  for (const options of [
    { online: false },
    { fetch: async () => { throw new TypeError('Offline'); } },
    { fetch: async () => ({ ok: false }) },
    { fetch: async () => ({ ok: true, redirected: true }) },
    { fetch: async () => ({ ok: true, json: async () => { throw new SyntaxError('HTML'); } }) },
    { fetch: async () => ({ ok: true, json: async () => ({ commit: 'not-a-release' }) }) },
  ]) {
    const state = updateFixture(options);
    await state.flush();
    assert.equal(state.events.includes('unregister'), false);
    assert.equal(state.events.some(event => event.startsWith('delete:')), false);
    assert.equal(state.events.includes('reload'), false);
    assert.equal(state.events.at(-1), 'bootstrap');
  }
});

test('slow update probe times out without losing the offline cache', async () => {
  const state = updateFixture({ fetch: (_, { signal }) => new Promise((_, reject) => {
    signal.addEventListener('abort', () => reject(new Error('Timeout')));
  }) });
  await state.flush();
  assert.equal(state.appended.length, 0);
  state.timers.get(1)();
  await state.flush();
  assert.deepEqual(state.events, ['fetch', 'bootstrap']);
  assert.equal(state.timers.size, 0);
});

test('failed unregistration never destroys its caches or traps the startup screen', async () => {
  for (const unregister of [async () => false, async () => { throw new Error('Denied'); }]) {
    const state = updateFixture({ registrations: [{
      scope: 'https://nightowl.example/app/', active: worker, unregister,
    }] });
    await state.flush();
    assert.equal(state.events.some(event => event.startsWith('delete:')), false);
    assert.equal(state.events.includes('reload'), false);
    assert.equal(state.events.at(-1), 'bootstrap');
  }
});

test('blocked session storage still opens the app without risking a reload loop', async () => {
  const state = updateFixture({ storageBlocked: true });
  await state.flush();
  assert.equal(state.events.includes('reload'), false);
  assert.equal(state.events.at(-1), 'bootstrap');
});

test('workers for another app path or origin are left alone', async () => {
  for (const registration of [
    { scope: 'https://nightowl.example/other/', active: worker },
    { scope: 'https://nightowl.example/app/', active: { scriptURL: 'https://other.example/app/flutter_service_worker.js' } },
    { scope: 'https://nightowl.example/app/', active: { scriptURL: 'https://nightowl.example/app/other_service_worker.js' } },
  ]) {
    const state = updateFixture({ controlled: false, registrations: [registration] });
    await state.flush();
    assert.deepEqual(state.events, ['bootstrap']);
  }
});

test('waiting legacy registration is retired without refreshing an uncontrolled page', async () => {
  const state = updateFixture({ controlled: false, registrations: [{
    scope: 'https://nightowl.example/app/', waiting: worker, unregister: async () => true,
  }] });
  await state.flush();
  assert.equal(state.events.includes('reload'), false);
  assert.equal(state.events.at(-1), 'bootstrap');
  assert.equal(state.events.filter(event => event.startsWith('delete:')).length, 3);
});

test('HTML and stable Flutter asset names must revalidate after deployment', () => {
  const headers = readFileSync(resolve(root, 'web/_headers'), 'utf8');
  assert.match(headers, /\/\*\s+Cache-Control: public, max-age=0, must-revalidate/);
  assert.doesNotMatch(updater, /localStorage|\.clear\(/);
  assert.doesNotMatch(updater, /visibilitychange|controllerchange/);
});

test('retirement worker unregisters without navigating tabs or deleting cache data', async () => {
  const source = readFileSync(resolve(root, 'web/flutter_service_worker.js'), 'utf8');
  const listeners = new Map();
  const calls = [];
  vm.runInNewContext(source, {
    self: {
      addEventListener: (name, callback) => listeners.set(name, callback),
      skipWaiting: async () => { calls.push('skipWaiting'); },
      registration: { unregister: async () => { calls.push('unregister'); return true; } },
      get clients() { throw new Error('Open tabs must not be touched'); },
    },
  });
  await new Promise(resolve => listeners.get('install')({ waitUntil: work => resolve(work) }));
  await new Promise(resolve => listeners.get('activate')({ waitUntil: work => resolve(work) }));
  assert.deepEqual(calls, ['skipWaiting', 'unregister']);
  assert.equal(listeners.has('fetch'), false);
  const build = readFileSync(resolve(root, 'tools/deployment/build_web.sh'), 'utf8');
  assert.match(build, /cp web\/flutter_service_worker\.js build\/web\/flutter_service_worker\.js/);
});
