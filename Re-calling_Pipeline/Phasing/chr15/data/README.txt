This is a plain directory, not a symlink, same reason as the other
Re-calling_Pipeline data/ stubs (see e.g. ../../../004_HaplotypeCaller/data/README.txt):
macOS's exFAT "XSym" symlink emulation can't be read or created by
Linux's native exfat driver.

This module has three real inputs, not one:
  - ../../../008_FilterVCF/results/WGS_EX2312012_HGWCNDSX7.PASS.vcf.gz
    (+ .tbi) — the PASS-only callset BEFORE any of the rarity/consequence
    narrowing modules (010-018), so common variants are still present to
    anchor phasing. bin/run_phase_chr15.sh reads directly from that path.
  - ../../../../references/1000G_GRCh38/chr15_1000G_GRCh38_phased.vcf.gz
    (+ .tbi) — 1000 Genomes high-coverage GRCh38 reference panel, chr15
    only (3,202 samples, natively GRCh38 — see bin/run_phase_chr15.sh's
    header for why this one and not the original 2013 Phase 3 panel or
    its withdrawn GRCh38 liftover).
  - The chr15 genetic map, NOT stored under references/ — it's baked
    into container/shapeit_amd64.sif itself at
    /opt/src/shapeit/resources/maps/b38/chr15.b38.gmap.gz (bundled in the
    same odelaneau/shapeit repo clone that provides phase_common).

Why "Phasing/chr15", not a numbered module: this is a targeted
investigation (a candidate compound-het pair in BUB1B), not a step both
fronts march through in lockstep like 001-019 — see
bin/run_phase_chr15.sh's header for the full reasoning. Named by
chromosome rather than by gene since the run phases all of chr15, not
just BUB1B; a future investigation on another chromosome would get its
own Phasing/chrN/ sibling.
