This is a plain directory, not a symlink — same exFAT+Linux limitation as
VCF_pipeline/001_FilterVCF/data, 002-VEPAnnotation/data, and
003-BCFToolsFiltering/data (see those README.txt files for the full story).

This module's input is the split-VEP VCF produced by 003-BCFToolsFiltering:
../../003-BCFToolsFiltering/results/SplitVEP_vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
(+ its .tbi). bin/run_bcftools_lowfreqvar.sh reads directly from that path
rather than through this data/ folder.
