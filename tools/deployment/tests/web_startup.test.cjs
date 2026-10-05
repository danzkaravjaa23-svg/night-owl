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
