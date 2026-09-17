This is a plain directory, not a symlink — same exFAT+Linux limitation as
the other VCF_pipeline modules' data/ (see their README.txt files for the
full story).

This module's inputs are:
  - ../../007-Tier1_HighImpact/results/Tier1_HighImpact_vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
    (+ its .tbi) — the Tier 1 (high-impact) variant set.
  - ../../../resources/genes.txt — the candidate gene panel.
bin/run_mva_gene_panel.sh reads both directly rather than through this
data/ folder.
