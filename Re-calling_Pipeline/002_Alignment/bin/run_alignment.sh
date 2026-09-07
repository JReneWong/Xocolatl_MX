#!/usr/bin/env bash
# Module 002_Alignment — bwa-mem align each lane's raw paired fastqs
# (module 001_FastQC's input, not its output — QC doesn't transform reads,
# and there's no trimming module: 001's MultiQC report showed negligible
# adapter content, and the container ships no trimmer anyway) against
# GRCh38 using the Broad resource bundle's prebuilt 64-bit bwa index,
# coordinate-sort each lane, then merge all lanes into one sample-level
# BAM and index it.
#
# Out of scope here, left for a later module: duplicate marking and BQSR.
# This module's output is a merged, sorted, but NOT deduped BAM.
#
# Run from the project root:
#   bash Re-calling_Pipeline/002_Alignment/bin/run_alignment.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=6 SORT_MEM=2G bash Re-calling_Pipeline/002_Alignment/bin/run_alignment.sh
#
# Safe to re-run: each lane and the final merge are skipped if their
# expected output already exists (set FORCE=1 to redo).
#
# RAM usage: this host has far more RAM than the alignment needs from disk
# I/O alone, so two things lean on that deliberately:
#   1. The ~5.6GB bwa index (.bwt/.pac/.sa/.amb/.ann/.alt) is copied once
#      into /dev/shm (tmpfs) before aligning, so bwa's random FM-index
#      lookups hit RAM instead of the external drive for all 4 lanes.
#      Removed again on exit (trap) — nothing persists once unplugged.
#   2. samtools sort gets a much larger per-thread buffer (SORT_MEM) than
#      its default, so it sorts each lane in one RAM pass instead of many
#      spill-merge passes against disk.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/002_Alignment"
INPUT_DIR="$PROJECT_ROOT/InitialData"   # see data/README.txt — not a symlink on this exFAT+Linux setup
REF_DIR="$PROJECT_ROOT/references/genome"
REF_PREFIX_NAME="Homo_sapiens_assembly38.fasta.64"

SAMPLE="WGS_EX2312012_HGWCNDSX7"
FLOWCELL="HGWCNDSX7"
LANES=(L001 L002 L003 L004)

CPUS="${CPUS:-10}"
SORT_MEM="${SORT_MEM:-3G}"   # per samtools sort thread; total up to CPUS * SORT_MEM

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

mkdir -p "$MODULE_DIR/results"

# --- Stage the bwa index into RAM (tmpfs) so all 4 lanes read it from
# there instead of the external drive; cleaned up on exit no matter how
# the script ends. ---
RAMDISK_REF="/dev/shm/hackathon_002_alignment_ref"
cleanup() { rm -rf "$RAMDISK_REF"; }
trap cleanup EXIT

if [ ! -f "$RAMDISK_REF/${REF_PREFIX_NAME}.bwt" ]; then
    echo "Staging bwa index into RAM ($RAMDISK_REF)..."
    mkdir -p "$RAMDISK_REF"
    cp "$REF_DIR/${REF_PREFIX_NAME}".{alt,amb,ann,bwt,pac,sa} "$RAMDISK_REF/"
fi
REF_PREFIX="$RAMDISK_REF/${REF_PREFIX_NAME}"

LANE_BAMS=()
for LANE in "${LANES[@]}"; do
    R1="$INPUT_DIR/${SAMPLE}_S16_${LANE}_R1_001.fastq.gz"
    R2="$INPUT_DIR/${SAMPLE}_S16_${LANE}_R2_001.fastq.gz"
    OUT_BAM="$MODULE_DIR/results/${SAMPLE}_${LANE}.sorted.bam"
    LANE_BAMS+=("$OUT_BAM")

    if [ -s "$OUT_BAM" ] && [ -s "$OUT_BAM.bai" ] && [ "${FORCE:-0}" != "1" ]; then
        echo "$OUT_BAM already present — skipping (FORCE=1 to redo)."
        continue
    fi

    RG="@RG\tID:${FLOWCELL}.${LANE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA\tPU:${FLOWCELL}.${LANE}"
    PIPELINE_CMD="set -euo pipefail; bwa mem -t $CPUS -R '$RG' '$REF_PREFIX' '$R1' '$R2' \
        | samtools sort -@ $CPUS -m $SORT_MEM -o '$OUT_BAM' - \
        && samtools index '$OUT_BAM'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "${SORT_MEM}-per-thread" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" --bind /dev/shm:/dev/shm "$CONTAINER" \
        bash -c "$PIPELINE_CMD"
done

MERGED_BAM="$MODULE_DIR/results/${SAMPLE}.sorted.bam"
if [ -s "$MERGED_BAM" ] && [ -s "$MERGED_BAM.bai" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$MERGED_BAM already present — skipping (FORCE=1 to redo)."
else
    MERGE_CMD="set -euo pipefail; samtools merge -@ $CPUS -f '$MERGED_BAM' $(printf "'%s' " "${LANE_BAMS[@]}") \
        && samtools index '$MERGED_BAM'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$MERGE_CMD"
fi

FLAGSTAT="$MODULE_DIR/results/${SAMPLE}.flagstat.txt"
if [ -s "$FLAGSTAT" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$FLAGSTAT already present — skipping (FORCE=1 to redo)."
else
    run_and_log "$MODULE_DIR" "$CONTAINER" "1" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "samtools flagstat '$MERGED_BAM' > '$FLAGSTAT'"
fi

echo
echo "Done. Merged BAM: $MERGED_BAM"
echo "Flagstat: $FLAGSTAT"
