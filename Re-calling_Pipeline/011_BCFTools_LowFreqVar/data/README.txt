This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module's input is
../../010_BCFToolsFiltering/results/SplitVEP_vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
(+ .tbi). bin/run_bcftools_lowfreqvar.sh reads directly from that path
rather than through this data/ folder.

Deliberately mirrors VCF_pipeline/004-BCFTools_LowFreqVar's script
exactly (same gnomAD AF threshold, 0.001) — see that module's own
comments. This is the Re-calling front's counterpart step, now that both
fronts follow the same methodology.
