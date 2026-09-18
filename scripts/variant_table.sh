input_vcf=$1
output_table=$2

bcftools query \
    -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/vepConsequence\t%INFO/vepIMPACT\t%INFO/vepSYMBOL\t%INFO/vepSIFT\t%INFO/vepPolyPhen\t%INFO/vepClinVar_CLNSIG\t%INFO/vepExisting_variation\t%INFO/vepgnomAD_AF[\t%GT\t%AD\t%DP]\n' \
    "$input_vcf" > "$output_table"
