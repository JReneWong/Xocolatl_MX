This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module has two real inputs, not one:
  - ../../003_MarkDuplicates/results/WGS_EX2312012_HGWCNDSX7.dedup.bam
    (+ .bai) — read-level evidence, needed because -tensor-type
    read_tensor is the 2D model (the 1D/"reference" model would only
    need the VCF).
  - ../../004_HaplotypeCaller/results/WGS_EX2312012_HGWCNDSX7.vcf.gz
    (+ .tbi) — the raw, unfiltered callset being scored.

bin/run_nvscorevariants.sh reads directly from both paths rather than
through this data/ folder. The reference genome
(../../../references/genome/) is also an input, treated as fixed
infrastructure the same way earlier modules treated it.
