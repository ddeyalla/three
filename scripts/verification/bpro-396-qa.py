#!/usr/bin/env python3
"""Prepare and inspect an isolated native BPRO-396 run. UI actions belong to CUA."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess


ROOT = Path(__file__).resolve().parents[2]
AUDIT = ROOT / "build/verification/bpro-396"
RUN = AUDIT / "native"
EXE = "ThreeB396QA"
SOURCE_APP = ROOT / "build/Three.app"


def command(*args, **kwargs):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{args}: {result.stdout}{result.stderr}")
    return result.stdout


def snapshot(database):
    with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
        connection.execute("BEGIN")
        tables = connection.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").fetchall()
        result = {}
        for (table,) in tables:
            quoted = '"' + table.replace('"', '""') + '"'
            rows = sorted(json.dumps(row, default=str) for row in connection.execute(f"SELECT * FROM {quoted}"))
            result[table] = {"rows": len(rows), "sha256": hashlib.sha256("\n".join(rows).encode()).hexdigest()}
        return result


def capture(label):
    AUDIT.mkdir(parents=True, exist_ok=True)
    production = Path.home() / "Library/Application Support/Three/three.sqlite"
    output = {"production": snapshot(production) if production.exists() else None}
    protected = [Path.home() / "Applications/Three.app/Contents/MacOS/ThreeApp",
                 Path.home() / "Library/Application Support/Google/Chrome/NativeMessagingHosts/com.deyalla.three.json"]
    output["protected_files"] = {
        str(path): hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None for path in protected
    }
    if (RUN / "three.sqlite").exists():
        output["scratch"] = snapshot(RUN / "three.sqlite")
    output["production_process"] = subprocess.run(
        ["pgrep", "-fl", str(Path.home() / "Applications/Three.app/Contents/MacOS/ThreeApp")],
        capture_output=True, text=True).stdout
    output["production_process_details"] = command("ps", "-p", ",".join(
        line.split()[0] for line in output["production_process"].splitlines()), "-o", "pid=,lstart=,command=") \
        if output["production_process"].strip() else ""
    (AUDIT / f"preservation-{label}.json").write_text(json.dumps(output, indent=2) + "\n")
    print(json.dumps(output, indent=2))


def prepare():
    if RUN.exists():
        raise SystemExit(f"Refusing to overwrite {RUN}")
    RUN.mkdir(parents=True)
    app = RUN / "Three B396 QA.app"
    shutil.copytree(SOURCE_APP, app)
    plist = app / "Contents/Info.plist"
    info = plistlib.loads(plist.read_bytes())
    info.update(CFBundleName="Three B396 QA", CFBundleDisplayName="Three B396 QA",
                CFBundleIdentifier="com.deyalla.three.b396qa", CFBundleExecutable=EXE)
    plist.write_bytes(plistlib.dumps(info))
    (app / "Contents/MacOS/ThreeApp").rename(app / f"Contents/MacOS/{EXE}")
    for target in [app / "Contents/Helpers/three-native-host", app / "Contents/Helpers/three", app]:
        command("codesign", "--force", "--sign", "-", target)
    command("codesign", "--verify", "--deep", "--strict", app)
    original = command("otool", "-s", "__TEXT", "__text", SOURCE_APP / "Contents/MacOS/ThreeApp").splitlines()[2:]
    relabelled = command("otool", "-s", "__TEXT", "__text", app / f"Contents/MacOS/{EXE}").splitlines()[2:]
    assert original == relabelled, "Relabelling changed executable instructions"
    binary = RUN / "fixture"
    command("xcrun", "swiftc", ROOT / "scripts/verification/bpro-396-fixture.swift", "-o", binary)
    fixtures = {}
    for kind, name in [("blocked", "B396 Distraction"), ("work", "B396 Work")]:
        bundle = RUN / f"{name}.app"
        (bundle / "Contents/MacOS").mkdir(parents=True)
        shutil.copy2(binary, bundle / "Contents/MacOS/Fixture")
        fixture_info = {"CFBundleName": name, "CFBundleDisplayName": name, "CFBundleExecutable": "Fixture",
                        "CFBundleIdentifier": f"com.deyalla.b396.{kind}", "CFBundlePackageType": "APPL",
                        "QALog": str(RUN / f"{kind}.log")}
        if kind == "work":
            fixture_info["QAOtherApp"] = fixtures["blocked"]
            fixture_info["QAThreeApp"] = str(app)
            fixture_info["QAWorkApp"] = str(bundle)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(fixture_info))
        command("codesign", "--force", "--sign", "-", bundle)
        fixtures[kind] = str(bundle)
    chrome = RUN / "chrome"
    chrome.mkdir()
    env = os.environ | {"THREE_DB": str(RUN / "three.sqlite"), "THREE_CHROME_DATA": str(chrome)}
    cli = app / "Contents/Helpers/three"
    seeds = [("add", "QA ordinary focus", "--block", "45"),
             ("add", "QA strict focus", "--block", "25", "--strict"),
             ("block", "add", "example.com", "--app", "com.deyalla.b396.blocked")]
    for args in seeds:
        command(cli, *args, env=env)
    manifest = {"app": str(app), "executable": str(app / f"Contents/MacOS/{EXE}"),
                "cli": str(cli), "database": env["THREE_DB"], "chrome": str(chrome), "fixtures": fixtures,
                "source": command("git", "rev-parse", "HEAD", cwd=ROOT).strip(),
                "sourceApp": str(SOURCE_APP),
                "sourceExecutableSHA256": hashlib.sha256((SOURCE_APP / "Contents/MacOS/ThreeApp").read_bytes()).hexdigest(),
                "textSHA256": hashlib.sha256("\n".join(original).encode()).hexdigest()}
    (RUN / "run.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


def inspect():
    run = json.loads((RUN / "run.json").read_text())
    processes = command("ps", "-axo", "pid=,lstart=,command=")
    owned = [line.strip() for line in processes.splitlines()
             if any(path + "/Contents/MacOS/" in line for path in [run["app"], *run["fixtures"].values()])]
    print("\n".join(owned))
    for line in owned:
        pid = line.split()[0]
        files = command("lsof", "-p", pid)
        if run["executable"] in line:
            assert run["database"] in files, "Scratch DB is not open"
            assert "Application Support/Three/three.sqlite" not in files, "Production DB is open"
        (RUN / f"open-files-{pid}.txt").write_text(files)
    state = command("swift", "-e", '''import AppKit
for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier?.contains("b396") == true {
    print("pid=\\(app.processIdentifier) active=\\(app.isActive) hidden=\\(app.isHidden) bundle=\\(app.bundleIdentifier ?? "") path=\\(app.executableURL?.path ?? "")")
}
''')
    print(state, end="")


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("action", choices=["prepare", "capture", "inspect"])
parser.add_argument("label", nargs="?", default="before")
parser.add_argument("--run-name", default="native")
parser.add_argument("--source-app", type=Path, default=SOURCE_APP)
args = parser.parse_args()
SOURCE_APP = args.source_app.resolve(strict=True) if args.action == "prepare" else args.source_app
if Path(args.run_name).name != args.run_name or args.run_name in {".", ".."}:
    parser.error("run-name must be one directory name inside the audit directory")
RUN = AUDIT / args.run_name
if args.action == "prepare":
    prepare()
elif args.action == "capture":
    capture(args.label)
else:
    inspect()
