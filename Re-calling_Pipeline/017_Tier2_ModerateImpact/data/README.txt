This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module's input is the SIFT/PolyPhen-filtered VCF produced by
013_BCFTools_SiftPolyphen (the SAME parent 014_Tier1_HighImpact draws
from — Tier 2 is a sibling partition, not built on top of Tier 1):
../../013_BCFTools_SiftPolyphen/results/SiftPolyphenFiltered_vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
(+ its .tbi). bin/run_tier2_moderateimpact.sh reads directly from that
path rather than through this data/ folder.

Deliberately mirrors VCF_pipeline/010-Tier2_ModerateImpact's script
exactly (same vepIMPACT="MODERATE" filter). This is the Re-calling
front's counterpart step, now that both fronts follow the same tiering
methodology.
