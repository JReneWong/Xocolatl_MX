This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module's primary input is
../../005_NVScoreVariants/results/WGS_EX2312012_HGWCNDSX7.cnn_scored.vcf.gz
(+ .tbi) — the CNN_2D-annotated-but-unfiltered VCF. bin/run_filter_variant_tranches.sh
reads directly from that path rather than through this data/ folder.

Two more real inputs, treated as fixed infrastructure like references/
elsewhere in the project:
  - ../../../references/hapmap/hapmap_3.3.hg38.vcf.gz — truth-set of
    high-confidence common SNPs.
  - ../../../references/mills/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz
    — truth-set of high-confidence indels.
Both downloaded from the same Broad public GATK resource bundle bucket
as the genome/dbSNP (see scripts/download_references.sh's BROAD_BASE) —
already chr-prefixed, matching our genome's convention, so no synonyms
fix needed here unlike ClinVar/gnomAD.
