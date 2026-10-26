#!/bin/bash
# Keep only the newest $KEEP blocks in mempool's `blocks` table.
#
# The backend saves every block it sees and never deletes one, but its hourly
# indexer runs several queries over the whole table. With 30s blocks the table
# passed 3.8M rows (7 GB) and each run read it four times at the disk's I/O
# limit. The backend only indexes the last INDEXING_BLOCKS_AMOUNT (11000)
# blocks, and refetches any older block from electrs when someone views it.
#
# Usage: prune-mempool-blocks.sh [batch size, default 5000]
set -euo pipefail

KEEP=${KEEP:-20000}
BATCH=${1:-5000}

sql() {
    docker exec -i mempool_db sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mariadb -u"$MYSQL_USER" -N mempool'
}

cutoff=$(echo "SELECT MAX(height) - $KEEP FROM blocks;" | sql)
total=0
while :; do
    n=$(echo "DELETE FROM blocks WHERE height < $cutoff ORDER BY height LIMIT $BATCH; SELECT ROW_COUNT();" | sql)
    total=$(( total + n ))
    (( n < BATCH )) && break
    sleep 1
done
echo "Deleted $total blocks below height $cutoff"
