#!/usr/bin/env bash
# Module 004_HaplotypeCaller — GATK4 HaplotypeCaller in standard mode
# (-ERC NONE, GATK's default) on 003_MarkDuplicates's deduped,
# coordinate-sorted BAM: emits directly genotyped calls, not a GVCF —
# this is the final call set for this sample, no GenotypeGVCFs step
# needed afterward. Scattered by chromosome, one sequential
# HaplotypeCaller invocation per contig (same loop-then-merge shape as
# 002_Alignment's per-lane bwa loop), so an interrupted run only has to
# redo the contigs it hadn't finished, not the whole genome. Contig VCFs
# are then gathered into one per-sample VCF and indexed.
#
# Trade-off of -ERC NONE vs GVCF: fine for a single sample analyzed on
# its own, but a GVCF retains per-site reference-confidence data that
# lets you cheaply joint-genotype against other samples later without
# recalling anything. Direct-mode output doesn't keep that — if this
# project ever needs joint calling against another sample, this module
# would need to be re-run in GVCF mode, not just re-genotyped. Chosen
# here to match the team's agreed approach.
#
# BQSR intentionally skipped (team decision — NovaSeq's binned quality
# scores make it low-value here). --dbsnp is still passed to *annotate*
# known-site rsIDs into the output VCF's ID column; that's unrelated to
# what BQSR does and doesn't correct/recalibrate anything.
#
# Ploidy: called diploid genome-wide (HaplotypeCaller's default), chrX/Y
# included. No sex-aware ploidy adjustment (would need the sample's
# inferred karyotype/sex first) — a known simplification, flag it if
# X/Y calls need to be trusted precisely.
#
# chrM: included in the scatter for completeness, but circular-genome,
# high-copy-number, heteroplasmic mitochondrial variants really want a
# dedicated caller (e.g. GATK's Mutect2 mitochondria mode), not
# standard diploid HaplotypeCaller — treat chrM output here as a rough
# pass, not a final answer, if mito variants matter for this case.
#
# Out of scope here, left for a later module: variant filtering
# (this module emits raw, unfiltered calls — every site HaplotypeCaller
# proposed, not a curated callset).
#
# Run from the project root:
#   bash Re-calling_Pipeline/004_HaplotypeCaller/bin/run_haplotypecaller.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=4 JAVA_MEM=12g bash Re-calling_Pipeline/004_HaplotypeCaller/bin/run_haplotypecaller.sh
#
# Safe to re-run: each contig and the final gather are skipped if their
# expected output already exists (set FORCE=1 to redo).
#
# Runtime note: HaplotypeCaller's PairHMM step only parallelizes within a
# single contig (--native-pair-hmm-threads), not across contigs — this
# script still runs contigs one at a time, so whole-genome at ~30x is
# realistically an overnight-plus job even scattered like this. If that's
# too slow, the next lever is finer-than-chromosome interval scatter
# (e.g. Broad's wgs_calling_regions.hg38.interval_list split into N
# pieces) run truly in parallel, not just more threads on one contig at
# a time — flag it here if we hit that wall.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/004_HaplotypeCaller"
INPUT_DIR="$PROJECT_ROOT/Re-calling_Pipeline/003_MarkDuplicates/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup
REF_DIR="$PROJECT_ROOT/references/genome"
REF_FASTA="$REF_DIR/Homo_sapiens_assembly38.fasta"
DBSNP="$PROJECT_ROOT/references/dbsnp/Homo_sapiens_assembly38.dbsnp138.vcf.gz"

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_BAM="$INPUT_DIR/${SAMPLE}.dedup.bam"

# Primary assembly only — chr1-22, chrX, chrY, chrM. Deliberately
# excludes ALT/decoy/unplaced contigs (chrUn_*, *_random, *_alt, etc.):
# HaplotypeCaller isn't ALT-aware, so calling on an ALT locus as well as
# the primary-chromosome coordinates it's a variant of would just
# produce spurious duplicate/conflicting calls for the same underlying
# sequence.
CONTIGS=(chr1 chr2 chr3 chr4 chr5 chr6 chr7 chr8 chr9 chr10 chr11 chr12 \
         chr13 chr14 chr15 chr16 chr17 chr18 chr19 chr20 chr21 chr22 \
         chrX chrY chrM)

CPUS="${CPUS:-10}"
JAVA_MEM="${JAVA_MEM:-8g}"   # HaplotypeCaller needs less heap than MarkDuplicates' record cache did

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

if [ ! -s "$INPUT_BAM" ]; then
    echo "Error: $INPUT_BAM not found. Run 003_MarkDuplicates first." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

# Same reasoning as 003_MarkDuplicates's TMP_DIR: keep GATK's scratch
# space on the SSD, not the host's much smaller root filesystem.
TMP_DIR="$MODULE_DIR/results/tmp"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT
mkdir -p "$TMP_DIR"

CONTIG_VCFS=()
for CONTIG in "${CONTIGS[@]}"; do
    OUT_VCF="$MODULE_DIR/results/${SAMPLE}.${CONTIG}.vcf.gz"
    CONTIG_VCFS+=("$OUT_VCF")

    if [ -s "$OUT_VCF" ] && [ -s "$OUT_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
        echo "$OUT_VCF already present — skipping (FORCE=1 to redo)."
        continue
    fi

    # No -ERC flag: GATK defaults to -ERC NONE, i.e. directly genotyped
    # calls rather than a GVCF's per-site reference-confidence records.
    HC_CMD="set -euo pipefail; gatk --java-options '-Xmx$JAVA_MEM -Djava.io.tmpdir=$TMP_DIR' HaplotypeCaller \
        -R '$REF_FASTA' \
        -I '$INPUT_BAM' \
        -L '$CONTIG' \
        --dbsnp '$DBSNP' \
        --native-pair-hmm-threads $CPUS \
        -O '$OUT_VCF'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "$JAVA_MEM" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$HC_CMD"
done

MERGED_VCF="$MODULE_DIR/results/${SAMPLE}.vcf.gz"
if [ -s "$MERGED_VCF" ] && [ -s "$MERGED_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$MERGED_VCF already present — skipping (FORCE=1 to redo)."
else
    # Picard MergeVcfs, not a naive concatenation: like samtools merge
    # does for the per-lane BAMs in 002_Alignment, it merges the inputs
    # by genomic coordinate against the shared sequence dictionary, so
    # command-line order doesn't matter — each per-contig VCF here is
    # already non-overlapping, so this is just a gather, not a real sort.
    INPUT_ARGS=""
    for VCF in "${CONTIG_VCFS[@]}"; do
        INPUT_ARGS="$INPUT_ARGS I=$VCF"
    done

    MERGE_CMD="set -euo pipefail; picard -Xmx$JAVA_MEM -Djava.io.tmpdir=$TMP_DIR MergeVcfs \
        $INPUT_ARGS \
        O='$MERGED_VCF'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "1" "$JAVA_MEM" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$MERGE_CMD"
fi

STATS="$MODULE_DIR/results/${SAMPLE}.vcf.stats.txt"
if [ -s "$STATS" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$STATS already present — skipping (FORCE=1 to redo)."
else
    run_and_log "$MODULE_DIR" "$CONTAINER" "1" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "bcftools stats '$MERGED_VCF' > '$STATS'"
fi

echo
echo "Done. Per-sample VCF (unfiltered): $MERGED_VCF"
echo "Per-contig VCFs kept in: $MODULE_DIR/results/${SAMPLE}.<contig>.vcf.gz"
echo "Stats: $STATS"
