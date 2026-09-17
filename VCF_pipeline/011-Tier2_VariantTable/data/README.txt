This is a plain directory, not a symlink — same exFAT+Linux limitation as
the other VCF_pipeline modules' data/ (see their README.txt files for the
full story).

This module's input is the Tier 2 (moderate-impact) VCF produced by
010-Tier2_ModerateImpact:
../../010-Tier2_ModerateImpact/results/Tier2_ModerateImpact_vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
(+ its .tbi). bin/run_export_table.sh reads directly from that path
rather than through this data/ folder.
