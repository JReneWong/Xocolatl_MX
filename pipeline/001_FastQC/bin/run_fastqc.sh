#!/usr/bin/env bash
# Module 001_FastQC — QC every raw fastq, then roll the reports up with
# MultiQC. Run from inside the Lima VM shell, from anywhere:
#   bash pipeline/001_FastQC/bin/run_fastqc.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=6 MEM=20GiB bash pipeline/001_FastQC/bin/run_fastqc.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/pipeline/001_FastQC"
CONTAINER="$PROJECT_ROOT/container/hackathon.sif"
CPUS="${CPUS:-2}"
MEM="${MEM:-3GiB}"

source "$PROJECT_ROOT/common/manifest.sh"

if [ ! -f "$CONTAINER" ]; then
    echo "Error: $CONTAINER not found. Build it first (see README.md)." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "$MEM" -- \
    apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
    fastqc --threads "$CPUS" --outdir "$MODULE_DIR/results" "$MODULE_DIR"/data/*.fastq.gz

run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "$MEM" -- \
    apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
    multiqc "$MODULE_DIR/results" --outdir "$MODULE_DIR/results" --force

echo
echo "Done. Open $MODULE_DIR/results/multiqc_report.html for the rollup."
