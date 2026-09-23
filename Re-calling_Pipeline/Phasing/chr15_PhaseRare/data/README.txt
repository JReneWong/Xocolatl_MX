This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module's inputs:
  - ../../chr15/results/chr15.phased.vcf.gz (+ .tbi) — the phased
    common-variant scaffold from phase_common (only 118,898 of our
    130,040 chr15 variants; anything absent from the reference panel,
    including both BUB1B variants, was dropped — see
    bin/run_phase_rare_chr15.sh's header). NOT used directly as
    phase_rare's --scaffold — see the merge step below.
  - ../../chr15/results/ours_chr15.vcf.gz (+ .tbi) — the full, unphased
    chr15 genotype set (all 130,040 variants), used as phase_rare's
    --input.
  - ../../../../references/1000G_GRCh38/chr15_1000G_GRCh38_phased.vcf.gz
    (+ .tbi) — the same reference panel Phasing/chr15 used, needed again
    here to build a real multi-sample scaffold (see below).
bin/run_phase_rare_chr15.sh reads all three directly rather than through
this data/ folder.

phase_rare crashes (confirmed: SIGSEGV, "PBWT initialization [#eval=0]")
if handed our 1-sample scaffold as-is — unlike phase_common, it has no
separate --reference flag, so the --scaffold argument itself needs to
already be a multi-sample panel. This module's first real step merges
chr15.phased.vcf.gz with the reference panel's own phased genotypes
(results/scaffold_merged.vcf.gz, 3,203 samples) before running
phase_rare against that.

Independent module from Phasing/chr15 (team decision) — phase_common and
phase_rare are separate SHAPEIT5 tools with different jobs, chained by
files the same way every other module in this project chains to its
predecessor, not folded into one script.
