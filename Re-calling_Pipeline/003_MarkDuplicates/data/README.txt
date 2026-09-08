This is a plain directory, not a symlink, same reason as
../../002_Alignment/data/README.txt: macOS's exFAT "XSym" symlink
emulation can't be read or created by Linux's native exfat driver.

This module's input is ../../002_Alignment/results/, specifically the
merged, sorted (but not yet deduped) sample-level BAM:
WGS_EX2312012_HGWCNDSX7.sorted.bam (+ .bai). bin/run_markduplicates.sh
reads directly from that path rather than through this data/ folder.

Deliberately NOT the four per-lane BAMs
(WGS_EX2312012_HGWCNDSX7_L00{1..4}.sorted.bam): all four lanes share one
library (LB:WGS_EX2312012_HGWCNDSX7 in every lane's @RG, set in
002_Alignment), so PCR duplicates from that library can appear across
lane boundaries. MarkDuplicates has to see the whole library at once to
catch those — running it per-lane would only catch within-lane
duplicates and under-count the true duplication rate.
