#!/usr/bin/env python3
"""Prove the packaged scheduled runner and restricted MCP channel using local fixtures only."""
import argparse
import datetime
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("three_mcp_fixture", ROOT / "scripts/test-mcp.py")
mcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp)


def draft_command():
    env = os.environ.copy()
    config = tomllib.loads(env["THREE_CODEX_MCP_CONFIG"])["mcp_servers"]["three"]
    assert config["command"] == env["THREE_HELPER"]
    assert config["args"] == ["mcp"]
    assert config["env"]["THREE_PLANNING_RUN"] == env["THREE_PLANNING_RUN"]
    rpc = mcp.RPC(Path(env["THREE_HELPER"]), env)
    date = env["THREE_PLANNING_DATE"]
    try:
        mcp.initialize(rpc)
        definitions = rpc.request("tools/list")["result"]["tools"]
        names = {tool["name"] for tool in definitions}
        assert names == {"get_today", "get_day", "plan_day", "list_categories", "get_status", "get_carryover", "get_history", "get_block_status"}, names
        schema = next(tool["inputSchema"] for tool in definitions if tool["name"] == "plan_day")
        assert schema["properties"]["commit"]["enum"] == [False]
        assert schema["properties"]["date"]["enum"] == [date]
        guide = rpc.request("resources/read", {"uri": "three://plan-day-guide"})["result"]["contents"][0]["text"]
        assert "Scheduled mode targets " + date in guide
        assert "buffer" in guide.lower()
        for name in ["commit_day", "start_focus", "pause", "resume", "stop", "extend", "start_break", "finish_focus", "add_task", "update_task", "remove_task", "move_task", "set_task_status", "carry_task", "schedule_task", "upsert_category", "add_block_rule", "set_task_strict", "close_day", "dismiss_carry", "get_day_close", "get_history_report", "get_stats"]:
            rpc.call(name, {}, error="scheduled_only")
        proposal = {"date": date, "tasks": [mcp.task("Scheduled fixture review"), mcp.task("Scheduled fixture proof"), mcp.task("Scheduled fixture handoff")], "commit": False}
        rpc.call("plan_day", dict(proposal, commit=True), error="scheduled_only")
        other = (datetime.date.fromisoformat(date) + datetime.timedelta(days=1)).isoformat()
        rpc.call("plan_day", dict(proposal, date=other), error="scheduled_only")
        rpc.call("plan_day", dict(proposal, tasks=[]), error="invalid_input")
        rpc.call("plan_day", dict(proposal, tasks=[mcp.task(str(i)) for i in range(6)]), error="invalid_input")
        created = rpc.call("plan_day", proposal)["day"]
        assert created["plan"]["status"] == "draft" and created["plan"]["source"] == "routine"
        assert all(row["task"]["createdBy"] == "routine" for row in created["tasks"])
        assert created.get("running") is None
        rpc.call("plan_day", proposal, error="invalid_input")
        after = rpc.call("get_day", {"date": date})
        assert after["tasks"] == created["tasks"]
        assert after["plan"] == created["plan"]
        print("scheduled MCP draft created; forbidden tools and duplicate draft refused")
    finally:
        rpc.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--draft-command", action="store_true")
    args = parser.parse_args()
    if args.draft_command:
        draft_command()
        return
    assert args.app, "Pass --app"
    with tempfile.TemporaryDirectory(prefix="scheduled-proof-", dir=ROOT / "build") as folder:
        scratch = Path(folder)
        app = scratch / "Scheduled Three.app"
        shutil.copytree(args.app.resolve(strict=True), app)
        binary = app / "Contents/Helpers/three"
        for name in ["PlanDay.md", "CodexPrompt.md", "plan-day/SKILL.md"]:
            assert (app / "Contents/Resources/Three_ThreeCLI.bundle/Contents/Resources" / name).is_file()
        db = scratch / "scheduled.sqlite"
        command = shlex.join([sys.executable, str(Path(__file__).resolve()), "--draft-command"])
        env = dict(os.environ, THREE_SCHEDULED_FIXTURE_DB=str(db), THREE_SCHEDULED_FIXTURE_COMMAND=command,
                   THREE_SCHEDULED_FIXTURE_HELPER=str(binary))
        result = subprocess.run([str(ROOT / "scripts/swift.sh"), "test", "--filter", "ScheduledPlanningTests/scheduledFixtureCommand"],
                                cwd=ROOT, env=env, text=True, capture_output=True, timeout=180)
        print(result.stdout, end="")
        print(result.stderr, end="")
        assert result.returncode == 0, "Real command/runner/MCP path failed"
        with sqlite3.connect(db) as connection:
            connection.row_factory = sqlite3.Row
            run = dict(connection.execute("SELECT * FROM planningRun").fetchone())
        assert run["status"] == "succeeded" and run["exitCode"] == 0, run
        assert "scheduled MCP draft created" in run["stdout"] and run["stderr"] == "", run
        env = dict(os.environ, THREE_DB=str(db))
        rpc = mcp.RPC(binary, env)
        try:
            mcp.initialize(rpc)
            draft = rpc.call("get_today")
            assert draft["plan"]["status"] == "draft"
            assert draft["plan"]["source"] == "routine"
            assert len(draft["tasks"]) == 3 and draft.get("running") is None
            rpc.call("commit_day", {"date": "today"})
            committed = rpc.call("get_today")
            assert committed["plan"]["status"] == "committed"
            assert committed["tasks"] == draft["tasks"] and committed.get("running") is None
        finally:
            rpc.close()
        expired_env = dict(env, THREE_PLANNING_RUN=run["id"], THREE_PLANNING_DATE=run["day"])
        expired = subprocess.run([str(binary), "mcp"], input="", env=expired_env, capture_output=True, text=True, timeout=15)
        assert expired.returncode != 0 and expired.stdout == "", expired
        malformed_env = dict(env, THREE_PLANNING_RUN="bad", THREE_PLANNING_DATE="today")
        malformed = subprocess.run([str(binary), "mcp"], input="", env=malformed_env, capture_output=True, text=True, timeout=15)
        assert malformed.returncode != 0 and malformed.stdout == "", malformed
        print(json.dumps({"status": "PASS", "run": run["id"], "source": "routine", "forbidden_mutations": 20, "additional_read_tools_refused": 3,
                          "packaged_helper": str(binary), "authenticated_model_run": False}, indent=2))
    print("PASS: native command runner -> relocated packaged MCP helper -> routine draft -> explicit normal-channel commit. No model or paid calls.")


if __name__ == "__main__":
    main()
