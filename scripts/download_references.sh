#!/usr/bin/env bash

set -euo pipefail

function download {
    url=$1
    filename=$2

    if [ -s "$filename" ]; then
        echo "$filename already exists, skipping download."
    elif [ -x "$(which wget)" ] ; then
        wget $url -O $filename
    elif [ -x "$(which curl)" ]; then
        curl -o $filename -fL $url
    else
        echo "Could not find curl or wget, please install one." >&2
    fi
}

REF_DIR="./data/references"
mkdir -p "$REF_DIR"/{genome,dbsnp,clinvar,vep_cache}

# Download genome
echo "Downloading GRCh38 reference genome + pre-built BWA index"
GENOME_FA="$REF_DIR/genome/Homo_sapiens_assembly38.fasta"
download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta" "$GENOME_FA"
# Pre-built BWA index
# otherwise run `bwa index` command
for ext in 64.alt 64.amb 64.ann 64.bwt 64.pac 64.sa; do
    download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta.$ext" "$GENOME_FA.$ext"
done

# Download dbSNP
echo "Downloading dbSNP "
DBSNP_VCF="$REF_DIR/dbsnp/Homo_sapiens_assembly38.dbsnp138.vcf.gz"
download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dbsnp138.vcf.gz" "$DBSNP_VCF"
download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dbsnp138.vcf.gz.tbi" "$DBSNP_VCF.tbi"

# Download ClinVar
echo "Downloading ClinVar"
CLINVAR_VCF="$REF_DIR/clinvar/clinvar_GRCh38.vcf.gz"
download "https://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh38/clinvar.vcf.gz" "$CLINVAR_VCF"
download "https://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh38/clinvar.vcf.gz.tbi" "$CLINVAR_VCF.tbi"

# Download VEP cache
echo "Downloading VEP cache"
VEP_CACHE="$REF_DIR/vep_cache/homo_sapiens_vep_116_GRCh38.tar.gz"
download "https://ftp.ensembl.org/pub/release-116/variation/indexed_vep_cache/homo_sapiens_vep_116_GRCh38.tar.gz" "$VEP_CACHE"

echo "Done"
