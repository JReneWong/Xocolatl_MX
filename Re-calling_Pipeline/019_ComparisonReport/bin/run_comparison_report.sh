#!/usr/bin/env bash
# Module 019_ComparisonReport — for each of the nine matching stages
# between the Re-calling front (008-015) and the VCF Filtering front
# (001-008), compute: record count on each side, and a proper variant-
# level intersection (private-to-us / private-to-them / shared).
#
# Renumbered from 014 to 017 when 014_Tier1_HighImpact,
# 015_MVAGenePanel, and 016_Tier1_VariantTable were inserted ahead of it
# (team decision, same "add modules, keep the rest, re-run" approach as
# 006_FilterVariantTranches's earlier insertion). The 009-Tier1_VariantTable
# / 016_Tier1_VariantTable stage is intentionally NOT in STAGES below —
# it's a flat text table, not a VCF, so bcftools isec doesn't apply; that
# comparison is done by row count / diff instead, ad hoc, not through
# this module.
#
# This module computes the underlying numbers only — no plot/panel is
# rendered here yet. That comes once these numbers are real (a chart
# can't be built on placeholder data), as a separate follow-up once this
# has actually run.
#
# --- Contig-naming reconciliation (the trickiest part of this module) ---
# VCF_pipeline's VCFs use plain contig names (1, 2, ..., X, Y, M) — same
# convention as the organizer's original VCF and VEP's offline cache.
# Ours use chr-prefixed names (chr1, chr2, ..., chrX, chrY, chrM), since
# 004_HaplotypeCaller was called against the chr-prefixed Broad genome.
# bcftools isec matches records by exact CHROM+POS+REF+ALT — without
# reconciling this, EVERY variant would wrongly show up as "private" to
# each side even when it's the same call.
#
# Fixed by renaming VCF_pipeline's side (not ours) to chr-prefixed, using
# references/genome/GRCh38_chr_synonyms.tsv — chosen over renaming our
# own side because that file is already stored in the "plain TAB
# chr-prefixed" order bcftools annotate --rename-chrs expects, and it
# lets bcftools norm below use our reference genome (already
# chr-prefixed) as-is, with no second reference copy needed.
#
# One real, expected asymmetry this surfaces at the FIRST stage only
# (FilterVCF): VCF_pipeline/001's PASS VCF still contains hundreds of
# decoy/unplaced-contig variants (organizer's data, pre-VEP) that aren't
# in the 25-contig synonyms map and so are left unrenamed — they will
# never match anything on our side, because 004_HaplotypeCaller never
# calls on those contigs at all (see 004's own script comments). This is
# real and correct, not a bug: VEP silently drops those same variants at
# the VEP stage on VCF_pipeline's side too (see 002-VEPAnnotation's own
# warnings.txt), so the asymmetry is specific to stage 1 and resolves
# itself from stage 2 onward.
#
# bcftools norm -m -both is also run on both sides before isec (splits
# multiallelic sites, left-aligns indels) — two callers can represent the
# same real variant differently on-disk otherwise, which would also
# wrongly register as "private" to each side.
#
# Run from the project root:
#   bash Re-calling_Pipeline/019_ComparisonReport/bin/run_comparison_report.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=4 bash Re-calling_Pipeline/019_ComparisonReport/bin/run_comparison_report.sh
#
# Safe to re-run: each stage is skipped if its row already exists in
# results/comparison_summary.tsv (set FORCE=1 to redo all stages).
# Missing inputs (a Re-calling module that hasn't run yet) are skipped
# with a warning rather than failing the whole report, so this can be
# run incrementally as 008-013 complete.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/019_ComparisonReport"
RC_DIR="$PROJECT_ROOT/Re-calling_Pipeline"
VCFP_DIR="$PROJECT_ROOT/VCF_pipeline"
REF_FASTA="$PROJECT_ROOT/references/genome/Homo_sapiens_assembly38.fasta"
SYNONYMS="$PROJECT_ROOT/references/genome/GRCh38_chr_synonyms.tsv"   # plain TAB chr-prefixed — exactly the order --rename-chrs wants for plain -> chr-prefixed

SAMPLE="WGS_EX2312012_HGWCNDSX7"
CPUS="${CPUS:-2}"

source "$PROJECT_ROOT/common/manifest.sh"
CONTAINER="$(resolve_container "$PROJECT_ROOT")"

if [ ! -f "$CONTAINER" ]; then
    echo "Error: $CONTAINER not found. Build it first (see README.md)." >&2
    exit 1
fi
if [ ! -s "$SYNONYMS" ]; then
    echo "Error: $SYNONYMS not found." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"
SUMMARY="$MODULE_DIR/results/comparison_summary.tsv"
if [ ! -s "$SUMMARY" ] || [ "${FORCE:-0}" = "1" ]; then
    echo -e "stage\tour_module\ttheir_module\tour_count\ttheir_count\tprivate_ours\tprivate_theirs\tshared" > "$SUMMARY"
fi

