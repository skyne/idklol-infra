#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <ue-sha> [tfvars-file]"
  exit 1
fi

UE_SHA="$1"
TFVARS_FILE="${2:-prod.tfvars}"
SHORT_SHA="${UE_SHA:0:7}"
IMAGE_TAG="sha-${SHORT_SHA}"
IMAGE="ghcr.io/skyne/ue-server:${IMAGE_TAG}"

if [[ ! -f "$TFVARS_FILE" ]]; then
  echo "Error: tfvars file not found: $TFVARS_FILE"
  exit 1
fi

python3 - "$TFVARS_FILE" "$IMAGE" <<'PY'
import re
import sys
from pathlib import Path

file_path = Path(sys.argv[1])
image = sys.argv[2]
text = file_path.read_text()

var_name = "ue_server_image"
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

echo "Updated $TFVARS_FILE with UE image tag: $IMAGE_TAG"