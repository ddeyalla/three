#!/usr/bin/env python3
"""Measure validated release Store, JSON, CLI, and persistent MCP reads on scratch data."""
import argparse
import ctypes
import datetime as dt
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import platform
import resource
import shutil
import sqlite3
import statistics
import subprocess
import sys
import threading
import time

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "build/verification/non-calendar"
spec = importlib.util.spec_from_file_location("mcp_fixture", ROOT / "scripts/test-mcp.py")
mcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp)


class UsageV2(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(name, ctypes.c_uint64) for name in (
        "user_time", "system_time", "pkg_idle_wkups", "interrupt_wkups", "pageins", "wired_size",
        "resident_size", "phys_footprint", "proc_start_abstime", "proc_exit_abstime", "child_user_time",
        "child_system_time", "child_pkg_idle_wkups", "child_interrupt_wkups", "child_pageins",
        "child_elapsed_abstime", "diskio_bytesread", "diskio_byteswritten")]


def owned_usage(pids):
    lib = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    result = {}
    for pid in pids:
        info = UsageV2()
        code = lib.proc_pid_rusage(pid, 2, ctypes.byref(info))
        result[str(pid)] = ({"errno": ctypes.get_errno()} if code else
                            {key: getattr(info, key) for key in ("user_time", "system_time", "pageins", "resident_size",
                                                                "diskio_bytesread", "diskio_byteswritten")})
    return result


def run(*args, **kwargs):
    try:
        return subprocess.run([str(x) for x in args], check=True, capture_output=True, text=True, **kwargs).stdout
    except subprocess.CalledProcessError as exc:
        print(exc.stderr, file=sys.stderr)
        raise


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot():
    return {"at": dt.datetime.now(dt.timezone.utc).isoformat(), "uptime": run("uptime").strip(),
            "cores": int(run("sysctl", "-n", "hw.ncpu")),
            "top_cpu": "\n".join(run("ps", "-axo", "pid,ppid,%cpu,comm", "-r").splitlines()[:16])}


