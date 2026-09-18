#!/usr/bin/env nextflow

nextflow.enable.dsl=2

process fastqc {
    tag "${sample_id}"

    publishDir "${params.outdir}/qc", mode: "copy"

    input:
    tuple val(sample_id), path(fastqs)
    
    output:
    path("*_fastqc.zip")

    script:
    """
    fastqc --threads ${task.cpus} ${fastqs[0]} ${fastqs[1]}
    """
}

process multiqc {
    publishDir "${params.outdir}/qc", mode: "copy"

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
    tuple val(sample_id), val(lane), path(fastqs)
    path(ref_genome)

    output:
    path("${sample_id}.bam{,.bai}")

    script:
    lane_str=lane.size() ? ".${lane}" : ""
    RG="@RG\\tID:${sample_id}${lane_str}\\tSM:${sample_id}\\tPL:${params.platform}"
    """
    # bwa index ${ref_genome} # Uncomment if skipped bwa index download
    bwa mem -t ${task.cpus} \
        -R "${RG}" \
        ${ref_genome}/${params.ref_genome_file} ${fastqs[0]} ${fastqs[1]} \
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
        M=picard_metrics.txt
    samtools index -@ ${task.cpus} dupmarked.bam
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
    path("bqsr.bam{,.bai}")

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
    tag "${bam_file.simpleName}_${contig}"

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

process nvscore {
    publishDir "${params.outdir}/nvscore", mode: "copy"

    input:
    path(bam)
    path(vcf)
    path(ref_genome)
    path(known_sites)

    output:
    path("${vcf_out}{,.tbi}")

    script:
    bam_file = bam.find { it.name.endsWith('.bam') }
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    vcf_out = "cnn_filter.PASS.vcf.gz"
    """
    gatk NVScoreVariants -I ${bam_file} -V ${vcf_file} \
        -R ${ref_genome}/${params.ref_genome_file} \
        -tensor-type read_tensor \
        -O cnn_scored.vcf.gz
    bcftools index -t --threads ${task.cpus} cnn_scored.vcf.gz
    gatk FilterVariantTranches -V cnn_scored.vcf.gz --info-key CNN_2D \
        --snp-tranche ${params.nvscore.snp_tranche} --indel-tranche ${params.nvscore.indel_tranche} \
        --resource ${known_sites}/${params.hapmap_file} \
        --resource ${known_sites}/${params.mills_file} \
        --invalidate-previous-filters \
        -O cnn_filter.vcf.gz
    bcftools view -i 'FILTER="PASS"' \
        --threads ${task.cpus} -Oz -o ${vcf_out} cnn_filter.vcf.gz
    bcftools index -t --threads ${task.cpus} ${vcf_out}
    """
}

process variant_filtration {
    publishDir "${params.outdir}/variant_filtration", mode: "copy"

    input:
    path(vcf)
    path(genome)

    output:
    path("${vcf_out}{,.tbi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    vcf_out = "filtered.vcf.gz"
    """
    gatk VariantFiltration -V ${vcf_file} \
        -R ${genome}/${params.ref_genome_file} \
        -O ${vcf_out} \
        --filter-expression 'QD < 2.0' --filter-name QD2 \
        --filter-expression 'MQ < 40.0' --filter-name MQ40 \
        --filter-expression 'ReadPosRankSum < -8.0' --filter-name RPRS-8 \
        --filter-expression 'FS > 60.0' --filter-name FS60 \
        --filter-expression 'MQRankSum < -12.5' --filter-name MQRankSum-12.5
    """
}

process vcf_filter {
    publishDir "${params.outdir}/vcf", mode: "copy"

    input:
    tuple val(id), path(vcf)

    output:
    tuple val(id), path("${vcf_out}{,.tbi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    vcf_out = "filtered-${id}.PASS.vcf.gz"
    """
    bcftools filter -i 'FILTER="PASS"' \
        --threads ${task.cpus} -Oz -o '${vcf_out}' '${vcf_file}'
    bcftools index -t --threads ${task.cpus} '${vcf_out}'
    """
}

process vep_annotation {
    tag "${id}"

    publishDir "${params.outdir}/vep", mode: "copy"

    input:
    tuple val(id), path(vcf)
    path(ref_genome)
    path(vep_cache)
    path(gnomad)
    path(clinvar)
    path(chrom_map)

    output:
    tuple val(id), path("${vcf_out}{,.tbi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    custom_clinvar = "--custom file=${clinvar}/${params.clinvar_file},short_name=ClinVar,format=vcf,type=exact,coords=0,fields=CLNSIG%CLNREVSTAT"
    custom_gnomad = "--custom file=${gnomad}/${params.gnomad_file},short_name=gnomAD,format=vcf,type=exact,coords=0,fields=AF"
    vcf_out = "vep-${id}.PASS.vcf.gz"
    """
    # @TODO: move params to config file
    vep -i ${vcf_file} \
        -o ${vcf_out} \
        --cache_version ${params.vep.cache_version} \
        --cache --dir ${vep_cache} --fasta ${ref_genome}/${params.ref_genome_file} \
        --species ${params.vep.species} --assembly ${params.vep.assembly}  \
        ${custom_clinvar} ${custom_gnomad} \
        --vcf -t SO --format vcf --buffer 50000 --offline --symbol \
        --compress_output bgzip --show_ref_allele --fork 6 --force_overwrite \
        --biotype --sift b --flag_pick_allele_gene --canonical --hgvs --shift_hgvs 1 \
        --mane --numbers --protein --polyphen p --transcript_version --domains \
        --synonyms ${chrom_map}
    tabix -f -p vcf ${vcf_out}
    """
}

process split_vep {
    tag "${id}"

    // publishDir "${params.outdir}/vep", mode: "copy"

    input:
    tuple val(id), path(vcf)

    output:
    tuple val(id), path("${vcf_out}{,.tbi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    vcf_out = "splitvep-${id}.PASS.vcf.gz"
    """
    bcftools +split-vep -c Consequence,IMPACT,SYMBOL,Gene,SIFT,PolyPhen,ClinVar_CLNSIG,Existing_variation,gnomAD_AF \
        -s worst -p vep '${vcf_file}' \
        | bcftools annotate -x 'INFO/CSQ' \
        -Oz -o '${vcf_out}'
    bcftools index -t --threads ${task.cpus} '${vcf_out}'
    """
}

process lowfreqvar {
    tag "${id}"

    publishDir "${params.outdir}/vep", mode: "copy"

    input:
    tuple val(id), path(vcf)

    output:
    tuple val(id), path("${vcf_out}{,.tbi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    vcf_out = "rarevars-${id}.PASS.vcf.gz"
    """
    bcftools view -i 'INFO/vepgnomAD_AF="." || INFO/vepgnomAD_AF < ${params.af_threshold}' \
        --threads ${task.cpus} -Oz -o '${vcf_out}' '${vcf_file}'
    bcftools index -t --threads ${task.cpus} '${vcf_out}'
    """
}

process synonymous_mutations {
    tag "${id}"

    publishDir "${params.outdir}/vep", mode: "copy"

    input:
    tuple val(id), path(vcf)

    output:
    tuple val(id), path("${vcf_out}{,.tbi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    vcf_out = "functional-${id}.PASS.vcf.gz"
    """
    bcftools view \
        -i 'INFO/vepConsequence ~ "missense_variant" || \
        INFO/vepConsequence ~ "frameshift_variant" || \
        INFO/vepConsequence ~ "stop_gained" || \
        INFO/vepConsequence ~ "stop_lost" || \
        INFO/vepConsequence ~ "start_lost" || \
        INFO/vepConsequence ~ "splice_acceptor_variant" || \
        INFO/vepConsequence ~ "splice_donor_variant" || \
        INFO/vepConsequence ~ "splice_region_variant" || \
        INFO/vepConsequence ~ "inframe_insertion" || \
        INFO/vepConsequence ~ "inframe_deletion"' \
        --threads ${task.cpus} -Oz -o '${vcf_out}' '${vcf_file}'
    bcftools index -t --threads ${task.cpus} '${vcf_out}'
    """
}

process sift_polyphen {
    tag "${id}"

    publishDir "${params.outdir}/vep", mode: "copy"

    input:
    tuple val(id), path(vcf)

    output:
    tuple val(id), path("${vcf_out}{,.tbi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    vcf_out = "sift_polyphen_filtered-${id}.PASS.vcf.gz"
    """
    bcftools view -e 'INFO/vepSIFT ~ "tolerated" || INFO/vepPolyPhen = "benign"' \
        --threads ${task.cpus} -Oz -o '${vcf_out}' '${vcf_file}'
    bcftools index -t --threads ${task.cpus} '${vcf_out}'
    """
}

process high_impact {
    tag "${id}"

    publishDir "${params.outdir}/vep", mode: "copy"

    input:
    tuple val(id), path(vcf)

    output:
    tuple val(id), path("${vcf_out}{,.tbi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    vcf_out = "high_impact-${id}.PASS.vcf.gz"
    """
    bcftools view \
        -i 'INFO/vepConsequence ~ "stop" || \
        INFO/vepConsequence ~ "frameshift" || \
        INFO/vepConsequence ~ "splice_donor_variant" || \
        INFO/vepConsequence ~ "splice_acceptor_variant" || \
        INFO/vepConsequence ~ "start_lost"' \
        --threads ${task.cpus} -Oz -o '${vcf_out}' '${vcf_file}'
    bcftools index -t --threads ${task.cpus} '${vcf_out}'
    """
}

process moderate_impact {
    tag "${id}"

    publishDir "${params.outdir}/vep", mode: "copy"

    input:
    tuple val(id), path(vcf)

    output:
    tuple val(id), path("${vcf_out}{,.tbi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    vcf_out = "moderate_impact-${id}.PASS.vcf.gz"
    """
    bcftools view \
        -i 'INFO/vepConsequence ~ "missense_variant" || \
        INFO/vepConsequence ~ "inframe_insertion" || \
        INFO/vepConsequence ~ "inframe_deletion"' \
        --threads ${task.cpus} -Oz -o '${vcf_out}' '${vcf_file}'
    bcftools index -t --threads ${task.cpus} '${vcf_out}'
    """
}

process gene_filter {
    tag "${id}"

    publishDir "${params.outdir}/vep", mode: "copy"

    input:
    tuple val(id), path(vcf)
    path(gene_list)

    output:
    tuple val(id), path("${vcf_out}{,.tbi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    vcf_out = "gene_list-${vcf_file.name}"
    """
    FILTER="\$(awk '{printf sep "INFO/vepSYMBOL=\\"%s\\"", \$1; sep=" || "}' \"${gene_list}\")"
    bcftools view -i "\$FILTER" \
        --threads ${task.cpus} -Oz -o '${vcf_out}' '${vcf_file}'
    bcftools index -t --threads ${task.cpus} '${vcf_out}'
    """
}

workflow qc {
    Channel.of(file(params.fastq_samplesheet))
        .flatMap { csv -> csv.splitCsv(header: true) }
        .map { row -> [row.id, [file(row.fastq1), file(row.fastq2)]] }
        .set { fastq_ch }

    fastqc(fastq_ch)

    multiqc(fastqc.out.collect())
}

workflow preprocess {
    Channel.of(file(params.fastq_samplesheet))
        .flatMap { csv -> csv.splitCsv(header: true) }
        .map { row -> [row.id, row.lane, [file(row.fastq1), file(row.fastq2)]] }
        .set { fastq_ch }

    alignment(fastq_ch, file(params.ref_genome_dir))
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
        mark_duplicates.out[0].map{ files -> [files]}.combine(contig_ch),
        file(params.ref_genome_dir),
        file(params.dbsnp_dir)
    )
    merge_vcfs(haplotype.out.collect())

    // @TODO use join or other operator
    nvscore(
        mark_duplicates.out[0],
        merge_vcfs.out[0],
        file(params.ref_genome_dir),
        file(params.known_sites_dir)
    )
    variant_filtration(nvscore.out, file(params.ref_genome_dir))

}

workflow recalling{
    qc()
    preprocess()
}

workflow vcf {
    Channel.of(file(params.vcf_samplesheet))
        .flatMap { csv -> csv.splitCsv(header: true) }
        .map { row -> [row.id, [file(row.vcf), file(row.index)]] }
        .set { vcf_ch }
    
    vcf_filter(vcf_ch)
    vep_annotation(
        vcf_filter.out,
        file(params.ref_genome_dir),
        file(params.vep_cache_dir),
        file(params.gnomad_dir),
        file(params.clinvar_dir),
        file(params.chrom_map)
    )
    split_vep(vep_annotation.out)
    lowfreqvar(split_vep.out)
    synonymous_mutations(lowfreqvar.out)
    sift_polyphen(synonymous_mutations.out)

    high_impact(sift_polyphen.out)
    moderate_impact(sift_polyphen.out)
    
    gene_filter(high_impact.out, file(params.gene_list))
}

workflow {
    if (params.flow == 'recalling') {
        recalling()
    } else if (params.flow == 'vcf') {
        vcf()
    }
}
