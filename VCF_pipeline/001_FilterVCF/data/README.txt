This is a plain directory, not a symlink, unlike some pipeline/ modules'
data/ (e.g. pipeline/001_FastQC/data). See pipeline/002_Alignment/data/README.txt
for the full story: macOS's exFAT driver emulates symlinks with a
proprietary on-disk format ("XSym") that Linux's native exfat driver can
neither read nor create, so a real symlink made through the Mac+Lima VM
setup doesn't work when running natively on a Linux workstation, and vice
versa.

This module's input is the hackathon-provided pre-called VCF:
../../InitialData/WGS_EX2312012_HGWCNDSX7.vcf.gz (+ its .tbi).
bin/run_filter_vcf.sh reads directly from $PROJECT_ROOT/InitialData rather
than through this data/ folder.
