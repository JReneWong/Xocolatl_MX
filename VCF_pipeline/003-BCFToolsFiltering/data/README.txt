This is a plain directory, not a symlink — same exFAT+Linux limitation as
VCF_pipeline/001_FilterVCF/data and VCF_pipeline/002-VEPAnnotation/data
(see those README.txt files for the full story).

This module's input is the VEP-annotated VCF produced by 002-VEPAnnotation:
../../002-VEPAnnotation/results/vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
(+ its .tbi). bin/run_bcftools_filtering.sh reads directly from that path
rather than through this data/ folder.
