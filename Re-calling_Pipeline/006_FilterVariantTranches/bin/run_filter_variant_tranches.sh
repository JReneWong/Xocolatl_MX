#!/usr/bin/env bash
# Module 006_FilterVariantTranches — GATK FilterVariantTranches, turning
# 005_NVScoreVariants's CNN_2D scores into an actual PASS/FAIL callset.
# This is the second half of the CNN-scoring approach: 005 only
# annotated variants with a score, this module is what decides PASS/FAIL
# from it, using truth-set resources (HapMap, Mills) to calibrate a
# sensitivity-based threshold on that score — same underlying idea as
# VQSR's tranche filtering, just scoring by CNN instead of by a
# Gaussian-mixture model over hand-picked annotations.
#
# Team decision: this now sits in the main pipeline sequence, between
# 005_NVScoreVariants and 007_VariantFiltration — i.e. 007 onward
# (originally designed to replicate the organizer's hard-filter
# methodology on the raw callset) now runs on THIS module's output
# instead of 004_HaplotypeCaller's raw VCF directly. That's a deliberate
# change from how 007 was first built — flagged here and in 007's own
# script comments so the shift is traceable.
#
# --snp-tranche 99.95 / --indel-tranche 99.4: colleague-suggested
# starting values — the sensitivity threshold (fraction of truth-set
# sites retained) at which the score cutoff is drawn, separately for
# SNPs and indels. Not something GATK enforces or recommends by default;
# treat as a tunable starting point.
#
# --invalidate-previous-filters: harmless no-op for us specifically —
# 005's output has FILTER="." on every record (no prior filter to
# invalidate), this flag just guarantees FilterVariantTranches becomes
# the sole authority on FILTER regardless.
#
# Run from the project root:
#   bash Re-calling_Pipeline/006_FilterVariantTranches/bin/run_filter_variant_tranches.sh
#
# Override defaults with env vars, e.g.:
#   JAVA_MEM=8g bash Re-calling_Pipeline/006_FilterVariantTranches/bin/run_filter_variant_tranches.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/006_FilterVariantTranches"
INPUT_DIR="$PROJECT_ROOT/Re-calling_Pipeline/005_NVScoreVariants/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup
HAPMAP="$PROJECT_ROOT/references/hapmap/hapmap_3.3.hg38.vcf.gz"
MILLS="$PROJECT_ROOT/references/mills/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz"

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/${SAMPLE}.cnn_scored.vcf.gz"

SNP_TRANCHE="${SNP_TRANCHE:-99.95}"
INDEL_TRANCHE="${INDEL_TRANCHE:-99.4}"
JAVA_MEM="${JAVA_MEM:-4g}"

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

for f in "$INPUT_VCF" "$HAPMAP" "$HAPMAP.tbi" "$MILLS" "$MILLS.tbi"; do
    if [ ! -s "$f" ]; then
        echo "Error: required file $f not found." >&2
        exit 1
    fi
done

mkdir -p "$MODULE_DIR/results"

TMP_DIR="$MODULE_DIR/results/tmp"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT
mkdir -p "$TMP_DIR"

OUT_VCF="$MODULE_DIR/results/${SAMPLE}.tranche_filtered.vcf.gz"

if [ -s "$OUT_VCF" ] && [ -s "$OUT_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$OUT_VCF already present — skipping (FORCE=1 to redo)."
else
    FVT_CMD="set -euo pipefail; gatk --java-options '-Xmx$JAVA_MEM -Djava.io.tmpdir=$TMP_DIR' FilterVariantTranches \
        -V '$INPUT_VCF' \
        --resource '$HAPMAP' \
        --resource '$MILLS' \
        --info-key CNN_2D \
        --snp-tranche $SNP_TRANCHE \
        --indel-tranche $INDEL_TRANCHE \
        --invalidate-previous-filters \
        -O '$OUT_VCF'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "1" "$JAVA_MEM" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$FVT_CMD"
fi

echo
echo "Done. Tranche-filtered VCF: $OUT_VCF"
