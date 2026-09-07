#!/usr/bin/env bash
# Module 002-VEPAnnotation — annotate the PASS-only VCF from 001_FilterVCF
# with Ensembl VEP (offline cache) + a ClinVar custom track.
#
# Adapted from bin/vep_annotation.sh (the team's reference script) to this
# project's actual resources and to the pipeline/manifest conventions used
# by VCF_pipeline/001_FilterVCF and pipeline/00N_*. The original script is
# left untouched for reference.
#
# Run from anywhere:
#   bash VCF_pipeline/002-VEPAnnotation/bin/run_vep_annotation.sh
#
# Override defaults with env vars, e.g.:
#   CPUS=8 bash VCF_pipeline/002-VEPAnnotation/bin/run_vep_annotation.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).
#
# --- Contig-naming fix (the key change vs. the reference script) ---
# Our input VCF (and the VEP cache, which is Ensembl-based) use plain
# contig names: 1, 2, ..., X, Y, M. Our downloaded reference genome (Broad
# GATK bundle, used for alignment) uses chr-prefixed names: chr1 ... chrM.
# Verified these are the same underlying assembly (identical contig
# lengths on both sides for 1-22/X/Y/M), so rather than keeping a second
# multi-GB copy of the genome, VEP is pointed at the original fasta plus a
# small synonyms file (references/genome/GRCh38_chr_synonyms.tsv, primary
# name <TAB> chr-prefixed synonym) so --fasta/--hgvs lookups resolve
# correctly. ClinVar is used in its "raw" pre-rename form
# (references/clinvar/clinvar_GRCh38.raw.vcf.gz), which is already plain-
# named and needed no fix — the processed clinvar_GRCh38.vcf.gz was
# deliberately re-chr-prefixed by scripts/download_references.sh to match
# the *genome*, i.e. the wrong convention for this VCF.
# Both syntax and this fix were validated on a 2,174-variant chr1 subset
# before writing this script (gene/transcript/HGVSc/ClinVar fields all
# populated correctly).
#
# --- Resources present vs. not present on this drive ---
# - dbSNP: intentionally omitted. Same chr-prefix mismatch as the genome
#   (Broad's dbsnp138 is chr-prefixed) and the reference script's own
#   comment says it's the one of the three custom tracks that's safe to
#   skip ("dbsnp lo podemos obviar").
# - COSMIC: not downloaded (nothing under references/), and germline
#   rare-disease variant prioritization doesn't need it. Dropped.
# - gnomAD: references/gnomAD/gnomad.genomes.v3.1.2.short.vcf.gz (v3.1.2
#   genomes, AF-reduced, ~9.2GB) — chr-prefixed like the genome, so it goes
#   through the same GRCh38_chr_synonyms.tsv fix as --fasta above (verified
#   working: --synonyms reconciles --custom track matching too, not just
#   --fasta — confirmed against ground truth on a real test variant).
#   Indexed here (.tbi was missing on arrival).
#   Only AF is pulled, not FLAG (gnomAD's own QC filter reasons, e.g.
#   AC0/AS_VQSR). Verified via a controlled test that when a variant has
#   more than one FLAG reason, the file stores them comma-joined
#   (e.g. "AS_VQSR,InbreedingCoeff"), and VEP's CSQ format also uses commas
#   to separate multiple transcript blocks — the two collide, and VEP
#   silently keeps only the last comma-separated value, dropping the rest.
#   AF (a single float, never comma-joined) is unaffected and transfers
#   exactly. Team decision: AF-only, since that's what rarity-based
#   filtering needs and it sidesteps the bug entirely rather than shipping
#   an occasionally-wrong FLAG value.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/VCF_pipeline/002-VEPAnnotation"
INPUT_DIR="$PROJECT_ROOT/VCF_pipeline/001_FilterVCF/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup
REF_DIR="$PROJECT_ROOT/references"

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_VCF="$INPUT_DIR/${SAMPLE}.PASS.vcf.gz"

