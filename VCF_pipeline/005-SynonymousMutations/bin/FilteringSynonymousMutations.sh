bcftools view \
 -i 'INFO/CSQ ~ "missense_variant" ||
 INFO/CSQ ~ "frameshift_variant" ||
 INFO/CSQ ~ "stop_gained" ||
 INFO/CSQ ~ "stop_lost" ||
 INFO/CSQ ~ "start_lost" ||
 INFO/CSQ ~ "splice_acceptor_variant" ||
 INFO/CSQ ~ "splice_donor_variant" ||
 INFO/CSQ ~ "splice_region_variant" ||
 INFO/CSQ ~ "inframe_insertion" ||
 INFO/CSQ ~ "inframe_deletion"' \
 -Oz \
 -o ${filt_vcf_out} \
 ${vcf_out}
