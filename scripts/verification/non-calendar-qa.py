#!/usr/bin/env python3
"""Create isolated non-calendar native fixtures and capture preservation fingerprints."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/verification/non-calendar'
BASE = 'e4f91f169bacf4e4d10c4574623fa3372d16fdc0'
PROD = Path.home() / 'Library/Application Support/Three/three.sqlite'
MANUAL = Path.home() / '.t3/worktrees/adhd/t3-fe1cb47d/build/manual-testing/20261103-133256/three.sqlite'
EXES = [Path.home() / 'Applications/Three.app/Contents/MacOS/ThreeApp', MANUAL.parent / 'Three Manual Test.app/Contents/MacOS/ThreeManualTest']
PIDS = [92331, 29492]


def run(*args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, capture_output=True, text=True, **kwargs).stdout


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fingerprint(path):
    with sqlite3.connect(f'{path.as_uri()}?mode=ro', uri=True) as db:
        db.execute('BEGIN')
        result = {}
        for (name,) in db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").fetchall():
            quoted = '"' + name.replace('"', '""') + '"'
            rows = sorted(json.dumps(row, default=lambda x: {'hex': x.hex()}, ensure_ascii=True) for row in db.execute(f'SELECT * FROM {quoted}'))
            result[name] = {'rows': len(rows), 'sha256': hashlib.sha256('\n'.join(rows).encode()).hexdigest()}
        return result


def capture(label):
    OUT.mkdir(parents=True, exist_ok=True)
    result = {}
    for name, pid, exe, db in zip(('production', 'manual'), PIDS, EXES, (PROD, MANUAL)):
        details = subprocess.run(['ps', '-p', str(pid), '-o', 'pid=,lstart=,command='], capture_output=True, text=True).stdout.strip()
        files = subprocess.run(['lsof', '-n', '-P', '-p', str(pid)], capture_output=True, text=True).stdout
        result[name] = {'pid': pid, 'process': details or None, 'expected_process_and_database_open': str(exe) in details and str(db) in files, 'executable': str(exe), 'executable_sha256': digest(exe), 'database': str(db), 'tables': fingerprint(db)}
        (OUT / f'lsof-{name}-{label}.txt').write_text('\n'.join(line for line in files.splitlines() if str(db) in line or str(exe) in line) + '\n')
    target = OUT / f'preservation-{label}.json'
    target.write_text(json.dumps(result, indent=2) + '\n')
    print(target)


def prepare():
    run('git', 'merge-base', '--is-ancestor', BASE, 'HEAD')
    changed = run('git', 'diff', '--name-only', BASE, '--', 'Sources', 'Resources', 'Extensions', 'Package.swift', 'Package.resolved', 'VERSION', 'scripts/bundle.sh', 'scripts/swift.sh')
    if changed:
        raise RuntimeError('Build inputs differ from the specified baseline commit')
    OUT.mkdir(parents=True, exist_ok=True)
    data = Path(tempfile.mkdtemp(prefix='three-non-calendar-qa-'))
    app = data / 'Three Noncalendar QA.app'
    shutil.copytree(ROOT / 'build/Three.app', app)
    suffix = uuid.uuid4().hex[:12]
    exe = 'ThreeNoncalendarQA' + suffix
    plist = app / 'Contents/Info.plist'
    info = plistlib.loads(plist.read_bytes())
    info.update(CFBundleName='Three Noncalendar QA', CFBundleDisplayName='Three Noncalendar QA', CFBundleIdentifier='com.deyalla.three.noncalendarqa.' + suffix, CFBundleExecutable=exe)
    plist.write_bytes(plistlib.dumps(info))
    (app / 'Contents/MacOS/ThreeApp').rename(app / 'Contents/MacOS' / exe)
    for item in (app / 'Contents/Helpers/three-native-host', app / 'Contents/Helpers/three', app):
        run('codesign', '--force', '--sign', '-', item)
    run('codesign', '--verify', '--deep', '--strict', app)
    chrome = data / 'chrome'
    chrome.mkdir()
    database = data / 'three.sqlite'
    helper = app / 'Contents/Helpers/three'
    env = dict(os.environ, THREE_DB=str(database), THREE_CHROME_DATA=str(chrome))
    run(helper, 'today', env=env)
    today = dt.date.today()
    previous = today.replace(day=1) - dt.timedelta(days=1)
    timestamp = today.isoformat() + ' 09:00:00.000'
    with sqlite3.connect(database) as db:
        db.execute('PRAGMA foreign_keys=ON')
        category = db.execute("SELECT id FROM category WHERE name='Coding'").fetchone()[0]
        db.execute("INSERT OR REPLACE INTO preference(key,value) VALUES('planning',?)", (json.dumps({'enabled': False, 'localTime': '09:30', 'command': 'true'}),))
        for ident, day in [('old', previous), ('today', today)]:
            db.execute("INSERT INTO dayPlan(id,day,status,source,createdAt,committedAt,updatedAt) VALUES(?,?,'committed','app',?,?,?)", (ident, day.isoformat(), timestamp, timestamp, timestamp))
        for ident, plan, pos, title, status in [('source','old',0,'Carry baseline','carried'), ('copy','today',0,'Carry baseline','todo'), ('done','today',1,'Completed baseline','done'), ('paused','today',2,'Paused baseline','active')]:
            db.execute("INSERT INTO task(id,dayPlanId,position,title,categoryId,blockMinutes,strict,status,notes,createdBy,updatedAt,doneAt) VALUES(?,?,?,?,?,25,0,?,'fixture','app',?,?)", (ident, plan, pos, title, category, status, timestamp, timestamp if status == 'done' else None))
        db.execute("INSERT INTO session(id,taskId,kind,plannedSeconds,startedAt,pausedSeconds,endedAt,endReason,outcome,focusRating,note,updatedAt,reflectionPending) VALUES('reflection','done','focus',1500,?,300,?,'completed','done',3,'Fixture reflection',?,0)", (previous.isoformat()+' 10:00:00.000', previous.isoformat()+' 10:30:00.000', timestamp))
        db.execute("INSERT INTO session(id,kind,plannedSeconds,startedAt,pausedSeconds,endedAt,endReason,updatedAt,reflectionPending) VALUES('break','break',300,?,0,?,'completed',?,0)", (previous.isoformat()+' 10:30:00.000', previous.isoformat()+' 10:35:00.000', timestamp))
        db.execute("INSERT INTO session(id,taskId,kind,plannedSeconds,startedAt,pausedAt,pausedSeconds,updatedAt,reflectionPending) VALUES('paused','paused','focus',1500,?,?,0,?,0)", (timestamp, today.isoformat()+' 09:05:00.000', timestamp))
        assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        assert not db.execute('PRAGMA foreign_key_check').fetchall()
        migrations = [x[0] for x in db.execute('SELECT identifier FROM grdb_migrations')]
        assert migrations[-1] == 'v10-planning-supervisor'
    pre = data / 'pre-upgrade-v10.sqlite'
    with sqlite3.connect(database) as source, sqlite3.connect(pre) as dest:
        source.backup(dest)
    expectations = {'today': today.isoformat(), 'previous_month_day': previous.isoformat(), 'empty_day': (previous - dt.timedelta(days=1)).isoformat(), 'focus_elapsed_seconds': 1500, 'break_seconds_excluded': 300, 'carried_source': 'source', 'copy': 'copy', 'paused_session': 'paused', 'reflection': 'reflection', 'planning_enabled': False, 'schema': migrations}
    manifest = {'source': BASE, 'app': str(app), 'executable': str(app / 'Contents/MacOS' / exe), 'bundle_id': info['CFBundleIdentifier'], 'database': str(database), 'pre_upgrade_v10': str(pre), 'chrome': str(chrome), 'helper': str(helper), 'executable_sha256': digest(app / 'Contents/MacOS' / exe), 'expectations': expectations}
    (data / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('action', choices=('capture', 'prepare'))
parser.add_argument('label', nargs='?', default='before', choices=('before', 'after'))
args = parser.parse_args()
capture(args.label) if args.action == 'capture' else prepare()
