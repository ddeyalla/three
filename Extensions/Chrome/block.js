// The block page. All text goes in through textContent. Only the rule id arrives in the URL; the blocked address is
// never known here, so "Open" goes to the site's front page, from what this page saw while it was blocked.
import { blockPageView, formatRemaining } from './state.js';

const params = new URLSearchParams(location.search);
const ruleId = params.get('rule');
const swept = params.get('swept') === '1';
const IDLE = '#8C8C8C';
const $ = (id) => document.getElementById(id);
let stored = { state: null, connected: false };
let counted = false;
let loaded = false;
/** The domain this page blocked, kept in memory only, for "Open" once it isn't blocked. */
let lastDomain = null;
let wasBlocked = null;

/** "3:45 PM" later today, else "Sat 2:00 AM", as the app says it. */
export function formatUntil(ms, now) {
  const d = new Date(ms);
  const time = d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  return d.toDateString() === new Date(now).toDateString() ? time : `${d.toLocaleDateString([], { weekday: 'short' })} ${time}`;
}

function setText(id, text) { $(id).textContent = text; }

function render() {
  if (!loaded) return;
  const now = Date.now();
  const view = blockPageView(stored.state, stored.connected, ruleId, now);
  const open = $('open'), back = $('back');
  if (view.blocked) {
    lastDomain = view.domain;
    if (!counted) {
      counted = true;
      chrome.runtime.sendMessage({ type: 'hit', ruleId: view.ruleId }).catch(() => {});
    }
    document.title = 'Focus · Three';
    document.documentElement.style.setProperty('--accent', view.task?.color ?? IDLE);
    setText('meta', `${view.domain} is blocked during ${view.reason === 'focusHours' ? 'focus hours' : 'this focus session'}`);
    $('dot').hidden = !view.task;
    setText('title', view.task ? view.task.title : 'Focus hours');
    setText('time', view.paused ? 'Paused' : view.until ? formatRemaining(view.until - now) : '');
    $('time').className = view.paused ? 'display secondary' : 'display';
    setText('until', view.until ? `Until ${formatUntil(view.until, now)}` : '');
    open.hidden = true;
    back.className = 'button primary';
    setText('how', view.strict ? 'Unblocking is off for this task.' : "To open it for 5 minutes, use Unblock in Three's menu bar.");
    $('connection').hidden = view.connected;
  } else {
    document.title = 'Three';
    document.documentElement.style.setProperty('--accent', IDLE);
    setText('meta', '');
    $('dot').hidden = true;
    setText('title', lastDomain ? `${lastDomain} isn't blocked right now` : "This site isn't blocked right now");
    setText('time', '');
    setText('until', lastDomain
      ? "Three doesn't keep the address you opened, so this goes to the site's front page."
      : "Three doesn't keep the address, so open the site again from where you found it.");
    open.hidden = !lastDomain;
    if (lastDomain) {
      open.href = `https://${lastDomain}/`;
      open.textContent = `Open ${lastDomain}`;
    }
    back.className = lastDomain ? 'button quiet' : 'button primary';
    setText('how', '');
    $('connection').hidden = true;
  }
  // When the state flips, the keyboard follows the new primary action, unless the person has moved it elsewhere.
  if (wasBlocked !== null && wasBlocked !== view.blocked) {
    const primary = view.blocked || !lastDomain ? back : open;
    if (document.activeElement === document.body || document.activeElement === open || document.activeElement === back) primary.focus();
  }
  wasBlocked = view.blocked;
}

async function load() {
  stored = await chrome.storage.session.get({ state: null, connected: false });
  loaded = true;
  render();
}

/** Back in history when that leads somewhere else; a tab that was swept off a blocked site goes to a new tab. */
async function backToWork() {
  if (!swept && history.length > 1) return history.back();
  const tab = await chrome.tabs.getCurrent();
  const siblings = await chrome.tabs.query({ windowId: tab.windowId });
  if (siblings.length > 1) await chrome.tabs.remove(tab.id);
  else await chrome.tabs.update(tab.id, { url: 'chrome://newtab/' });
}

$('back').addEventListener('click', backToWork);
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') backToWork(); });
chrome.storage.onChanged.addListener((_, area) => { if (area === 'session') load(); });
setInterval(render, 1000);
load();
