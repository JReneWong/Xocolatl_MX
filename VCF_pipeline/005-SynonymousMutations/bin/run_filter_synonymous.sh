#!/usr/bin/env bash
# Module 005-SynonymousMutations — keep only variants whose worst
# consequence is potentially protein/splicing-altering (drops synonymous
# and everything functionally milder: intronic, UTR, upstream/downstream,
# etc.). Operates on 004-BCFTools_LowFreqVar's output.
#
# Adapted from bin/FilteringSynonymousMutations.sh (the team's reference
# script) to this project's pipeline/manifest conventions. The original
# script is left untouched for reference (moved into bin/ to match module
# layout — it was sitting at the module root).
#
# --- The actual improvement over the reference script ---
# The reference script substring-matches against the raw, unparsed
# INFO/CSQ string. That's imprecise: CSQ packs in *every* transcript
# overlapping the variant, comma-separated, so a match can come from a
# minor/non-canonical transcript rather than the biologically relevant
# one, and matching a big multi-transcript blob makes it hard to reason
# about compound (SO-term, "&"-joined) consequences correctly.
#
# 003-BCFToolsFiltering already ran bcftools +split-vep -s worst to
# produce vepConsequence — one precise value per variant, taken from its
# single worst-consequence transcript — and that field is carried forward
# untouched through 004's output. Matching against vepConsequence instead
# of raw CSQ is strictly more correct, using the exact same curated term
# list as the reference script.
#
# This also resolves compound terms correctly by construction: verified
# against 004's actual output that of variants whose vepConsequence
# mentions "synonymous", 131 are exactly "synonymous_variant" and 10 are
# "synonymous_variant&NMD_transcript_variant" (both silent at the codon
# level, both correctly dropped — neither matches any allow-listed term
# below), while 2 are "splice_region_variant&synonymous_variant" (real
# splice significance despite the synonymous codon change — correctly
# kept, since "splice_region_variant" is in the allow-list and this is
# now a substring match against a single precise value, not a scan across
# every transcript's worth of CSQ text).
#
# Run from anywhere:
#   bash VCF_pipeline/005-SynonymousMutations/bin/run_filter_synonymous.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=4 bash VCF_pipeline/005-SynonymousMutations/bin/run_filter_synonymous.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/VCF_pipeline/005-SynonymousMutations"
INPUT_DIR="$PROJECT_ROOT/VCF_pipeline/004-BCFTools_LowFreqVar/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/RareVars_vep_${SAMPLE}.PASS.vcf.gz"

# Same curated allow-list as the reference script, just matched against
# the flattened vepConsequence field instead of raw CSQ.
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
    echo "Error: $INPUT_VCF not found. Run 004-BCFTools_LowFreqVar first." >&2
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
