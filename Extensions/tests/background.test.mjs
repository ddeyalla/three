// Runs the real service worker against a fake `chrome` to check connection, enforcement, sweeps and expiry.
import { test } from 'node:test';
import assert from 'node:assert/strict';

const REDDIT = '11111111-1111-4111-8111-111111111111';
const X = '22222222-2222-4222-8222-222222222222';
const settle = () => new Promise((r) => setTimeout(r, 20));
let loads = 0;

function fakeChrome({ tabs = [], session = {} } = {}) {
  const listeners = { alarm: [], message: [] };
  const fake = {
    ports: [], dnr: [], ruleUpdates: 0, tabUpdates: [], alarms: new Map(), session: { ...session }, local: {},
    fireAlarm: (name) => listeners.alarm.forEach((f) => f({ name })),
    pageMessage: (msg, sender) => listeners.message.forEach((f) => f(msg, sender)),
  };
  const area = (store) => ({
    get: async (keys) => {
      if (typeof keys === 'string') return keys in store ? { [keys]: store[keys] } : {};
      return Object.fromEntries(Object.entries(keys).map(([k, d]) => [k, k in store ? store[k] : d]));
    },
    set: async (o) => { Object.assign(store, o); },
  });
  globalThis.chrome = {
    runtime: {
      id: 'ext',
      lastError: undefined,
      getURL: (p) => `chrome-extension://ext/${p.replace(/^\//, '')}`,
      getManifest: () => ({ version: '0.3.0' }),
      connectNative(name) {
        assert.equal(name, 'com.deyalla.three');
        const on = { message: [], disconnect: [] };
        const port = {
          posted: [],
          postMessage: (m) => port.posted.push(m),
          onMessage: { addListener: (f) => on.message.push(f) },
          onDisconnect: { addListener: (f) => on.disconnect.push(f) },
          fromHost: (m) => on.message.forEach((f) => f(m)),
          drop: () => on.disconnect.forEach((f) => f()),
        };
        fake.ports.push(port);
        return port;
      },
      onMessage: { addListener: (f) => listeners.message.push(f) },
    },
    storage: { session: area(fake.session), local: area(fake.local) },
    declarativeNetRequest: {
      getSessionRules: async () => structuredClone(fake.dnr),
      updateSessionRules: async ({ removeRuleIds, addRules }) => {
        fake.ruleUpdates += 1;
        fake.dnr = fake.dnr.filter((r) => !removeRuleIds.includes(r.id)).concat(addRules);
      },
    },
    alarms: {
      create: async (name, info) => { fake.alarms.set(name, info); },
      clear: async (name) => { fake.alarms.delete(name); },
      onAlarm: { addListener: (f) => listeners.alarm.push(f) },
    },
    tabs: { query: async () => tabs, update: async (tabId, { url }) => { fake.tabUpdates.push({ tabId, url }); } },
    permissions: { contains: async () => true },
  };
  return fake;
}

async function boot(options) {
  const fake = fakeChrome(options);
  await import(`../Chrome/background.js?load=${loads++}`);
  await settle();
  return fake;
}

const state = (over = {}) => ({
  type: 'state', protocol: 1, validUntil: Date.now() + 120_000, active: true, reason: 'focus', strict: false,
  until: Date.now() + 60_000, task: null,
  rules: [{ id: REDDIT, domain: 'reddit.com', label: 'Reddit' }, { id: X, domain: 'x.com', label: 'X' }],
  ...over,
});

test('connects, says hello without any address, and enforces the first state', async () => {
  const fake = await boot({ tabs: [{ id: 9, url: 'https://old.reddit.com/r/adhd' }, { id: 10, url: 'https://example.com/' }] });
  const [port] = fake.ports;
  assert.deepEqual(Object.keys(port.posted[0]).sort(), ['clientId', 'hostAccess', 'protocol', 'type', 'version']);
  assert.equal(port.posted[0].type, 'hello');
  port.fromHost(state());
  await settle();
  assert.deepEqual(fake.dnr.map((r) => r.condition.requestDomains[0]), ['reddit.com', 'x.com']);
  assert.deepEqual(fake.tabUpdates, [{ tabId: 9, url: `chrome-extension://ext/block.html?rule=${REDDIT}&swept=1` }]);
  assert.equal(fake.session.connected, true);
  assert.ok(fake.alarms.get('lease').when > Date.now());
});

test('a repeated state changes nothing; a changed rule set re-sweeps open tabs', async () => {
  const fake = await boot({ tabs: [{ id: 9, url: 'https://reddit.com/' }] });
  const [port] = fake.ports;
  port.fromHost(state({ rules: [{ id: X, domain: 'x.com', label: 'X' }] }));
  await settle();
  port.fromHost(state({ rules: [{ id: X, domain: 'x.com', label: 'X' }] }));
  await settle();
  assert.equal(fake.ruleUpdates, 1);
  assert.deepEqual(fake.tabUpdates, []);
  // Reddit's five-minute exception ended: the rule is back, and the tab left open during it is blocked again.
  port.fromHost(state());
  await settle();
  assert.equal(fake.ruleUpdates, 2);
  assert.deepEqual(fake.tabUpdates.map((u) => u.tabId), [9]);
});

test('rules lapse with the lease when Three goes quiet, and reconnecting resumes', async () => {
  const fake = await boot();
  const [port] = fake.ports;
  port.fromHost(state({ validUntil: Date.now() + 40 }));
  await settle();
  assert.equal(fake.dnr.length, 2);
  port.drop();
  await settle();
  assert.equal(fake.session.connected, false);
  assert.ok(fake.alarms.has('reconnect-soon'));
  await new Promise((r) => setTimeout(r, 40));
  fake.fireAlarm('lease');
  await settle();
  assert.deepEqual(fake.dnr, []);
  fake.fireAlarm('reconnect-soon');
  await settle();
  assert.equal(fake.ports.length, 2);
  assert.equal(fake.ports[1].posted[0].type, 'hello');
});

test('a restarted worker drops rules whose lease already lapsed', async () => {
  const lapsed = { ...state(), validUntil: Date.now() - 1 };
  const fake = fakeChrome({ session: { state: lapsed } });
  fake.dnr = [{ id: 1, condition: { requestDomains: ['reddit.com'] }, action: { type: 'redirect', redirect: { extensionPath: '/block.html' } } }];
  await import(`../Chrome/background.js?load=${loads++}`);
  await settle();
  assert.deepEqual(fake.dnr, []);
});

test('only the block page can report a hit, and only for a rule in force', async () => {
  const fake = await boot();
  const [port] = fake.ports;
  port.fromHost(state());
  await settle();
  const page = { id: 'ext', url: `chrome-extension://ext/block.html?rule=${REDDIT}` };
  fake.pageMessage({ type: 'hit', ruleId: REDDIT }, { id: 'other', url: page.url });
  fake.pageMessage({ type: 'hit', ruleId: REDDIT }, { id: 'ext', url: 'https://reddit.com/' });
  fake.pageMessage({ type: 'hit', ruleId: '33333333-3333-4333-8333-333333333333' }, page);
  fake.pageMessage({ type: 'hit', ruleId: REDDIT }, page);
  await settle();
  assert.deepEqual(port.posted.slice(1), [{ type: 'hit', ruleId: REDDIT }]);
});
