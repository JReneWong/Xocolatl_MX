#!/usr/bin/env bash
# Module 003-BCFToolsFiltering — pull the worst-consequence-per-variant VEP
# annotations out of the CSQ string into flat, top-level INFO fields (via
# bcftools +split-vep), so they're directly queryable/filterable downstream
# (e.g. bcftools view -i 'vep_gnomAD_AF<0.01') without re-parsing CSQ.
#
# Adapted from bin/BCFTools_Filtering.sh (the team's reference one-liner)
# to this project's actual resources and to the pipeline/manifest
# conventions used by the rest of VCF_pipeline. The original script is
# left untouched for reference.
#
# Run from anywhere:
#   bash VCF_pipeline/003-BCFToolsFiltering/bin/run_bcftools_filtering.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=4 bash VCF_pipeline/003-BCFToolsFiltering/bin/run_bcftools_filtering.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).
#
# --- Field-name fix vs. the reference script (verified against our actual
# CSQ header before writing this, not executed) ---
# The reference script requests: Consequence,IMPACT,SYMBOL,gene,SIFT,
# PolyPhen,ClinVar_CLNSIG,dbSNP,gnomAD_AF — two of those don't exist in our
# 002-VEPAnnotation output's CSQ format:
#   - "gene" -> our CSQ field is "Gene" (capitalized) — bcftools +split-vep
#     -c matches field names exactly, so the lowercase form would pull
#     nothing.
#   - "dbSNP" -> we never added a dbSNP custom track (see
#     002-VEPAnnotation/bin/run_vep_annotation.sh's header note — dropped
#     as skippable, same chr-prefix mismatch as the genome). rsIDs are
#     still present, though: VEP's --cache annotation populates
#     "Existing_variation" from the Ensembl variation database (which
#     includes dbSNP) independently of any custom dbSNP track, so that's
#     used here instead to get the same information.
# Confirmed via `bcftools view -h .../vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
# | grep CSQ` that Gene and Existing_variation are the real field names.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/VCF_pipeline/003-BCFToolsFiltering"
INPUT_DIR="$PROJECT_ROOT/VCF_pipeline/002-VEPAnnotation/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/vep_${SAMPLE}.PASS.vcf.gz"

# -c: fields pulled out of CSQ into new top-level INFO tags (prefixed vep_,
#     see -p below); Gene/Existing_variation corrected per the note above.
# -s worst: one row of annotations per variant, taken from its
#     worst-consequence transcript (transcript-selection mode "worst";
#     consequence-severity filter defaults to "any").
# -p vep: prefix every extracted field with "vep_" to avoid any future
#     name collision with existing INFO tags.
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
    echo "Error: $INPUT_VCF not found. Run 002-VEPAnnotation first." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

OUT_VCF="$MODULE_DIR/results/SplitVEP_vep_${SAMPLE}.PASS.vcf.gz"

if [ -s "$OUT_VCF" ] && [ -s "$OUT_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$OUT_VCF already present — skipping (FORCE=1 to redo)."
else
    # Note: +split-vep has its own option set, separate from bcftools'
    # core subcommands, and does not support --threads (confirmed via
    # `bcftools +split-vep` usage output when the first attempt at this
    # rejected it with "unrecognized option '--threads'") — only the
    # indexing step below actually uses $CPUS.
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
