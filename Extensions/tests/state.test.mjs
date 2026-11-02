import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_LEASE_MS, MAX_RULES, blockPageView, hostMatches, parseState, rulesInForce, sameRules, sessionRules, tabsToBlock,
} from '../Chrome/state.js';

const now = 1_800_000_000_000;
const REDDIT = '11111111-1111-4111-8111-111111111111';
const X = '22222222-2222-4222-8222-222222222222';
const host = (over = {}) => ({
  type: 'state', protocol: 1, validUntil: now + 120_000, active: true, reason: 'focus', strict: false,
  until: now + 25 * 60_000, task: { title: 'Write PRD', color: '#6E9BF2' },
  rules: [{ id: REDDIT, domain: 'reddit.com', label: 'Reddit' }, { id: X, domain: 'x.com', label: 'X' }],
  ...over,
});

test('accepts a host state and clamps its lease', () => {
  const s = parseState(host({ validUntil: now + 24 * 3600_000 }), now);
  assert.equal(s.validUntil, now + MAX_LEASE_MS);
  assert.deepEqual(s.rules.map((r) => r.domain), ['reddit.com', 'x.com']);
  assert.deepEqual(s.task, { title: 'Write PRD', color: '#6E9BF2' });
});

test('rejects any state it cannot trust', () => {
  const bad = [
    host({ protocol: 2 }), host({ validUntil: now }), host({ active: 'yes' }), host({ reason: 'bypass' }),
    host({ rules: [{ id: 'not-a-uuid', domain: 'reddit.com', label: 'Reddit' }] }),
    host({ rules: [{ id: REDDIT, domain: 'reddit.com/r/adhd', label: 'Reddit' }] }),
    host({ rules: [{ id: REDDIT, domain: '*.reddit.com', label: 'Reddit' }] }),
    host({ rules: [{ id: REDDIT, domain: 'Reddit.com', label: 'Reddit' }] }),
    host({ rules: Array.from({ length: MAX_RULES + 1 }, () => ({ id: REDDIT, domain: 'reddit.com', label: 'Reddit' })) }),
    host({ task: { title: 7 } }), host({ until: 'soon' }), null, 'state',
  ];
  for (const msg of bad) assert.equal(parseState(msg, now), null, JSON.stringify(msg)?.slice(0, 80));
});

test('Unicode display titles cannot invalidate blocking rules', () => {
  for (const title of ['😀' + 'a'.repeat(199), 'a' + '\u0301'.repeat(10_000)]) {
    const parsed = parseState(host({ task: { title, color: '#6E9BF2' } }), now);
    assert.equal(parsed.rules.length, 2);
    assert.equal(parsed.task.title, Array.from(title).slice(0, 200).join(''));
  }
});

test('existing lists above the new Store limit still enforce all their rules', () => {
  for (const count of [1001, MAX_RULES]) {
    const rules = Array.from({ length: count }, (_, i) => ({
      id: `00000000-0000-4000-8000-${i.toString(16).padStart(12, '0')}`,
      domain: `legacy${i}.example.com`, label: `legacy${i}.example.com`,
    }));
    const parsed = parseState(host({ rules }), now);
    assert.equal(rulesInForce(parsed, now).length, count);
    assert.equal(sessionRules(parsed.rules).length, count);
  }
});

test('an inactive state carries no rules, and a lapsed lease enforces none', () => {
  assert.deepEqual(parseState(host({ active: false }), now).rules, []);
  const s = parseState(host(), now);
  assert.equal(rulesInForce(s, now + 119_999).length, 2);
  assert.deepEqual(rulesInForce(s, now + 120_000), []);
  assert.deepEqual(rulesInForce(null, now), []);
});

test('session rules redirect only top-level pages of each domain to the block page', () => {
  const rules = sessionRules(parseState(host(), now).rules);
  assert.deepEqual(rules[0], {
    id: 1, priority: 1,
    action: { type: 'redirect', redirect: { extensionPath: `/block.html?rule=${REDDIT}` } },
    condition: { requestDomains: ['reddit.com'], resourceTypes: ['main_frame'] },
  });
  assert.deepEqual(rules.map((r) => r.id), [1, 2]);
});

test('installed rules compare by what they enforce, not their ids', () => {
  const rules = parseState(host(), now).rules;
  const installed = sessionRules(rules).reverse().map((r, i) => ({ ...r, id: 40 + i }));
  assert.ok(sameRules(installed, rules));
  assert.ok(!sameRules(installed, rules.slice(0, 1)));
  assert.ok(!sameRules([], rules));
  assert.ok(sameRules([], []));
});

test('matching follows label boundaries and skips non-web tabs', () => {
  assert.ok(hostMatches('old.reddit.com', 'reddit.com'));
  assert.ok(hostMatches('REDDIT.COM.', 'reddit.com'));
  assert.ok(!hostMatches('notreddit.com', 'reddit.com'));
  assert.ok(!hostMatches('t.co', 'x.com'));
  const rules = [{ id: REDDIT, domain: 'reddit.com' }, { id: X, domain: 'old.reddit.com' }];
  const tabs = [
    { id: 1, url: 'https://www.reddit.com/r/adhd' },
    { id: 2, url: 'https://old.reddit.com/' },
    { id: 3, url: 'https://notreddit.com/' },
    { id: 4, url: 'chrome://extensions/' },
    { id: 5, url: `chrome-extension://abc/block.html?rule=${REDDIT}` },
    { id: 6 },
    { id: 7, url: 'https://bücher.de/' },
  ];
  assert.deepEqual(tabsToBlock(tabs, rules), [{ tabId: 1, ruleId: REDDIT }, { tabId: 2, ruleId: X }]);
  assert.deepEqual(tabsToBlock(tabs, [{ id: REDDIT, domain: 'xn--bcher-kva.de' }]), [{ tabId: 7, ruleId: REDDIT }]);
});

test('the block page view is the contract for the visual pass', () => {
  const s = parseState(host({ reason: 'paused', strict: true }), now);
  assert.deepEqual(blockPageView(s, true, REDDIT, now), {
    blocked: true, ruleId: REDDIT, label: 'Reddit', domain: 'reddit.com', reason: 'paused',
    task: { title: 'Write PRD', color: '#6E9BF2' }, until: now + 25 * 60_000, paused: true, strict: true,
    connected: true, validUntil: now + 120_000,
  });
  assert.deepEqual(blockPageView(s, true, 'unknown', now), { blocked: false });
  assert.deepEqual(blockPageView(s, false, REDDIT, now + 120_000), { blocked: false });
});
