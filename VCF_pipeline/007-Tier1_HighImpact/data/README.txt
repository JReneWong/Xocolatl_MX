This is a plain directory, not a symlink — same exFAT+Linux limitation as
the other VCF_pipeline modules' data/ (see their README.txt files for the
full story).

This module's input is the SIFT/PolyPhen-filtered VCF produced by
006-BCFTools_SiftPolyphen:
../../006-BCFTools_SiftPolyphen/results/SiftPolyphenFiltered_vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
(+ its .tbi). bin/run_tier1_highimpact.sh reads directly from that path
rather than through this data/ folder.
