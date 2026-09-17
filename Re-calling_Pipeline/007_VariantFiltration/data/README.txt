This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module's input is
../../006_FilterVariantTranches/results/WGS_EX2312012_HGWCNDSX7.tranche_filtered.vcf.gz
(+ .tbi) — NOT 004_HaplotypeCaller's raw VCF directly, as it was before
006_FilterVariantTranches was inserted into the chain (team decision:
single linear sequence, not two branches). bin/run_variant_filtration.sh
reads directly from that path rather than through this data/ folder.
The reference genome (../../../references/genome/) is also an input,
treated as fixed infrastructure the same way earlier modules treated it.

This module internally pre-filters 006's output to its PASS-only subset
before running GATK VariantFiltration on it — see bin/run_variant_filtration.sh's
header comment for why (GATK's VariantFiltration discards any existing
FILTER value rather than combining with it, confirmed on real data, so
the only way to make this module's hard-filter and 006's CNN tranche
filter both count is to remove anything that already failed 006 before
this module's own filter ever sees it).
