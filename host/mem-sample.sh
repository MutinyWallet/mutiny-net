#!/bin/bash
# Print one memory sample to stdout (the journal, via mutinynet-mem.service).
# Host figures first, then each container's anon + swapped memory, all in MiB:
#   used=6400 swap=3500 need=9900 avail=9200 psi=0.00 swapin=123 | bitcoind-miner=1650 ...
# need = used + swap: roughly the RAM the box would need to stop swapping.
# Swap that is never read back costs nothing, so need overstates the RAM in
# use. psi is the share of the last 5 minutes some task stalled waiting for
# memory (/proc/pressure/memory "some avg300"); swapin is the cumulative count
# of pages read back from swap. Those two show whether the box is short.
set -euo pipefail

read -r total avail swap_total swap_free < <(awk '
    /^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2}
    /^SwapTotal:/ {st=$2} /^SwapFree:/ {sf=$2}
    END {print t, a, st, sf}' /proc/meminfo)
used=$(( (total - avail) / 1024 ))
swap=$(( (swap_total - swap_free) / 1024 ))
psi=$(awk '$1 == "some" {sub("avg300=", "", $4); print $4}' /proc/pressure/memory)
swapin=$(awk '$1 == "pswpin" {print $2}' /proc/vmstat)
line="used=$used swap=$swap need=$(( used + swap )) avail=$(( avail / 1024 )) psi=$psi swapin=$swapin |"

while read -r id name; do
    cg=/sys/fs/cgroup/system.slice/docker-$id.scope
    [[ -d $cg ]] || continue
    anon=$(awk '$1 == "anon" {print $2}' "$cg/memory.stat")
    cswap=$(cat "$cg/memory.swap.current" 2>/dev/null || echo 0)
    line+=" $name=$(( (anon + cswap) / 1048576 ))"
done < <(docker ps --no-trunc --format '{{.ID}} {{.Names}}')

echo "$line"
