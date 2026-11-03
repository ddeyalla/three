#!/usr/bin/env python3
"""Exercise the packaged supervisor with owner death, pipe cancellation, and a real deadline."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shlex
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
import uuid


def record(database):
    with sqlite3.connect(database) as connection:
        connection.row_factory = sqlite3.Row
        return dict(connection.execute("SELECT * FROM planningRun").fetchone())


def await_state(predicate, deadline):
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.01)
    raise AssertionError("Fixture did not reach the required state before its bound")


def group_gone(group):
    try:
        os.killpg(group, 0)
        return False
    except ProcessLookupError:
        return True


def exercise(binary, scratch, case):
    folder = scratch / case
    folder.mkdir()
    database = folder / "three.sqlite"
    ready = folder / "ready"
    env = dict(os.environ, THREE_DB=str(database))
    subprocess.run([str(binary), "today"], env=env, check=True, capture_output=True, timeout=10)
    run_id = str(uuid.uuid4()).upper()
    now = time.time()
    lifetime = 2.0
    command = "/bin/sleep 60 & child=$!; printf '%s %s' $$ $child > " + shlex.quote(str(ready)) + "; wait"
    with sqlite3.connect(database) as connection:
        connection.execute("""INSERT INTO planningRun
            (id,day,trigger,status,startedAt,deadline,command)
            VALUES(?,?,'test','running',?,?,?)""",
                           (run_id, datetime.date.today().isoformat(), now, now + lifetime, command))
    owner = None
    helper = None
    try:
        if case == "owner-death":
            owner_code = """import json, os, subprocess, sys
from pathlib import Path
helper = subprocess.Popen([sys.argv[1], 'planning-run', sys.argv[2]], stdin=subprocess.PIPE,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=os.environ)
Path(sys.argv[3]).write_text(str(helper.pid))
helper.wait()
"""
            owner = subprocess.Popen([sys.executable, "-c", owner_code, str(binary), run_id, str(folder / "helper.pid")], env=env)
        else:
            helper = subprocess.Popen([str(binary), "planning-run", run_id], stdin=subprocess.PIPE,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
        await_state(lambda: ready.exists() and len(ready.read_text().split()) == 2, time.monotonic() + lifetime)
        group, child = map(int, ready.read_text().split())
        assert record(database)["processGroup"] == group
        if case == "owner-death":
            owner.kill()
            owner.wait(timeout=2)
        elif case == "cancel":
            helper.stdin.close()
        expected = "timedOut" if case == "deadline" else "cancelled"
        result = await_state(lambda: (row if (row := record(database))["status"] != "running" else None), time.monotonic() + lifetime + 1)
        assert result["status"] == expected, result
        await_state(lambda: group_gone(group), time.monotonic() + 1)
        if helper:
            helper.wait(timeout=2)
            assert helper.returncode == 0
        print(json.dumps({"case": case, "status": result["status"], "group": group, "child": child,
                          "group_gone": True, "lifetime_seconds": lifetime}))
    finally:
        if owner and owner.poll() is None:
            owner.kill()
            owner.wait(timeout=2)
        if helper:
            if helper.stdin and not helper.stdin.closed:
                helper.stdin.close()
            helper.wait(timeout=3)
        row = record(database)
        group = row.get("processGroup")
        if group and not group_gone(group):
            os.killpg(group, signal.SIGKILL)
        pid_file = folder / "helper.pid"
        if pid_file.exists():
            pid = int(pid_file.read_text())
            # The helper is this fixture's direct child of the killed owner, never a production process.
            if row["status"] == "running":
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="supervisor-proof-", dir=root / "build") as folder:
        for case in ["owner-death", "cancel", "deadline"]:
            exercise(binary, Path(folder), case)
    print("PASS: owner death, cancellation, and deadline stop the real helper's owned command group and persist the result.")


if __name__ == "__main__":
    main()