# label | our module dir | their module dir | shared filename (identical on both sides at every stage)
STAGES=(
    "FilterVCF|008_FilterVCF|001_FilterVCF|${SAMPLE}.PASS.vcf.gz"
    "VEPAnnotation|009_VEPAnnotation|002-VEPAnnotation|vep_${SAMPLE}.PASS.vcf.gz"
    "BCFToolsFiltering|010_BCFToolsFiltering|003-BCFToolsFiltering|SplitVEP_vep_${SAMPLE}.PASS.vcf.gz"
    "BCFTools_LowFreqVar|011_BCFTools_LowFreqVar|004-BCFTools_LowFreqVar|RareVars_vep_${SAMPLE}.PASS.vcf.gz"
    "SynonymousMutations|012_SynonymousMutations|005-SynonymousMutations|Functional_RareVars_vep_${SAMPLE}.PASS.vcf.gz"
    "BCFTools_SiftPolyphen|013_BCFTools_SiftPolyphen|006-BCFTools_SiftPolyphen|SiftPolyphenFiltered_vep_${SAMPLE}.PASS.vcf.gz"
    "Tier1_HighImpact|014_Tier1_HighImpact|007-Tier1_HighImpact|Tier1_HighImpact_vep_${SAMPLE}.PASS.vcf.gz"
    "MVAGenePanel|015_MVAGenePanel|008-MVAGenePanel|MVAGenePanel_vep_${SAMPLE}.PASS.vcf.gz"
    "Tier2_ModerateImpact|017_Tier2_ModerateImpact|010-Tier2_ModerateImpact|Tier2_ModerateImpact_vep_${SAMPLE}.PASS.vcf.gz"
)

for stage_def in "${STAGES[@]}"; do
    IFS='|' read -r LABEL OUR_MOD THEIR_MOD FNAME <<< "$stage_def"

    if [ "${FORCE:-0}" != "1" ] && grep -q "^${LABEL}	" "$SUMMARY" 2>/dev/null; then
        echo "$LABEL already in $SUMMARY — skipping (FORCE=1 to redo)."
        continue
    fi

    OUR_VCF="$RC_DIR/$OUR_MOD/results/$FNAME"
    THEIR_VCF="$VCFP_DIR/$THEIR_MOD/results/$FNAME"

    if [ ! -s "$OUR_VCF" ]; then
        echo "Skipping $LABEL — $OUR_VCF not found yet (run $OUR_MOD first)." >&2
        continue
    fi
    if [ ! -s "$THEIR_VCF" ]; then
        echo "Skipping $LABEL — $THEIR_VCF not found (VCF_pipeline/$THEIR_MOD hasn't run)." >&2
        continue
    fi

    TMP_DIR="$MODULE_DIR/results/tmp_$LABEL"
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"

    STAGE_CMD="set -euo pipefail
        # 1. rename VCF_pipeline's contigs to chr-prefixed
        bcftools annotate --rename-chrs '$SYNONYMS' -Oz -o '$TMP_DIR/theirs_renamed.vcf.gz' '$THEIR_VCF'
        bcftools index -t --threads $CPUS '$TMP_DIR/theirs_renamed.vcf.gz'

        # 2. normalize both sides (split multiallelics, left-align indels)
        bcftools norm -f '$REF_FASTA' -m -both -Oz -o '$TMP_DIR/ours_norm.vcf.gz' '$OUR_VCF'
        bcftools index -t --threads $CPUS '$TMP_DIR/ours_norm.vcf.gz'
        bcftools norm -f '$REF_FASTA' -m -both -Oz -o '$TMP_DIR/theirs_norm.vcf.gz' '$TMP_DIR/theirs_renamed.vcf.gz'
        bcftools index -t --threads $CPUS '$TMP_DIR/theirs_norm.vcf.gz'

        # 3. intersect: 0000=private ours, 0001=private theirs, 0002/0003=shared (from each side's own INFO)
        bcftools isec -p '$TMP_DIR/isec' -Oz '$TMP_DIR/ours_norm.vcf.gz' '$TMP_DIR/theirs_norm.vcf.gz'

        # 4. counts
        OUR_COUNT=\$(bcftools view -H '$OUR_VCF' | wc -l)
        THEIR_COUNT=\$(bcftools view -H '$THEIR_VCF' | wc -l)
        PRIVATE_OURS=\$(bcftools view -H '$TMP_DIR/isec/0000.vcf.gz' | wc -l)
        PRIVATE_THEIRS=\$(bcftools view -H '$TMP_DIR/isec/0001.vcf.gz' | wc -l)
        SHARED=\$(bcftools view -H '$TMP_DIR/isec/0002.vcf.gz' | wc -l)
        echo -e \"$LABEL\t$OUR_MOD\t$THEIR_MOD\t\$OUR_COUNT\t\$THEIR_COUNT\t\$PRIVATE_OURS\t\$PRIVATE_THEIRS\t\$SHARED\" >> '$SUMMARY'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$STAGE_CMD"

    rm -rf "$TMP_DIR"
done

echo
echo "Done. Comparison summary: $SUMMARY"
column -t -s $'\t' "$SUMMARY"
