#!/usr/bin/env nextflow

nextflow.enable.dsl=2

process fastqc {
    tag "${sample_id}"

    publishDir "${params.outdir}/fastqc", mode: "copy"

    input:
    tuple val(sample_id), path(gz_file)
    
    output:
    path("${sample_id}_fastqc.zip")

    script:
    """
    fastqc --threads ${task.cpus} ${gz_file}
    """
}

process multiqc {
    publishDir "${params.outdir}/multiqc", mode: "copy"

    input:
    path(fastqc_outs)

    output:
    path("multiqc_report.html")

    script:
    """
    multiqc .
    """
}

// @TODO: add reference download process

process vep {
    publishDir "${params.outdir}/vep", mode: "copy"

    input:
    tuple path(vcf), path(ref_genome), path(vep_cache), path(gnomad), path(clinvar), path(dbsnp), val(ens_ver), val(assembly), val(species)

    output:
    path("${vcf_out}")

    script:
    custom_clinvar = "--custom ${clinvar},ClinVar,vcf,exact,0,CLNSIG,CLNREVSTAT"
    custom_dbsnp = dbsnp.name != "NO_FILE" ? "--custom ${dbsnp},dbSNP,vcf,exact,0," : ""
    custom_gnomad = "--custom ${gnomad},gnomAD,vcf,exact,0,FLAG,AF"
    vcf_out = "vep_${vcf.simpleName}"
    """
    vep -i ${vcf} \
        -o ${vcf_out} \
        --cache_version ${ens_ver} \
        --cache --dir ${vep_cache} --fasta ${ref_genome} \
        --species ${species} --assembly ${assembly}  \
        ${custom_clinvar} ${custom_dbsnp} ${custom_gnomad} \
        --compress_output bgzip --show_ref_allele --fork 6 --force_overwrite \
        --vcf -t SO --format vcf --buffer 50000 --offline --symbol \
        --biotype --sift b --flag_pick_allele_gene --canonical --hgvs --shift_hgvs 1 \
        --mane --numbers --protein --polyphen p --transcript_version --domains
    tabix -f -p vcf ${vcf_out}
    """

}

workflow qc {
    Channel.fromPath("${params.fastqDir}/*.fastq.gz")
        .map { file -> record(id: file.simpleName, fastq: file) }
        .set { fastq_ch }

    fastqc(fastq_ch)

    multiqc(fastqc.out.collect())
}

// Default entrypoint
workflow {
    qc()
}
