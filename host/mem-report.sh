#!/bin/bash
# Summarise the samples from mutinynet-mem.timer. Memory figures are MiB, psi is
# a percentage of time stalled on memory, swapin is pages read back per second.
# Usage: mem-report.sh [journalctl --since value, default "7 days ago"]
set -euo pipefail

since=${1:-7 days ago}
samples=$(journalctl -u mutinynet-mem.service --since "$since" -o cat --no-pager | grep '^used=' || true)

if [[ -z $samples ]]; then
    echo "No samples since $since."
    exit 1
fi

# Print min/avg/p95/max of the numbers on stdin, one per line.
stats() {
    sort -n | awk -v key="$1" '
        { v[NR] = $1; sum += $1 }
        END {
            if (NR == 0) { printf "%-7s no data\n", key; exit }
            p95 = int(NR * 0.95); if (p95 < 1) p95 = 1
            printf "%-7s min %8.2f  avg %8.2f  p95 %8.2f  max %8.2f\n", key, v[1], sum / NR, v[p95], v[NR]
        }'
}

# Print the value of host field $1 from each sample that has it.
field() {
    grep -o "^.*|" <<<"$samples" | grep -o "\b$1=[0-9.]*" | cut -d= -f2 || true
}

echo "$(wc -l <<<"$samples") samples since $since"
echo
for key in used swap need avail psi; do
    field "$key" | stats "$key"
done
# swapin is a running counter; samples are five minutes apart. A drop means
# the host rebooted, so skip that interval.
field swapin | awk 'NR > 1 && $1 >= prev { print ($1 - prev) / 300 } { prev = $1 }' | stats swapin

echo
echo "Peak per container (anon + swap):"
sed 's/^.*| *//' <<<"$samples" | tr ' ' '\n' | grep '=' |
    awk -F= '$2 > peak[$1] { peak[$1] = $2 } END { for (c in peak) printf "  %-20s %6d\n", c, peak[c] }' |
    sort -k2 -rn
