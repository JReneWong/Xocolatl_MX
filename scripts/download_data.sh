#!/usr/bin/env bash
# Downloads the MVA hackathon dataset (~85GB) into ./data
# Run this from the project root, ideally on the SSD, with the huggingface_hub
# CLI available (pip install -U "huggingface_hub[cli]" or run inside the VM/container).
#
# Set HF_TOKEN in your environment first if the dataset requires auth:
#   export HF_TOKEN=hf_xxx

set -euo pipefail

DATA_DIR="${1:-./data}"
mkdir -p "$DATA_DIR"

echo "Downloading SageBio/mva-hackathon-2026-data into $DATA_DIR ..."

hf download SageBio/mva-hackathon-2026-data \
    --repo-type dataset \
    --local-dir "$DATA_DIR" \
    --exclude "README.md" ".gitattributes"

echo "Done. Contents:"
du -sh "$DATA_DIR"/*
