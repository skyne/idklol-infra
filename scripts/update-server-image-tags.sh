#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <server-sha> [tfvars-file]"
  exit 1
fi

SERVER_SHA="$1"
TFVARS_FILE="${2:-prod.public.tfvars}"
SHORT_SHA="${SERVER_SHA:0:7}"
IMAGE_TAG="sha-${SHORT_SHA}"

if [[ ! -f "$TFVARS_FILE" ]]; then
  echo "Error: tfvars file not found: $TFVARS_FILE"
  exit 1
fi

python3 - "$TFVARS_FILE" "$IMAGE_TAG" <<'PY'
import re
import sys
from pathlib import Path

file_path = Path(sys.argv[1])
tag = sys.argv[2]
text = file_path.read_text()

mapping = {
    "chatserver_image": f"ghcr.io/skyne/idklol-server-chatserver:{tag}",
    "characters_grpc_image": f"ghcr.io/skyne/idklol-server-characters-grpc:{tag}",
    "characters_admin_image": f"ghcr.io/skyne/idklol-server-characters-admin:{tag}",
    "characters_server_image": f"ghcr.io/skyne/idklol-server-characters-server:{tag}",
    "npc_metadata_service_image": f"ghcr.io/skyne/idklol-server-npc-metadata-service:{tag}",
    "npc_interactions_bridge_image": f"ghcr.io/skyne/idklol-server-npc-interactions-bridge:{tag}",
    "webadmin_image": f"ghcr.io/skyne/idklol-server-webadmin:{tag}",
}

for var_name, image in mapping.items():
    pattern = re.compile(rf"(?m)^\s*{re.escape(var_name)}\s*=\s*\"[^\"]*\"\s*$")
    replacement = f'{var_name} = "{image}"'
    if pattern.search(text):
        text = pattern.sub(replacement, text, count=1)
    else:
        if not text.endswith("\n"):
            text += "\n"
        text += replacement + "\n"

file_path.write_text(text)
PY

echo "Updated $TFVARS_FILE with server image tag: $IMAGE_TAG"