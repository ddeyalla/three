#!/usr/bin/env python3
"""Prepare an isolated BPRO-399 native app and record production preservation evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import sqlite3
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "build/verification/bpro-399"
NATIVE = ARTIFACTS / "native"
APP = NATIVE / "Three B399 QA.app"
EXE = "ThreeB399QA"


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, capture_output=True, text=True, **kwargs).stdout


def database_snapshot(path):
    if not path.exists():
        return None
    with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as connection:
        connection.execute("BEGIN")
        result = {}
        for (table,) in connection.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").fetchall():
            quoted = '"' + table.replace('"', '""') + '"'
            rows = sorted(json.dumps(row, default=str) for row in connection.execute(f"SELECT * FROM {quoted}"))
            result[table] = {"rows": len(rows), "sha256": hashlib.sha256("\n".join(rows).encode()).hexdigest()}
        return result


def capture(label):
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    production = Path.home() / "Library/Application Support/Three/three.sqlite"
    executable = Path.home() / "Applications/Three.app/Contents/MacOS/ThreeApp"
    process = subprocess.run(["pgrep", "-fl", str(executable)], capture_output=True, text=True).stdout
    pids = ",".join(line.split()[0] for line in process.splitlines())
    result = {"production_database": database_snapshot(production), "production_process": process,
              "production_process_details": run("ps", "-p", pids, "-o", "pid=,lstart=,command=") if pids else "",
              "production_executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest() if executable.exists() else None}
    (ARTIFACTS / f"preservation-{label}.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


def prepare():
    assert not NATIVE.exists(), f"Refusing to replace {NATIVE}"
    NATIVE.mkdir(parents=True)
    shutil.copytree(ROOT / "build/Three.app", APP)
    plist = APP / "Contents/Info.plist"
    info = plistlib.loads(plist.read_bytes())
    info.update(CFBundleName="Three B399 QA", CFBundleDisplayName="Three B399 QA",
                CFBundleIdentifier="com.deyalla.three.b399qa", CFBundleExecutable=EXE)
    plist.write_bytes(plistlib.dumps(info))
    (APP / "Contents/MacOS/ThreeApp").rename(APP / f"Contents/MacOS/{EXE}")
    for target in [APP / "Contents/Helpers/three-native-host", APP / "Contents/Helpers/three", APP]:
        run("codesign", "--force", "--sign", "-", target)
    run("codesign", "--verify", "--deep", "--strict", APP)
    original = run("otool", "-s", "__TEXT", "__text", ROOT / "build/Three.app/Contents/MacOS/ThreeApp").splitlines()[2:]
    copied = run("otool", "-s", "__TEXT", "__text", APP / f"Contents/MacOS/{EXE}").splitlines()[2:]
    assert original == copied, "Relabelled executable instructions differ"
    database = NATIVE / "three.sqlite"
    chrome = NATIVE / "chrome"
    chrome.mkdir()
    helper = APP / "Contents/Helpers/three"
    run(helper, "today", env=dict(os.environ, THREE_DB=str(database), THREE_CHROME_DATA=str(chrome)))
    settings = {"enabled": False, "localTime": "09:30", "command": "printf 'native fixture stdout'; printf 'native fixture error' >&2; exit 9"}
    with sqlite3.connect(database) as connection:
        connection.execute("INSERT INTO preference(key,value) VALUES('planning',?)", [json.dumps(settings)])
    manifest = {"app": str(APP), "executable": str(APP / f"Contents/MacOS/{EXE}"), "database": str(database), "helper": str(helper),
                "chrome": str(chrome), "source": run("git", "rev-parse", "HEAD").strip(),
                "text_sha256": hashlib.sha256("\n".join(original).encode()).hexdigest(),
                "success_command": shlex.join([sys.executable, str(ROOT / "scripts/test-scheduled-planning.py"), "--draft-command"])}
    (NATIVE / "run.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("action", choices=["prepare", "capture"])
parser.add_argument("label", nargs="?", default="before")
args = parser.parse_args()
prepare() if args.action == "prepare" else capture(args.label)
