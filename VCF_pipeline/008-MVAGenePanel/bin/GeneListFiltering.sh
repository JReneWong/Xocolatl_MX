filter=$(awk '{printf sep "INFO/vepSYMBOL=\"%s\"", $1; sep=" || "}' ../../../resources/genes.txt)

bcftools view -i "$filter vep103_joint_germline_recalibrated.rare.vcf.gz --Oz -o ../Tier_1/vep103_joint_germline_recalibrated.rare_high_impact_gene_list.vcf.gz
