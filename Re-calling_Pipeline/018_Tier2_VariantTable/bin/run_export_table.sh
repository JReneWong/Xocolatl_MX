#!/usr/bin/env bash
# Module 018_Tier2_VariantTable — export the 017_Tier2_ModerateImpact VCF
# as a flat, tab-delimited review table, mirroring
# 016_Tier1_VariantTable's column set (including %GT/%AD/%DP) exactly.
#
# Deliberately identical to VCF_pipeline/011-Tier2_VariantTable — this is
# the Re-calling front's counterpart step, now that both fronts follow
# the same methodology (team decision).
#
# Run from anywhere:
#   bash Re-calling_Pipeline/018_Tier2_VariantTable/bin/run_export_table.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/018_Tier2_VariantTable"
INPUT_DIR="$PROJECT_ROOT/Re-calling_Pipeline/017_Tier2_ModerateImpact/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/Tier2_ModerateImpact_vep_${SAMPLE}.PASS.vcf.gz"

QUERY_FMT='%CHROM\t%POS\t%REF\t%ALT\t%INFO/vepConsequence\t%INFO/vepIMPACT\t%INFO/vepSYMBOL\t%INFO/vepSIFT\t%INFO/vepPolyPhen\t%INFO/vepClinVar_CLNSIG\t%INFO/vepExisting_variation\t%INFO/vepgnomAD_AF[\t%GT\t%AD\t%DP]\n'

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
    echo "Error: $INPUT_VCF not found. Run 017_Tier2_ModerateImpact first." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

OUT_TABLE="$MODULE_DIR/results/tier2_variants.txt"

if [ -s "$OUT_TABLE" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$OUT_TABLE already present — skipping (FORCE=1 to redo)."
else
    QUERY_CMD="set -euo pipefail; bcftools query -f '$QUERY_FMT' -H '$INPUT_VCF' > '$OUT_TABLE'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "1" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$QUERY_CMD"
fi

echo
echo "Done. Tier 2 variant table: $OUT_TABLE"
