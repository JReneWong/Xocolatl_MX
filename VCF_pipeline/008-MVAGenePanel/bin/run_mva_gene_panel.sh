#!/usr/bin/env bash
# Module 008-MVAGenePanel — narrow Tier 1 (high-impact) down to variants
# in the curated Mosaic Variegated Aneuploidy candidate gene panel
# (resources/genes.txt: BUB1, CEP57, TRIP13, CENATAC, MAD1L1, MAD2L1BP,
# CEP192) — matches the phenotype doc's "chromosomal instability
# disorder" framing. Operates on 007-Tier1_HighImpact's output.
#
# Adapted from bin/GeneListFiltering.sh (the colleague's reference
# script, from a different project — same generic "vep103_joint_germline
# ..." naming as earlier colleague scripts) to this project's actual
# paths and pipeline/manifest conventions. The original script is left
# as-is for reference.
#
# --- Fixes vs. the reference script ---
# - Real bug: `bcftools view -i "$filter vep103_....vcf.gz` never closes
#   the quote around $filter, so the input filename gets swallowed into
#   the filter expression string instead of being a separate argument.
#   Fixed by closing the quote right after $filter.
# - Branch point: the reference script reads from "...rare.vcf.gz" (i.e.
#   the rare-variant set before any impact filtering, matching this
#   project's module 004) but names its output
#   "...rare_high_impact_gene_list.vcf.gz" — implying Tier 1's
#   high-impact filter should already be applied, which "rare.vcf.gz"
#   alone doesn't reflect. Team decision: chain off 007-Tier1_HighImpact
#   instead, matching the output name's actual meaning (rare AND
#   high-impact AND in the gene panel).
# - Gene symbols verified against our actual vepSYMBOL values before
#   writing this (not executed): all 7 panel genes have real hits in our
#   VEP annotation, no symbol/alias mismatches.
#
# Run from anywhere:
#   bash VCF_pipeline/008-MVAGenePanel/bin/run_mva_gene_panel.sh
#
# Override defaults with env vars, e.g.:
#   GENE_LIST=/path/to/other_panel.txt bash VCF_pipeline/008-MVAGenePanel/bin/run_mva_gene_panel.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/VCF_pipeline/008-MVAGenePanel"
INPUT_DIR="$PROJECT_ROOT/VCF_pipeline/007-Tier1_HighImpact/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/Tier1_HighImpact_vep_${SAMPLE}.PASS.vcf.gz"
GENE_LIST="${GENE_LIST:-$PROJECT_ROOT/resources/genes.txt}"

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
    echo "Error: $INPUT_VCF not found. Run 007-Tier1_HighImpact first." >&2
    exit 1
fi

if [ ! -s "$GENE_LIST" ]; then
    echo "Error: $GENE_LIST not found." >&2
    exit 1
fi

FILTER_EXPR="$(awk '{printf sep "INFO/vepSYMBOL=\"%s\"", $1; sep=" || "}' "$GENE_LIST")"

mkdir -p "$MODULE_DIR/results"

OUT_VCF="$MODULE_DIR/results/MVAGenePanel_vep_${SAMPLE}.PASS.vcf.gz"

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
echo "Done. MVA gene panel VCF: $OUT_VCF"
