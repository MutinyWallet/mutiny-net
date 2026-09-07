#!/bin/bash
# Link this directory's nginx config into /etc/nginx, test it, and reload.
#
#   nginx/deploy.sh            link, test, reload
#   nginx/deploy.sh --check    report drift only; exit 1 if any
#
# Every vhost in this directory becomes a symlink in sites-available and
# sites-enabled, and nginx.conf is linked too. A differing copy that was
# not a link is backed up beside itself before it is replaced. After this
# runs once, a `git pull` changes the live config, and the reload here is
# what makes nginx read it. `nginx -t` runs before the reload, and nginx
# keeps the old config if the test fails.
set -euo pipefail
REPO_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1
drift=0

link() {
    local src=$1 dst=$2
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        return
    fi
    drift=1
    if [ "$CHECK" = 1 ]; then
        echo "DRIFT: $dst is not a link to $src"
        [ -f "$dst" ] && ! cmp -s "$src" "$dst" && diff -u "$dst" "$src" | head -20 || true
        return
    fi
    if [ -e "$dst" ] && [ ! -L "$dst" ] && ! cmp -s "$src" "$dst"; then
        cp -a "$dst" "$dst.pre-link-$(date -u +%Y%m%dT%H%M%SZ)"
        echo "backed up differing $dst"
    fi
    ln -sfn "$src" "$dst"
    echo "linked $dst -> $src"
}

link "$REPO_DIR/nginx.conf" /etc/nginx/nginx.conf
for f in "$REPO_DIR"/*mutinynet.com; do
    name=$(basename "$f")
    link "$f" "/etc/nginx/sites-available/$name"
    link "/etc/nginx/sites-available/$name" "/etc/nginx/sites-enabled/$name"
done

for e in /etc/nginx/sites-enabled/*; do
    n=$(basename "$e")
    [ -f "$REPO_DIR/$n" ] || echo "note: $e is enabled but not tracked in the repo"
done

if [ "$CHECK" = 1 ]; then
    [ "$drift" = 0 ] && echo "nginx config matches the repo"
    exit "$drift"
fi

nginx -t
systemctl reload nginx
echo "nginx reloaded"
