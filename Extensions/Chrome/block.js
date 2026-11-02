// The block page: plain and functional until the visual pass. All text goes in through textContent.
import { blockPageView, formatRemaining } from './state.js';

const params = new URLSearchParams(location.search);
const ruleId = params.get('rule');
const swept = params.get('swept') === '1';
const $ = (id) => document.getElementById(id);
let stored = { state: null, connected: false };
let counted = false;

function render() {
  const view = blockPageView(stored.state, stored.connected, ruleId, Date.now());
  if (!view.blocked) {
    $('site').textContent = '';
    $('headline').textContent = "This site isn't blocked right now";
    $('time').textContent = '';
    $('until').textContent = 'Reload the page to open it.';
    $('note').textContent = '';
    return;
  }
  if (!counted) {
    counted = true;
    chrome.runtime.sendMessage({ type: 'hit', ruleId: view.ruleId }).catch(() => {});
  }
  $('site').textContent = view.label === view.domain ? `${view.domain} is blocked` : `${view.label} (${view.domain}) is blocked`;
  $('headline').textContent = view.task ? view.task.title : 'Focus hours';
  $('time').textContent = view.paused ? 'Paused' : view.until ? formatRemaining(view.until - Date.now()) : '';
  $('until').textContent = view.until
    ? `Blocking until ${new Date(view.until).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}` : '';
  $('note').textContent = [view.strict ? 'Strict session.' : '', view.connected ? '' : "Three isn't connected right now."]
    .filter(Boolean).join(' ');
}

async function load() {
  stored = await chrome.storage.session.get({ state: null, connected: false });
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
