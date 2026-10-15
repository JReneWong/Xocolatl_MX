#!/usr/bin/env bash

# Following https://github.com/gatk-workflows/gatk3-data-processing/blob/ba011a0c72b89b76fe45c129dba12fb436764cec/processing-for-variant-discovery-gatk3.hg38.wgs.inputs.json

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
mkdir -p "$REF_DIR"/{genome,dbsnp,clinvar,vep_cache,known_sites}

# Download genome
# 3.2GB + 488KB + 20KB + 455KB + 3.22GB + 804.3MB + 1.61GB
echo "Downloading GRCh38 reference genome + pre-built BWA index"
GENOME_FA="$REF_DIR/genome/Homo_sapiens_assembly38"
download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta" "$GENOME_FA.fasta"
# Pre-built BWA index
# otherwise run `bwa index` command
for ext in 64.alt 64.amb 64.ann 64.bwt 64.pac 64.sa; do
    download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta.$ext" "$GENOME_FA.fasta.$ext"
done
# .fai and .dict for gatk
download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta.fai" "$GENOME_FA.fasta.fai"
download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dict" "$GENOME_FA.dict"

# Download dbSNP
# 1.6GB + 2.3MB
echo "Downloading dbSNP "
DBSNP_VCF="$REF_DIR/dbsnp/Homo_sapiens_assembly38.dbsnp138.vcf.gz"
download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dbsnp138.vcf.gz" "$DBSNP_VCF"
download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dbsnp138.vcf.gz.tbi" "$DBSNP_VCF.tbi"

# Download ClinVar
# 184MB
echo "Downloading ClinVar"
CLINVAR_VCF="$REF_DIR/clinvar/clinvar_GRCh38.vcf.gz"
download "https://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh38/clinvar.vcf.gz" "$CLINVAR_VCF"
download "https://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh38/clinvar.vcf.gz.tbi" "$CLINVAR_VCF.tbi"

# Download VEP cache
# 26GB
echo "Downloading VEP cache"
VEP_CACHE="$REF_DIR/vep_cache/homo_sapiens_vep_116_GRCh38.tar.gz"
download "https://ftp.ensembl.org/pub/release-116/variation/indexed_vep_cache/homo_sapiens_vep_116_GRCh38.tar.gz" "$VEP_CACHE"
echo "Extracting VEP cache"
tar -xzf "$VEP_CACHE" -C "$REF_DIR/vep_cache"
rm -rf "$VEP_CACHE"

# Download known sites VCF
# 63MB
echo "Downloading known indels VCF"
KNOWN_INDELS_VCF="$REF_DIR/known_sites/Homo_sapiens_assembly38.known_indels.vcf.gz"
download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.known_indels.vcf.gz" "$KNOWN_INDELS_VCF"
download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.known_indels.vcf.gz.tbi" "$KNOWN_INDELS_VCF.tbi"
# 22MB
echo "Downloading Mills VCF"
MILLS_VCF="$REF_DIR/known_sites/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz"
download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz" "$MILLS_VCF"
download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz.tbi" "$MILLS_VCF.tbi"
# 62MB
echo "Downloading HapMap VCF"
HAPMAP_VCF="$REF_DIR/known_sites/HapMap_3.3.hg38.vcf.gz"
download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/hapmap_3.3.hg38.vcf.gz" "$HAPMAP_VCF"
download "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/hapmap_3.3.hg38.vcf.gz.tbi" "$HAPMAP_VCF.tbi"

echo "Done"
