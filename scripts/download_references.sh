#!/usr/bin/env bash
# Downloads reference data for variant calling/annotation, all pinned to
# GRCh38 (must match whatever build the challenge dataset uses — double check
# against the hackathon's dataset docs before running this).
#
# Uses Broad Institute's public GATK resource bundle for the genome + BWA
# index + dbSNP, instead of building a BWA index locally: bwa index on the
# full genome needs ~16-17GB RAM at peak, which no 8GB laptop can do, no
# matter how the VM is tuned. Broad's bundle ships a pre-built index, so
# nothing memory-heavy runs on this machine at all.
#
# Run from the project root, inside the VM/container, with the SSD mounted:
#   bash scripts/download_references.sh
#
# Pulls into ./references/: genome + BWA index (~8.9GB), dbSNP
# (Broad's dbsnp138, ~1.6GB — much smaller than NCBI's full raw dump, and
# already in the same chr-prefixed contig naming as the genome), ClinVar
# (<1GB), VEP cache (~20GB). ~30-35GB total, one-time, do it on wifi you
# trust. URLs verified live (Aug 2026) against the current public bucket
# listing and NCBI FTP layout.
#
# IMPORTANT — contig naming: this bundle's genome/dbSNP use "chr1"/"chr2"/
# "chrM" naming (the Broad/UCSC convention). NCBI's ClinVar VCF uses plain
# "1"/"2"/"MT" (the Ensembl/NCBI convention) — this script renames ClinVar's
# contigs to match after downloading it, via bcftools + the mapping file
# this script generates. If you later feed a VCF into VEP's offline cache
# (which is Ensembl-based, i.e. non-chr-prefixed), you'll hit the same
# mismatch there — strip the "chr" prefix first (the reverse of what this
# script does for ClinVar) or use VEP's --synonyms option; not yet
# automated here, flag it if we hit it.

set -euo pipefail

REF_DIR="${1:-./references}"
mkdir -p "$REF_DIR"/{genome,dbsnp,clinvar,vep_cache}

BROAD_BASE="https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0"

# NOTE: all "already downloaded?" checks below use `-s` (exists AND
# non-empty), not `-f` — a run interrupted mid-download/mid-transform can
# leave a truncated or zero-byte file behind, and `-f` alone would mistake
# that for "done" on the next run and silently skip regenerating it.

echo "=== 1/4: GRCh38 reference genome + pre-built BWA index (Broad resource bundle) ==="
GENOME_FA="$REF_DIR/genome/Homo_sapiens_assembly38.fasta"
if [ ! -s "$GENOME_FA" ]; then
    wget -O "$GENOME_FA" "$BROAD_BASE/Homo_sapiens_assembly38.fasta"
fi
for ext in fai; do
    [ -s "$GENOME_FA.$ext" ] || wget -O "$GENOME_FA.$ext" "$BROAD_BASE/Homo_sapiens_assembly38.fasta.$ext"
done
[ -s "$REF_DIR/genome/Homo_sapiens_assembly38.dict" ] || \
    wget -O "$REF_DIR/genome/Homo_sapiens_assembly38.dict" "$BROAD_BASE/Homo_sapiens_assembly38.dict"
# Pre-built BWA index (64-bit format, required for a genome this size) —
# no local `bwa index` run needed.
for ext in 64.alt 64.amb 64.ann 64.bwt 64.pac 64.sa; do
    [ -s "$GENOME_FA.$ext" ] || wget -O "$GENOME_FA.$ext" "$BROAD_BASE/Homo_sapiens_assembly38.fasta.$ext"
done

echo "=== 2/4: dbSNP (Broad's dbsnp138, GRCh38, chr-prefixed to match the genome) ==="
DBSNP_VCF="$REF_DIR/dbsnp/Homo_sapiens_assembly38.dbsnp138.vcf.gz"
if [ ! -s "$DBSNP_VCF" ]; then
    wget -O "$DBSNP_VCF" "$BROAD_BASE/Homo_sapiens_assembly38.dbsnp138.vcf.gz"
    wget -O "$DBSNP_VCF.tbi" "$BROAD_BASE/Homo_sapiens_assembly38.dbsnp138.vcf.gz.tbi"
fi

