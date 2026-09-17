This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module's inputs are:
  - ../../014_Tier1_HighImpact/results/Tier1_HighImpact_vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
    (+ its .tbi) — the Tier 1 (high-impact) variant set.
  - ../../../resources/genes.txt — the candidate gene panel (shared with
    VCF_pipeline/008-MVAGenePanel, not duplicated).
bin/run_mva_gene_panel.sh reads both directly rather than through this
data/ folder.

Deliberately mirrors VCF_pipeline/008-MVAGenePanel's script exactly —
see that module's own comments for the full reasoning (gene panel
choice, fix vs. the colleague's reference script). This is the
Re-calling front's counterpart step, now that both fronts follow the
same gene-panel methodology.
