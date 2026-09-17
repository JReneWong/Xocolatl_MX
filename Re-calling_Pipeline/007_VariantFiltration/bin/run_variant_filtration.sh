#!/usr/bin/env bash
# Module 007_VariantFiltration — GATK VariantFiltration, using the EXACT
# same filter expressions the organizers used to produce
# InitialData/WGS_EX2312012_HGWCNDSX7.vcf.gz. Team decision: the
# Re-calling front now follows the VCF Filtering front's steps, so
# filtering methodology needs to match theirs, not just the tool.
#
# Found by reading the organizer's own VCF header (GATK stamps full command
# provenance into every VCF it writes) — not guessed or inferred:
#   zcat InitialData/WGS_EX2312012_HGWCNDSX7.vcf.gz | grep '^##GATKCommandLine'
# Their command: VariantFiltration (GATK 4.2.4.0), one uniform pass over
# the whole callset (no SNP/indel split, no SOR filter — simpler than
# GATK's fuller best-practice recommendation). Replicated verbatim here.
#
# --- Input changed as of the 006_FilterVariantTranches insertion (team
# decision), and a real bug found + fixed along the way ---
# This module originally ran directly on 004_HaplotypeCaller's raw VCF.
# It now runs on 006_FilterVariantTranches's output instead — single
# linear chain, not two branches: 004 -> 005 -> 006 -> 007 -> 008 -> ...
#
# First attempt at this assumed GATK's VariantFiltration would ADD a
# failing reason on top of whatever FILTER value 006 already set,
# preserving 006's tranche-fail calls while layering this module's own
# hard-filter on top. That's wrong: VariantFiltration recomputes FILTER
# from scratch using only the expressions given IN THIS invocation,
# discarding whatever was already there — confirmed directly on real
# data (chr1:10469 failed 006's CNN tranche filter but came out of a
# naive 007 run marked PASS, as if 006 had never run).
#
# Fixed by pre-filtering to 006's PASS-only subset FIRST (bcftools view
# -i 'FILTER="PASS"', identical operation to 008_FilterVCF, just run one
# step earlier), then handing GATK only that already-CNN-passing subset.
# Since anything that failed 006 is removed before VariantFiltration ever
# sees it, whatever comes out the other end marked PASS is guaranteed —
# by construction, not by GATK's cooperation — to have passed BOTH 006's
# CNN tranche filter and this module's hard-filter thresholds.
#
# QD/MQ/FS/ReadPosRankSum/MQRankSum (this module's filter targets) are
# original HaplotypeCaller annotations, untouched by 005/006, so they're
# still present and unchanged on every record reaching this module.
#
# This means the comparison against VCF_pipeline (which applies only the
# organizer's single hard-filter pass, no CNN step) is no longer
# filtering-methodology-identical — see 014_ComparisonReport, still on
# hold, for how that's accounted for once it's built out.
#
# Record count is NO LONGER preserved 1:1 from 006 as of this fix: the
# pre-filter step above already drops every record that failed 006, so
# this module's final output can only ever contain, at most, 006's PASS
# count (4,257,769 last measured) — see 008_FilterVCF for the PASS-only
# extraction step that then narrows this module's own hard-filter
# result, mirroring VCF_pipeline/001_FilterVCF.
#
# Run from the project root:
#   bash Re-calling_Pipeline/007_VariantFiltration/bin/run_variant_filtration.sh
#
# Override defaults with env vars, e.g.:
#   JAVA_MEM=8g bash Re-calling_Pipeline/007_VariantFiltration/bin/run_variant_filtration.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/007_VariantFiltration"
INPUT_DIR="$PROJECT_ROOT/Re-calling_Pipeline/006_FilterVariantTranches/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup
REF_FASTA="$PROJECT_ROOT/references/genome/Homo_sapiens_assembly38.fasta"

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/${SAMPLE}.tranche_filtered.vcf.gz"

CPUS="${CPUS:-2}"
JAVA_MEM="${JAVA_MEM:-4g}"

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
    echo "Error: $INPUT_VCF not found. Run 006_FilterVariantTranches first." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

TMP_DIR="$MODULE_DIR/results/tmp"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT
mkdir -p "$TMP_DIR"

# --- Step 1: pre-filter 006's output to its PASS-only subset ---
# This is the actual fix (see header comment above) — without it,
# VariantFiltration below would silently discard 006's CNN tranche
# decision. Kept in results/ (not TMP_DIR) since it's a meaningful,
# inspectable checkpoint, not just scratch space.
CNN_PASS_VCF="$MODULE_DIR/results/${SAMPLE}.cnn_pass_only.vcf.gz"

if [ -s "$CNN_PASS_VCF" ] && [ -s "$CNN_PASS_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$CNN_PASS_VCF already present — skipping (FORCE=1 to redo)."
else
    PASS_CMD="set -euo pipefail; bcftools view -i 'FILTER=\"PASS\"' --threads $CPUS -Oz -o '$CNN_PASS_VCF' '$INPUT_VCF' \
        && bcftools index -t --threads $CPUS '$CNN_PASS_VCF'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$PASS_CMD"
fi

# --- Step 2: apply the organizer's hard-filter to that already-CNN-passing subset ---
OUT_VCF="$MODULE_DIR/results/${SAMPLE}.filtered.vcf.gz"

if [ -s "$OUT_VCF" ] && [ -s "$OUT_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$OUT_VCF already present — skipping (FORCE=1 to redo)."
else
    VF_CMD="set -euo pipefail; gatk --java-options '-Xmx$JAVA_MEM -Djava.io.tmpdir=$TMP_DIR' VariantFiltration \
        -R '$REF_FASTA' \
        -V '$CNN_PASS_VCF' \
        -O '$OUT_VCF' \
        --filter-expression 'QD < 2.0' --filter-name QD2 \
        --filter-expression 'MQ < 40.0' --filter-name MQ40 \
        --filter-expression 'ReadPosRankSum < -8.0' --filter-name RPRS-8 \
        --filter-expression 'FS > 60.0' --filter-name FS60 \
        --filter-expression 'MQRankSum < -12.5' --filter-name MQRankSum-12.5"

    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "$JAVA_MEM" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$VF_CMD"
fi

echo
echo "Done. CNN-pass-only subset: $CNN_PASS_VCF"
echo "FILTER-annotated callset (both filters applied): $OUT_VCF"
