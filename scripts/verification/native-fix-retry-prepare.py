#!/usr/bin/env python3
"""Prepare an isolated native QA bundle from the pinned debug candidate."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path('/Users/divyanshudv/Documents/code-deyalla/adhd/build/Three.app')
HEAD = '35e9da278d31311db18006371dbe6988ef274b2d'
PRODUCT = '7e0e382eab1f4f8a3b556f685fb9615f826370a1'
HASHES = {'Contents/MacOS/ThreeApp': '41095bbf08ac0d5e1a80ff213acf6b8b931f2ed401b60f103ff0881f783e1f73',
          'Contents/Helpers/three': '5123937f55ab4c2bc21c73896c3fd186644372e36f80f8da4c73f408cfde778d'}

def run(*args, env=None):
    return subprocess.run([str(x) for x in args], cwd=ROOT, env=env, check=True, capture_output=True, text=True).stdout

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

run('git', 'merge-base', '--is-ancestor', HEAD, 'HEAD')
inputs = ('Sources', 'Resources', 'Extensions', 'Package.swift', 'Package.resolved', 'VERSION', 'scripts/bundle.sh', 'scripts/swift.sh')
assert not run('git', 'diff', '--name-only', HEAD, '--', *inputs), 'Candidate inputs changed'
assert not run('git', 'status', '--porcelain', '--untracked-files=all', '--', *inputs), 'Dirty candidate inputs'
for path, expected in HASHES.items():
    assert digest(SOURCE / path) == expected, f'Input hash mismatch: {path}'
run('codesign', '--verify', '--deep', '--strict', SOURCE)
base = ROOT / 'build/verification/non-calendar' / ('retry-' + uuid.uuid4().hex[:12])
base.mkdir(parents=True)
app = base / 'Three Retry QA.app'
shutil.copytree(SOURCE, app)
for path, expected in HASHES.items():
    assert digest(app / path) == expected, f'Copy hash mismatch: {path}'
suffix = base.name.split('-')[-1]
exe = 'ThreeRetryQA' + suffix
plist = app / 'Contents/Info.plist'
info = plistlib.loads(plist.read_bytes())
info.update(CFBundleName='Three Retry QA', CFBundleDisplayName='Three Retry QA',
            CFBundleIdentifier='com.deyalla.three.retryqa.' + suffix, CFBundleExecutable=exe)
plist.write_bytes(plistlib.dumps(info))
(app / 'Contents/MacOS/ThreeApp').rename(app / 'Contents/MacOS' / exe)
for target in (app / 'Contents/Helpers/three-native-host', app / 'Contents/Helpers/three', app):
    run('codesign', '--force', '--sign', '-', target)
run('codesign', '--verify', '--deep', '--strict', app)
source_text = run('otool', '-s', '__TEXT', '__text', SOURCE / 'Contents/MacOS/ThreeApp').splitlines()[2:]
copy_text = run('otool', '-s', '__TEXT', '__text', app / 'Contents/MacOS' / exe).splitlines()[2:]
assert source_text == copy_text
helper = app / 'Contents/Helpers/three'
chrome = base / 'chrome'
chrome.mkdir()
watched, other = base / 'watched.sqlite', base / 'other.sqlite'
env = dict(os.environ, THREE_DB=str(watched), THREE_CHROME_DATA=str(chrome))
run(helper, 'today', env=env)
with sqlite3.connect(watched) as db:
    db.execute("INSERT OR REPLACE INTO preference(key,value) VALUES('planning',?)", (json.dumps({'enabled': False, 'localTime': '09:30', 'command': 'true'}),))
run(helper, 'plan', 'Active focus:Coding:60', 'Companion:Writing:30', '--commit', env=env)
run(helper, 'today', env=dict(env, THREE_DB=str(other)))
manifest = {'head': HEAD, 'product_source': PRODUCT, 'source_bundle': str(SOURCE), 'input_sha256': HASHES,
            'app': str(app), 'bundle_id': info['CFBundleIdentifier'], 'executable': str(app / 'Contents/MacOS' / exe),
            'signed_executable_sha256': digest(app / 'Contents/MacOS' / exe), 'text_sha256': hashlib.sha256('\n'.join(source_text).encode()).hexdigest(),
            'helper': str(helper), 'signed_helper_sha256': digest(helper), 'database': str(watched), 'other_database': str(other), 'chrome': str(chrome)}
(base / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest, indent=2))
