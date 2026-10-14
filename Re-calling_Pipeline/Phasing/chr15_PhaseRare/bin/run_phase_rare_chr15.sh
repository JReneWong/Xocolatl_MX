#!/usr/bin/env bash
# Re-calling_Pipeline/Phasing/chr15_PhaseRare — phase the rare/private
# chr15 variants that Phasing/chr15's phase_common run DROPPED (it only
# outputs sites present in the reference panel) onto the phased
# common-variant scaffold that same run produced, using SHAPEIT5's
# phase_rare.
#
# Independent module, not a step tacked onto Phasing/chr15's own script
# (team decision) — phase_common and phase_rare are two genuinely
# separate SHAPEIT5 tools with different inputs/purposes, so each gets
# its own bin/data/results, chained by reading the other's results/
# directly (same convention every other module in this project uses).
#
# --- Why this module exists at all ---
# Phasing/chr15/results/chr15.phased.vcf.gz has only 118,898 of our
# original 130,040 chr15 variants: phase_common silently drops anything
# not present in the reference panel (8,253 sites here) plus
# multiallelics (2,889) — confirmed directly by comparing record counts,
# not assumed. Both of BUB1B's variants (chr15:40209701 stop_gained,
# chr15:40220612 missense — the actual motivation for all of this) were
# among the dropped sites, since neither exists in the panel at its
# exact position (also confirmed directly — see Phasing/chr15's own
# results). phase_common's own output is therefore NOT an answer to "are
# these two variants in phase" — it doesn't even contain them.
#
# phase_rare is SHAPEIT5's dedicated second stage for exactly this:
# given (a) the phased common-variant scaffold and (b) the FULL,
# unphased genotype set (rare variants included), it phases the rare
# sites onto that scaffold using local haplotype structure in our own
# sample plus the scaffold's phase, rather than requiring the rare site
# itself to match the reference panel.
#
# --- Inputs, both from Phasing/chr15's results (not re-derived here) ---
#   --scaffold : Phasing/chr15/results/chr15.phased.vcf.gz  (phased, common-only)
#   --input    : Phasing/chr15/results/ours_chr15.vcf.gz    (unphased, ALL variants)
# Same genetic map as chr15's phase_common run (bundled in the shapeit
# container, not downloaded separately).
#
# --- Real bug hit and fixed: phase_rare segfaults on a 1-sample scaffold ---
# First attempt used chr15.phased.vcf.gz as --scaffold directly (just our
# one sample). It crashed (SIGSEGV) right after "PBWT initialization
# [#eval=0 / #select=1300]" — confirmed from the log, not guessed: #eval=0
# means zero haplotypes were available for phase_rare's PBWT to condition
# on. Unlike phase_common, phase_rare has NO separate --reference flag —
# it expects the --scaffold ITSELF to already be a multi-sample panel
# (normal usage: phase_common a whole cohort together with a reference
# panel, then phase_rare that same cohort). A lone target sample gives it
# nothing to condition against, and it crashes on that degenerate case
# instead of erroring out cleanly.
#
# Fixed by merging our 1-sample scaffold with the 1000G panel's own
# phased genotypes at the same 118,898 sites (guaranteed present in both,
# by construction — that's exactly the set phase_common filtered down
# to) into one 3,203-sample scaffold. --input stays our own single-sample
# full genotype set — phase_rare only phases/outputs samples present in
# --input, the extra panel samples in --scaffold are conditioning data
# only. No sample-ID collision (checked directly).
#
# Run from the project root:
#   bash Re-calling_Pipeline/Phasing/chr15_PhaseRare/bin/run_phase_rare_chr15.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=8 bash Re-calling_Pipeline/Phasing/chr15_PhaseRare/bin/run_phase_rare_chr15.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/Phasing/chr15_PhaseRare"
INPUT_DIR="$PROJECT_ROOT/Re-calling_Pipeline/Phasing/chr15/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup

OURS_SCAFFOLD_VCF="$INPUT_DIR/chr15.phased.vcf.gz"
GENOTYPES_VCF="$INPUT_DIR/ours_chr15.vcf.gz"
PANEL="$PROJECT_ROOT/references/1000G_GRCh38/chr15_1000G_GRCh38_phased.vcf.gz"

