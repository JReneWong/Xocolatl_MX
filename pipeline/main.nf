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

process haplotype {
    tag "${bam.simpleName}_${contig}"

    // publishDir "${params.outdir}/haplotype", mode: "copy"

    input:
    tuple path(bam), val(contig)
    path(ref_genome)
    path(dbsnp)

    output:
    path("chr*.vcf.gz{,.tbi}")

    script:
    bam_file = bam.find { it.name.endsWith('.bam') }
    contig_str = "chr${contig}"
    """
    gatk HaplotypeCaller -I ${bam_file} \
        -R ${ref_genome}/${params.ref_genome_file} \
        -L ${contig_str} \
        --dbsnp ${dbsnp}/${params.dbsnp_file} \
        --native-pair-hmm-threads ${task.cpus} \
        -O ${contig_str}.vcf.gz -OVI
    """
}

process merge_vcfs {
    publishDir "${params.outdir}/haplotype", mode: "copy"

    input:
    path(vcfs)

    output:
    path("merged.vcf.gz{,.tbi}")
    path("merged.vcf.gz.stats.txt")

    script:
    vcf_files = vcfs.findAll { it.name.endsWith('.vcf.gz') }.collect { "I=${it}" }
    """
    picard MergeVcfs ${vcf_files.join(' ')} O=merged.vcf.gz
    bcftools stats merged.vcf.gz > merged.vcf.gz.stats.txt
    """
}

process vcf_filter {
    publishDir "${params.outdir}/vcf", mode: "copy"

    input:
    tuple val(id), path(vcf)

    output:
    path("${vcf_out}{,.tbi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    vcf_out = "filtered.vcf.gz"
    """
    bcftools filter -i 'FILTER="PASS" || FILTER="." ' \
        --threads ${task.cpus} -Oz -o '${vcf_out}' '${vcf_file}'
    bcftools index -t --threads ${task.cpus} '${vcf_out}'
    """
}

process vep_annotation {
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
    path("${vcf_out}{,.tbi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    custom_clinvar = "--custom ${clinvar}/${params.clinvar_file},ClinVar,vcf,exact,0,CLNSIG,CLNREVSTAT"
    custom_gnomad = "--custom ${gnomad}/${params.gnomad_file},gnomAD,vcf,exact,0,FLAG,AF"
    custom_dbsnp = "--custom ${dbsnp}/${params.dbsnp_file},dbSNP,vcf,exact,0,"
    vcf_out = "vep.PASS.vcf.gz"
    """
    # @TODO: move params to config file
    vep -i ${vcf_file} \
        -o ${vcf_out} \
        --cache_version ${params.vep.cache_version} \
        --cache --dir ${vep_cache} --fasta ${ref_genome}/${params.ref_genome_file} \
        --species ${params.vep.species} --assembly ${params.vep.assembly}  \
        ${custom_clinvar} ${custom_dbsnp} ${custom_gnomad} \
        --vcf -t SO --format vcf --buffer 50000 --offline --symbol \
        --compress_output bgzip --show_ref_allele --fork 6 --force_overwrite \
        --biotype --sift b --flag_pick_allele_gene --canonical --hgvs --shift_hgvs 1 \
        --mane --numbers --protein --polyphen p --transcript_version --domains
    tabix -f -p vcf ${vcf_out}
    """
}

process lowfreqvar {
    tag "${vcf.simpleName}"

    publishDir "${params.outdir}/vep", mode: "copy"

    input:
    path(vcf)

    output:
    path("${vcf_out}{,.tbi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    vcf_out = "rarevars-vep.PASS.vcf.gz"
    """
    bcftools +split-vep -c Consequence,IMPACT,SYMBOL,Gene,SIFT,PolyPhen,ClinVar_CLNSIG,Existing_variation,gnomAD_AF \
        -s worst -p vep '${vcf_file}' \
        | bcftools annotate -x 'INFO/CSQ' \
        | bcftools view -i 'INFO/vepgnomAD_AF="." || INFO/vepgnomAD_AF < ${params.af_threshold}' \
        --threads ${task.cpus} -Oz -o '${vcf_out}'
    bcftools index -t --threads ${task.cpus} '${vcf_out}'
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

    // @TODO: implement optional process
    // if (params.run_bqsr) {
    //     bqsr(
    //         mark_duplicates.out[0],
    //         file(params.ref_genome_dir),
    //         file(params.dbsnp_dir),
    //         file(params.known_sites_dir)
    //     )
    // }

    // Define contigs for haplotype calling
    Channel.of(1..22,"X","Y","M")
        .flatten()
        .set { contig_ch }

    haplotype(
        mark_duplicates.out[0].combine(contig_ch),
        file(params.ref_genome_dir),
        file(params.dbsnp_dir)
    )
    merge_vcfs(haplotype.out.collect())
}

workflow recalling{
    qc()
    preprocess()
}

workflow vcf {
    Channel.fromFilePairs("${params.vcf_file}{,.tbi}", flat: false, size: -1)
        .set { vcf_ch }
    
    vcf_filter(vcf_ch)
    vep_annotation(
        vcf_filter.out,
        file(params.ref_genome_dir),
        file(params.vep_cache_dir),
        file(params.gnomad_dir),
        file(params.clinvar_dir),
        file(params.dbsnp_dir)
    )
    lowfreqvar(vep_annotation.out)
}

workflow {
    if (params.flow == 'recalling') {
        recalling()
    } else if (params.flow == 'vcf') {
        vcf()
    }
}
