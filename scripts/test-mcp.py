#!/usr/bin/env python3
"""Exercise the built three binary over real stdio with a disposable database."""
import argparse
import ctypes
import datetime
import json
import os
from pathlib import Path
import queue
import shutil
import sqlite3
import subprocess
import tempfile
import threading


class RPC:
    def __init__(self, binary, env):
        self.process = subprocess.Popen(
            [str(binary), "mcp"], env=env, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1,
        )
        self.lines = queue.Queue()
        self.errors = []
        self.counter = 0
        self.reader = threading.Thread(target=self.read_stdout, daemon=True)
        self.error_reader = threading.Thread(target=self.read_stderr, daemon=True)
        self.reader.start()
        self.error_reader.start()

    def read_stdout(self):
        for line in self.process.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def read_stderr(self):
        for line in self.process.stderr:
            self.errors.append(line)

    def send(self, method, params=None):
        self.counter += 1
        message = {"jsonrpc": "2.0", "id": self.counter, "method": method}
        if params is not None:
            message["params"] = params
        self.raw(json.dumps(message))
        return self.counter

    def raw(self, line):
        self.process.stdin.write(line + "\n")
        self.process.stdin.flush()

    def receive(self, expected=None):
        line = self.lines.get(timeout=15)
        assert line is not None, f"MCP exited early: {self.errors}"
        reply = json.loads(line)
        assert reply["jsonrpc"] == "2.0", reply
        if expected is not None:
            assert reply["id"] == expected, reply
        return reply

    def request(self, method, params=None):
        return self.receive(self.send(method, params))

    def call(self, name, arguments=None, error=None):
        reply = self.request("tools/call", {"name": name, "arguments": arguments or {}})
        assert "result" in reply, reply
        result = reply["result"]
        value = json.loads(result["content"][0]["text"])
        if error:
            assert result["isError"] is True and value["code"] == error, reply
        else:
            assert result.get("isError") is not True, reply
        return value

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=10)
            self.reader.join(timeout=2)
            self.error_reader.join(timeout=2)
            assert self.process.returncode == 0, self.errors
            assert not self.errors, self.errors
            assert self.lines.get(timeout=1) is None, "Unrequested stdout output"
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait()


def task(title):
    return {"title": title, "category": "Coding", "block_minutes": 30}


def initialize(rpc):
    reply = rpc.request("initialize", {
        "protocolVersion": "2025-11-25", "capabilities": {},
        "clientInfo": {"name": "three-stdio-test", "version": "1"},
    })
    assert reply["result"]["serverInfo"]["name"] == "three", reply
    assert "tools" in reply["result"]["capabilities"], reply
    rpc.raw(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}))


