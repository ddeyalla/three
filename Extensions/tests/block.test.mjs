// Runs the real block page against a fake DOM and a fake `chrome`, so its states need no browser.
import { test } from 'node:test';
import assert from 'node:assert/strict';

const REDDIT = '11111111-1111-4111-8111-111111111111';
const NOW = Date.parse('2026-11-03T10:00:00Z');
const settle = () => new Promise((r) => setImmediate(r));
let loads = 0;

function state({ reason = 'focus', task = { title: 'Write the Q4 PRD', color: '#F2766B' }, until = NOW + (23 * 60 + 41) * 1000,
  strict = false, rules = [{ id: REDDIT, domain: 'reddit.com', label: 'Reddit' }], validUntil = NOW + 120_000 } = {}) {
  return { active: true, reason, task, until, strict, rules, validUntil };
}

/** Loads a fresh copy of block.js with `stored` in session storage. Returns the page and its fakes. */
async function page({ stored, rule = REDDIT, swept = false, historyLength = 1, siblings = 2 }) {
  const body = { id: 'body' };
  const doc = {
    activeElement: body,
    body,
    title: '',
    listeners: {},
    accent: null,
    documentElement: { style: { setProperty: (k, v) => { if (k === '--accent') doc.accent = v; } } },
    addEventListener: (type, f) => { doc.listeners[type] = f; },
    getElementById: (id) => els[id],
  };
  const element = (id, init = {}) => ({
    id, textContent: '', hidden: false, className: '', href: '', listeners: {},
    addEventListener(type, f) { this.listeners[type] = f; },
    focus() { doc.activeElement = this; },
    ...init,
  });
  // As block.html starts.
  const els = {
    meta: element('meta'), dot: element('dot', { hidden: true }), title: element('title'), time: element('time'),
    until: element('until'), open: element('open', { hidden: true, className: 'button primary' }),
    back: element('back', { className: 'button primary' }), how: element('how'), connection: element('connection', { hidden: true }),
  };
  doc.activeElement = els.back; // autofocus
  const fake = { session: { ...stored }, sent: [], writes: 0, onChanged: null, tabCalls: [], back: 0, tick: null };
  globalThis.document = doc;
  globalThis.location = { search: `?rule=${rule}${swept ? '&swept=1' : ''}` };
  globalThis.history = { length: historyLength, back: () => { fake.back += 1; } };
  globalThis.chrome = {
    runtime: { sendMessage: async (m) => { fake.sent.push(m); } },
    storage: {
      session: {
        get: async (defaults) => Object.fromEntries(Object.entries(defaults).map(([k, d]) => [k, k in fake.session ? fake.session[k] : d])),
        set: async () => { fake.writes += 1; },
      },
      local: { set: async () => { fake.writes += 1; } },
      onChanged: { addListener: (f) => { fake.onChanged = f; } },
    },
    tabs: {
      getCurrent: async () => ({ id: 7, windowId: 1 }),
      query: async () => Array.from({ length: siblings }, (_, i) => ({ id: i + 7 })),
      remove: async (id) => { fake.tabCalls.push(['remove', id]); },
      update: async (id, props) => { fake.tabCalls.push(['update', id, props.url]); },
    },
  };
  const realInterval = globalThis.setInterval;
  globalThis.setInterval = (f) => { fake.tick = f; return 0; };
  const mod = await import(`../Chrome/block.js?load=${++loads}`);
  globalThis.setInterval = realInterval;
  await settle();
  /** Pushes a new session state, as the service worker does. */
  fake.push = async (next) => {
    Object.assign(fake.session, next);
    fake.onChanged({}, 'session');
    await settle();
  };
  return { els, doc, fake, mod };
}

test('a blocked site names the session, counts down to when blocking ends and offers only Back to work', async (t) => {
  t.mock.method(Date, 'now', () => NOW);
  const { els, doc, fake } = await page({ stored: { state: state(), connected: true } });
  assert.equal(els.meta.textContent, 'reddit.com is blocked during this focus session');
  assert.equal(els.title.textContent, 'Write the Q4 PRD');
  assert.equal(els.dot.hidden, false);
  assert.equal(doc.accent, '#F2766B');
  assert.equal(els.time.textContent, '23:41');
  assert.equal(els.time.className, 'display');
  assert.match(els.until.textContent, /^Until /);
  assert.equal(els.how.textContent, "To open it for 5 minutes, use Unblock in Three's menu bar.");
  assert.equal(els.connection.hidden, true);
  assert.equal(els.open.hidden, true);
  assert.equal(els.back.className, 'button primary');
  assert.equal(doc.title, 'Focus · Three');

  t.mock.method(Date, 'now', () => NOW + 1000);
  fake.tick();
  fake.tick();
  assert.equal(els.time.textContent, '23:40');
  assert.deepEqual(fake.sent, [{ type: 'hit', ruleId: REDDIT }], 'one hit per page, however often it re-renders');
});

