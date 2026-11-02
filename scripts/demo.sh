#!/usr/bin/env bash
# Seeds build/demo.sqlite with a realistic day: one finished block, a break, one running block.
set -euo pipefail
cd "$(dirname "$0")/.."
export THREE_DB="${THREE_DB:-${TMPDIR:-/tmp}/three-demo.sqlite}"
rm -f "$THREE_DB" "$THREE_DB-wal" "$THREE_DB-shm"
T=build/Three.app/Contents/Helpers/three
$T plan "Ship onboarding flow:Coding:90" "Write the Q4 PRD:Writing:1h" "Inbox and invoices:Admin:30m" >/dev/null
$T add "Read Dieter Rams essay" --cat Learning --block 45 >/dev/null
$T start 1 --min 50 >/dev/null
$T done 1 >/dev/null
sqlite3 "$THREE_DB" "UPDATE session SET startedAt=datetime('now','-2 hours','-30 minutes'), endedAt=datetime('now','-1 hours','-40 minutes'), focusRating=3;
INSERT INTO session VALUES('b1',NULL,'break',300,datetime('now','-1 hours','-38 minutes'),NULL,0,datetime('now','-1 hours','-33 minutes'),'completed',NULL,NULL,NULL,datetime('now'));"
$T tomorrow 4 >/dev/null
$T start 2 --min 45 >/dev/null
sqlite3 "$THREE_DB" "UPDATE session SET startedAt=datetime('now','-18 minutes') WHERE endedAt IS NULL;"
$T step add 2 "Outline the problem" >/dev/null
$T step add 2 "Draft success metrics" >/dev/null
$T step add 2 "Send to Maya for review" >/dev/null
$T step done 2 1 >/dev/null
$T capture "Renew passport #admin 30m" >/dev/null
$T capture "Try the new SwiftUI inspector API #learning 45m" >/dev/null
$T capture "Book dentist #admin 15m" >/dev/null
$T capture "Review onboarding PR #coding 30m wed" >/dev/null
$T capture "Weekly planning #meetingprep 45m fri" >/dev/null
echo "$THREE_DB"
