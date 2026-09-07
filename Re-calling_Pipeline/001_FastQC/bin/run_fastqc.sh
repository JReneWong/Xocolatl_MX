#!/usr/bin/env bash
# Module 001_FastQC — QC every raw fastq, then roll the reports up with
# MultiQC. Run from inside the Lima VM shell, from anywhere:
#   bash Re-calling_Pipeline/001_FastQC/bin/run_fastqc.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=6 MEM=20GiB bash Re-calling_Pipeline/001_FastQC/bin/run_fastqc.sh
#
# Safe to re-run: each step is skipped if its expected output already
# exists (set FORCE=1 to redo a step anyway). This matters because FastQC
# alone takes hours on this data — a re-run after an interrupted session
# shouldn't have to repeat it just to pick up MultiQC.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/001_FastQC"
CPUS="${CPUS:-2}"
MEM="${MEM:-3GiB}"

source "$PROJECT_ROOT/common/manifest.sh"
CONTAINER="$(resolve_container "$PROJECT_ROOT")"

if [ ! -f "$CONTAINER" ]; then
    echo "Error: $CONTAINER not found. Build it first (see README.md)." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

fastqc_done=1
for f in "$MODULE_DIR"/data/*.fastq.gz; do
    base="$(basename "$f" .fastq.gz)"
    if [ ! -s "$MODULE_DIR/results/${base}_fastqc.html" ] || [ ! -s "$MODULE_DIR/results/${base}_fastqc.zip" ]; then
        fastqc_done=0
        break
    fi
done

if [ "$fastqc_done" = "1" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "FastQC outputs already present for all inputs — skipping (FORCE=1 to redo)."
else
    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "$MEM" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        fastqc --threads "$CPUS" --outdir "$MODULE_DIR/results" "$MODULE_DIR"/data/*.fastq.gz
fi

if [ -s "$MODULE_DIR/results/multiqc_report.html" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "multiqc_report.html already present — skipping (FORCE=1 to redo)."
else
    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "$MEM" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        multiqc "$MODULE_DIR/results" --outdir "$MODULE_DIR/results" --force
fi

echo
echo "Done. Open $MODULE_DIR/results/multiqc_report.html for the rollup."
