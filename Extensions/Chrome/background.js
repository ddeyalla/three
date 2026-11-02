// Keeps Chrome's session rules matching what Three says to block. Session rules vanish when Chrome quits, and
// every state carries a lease, so blocking can't outlive Three: with no fresh state, the rules lapse.
// The extension sends Three only a hello and the ids of rules that matched; never an address.
import { HOST, PROTOCOL, blockPagePath, parseState, rulesInForce, sameRules, sessionRules, tabsToBlock } from './state.js';

let port = null;
let queue = Promise.resolve();

/** Rule updates and sweeps run one at a time, in arrival order. */
function serial(task) {
  queue = queue.then(task).catch((error) => console.error('Three:', error));
  return queue;
}

async function stored() {
  const { state = null } = await chrome.storage.session.get('state');
  return state;
}

async function enforce(state) {
  const rules = rulesInForce(state, Date.now());
  const installed = await chrome.declarativeNetRequest.getSessionRules();
  if (!sameRules(installed, rules)) {
    await chrome.declarativeNetRequest.updateSessionRules({ removeRuleIds: installed.map((r) => r.id), addRules: sessionRules(rules) });
    // Rules only act on new requests, so pages already open on a newly blocked site are sent to the block page.
    if (rules.length) await sweep(rules);
  }
  if (rules.length) await chrome.alarms.create('lease', { when: state.validUntil });
  else await chrome.alarms.clear('lease');
}

async function sweep(rules) {
  const tabs = await chrome.tabs.query({ url: ['http://*/*', 'https://*/*'] });
  await Promise.all(tabsToBlock(tabs, rules).map(({ tabId, ruleId }) =>
    chrome.tabs.update(tabId, { url: chrome.runtime.getURL(blockPagePath(ruleId, true)) }).catch(() => {})));
}

async function clientId() {
  const { clientId: id } = await chrome.storage.local.get('clientId');
  if (id) return id;
  const fresh = crypto.randomUUID();
  await chrome.storage.local.set({ clientId: fresh });
  return fresh;
}

async function reportPermissions(p) {
  const [hostAccess, id] = await Promise.all([
    chrome.permissions.contains({ origins: ['<all_urls>'] }), clientId(),
  ]);
  if (port !== p) return;
  try {
    p.postMessage({ type: 'hello', protocol: PROTOCOL, clientId: id, version: chrome.runtime.getManifest().version, hostAccess });
  } catch {
    // onDisconnect schedules the retry if the port closes during the permission check.
  }
}

function connect() {
  if (port) return;
  let p;
  try {
    p = chrome.runtime.connectNative(HOST);
  } catch {
    chrome.alarms.create('reconnect-soon', { delayInMinutes: 0.5 });
    return;
  }
  port = p;
  p.onMessage.addListener((msg) => {
    const state = parseState(msg, Date.now());
    if (!state) return console.warn('Three: ignored a message that is not a valid state');
    serial(async () => {
      await chrome.storage.session.set({ state, connected: true });
      await enforce(state);
    });
  });
  p.onDisconnect.addListener(() => {
    void chrome.runtime.lastError;
    if (port === p) port = null;
    chrome.storage.session.set({ connected: false });
    // The current rules stay until their lease; reconnecting before then keeps blocking seamless.
    chrome.alarms.create('reconnect-soon', { delayInMinutes: 0.5 });
  });
  serial(() => reportPermissions(p));
}

function permissionsChanged() {
  serial(async () => {
    if (port) await reportPermissions(port);
    await sweep(rulesInForce(await stored(), Date.now()));
  });
}

chrome.permissions.onAdded.addListener(permissionsChanged);
chrome.permissions.onRemoved.addListener(permissionsChanged);

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'lease') serial(async () => enforce(await stored()));
  if (alarm.name === 'reconnect' || alarm.name === 'reconnect-soon') {
    if (port) serial(() => reportPermissions(port));
    else connect();
    serial(async () => enforce(await stored()));
  }
});

chrome.runtime.onMessage.addListener((msg, sender) => {
  if (sender.id !== chrome.runtime.id || !sender.url?.startsWith(chrome.runtime.getURL('block.html'))) return;
  if (msg?.type !== 'hit' || typeof msg.ruleId !== 'string') return;
  serial(async () => {
    if (!port || !rulesInForce(await stored(), Date.now()).some((r) => r.id === msg.ruleId)) return;
    try { port.postMessage({ type: 'hit', ruleId: msg.ruleId }); } catch { /* disconnected */ }
  });
});

chrome.alarms.create('reconnect', { periodInMinutes: 1 });
// A restarted worker has no port yet, and drops rules whose lease lapsed at once instead of waiting for the alarm.
serial(async () => {
  await chrome.storage.session.set({ connected: false });
  await enforce(await stored());
});
connect();
