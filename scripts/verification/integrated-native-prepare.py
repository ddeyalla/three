#!/usr/bin/env python3
"""Build a uniquely identified native QA copy and retain the history fixture."""
import hashlib
import importlib.util
import json
import plistlib
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = '3270869ce3165137f228e3a36243450929bfcfd3'
sys.dont_write_bytecode = True

def run(*args):
    return subprocess.run([str(x) for x in args], cwd=ROOT, check=True, capture_output=True, text=True).stdout

run('git', 'merge-base', '--is-ancestor', EXPECTED, 'HEAD')
inputs = ('Sources', 'Resources', 'Extensions', 'Package.swift', 'Package.resolved', 'VERSION',
          'scripts/bundle.sh', 'scripts/swift.sh', 'scripts/test-history.py', 'scripts/test-mcp.py')
assert not run('git', 'diff', '--name-only', EXPECTED, '--', *inputs), 'Candidate inputs changed'
scratch = Path(tempfile.mkdtemp(prefix='three-integrated-native-')).resolve()
suffix = scratch.name.rsplit('-', 1)[-1]
app = scratch / 'Three Integrated QA.app'
executable = 'ThreeIntegratedQA' + suffix
shutil.copytree(ROOT / 'build/Three.app', app)
plist = app / 'Contents/Info.plist'
info = plistlib.loads(plist.read_bytes())
info.update(CFBundleName='Three Integrated QA', CFBundleDisplayName='Three Integrated QA',
            CFBundleIdentifier='com.deyalla.three.integratedqa.' + suffix.lower(), CFBundleExecutable=executable)
plist.write_bytes(plistlib.dumps(info))
(app / 'Contents/MacOS/ThreeApp').rename(app / 'Contents/MacOS' / executable)
for target in (app / 'Contents/Helpers/three-native-host', app / 'Contents/Helpers/three', app):
    run('codesign', '--force', '--sign', '-', target)
run('codesign', '--verify', '--deep', '--strict', app)
source = ROOT / 'build/Three.app/Contents/MacOS/ThreeApp'
copy = app / 'Contents/MacOS' / executable
source_text = run('otool', '-s', '__TEXT', '__text', source).splitlines()[2:]
copy_text = run('otool', '-s', '__TEXT', '__text', copy).splitlines()[2:]
assert source_text == copy_text
helper = app / 'Contents/Helpers/three'
spec = importlib.util.spec_from_file_location('history_fixture', ROOT / 'scripts/test-history.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
fixture.run(helper, scratch)
database = scratch / 'history.sqlite'
with sqlite3.connect(database) as db:
    db.execute("INSERT OR REPLACE INTO preference(key,value) VALUES('planning',?)", (json.dumps({'enabled': False, 'localTime': '09:30', 'command': 'true'}),))
    assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    assert not db.execute('PRAGMA foreign_key_check').fetchall()
(scratch / 'chrome').mkdir()
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
manifest = {'source': EXPECTED, 'app': str(app), 'bundle_id': info['CFBundleIdentifier'],
            'executable': str(copy), 'executable_sha256': digest(copy), 'source_executable_sha256': digest(source),
            'text_sha256': hashlib.sha256('\n'.join(source_text).encode()).hexdigest(), 'helper': str(helper),
            'database': str(database), 'chrome': str(scratch / 'chrome')}
(scratch / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest, indent=2))
