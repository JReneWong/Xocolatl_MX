#!/usr/bin/env nextflow

nextflow.enable.dsl=2

process shapeit_common {
    label "shapeit"
    tag "${id}"

    publishDir "${params.outdir}/shapeit", mode: "copy"

    input:
    tuple val(id), path(vcf), path(panel), val(region)

    output:
    tuple val(id), path(vcf), path("${id}-${region}.scaffold.vcf.gz{,.csi}"), val(region)

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    panel_file = panel.find { it.name.endsWith('.vcf.gz') }
    region_chr = region.startsWith("chr") ? region : "chr${region}"
    """
    phase_common --input ${vcf_file} \
        --reference ${panel_file} \
        --map /usr/local/share/shapeit/maps/b38/${region_chr}.b38.gmap.gz \
        --region ${region} \
        --thread ${task.cpus} \
        --output ${id}-${region}.scaffold.vcf.gz
    """
}

process shapeit_rare {
    label "shapeit"
    tag "${id}"

    publishDir "${params.outdir}/shapeit", mode: "copy"

    input:
    tuple val(id), path(vcf), path(scaffold), val(region)
    path(ref_genome)

    output:
    path("${id}-${region}.phased.vcf.gz{,.csi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    scaffold_file = scaffold.find { it.name.endsWith('.vcf.gz') }
    region_chr = region.startsWith("chr") ? region : "chr${region}"
    fai_file = "${ref_genome}/${params.ref_genome_file}.fai"
    """
    CHR_LEN="\$(awk -v c="${region_chr}" '\$1==c {print \$2}' "${fai_file}")"
    FULL_REGION="${region_chr}:1-\$CHR_LEN"
    phase_rare --input ${vcf_file} \
        --scaffold ${scaffold_file} \
        --map /usr/local/share/shapeit/maps/b38/${region_chr}.b38.gmap.gz \
        --input-region \$FULL_REGION --scaffold-region \$FULL_REGION \
        --thread ${task.cpus} \
        --output ${id}-${region}.phased.vcf.gz
    """
}

workflow {
    if (params.flow == "shapeit") {
        Channel.of(file(params.phasing_samplesheet))
            .flatMap { csv -> csv.splitCsv(header: true) }
            .map { row -> [row.id, [file(row.vcf), file(row.vcf_index)], [file(row.panel), file(row.panel_index)], row.region] }
            .set { shapeit_ch }
        
        shapeit_common(shapeit_ch)
        shapeit_rare(shapeit_common.out, file(params.ref_genome_dir))

    }
}
