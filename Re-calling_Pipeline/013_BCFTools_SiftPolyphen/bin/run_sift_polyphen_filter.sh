#!/usr/bin/env bash
# Module 013_BCFTools_SiftPolyphen — drop variants predicted tolerated by
# SIFT or benign by PolyPhen, keeping everything else: variants both
# tools flag as damaging, variants where the two disagree, and variants
# with no SIFT/PolyPhen call at all (these predictors only ever score
# missense_variant). Operates on 012_SynonymousMutations's output.
#
# Deliberately identical to VCF_pipeline/006-BCFTools_SiftPolyphen (same
# exclusion expression) — this is the Re-calling front's counterpart
# step, now that both fronts follow the same methodology (team decision).
# This is also the final step in both fronts' shared sequence — its
# output is what 013_ComparisonReport treats as each front's "final"
# callset for that last comparison panel.
#
# Run from anywhere:
#   bash Re-calling_Pipeline/013_BCFTools_SiftPolyphen/bin/run_sift_polyphen_filter.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=4 bash Re-calling_Pipeline/013_BCFTools_SiftPolyphen/bin/run_sift_polyphen_filter.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/013_BCFTools_SiftPolyphen"
INPUT_DIR="$PROJECT_ROOT/Re-calling_Pipeline/012_SynonymousMutations/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/Functional_RareVars_vep_${SAMPLE}.PASS.vcf.gz"

FILTER_EXPR='INFO/vepSIFT~"tolerated" || INFO/vepPolyPhen="benign"'

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
    echo "Error: $INPUT_VCF not found. Run 012_SynonymousMutations first." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

OUT_VCF="$MODULE_DIR/results/SiftPolyphenFiltered_vep_${SAMPLE}.PASS.vcf.gz"

if [ -s "$OUT_VCF" ] && [ -s "$OUT_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$OUT_VCF already present — skipping (FORCE=1 to redo)."
else
    FILTER_CMD="set -euo pipefail; bcftools view -e '$FILTER_EXPR' --threads $CPUS -Oz -o '$OUT_VCF' '$INPUT_VCF' \
        && bcftools index -t --threads $CPUS '$OUT_VCF'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$FILTER_CMD"
fi

echo
echo "Done. SIFT/PolyPhen-filtered VCF: $OUT_VCF"
