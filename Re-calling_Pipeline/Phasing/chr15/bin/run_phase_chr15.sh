#!/usr/bin/env bash
# Re-calling_Pipeline/Phasing/chr15 — statistically phase every chr15
# variant in 008_FilterVCF's PASS-only callset (before any of the
# rarity/consequence narrowing modules 010-018 apply) using SHAPEIT5's
# phase_common against the 1000 Genomes high-coverage GRCh38 reference
# panel.
#
# Not part of the numbered 001-019 sequence deliberately (team decision):
# this is a targeted investigation, not a step both fronts march through
# in lockstep — Phasing/ is a separate branch off Re-calling for exactly
# this kind of follow-up. Named by chromosome, not by the finding that
# motivated it (a candidate compound-het pair in BUB1B, chr15:40209701 +
# chr15:40220612 — see 016/018's variant tables), since the actual run
# phases all of chr15, not just that gene, and future investigations on
# other chromosomes would get their own Phasing/chrN/ sibling.
#
# --- Why the PRE-filter VCF (008), not the rare/functional-only ones ---
# phase_common phases everything in the input jointly: rare/private sites
# get phased "for free" by riding along a scaffold of nearby COMMON
# variants that actually carry the LD signal back to the reference panel
# — that scaffold is exactly what modules 010-018 (rare-variant, then
# consequence, then impact-tier filtering) progressively strip out. Using
# 008's still-common-variant-rich PASS callset gives phase_common the
# best chance of placing our two private BUB1B variants onto a real
# haplotype block. See the team's earlier discussion for the fuller
# reasoning.
#
# --- Reference panel and genetic map ---
# Panel: 1000 Genomes high-coverage GRCh38 recall (NYGC, 3,202 samples,
# natively called on GRCh38 — NOT the original 2013 Phase 3 panel, which
# is GRCh37, nor its since-withdrawn GRCh38 liftover, which EBI's own
# README flags as having known coordinate/strand-flip issues).
#   references/1000G_GRCh38/chr15_1000G_GRCh38_phased.vcf.gz
# Contig naming already matches ours exactly ("chr15" both sides) —
# verified directly, no --rename-chrs step needed here (unlike the
# VCF_pipeline-vs-Re-calling comparisons, which use "1"/"chr1").
#
# Genetic map: bundled inside the shapeit container itself (built from
# the same odelaneau/shapeit repo clone that provides phase_common), at
# /opt/src/shapeit/resources/maps/b38/chr15.b38.gmap.gz — no separate
# download needed.
#
# Both of BUB1B's positions were confirmed absent from the panel at
# their exact coordinates (checked directly, not assumed) — expected,
# given neither variant has a gnomAD_AF or Existing_variation entry
# either (see 016_Tier1_VariantTable's table). There IS a reasonable
# local scaffold though: 302 panel variants in the ~15kb window spanning
# both positions, so phase_common has real nearby haplotype structure to
# work with, even though it can't match either site directly.
#
# Run from the project root:
#   bash Re-calling_Pipeline/Phasing/chr15/bin/run_phase_chr15.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=8 bash Re-calling_Pipeline/Phasing/chr15/bin/run_phase_chr15.sh
#
# Safe to re-run: each step is skipped if its expected output already
# exists (set FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/Phasing/chr15"
INPUT_DIR="$PROJECT_ROOT/Re-calling_Pipeline/008_FilterVCF/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/${SAMPLE}.PASS.vcf.gz"

REGION="chr15"
PANEL="$PROJECT_ROOT/references/1000G_GRCh38/chr15_1000G_GRCh38_phased.vcf.gz"
GMAP="/opt/src/shapeit/resources/maps/b38/chr15.b38.gmap.gz"   # path INSIDE the shapeit container — baked into the image, not bind-mounted

CPUS="${CPUS:-4}"

source "$PROJECT_ROOT/common/manifest.sh"
CONTAINER="$(resolve_container "$PROJECT_ROOT")"                 # hackathon_<arch>.sif — bcftools/tabix
SHAPEIT_CONTAINER="$(resolve_container "$PROJECT_ROOT" "shapeit")"   # shapeit_<arch>.sif — phase_common

export MANIFEST_INPUT_DIR="$INPUT_DIR"

if [ ! -f "$CONTAINER" ]; then
    echo "Error: $CONTAINER not found. Build it first (see README.md)." >&2
    exit 1
fi
if [ ! -f "$SHAPEIT_CONTAINER" ]; then
    echo "Error: $SHAPEIT_CONTAINER not found. Build it first: apptainer build $SHAPEIT_CONTAINER shapeit.def" >&2
    exit 1
fi
if [ ! -s "$INPUT_VCF" ]; then
    echo "Error: $INPUT_VCF not found. Run 008_FilterVCF first." >&2
    exit 1
fi
if [ ! -s "$PANEL" ] || [ ! -s "$PANEL.tbi" ]; then
    echo "Error: $PANEL (+ .tbi) not found." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

# --- Step 1: subset our PASS-only callset to chr15 ---
OURS_CHR15="$MODULE_DIR/results/ours_chr15.vcf.gz"

if [ -s "$OURS_CHR15" ] && [ -s "$OURS_CHR15.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$OURS_CHR15 already present — skipping (FORCE=1 to redo)."
else
    SUBSET_CMD="set -euo pipefail; bcftools view -r '$REGION' --threads $CPUS -Oz -o '$OURS_CHR15' '$INPUT_VCF' \
        && bcftools index -t --threads $CPUS '$OURS_CHR15'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$SUBSET_CMD"
fi

# --- Step 2: phase_common ---
PHASED_VCF="$MODULE_DIR/results/chr15.phased.vcf.gz"

if [ -s "$PHASED_VCF" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$PHASED_VCF already present — skipping (FORCE=1 to redo)."
else
    run_and_log "$MODULE_DIR" "$SHAPEIT_CONTAINER" "$CPUS" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$SHAPEIT_CONTAINER" \
        /opt/src/shapeit/phase_common/bin/phase_common \
            --input "$OURS_CHR15" \
            --reference "$PANEL" \
            --map "$GMAP" \
            --region "$REGION" \
            --thread "$CPUS" \
            --output "$PHASED_VCF" \
            --log "$MODULE_DIR/results/chr15.phase_common.log"
fi

# --- Step 3: index the phased output ---
if [ -s "$PHASED_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$PHASED_VCF.tbi already present — skipping (FORCE=1 to redo)."
else
    run_and_log "$MODULE_DIR" "$CONTAINER" "1" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bcftools index -t "$PHASED_VCF"
fi

echo
echo "Done. Phased chr15 VCF: $PHASED_VCF"
echo
echo "BUB1B check (chr15:40209701 stop_gained, chr15:40220612 missense) — same GT means same haplotype (phase set permitting), 0|1 vs 1|0 means opposite (compound het):"
apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
    bcftools query -f '%CHROM\t%POS[\t%GT]\n' -r chr15:40209701,chr15:40220612 "$PHASED_VCF"
