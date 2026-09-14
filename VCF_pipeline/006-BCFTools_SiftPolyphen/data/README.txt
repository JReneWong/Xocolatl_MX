This is a plain directory, not a symlink — same exFAT+Linux limitation as
the other VCF_pipeline modules' data/ (see their README.txt files for the
full story).

This module's input is the functional rare-variant VCF produced by
005-SynonymousMutations:
../../005-SynonymousMutations/results/Functional_RareVars_vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
(+ its .tbi). bin/run_sift_polyphen_filter.sh reads directly from that
path rather than through this data/ folder.
