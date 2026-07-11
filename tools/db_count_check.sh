#!/bin/bash
# db_count_check.sh: field helper for file 07 T3 (partition and heal).
# Prints per-table row counts and duplicate primary keys for one or more
# node databases; after heal, counts must match across nodes and every
# duplicate count must be zero.
#
# Usage: tools/db_count_check.sh nodeA.db [nodeB.db ...]

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <db file> [<db file> ...]"
    exit 1
fi

TABLES="messages:msg_id personnel:personnel_id announcements:id gs_messages:id checkins:id"

printf '%-28s' "table"
for db in "$@"; do printf '%-22s' "$(basename "$db")"; done
echo ""

for entry in $TABLES; do
    table="${entry%%:*}"
    pk="${entry##*:}"
    printf '%-28s' "$table"
    for db in "$@"; do
        rows=$(sqlite3 "$db" "SELECT COUNT(*) FROM $table" 2>/dev/null || echo "-")
        dups="-"
        if [[ "$rows" != "-" ]]; then
            distinct=$(sqlite3 "$db" "SELECT COUNT(DISTINCT $pk) FROM $table")
            dups=$((rows - distinct))
        fi
        printf '%-22s' "${rows} (dup:${dups})"
    done
    echo ""
done
