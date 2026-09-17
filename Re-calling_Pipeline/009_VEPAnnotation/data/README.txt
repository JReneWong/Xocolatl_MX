This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module's input is
../../008_FilterVCF/results/WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz (+ .tbi).
bin/run_vep_annotation.sh reads directly from that path rather than
through this data/ folder.

Deliberately mirrors VCF_pipeline/002-VEPAnnotation's script exactly —
same VEP flags, same ClinVar + gnomAD custom tracks, same
GRCh38_chr_synonyms.tsv fix — see that module's own comments for the
full reasoning behind each choice. This is the Re-calling front's
counterpart step, now that both fronts follow the same annotation
methodology.

Scattered per chromosome (bin/run_vep_annotation.sh's header comment has
the full story): 7 whole-genome runs were killed by the OS before this
change. Produces vep_WGS_EX2312012_HGWCNDSX7.PASS.<contig>.vcf.gz per
chromosome plus the gathered vep_WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
(same final filename as before the restructure — downstream modules
don't need to change).