# Unlike phase_common's --region (accepts a bare chromosome name, used
# as-is in Phasing/chr15), phase_rare's --input-region/--scaffold-region
# require the full chrX:Y-Z form ("chromosome ID cannot be extracted"
# otherwise — hit this directly on the first run). Derived from the
# reference .fai rather than hardcoded, so this still works if reused
# for another chromosome later.
FAI="$PROJECT_ROOT/references/genome/Homo_sapiens_assembly38.fasta.fai"
CHR="chr15"
CHR_LEN="$(awk -v c="$CHR" '$1==c {print $2}' "$FAI")"
REGION="${CHR}:1-${CHR_LEN}"
GMAP="/opt/src/shapeit/resources/maps/b38/chr15.b38.gmap.gz"   # path INSIDE the shapeit container — baked into the image, same as Phasing/chr15

CPUS="${CPUS:-4}"

source "$PROJECT_ROOT/common/manifest.sh"
CONTAINER="$(resolve_container "$PROJECT_ROOT")"                 # hackathon_<arch>.sif — bcftools
SHAPEIT_CONTAINER="$(resolve_container "$PROJECT_ROOT" "shapeit")"   # shapeit_<arch>.sif — phase_rare

export MANIFEST_INPUT_DIR="$INPUT_DIR"

if [ ! -f "$CONTAINER" ]; then
    echo "Error: $CONTAINER not found. Build it first (see README.md)." >&2
    exit 1
fi
if [ ! -f "$SHAPEIT_CONTAINER" ]; then
    echo "Error: $SHAPEIT_CONTAINER not found. Build it first: apptainer build --force $SHAPEIT_CONTAINER shapeit.def" >&2
    exit 1
fi
if [ ! -s "$OURS_SCAFFOLD_VCF" ]; then
    echo "Error: $OURS_SCAFFOLD_VCF not found. Run Phasing/chr15 first." >&2
    exit 1
fi
if [ ! -s "$GENOTYPES_VCF" ]; then
    echo "Error: $GENOTYPES_VCF not found. Run Phasing/chr15 first." >&2
    exit 1
fi
if [ ! -s "$PANEL" ] || [ ! -s "$PANEL.tbi" ]; then
    echo "Error: $PANEL (+ .tbi) not found." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

# --- Step 1: merge our 1-sample scaffold with the panel's own phased
# genotypes at the same sites, giving phase_rare a real multi-sample
# scaffold to condition on (see header — this is the actual crash fix) ---
SCAFFOLD_VCF="$MODULE_DIR/results/scaffold_merged.vcf.gz"

if [ -s "$SCAFFOLD_VCF" ] && [ -s "$SCAFFOLD_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$SCAFFOLD_VCF already present — skipping (FORCE=1 to redo)."
else
    MERGE_CMD="set -euo pipefail; bcftools merge -R '$OURS_SCAFFOLD_VCF' --threads $CPUS -Oz -o '$SCAFFOLD_VCF' '$OURS_SCAFFOLD_VCF' '$PANEL' \
        && bcftools index -t --threads $CPUS '$SCAFFOLD_VCF'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$MERGE_CMD"
fi

PHASED_VCF="$MODULE_DIR/results/chr15.rare_phased.vcf.gz"

if [ -s "$PHASED_VCF" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$PHASED_VCF already present — skipping (FORCE=1 to redo)."
else
    run_and_log "$MODULE_DIR" "$SHAPEIT_CONTAINER" "$CPUS" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$SHAPEIT_CONTAINER" \
        /opt/src/shapeit/phase_rare/bin/phase_rare \
            --input "$GENOTYPES_VCF" \
            --scaffold "$SCAFFOLD_VCF" \
            --map "$GMAP" \
            --input-region "$REGION" \
            --scaffold-region "$REGION" \
            --thread "$CPUS" \
            --output "$PHASED_VCF" \
            --log "$MODULE_DIR/results/chr15.phase_rare.log"
fi

if [ -s "$PHASED_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$PHASED_VCF.tbi already present — skipping (FORCE=1 to redo)."
else
    run_and_log "$MODULE_DIR" "$CONTAINER" "1" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bcftools index -t "$PHASED_VCF"
fi

echo
echo "Done. Rare-phased chr15 VCF: $PHASED_VCF"
echo
echo "BUB1B check (chr15:40209701 stop_gained, chr15:40220612 missense) — same GT means same haplotype (phase set permitting), 0|1 vs 1|0 means opposite (compound het):"
apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
    bcftools query -f '%CHROM\t%POS[\t%GT]\n' -r chr15:40209701,chr15:40220612 "$PHASED_VCF"
