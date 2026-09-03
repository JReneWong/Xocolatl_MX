#!/usr/bin/env nextflow

nextflow.enable.dsl=2

process fastqc {
    tag "${sample_id}"

    publishDir "${params.outdir}/fastqc", mode: "copy"

    input:
    tuple val(sample_id), path(gz_file)
    
    output:
    tuple val(sample_id), path("${sample_id}.fastq.out") // @TODO

    script:
    """
    # fastqc --threads ${task.cpus} ${gz_file}
    touch ${sample_id}.fastq.out # temp
    fastqc --help
    """
}

process multiqc {
    tag "${sample_id}"

    publishDir "${params.outdir}/multiqc", mode: "copy"

    input:
    tuple val(sample_id), path(fastqc_output)

    output:
    tuple val(sample_id), path("${sample_id}.multiqc_report.html") // @TODO

    script:
    """
    # multiqc ${fastqc_output} --force
    touch ${sample_id}.multiqc_report.html # temp
    multiqc --help
    """
}

workflow qc {
    Channel.fromPath("${params.fastq}")
        .map { file -> tuple(file.simpleName, file) }
        .set { fastq_ch }

    fastqc(fastq_ch)

    multiqc(fastqc.out)
}

// Default entrypoint
workflow {
    qc()
}
