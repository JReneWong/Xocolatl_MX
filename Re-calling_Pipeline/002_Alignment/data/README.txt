This is a plain directory, not a symlink, unlike other modules' data/.

Module 001_FastQC's data/ is a real symlink to ../../InitialData — but it
was created on macOS, whose exFAT driver emulates symlinks with a
proprietary on-disk format ("XSym"). Linux's native exfat driver can
neither read nor create that format (`ln -s` fails with "Operation not
permitted" on this filesystem from Linux), so the same trick doesn't work
when running natively on a Linux workstation instead of through the
Mac+Lima VM setup.

This module's input is ../../InitialData (the raw lane fastqs), same as
001_FastQC. bin/run_alignment.sh reads directly from
$PROJECT_ROOT/InitialData rather than through this data/ folder.
