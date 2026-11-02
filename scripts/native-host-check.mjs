#!/usr/bin/env node
// Drives `three native-host` the way Chrome does, against a scratch database, and checks the protocol.
// Usage: node scripts/native-host-check.mjs [path/to/three] [--timer]
// --timer also waits up to two minutes for a focus-hours window to end on its own. When three-native-host
// sits beside three, as in the app bundle, Chrome's entry point through it is checked too.
import { spawn, execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { existsSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import assert from 'node:assert/strict';
import { parseState } from '../Extensions/Chrome/state.js';

const args = process.argv.slice(2);
const three = args.find((a) => !a.startsWith('--')) ?? 'build/Three.app/Contents/Helpers/three';
const withTimer = args.includes('--timer');
const ORIGIN = 'chrome-extension://mgaphdelplkgbnffedmakgpemgnhnaai/';
const env = { ...process.env, THREE_DB: join(mkdtempSync(join(tmpdir(), 'three-host-')), 'three.sqlite') };
const cli = (...a) => execFileSync(three, a, { env, encoding: 'utf8' });
const status = () => JSON.parse(cli('block', 'status', '--json'));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function frame(body) {
  const bytes = Buffer.isBuffer(body) ? body : Buffer.from(JSON.stringify(body));
  const head = Buffer.alloc(4);
  head.writeUInt32LE(bytes.length);
  return Buffer.concat([head, bytes]);
}

class Host {
  constructor(argv = [ORIGIN], launcher = null) {
    this.proc = launcher ? spawn(launcher, argv, { env }) : spawn(three, ['native-host', ...argv], { env });
    this.pending = Buffer.alloc(0);
    this.frames = [];
    this.read = 0;
    this.stdoutBytes = 0;
    this.stderr = '';
    this.proc.stdout.on('data', (d) => {
      this.stdoutBytes += d.length;
      this.pending = Buffer.concat([this.pending, d]);
      while (this.pending.length >= 4) {
        const n = this.pending.readUInt32LE(0);
        if (this.pending.length < 4 + n) break;
        // Anything on stdout that isn't a JSON frame fails here.
        this.frames.push(JSON.parse(this.pending.subarray(4, 4 + n).toString('utf8')));
        this.pending = this.pending.subarray(4 + n);
      }
    });
    this.proc.stderr.on('data', (d) => (this.stderr += d));
    this.exited = new Promise((r) => this.proc.on('exit', (code) => r(code)));
  }

  async next(what, test, ms = 5000) {
    const until = Date.now() + ms;
    while (Date.now() < until) {
      while (this.read < this.frames.length) {
        const f = this.frames[this.read++];
        if (test(f)) return f;
      }
      await sleep(25);
    }
    assert.fail(`no frame for: ${what}. stderr: ${this.stderr}`);
  }

  async quiet(ms) {
    const before = this.frames.length;
    await sleep(ms);
    return this.frames.length - before;
  }

  send(body) { this.proc.stdin.write(frame(body)); }
}

const results = [];
const check = (name) => results.push(name) && console.log(`ok  ${name}`);

cli('block', 'add', 'reddit');
const title = '😀' + 'a'.repeat(199);
cli('add', title, '--block', '60m');
const reddit = status().rules.find((r) => r.value === 'reddit.com');

const host = new Host();
let f = await host.next('initial state', (m) => m.type === 'state');
assert.equal(f.active, false);
assert.deepEqual(f.rules, []);
assert.ok(f.validUntil > Date.now() + 100_000 && f.validUntil <= Date.now() + 121_000, 'lease is about two minutes');
check('pushes an inactive state with a two-minute lease on start');

host.send({ type: 'hello', protocol: 1, clientId: randomUUID(), version: '0.3.0', hostAccess: true });
await host.next('state after hello', (m) => m.type === 'state');
await sleep(200);
assert.equal(status().chrome.connectedProfiles, 1);
check('hello registers one connected profile');

cli('start', '--min', '25');
f = await host.next('focus push', (m) => m.active && m.reason === 'focus');
assert.deepEqual(f.rules.map((r) => r.domain).sort(), ['redd.it', 'reddit.com']);
assert.equal(f.task.title, title);
assert.equal(parseState(f, Date.now()).rules.length, 2, 'the extension accepts the real host state with a Unicode title');
assert.match(f.task.color, /^#[0-9A-F]{6}$/i);
assert.ok(Math.abs(f.until - (Date.now() + 25 * 60_000)) < 10_000, 'until is the planned end');
check('three start pushes the rules with task and until');

host.send({ type: 'hit', ruleId: reddit.id });
host.send({ type: 'hit', ruleId: reddit.id });
assert.equal(await host.quiet(700), 0, 'hits must not echo back as pushes');
assert.equal(status().rules.find((r) => r.id === reddit.id).hitsToday, 1);
check('a hit is recorded once, and the write does not cause a push');

host.proc.stdin.write(frame(Buffer.from('{not json')));
host.send({ type: 'removeRule', ruleId: reddit.id });
host.send({ type: 'hit', ruleId: randomUUID() });
host.send({ type: 'hello', protocol: 1, clientId: '../etc', version: '1', hostAccess: true });
cli('pause');
f = await host.next('paused push', (m) => m.reason === 'paused');
assert.ok(Math.abs(f.until - (Date.now() + 15 * 60_000)) < 10_000, 'paused until is 15 minutes after the pause');
assert.equal(status().rules.find((r) => r.id === reddit.id).value, 'reddit.com');
assert.match(host.stderr, /ignored a message outside the protocol/);
check('malformed and unknown messages are ignored; pause pushes the 15-minute bound');

cli('resume');
await host.next('resumed push', (m) => m.reason === 'focus');
cli('stop');
f = await host.next('stop push', (m) => m.active === false);
assert.deepEqual(f.rules, []);
check('resume and stop push the matching states');

if (withTimer) {
  // A window from the last minute to the next one ends on its own; the host must push without any write.
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  const hhmm = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  const start = new Date(now.getTime() - 60_000), end = new Date(now.getTime() + 60_000);
  const day = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'][now.getDay()];
  if (start.getDate() === end.getDate()) {
    cli('block', 'hours', 'add', day, `${hhmm(start)}-${hhmm(end)}`);
    await host.next('focus hours push', (m) => m.reason === 'focusHours');
    await host.next('focus hours end push', (m) => m.active === false, 130_000);
    check('focus hours start and end push on their own, from the wall-clock timer');
  } else {
    console.log('skip timer check: too close to midnight');
  }
}

assert.equal(host.pending.length, 0, 'no trailing bytes on stdout');
assert.ok(host.frames.every((m) => m.type === 'state' && m.protocol === 1), 'every frame is a state');
host.proc.stdin.end();
assert.equal(await host.exited, 0);
check(`EOF exits 0; ${host.frames.length} frames, ${host.stdoutBytes} bytes, all protocol`);

const big = new Host();
await big.next('initial state', (m) => m.type === 'state');
const head = Buffer.alloc(4);
head.writeUInt32LE(1024 * 1024);
big.proc.stdin.write(head);
assert.notEqual(await big.exited, 0);
assert.match(big.stderr, /aren't part of the protocol/);
check('an oversize frame closes the host with a stderr diagnostic');

const partial = new Host();
await partial.next('initial state', (m) => m.type === 'state');
partial.proc.stdin.end(frame({ type: 'hit', ruleId: reddit.id }).subarray(0, 7));
assert.equal(await partial.exited, 0);
assert.match(partial.stderr, /closed in the middle of a message/);
check('EOF mid-frame exits cleanly and says so');

const stranger = new Host(['chrome-extension://abcdefghijklmnopabcdefghijklmnop/']);
assert.notEqual(await stranger.exited, 0);
assert.equal(stranger.stdoutBytes, 0);
check('another extension origin is refused with nothing on stdout');

const windows = new Host([ORIGIN, '--parent-window=0']);
await windows.next('initial state', (m) => m.type === 'state');
windows.proc.stdin.end();
assert.equal(await windows.exited, 0);
check('extra launch arguments are tolerated');

const launcher = join(dirname(three), 'three-native-host');
if (existsSync(launcher)) {
  const chrome = new Host([ORIGIN], launcher);
  await chrome.next('initial state through the launcher', (m) => m.type === 'state');
  chrome.proc.stdin.end();
  assert.equal(await chrome.exited, 0);
  check('the bundled launcher starts the host with only the origin, as Chrome does');
}

console.log(`\n${results.length} checks passed against ${three}`);
