#!/usr/bin/env bash
# Module 010-Tier2_ModerateImpact — Tier 2 of the tiering scheme: variants
# VEP itself classifies as MODERATE impact (predominantly missense, plus
# inframe insertions/deletions) — protein-altering but not
# protein-destroying, unlike Tier 1's HIGH-impact set. Operates on
# 006-BCFTools_SiftPolyphen's output, the same parent set Tier 1
# (007-Tier1_HighImpact) was drawn from — Tier 2 is a sibling partition,
# not built on top of Tier 1.
#
# Unlike Tier 1 (which reconstructed VEP's HIGH-impact category by
# hand-listing consequence substrings, since the original colleague
# script used a plain regex against raw CSQ), this tier uses vepIMPACT
# directly — VEP's own official impact classification, already flattened
# by module 003 alongside vepConsequence. Verified before writing this:
# vepIMPACT="HIGH" on 006's 218-variant set gives exactly 50 variants,
# matching module 007 exactly, confirming vepIMPACT is a reliable,
# authoritative stand-in for the manual reconstruction. The three impact
# tiers partition the 218-variant set cleanly: 50 HIGH + 100 MODERATE +
# 68 LOW = 218.
#
# Run from anywhere:
#   bash VCF_pipeline/010-Tier2_ModerateImpact/bin/run_tier2_moderateimpact.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=4 bash VCF_pipeline/010-Tier2_ModerateImpact/bin/run_tier2_moderateimpact.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/VCF_pipeline/010-Tier2_ModerateImpact"
INPUT_DIR="$PROJECT_ROOT/VCF_pipeline/006-BCFTools_SiftPolyphen/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/SiftPolyphenFiltered_vep_${SAMPLE}.PASS.vcf.gz"

FILTER_EXPR='INFO/vepIMPACT="MODERATE"'

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
    echo "Error: $INPUT_VCF not found. Run 006-BCFTools_SiftPolyphen first." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

OUT_VCF="$MODULE_DIR/results/Tier2_ModerateImpact_vep_${SAMPLE}.PASS.vcf.gz"

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
echo "Done. Tier 2 (moderate-impact) VCF: $OUT_VCF"
