This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module has sixteen real inputs, not one — the outputs of every
Re-calling module from 008 through 015, paired against their
VCF_pipeline counterpart (001 through 008-MVAGenePanel).
bin/run_comparison_report.sh reads directly from those paths rather
than through this data/ folder. See that script's STAGES array for the
exact pairing. 009-Tier1_VariantTable / 016_Tier1_VariantTable is
excluded — it's a flat text table, not a VCF, so it's compared ad hoc
(row count / diff) rather than through this module's bcftools isec
logic.

references/genome/GRCh38_chr_synonyms.tsv is also an input — needed to
reconcile contig naming (VCF_pipeline's VCFs use plain "1"/"2"/"X"
contigs, ours use chr-prefixed "chr1"/"chr2"/"chrX" since we called
against the chr-prefixed Broad genome) before any variant-level
comparison can be done. See the script header for why VCF_pipeline's
side gets renamed rather than ours.
