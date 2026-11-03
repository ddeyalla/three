#!/usr/bin/env python3
"""Compare packaged CLI and MCP history against fixed SQLite session records."""
import argparse
import importlib.util
import json
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


def run(binary, scratch):
    database = scratch / "history.sqlite"
    env = dict(os.environ, THREE_DB=str(database), TZ="Asia/Kolkata")
    rpc = mcp.RPC(binary, env)
    try:
        mcp.initialize(rpc)
        tools = rpc.request("tools/list")["result"]["tools"]
        definition = next(tool for tool in tools if tool["name"] == "get_history_report")
        assert definition["annotations"]["readOnlyHint"] is True
        assert definition["inputSchema"]["additionalProperties"] is False
        rpc.call("plan_day", {"date": "2026-10-31", "commit": True, "tasks": [
            dict(mcp.task("Carry history"), tags=["launch", "quality"], strict=True),
            dict(mcp.task("Finished history"), block_minutes=45),
        ]})
        rows = rpc.call("get_day", {"date": "2026-10-31"})["tasks"]
        source, finished = [row["task"]["id"] for row in rows]
        copy = rpc.call("carry_task", {"id": source})["id"]
        with sqlite3.connect(database) as db:
            db.execute("UPDATE task SET status='done', doneAt='2026-11-01 09:10:00.000' WHERE id=?", [finished])
            db.execute("UPDATE category SET archived=1, deletedAt='2026-11-02 00:00:00.000' WHERE id=?", [rows[0]["task"]["categoryId"]])
            sessions = [
                ("cross-midnight", source, "focus", 1800, "2026-10-31 18:15:00.000", 600, "2026-10-31 18:45:00.000", "progress", 3, "Keep source history"),
                ("finished", finished, "focus", 900, "2026-11-01 03:30:00.000", 0, "2026-11-01 03:40:00.000", "done", 2, "Finished on another date"),
                ("break", None, "break", 300, "2026-11-01 03:40:00.000", 0, "2026-11-01 03:45:00.000", None, None, None),
            ]
            for row in sessions:
                db.execute("""INSERT INTO session
                    (id,taskId,kind,plannedSeconds,startedAt,pausedSeconds,endedAt,outcome,focusRating,note,endReason,updatedAt)
                    VALUES(?,?,?,?,?,?,?,?,?,?,'completed','2026-11-02 00:00:00.000')""", row)
            assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert not db.execute("PRAGMA foreign_key_check").fetchall()
        arguments = {"from": "2026-10-31", "to": "2026-11-02"}
        with sqlite3.connect(database) as db:
            before = list(db.iterdump())
        report = rpc.call("get_history_report", arguments)
        cli = json.loads(subprocess.run(
            [str(binary), "history", "--from", arguments["from"], "--to", arguments["to"], "--json"],
            env=env, check=True, capture_output=True, text=True,
        ).stdout)
        assert report.pop("takenAt") and cli.pop("takenAt")
        assert report == cli, "CLI and MCP detailed reports differ"
        assert report["plannedMetrics"] == "derivedFromCurrentTaskRows"
        assert report["dateAttribution"] == "sessionStartDayInReportTimeZone"
        assert report["totals"] == {
            "plannedSeconds": 4500, "focusSeconds": 1800, "breakSeconds": 300,
            "plannedTaskCount": 2, "doneTaskCount": 1,
            "focusSessionCount": 2, "breakSessionCount": 1,
        }, report["totals"]
        assert [month["month"] for month in report["months"]] == ["2026-10", "2026-11"]
        first, second, empty = report["days"]
        assert first["totals"]["focusSeconds"] == 1200
        assert second["totals"]["focusSeconds"] == 600
        assert empty["tasks"] == [] and empty["sessions"] == []
        carried = next(row for row in first["tasks"] if row["task"]["id"] == source)
        assert carried["task"]["status"] == "carried" and carried["derivedPlannedSeconds"] == 0
        assert carried["focusSeconds"] == 1200
        assert carried["category"]["archived"] and carried["category"]["deletedAt"]
        assert {tag["name"] for tag in carried["tags"]} == {"launch", "quality"}
        copied = next(row for row in second["tasks"] if row["task"]["id"] == copy)
        assert copied["focusSeconds"] == 0 and copied["task"]["strict"]
        recorded = [row for day in report["days"] for row in day["sessions"]]
        assert {row["session"]["id"] for row in recorded} == {"cross-midnight", "finished", "break"}
        legacy = rpc.call("get_history", arguments)
        assert legacy == [row["session"] for row in recorded]
        rpc.call("get_history_report", {"from": "2026-11-02", "to": "2026-10-31"}, error="invalid_input")
        rpc.call("get_history_report", {"from": "2020-01-01", "to": "2026-11-02"}, error="invalid_input")
        rpc.call("get_history_report", dict(arguments, extra=True), error="invalid_input")
        rpc.call("get_history_report", dict(arguments, **{"from": "2026-02-30"}), error="invalid_input")
        invalid = subprocess.run([str(binary), "history", "--from", "2026-11-02", "--to", "2026-10-31", "--json"], env=env, capture_output=True, text=True)
        assert invalid.returncode != 0 and not invalid.stdout.strip()
        with sqlite3.connect(database) as db:
            assert list(db.iterdump()) == before, "History reads changed stored data"
        print("PASS: fixed session accounting, carry history, archived/deleted category, empty dates, CLI/MCP parity, legacy compatibility, read-only validation")
    finally:
        rpc.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="three-history-") as scratch:
        run(args.binary.resolve(), Path(scratch))
