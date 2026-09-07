#!/bin/bash
# Look for use of the Spark services that were reachable from the Internet
# before the nginx deny rules and service_authz enforcement: MockService,
# SparkInternalService, SparkTokenInternalService, DKGService, GossipService.
#
# Run on the host from the repository directory. Needs read access to
# /var/log/nginx, docker, and .env (POSTGRES_PASSWORD).
#
#   ./audit-spark.sh [days]     default: 30
#
# The nginx access log is the only real signal: every gRPC call through the
# operator vhosts is logged as "POST /<pkg>.<Service>/<Method> HTTP/2.0".
# Container logs only reach back to the last recreate. The database counts
# are baselines for comparison over time, not indicators: refund transactions
# are re-signed on every transfer, and preimage requests without a share are
# normal for outgoing payments.
set -uo pipefail
DAYS=${1:-30}
PATTERN='/(mock\.MockService|spark_internal\.SparkInternalService|spark_token\.SparkTokenInternalService|dkg\.DKGService|gossip\.GossipService)/'

echo "== nginx access logs: calls to internal or mock services in the last $DAYS days =="
found=0
while IFS= read -r f; do
    case "$f" in
        *.gz) hits=$(zgrep -E "$PATTERN" "$f" | grep -v ' 404 ') ;;
        *)    hits=$(grep -E "$PATTERN" "$f" | grep -v ' 404 ') ;;
    esac
    if [ -n "$hits" ]; then
        found=1
        echo "-- $f"
        echo "$hits"
    fi
done < <(find /var/log/nginx -name 'access.log*' -mtime -"$DAYS" 2>/dev/null | sort)
[ "$found" = 0 ] && echo "none found (check that access_log is enabled for the spark vhosts)"

echo
echo "== operator container logs: MockService handlers =="
for c in spark spark2; do
    echo "-- $c"
    docker logs --since "${DAYS}d" "$c" 2>&1 | grep -E 'MockService' | tail -50
done

echo
echo "== operator databases =="
if [ -f .env ]; then
    set -a; . ./.env; set +a
fi
if [ -z "${POSTGRES_PASSWORD:-}" ]; then
    echo "POSTGRES_PASSWORD is not set; skipping database checks" >&2
    exit 0
fi
q() { docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres psql -U lightning-rgs -d "$1" -tA -c "$2"; }
for i in 0 1; do
    db="sparkoperator_$i"
    echo "-- $db: tree nodes updated in the last $DAYS days, by status"
    q "$db" "SELECT status, count(*) FROM tree_nodes WHERE update_time > now() - interval '$DAYS days' GROUP BY status ORDER BY 2 DESC;"
    echo "-- $db: tree nodes whose refund transaction changed after creation (normal on transfer; baseline only)"
    q "$db" "SELECT count(*) FROM tree_nodes WHERE raw_refund_tx IS NOT NULL AND update_time - create_time > interval '1 second' AND update_time > now() - interval '$DAYS days';"
    echo "-- $db: preimage requests without a share (normal for sends; baseline only)"
    q "$db" "SELECT count(*) FROM preimage_requests pr LEFT JOIN preimage_shares ps ON ps.preimage_request_preimage_shares = pr.id WHERE ps.id IS NULL AND pr.create_time > now() - interval '$DAYS days';"
    echo "-- $db: signing keyshares by status (baseline only)"
    q "$db" "SELECT status, count(*) FROM signing_keyshares GROUP BY status;"
done