def run(binary, scratch):
    db = scratch / "three.sqlite"
    env = dict(os.environ, THREE_DB=str(db))
    rpc = RPC(binary, env)
    try:
        initialize(rpc)
        tools = rpc.request("tools/list")["result"]["tools"]
        names = {tool["name"] for tool in tools}
        assert len(names) == 27, names
        assert {"plan_day", "set_task_strict", "get_history", "get_history_report"} <= names
        assert not {"block_now", "get_meetings", "get_free_time", "remove_block_rule", "disable_blocking", "request_block_exception"} & names
        for tool in tools:
            assert tool["inputSchema"]["additionalProperties"] is False, tool
        resources = rpc.request("resources/list")["result"]["resources"]
        assert {item["uri"] for item in resources} == {"three://today", "three://plan-day-guide"}
        guide = rpc.request("resources/read", {"uri": "three://plan-day-guide"})["result"]["contents"][0]
        assert "commit=false" in guide["text"] and "25%" in guide["text"]
        assert rpc.request("resources/read", {"uri": "three://unknown"})["error"]["code"] == -32602
        rpc.raw("{invalid-json")
        assert rpc.receive()["error"]["code"] == -32700
        assert rpc.request("unknown/method")["error"]["code"] == -32601
        assert rpc.request("tools/call", {"arguments": {}})["error"]["code"] == -32602
        rpc.call("block_now", {"minutes": 30}, error="unknown_tool")
        for args in [{"date": "2026-02-30"}, {"date": "2026-1-01"}, {"date": 42}, {"date": "today", "extra": True}]:
            rpc.call("get_day", args, error="invalid_input")
        assert rpc.call("get_today")["tasks"] == []
        assert rpc.call("get_status") is None
        for stamp in ["2026-02-30T09:00:00Z", "2026-11-03T25:00:00Z", "2026-11-03T09:00:00", "bad"]:
            rpc.call("add_task", dict(task("Bad timestamp"), date="today", scheduled_start=stamp), error="invalid_input")
        rpc.call("stop", error="no_running_session")
        for malformed in [None, [], "wrong"]:
            reply = rpc.request("tools/call", {"name": "plan_day", "arguments": malformed})
            assert "error" in reply or reply["result"].get("isError") is True, reply

        notify = ctypes.CDLL("/usr/lib/system/libsystem_notify.dylib")
        token = ctypes.c_int()
        assert notify.notify_register_check(b"com.deyalla.three.changed", ctypes.byref(token)) == 0
        changed = ctypes.c_int()
        assert notify.notify_check(token.value, ctypes.byref(changed)) == 0
        try:
            proposal = rpc.call("plan_day", {"date": "today", "tasks": [task("Review draft"), task("Ship feature")]})
            assert proposal["day"]["plan"]["status"] == "draft"
            assert proposal["day"]["plan"]["source"] == "mcp"
            assert notify.notify_check(token.value, ctypes.byref(changed)) == 0 and changed.value == 1
        finally:
            notify.notify_cancel(token.value)
        first, second = [row["task"]["id"] for row in proposal["day"]["tasks"]]
        rpc.call("plan_day", {"date": "today", "tasks": [task("First valid"), dict(task("Bad category"), category="Missing")]}, error="no_such_category")
        assert [row["task"]["id"] for row in rpc.call("get_today")["tasks"]] == [first, second]
        rpc.call("update_task", {"id": first, "title": " \n "}, error="invalid_input")
        rpc.call("update_task", {"id": first, "strict": False}, error="invalid_input")
        rpc.call("update_task", {"id": first, "notes": "Next action", "title": "Reviewed draft"})
        rpc.call("set_task_strict", {"id": first})
        rpc.call("set_task_strict", {"id": first})
        rpc.call("set_task_strict", {"id": first, "strict": False}, error="invalid_input")
        rpc.call("move_task", {"id": second, "index": 0})
        assert rpc.call("get_today")["tasks"][0]["task"]["id"] == second
        shared = json.loads(subprocess.check_output([str(binary), "today", "--json"], env=env, text=True))
        assert shared["tasks"][1]["title"] == "Reviewed draft"
        subprocess.run([str(binary), "add", "CLI shared row", "--cat", "Coding", "--block", "30m"], env=env, check=True, capture_output=True)
        today_resource = rpc.request("resources/read", {"uri": "three://today"})["result"]["contents"][0]
        day = json.loads(today_resource["text"])
        assert day["tasks"][-1]["task"]["createdBy"] == "cli"
        assert day["tasks"][1]["task"]["strict"] is True
        assert day["tasks"][1]["task"]["notes"] == "Next action"

        rpc.call("commit_day", {"date": "today"})
        before = rpc.call("get_today")
        rpc.call("plan_day", {"date": "today", "tasks": [task("Unsafe draft")]}, error="invalid_input")
        assert rpc.call("get_today")["tasks"] == before["tasks"]
        rpc.call("set_task_status", {"id": first, "status": "active"}, error="invalid_input")
        rpc.call("start_focus", {"task_id": first, "minutes": 0}, error="invalid_input")
        rpc.call("start_focus", {"task_id": first, "minutes": "30"}, error="invalid_input")
        rpc.call("start_focus", {"task_id": first, "minutes": 10})
        running = rpc.call("get_status")
        assert running["taskId"] == first and 590 <= running["remainingSeconds"] <= 600
        rpc.call("start_focus", {"task_id": second}, error="already_running")
        rpc.call("carry_task", {"id": first}, error="invalid_input")
        rpc.call("pause")
        assert rpc.call("get_status")["paused"] is True
        rpc.call("resume")
        rpc.call("extend", {"minutes": 5})
        assert rpc.call("get_status")["remainingSeconds"] > 880
        rpc.call("finish_focus", {"outcome": "progress", "rating": 2, "mark_task_done": False, "note": "Made progress"})
        assert rpc.call("get_status") is None
        history = rpc.call("get_history", {"from": "today", "to": "today"})
        assert history[0]["note"] == "Made progress" and history[0]["outcome"] == "progress"
        rpc.call("get_history", {"from": "tomorrow", "to": "today"}, error="invalid_input")
        rpc.call("get_history", {"from": "2020-01-01", "to": "today"}, error="invalid_input")
        rpc.call("start_break", {"minutes": 5})
        rpc.call("stop")

        rpc.call("plan_day", {"date": "tomorrow", "tasks": [dict(task("Tagged carry"), tags=["launch"], strict=True)]})
        tomorrow = rpc.call("get_day", {"date": "tomorrow"})["tasks"][0]["task"]["id"]
        rpc.call("schedule_task", {"id": tomorrow, "date": "inbox"})
        subprocess.run([str(binary), "step", "add", tomorrow, "First step"], env=env, check=True, capture_output=True)
        rpc.call("schedule_task", {"id": tomorrow, "date": "tomorrow"})
        copied = rpc.call("carry_task", {"id": tomorrow})
        rpc.call("carry_task", {"id": tomorrow}, error="invalid_input")
        rpc.call("remove_task", {"id": tomorrow}, error="invalid_input")
        rpc.call("set_task_status", {"id": tomorrow, "status": "todo"}, error="invalid_input")
        future_date = (datetime.date.today() + datetime.timedelta(days=2)).isoformat()
        future = rpc.call("get_day", {"date": future_date})
        assert future["tasks"][0]["task"]["id"] == copied["id"]
        assert future["tasks"][0]["tags"][0]["name"] == "launch"
        assert future["tasks"][0]["steps"][0]["title"] == "First step"
        assert any(row["task"]["id"] == first for row in rpc.call("get_carryover", {"date": "tomorrow"}))
        rpc.call("schedule_task", {"id": copied["id"], "date": "inbox"})
        rpc.call("schedule_task", {"id": copied["id"], "date": future_date})
        rpc.call("remove_task", {"id": copied["id"]})
        rpc.call("update_task", {"id": copied["id"], "title": "Resurrect"}, error="no_such_task")
        rpc.call("set_task_strict", {"id": copied["id"]}, error="no_such_task")

        category = rpc.call("upsert_category", {"name": "Research", "color_hex": "#123456"})
        rpc.call("upsert_category", {"id": category["id"], "name": "Deep research", "archived": True})
        assert any(row["name"] == "Deep research" and row["archived"] for row in rpc.call("list_categories"))
        rpc.call("upsert_category", {"name": "Missing color"}, error="invalid_input")
        rpc.call("upsert_category", {"name": "Bad color", "color_hex": "red"}, error="invalid_input")
        rpc.call("add_block_rule", {"kind": "domain", "value": "reddit.com"})
        rules = rpc.call("add_block_rule", {"kind": "domain", "value": "reddit.com"})["rules"]
        assert len(rules) == 1 and rules[0]["enabled"]
        rpc.call("add_block_rule", {"kind": "app", "value": "com.example.distraction"})
        rpc.call("add_block_rule", {"kind": "domain", "value": "reddit.com/path"}, error="block_rule_error")
        assert len(rpc.call("get_block_status")["rules"]) == 2
        rpc.call("add_block_rule", {"kind": "domain", "value": "reddit.com", "enabled": False}, error="invalid_input")

        rpc.call("plan_day", {"date": future_date, "tasks": []})
        peer = RPC(binary, env)
        try:
            initialize(peer)
            start_ids = [client.send("tools/call", {"name": "start_focus", "arguments": {"task_id": task_id}})
                         for client, task_id in [(rpc, first), (peer, second)]]
            starts = [client.receive(request_id) for client, request_id in zip([rpc, peer], start_ids)]
            assert sum(reply["result"].get("isError") is not True for reply in starts) == 1
            failures = [reply for reply in starts if reply["result"].get("isError")]
            assert json.loads(failures[0]["result"]["content"][0]["text"])["code"] == "already_running"
            assert rpc.call("get_status")["id"] == peer.call("get_status")["id"]
            rpc.call("stop")
            pending = []
            for client, prefix in [(rpc, "first"), (peer, "peer")]:
                ids = [client.send("tools/call", {"name": "add_task", "arguments": dict(task(f"Concurrent {prefix} {i}"), date=future_date)}) for i in range(4)]
                pending.append((client, ids))
            replies = []
            for client, ids in pending:
                batch = [client.receive() for _ in ids]
                assert {reply["id"] for reply in batch} == set(ids)
                replies.extend(batch)
        finally:
            peer.close()
        assert sum(reply["result"].get("isError") is not True for reply in replies) == 5
        assert all(json.loads(reply["result"]["content"][0]["text"])["code"] == "too_many_tasks" for reply in replies if reply["result"].get("isError"))
        capped = rpc.call("get_day", {"date": future_date})["tasks"]
        dropped = capped[0]["task"]["id"]
        rpc.call("set_task_status", {"id": dropped, "status": "dropped"})
        rpc.call("add_task", dict(task("Replacement slot"), date=future_date))
        rpc.call("set_task_status", {"id": dropped, "status": "todo"}, error="too_many_tasks")
        rpc.call("plan_day", {"date": future_date, "tasks": [task(str(i)) for i in range(6)]}, error="invalid_input")
        assert len(rpc.call("get_day", {"date": future_date})["tasks"]) == 6
        with sqlite3.connect(db) as connection:
            connection.execute("UPDATE dayPlan SET status = 'closed' WHERE day = ?", (future_date,))
        rpc.call("commit_day", {"date": future_date}, error="invalid_input")
        for commit in [True, False]:
            rpc.call("plan_day", {"date": future_date, "tasks": [], "commit": commit}, error="invalid_input")
        assert rpc.call("get_day", {"date": future_date})["plan"]["status"] == "closed"
        for _ in range(5):
            rpc.call("get_today")
        with sqlite3.connect(db) as connection:
            assert connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert not connection.execute("PRAGMA foreign_key_check").fetchall()
            assert connection.execute("SELECT COUNT(*) FROM session WHERE endedAt IS NULL").fetchone()[0] == 0
        print(f"PASS: {len(names)} tool schemas, two resources, real stdio lifecycle, malformed requests, shared CLI reads/writes and Darwin signal, draft/closed guards, cap concurrency, timer, carry-over, strictness and blocker rules.")
    finally:
        rpc.close()
    restarted = RPC(binary, env)
    try:
        initialize(restarted)
        assert restarted.call("get_today")["plan"]["status"] == "committed"
        assert len(restarted.call("get_history", {"from": "today", "to": "today"})) == 3
    finally:
        restarted.close()
    bare_binary = scratch / "three-without-resources"
    shutil.copy2(binary, bare_binary)
    bare = RPC(bare_binary, env)
    try:
        initialize(bare)
        assert bare.request("resources/read", {"uri": "three://plan-day-guide"})["error"]["code"] == -32603
        bare.call("get_today")
    finally:
        bare.close()
    failed = subprocess.run([str(binary), "mcp"], env=dict(env, THREE_DB=str(scratch)), input="", text=True, capture_output=True, timeout=15)
    assert failed.returncode != 0 and failed.stdout == "", failed
    assert "MCP server could not start" in failed.stderr and len(failed.stderr) < 1024, failed.stderr
    print("PASS: restart reads persisted plans, sessions and reflections; two-server timer/cap races; bounded stderr startup failure. All database writes stayed under THREE_DB scratch.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    root = Path(__file__).resolve().parent.parent
    (root / "build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="mcp-test-", dir=root / "build") as folder:
        run(binary, Path(folder))


if __name__ == "__main__":
    main()
