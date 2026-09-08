This is a plain directory, not a symlink — same exFAT+Linux limitation as
VCF_pipeline/001_FilterVCF/data and pipeline/002_Alignment/data (see those
README.txt files for the full story).

This module's input is the PASS-only VCF produced by 001_FilterVCF:
../../001_FilterVCF/results/WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz (+ its .tbi).
bin/run_vep_annotation.sh reads directly from that path rather than through
this data/ folder.
