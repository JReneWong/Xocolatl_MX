#!/usr/bin/env bash
# Module 008_FilterVCF — keep only variants whose FILTER column is PASS
# from 007_VariantFiltration's output, using bcftools view -i 'FILTER="PASS"'.
#
# Deliberately identical in approach to VCF_pipeline/001_FilterVCF (same
# bcftools command) — this is the Re-calling front's counterpart step, now
# that both fronts follow the same filtering methodology (team decision).
# Only the input path differs: 007's own hard-filter output here (itself
# now stacked on top of 006_FilterVariantTranches's CNN tranche filter —
# see 007's own script comments), vs. the organizer's pre-filtered
# InitialData VCF there.
#
# Run from anywhere:
#   bash Re-calling_Pipeline/008_FilterVCF/bin/run_filter_vcf.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=4 bash Re-calling_Pipeline/008_FilterVCF/bin/run_filter_vcf.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/008_FilterVCF"
INPUT_DIR="$PROJECT_ROOT/Re-calling_Pipeline/007_VariantFiltration/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/${SAMPLE}.filtered.vcf.gz"

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
    echo "Error: $INPUT_VCF not found. Run 007_VariantFiltration first." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

OUT_VCF="$MODULE_DIR/results/${SAMPLE}.PASS.vcf.gz"

if [ -s "$OUT_VCF" ] && [ -s "$OUT_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$OUT_VCF already present — skipping (FORCE=1 to redo)."
else
    FILTER_CMD="set -euo pipefail; bcftools view -i 'FILTER=\"PASS\"' --threads $CPUS -Oz -o '$OUT_VCF' '$INPUT_VCF' \
        && bcftools index -t --threads $CPUS '$OUT_VCF'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$FILTER_CMD"
fi

echo
echo "Done. PASS-only VCF: $OUT_VCF"
