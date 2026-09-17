This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module's input is
../../007_VariantFiltration/results/WGS_EX2312012_HGWCNDSX7.filtered.vcf.gz
(+ .tbi). bin/run_filter_vcf.sh reads directly from that path rather than
through this data/ folder.

Deliberately mirrors VCF_pipeline/001_FilterVCF's script exactly (same
bcftools command) — see that module's own comments for why. This is the
Re-calling front's counterpart step, now that both fronts follow the
same filtering methodology.
