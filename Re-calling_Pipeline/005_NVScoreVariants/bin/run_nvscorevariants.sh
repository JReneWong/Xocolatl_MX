#!/usr/bin/env bash
# Module 005_NVScoreVariants — GATK4 NVScoreVariants (PyTorch-based CNN,
# -tensor-type read_tensor, the 2D model) scoring 004_HaplotypeCaller's
# raw callset. This step only ANNOTATES: every input record passes
# through unchanged in count, gaining a CNN score in its INFO field — it
# does not populate the FILTER column or drop/keep anything. Deciding
# PASS/FAIL from these scores is a separate later step
# (FilterVariantTranches, which needs truth-set resources not yet in
# references/) — going step by step, per team decision, this module
# stops at scoring.
#
# NVScoreVariants is GATK's replacement for CNNScoreVariants (the tool
# originally proposed), which was removed as of GATK 4.6.1.0 — we're
# pinned to 4.6.2.0. GATK's own error message for the removed tool points
# here, describing it as producing "virtually identical results". Two
# corrections from the originally-proposed command: the tool name itself,
# and the tensor-type value is read_tensor (underscore) not read-tensor
# (hyphen) — confirmed against this tool's own --help output.
#
# The 2D/read_tensor model (vs. the lighter 1D/"reference" model) needs
# actual read-level evidence, hence -I pointing at 003's BAM alongside -V
# for the VCF being scored.
#
# Still marked "BETA FEATURE - WORK IN PROGRESS" in GATK's own --help for
# this tool. Container ships pytorch-cpu now, not tensorflow (which the
# tool this replaces used) — see container/hackathon.def.
#
# Runtime, now measured: ~40.4 hours (2,424 minutes) for ~5M variant
# sites against this ~70GB BAM — roughly 1.8x 004_HaplotypeCaller's own
# ~22 hour runtime, despite only annotating already-called sites rather
# than doing full local reassembly + PairHMM across the whole genome.
# Likely I/O-bound: each variant needs a fresh random-access read pileup
# pulled from the BAM to build its tensor (~22 variants/sec observed,
# with CPU usage well under saturated). No per-region progress meter is
# printed during the run — the only visible progress signal is the
# growing --tmp-file (one line per scored variant so far; compare its
# line count against the input VCF's record count for a % estimate).
#
# Run from the project root:
#   bash Re-calling_Pipeline/005_NVScoreVariants/bin/run_nvscorevariants.sh
#
# Override defaults with env vars, e.g.:
#   JAVA_MEM=8g bash Re-calling_Pipeline/005_NVScoreVariants/bin/run_nvscorevariants.sh
#
# Safe to re-run: skipped if the expected output already exists (set
# FORCE=1 to redo).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$PROJECT_ROOT/Re-calling_Pipeline/005_NVScoreVariants"
BAM_DIR="$PROJECT_ROOT/Re-calling_Pipeline/003_MarkDuplicates/results"    # see data/README.txt — not a symlink on this exFAT+Linux setup
VCF_DIR="$PROJECT_ROOT/Re-calling_Pipeline/004_HaplotypeCaller/results"   # see data/README.txt — not a symlink on this exFAT+Linux setup
REF_FASTA="$PROJECT_ROOT/references/genome/Homo_sapiens_assembly38.fasta"

SAMPLE="WGS_EX2312012_HGWCNDSX7"
INPUT_BAM="$BAM_DIR/${SAMPLE}.dedup.bam"
INPUT_VCF="$VCF_DIR/${SAMPLE}.vcf.gz"

JAVA_MEM="${JAVA_MEM:-4g}"   # orchestration only — the PyTorch inference itself runs outside the JVM heap

source "$PROJECT_ROOT/common/manifest.sh"
CONTAINER="$(resolve_container "$PROJECT_ROOT")"

# data/ is just a documentation stub here (see data/README.txt) — point
# manifests at the real input so provenance is accurate. Two real input
# dirs feed this module (BAM from 003, VCF from 004); MANIFEST_INPUT_DIR
# can only point at one, so it's set to 004's dir since the VCF is this
# module's primary subject — the BAM path is still recorded explicitly
# in the logged command itself.
export MANIFEST_INPUT_DIR="$VCF_DIR"

if [ ! -f "$CONTAINER" ]; then
    echo "Error: $CONTAINER not found. Build it first (see README.md)." >&2
    exit 1
fi

if [ ! -s "$INPUT_BAM" ]; then
    echo "Error: $INPUT_BAM not found. Run 003_MarkDuplicates first." >&2
    exit 1
fi

if [ ! -s "$INPUT_VCF" ]; then
    echo "Error: $INPUT_VCF not found. Run 004_HaplotypeCaller first." >&2
    exit 1
fi

mkdir -p "$MODULE_DIR/results"

TMP_DIR="$MODULE_DIR/results/tmp"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT
mkdir -p "$TMP_DIR"

OUT_VCF="$MODULE_DIR/results/${SAMPLE}.cnn_scored.vcf.gz"

if [ -s "$OUT_VCF" ] && [ -s "$OUT_VCF.tbi" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "$OUT_VCF already present — skipping (FORCE=1 to redo)."
else
    # Unlike every other GATK VCF writer in this pipeline, NVScoreVariants'
    # python-mediated writer does NOT auto-create a .tbi — confirmed by
    # running this for real (a ~40 hour run) and finding no index
    # afterward. Indexing explicitly here, not just for consistency with
    # the rest of the pipeline, but because the skip-check above requires
    # the .tbi to exist: without this step, any future re-run (FORCE=1 or
    # otherwise) would never recognize a completed output and would redo
    # the full ~40 hour computation from scratch every time.
    NVSV_CMD="set -euo pipefail; gatk --java-options '-Xmx$JAVA_MEM -Djava.io.tmpdir=$TMP_DIR' NVScoreVariants \
        -I '$INPUT_BAM' \
        -V '$INPUT_VCF' \
        -R '$REF_FASTA' \
        -O '$OUT_VCF' \
        -tensor-type read_tensor \
        && bcftools index -t '$OUT_VCF'"

    run_and_log "$MODULE_DIR" "$CONTAINER" "n/a" "$JAVA_MEM" -- \
        apptainer exec --bind "$PROJECT_ROOT:$PROJECT_ROOT" "$CONTAINER" \
        bash -c "$NVSV_CMD"
fi

echo
echo "Done. CNN-scored (still unfiltered) VCF: $OUT_VCF"
echo "Same record count as 004's output — check the CNN score annotation in"
echo "INFO; the FILTER column is still unset. FilterVariantTranches (with"
echo "truth-set resources) is the separate next step to turn this into an"
echo "actual PASS/FAIL callset."
