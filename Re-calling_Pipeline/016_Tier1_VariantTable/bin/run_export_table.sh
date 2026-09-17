#!/usr/bin/env bash
# Module 016_Tier1_VariantTable — export the 014_Tier1_HighImpact VCF as
# a flat, tab-delimited review table (one row per variant, key VEP
# fields as columns) for human review outside a VCF viewer.
#
# Deliberately identical to VCF_pipeline/009-Tier1_VariantTable (same
# columns, same fix substituting vepExisting_variation for the
# nonexistent vepdbSNP field — see that module's own comments for the
# full reasoning) — this is the Re-calling front's counterpart step, now
# that both fronts follow the same methodology (team decision).
#
# Branches off 014_Tier1_HighImpact directly, NOT off 015_MVAGenePanel —
# same branching shape as VCF_pipeline's own 007 -> {008, 009}: this
# table covers the full Tier 1 (high-impact) set, not just the
# gene-panel-narrowed subset.
#
# Also adds %GT/%AD/%DP (genotype, allele depth, total depth), matching
# VCF_pipeline/009's own later addition — none of this pipeline's
# filtering steps touch FORMAT/sample columns, only INFO, so these have
# been in the VCF the whole time; just weren't in the exported table
# until asked for.
#
# Run from anywhere:
#   bash Re-calling_Pipeline/016_Tier1_VariantTable/bin/run_export_table.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/016_Tier1_VariantTable"
INPUT_DIR="$PROJECT_ROOT/Re-calling_Pipeline/014_Tier1_HighImpact/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/Tier1_HighImpact_vep_${SAMPLE}.PASS.vcf.gz"

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
    echo "Error: $INPUT_VCF not found. Run 014_Tier1_HighImpact first." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

OUT_TABLE="$MODULE_DIR/results/tier1_variants.txt"

if [ -s "$OUT_TABLE" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$OUT_TABLE already present — skipping (FORCE=1 to redo)."
else
    QUERY_CMD="set -euo pipefail; bcftools query -f '$QUERY_FMT' -H '$INPUT_VCF' > '$OUT_TABLE'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "1" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$QUERY_CMD"
fi

echo
echo "Done. Tier 1 variant table: $OUT_TABLE"
