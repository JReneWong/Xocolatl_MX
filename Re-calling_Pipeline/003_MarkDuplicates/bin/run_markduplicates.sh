#!/usr/bin/env bash
# Module 003_MarkDuplicates — Picard MarkDuplicates on 002_Alignment's
# merged, sorted, sample-level BAM (all 4 lanes, one library). Marks PCR
# and optical duplicates (does not remove reads) and writes a duplication
# metrics report, then re-indexes and flagstats the result.
#
# Run from the project root:
#   bash Re-calling_Pipeline/003_MarkDuplicates/bin/run_markduplicates.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=6 JAVA_MEM=24g bash Re-calling_Pipeline/003_MarkDuplicates/bin/run_markduplicates.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).
#
# Left for a later module: BQSR, then HaplotypeCaller.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/003_MarkDuplicates"
INPUT_DIR="$PROJECT_ROOT/Re-calling_Pipeline/002_Alignment/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_BAM="$INPUT_DIR/${SAMPLE}.sorted.bam"

CPUS="${CPUS:-10}"
JAVA_MEM="${JAVA_MEM:-16g}"   # Picard MarkDuplicates heap; not multi-threaded, CPUS only affects samtools/index/flagstat steps below

# HGWCNDSX7's "DSX" code is a NovaSeq 6000 S4-kit flow cell — patterned,
# so optical duplicates cluster much closer together than on older
# unpatterned (HiSeq-style) flow cells. Broad's guidance for patterned
# flow cells is 2500px instead of Picard's 100px default; too small a
# value on a patterned cell undercounts optical duplicates.
OPTICAL_DUP_PIXEL_DIST="${OPTICAL_DUP_PIXEL_DIST:-2500}"

source "$PROJECT_ROOT/common/manifest.sh"
CONTAINER="$(resolve_container "$PROJECT_ROOT")"

# data/ is just a documentation stub here (see data/README.txt) — point
# manifests at the real input so provenance is accurate, not at the empty
# placeholder.
export MANIFEST_INPUT_DIR="$INPUT_DIR"

if [ ! -f "$CONTAINER" ]; then
    echo "Error: $CONTAINER not found. Build it first (see README.md)." >&2
    exit 1
fi

if [ ! -s "$INPUT_BAM" ]; then
    echo "Error: $INPUT_BAM not found. Run 002_Alignment first." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

# Picard spills unsorted intermediate records to disk once it exceeds its
# in-RAM record cap, and for ~60GB/1B-read input that spill can run to
# tens of GB — put it on the SSD (this module's own results/, plenty of
# free space there) rather than the host's root filesystem, which is far
# smaller and not what we want to fill up.
TMP_DIR="$MODULE_DIR/results/tmp"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

OUT_BAM="$MODULE_DIR/results/${SAMPLE}.dedup.bam"
METRICS="$MODULE_DIR/results/${SAMPLE}.dedup_metrics.txt"

if [ -s "$OUT_BAM" ] && [ -s "$OUT_BAM.bai" ] && [ -s "$METRICS" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$OUT_BAM already present — skipping (FORCE=1 to redo)."
else
    mkdir -p "$TMP_DIR"
    MARKDUP_CMD="set -euo pipefail; picard -Xmx$JAVA_MEM -Djava.io.tmpdir='$TMP_DIR' MarkDuplicates \
        I='$INPUT_BAM' \
        O='$OUT_BAM' \
        M='$METRICS' \
        TMP_DIR='$TMP_DIR' \
        OPTICAL_DUPLICATE_PIXEL_DISTANCE=$OPTICAL_DUP_PIXEL_DIST \
        VALIDATION_STRINGENCY=LENIENT \
        && samtools index -@ $CPUS '$OUT_BAM'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "$JAVA_MEM" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$MARKDUP_CMD"
fi

FLAGSTAT="$MODULE_DIR/results/${SAMPLE}.dedup.flagstat.txt"
if [ -s "$FLAGSTAT" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$FLAGSTAT already present — skipping (FORCE=1 to redo)."
else
    run_and_log "$MODULE_DIR" "$CONTAINER" "1" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "samtools flagstat '$OUT_BAM' > '$FLAGSTAT'"
fi

echo
echo "Done. Deduped BAM: $OUT_BAM"
echo "Duplication metrics: $METRICS"
echo "Flagstat: $FLAGSTAT"
