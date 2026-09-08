#!/usr/bin/env bash
# Module 004-BCFTools_LowFreqVar — keep only rare/novel variants: those
# absent from gnomAD entirely (vepgnomAD_AF missing, i.e. ".") or with a
# gnomAD population allele frequency below 0.1% (AF < 0.001). Operates on
# 003-BCFToolsFiltering's flattened vepgnomAD_AF INFO field.
#
# Adapted from bin/BCFTools_FilteringLowFreVar.sh (the team's reference
# one-liner) to this project's pipeline/manifest conventions. Field name
# and type (vepgnomAD_AF, Float) were verified against 003's actual output
# header before writing this — no correction needed here, unlike earlier
# modules; the reference script already used the real field name.
# The original script is left untouched for reference.
#
# Run from anywhere:
#   bash VCF_pipeline/004-BCFTools_LowFreqVar/bin/run_bcftools_lowfreqvar.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=4 AF_THRESHOLD=0.01 bash VCF_pipeline/004-BCFTools_LowFreqVar/bin/run_bcftools_lowfreqvar.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/VCF_pipeline/004-BCFTools_LowFreqVar"
INPUT_DIR="$PROJECT_ROOT/VCF_pipeline/003-BCFToolsFiltering/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/SplitVEP_vep_${SAMPLE}.PASS.vcf.gz"

AF_THRESHOLD="${AF_THRESHOLD:-0.001}"   # gnomAD AF cutoff; missing (".") always kept regardless of threshold
FILTER_EXPR="INFO/vepgnomAD_AF=\".\" || INFO/vepgnomAD_AF < ${AF_THRESHOLD}"

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
    echo "Error: $INPUT_VCF not found. Run 003-BCFToolsFiltering first." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

OUT_VCF="$MODULE_DIR/results/RareVars_vep_${SAMPLE}.PASS.vcf.gz"

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
echo "Done. Rare-variant VCF: $OUT_VCF"
