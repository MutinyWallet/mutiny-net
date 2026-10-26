#!/bin/bash
# Summarise the samples from mutinynet-mem.timer. All figures are MiB.
# Usage: mem-report.sh [journalctl --since value, default "7 days ago"]
set -euo pipefail

since=${1:-7 days ago}
samples=$(journalctl -u mutinynet-mem.service --since "$since" -o cat --no-pager | grep '^used=' || true)

if [[ -z $samples ]]; then
    echo "No samples since $since."
    exit 1
fi

echo "$(wc -l <<<"$samples") samples since $since"
echo
for key in used swap need avail; do
    grep -o "^.*|" <<<"$samples" | grep -o "\b$key=[0-9]*" | cut -d= -f2 | sort -n |
        awk -v key="$key" '
        { v[NR] = $1; sum += $1 }
        END {
            p95 = int(NR * 0.95); if (p95 < 1) p95 = 1
            printf "%-6s min %6d  avg %6d  p95 %6d  max %6d\n", key, v[1], sum / NR, v[p95], v[NR]
        }'
done

echo
echo "Peak per container (anon + swap):"
sed 's/^.*| *//' <<<"$samples" | tr ' ' '\n' | grep '=' |
    awk -F= '$2 > peak[$1] { peak[$1] = $2 } END { for (c in peak) printf "  %-20s %6d\n", c, peak[c] }' |
    sort -k2 -rn
