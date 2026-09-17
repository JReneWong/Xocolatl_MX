This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module's input is
../../011_BCFTools_LowFreqVar/results/RareVars_vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
(+ .tbi). bin/run_filter_synonymous.sh reads directly from that path
rather than through this data/ folder.

Deliberately mirrors VCF_pipeline/005-SynonymousMutations's script
exactly (same curated consequence allow-list, matched against
vepConsequence) — see that module's own comments for why matching the
flattened field is more precise than substring-matching raw CSQ. This is
the Re-calling front's counterpart step, now that both fronts follow the
same methodology.
