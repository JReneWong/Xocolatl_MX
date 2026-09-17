This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module's input is
../../012_SynonymousMutations/results/Functional_RareVars_vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
(+ .tbi). bin/run_sift_polyphen_filter.sh reads directly from that path
rather than through this data/ folder.

Deliberately mirrors VCF_pipeline/006-BCFTools_SiftPolyphen's script
exactly (same exclusion expression: SIFT "tolerated" or PolyPhen
"benign") — see that module's own comments. This is the Re-calling
front's counterpart step, now that both fronts follow the same
methodology.