REFERENCE_GENOME="$REF_DIR/genome/Homo_sapiens_assembly38.fasta"
SYNONYMS="$REF_DIR/genome/GRCh38_chr_synonyms.tsv"
VEP_CACHE_DIR="$REF_DIR/vep_cache"
CLINVAR_FILE="$REF_DIR/clinvar/clinvar_GRCh38.raw.vcf.gz"   # non-chr-prefixed — matches INPUT_VCF/cache, see note above
GNOMAD_FILE="${GNOMAD_FILE:-$REF_DIR/gnomAD/gnomad.genomes.v3.1.2.short.vcf.gz}"   # chr-prefixed — needs SYNONYMS, see note above

SPECIES="homo_sapiens"
CACHE_VERSION="116"   # matches installed ensembl-vep 116.1 and references/vep_cache/homo_sapiens/116_GRCh38
ASSEMBLY="GRCh38"

CPUS="${CPUS:-4}"
MEM="${MEM:-n/a}"   # logged in the manifest only — VEP has no hard memory-cap flag; watch `free`/`top` during the run

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

for f in "$INPUT_VCF" "$REFERENCE_GENOME" "$SYNONYMS" "$CLINVAR_FILE" "$CLINVAR_FILE.tbi"; do
    if [ ! -e "$f" ]; then
        echo "Error: required file $f does not exist." >&2
        exit 1
    fi
done
if [ ! -d "$VEP_CACHE_DIR/$SPECIES/${CACHE_VERSION}_${ASSEMBLY}" ]; then
    echo "Error: VEP cache dir $VEP_CACHE_DIR/$SPECIES/${CACHE_VERSION}_${ASSEMBLY} does not exist." >&2
    exit 1
fi

CUSTOM_ARGS=(--custom "file=${CLINVAR_FILE},short_name=ClinVar,format=vcf,type=exact,coords=0,fields=CLNSIG%CLNREVSTAT")
if [ -n "$GNOMAD_FILE" ]; then
    if [ ! -e "$GNOMAD_FILE" ] || [ ! -e "$GNOMAD_FILE.tbi" ]; then
        echo "Error: GNOMAD_FILE=$GNOMAD_FILE or its .tbi index does not exist." >&2
        exit 1
    fi
    CUSTOM_ARGS+=(--custom "file=${GNOMAD_FILE},short_name=gnomAD,format=vcf,type=exact,coords=0,fields=AF")
else
    echo "Warning: GNOMAD_FILE not set — no gnomAD file found on this drive." >&2
    echo "         Annotating without population allele frequency. See script header." >&2
fi

mkdir -p "$MODULE_DIR/results"

OUT_VCF="$MODULE_DIR/results/vep_${SAMPLE}.PASS.vcf.gz"

if [ -s "$OUT_VCF" ] && [ -s "$OUT_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$OUT_VCF already present — skipping (FORCE=1 to redo)."
else
    # "${CUSTOM_ARGS[@]}" below expands to ClinVar always, plus gnomAD only
    # if GNOMAD_FILE is set — built above (~line 108).
    run_and_log "$MODULE_DIR" "$CONTAINER" "$CPUS" "$MEM" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        vep -i "$INPUT_VCF" \
            --cache_version "$CACHE_VERSION" \
            --vcf \
            -t SO \
            --format vcf \
            --buffer_size 50000 \
            --offline \
            --symbol \
            -o "$OUT_VCF" \
            --cache \
            --dir "$VEP_CACHE_DIR" \
            --species "$SPECIES" \
            --biotype \
            --sift b \
            --flag_pick_allele_gene \
            --canonical \
            --hgvs \
            --shift_hgvs 1 \
            --mane \
            --numbers \
            --protein \
            --polyphen p \
            --transcript_version \
            --domains \
            --assembly "$ASSEMBLY" \
            --fasta "$REFERENCE_GENOME" \
            --synonyms "$SYNONYMS" \
            --compress_output bgzip \
            "${CUSTOM_ARGS[@]}" \
            --show_ref_allele \
            --fork "$CPUS" \
            --force_overwrite

    run_and_log "$MODULE_DIR" "$CONTAINER" "1" "n/a" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        tabix -f -p vcf "$OUT_VCF"
fi

echo
echo "Done. Annotated VCF: $OUT_VCF"
