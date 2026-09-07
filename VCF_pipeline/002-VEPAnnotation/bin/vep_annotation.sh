#!/bin/bash
set -euo pipefail

export PROJECTDIR=[tu path del hackaton]
export ANNOTATION_DIR=${PROJECTDIR}/analysis/annotation/
export LOG_DIR=${ANNOTATION_DIR}/logs/vep_annotation


cd ${PROJECTDIR}

export INPUT_VCF=${PROJECTDIR}/[el vcf aqui]


echo $(date)
echo 'Running VEP annotation'
echo "Input VCF: ${INPUT_VCF:?unset}"
echo "PROJECTDIR: ${PROJECTDIR:?unset}"

#[carga bcftools y vep aqui si hace falta, depende de como los hayas instalado]


export reference_genome="genome.fa" ### agrega el path y nombre correcto de la referencia
export vep_cache="/vep_cache" ## path del cache de vep (recuerda que el cache debe coincidir con la version de vep si no crashea)
export gnomadfile="/gnomad.genomes.v3.1.2.short.vcf.gz" 
export clinvarfile="/clinvar_20230121.chr.canonical.vcf.gz"
export dbsnpfile="/dbSNP155.GRCh38.GCF_000001405.39.mod.vcf.gz"

#De los tres anteriores hay que poner el nombre de la base de datos que hayas descargado y su path, los mas importantes aqui son clinvar y gnomad, dbsnp lo podemos obviar

export species="homo_sapiens"
export ens_ver="103". ## seguramente instalaste una version mucho mas reciente asi que hay que ajustar aqui
export assembly="GRCh38" ## este si supongo es igual si alineaste al 38

echo $(date)
echo "Checking input file and required resources for VEP annotation"
# Check directories
if [[ -z ${INPUT_VCF:?unset} ]]; then
	echo -e "\nUsage: $0 input_vcf_file.vcf.gz \n"
	exit 0
fi

if [[ ! -e ${INPUT_VCF:?unset} ]]; then
	echo "Input VCF file ${INPUT_VCF:?unset} does not exist"
	exit 1
fi

# Check input files and directories
for d in ${vep_cache}; do
	if [[ ! -d ${d} ]]; then
		echo "Directory ${d} does not exist"
		exit 1
	fi
done
for annotfile in ${reference_genome:?unset} ${gnomadfile:?unset} ${clinvarfile:?unset} ${dbsnpfile:?unset} ${cosmicfile:?unset}; do
	if [[ ! -e ${annotfile} ]]; then
		echo "File ${annotfile} does not exist"
		exit 1
	fi
done
# EN la parte anterior ajusta si no pones alguno de las bases de datos previas. 

# Aqui tambbién hay que ajustar dependiendo de las bases de datos que hayas descargado
custom="--custom ${cosmicfile},Cosmic,vcf,exact,0,CNT --custom ${clinvarfile},ClinVar,vcf,exact,0,CLNSIG,CLNREVSTAT --custom ${dbsnpfile},dbSNP,vcf,exact,0, --custom ${gnomadfile},gnomAD,vcf,exact,0,FLAG,AF"

# Submit jobs
outdir=${ANNOTATION_DIR}/vep_output
filename=`basename ${INPUT_VCF}`
vcf_out=${outdir:?unset}/vep_${filename:?unset}

echo $(date)
echo "Running VEP annotation for ${INPUT_VCF}"

##	echo "$outdir $filename $vcf_out $f"
vep -i ${INPUT_VCF} \
 --cache_version ${ens_ver} \
 --vcf \
 -t SO \
 --format vcf \
 --buffer 50000 \
 --offline \
 --symbol \
 -o ${vcf_out} \
 --cache \
 --dir ${vep_cache} \
 --species ${species} \
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
 --assembly ${assembly:?unset} \
 --fasta ${reference_genome} \
 --compress_output bgzip \
 ${custom} \
 --show_ref_allele \
 --fork 6 \
 --force_overwrite 

echo $(date)
echo "Indexing annotated VCF with tabix"
tabix -f -p vcf ${vcf_out}

echo $(date)
echo "Annotated VCF file: ${vcf_out}"