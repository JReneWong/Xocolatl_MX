bcftools view -e 'INFO/vepSIFT~"tolerated" || INFO/vepPolyPhen="benign"' vep103_joint_germline_recalibrated.worst_consequence.vcf.gz -Oz -o vep103_joint_germline_recalibrated.sift_polyphen.vcf.gz
