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

process alignment {
    tag "${sample_id}"

    // publishDir "${params.outdir}/bam", mode: "copy"

    input:
    tuple val(sample_id), path(fastq1), path(fastq2)
    path(ref_genome)

    output:
    path("${sample_id}.bam{,.bai}")

    script:
    """
    RG=\$(split_id.sh ${sample_id} ${params.platform})
    # bwa index ${ref_genome} # Uncomment if skipped bwa index download
    bwa mem -t ${task.cpus} \
        -R \$RG \
        ${ref_genome}/${params.ref_genome_file} ${fastq1} ${fastq2} \
        | samtools view -b -o ${sample_id}_unsorted.bam
    samtools sort -@ ${task.cpus} -o ${sample_id}.bam ${sample_id}_unsorted.bam
    samtools index -@ ${task.cpus} ${sample_id}.bam
    """
}

process merge_bams {
    publishDir "${params.outdir}/bam", mode: "copy"

    input:
    path(bams)

    output:
    path("merged.bam{,.bai}")
    path("merged.flagstat.txt")

    script:
    bam_files = bams.findAll { it.name.endsWith('.bam') }
    """
    samtools merge -@ ${task.cpus} -o merged.bam ${bam_files.join(' ')}
    samtools index -@ ${task.cpus} merged.bam
    samtools flagstat -@ ${task.cpus} merged.bam > merged.flagstat.txt
    """
}

process mark_duplicates {
    publishDir "${params.outdir}/bam", mode: "copy"

    input:
    path(bam)

    output:
    path("dupmarked.bam{,.bai}")
    path("picard_metrics.txt")
    path("dupmarked.flagstat.txt")

    script:
    bam_file = bam.find { it.name.endsWith('.bam') }
    """
    picard MarkDuplicates I=${bam_file} O=dupmarked.bam \
        OPTICAL_DUPLICATE_PIXEL_DISTANCE=${params.optical_dup_pixel_dist} \
        VALIDATION_STRINGENCY=LENIENT \
        M=picard_metrics.txt CREATE_INDEX=true
    samtools flagstat -@ ${task.cpus} dupmarked.bam > dupmarked.flagstat.txt
    """
}

process bqsr {
    publishDir "${params.outdir}/bqsr", mode: "copy"

    input:
    path(bam)
    path(ref_genome)
    path(dbsnp)
    path(known_sites)

    output:
    path("bqsr.bam")

    script:
    bam_file = bam.find { it.name.endsWith('.bam') }
    """
    gatk BaseRecalibrator -I ${bam_file} -O recal_data.table \
        -R ${ref_genome}/${params.ref_genome_file} \
        -known-sites ${dbsnp}/${params.dbsnp_file} \
        -known-sites ${known_sites}/${params.known_indels_file} \
        -known-sites ${known_sites}/${params.mills_file}
    gatk ApplyBQSR -R ${ref_genome}/${params.ref_genome_file} \
        -I ${bam_file} -O bqsr.bam --bqsr-recal-file recal_data.table \
    """
}

// process haplotype {

// }

process vcf_filter {
    publishDir "${params.outdir}/vcf", mode: "copy"

    input:
    path(vcf)

    output:
    path("filtered.vcf")

    script:
    """
    bcftools filter -i FILTER=PASS --threads ${task.cpus} -Oz -o 'filtered.vcf' '${vcf}'
    bcftools index -t --threads ${task.cpus} 'filtered.vcf'
    """
}

process annotation {
    tag "${vcf.simpleName}"

    publishDir "${params.outdir}/vep", mode: "copy"

    input:
    path(vcf)
    path(ref_genome)
    path(vep_cache)
    path(gnomad)
    path(clinvar)
    path(dbsnp)

    output:
    path("${vcf_out}")

    script:
    custom_clinvar = "--custom ${clinvar},ClinVar,vcf,exact,0,CLNSIG,CLNREVSTAT"
    custom_gnomad = "--custom ${gnomad},gnomAD,vcf,exact,0,FLAG,AF"
    custom_dbsnp = dbsnp.name != "NO_FILE" ? "--custom ${dbsnp},dbSNP,vcf,exact,0," : "" // optional
    vcf_out = "vep_${vcf.simpleName}"
    """
    vep -i ${vcf} \
        -o ${vcf_out} \
        --cache_version ${params.vep.cache_version} \
        --cache --dir ${vep_cache} --fasta ${ref_genome} \
        --species ${params.vep.species} --assembly ${params.vep.assembly}  \
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

workflow preprocess {
    Channel.fromFilePairs("${params.fastqDir}/*_{R1,R2}*.fastq.gz", flat: true)
        .set { fastq_pairs_ch }

    alignment(fastq_pairs_ch, file(params.ref_genome_dir))
    merge_bams(alignment.out.collect()) // all bams, only one patient
    mark_duplicates(merge_bams.out[0])
    if (params.run_bqsr) {
        bqsr(
            mark_duplicates.out[0],
            file(params.ref_genome_dir),
            file(params.dbsnp_dir),
            file(params.known_sites_dir)
        )
    }
}

// Default entrypoint
workflow {
    qc()
    preprocess()
}
