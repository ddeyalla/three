#!/usr/bin/env python3
"""Capture a packaged helper's schema using a new disposable database."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile


def capture(binary: Path, source: str) -> dict:
    with tempfile.TemporaryDirectory(prefix="three-schema-audit-") as directory:
        root = Path(directory)
        database = root / "three.sqlite"
        environment = dict(os.environ, THREE_DB=str(database), THREE_CHROME_DATA=str(root / "chrome"))
        subprocess.run([str(binary), "status", "--json"], env=environment,
                       check=True, capture_output=True, text=True)
        with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as db:
            db.execute("BEGIN")
            assert db.execute("PRAGMA integrity_check").fetchall() == [("ok",)]
            assert not db.execute("PRAGMA foreign_key_check").fetchall()
            tables = {}
            for name, sql in db.execute("SELECT name, sql FROM sqlite_schema WHERE type = 'table' ORDER BY name"):
                quoted = '"' + name.replace('"', '""') + '"'
                indexes = db.execute(f"PRAGMA index_list({quoted})").fetchall()
                definitions = {}
                for index in indexes:
                    index_name = index[1]
                    index_quoted = '"' + index_name.replace('"', '""') + '"'
                    definitions[index_name] = {
                        "sql": db.execute("SELECT sql FROM sqlite_schema WHERE type = 'index' AND name = ?",
                                          (index_name,)).fetchone()[0],
                        "columns": db.execute(f"PRAGMA index_xinfo({index_quoted})").fetchall(),
                    }
                tables[name] = {
                    "sql": sql,
                    "columns": db.execute(f"PRAGMA table_info({quoted})").fetchall(),
                    "foreignKeys": db.execute(f"PRAGMA foreign_key_list({quoted})").fetchall(),
                    "indexes": indexes,
                    "indexDefinitions": definitions,
                }
            return {
                "source": source,
                "binarySHA256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                "migrations": [row[0] for row in db.execute("SELECT identifier FROM grdb_migrations ORDER BY rowid")],
                "tables": tables,
                "viewsAndTriggers": db.execute("SELECT type, name, sql FROM sqlite_schema WHERE type IN ('view', 'trigger') ORDER BY type, name").fetchall(),
            }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--source", required=True, help="Commit used for the verified packaged build")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output exists; choose a new receipt path.")
    receipt = capture(args.binary.resolve(strict=True), args.source)
    with args.output.open("x") as output:
        output.write(json.dumps(receipt, indent=2) + "\n")
    print(f"PASS {len(receipt['tables'])} tables, {len(receipt['migrations'])} migrations; {args.output}")