echo "=== 3/4: ClinVar (GRCh38, NCBI) — rename contigs to match chr-prefixed genome ==="
CLINVAR_RAW="$REF_DIR/clinvar/clinvar_GRCh38.raw.vcf.gz"
CLINVAR_VCF="$REF_DIR/clinvar/clinvar_GRCh38.vcf.gz"
DICT="$REF_DIR/genome/Homo_sapiens_assembly38.dict"
if [ ! -s "$CLINVAR_RAW" ]; then
    wget -O "$CLINVAR_RAW" "https://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh38/clinvar.vcf.gz"
fi
if [ ! -s "$CLINVAR_VCF" ]; then
    # ClinVar's VCF ships with NO ##contig header lines at all, and uses
    # plain "1"/"MT" contig names — `bcftools annotate --rename-chrs` needs
    # a header to validate against, which this file doesn't have, so we
    # rewrite contigs directly with awk instead (portable/mawk-safe: no
    # gawk-only features) and inject proper ##contig lines pulled from the
    # genome's own .dict, so the result is a fully well-formed, matching
    # VCF rather than just a text substitution.
    CONTIG_HDR="$REF_DIR/clinvar/contig_header.txt"
    awk -F'\t' '
        /^@SQ/ {
            id=""; ln=""
            for (i=1;i<=NF;i++) {
                if ($i ~ /^SN:/) { sub(/^SN:/,"",$i); id=$i }
                if ($i ~ /^LN:/) { sub(/^LN:/,"",$i); ln=$i }
            }
            if (id ~ /^chr([0-9]+|[XYM])$/) print "##contig=<ID=" id ",length=" ln ">"
        }
    ' "$DICT" > "$CONTIG_HDR"

    zcat "$CLINVAR_RAW" | awk -F'\t' -v OFS='\t' -v contigfile="$CONTIG_HDR" '
        /^##/ { print; next }
        /^#CHROM/ {
            while ((getline line < contigfile) > 0) print line
            print
            next
        }
        {
            c = $1
            if (c == "MT") c = "chrM"
            else c = "chr" c
            $1 = c
            print
        }
    ' | bgzip > "$CLINVAR_VCF"
    tabix -p vcf "$CLINVAR_VCF"
    rm -f "$CONTIG_HDR"
fi

echo "=== 4/4: VEP offline cache (GRCh38) ==="
# No --CACHE_VERSION pin: vep_install auto-matches the cache to the installed
# vep binary's own version, which is what actually needs to match.
# Note: this cache is Ensembl-based (non-chr-prefixed contigs) — see the
# contig-naming note at the top of this file before annotating a VCF that
# came from the chr-prefixed genome/dbSNP above.
if [ ! -d "$REF_DIR/vep_cache/homo_sapiens" ]; then
    # vep_install's default downloader uses Perl's Net::FTP, whose
    # control-connection timeout is too short for a multi-hour transfer of
    # this ~27GB file over a slow/unstable link — it repeatedly killed the
    # whole install partway through with "Timeout at .../Net/FTP.pm line
    # 581", discarding all progress each time (no resume), and on at least
    # one run reported success while having silently truncated the file.
    # --USE_HTTPS_PROTO avoids Net::FTP but needs the HTML::TableExtract
    # Perl module, which isn't in /opt/vep-env — it fails silently (exit 0,
    # "Skipping cache installation") rather than erroring, so it's not a
    # usable fix without a container rebuild.
    #
    # Instead: fetch the tarball ourselves with `wget -c` (real HTTP
    # client, resumable, verifies size against Content-Length), then
    # extract it exactly where vep_install would have.
    VEP_CACHE_URL="https://ftp.ensembl.org/pub/release-116/variation/indexed_vep_cache/homo_sapiens_vep_116_GRCh38.tar.gz"
    VEP_TARBALL="$REF_DIR/vep_cache/homo_sapiens_vep_116_GRCh38.tar.gz"
    wget -c -O "$VEP_TARBALL" "$VEP_CACHE_URL"
    tar -xzf "$VEP_TARBALL" -C "$REF_DIR/vep_cache"
    rm -f "$VEP_TARBALL"
fi

echo "Done. Contents:"
du -sh "$REF_DIR"/*/*
