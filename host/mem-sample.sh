#!/bin/bash
# Print one memory sample to stdout (the journal, via mutinynet-mem.service).
# Host figures first, then each container's anon + swapped memory, all in MiB:
#   used=6400 swap=3500 need=9900 avail=9200 | bitcoind-miner=1650 ...
# need = used + swap: roughly the RAM the box would need to stop swapping.
set -euo pipefail

read -r total avail swap_total swap_free < <(awk '
    /^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2}
    /^SwapTotal:/ {st=$2} /^SwapFree:/ {sf=$2}
    END {print t, a, st, sf}' /proc/meminfo)
used=$(( (total - avail) / 1024 ))
swap=$(( (swap_total - swap_free) / 1024 ))
line="used=$used swap=$swap need=$(( used + swap )) avail=$(( avail / 1024 )) |"

while read -r id name; do
    cg=/sys/fs/cgroup/system.slice/docker-$id.scope
    [[ -d $cg ]] || continue
    anon=$(awk '$1 == "anon" {print $2}' "$cg/memory.stat")
    cswap=$(cat "$cg/memory.swap.current" 2>/dev/null || echo 0)
    line+=" $name=$(( (anon + cswap) / 1048576 ))"
done < <(docker ps --no-trunc --format '{{.ID}} {{.Names}}')

echo "$line"
