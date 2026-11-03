#!/usr/bin/env python3
"""Exercise durable close and carry through the packaged CLI and MCP."""
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
    database = scratch / "day-close.sqlite"
    env = dict(os.environ, THREE_DB=str(database), TZ="Asia/Kolkata")

    def cli(*args):
        return json.loads(subprocess.run([str(binary), *args, "--json"], env=env,
                                        check=True, capture_output=True, text=True).stdout)

    rpc = mcp.RPC(binary, env)
    try:
        mcp.initialize(rpc)
        source_day, target_day, full_day = "2026-10-29", "2026-10-30", "2026-10-31"
        assert rpc.call("get_day_close", {"date": source_day}) is None
        tasks = [dict(mcp.task(title), notes="Keep these notes", tags=["launch"], strict=True)
                 for title in ["Accept this work", "Destination cap", "Dismiss this work"]]
        proposal = rpc.call("plan_day", {"date": source_day, "commit": True, "tasks": tasks})
        accepted, capped, dismissed = [row["task"]["id"] for row in proposal["day"]["tasks"]]
        subprocess.run([str(binary), "step", "add", accepted, "Preserved step"], env=env,
                       check=True, capture_output=True)
        with sqlite3.connect(database) as db:
            db.execute("UPDATE task SET status='partial' WHERE id=?", [accepted])
            db.execute("UPDATE step SET done=1 WHERE taskId=?", [accepted])
            db.execute("""INSERT INTO session
                (id,taskId,kind,plannedSeconds,startedAt,pausedSeconds,endedAt,endReason,updatedAt)
                VALUES('closed-source-session',?,'focus',1800,'2026-10-29 03:30:00.000',300,
                       '2026-10-29 04:00:00.000','stopped','2026-10-29 04:00:00.000')""", [accepted])
        closed = rpc.call("close_day", {"date": source_day})
        assert "closed" in closed, closed
        assert cli("close-day", "--date", source_day) == closed
        summary = rpc.call("get_day_close", {"date": source_day})
        assert summary["focusedSeconds"] == 1500, summary
        assert len(summary["commitment"]["tasks"]) == 3
        assert sum(task["plannedMinutes"] for task in summary["commitment"]["tasks"]) == 90
        assert summary["breakDecisions"] == []
        assert rpc.call("get_day", {"date": target_day})["tasks"] == []
        rpc.call("update_task", {"id": accepted, "title": "Forbidden"}, error="invalid_input")
        rpc.call("start_focus", {"task_id": accepted}, error="invalid_input")
        copy = rpc.call("carry_task", {"id": accepted, "date": target_day})
        assert cli("carry", accepted, "--date", target_day) == copy
        assert copy["carriedFromTaskId"] == accepted and copy["strict"]
        copied_row = rpc.call("get_day", {"date": target_day})["tasks"][0]
        assert copied_row["task"]["notes"] == "Keep these notes"
        assert copied_row["steps"][0]["done"] is True
        assert copied_row["tags"][0]["name"] == "launch"
        rpc.call("carry_task", {"id": accepted, "date": full_day}, error="invalid_input")
        dismissal = cli("dismiss-carry", dismissed)
        assert rpc.call("dismiss_carry", {"id": dismissed}) == dismissal
        rpc.call("carry_task", {"id": dismissed, "date": target_day}, error="invalid_input")
        rpc.call("dismiss_carry", {"id": accepted}, error="invalid_input")
        rpc.call("plan_day", {"date": full_day, "tasks": [mcp.task(f"Full {i}") for i in range(5)]})
        rpc.call("carry_task", {"id": capped, "date": full_day}, error="too_many_tasks")
        with sqlite3.connect(database) as db:
            assert db.execute("SELECT count(*) FROM task WHERE carriedFromTaskId=?", [capped]).fetchone()[0] == 0
            assert db.execute("SELECT taskId FROM session WHERE id='closed-source-session'").fetchone()[0] == accepted
            assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert not db.execute("PRAGMA foreign_key_check").fetchall()
            before = list(db.iterdump())
        assert cli("day-review", "--date", source_day) == summary
        assert rpc.call("get_day_close", {"date": source_day}) == summary
        with sqlite3.connect(database) as db:
            assert list(db.iterdump()) == before, "Summary reads mutated storage"
        rpc.call("get_day_close", {"date": "2026-02-30"}, error="invalid_input")
        rpc.call("close_day", {"date": source_day, "force": True}, error="invalid_input")
        rpc.close()
        rpc = mcp.RPC(binary, env)
        mcp.initialize(rpc)
        assert rpc.call("close_day", {"date": source_day}) == closed
        assert rpc.call("carry_task", {"id": accepted, "date": target_day}) == copy
        assert rpc.call("dismiss_carry", {"id": dismissed}) == dismissal
        assert rpc.call("get_status") is None
        print("PASS packaged day-close CLI/MCP parity, relaunch, frozen summary, carry lineage, dismissal, cap rollback and read-only summaries")
    finally:
        rpc.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, required=True)
    arguments = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="three-day-close-") as directory:
        run(arguments.binary.resolve(), Path(directory))
