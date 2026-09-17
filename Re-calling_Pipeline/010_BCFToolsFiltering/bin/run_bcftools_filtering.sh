#!/usr/bin/env bash
# Module 010_BCFToolsFiltering — pull the worst-consequence-per-variant VEP
# annotations out of the CSQ string into flat, top-level INFO fields (via
# bcftools +split-vep), so they're directly queryable/filterable downstream.
#
# Deliberately identical to VCF_pipeline/003-BCFToolsFiltering (same
# columns, select mode, prefix) — this is the Re-calling front's
# counterpart step, now that both fronts follow the same methodology
# (team decision). Field names (Gene, Existing_variation, etc.) carry
# over correctly since 009_VEPAnnotation mirrors VCF_pipeline/002's exact
# VEP command/custom tracks that produced them there.
#
# Run from anywhere:
#   bash Re-calling_Pipeline/010_BCFToolsFiltering/bin/run_bcftools_filtering.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=4 bash Re-calling_Pipeline/010_BCFToolsFiltering/bin/run_bcftools_filtering.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/010_BCFToolsFiltering"
INPUT_DIR="$PROJECT_ROOT/Re-calling_Pipeline/009_VEPAnnotation/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/vep_${SAMPLE}.PASS.vcf.gz"

SPLIT_VEP_COLUMNS="Consequence,IMPACT,SYMBOL,Gene,SIFT,PolyPhen,ClinVar_CLNSIG,Existing_variation,gnomAD_AF"
SPLIT_VEP_SELECT="worst"
SPLIT_VEP_PREFIX="vep"

CPUS="${CPUS:-1}"

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

if [ ! -s "$INPUT_VCF" ]; then
    echo "Error: $INPUT_VCF not found. Run 009_VEPAnnotation first." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

OUT_VCF="$MODULE_DIR/results/SplitVEP_vep_${SAMPLE}.PASS.vcf.gz"

if [ -s "$OUT_VCF" ] && [ -s "$OUT_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$OUT_VCF already present — skipping (FORCE=1 to redo)."
else
    # +split-vep does not support --threads (same as VCF_pipeline/003 —
    # confirmed there via its own usage output) — only indexing uses $CPUS.
    SPLIT_VEP_CMD="set -euo pipefail; bcftools +split-vep \
        -c '$SPLIT_VEP_COLUMNS' \
        -s '$SPLIT_VEP_SELECT' \
        -p '$SPLIT_VEP_PREFIX' \
        -Oz -o '$OUT_VCF' \
        '$INPUT_VCF' \
        && bcftools index -t --threads $CPUS '$OUT_VCF'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$SPLIT_VEP_CMD"
fi

echo
echo "Done. Split-VEP VCF: $OUT_VCF"
