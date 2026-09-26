#!/usr/bin/env nextflow

nextflow.enable.dsl=2

process normalize_and_filter {
    label "shapeit"
    tag "${id}"

    input:
    tuple val(id), path(vcf), val(region)
    path(ref_genome)

    output:
    tuple val(id), path("${vcf_out}{,.tbi}"), val(region)

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    region_chr = region.startsWith("chr") ? region : "chr${region}"
    norm_vcf = "norm-${id}.vcf.gz"
    vcf_out = "norm-${id}-${region_chr}.vcf.gz"
    """
    bcftools norm -f ${ref_genome}/${params.ref_genome_file} -m -both \
        --threads ${task.cpus} -Oz -o '${norm_vcf}' '${vcf_file}'
    bcftools index -t --threads ${task.cpus} '${norm_vcf}'

    bcftools filter -r ${region_chr} \
        --threads ${task.cpus} -Oz -o '${vcf_out}' '${norm_vcf}'
    bcftools index -t --threads ${task.cpus} '${vcf_out}'
    """
}

process shapeit_common {
    label "shapeit"
    tag "${id}"

    publishDir "${params.outdir}/shapeit", mode: "copy"

    input:
    tuple val(id), path(vcf), val(region), path(panel)

    output:
    tuple val(id), path("${id}-${region}.phase_common.vcf.gz{,.tbi}")

    script:
    vcf_file = vcf.find { it.name.endsWith('.vcf.gz') }
    panel_file = panel.find { it.name.endsWith('.vcf.gz') }
    region_chr = region.startsWith("chr") ? region : "chr${region}"
    """
    phase_common --input ${vcf_file} \
        --filter-maf 0.0 \
        --reference ${panel_file} \
        --map /usr/local/share/shapeit/maps/b38/${region_chr}.b38.gmap.gz \
        --region ${region} \
        --thread ${task.cpus} \
        --output ${id}-${region}.phase_common.vcf.gz
    bcftools index -t --threads ${task.cpus} ${id}-${region}.phase_common.vcf.gz
    """
}

process merge {
    label "shapeit"

    input:
    tuple val(id), path(vcf1), path(vcf2)
    val(name)

    output:
    tuple val(id), path("${id}-${name}.vcf.gz{,.tbi}")

    script:
    vcf1_file = vcf1.find { it.name.endsWith('.vcf.gz') }
    vcf2_file = vcf2.find { it.name.endsWith('.vcf.gz') }
    """
    bcftools merge --threads ${task.cpus} -Oz -o '${id}-${name}.vcf.gz' -R ${vcf1_file} '${vcf1_file}' '${vcf2_file}'
    bcftools index -t --threads ${task.cpus} '${id}-${name}.vcf.gz'
    """
}

process shapeit_rare {
    label "shapeit"
    tag "${id}"

    publishDir "${params.outdir}/shapeit", mode: "copy"

    input:
    tuple val(id), path(vcf), val(region), path(scaffold)
    path(ref_genome)

    output:
    path("${id}-${region}.phase_rare.vcf.gz{,.tbi}")

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
        --output ${id}-${region}.phase_rare.vcf.gz
    bcftools index -t --threads ${task.cpus} ${id}-${region}.phase_rare.vcf.gz
    """
}

workflow {
    if (params.flow == "shapeit") {
        Channel.of(file(params.phasing_samplesheet))
            .flatMap { csv -> csv.splitCsv(header: true) }
            .set { input_ch }
        
        input_ch
            .map { row -> [row.id, [file(row.vcf), file(row.vcf_index)], row.region] }
            .set { norm_ch }
        
        input_ch
            .map { row -> [row.id, [file(row.panel), file(row.panel_index)]] }
            .set { meta_ch }
        
        normalize_and_filter(norm_ch, file(params.ref_genome_dir))

        normalize_and_filter.out.join(meta_ch)
            .set { shapeit_ch } // [id, [vcf], region, [panel]]

        shapeit_common(shapeit_ch)

        // Use phase_common output as scaffold for rare variants
        // Note: fails with only one sample in the phased output

        // shapeit_common.out.join(meta_ch)
        //     .set { phased_ch } // [id, [phased], [panel]]
        
        // // Merge panel with phase_common output to use as scaffold for rare variants
        // // as only one sample causes error "Segmentation fault"
        // merge(phased_ch, "scaffold")

        // normalize_and_filter.out.join(merge.out)
        //     .set { scaffold_ch } // [id, [vcf], region, [scaffold]]

        // // Note: merged scaffold triggers error "Different sets of samples across files"
        // shapeit_rare(scaffold_ch, file(params.ref_genome_dir))

    }
}
