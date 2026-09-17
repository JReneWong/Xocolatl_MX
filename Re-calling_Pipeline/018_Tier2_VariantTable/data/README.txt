This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module's input is the Tier 2 (moderate-impact) VCF produced by
017_Tier2_ModerateImpact:
../../017_Tier2_ModerateImpact/results/Tier2_ModerateImpact_vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
(+ its .tbi). bin/run_export_table.sh reads directly from that path
rather than through this data/ folder.

Deliberately mirrors VCF_pipeline/011-Tier2_VariantTable's script
exactly (same column set as 016_Tier1_VariantTable, including
%GT/%AD/%DP). This is the Re-calling front's counterpart step, now that
both fronts follow the same table-export methodology.