def storage(database):
    with sqlite3.connect(f"{database.as_uri()}?mode=ro", uri=True) as db:
        dump = "\n".join(db.iterdump()).encode()
        counts = {name: db.execute(f'SELECT count(*) FROM "{name}"').fetchone()[0]
                  for name, in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    return {"logical_sha256": hashlib.sha256(dump).hexdigest(), "main_sha256": sha(database),
            "bytes": database.stat().st_size, "tables": counts}


def check_schema(db):
    migrations = [x[0] for x in db.execute("SELECT identifier FROM grdb_migrations")]
    assert migrations[-1] == "v12-sleep-recovery", migrations
    assert db.execute("SELECT count(*) FROM recoveryGap").fetchone()[0] == 0
    assert db.execute("SELECT count(*) FROM recoveryImpact").fetchone()[0] == 0
    assert db.execute("SELECT count(*) FROM session WHERE recoveryTrimSeconds <> 0").fetchone()[0] == 0


def fixture(binary, database, end, env):
    run(binary, "stats", "--json", env=env)
    first = end - dt.timedelta(days=365)
    with sqlite3.connect(database) as db:
        db.execute("PRAGMA foreign_keys=ON")
        categories = [row[0] for row in db.execute("SELECT id FROM category ORDER BY position")]
        for j in range(6):
            db.execute("INSERT INTO tag VALUES(?,?,0,?,?)", (f"tag{j}", f"Track {j}", str(first), str(first)))
        for j in range(3):
            db.execute("INSERT INTO blockRule(id,kind,value,createdAt,updatedAt) VALUES(?,'domain',?,?,?)",
                       (f"rule{j}", f"fixture{j}.example", str(first), str(first)))
        for i in range(366):
            day = first + dt.timedelta(days=i)
            stamp = f"{day} 00:00:00.000"
            plan = f"plan{i:03}"
            db.execute("INSERT INTO dayPlan(id,day,status,source,createdAt,committedAt,updatedAt) VALUES(?,?,'committed','app',?,?,?)",
                       (plan, str(day), stamp, stamp, stamp))
            commitments = []
            for j, minutes in enumerate([25, 30, 45, 20, 40]):
                task = f"task{i:03}-{j}"
                db.execute("""INSERT INTO task(id,dayPlanId,position,title,categoryId,blockMinutes,strict,status,notes,createdBy,updatedAt,doneAt)
                    VALUES(?,?,?,?,?,?,?,?,'Retained synthetic measurement fixture','app',?,?)""",
                           (task, plan, j, f"Work {i:03} {j}", categories[j], minutes, j == 0,
                            "done" if j < 3 else "partial", stamp, f"{day} 05:00:00.000" if j < 3 else None))
                commitments.append({"taskId": task, "plannedMinutes": minutes})
                for tag in (0, j + 1):
                    db.execute("INSERT INTO taskTag VALUES(?,?)", (task, f"tag{tag}"))
                for k in range(2):
                    db.execute("INSERT INTO step(id,taskId,position,title,done,updatedAt) VALUES(?,?,?,?,?,?)",
                               (f"step{i:03}-{j}-{k}", task, k, f"Check {k}", j < 3, stamp))
                    session = f"focus{i:03}-{j}-{k}"
                    start = f"{day} {j:02}:{0 if k == 0 else 27:02}:00.000"
                    stop = f"{day} {j:02}:{22 if k == 0 else 37:02}:00.000"
                    db.execute("""INSERT INTO session(id,taskId,kind,plannedSeconds,startedAt,pausedSeconds,endedAt,endReason,outcome,focusRating,note,updatedAt)
                        VALUES(?,?,'focus',?,?,?,?, 'completed','progress',?,'Recorded fixture reflection',?)""",
                               (session, task, 1200 if k == 0 else 600, start, 120 if k == 0 else 0, stop,
                                3 if k == 0 else (2 if j < 4 else None), stamp))
                    if k == 0 or j < 3:
                        db.execute("INSERT INTO breakDecision VALUES(?,?,?)", (session, "taken" if k == 0 else "skipped", stop))
                    for e, action in enumerate(["blocked", "blocked", "unblocked"]):
                        db.execute("INSERT INTO blockEvent(id,sessionId,action,at,ruleId) VALUES(?,?,?,?,?)",
                                   (f"event{i:03}-{j}-{k}-{e}", session, action, start, f"rule{j % 3}"))
            if i % 7:
                db.execute("INSERT INTO planCommitment VALUES(?,?,?)", (plan, stamp, json.dumps(commitments)))
            for k in range(3):
                db.execute("""INSERT INTO session(id,kind,plannedSeconds,startedAt,pausedSeconds,endedAt,endReason,updatedAt)
                    VALUES(?,'break',300,?,0,?,'completed',?)""",
                           (f"break{i:03}-{k}", f"{day} {k:02}:22:00.000", f"{day} {k:02}:27:00.000", stamp))
            for k, (session, action) in enumerate([(None, "blocked")] * 3 + [(None, "unblocked"), (f"break{i:03}-0", "blocked")]):
                db.execute("INSERT INTO blockEvent(id,sessionId,action,at,ruleId) VALUES(?,?,?,?, 'rule0')",
                           (f"ambient{i:03}-{k}", session, action, stamp))
        assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert not db.execute("PRAGMA foreign_key_check").fetchall()
        check_schema(db)
        db.commit()
        db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    return first


def metrics(indices, tag=None):
    n = len(indices)
    known = sum(i % 7 != 0 for i in indices)
    tasks = list(range(5)) if tag in (None, 0) else [tag - 1]
    count = len(tasks)
    focus = n * count * 1800
    planned = sum([25, 30, 45, 20, 40][j] * 60 for j in tasks)
    return {"focusSeconds": focus, "derivedPlannedSeconds": n * planned,
            "committedPlanCount": n, "commitmentSnapshotPlanCount": known,
            "legacyCommittedPlanCount": n - known, "committedPlannedSeconds": known * planned,
            "accuracyFocusSeconds": known * count * 1800,
            "completedTaskCount": known * sum(j < 3 for j in tasks), "committedPlannedTaskCount": known * count,
            "quality": {"focusSessionCount": n * count * 2, "ratedSessionCount": n * (count * 2 - (4 in tasks)),
                        "focusedSessionCount": n * count, "missingRatingCount": n * (4 in tasks)},
            "blocks": {"associatedHits": n * count * 4, "associatedUnblocks": n * count * 2,
                       "unassociatedHits": n * 4 if tag is None else 0,
                       "unassociatedUnblocks": n if tag is None else 0, "unresolvedSessionEventCount": 0},
            "breaks": {"endedFocusSessionCount": n * count * 2, "pendingFocusSessionCount": 0,
                       "takenCount": n * count, "skippedCount": n * sum(j < 3 for j in tasks),
                       "missingDecisionCount": n * sum(j >= 3 for j in tasks)}}


def subset(actual, expected):
    for key, value in expected.items():
        if isinstance(value, dict):
            subset(actual[key], value)
        else:
            assert actual[key] == value, (key, actual[key], value)


def validate(result, case, first):
    dates = [first + dt.timedelta(days=i) for i in case["indices"]]
    assert result["from"] == str(dates[0]) and result["through"] == str(dates[-1])
    assert [d["day"] for d in result["days"]] == [str(x) for x in dates]
    n = len(dates)
    if case["kind"] == "history":
        expected = {"focusSeconds": 9000, "breakSeconds": 900, "plannedSeconds": 9600,
                    "plannedTaskCount": 5, "doneTaskCount": 3, "focusSessionCount": 10, "breakSessionCount": 3}
        subset(result["totals"], {k: v * n for k, v in expected.items()})
        for day, index in zip(result["days"], case["indices"]):
            subset(day["totals"], expected)
            assert len(day["tasks"]) == 5 and len(day["sessions"]) == 13
            assert {t["task"]["id"] for t in day["tasks"]} == {f"task{index:03}-{j}" for j in range(5)}
            for task in day["tasks"]:
                assert len(task["steps"]) == 2 and len(task["tags"]) == 2
                assert task["focusSeconds"] == 1800 and len(task["sessionIds"]) == 2
            for session in day["sessions"]:
                ident = session["session"]["id"]
                expected_seconds = 300 if ident.startswith("break") else (1200 if ident.endswith("-0") else 600)
                assert session["actualSeconds"] == expected_seconds
        for month in result["months"]:
            included = [d for d in dates if str(d).startswith(month["month"])]
            assert month["dayCount"] == len(included)
            subset(month["totals"], {k: v * len(included) for k, v in expected.items()})
    else:
        validate_metrics(result["metrics"], case["indices"])
        assert len(result["tags"]) == 6
        for tag in [None] + list(range(6)):
            group = result if tag is None else next(x for x in result["tags"] if x["tag"]["id"] == f"tag{tag}")
            validate_metrics(group["metrics"], case["indices"], tag)
            for offset, (day, index) in enumerate(zip(group["days"], case["indices"])):
                assert day["day"] == str(first + dt.timedelta(days=index))
                validate_metrics(day["metrics"], [index], tag)
                assert day["averageDayCount"] == min(7, offset + 1)
                avg = day.get("sevenDayAverageMinutes")
                assert avg is None if offset < 6 else avg == (150 if tag in (None, 0) else 30)
            assert sum(w["includedDayCount"] for w in group["weeks"]) == n
            for week in group["weeks"]:
                indices = [i for i in case["indices"] if week["from"] <= str(first + dt.timedelta(days=i)) <= week["through"]]
                validate_metrics(week["metrics"], indices, tag)
        assert result["streak"]["days"] == n and result["streak"]["isLowerBound"] is True
        subset(result["missingData"], {"commitmentSnapshotsUnavailable": any(i % 7 == 0 for i in case["indices"]),
                                       "missingRatingCount": n, "missingBreakDecisionCount": n * 2})


def validate_metrics(actual, indices, tag=None):
    expected = metrics(indices, tag)
    subset(actual, expected)
    for key, numerator, denominator in [
        ("completion", expected["completedTaskCount"], expected["committedPlannedTaskCount"]),
        ("actualToPlanned", expected["accuracyFocusSeconds"], expected["committedPlannedSeconds"]),
    ]:
        subset(actual[key], {"numerator": numerator, "denominator": denominator})
        assert actual[key]["value"] is None if denominator == 0 else math.isclose(actual[key]["value"], numerator / denominator)
    for key, event in [("hitsPerFocusHour", "associatedHits"), ("unblocksPerFocusHour", "associatedUnblocks")]:
        assert math.isclose(actual["blocks"][key]["value"], expected["blocks"][event] / (expected["focusSeconds"] / 3600))
    quality = expected["quality"]
    assert math.isclose(actual["quality"]["focusedShare"]["value"], quality["focusedSessionCount"] / quality["ratedSessionCount"])


def normalized(result):
    return {k: v for k, v in result.items() if k != "takenAt"}


def verify_event_dates(sides, out):
    cases = [
        ("cairo-spring", "Africa/Cairo", ["2014-07-31", "2014-08-01"], "2014-07-31 21:59:59.500", "2014-07-31 22:01:00.000"),
        ("cairo-fall", "Africa/Cairo", ["2014-09-25"], "2014-09-25 21:30:00.000", "2014-09-25 21:31:00.000"),
        ("apia-skip", "Pacific/Apia", ["2011-12-29", "2011-12-30", "2011-12-31"], "2011-12-30 09:59:59.500", "2011-12-30 10:01:00.000"),
        ("la-midnight", "America/Los_Angeles", ["2026-11-01", "2026-11-02"], "2026-11-02 07:59:59.500", "2026-11-02 08:01:00.000"),
    ]
    results = []
    for name, zone, days, start, event_at in cases:
        folder = out / name
        folder.mkdir()
        database = folder / "dates.sqlite"
        env = dict(os.environ, THREE_DB=str(database), THREE_CHROME_DATA=str(folder / "chrome"), TZ=zone)
        run(sides[0]["binary"], "stats", "--json", env=env)
        with sqlite3.connect(database) as db:
            db.execute("PRAGMA foreign_keys=ON")
            db.execute("INSERT INTO blockRule(id,kind,value,createdAt,updatedAt) VALUES('dates','domain','dates.example',?,?)", (start, start))
            for ident, kind, seconds in [("focus", "focus", 600), ("break", "break", 300)]:
                end = dt.datetime.fromisoformat(start) + dt.timedelta(seconds=seconds)
                db.execute("INSERT INTO session(id,kind,plannedSeconds,startedAt,endedAt,endReason,updatedAt) VALUES(?,?,?,?,?,'stopped',?)",
                           (ident, kind, seconds, start, end.isoformat(sep=" ", timespec="milliseconds"), start))
            for ident, session, action in [("hit1", "focus", "blocked"), ("hit2", "focus", "blocked"),
                                           ("unblock", "focus", "unblocked"), ("ambient", None, "blocked"), ("break-hit", "break", "blocked")]:
                db.execute("INSERT INTO blockEvent(id,sessionId,action,at,ruleId) VALUES(?,?,?,?,'dates')", (ident, session, action, event_at))
            assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert not db.execute("PRAGMA foreign_key_check").fetchall()
            before = list(db.iterdump())
        canonical = {}
        for side in sides:
            rpc = MeasurementRPC(side["binary"], env)
            try:
                mcp.initialize(rpc)
                for kind, tool in [("history", "get_history_report"), ("stats", "get_stats")]:
                    cli = json.loads(run(side["binary"], kind, "--from", days[0], "--to", days[-1], "--json", env=env))
                    reply = rpc.call(tool, {"from": days[0], "to": days[-1]})
                    for result in [cli, reply]:
                        assert [day["day"] for day in result["days"]] == days
                        values = [day["totals" if kind == "history" else "metrics"] for day in result["days"]]
                        assert [v["focusSeconds"] for v in values] == [600] + [0] * (len(days) - 1)
                        if kind == "stats":
                            assert [v["blocks"]["associatedHits"] for v in values] == [2] + [0] * (len(days) - 1)
                            assert [v["blocks"]["associatedUnblocks"] for v in values] == [1] + [0] * (len(days) - 1)
                            assert [v["blocks"]["unassociatedHits"] for v in values] == [0] * (len(days) - 1) + [2]
                        else:
                            assert [v["breakSeconds"] for v in values] == [300] + [0] * (len(days) - 1)
                        stable = json.dumps(normalized(result), sort_keys=True, separators=(",", ":"))
                        if kind not in canonical:
                            canonical[kind] = stable
                            write(folder / f"{kind}.json", result)
                        assert stable == canonical[kind], (name, kind, side["name"])
            finally:
                rpc.close()
        with sqlite3.connect(database) as db:
            assert list(db.iterdump()) == before
        results.append({"case": name, "zone": zone, "days": days, "validated_responses": len(sides) * 4, "storage_unchanged": True})
    write(out / "date-checks.json", results)
    print("PASS Cairo transitions, Apia skipped date, and Los Angeles midnight event attribution across packaged CLI/MCP sides", flush=True)


class Probe:
    def __init__(self, binary, database, env, stderr):
        self.log = stderr.open("w")
        self.process = subprocess.Popen([str(binary), str(database)], env=env, text=True,
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.log, bufsize=1)
        try:
            assert json.loads(self.process.stdout.readline()) == {"ready": True}
        except BaseException:
            if self.process.poll() is None:
                self.process.kill()
            self.process.wait()
            self.log.close()
            raise

    def call(self, case):
        self.process.stdin.write(json.dumps({"kind": case["kind"], "from": case["from"], "to": case["to"], "days": len(case["indices"])}) + "\n")
        self.process.stdin.flush()
        reply = self.process.stdout.readline()
        assert reply, "Probe exited before returning a complete result"
        return json.loads(reply)

    def close(self):
        self.process.stdin.close()
        try:
            assert self.process.wait(timeout=15) == 0
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait()
            self.log.close()


class MeasurementRPC(mcp.RPC):
    def receive(self, expected=None):
        line = self.lines.get(timeout=15)
        assert line is not None, f"MCP exited early: {self.errors}"
        self.wire_bytes = len(line.encode())
        reply = json.loads(line)
        assert reply["jsonrpc"] == "2.0", reply
        if expected is not None:
            assert reply["id"] == expected, reply
        return reply


def compile_probe(out):
    products = ROOT / ".build/out/Products/Release"
    assert (products / "ThreeCore.o").exists(), "Run CONFIG=release ./scripts/bundle.sh first"
    sdk = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk")
    if not sdk.exists():
        sdk = Path(run("xcrun", "--show-sdk-path").strip())
    command = ["xcrun", "swiftc", "-O", "-g", "-parse-as-library", "-sdk", str(sdk),
               "-target", f"{platform.machine()}-apple-macos26.0", "-I", str(products),
               "-I", str(ROOT / ".build/checkouts/GRDB.swift/Sources/GRDBSQLite"),
               str(Path(__file__).with_suffix(".swift")), str(products / "ThreeCore.o"),
               str(products / "GRDB.o"), "-lsqlite3", "-o", str(out / "read-probe")]
    write(out / "probe-compile-command.json", command)
    (out / "probe-compile.log").write_text(run(*command))
    return out / "read-probe"


def profile(probe, case, rpc, out, first):
    stop = threading.Event()
    counters = []
    def observe():
        while not stop.is_set():
            counters.append({"at": time.monotonic(), "uptime": run("uptime").strip(),
                             "owned_processes": run("ps", "-p", f"{os.getpid()},{probe.process.pid},{rpc.process.pid}",
                                                    "-o", "pid=,ppid=,%cpu=,rss=,time=,pagein=,comm="),
                             "rusage": owned_usage([os.getpid(), probe.process.pid, rpc.process.pid])})
            stop.wait(0.5)
    watcher = threading.Thread(target=observe)
    watcher.start()
    sample_log = (out / "sample-tool.log").open("w")
    sampler = subprocess.Popen(["sample", str(probe.process.pid), "5", "1", "-file", str(out / "probe.sample.txt")],
                               stdout=sample_log, stderr=sample_log)
    completed = 0
    usage_before = resource.getrusage(resource.RUSAGE_SELF)
    start = time.monotonic()
    try:
        while time.monotonic() - start < 10:
            reply = probe.call(case)
            validate(reply["result"], case, first)
            completed += 1
        code = sampler.wait(timeout=15)
        fallback = None
        if code != 0:
            fallback = run("ps", "-p", str(probe.process.pid), "-o", "pid=,%cpu=,time=,pagein=,comm=")
        usage_after = resource.getrusage(resource.RUSAGE_SELF)
        write(out / "profile.json", {"reported_samples": False, "case": case["name"], "iterations": completed,
                                    "wall_seconds": time.monotonic() - start, "sample_exit": code,
                                    "fallback": fallback, "counters": counters,
                                    "generator_user_seconds": usage_after.ru_utime - usage_before.ru_utime,
                                    "generator_system_seconds": usage_after.ru_stime - usage_before.ru_stime})
    finally:
        stop.set()
        watcher.join()
        if sampler.poll() is None:
            sampler.kill()
            sampler.wait()
        sample_log.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="New directory under build/verification/non-calendar")
    parser.add_argument("--through", type=dt.date.fromisoformat, required=True)
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--baseline", type=Path, help="Completed v12 run with preserved optimized artifacts")
    args = parser.parse_args()
    out = args.output.resolve()
    assert out.is_relative_to(EVIDENCE.resolve()) and not out.exists(), "Use a NEW scratch output directory"
    assert args.samples >= 5
    assert args.through == dt.datetime.now(dt.timezone.utc).date(), "The true default 28-day case must end today UTC"
    changed = run("git", "diff", "--name-only", "HEAD", "--", "Sources", "Package.swift", "Package.resolved", "scripts/bundle.sh", "scripts/swift.sh").splitlines()
    assert not changed or (args.baseline and changed == ["Sources/ThreeCore/Stats.swift"]), "Only the measured Stats candidate may differ from HEAD"
    inputs = {name: sha(ROOT / name) for name in run("git", "ls-files", "Sources", "Package.swift", "Package.resolved", "scripts/bundle.sh", "scripts/swift.sh").splitlines()}
    out.mkdir(parents=True)
    shutil.copy2(Path(__file__), out / "driver-source.py")
    shutil.copy2(Path(__file__).with_suffix(".swift"), out / "probe-source.swift")
    (out / "codesign.log").write_text(run("codesign", "--verify", "--deep", "--strict", ROOT / "build/Three.app"))
    probe_binary = compile_probe(out)
    run("ditto", ROOT / "build/Three.app", out / "Three.app")
    (out / "archived-codesign.log").write_text(run("codesign", "--verify", "--deep", "--strict", out / "Three.app"))
    binary = out / "Three.app/Contents/Helpers/three"
    sides = [{"name": "candidate" if args.baseline else "baseline", "binary": binary, "probe_binary": probe_binary}]
    if args.baseline:
        baseline = args.baseline.resolve()
        assert baseline.is_relative_to(EVIDENCE.resolve())
        previous = json.loads((baseline / "manifest.json").read_text())
        assert previous["through"] == str(args.through) and previous["schema"] == "v12-sleep-recovery"
        assert {k: v for k, v in inputs.items() if k != "Sources/ThreeCore/Stats.swift"} == {k: v for k, v in previous["product_inputs"].items() if k != "Sources/ThreeCore/Stats.swift"}
        assert previous["probe_source_sha256"] == sha(Path(__file__).with_suffix(".swift"))
        assert json.loads((baseline / "errors.json").read_text())["unexpected_errors_or_rejections"] == 0
        baseline_binary = baseline / "Three.app/Contents/Helpers/three"
        baseline_probe = baseline / "read-probe"
        assert sha(baseline_binary) == previous["binary_sha256"] and sha(baseline_probe) == previous["probe_sha256"]
        (out / "baseline-codesign.log").write_text(run("codesign", "--verify", "--deep", "--strict", baseline / "Three.app"))
        sides.insert(0, {"name": "baseline", "binary": baseline_binary, "probe_binary": baseline_probe})
    (out / "product.diff").write_text(run("git", "diff", "HEAD", "--", "Sources", "Package.swift", "Package.resolved"))
    database = out / "fixture.sqlite"
    env = dict(os.environ, THREE_DB=str(database), THREE_CHROME_DATA=str(out / "chrome"), TZ="UTC")
    first = args.through - dt.timedelta(days=365)
    month_end = args.through.replace(day=1) - dt.timedelta(days=1)
    month_start = month_end.replace(day=1)
    cases = []
    for name, kind, start, end, default in [
        ("history-month", "history", month_start, month_end, False),
        ("stats-default28", "stats", args.through - dt.timedelta(days=27), args.through, True),
        ("history-366", "history", first, args.through, False),
        ("stats-366", "stats", first, args.through, False),
    ]:
        cases.append({"name": name, "kind": kind, "from": None if default else str(start),
                      "to": None if default else str(end), "indices": list(range((start - first).days, (end - first).days + 1))})
    write(out / "manifest.json", {"claim": "Reusing History civil dates reduces linked-event conversion work; a latency difference is inconclusive when the alternating run spread exceeds the gap.",
                                  "head": run("git", "rev-parse", "HEAD").strip(), "cwd": str(ROOT),
                                  "binary": str(binary), "binary_sha256": sha(binary), "probe_sha256": sha(probe_binary),
                                  "schema": "v12-sleep-recovery", "baseline": str(args.baseline.resolve()) if args.baseline else None,
                                  "sides": [{"name": s["name"], "binary": str(s["binary"]), "binary_sha256": sha(s["binary"]),
                                             "probe_sha256": sha(s["probe_binary"])} for s in sides],
                                  "stats_source_sha256": sha(ROOT / "Sources/ThreeCore/Stats.swift"),
                                  "product_inputs": inputs,
                                  "driver_sha256": sha(Path(__file__)), "probe_source_sha256": sha(Path(__file__).with_suffix(".swift")),
                                  "first": str(first), "through": str(args.through), "timezone": "UTC",
                                  "warmups_per_case_per_path": 1, "measured_samples": args.samples, "cases": cases,
                                  "expected_rows": {"dayPlan": 366, "task": 1830, "session": 4758, "tag": 6, "taskTag": 3660,
                                                    "step": 3660, "blockEvent": 12810, "planCommitment": 313, "breakDecision": 2928,
                                                    "recoveryGap": 0, "recoveryImpact": 0},
                                  "expected_metrics": {c["name"]: metrics(c["indices"]) for c in cases},
                                  "host_before": snapshot(), "macos": run("sw_vers"), "swift": run("xcrun", "swift", "--version")})
    if args.baseline:
        shutil.copy2(baseline / "fixture.sqlite", database)
        with sqlite3.connect(database) as db:
            check_schema(db)
            assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert not db.execute("PRAGMA foreign_key_check").fetchall()
        assert storage(database) == json.loads((baseline / "storage-after.json").read_text())
    else:
        fixture(binary, database, args.through, env)
    owned_pids = []
    records = []
    errors = []
    canonical = {}
    if args.baseline:
        canonical = {c["name"]: json.dumps(normalized(json.loads((baseline / f"{c['name']}.json").read_text())), sort_keys=True, separators=(",", ":")) for c in cases}
    monitor_stop = threading.Event()
    monitor_errors = []
    def monitor():
        try:
            with (out / "owned-counters.jsonl").open("w") as log:
                while not monitor_stop.is_set():
                    log.write(json.dumps({"at": time.monotonic(), "uptime": run("uptime").strip(),
                                          "processes": run("ps", "-p", ",".join(map(str, owned_pids)),
                                                           "-o", "pid=,ppid=,%cpu=,rss=,time=,pagein=,comm="),
                                          "rusage": owned_usage(owned_pids)}) + "\n")
                    log.flush()
                    monitor_stop.wait(1)
        except Exception as exc:
            monitor_errors.append({"type": type(exc).__name__, "message": str(exc)})
    before = None
    monitor_thread = None
    try:
        for side in sides:
            side["probe"] = Probe(side["probe_binary"], database, env, out / f"{side['name']}-probe-stderr.log")
            side["rpc"] = MeasurementRPC(side["binary"], env)
            mcp.initialize(side["rpc"])
        owned_pids = [os.getpid()] + [p.process.pid for s in sides for p in [s["probe"], s["rpc"]]]
        with sqlite3.connect(database) as db:
            assert db.execute("PRAGMA wal_checkpoint(FULL)").fetchone()[0] == 0
        db.close()
        before = storage(database)
        manifest = json.loads((out / "manifest.json").read_text())
        subset(before["tables"], manifest["expected_rows"])
        write(out / "storage-before.json", before)
        monitor_thread = threading.Thread(target=monitor)
        monitor_thread.start()
        for round_number in range(args.samples + 1):
            order = cases[round_number % len(cases):] + cases[:round_number % len(cases)]
            for case in order:
                write(out / "host-current.json", snapshot())
                for side in sides:
                    probe, rpc, binary = side["probe"], side["rpc"], side["binary"]
                    for path in ["store", "mcp", "cli"]:
                        start = time.perf_counter_ns()
                        if path == "store":
                            response = probe.call(case)
                            result = response.pop("result")
                        elif path == "mcp":
                            bounds = {} if case["from"] is None else {"from": case["from"], "to": case["to"]}
                            reply = rpc.request("tools/call", {"name": "get_history_report" if case["kind"] == "history" else "get_stats", "arguments": bounds})
                            assert "error" not in reply, reply
                            body = reply["result"]
                            assert not body.get("isError", False), body
                            text = body["content"][0]["text"]
                            result = json.loads(text)
                            response = {"payload_bytes": len(text.encode()), "wire_bytes": rpc.wire_bytes}
                        else:
                            command = [str(binary), case["kind"], "--json"]
                            if case["from"]:
                                command += ["--from", case["from"], "--to", case["to"]]
                            raw = run(*command, env=env)
                            result = json.loads(raw)
                            response = {"payload_bytes": len(raw.encode())}
                        parsed = time.perf_counter_ns()
                        validate(result, case, first)
                        stable = json.dumps(normalized(result), sort_keys=True, separators=(",", ":"))
                        if case["name"] not in canonical:
                            canonical[case["name"]] = stable
                        assert stable == canonical[case["name"]], f"Full result differs for {side['name']} {path} {case['name']}"
                        if not (out / f"{case['name']}.json").exists():
                            write(out / f"{case['name']}.json", result)
                        done = time.perf_counter_ns()
                        record = {"case": case["name"], "side": side["name"], "path": path, "warmup": round_number == 0, "round": round_number,
                                  "parsed_ns": parsed - start, "validated_ns": done - start,
                                  "normalized_sha256": hashlib.sha256(stable.encode()).hexdigest(), **response}
                        records.append(record)
                        with (out / "samples.jsonl").open("a") as log:
                            log.write(json.dumps(record) + "\n")
                with (out / "host-snapshots.jsonl").open("a") as log:
                    log.write(json.dumps(snapshot()) + "\n")
            print(f"Completed {'warmup' if round_number == 0 else 'measured round ' + str(round_number)}", flush=True)
        for side in sides:
            profile_out = out / (side["name"] + "-profile")
            profile_out.mkdir()
            profile(side["probe"], cases[-1], side["rpc"], profile_out, first)
    except BaseException as exc:
        errors.append({"type": type(exc).__name__, "message": str(exc)})
        raise
    finally:
        monitor_stop.set()
        if monitor_thread is not None:
            monitor_thread.join()
        cleanup = []
        for side in sides:
            for path in ["probe", "rpc"]:
                if path not in side:
                    continue
                process = side[path].process
                try:
                    side[path].close()
                except Exception as exc:
                    errors.append({"type": type(exc).__name__, "message": str(exc)})
                    if process.poll() is None:
                        process.kill()
                        process.wait()
                cleanup.append({"side": side["name"], "path": path, "pid": process.pid, "exit": process.returncode})
        write(out / "cleanup.json", cleanup)
        after = storage(database)
        write(out / "storage-after.json", after)
        errors.extend(monitor_errors)
        if before is not None and before != after:
            errors.append({"type": "StorageChanged", "message": "Reads changed disposable storage"})
        write(out / "errors.json", {"unexpected_errors_or_rejections": len(errors), "errors": errors, "mcp_stderr": {s["name"]: s["rpc"].errors for s in sides if "rpc" in s}})
        assert before is None or before == after, "Reads changed disposable storage"
        assert not errors, errors
    summary = []
    for side in sides:
        for case in cases:
            for path in ["store", "mcp", "cli"]:
                rows = [r for r in records if r["case"] == case["name"] and r["path"] == path and r["side"] == side["name"] and not r["warmup"]]
                fields = ["query_ns", "compact_encode_ns", "pretty_encode_ns"] if path == "store" else ["parsed_ns", "validated_ns"]
                for field in fields:
                    values = [r[field] / 1e6 for r in rows]
                    summary.append({"case": case["name"], "side": side["name"], "path": path, "metric": field, "n": len(values),
                                    "median_ms": statistics.median(values), "min_ms": min(values), "max_ms": max(values)})
    write(out / "summary.json", summary)
    write(out / "host-after.json", snapshot())
    print(json.dumps({"output": str(out), "validated_responses": len(records), "unexpected_errors_or_rejections": 0,
                      "storage_unchanged": True, "summary": summary}, indent=2))
    if args.baseline:
        verify_event_dates(sides, out)


if __name__ == "__main__":
    main()
