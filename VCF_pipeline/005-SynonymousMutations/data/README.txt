This is a plain directory, not a symlink — same exFAT+Linux limitation as
VCF_pipeline/001_FilterVCF/data, 002-VEPAnnotation/data,
003-BCFToolsFiltering/data, and 004-BCFTools_LowFreqVar/data (see those
README.txt files for the full story).

This module's input is the rare-variant VCF produced by
004-BCFTools_LowFreqVar:
../../004-BCFTools_LowFreqVar/results/RareVars_vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
(+ its .tbi). bin/run_filter_synonymous.sh reads directly from that path
rather than through this data/ folder.
