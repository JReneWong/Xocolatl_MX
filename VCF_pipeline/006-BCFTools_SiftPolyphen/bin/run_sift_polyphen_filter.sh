#!/usr/bin/env bash
# Module 006-BCFTools_SiftPolyphen — drop variants predicted tolerated by
# SIFT or benign by PolyPhen (colleague-suggested filter), keeping
# everything else: variants both tools flag as damaging, variants where
# the two disagree, and variants with no SIFT/PolyPhen call at all
# (frameshift/stop/splice/inframe-indel — these predictors only ever
# score missense_variant, so they're untouched by this filter either way).
# Operates on 005-SynonymousMutations's output.
#
# Adapted from bin/SiftPolyphenFiltering.sh (the colleague's reference
# one-liner, itself from a different project — its filename
# "vep103_joint_germline_recalibrated..." doesn't refer to anything in
# this pipeline) to this project's actual paths and pipeline/manifest
# conventions. The original one-liner is left as-is for reference.
#
# --- Verified against our actual data before writing this (not executed) ---
# Field format compatibility confirmed directly, no corrections needed
# this time (unlike modules 002/003, where field names had to be fixed):
#   - vepSIFT was produced with --sift b (term+score, e.g.
#     "tolerated(1)", "deleterious_low_confidence(0)") — the substring
#     match ~"tolerated" works as written, and naturally also catches
#     "tolerated_low_confidence(...)", which is a reasonable inclusion.
#   - vepPolyPhen was produced with --polyphen p (prediction term only,
#     e.g. "benign", "probably_damaging", no score) — the exact match
#     ="benign" works as written.
# Previewed (read-only, no file written) against 005's 409-variant
# output: 191 variants would be excluded, 218 would remain.
#
# Run from anywhere:
#   bash VCF_pipeline/006-BCFTools_SiftPolyphen/bin/run_sift_polyphen_filter.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=4 bash VCF_pipeline/006-BCFTools_SiftPolyphen/bin/run_sift_polyphen_filter.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/VCF_pipeline/006-BCFTools_SiftPolyphen"
INPUT_DIR="$PROJECT_ROOT/VCF_pipeline/005-SynonymousMutations/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

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
    echo "Error: $INPUT_VCF not found. Run 005-SynonymousMutations first." >&2
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
