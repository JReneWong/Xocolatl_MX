#!/usr/bin/env bash
# Module 012_SynonymousMutations — keep only variants whose worst
# consequence is potentially protein/splicing-altering (drops synonymous
# and everything functionally milder). Operates on
# 011_BCFTools_LowFreqVar's output, matching against the flattened
# vepConsequence field.
#
# Deliberately identical to VCF_pipeline/005-SynonymousMutations (same
# curated allow-list, same field) — this is the Re-calling front's
# counterpart step, now that both fronts follow the same methodology
# (team decision).
#
# Run from anywhere:
#   bash Re-calling_Pipeline/012_SynonymousMutations/bin/run_filter_synonymous.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=4 bash Re-calling_Pipeline/012_SynonymousMutations/bin/run_filter_synonymous.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/012_SynonymousMutations"
INPUT_DIR="$PROJECT_ROOT/Re-calling_Pipeline/011_BCFTools_LowFreqVar/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/RareVars_vep_${SAMPLE}.PASS.vcf.gz"

# Same curated allow-list as VCF_pipeline/005, matched against the
# flattened vepConsequence field.
KEEP_TERMS=(
    missense_variant
    frameshift_variant
    stop_gained
    stop_lost
    start_lost
    splice_acceptor_variant
    splice_donor_variant
    splice_region_variant
    inframe_insertion
    inframe_deletion
)
FILTER_EXPR=""
for term in "${KEEP_TERMS[@]}"; do
    [ -n "$FILTER_EXPR" ] && FILTER_EXPR+=" || "
    FILTER_EXPR+="INFO/vepConsequence ~ \"$term\""
done

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
    echo "Error: $INPUT_VCF not found. Run 011_BCFTools_LowFreqVar first." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

OUT_VCF="$MODULE_DIR/results/Functional_RareVars_vep_${SAMPLE}.PASS.vcf.gz"

if [ -s "$OUT_VCF" ] && [ -s "$OUT_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$OUT_VCF already present — skipping (FORCE=1 to redo)."
else
    FILTER_CMD="set -euo pipefail; bcftools view -i '$FILTER_EXPR' --threads $CPUS -Oz -o '$OUT_VCF' '$INPUT_VCF' \
        && bcftools index -t --threads $CPUS '$OUT_VCF'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$FILTER_CMD"
fi

echo
echo "Done. Functional rare-variant VCF: $OUT_VCF"
