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
