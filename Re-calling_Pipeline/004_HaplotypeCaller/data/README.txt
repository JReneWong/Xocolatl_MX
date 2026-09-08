This is a plain directory, not a symlink, same reason as
../../002_Alignment/data/README.txt and
../../003_MarkDuplicates/data/README.txt: macOS's exFAT "XSym" symlink
emulation can't be read or created by Linux's native exfat driver.

This module's input is ../../003_MarkDuplicates/results/, specifically
the deduped, still coordinate-sorted sample BAM:
WGS_EX2312012_HGWCNDSX7.dedup.bam (+ .bai). bin/run_haplotypecaller.sh
reads directly from that path rather than through this data/ folder.

The reference genome/dict/fai (../../../references/genome/) and dbSNP
(../../../references/dbsnp/) are also inputs, but are treated as fixed
infrastructure the same way 002_Alignment treated the bwa index — used
directly from references/, not staged through this data/ folder.