test('focus hours, a paused session, a strict task and a lost connection each read plainly', async (t) => {
  t.mock.method(Date, 'now', () => NOW);
  const hours = await page({ stored: { state: state({ reason: 'focusHours', task: null, strict: true }), connected: false } });
  assert.equal(hours.els.meta.textContent, 'reddit.com is blocked during focus hours');
  assert.equal(hours.els.title.textContent, 'Focus hours');
  assert.equal(hours.els.dot.hidden, true);
  assert.equal(hours.doc.accent, '#8C8C8C');
  assert.equal(hours.els.how.textContent, 'Unblocking is off for this task.');
  assert.equal(hours.els.connection.hidden, false);

  const paused = await page({ stored: { state: state({ reason: 'paused' }), connected: true } });
  assert.equal(paused.els.meta.textContent, 'reddit.com is blocked during this focus session');
  assert.equal(paused.els.time.textContent, 'Paused');
  assert.equal(paused.els.time.className, 'display secondary');
  assert.match(paused.els.until.textContent, /^Until /);
});

test('once the site is unblocked the page offers its front page, and Back to work steps back', async (t) => {
  t.mock.method(Date, 'now', () => NOW);
  const { els, doc, fake } = await page({ stored: { state: state(), connected: true } });
  await fake.push({ state: state({ rules: [] }) });
  assert.equal(els.title.textContent, "reddit.com isn't blocked right now");
  assert.equal(els.meta.textContent, '');
  assert.equal(els.time.textContent, '');
  assert.equal(els.open.hidden, false);
  assert.equal(els.open.href, 'https://reddit.com/');
  assert.equal(els.open.textContent, 'Open reddit.com');
  assert.equal(els.back.className, 'button quiet');
  assert.equal(doc.activeElement, els.open, 'the keyboard follows the new primary action');
  assert.equal(doc.title, 'Three');
  assert.equal(fake.writes, 0, 'the page never stores anything, least of all the address');

  await fake.push({ state: state() });
  assert.equal(els.title.textContent, 'Write the Q4 PRD');
  assert.equal(els.open.hidden, true);
  assert.equal(doc.activeElement, els.back);
  assert.equal(fake.sent.length, 1);
});

test('blocking lapses with the lease when Three stops answering', async (t) => {
  t.mock.method(Date, 'now', () => NOW);
  const { els, fake } = await page({ stored: { state: state({ validUntil: NOW + 60_000 }), connected: false } });
  assert.equal(els.connection.hidden, false);
  t.mock.method(Date, 'now', () => NOW + 61_000);
  fake.tick();
  assert.equal(els.title.textContent, "reddit.com isn't blocked right now");
  assert.equal(els.connection.hidden, true);
});

test('a page opened for a rule not in force says so without guessing the address', async (t) => {
  t.mock.method(Date, 'now', () => NOW);
  const { els, fake } = await page({ stored: { state: state({ rules: [] }), connected: true } });
  assert.equal(els.title.textContent, "This site isn't blocked right now");
  assert.equal(els.open.hidden, true);
  assert.equal(els.back.className, 'button primary');
  assert.deepEqual(fake.sent, []);
});

test('Back to work goes back, closes a swept tab, or keeps the last tab open', async (t) => {
  t.mock.method(Date, 'now', () => NOW);
  const stored = { state: state(), connected: true };
  const withHistory = await page({ stored, historyLength: 3 });
  withHistory.els.back.listeners.click();
  await settle();
  assert.equal(withHistory.fake.back, 1);

  const swept = await page({ stored, swept: true, historyLength: 3, siblings: 2 });
  swept.doc.listeners.keydown({ key: 'Escape' });
  await settle();
  assert.equal(swept.fake.back, 0);
  assert.deepEqual(swept.fake.tabCalls, [['remove', 7]]);

  const last = await page({ stored, siblings: 1 });
  last.els.back.listeners.click();
  await settle();
  assert.deepEqual(last.fake.tabCalls, [['update', 7, 'chrome://newtab/']]);
});

test('an end on another day carries its weekday', async (t) => {
  t.mock.method(Date, 'now', () => NOW);
  const { mod } = await page({ stored: { state: state(), connected: true } });
  // Local times, so the case holds in any time zone.
  const morning = new Date(2026, 10, 3, 10, 0).getTime();
  const later = new Date(2026, 10, 3, 23, 30).getTime();
  const tomorrow = new Date(2026, 10, 4, 0, 30).getTime();
  assert.equal(mod.formatUntil(later, morning), new Date(later).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }));
  assert.equal(mod.formatUntil(tomorrow, morning),
    `${new Date(tomorrow).toLocaleDateString([], { weekday: 'short' })} ${new Date(tomorrow).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`);
});
