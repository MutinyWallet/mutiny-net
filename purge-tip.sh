#!/bin/bash
set -euo pipefail

CF_TOKEN="${CF_TOKEN:?CF_TOKEN is required}"
ZONE_ID="44d75402113591888d6130c09a2c005e"

curl -s -X POST \
  -H "Authorization: Bearer ${CF_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/purge_cache" \
  -d '{"files":["https://mutinynet.com/api/blocks/tip/height"]}' > /dev/null
