#!/usr/bin/env python3
"""Create a new scratch recovery database for the exclusive native QA owner."""
import argparse
from datetime import datetime, timedelta, timezone
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import uuid

sys.dont_write_bytecode = True


def create(binary, scenario):
    scratch = Path(tempfile.mkdtemp(prefix="three-recovery-native-"))
    database = scratch / "recovery.sqlite"
    env = dict(os.environ, THREE_DB=str(database), THREE_CHROME_DATA=str(scratch / "chrome"))
    subprocess.run([str(binary), "plan", "Recovery fixture:Coding:45", "--commit"],
                   env=env, check=True, capture_output=True, text=True)
    now = datetime.now(timezone.utc).replace(microsecond=0)
    start, begin, end = now - timedelta(seconds=1800), now - timedelta(seconds=900), now
    session_id, gap_id = str(uuid.uuid4()), str(uuid.uuid4())
    reliable = scenario not in ("untrusted", "observing")
    observing = scenario == "observing"
    historical = scenario == "historical"

    def stamp(value):
        return value.strftime("%Y-%m-%d %H:%M:%S.000")

    with sqlite3.connect(database) as db:
        db.execute("PRAGMA foreign_keys=ON")
        task_id, day = db.execute("SELECT t.id, p.day FROM task t JOIN dayPlan p ON p.id=t.dayPlanId").fetchone()
        db.execute("UPDATE task SET status=? WHERE id=?", ["partial" if historical else "active", task_id])
        db.execute("""INSERT INTO session
            (id,taskId,kind,plannedSeconds,startedAt,pausedSeconds,endedAt,endReason,outcome,focusRating,note,updatedAt)
            VALUES(?,?,'focus',2700,?,300,?,?,?,?,?,?)""",
                   [session_id, task_id, stamp(start), stamp(end) if historical else None,
                    "completed" if historical else None, "progress" if historical else None,
                    2 if historical else None, "Preserve this reflection" if historical else None, stamp(now)])
        db.execute("""INSERT INTO recoveryGap
            (id,startedAt,endedAt,lastObservedAt,clockReliable,sleeping,locked,awaySeconds,state)
            VALUES(?,?,?,?,?,?,0,?,?)""",
                   [gap_id, stamp(begin), None if observing else stamp(end), stamp(begin if observing else end),
                    int(reliable), int(observing), 0 if observing else 900, "observing" if observing else "review"])
        db.execute("INSERT INTO recoveryImpact(gapId,sessionId,baselineWork,eligibleSeconds) VALUES(?,?,600,?)",
                   [gap_id, session_id, 900 if reliable else 0])
        assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert not db.execute("PRAGMA foreign_key_check").fetchall()
        assert db.execute("SELECT recoveryTrimSeconds FROM session WHERE id=?", [session_id]).fetchone()[0] == 0
    if historical:
        result = json.loads(subprocess.run([str(binary), "close-day", "--date", day, "--json"],
                                          env=env, check=True, capture_output=True, text=True).stdout)
        assert result == {"deferred": {"_0": "recovery"}}, result
        helper = Path(__file__).resolve().parents[1] / "test-mcp.py"
        spec = importlib.util.spec_from_file_location("three_recovery_mcp_fixture", helper)
        mcp = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mcp)
        rpc = mcp.RPC(binary, env)
        try:
            mcp.initialize(rpc)
            assert rpc.call("close_day", {"date": day}) == result
            report = rpc.call("get_history_report", {"from": day, "to": day})
            assert report["totals"]["focusSeconds"] == 1500, report
        finally:
            rpc.close()
    manifest = dict(scenario=scenario, scratch=str(scratch), database=str(database), session_id=session_id,
                    gap_id=gap_id, day=day, before_focus_seconds=1500, eligible_seconds=900 if reliable else 0,
                    after_trim_seconds=600 if reliable else None,
                    environment={"THREE_DB": str(database), "THREE_CHROME_DATA": str(scratch / "chrome")},
                    physical_sleep_verified=False, app_launched=False, protocol_recovery_guard_verified=historical)
    path = scratch / "fixture.json"
    path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(dict(result="PASS scratch fixture and integrity checks", manifest=str(path), **manifest), indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--create", action="store_true", required=True,
                        help="Opt in to creating a new disposable directory. No app is launched.")
    parser.add_argument("--scenario", choices=["pending", "historical", "untrusted", "observing"], default="pending")
    args = parser.parse_args()
    create(args.binary.resolve(strict=True), args.scenario)
