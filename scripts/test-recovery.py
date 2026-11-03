#!/usr/bin/env python3
"""Prove packaged CLI/MCP recovery parity with disposable databases. Launch no app."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("three_recovery_protocol", ROOT / "scripts/test-mcp.py")
mcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp)


def cli(binary, env, *args, error=False, json_output=True):
    command = [str(binary), *args]
    if json_output:
        command.append("--json")
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=20)
    if error:
        assert result.returncode != 0 and result.stdout == "" and result.stderr, result
        return result.stderr
    assert result.returncode == 0 and result.stderr == "", result
    return json.loads(result.stdout) if json_output else result.stdout


def logical(database):
    with sqlite3.connect(database) as db:
        return sorted(db.iterdump())


def session_rows(database):
    with sqlite3.connect(database) as db:
        db.row_factory = sqlite3.Row
        return {row["id"]: dict(row) for row in db.execute("SELECT * FROM session")}


def fixture(binary, scenario):
    env = {key: value for key, value in os.environ.items()
           if key not in ("THREE_DB", "THREE_CHROME_DATA", "THREE_PLANNING_RUN", "THREE_PLANNING_DATE")}
    result = subprocess.run([sys.executable, str(ROOT / "scripts/verification/recovery-fixture.py"),
                             "--binary", str(binary), "--create", "--scenario", scenario],
                            env=env, capture_output=True, text=True, check=True, timeout=30)
    manifest = json.loads(result.stdout)
    return manifest, dict(env, **manifest["environment"])


def open_rpc(binary, env):
    rpc = mcp.RPC(binary, env)
    try:
        mcp.initialize(rpc)
    except BaseException:
        rpc.close()
        raise
    return rpc


def report_pair(binary, env, rpc, day, expected):
    first = (date.fromisoformat(day) - timedelta(days=6)).isoformat()
    args = {"from": first, "to": day}
    history = rpc.call("get_history_report", args)
    cli_history = cli(binary, env, "history", "--from", first, "--to", day)
    stats = rpc.call("get_stats", args)
    cli_stats = cli(binary, env, "stats", "--from", first, "--to", day)
    for left, right in [(history, cli_history), (stats, cli_stats)]:
        left = {k: v for k, v in left.items() if k != "takenAt"}
        right = {k: v for k, v in right.items() if k != "takenAt"}
        assert left == right, (left, right)
    assert history["totals"]["focusSeconds"] == expected, history
    assert history["totals"]["focusSessionCount"] == 1, history
    assert history["totals"]["plannedSeconds"] == 2700, history
    assert history["months"][-1]["totals"]["focusSeconds"] == expected, history
    assert history["days"][-1]["tasks"][0]["focusSeconds"] == expected, history
    metrics = stats["metrics"]
    assert metrics["focusSeconds"] == metrics["accuracyFocusSeconds"] == expected, metrics
    assert metrics["actualToPlanned"]["numerator"] == expected, metrics
    assert metrics["actualToPlanned"]["denominator"] == 2700, metrics
    assert math.isclose(metrics["actualToPlanned"]["value"], expected / 2700), metrics
    assert metrics["committedPlannedTaskCount"] == metrics["committedPlanCount"] == 1, metrics
    assert metrics["completion"]["numerator"] == 0 and metrics["completion"]["denominator"] == 1, metrics
    assert metrics["committedPlannedSeconds"] == metrics["derivedPlannedSeconds"] == 2700, metrics
    assert metrics["quality"]["okaySessionCount"] == metrics["quality"]["ratedSessionCount"] == 1, metrics
    assert metrics["quality"]["focusedShare"]["numerator"] == 0, metrics
    assert metrics["quality"]["focusedShare"]["denominator"] == 1, metrics
    assert metrics["blocks"]["associatedHits"] == 2 and metrics["blocks"]["associatedUnblocks"] == 1, metrics
    assert metrics["blocks"]["hitsPerFocusHour"]["numerator"] == 2, metrics
    assert metrics["blocks"]["hitsPerFocusHour"]["denominator"] == expected / 3600, metrics
    assert math.isclose(metrics["blocks"]["hitsPerFocusHour"]["value"], 2 / (expected / 3600)), metrics
    assert math.isclose(stats["days"][-1]["sevenDayAverageMinutes"], expected / 60 / 7), stats
    assert {tag["tag"]["name"] for tag in stats["tags"]} == {"Client", "Three"}, stats
    for tag in stats["tags"]:
        assert tag["metrics"]["focusSeconds"] == expected, tag
        assert tag["metrics"]["actualToPlanned"]["denominator"] == 2700, tag
        assert tag["metrics"]["blocks"]["associatedHits"] == 2, tag
    return history, stats


def prepare_report_fixture(binary, env, manifest):
    cli(binary, env, "tags", "add", "1", "Three", "Client", json_output=False)
    rpc = open_rpc(binary, env)
    try:
        rpc.call("add_block_rule", {"kind": "domain", "value": "example.com"})
    finally:
        rpc.close()
    with sqlite3.connect(manifest["database"]) as db:
        manifest["day"] = (date.fromisoformat(manifest["day"]) - timedelta(days=1)).isoformat()
        start = datetime.fromisoformat(manifest["day"] + "T09:00:00").astimezone(timezone.utc)
        stamp = lambda seconds: (start + timedelta(seconds=seconds)).strftime("%Y-%m-%d %H:%M:%S.000")
        db.execute("UPDATE dayPlan SET day=?", [manifest["day"]])
        db.execute("UPDATE session SET startedAt=?, endedAt=?, updatedAt=? WHERE id=?",
                   [stamp(0), stamp(1800), stamp(1800), manifest["session_id"]])
        db.execute("UPDATE recoveryGap SET startedAt=?, endedAt=?, lastObservedAt=? WHERE id=?",
                   [stamp(900), stamp(1800), stamp(1800), manifest["gap_id"]])
        rule = db.execute("SELECT id FROM blockRule WHERE value = 'example.com'").fetchone()[0]
        at = db.execute("SELECT startedAt FROM session WHERE id=?", [manifest["session_id"]]).fetchone()[0]
        for action in ("blocked", "blocked", "unblocked"):
            db.execute("INSERT INTO blockEvent(id, at, ruleId, sessionId, action) VALUES(?,?,?,?,?)",
                       [str(uuid.uuid4()), at, rule, manifest["session_id"], action])


def historical(binary, decision, concurrent=False):
    manifest, env = fixture(binary, "historical")
    rpc = peer = None
    try:
        prepare_report_fixture(binary, env, manifest)
        rpc = open_rpc(binary, env)
        database, gap = manifest["database"], manifest["gap_id"]
        original = logical(database)
        status = rpc.call("get_recovery")
        assert status == cli(binary, env, "recovery"), status
        assert status["unresolvedSessionIDs"] == [manifest["session_id"]], status
        review = status["reviews"][0]
        assert review["gap"]["id"] == gap and review["gap"]["clockReliable"], status
        assert review["gap"]["awaySeconds"] == 900 and review["gap"]["state"] == "review", status
        assert review["sessions"][0]["eligibleSeconds"] == 900, status
        assert review["sessions"][0]["session"]["id"] == manifest["session_id"], status
        rpc.call("get_recovery")
        assert original == logical(database), "Status read changed logical database"
        before_history, before_stats = report_pair(binary, env, rpc, manifest["day"], 1500)
        assert original == logical(database), "Report read changed logical database"
        for arguments in [{}, {"id": gap}, {"decision": "keep"}, {"id": 1, "decision": "trim"},
                          {"id": "", "decision": "trim"}, {"id": gap[:8], "decision": "trim"},
                          {"id": " " + gap, "decision": "keep"}, {"id": gap, "decision": None},
                          {"id": gap, "decision": "TRIM"}, {"id": gap, "decision": True},
                          {"id": gap, "decision": "discard"}, {"id": gap, "decision": "trim", "extra": True}]:
            rpc.call("decide_recovery", arguments, error="invalid_input")
        rpc.call("get_recovery", {"extra": True}, error="invalid_input")
        rpc.call("decide_recovery", {"id": str(uuid.uuid4()), "decision": "trim"}, error="invalid_input")
        for arguments in [(gap,), (gap, "--decision", "wrong"), ("1", "--decision", "keep"),
                          (gap[:8], "--decision", "trim"), (" " + gap, "--decision", "keep")]:
            cli(binary, env, "recovery-decide", *arguments, error=True)
        assert original == logical(database), "Rejected input changed logical database"
        guard = {"deferred": {"_0": "recovery"}}
        assert rpc.call("close_day", {"date": manifest["day"]}) == guard
        assert cli(binary, env, "close-day", "--date", manifest["day"]) == guard
        rpc.close()
        rpc = None
        rpc = open_rpc(binary, env)
        assert rpc.call("get_recovery") == status, "Pending review lost after restart"
        newer = rpc.call("start_break", {"minutes": 5})
        rpc.call("pause")
        old_sessions = session_rows(database)
        with sqlite3.connect(database) as db:
            commitment = db.execute("SELECT * FROM planCommitment").fetchall()
            events = db.execute("SELECT * FROM blockEvent ORDER BY id").fetchall()
        if concurrent:
            peer = open_rpc(binary, env)
            with ThreadPoolExecutor(max_workers=3) as executor:
                calls = [executor.submit(rpc.call, "decide_recovery", {"id": gap, "decision": decision}),
                         executor.submit(peer.call, "decide_recovery", {"id": gap, "decision": "keep"}),
                         executor.submit(cli, binary, env, "recovery-decide", gap, "--decision", "trim")]
                results = [call.result() for call in calls]
            assert results[0] == results[1] == results[2], results
            decided = results[0]
        elif decision == "keep":
            decided = cli(binary, env, "recovery-decide", gap, "--decision", decision)
        else:
            decided = rpc.call("decide_recovery", {"id": gap, "decision": decision})
        expected = 600 if decided["state"] == "trimmed" else 1500
        if not concurrent:
            assert decided["state"] == ("trimmed" if decision == "trim" else "kept"), decided
        for retry in ("keep", "trim", "trim"):
            assert rpc.call("decide_recovery", {"id": gap, "decision": retry}) == decided
            assert cli(binary, env, "recovery-decide", gap, "--decision", retry) == decided
        after_history, after_stats = report_pair(binary, env, rpc, manifest["day"], expected)
        old_focus = before_history["days"][-1]["sessions"][0]["session"]
        new_focus = next(row["session"] for row in after_history["days"][-1]["sessions"]
                         if row["session"]["id"] == manifest["session_id"])
        for key in ("id", "taskId", "kind", "plannedSeconds", "startedAt", "endedAt", "pausedSeconds", "outcome", "focusRating", "note"):
            assert old_focus.get(key) == new_focus.get(key), (key, old_focus, new_focus)
        assert before_stats["metrics"]["quality"] == after_stats["metrics"]["quality"]
        assert before_stats["metrics"]["completion"] == after_stats["metrics"]["completion"]
        saved = session_rows(database)
        assert saved[newer["id"]] == old_sessions[newer["id"]], "Historical decision changed newer timer"
        assert saved[manifest["session_id"]]["recoveryTrimSeconds"] == (900 if expected == 600 else 0)
        with sqlite3.connect(database) as db:
            assert db.execute("SELECT * FROM planCommitment").fetchall() == commitment
            assert db.execute("SELECT * FROM blockEvent ORDER BY id").fetchall() == events
            assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert db.execute("PRAGMA foreign_key_check").fetchall() == []
        rpc.close()
        rpc = None
        rpc = open_rpc(binary, env)
        assert rpc.call("get_recovery") == {"reviews": [], "unresolvedSessionIDs": []}
        assert cli(binary, env, "recovery-decide", gap, "--decision", "keep") == decided
        assert rpc.call("decide_recovery", {"id": gap, "decision": "trim"}) == decided
        assert cli(binary, env, "recovery", json_output=False).strip() == "No recovery reviews pending."
        assert cli(binary, env, "recovery-decide", gap, "--decision", "keep", json_output=False).strip() == f"{gap} · {decided['state']}"
        print(f"PASS historical {decision}, concurrent={concurrent}, durable={decided['state']}, focus={expected}")
    finally:
        try:
            if peer:
                peer.close()
        finally:
            try:
                if rpc:
                    rpc.close()
            finally:
                shutil.rmtree(manifest["scratch"])


def unresolved(binary, scenario):
    manifest, env = fixture(binary, scenario)
    rpc = None
    try:
        rpc = open_rpc(binary, env)
        status = rpc.call("get_recovery")
        assert cli(binary, env, "recovery") == status
        text = cli(binary, env, "recovery", json_output=False)
        assert manifest["gap_id"] in text, text
        if scenario == "untrusted":
            assert "Keep only, clock changed" in text, text
        original = logical(manifest["database"])
        if scenario == "observing":
            assert status["observing"]["id"] == manifest["gap_id"] and not status["reviews"], status
            for decision in ("keep", "trim"):
                rpc.call("decide_recovery", {"id": manifest["gap_id"], "decision": decision}, error="invalid_input")
                cli(binary, env, "recovery-decide", manifest["gap_id"], "--decision", decision, error=True)
        else:
            review = status["reviews"][0]
            assert review["gap"]["id"] == manifest["gap_id"], status
            if scenario == "untrusted":
                assert not review["gap"]["clockReliable"] and review["sessions"][0]["eligibleSeconds"] == 0, status
                rpc.call("decide_recovery", {"id": manifest["gap_id"], "decision": "trim"}, error="invalid_input")
                cli(binary, env, "recovery-decide", manifest["gap_id"], "--decision", "trim", error=True)
        assert original == logical(manifest["database"]), "Rejected decision or status read wrote data"
        rpc.close()
        rpc = None
        rpc = open_rpc(binary, env)
        assert rpc.call("get_recovery") == status
        if scenario != "observing":
            before = session_rows(manifest["database"])
            assert cli(binary, env, "recovery-decide", manifest["gap_id"], "--decision", "keep")["state"] == "kept"
            assert session_rows(manifest["database"]) == before, "Keep changed session records"
        print(f"PASS {scenario}, status/rejection read-only, restart persistence")
    finally:
        try:
            if rpc:
                rpc.close()
        finally:
            shutil.rmtree(manifest["scratch"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    for decision in ("keep", "trim"):
        historical(binary, decision)
    historical(binary, "trim", concurrent=True)
    for scenario in ("pending", "untrusted", "observing"):
        unresolved(binary, scenario)
    print("PASS packaged CLI/MCP recovery. No app launch, physical sleep, or model calls.")


if __name__ == "__main__":
    main()
