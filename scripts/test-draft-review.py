#!/usr/bin/env python3
"""Prove a real MCP draft can be reviewed and committed through the app's Store API, without desktop automation."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("mcp_test", root / "scripts/test-mcp.py")
    mcp = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mcp)
    with tempfile.TemporaryDirectory(prefix="draft-review-", dir=root / "build") as folder:
        scratch = Path(folder)
        app = scratch / "Relocated Three.app"
        shutil.copytree(args.app.resolve(strict=True), app)
        binary = app / "Contents/Helpers/three"
        resources = app / "Contents/Resources/Three_ThreeCLI.bundle/Contents/Resources"
        for name in ["PlanDay.md", "CodexPrompt.md", "plan-day/SKILL.md"]:
            assert (resources / name).is_file(), f"Missing bundled guidance: {name}"
        db = scratch / "review.sqlite"
        env = dict(os.environ, THREE_DB=str(db), THREE_REVIEW_DB=str(db))
        rpc = mcp.RPC(binary, env)
        try:
            mcp.initialize(rpc)
            guide = rpc.request("resources/read", {"uri": "three://plan-day-guide"})["result"]["contents"][0]["text"]
            assert guide == (root / "Sources/ThreeCLI/Resources/PlanDay.md").read_text()
            assert guide == (resources / "PlanDay.md").read_text()
            tasks = [dict(mcp.task(f"Proposed {index}"), strict=True, tags=["review"],
                          linear="https://linear.app/brunoh-ai/issue/BPRO-398", notes="Issue context") for index in range(1, 4)]
            draft = rpc.call("plan_day", {"date": "today", "tasks": tasks, "commit": False})["day"]
            assert draft["plan"]["status"] == "draft" and draft["plan"]["source"] == "mcp"
            first = draft["tasks"][0]["task"]["id"]
            subprocess.run([str(binary), "step", "add", first, "Review the diff"], env=env, check=True, capture_output=True, timeout=15)
            result = subprocess.run([str(root / "scripts/swift.sh"), "test", "--filter", "DraftReviewTests/sharedDraftCanBeEditedThenCommitted"],
                                    cwd=root, env=env, text=True, capture_output=True, timeout=180)
            print(result.stdout, end="")
            print(result.stderr, end="")
            assert result.returncode == 0, "Shared Store review check failed"
            committed = rpc.call("get_today")
            assert committed["plan"]["status"] == "committed"
            assert committed["plan"]["source"] == "mcp"
            assert committed["tasks"][1]["task"]["title"] == "Reviewed task"
            assert committed["tasks"][1]["task"]["blockMinutes"] == 45
            assert committed["tasks"][2]["task"]["status"] == "dropped"
            assert committed["tasks"][1]["steps"][0]["title"] == "Review the diff"
            assert committed.get("running") is None
            rpc.call("plan_day", {"date": "today", "tasks": [], "commit": False}, error="invalid_input")
            assert rpc.call("get_today")["tasks"] == committed["tasks"]
        finally:
            rpc.close()
    print("PASS: relocated app helper reads the packaged canonical guide; MCP draft -> editable shared Store -> explicit commit; active-plan replacement refused.")
    print("HEADLESS ONLY: native review, keyboard controls, drag ordering, links, and copy actions still require desktop acceptance.")


if __name__ == "__main__":
    main()
