// Pure logic shared by the service worker and the block page, kept free of chrome.* so Node can test it.

export const HOST = 'com.deyalla.three';
export const PROTOCOL = 1;
/** Rules never outlive this without a fresh state, whatever lease the host claims. */
export const MAX_LEASE_MS = 3 * 60_000;
/** Matches BlockRule.maxDomains, including room for maximum-length domains in a native message. */
export const MAX_RULES = 1000;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DOMAIN = /^(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/;
const COLOR = /^#[0-9a-f]{6}$/i;
const REASONS = new Set(['focus', 'overrun', 'paused', 'focusHours']);

/** A host message as the state the extension keeps, or null when any field is off. */
export function parseState(msg, now) {
  if (!msg || typeof msg !== 'object' || msg.type !== 'state' || msg.protocol !== PROTOCOL) return null;
  if (typeof msg.active !== 'boolean' || typeof msg.strict !== 'boolean' || !Number.isFinite(msg.validUntil)) return null;
  const validUntil = Math.min(msg.validUntil, now + MAX_LEASE_MS);
  if (validUntil <= now || !Array.isArray(msg.rules) || msg.rules.length > MAX_RULES) return null;
  const rules = [];
  for (const r of msg.rules) {
    if (!r || typeof r.id !== 'string' || !UUID.test(r.id) || typeof r.domain !== 'string' || !DOMAIN.test(r.domain)
      || typeof r.label !== 'string' || r.label.length > 253) return null;
    if (!rules.some((seen) => seen.id === r.id)) rules.push({ id: r.id, domain: r.domain, label: r.label });
  }
  if (msg.reason !== null && !REASONS.has(msg.reason)) return null;
  if (msg.until !== null && !Number.isFinite(msg.until)) return null;
  let task = null;
  if (msg.task !== null) {
    if (!msg.task || typeof msg.task.title !== 'string') return null;
    task = { title: Array.from(msg.task.title).slice(0, 200).join(''), color: typeof msg.task.color === 'string' && COLOR.test(msg.task.color) ? msg.task.color : null };
  }
  return { active: msg.active, reason: msg.reason, task, until: msg.until, strict: msg.strict, rules: msg.active ? rules : [], validUntil };
}

/** The rules to enforce at `now`. None once the host's lease lapses. */
export function rulesInForce(state, now) {
  return state && state.active && state.validUntil > now ? state.rules : [];
}

/** The block page for a rule. Only the rule id travels; the blocked address is never kept. */
export function blockPagePath(ruleId, swept = false) {
  return `/block.html?rule=${encodeURIComponent(ruleId)}${swept ? '&swept=1' : ''}`;
}

export function sessionRules(rules) {
  return rules.map((r, i) => ({
    id: i + 1,
    priority: 1,
    action: { type: 'redirect', redirect: { extensionPath: blockPagePath(r.id) } },
    condition: { requestDomains: [r.domain], resourceTypes: ['main_frame'] },
  }));
}

const signature = (dnr) => dnr
  .map((r) => `${(r.condition?.requestDomains ?? []).join(',')} ${r.action?.redirect?.extensionPath ?? ''}`)
  .sort().join('\n');

/** True when the installed session rules already enforce exactly `rules`. */
export function sameRules(installed, rules) {
  return signature(installed) === signature(sessionRules(rules));
}

/** Label-boundary match, as declarativeNetRequest's requestDomains does: reddit.com covers old.reddit.com only. */
export function hostMatches(host, domain) {
  const h = host.toLowerCase().replace(/\.$/, '');
  return h === domain || h.endsWith(`.${domain}`);
}

/** Open http(s) tabs on a blocked site, each with its most specific rule. */
export function tabsToBlock(tabs, rules) {
  const hits = [];
  for (const tab of tabs) {
    let url;
    try { url = new URL(tab.url ?? ''); } catch { continue; }
    if ((url.protocol !== 'http:' && url.protocol !== 'https:') || tab.id === undefined) continue;
    const matching = rules.filter((r) => hostMatches(url.hostname, r.domain));
    if (matching.length) {
      const rule = matching.reduce((a, b) => (b.domain.length > a.domain.length ? b : a));
      hits.push({ tabId: tab.id, ruleId: rule.id });
    }
  }
  return hits;
}

/**
 * Everything the block page may show for `ruleId`. This is the contract the page's visual design builds on:
 * blocked, ruleId, label, domain, reason ('focus' | 'overrun' | 'paused' | 'focusHours'), task ({ title, color } or null),
 * until (ms, "Blocking until"), paused, strict, connected (a live link to Three now) and validUntil (ms; without a
 * fresh state from Three, blocking lapses then).
 */
export function blockPageView(state, connected, ruleId, now) {
  const rule = rulesInForce(state, now).find((r) => r.id === ruleId);
  if (!rule) return { blocked: false };
  return {
    blocked: true,
    ruleId: rule.id,
    label: rule.label,
    domain: rule.domain,
    reason: state.reason,
    task: state.task,
    until: state.until,
    paused: state.reason === 'paused',
    strict: state.strict,
    connected: Boolean(connected),
    validUntil: state.validUntil,
  };
}

export function formatRemaining(ms) {
  const s = Math.max(0, Math.ceil(ms / 1000));
  const pad = (n) => String(n).padStart(2, '0');
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
  return h ? `${h}:${pad(m)}:${pad(s % 60)}` : `${m}:${pad(s % 60)}`;
}
