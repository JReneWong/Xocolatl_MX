#!/usr/bin/env bash
# Copies the software version manifest baked into hackathon.sif at build time
# out to docs/software_versions.txt, so it's tracked in git (code/config only,
# per .gitignore) even though the .sif itself is not.
#
# Run from the project root, inside the VM, after `apptainer build`:
#   bash scripts/record_versions.sh

set -euo pipefail

SIF="${1:-container/hackathon.sif}"
OUT="docs/software_versions.txt"

if [ ! -f "$SIF" ]; then
    echo "Error: $SIF not found. Build it first with:" >&2
    echo "  apptainer build container/hackathon.sif container/hackathon.def" >&2
    exit 1
fi

apptainer exec "$SIF" cat /opt/software_versions.txt > "$OUT"
echo "Wrote $OUT"
