#!/usr/bin/env bash
# Module 009-Tier1_VariantTable — export the 007-Tier1_HighImpact VCF as a
# flat, tab-delimited review table (one row per variant, key VEP fields
# as columns) for human review outside a VCF viewer.
#
# Adapted from bin/ExportTable.sh (the colleague's reference script, from
# a different project) to this project's actual paths and pipeline/
# manifest conventions. The original script is left as-is for reference.
#
# --- Fix vs. the reference script ---
# %INFO/vepdbSNP doesn't exist in our data — we never added a dbSNP
# custom track (see 002-VEPAnnotation's header note), so there's no
# "vepdbSNP" field to split out. rsIDs are still available via VEP's own
# --cache annotation, flattened in module 003 as vepExisting_variation
# (same fix already applied in 003 and 005). Substituted here.
#
# Also adds %GT/%AD/%DP (genotype, allele depth, total depth) beyond the
# colleague's original column set — none of this pipeline's filtering
# steps touch FORMAT/sample columns, only INFO, so these have been in the
# VCF the whole time; just weren't in the exported table until asked for.
#
# Run from anywhere:
#   bash VCF_pipeline/009-Tier1_VariantTable/bin/run_export_table.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/VCF_pipeline/009-Tier1_VariantTable"
INPUT_DIR="$PROJECT_ROOT/VCF_pipeline/007-Tier1_HighImpact/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

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
    echo "Error: $INPUT_VCF not found. Run 007-Tier1_HighImpact first." >&2
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
