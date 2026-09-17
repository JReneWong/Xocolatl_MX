This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module's input is the Tier 1 (high-impact) VCF produced by
014_Tier1_HighImpact:
../../014_Tier1_HighImpact/results/Tier1_HighImpact_vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
(+ its .tbi). bin/run_export_table.sh reads directly from that path
rather than through this data/ folder — NOT through 015_MVAGenePanel;
see bin/run_export_table.sh's header for why.

Deliberately mirrors VCF_pipeline/009-Tier1_VariantTable's script
exactly. This is the Re-calling front's counterpart step, now that both
fronts follow the same table-export methodology.
