#!/usr/bin/env bash
# Module 007-Tier1_HighImpact — Tier 1 of the tiering scheme: keep only
# variants whose worst consequence is genuinely VEP HIGH-impact (stop
# gained/lost, frameshift, canonical splice site, start lost). Operates
# on 006-BCFTools_SiftPolyphen's output.
#
# Adapted from bin/Tier1_HighImpact.sh (the colleague's reference
# one-liner, from a different project — same "vep103_joint_germline..."
# generic naming as the earlier FilterVariantTranches suggestion) to this
# project's actual paths and pipeline/manifest conventions. The original
# one-liner is left as-is for reference.
#
# --- The fix vs. the reference script ---
# The reference script matches INFO/vepConsequence~"splice" — a bare
# substring match that also catches splice_region_variant, which VEP
# classifies as LOW impact (near a splice site, but not hitting the
# invariant donor/acceptor dinucleotide), unlike splice_donor_variant and
# splice_acceptor_variant, which are genuinely HIGH impact. Verified
# against 006's actual 218-variant output: the broad "splice" match would
# incorrectly pull in 69 splice_region_variant-only entries alongside the
# 12 that actually contain splice_donor_variant/splice_acceptor_variant.
# Narrowed to those two specific terms instead, so this tier now exactly
# reconstructs VEP's own HIGH-impact consequence category (stop_gained,
# stop_lost, frameshift_variant, splice_acceptor_variant,
# splice_donor_variant, start_lost — omitting only the structural-variant
# terms transcript_ablation/amplification/feature_elongation/truncation,
# irrelevant here since this VCF only has SNVs/small indels).
#
# Run from anywhere:
#   bash VCF_pipeline/007-Tier1_HighImpact/bin/run_tier1_highimpact.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=4 bash VCF_pipeline/007-Tier1_HighImpact/bin/run_tier1_highimpact.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/VCF_pipeline/007-Tier1_HighImpact"
INPUT_DIR="$PROJECT_ROOT/VCF_pipeline/006-BCFTools_SiftPolyphen/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/SiftPolyphenFiltered_vep_${SAMPLE}.PASS.vcf.gz"

FILTER_EXPR='INFO/vepConsequence~"stop" || INFO/vepConsequence~"frameshift" || INFO/vepConsequence~"splice_donor_variant" || INFO/vepConsequence~"splice_acceptor_variant" || INFO/vepConsequence~"start_lost"'

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

OUT_VCF="$MODULE_DIR/results/Tier1_HighImpact_vep_${SAMPLE}.PASS.vcf.gz"

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
echo "Done. Tier 1 (high-impact) VCF: $OUT_VCF"
