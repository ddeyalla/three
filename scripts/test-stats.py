#!/usr/bin/env python3
"""Prove packaged statistics parity with fixed numerical expectations."""
import argparse
import datetime
import importlib.util
import json
import math
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("three_mcp_fixture", ROOT / "scripts/test-mcp.py")
mcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp)


def verify(binary, database):
    assert not database.exists(), "A new disposable fixture path is required"
    database.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, THREE_DB=str(database), TZ="UTC")
    rpc = mcp.RPC(binary, env)
    try:
        mcp.initialize(rpc)
        definition = next(tool for tool in rpc.request("tools/list")["result"]["tools"] if tool["name"] == "get_stats")
        assert definition["annotations"]["readOnlyHint"] is True
        assert definition["inputSchema"]["additionalProperties"] is False
        assert definition["inputSchema"]["required"] == []
        empty = rpc.call("get_stats")
        assert len(empty["days"]) == 28
        assert empty["metrics"]["completion"]["value"] is None
        assert empty["metrics"]["blocks"]["hitsPerFocusHour"]["value"] is None
        plan = rpc.call("plan_day", {"date": "2026-11-02", "commit": True, "tasks": [
            dict(mcp.task("403 Build with focus"), tags=["Three", "Client"]),
            dict(mcp.task("403 Write and reflect"), category="Writing", block_minutes=60, tags=["Client"]),
        ]})
        first, second = [row["task"]["id"] for row in plan["day"]["tasks"]]
        draft = rpc.call("plan_day", {"date": "2026-11-03", "tasks": [mcp.task("403 Draft stays outside commitment")]})
        draft_id = draft["day"]["tasks"][0]["task"]["id"]
        rule = rpc.call("add_block_rule", {"kind": "domain", "value": "example.com"})["rules"][0]["id"]
        with sqlite3.connect(database) as db:
            for task, done_at in [(first, "2026-11-02 11:00:00.000"), (draft_id, "2026-11-03 11:00:00.000")]:
                db.execute("UPDATE task SET status='done', doneAt=? WHERE id=?", [done_at, task])
            for row in [
                ("focused", first, "focus", "2026-11-02 09:00:00.000", 7200, "2026-11-02 11:30:00.000", 3),
                ("scattered", second, "focus", "2026-11-02 12:00:00.000", 0, "2026-11-02 12:15:00.000", 1),
                ("unrated", second, "focus", "2026-11-02 13:00:00.000", 0, "2026-11-02 13:15:00.000", None),
                ("break", None, "break", "2026-11-02 14:00:00.000", 0, "2026-11-02 14:10:00.000", None),
            ]:
                db.execute("""INSERT INTO session(id,taskId,kind,startedAt,pausedSeconds,endedAt,focusRating,
                    plannedSeconds,endReason,updatedAt) VALUES(?,?,?,?,?,?,?,1800,'stopped','2026-11-03 12:00:00.000')""", row)
            for ident, session, action, at in [
                ("hit1", "focused", "blocked", "2026-11-02 09:00:01.000"),
                ("hit2", "focused", "blocked", "2026-11-02 09:00:02.000"),
                ("hit3", "focused", "blocked", "2026-11-02 09:00:03.000"),
                ("unblock", "focused", "unblocked", "2026-11-02 09:01:00.000"),
                ("ambient", None, "blocked", "2026-11-03 09:01:00.000"),
            ]:
                db.execute("INSERT INTO blockEvent(id,sessionId,action,at,ruleId) VALUES(?,?,?,?,?)", [ident, session, action, at, rule])
            db.execute("INSERT INTO breakDecision VALUES('focused','skipped','2026-11-02 11:30:00.000')")
            db.execute("INSERT INTO breakDecision VALUES('scattered','taken','2026-11-02 12:15:00.000')")
            assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert not db.execute("PRAGMA foreign_key_check").fetchall()
            before = list(db.iterdump())
        bounds = {"from": "2026-10-28", "to": "2026-11-03"}
        report = rpc.call("get_stats", bounds)
        cli = json.loads(subprocess.run([str(binary), "stats", "--from", bounds["from"], "--to", bounds["to"], "--json"],
                                        env=env, check=True, capture_output=True, text=True).stdout)
        assert report.pop("takenAt") and cli.pop("takenAt")
        assert report == cli, "CLI and MCP statistics differ"
        metrics = report["metrics"]
        assert metrics["focusSeconds"] == 3600 and metrics["derivedPlannedSeconds"] == 7200
        assert metrics["committedPlannedSeconds"] == 5400
        assert metrics["completion"]["numerator"] == 1 and metrics["completion"]["denominator"] == 2
        assert metrics["completion"]["value"] == 0.5
        assert math.isclose(metrics["actualToPlanned"]["value"], 2 / 3)
        assert metrics["quality"]["focusedShare"]["value"] == 0.5 and metrics["quality"]["missingRatingCount"] == 1
        assert metrics["blocks"]["hitsPerFocusHour"]["value"] == 3
        assert metrics["blocks"]["unblocksPerFocusHour"]["value"] == 1
        assert metrics["blocks"]["unassociatedHits"] == 1
        assert metrics["blocks"]["topTargets"][0]["associatedHits"] == 3
        assert metrics["breaks"]["skippedShare"]["value"] == 0.5
        assert metrics["breaks"]["missingDecisionCount"] == 1
        tags = {row["tag"]["name"]: row for row in report["tags"]}
        assert tags["Three"]["metrics"]["focusSeconds"] == 1800
        assert tags["Client"]["metrics"]["focusSeconds"] == 3600
        assert tags["Three"]["metrics"]["blocks"]["hitsPerFocusHour"]["value"] == 6
        assert math.isclose(report["days"][-1]["sevenDayAverageMinutes"], 60 / 7)
        assert [week["includedDayCount"] for week in report["weeks"]] == [5, 2]
        assert all(week["isPartial"] for week in report["weeks"])
        assert report["weeks"][0]["metrics"]["quality"]["focusedShare"]["value"] is None
        assert report["weeks"][1]["metrics"]["quality"]["focusedShare"]["value"] == 0.5
        assert report["weeks"][1]["metrics"]["blocks"]["hitsPerFocusHour"]["value"] == 3
        ends_today = report["through"] == datetime.datetime.now(datetime.timezone.utc).date().isoformat()
        assert report["streak"]["days"] == (1 if ends_today else 0)
        assert report["streak"]["currentIncompleteDayPreservesPrevious"] == ends_today
        history = rpc.call("get_history_report", bounds)
        assert history["totals"]["focusSeconds"] == metrics["focusSeconds"]
        assert history["totals"]["breakSeconds"] == 600
        for args in [{"from": "2026-02-30"}, {"from": "2026-11-03", "to": "2026-11-02"},
                     {"from": "2020-01-01", "to": "2026-11-03"}, {"to": "2999-01-01"}, {"from": None}, {"extra": True}]:
            rpc.call("get_stats", args, error="invalid_input")
        with sqlite3.connect(database) as db:
            assert list(db.iterdump()) == before, "Statistics or invalid reads mutated storage"
        print("PASS five fixed statistics, commitment denominators, overlapping tags, break choices, CLI/MCP/History parity, null ratios, range validation and read-only storage")
    finally:
        rpc.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--fixture-db", type=Path, help="Retain a NEW disposable fixture for native QA; refuses existing paths.")
    args = parser.parse_args()
    if args.fixture_db:
        verify(args.binary.resolve(), args.fixture_db.resolve())
        print(json.dumps({"database": str(args.fixture_db.resolve()), "range": ["2026-10-28", "2026-11-03"], "focusSeconds": 3600}))
    else:
        with tempfile.TemporaryDirectory(prefix="three-stats-") as folder:
            verify(args.binary.resolve(), Path(folder) / "stats.sqlite")
