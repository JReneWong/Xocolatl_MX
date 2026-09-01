# Rare Disease, Real Kid — MVA Hackathon 2026

Submission window:
24 Aug 2026 – 24 Oct 2026.

## Setup

We use an Apptainer image to run analysis on the provided dataset.

Apptainer only runs on Linux, if you're using MacOS you can follow the next steps to setup a Linux VM.

<details>
<summary>Create a Linux VM with MacOS</summary>

We recommend using Lima to create the VM.

```bash
# Install Lima (VM manager) via Homebrew
brew install lima
```

The VM config is defined under `lima/hackathon-vm.yaml`. You can edit it to setup specific resources for the VM. If you're using an external drive, edit the config yaml file to set the mount point for the VM.

Start the VM

```bash
limactl start --name=hackathon lima/hackathon-vm.yaml
limactl shell hackathon
```

You should now be inside an Ubuntu VM. If you configured an external drive it will be mounted at the path you defined in the yaml file.

If you need to resize the VM you can do so by stopping the VM, editing the config yaml file and starting it again.

```bash
limactl stop hackathon
# edit lima/hackathon-vm.yaml: raise cpus/memory
limactl start hackathon
```

</details>

## 2. Install Apptainer

```bash
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:apptainer/ppa
sudo apt update
sudo apt install -y apptainer
apptainer --version
```

## 3. Build the container image

Run the command from the directory you want the image to be created

```shell
apptainer build container/hackathon.sif container/hackathon.def
```

This builds a `.sif` image. Building can take a while and use a fair bit of RAM/CPU.

### What's inside the image

Two separate conda/micromamba environments (kept apart so a solver conflict
or a future package change on one side never forces re-resolving the other),
both added to `PATH`:

- **`/opt/env`** — alignment, variant calling, QC, pipeline: `fastqc`,
  `multiqc`, `bwa`, `samtools`, `picard`, `bcftools`, `gatk4`, `ensembl-vep`,
  `nextflow`, plus `python=3.11` with `pysam`/`pandas`/`numpy`/`matplotlib`.
- **`/opt/r-env`** — `r-base`, `r-ggplot2`, `bioconductor-genomicranges`.

Exact resolved versions aren't hand-pinned above (only `python=3.11` is) —
conda's solver picks a mutually-compatible set at build time, and the real
answer to "what version of X is installed" always lives in
[`docs/software_versions.txt`](docs/software_versions.txt), generated fresh
after every build (see below) rather than guessed ahead of time.

Need a different version of something, or a new tool entirely? Edit the
package list (and pin a version, e.g. `gatk4=4.5.0.0`) in
`container/hackathon.def`, then rebuild — nothing is ever patched in place,
so a bad rebuild can't leave you with a half-broken environment; the old
`.sif` is untouched until the new build succeeds.

After building, capture the version manifest into git-tracked docs:

```bash
bash scripts/record_versions.sh
```

## 4. Clone the git repo

```bash
git clone git@github.com:JReneWong/Xocolatl_MX.git
```

**Important:** never commit anything from `data/`, `.sif` images, or large intermediate files — see `.gitignore`.

## 5. Download the challenge data (do this when ready, it's ~85GB)

```bash
bash scripts/download_data.sh
```

## 5b. Download reference data (genome, dbSNP, ClinVar, VEP cache)

Everything here is pinned to **GRCh38** — confirm this matches the challenge
dataset's build before running (check the HF dataset card/rules); dbSNP,
ClinVar, and the VEP cache all have to agree with each other and with
whatever the sequencing data was aligned to, or coordinates won't line up.

```bash
bash scripts/download_references.sh
```

Genome + BWA index come from **Broad Institute's public GATK resource
bundle**, not a local `bwa index` build — indexing the full genome needs
~16-17GB RAM at peak, which no tuning fixes on an 8GB laptop. This bundle
ships a pre-built index instead, so nothing memory-heavy runs locally at all.
dbSNP is Broad's `dbsnp138` (much smaller than NCBI's full raw dump, and
already contig-matched to the genome).

Pulls into `./references/`: genome + BWA index (~8.9GB), dbSNP (~1.6GB),
ClinVar (<1GB), VEP offline cache (~20GB). ~30-35GB total, one-time, do it
on wifi you trust.

**Contig naming — read this before annotating anything.** The genome/dbSNP
above use `chr1`/`chr2`/`chrM` naming (Broad/UCSC convention). NCBI's ClinVar
VCF uses plain `1`/`2`/`MT` (Ensembl/NCBI convention) — the script renames
ClinVar's contigs to match after downloading. The VEP offline cache (step
4) is Ensembl-based, i.e. **non**-chr-prefixed — if you feed it a VCF called
from the chr-prefixed genome above, VEP won't match anything until you
either strip the `chr` prefix first or pass VEP's `--synonyms` option. Not
yet automated here; flag it when we get to the annotation step and we'll
sort out whichever approach is cleaner then.

### Space budget on the 0.5TB SSD

| Item | Est. size |
|---|---|
| Challenge dataset | ~85GB |
| Reference genome + BWA index (Broad bundle) | ~8.9GB |
| dbSNP (Broad dbsnp138) | ~1.6GB |
| ClinVar | <1GB |
| VEP offline cache | ~20GB |
| Container image (`.sif`) | ~5-8GB |
| **Baseline total** | **~120GB** |
| Nextflow `work/` during pipeline runs | variable, can add 100GB+ |

Point Nextflow's work directory at the SSD (default is fine if you launch
`nextflow run` from inside the project root on `/mnt/ssd`) and run
`nextflow clean -f` after confirming a run succeeded, so intermediate files
don't quietly eat the remaining headroom.


## Pipeline modules

Analysis lives in `pipeline/`, one numbered module per step:

```
pipeline/
├── 001_FastQC/
│   ├── data -> ../../InitialData     # symlink to this module's input
│   ├── bin/run_fastqc.sh             # the only thing you run
│   └── results/                      # outputs + one manifest per command
├── 002_Trimming/
├── 003_Alignment/
└── ...
```

Each module has exactly three folders:
- **`data/`** — a symlink to this module's input (raw data for module 001,
  the previous module's `results/` for most later ones — but not always:
  e.g. trimming acts on the raw reads, not on FastQC's reports, so its
  `data/` symlinks past 001 straight to `InitialData/`. Check what a module
  actually needs before assuming "previous module's output").
- **`bin/`** — the module's script(s). One `run_*.sh` entrypoint per
  module, sourcing `common/manifest.sh`.
- **`results/`** — outputs, plus a `manifest_<timestamp>.yaml` per command
  actually executed (command, params, container + its sha256, resources,
  git commit, inputs, outputs, exit code) via the shared `run_and_log`
  helper in `common/manifest.sh`. `manifest_latest.yaml` symlinks to the
  most recent one. Small reports (FastQC/MultiQC html) and every manifest
  are git-tracked; heavy formats (fastq/bam/vcf/etc.) are not — see
  `.gitignore`.

Run a module from the project root, inside the VM:
```bash
bash pipeline/001_FastQC/bin/run_fastqc.sh
# override defaults: CPUS=6 MEM=20GiB bash pipeline/001_FastQC/bin/run_fastqc.sh
```

`scripts/` (one-time environment/data setup — build the container, pull the
dataset/references) is separate from `pipeline/` (the actual analysis
steps) on purpose: the former runs once per laptop, the latter is what
gets re-run, extended, and eventually ported to Nextflow.

**Known gap:** `container/hackathon.def` has no read trimmer (no
`fastp`/`trimmomatic`/`cutadapt`) — only decide whether 002_Trimming is
needed after reading 001's MultiQC report; if trimming turns out to be
required, add `fastp` to the def file and rebuild before writing that
module.

## If the SSD mount misbehaves inside the VM

Lima shares the host directory via virtiofs, which usually handles Apptainer
sandbox/build operations fine. If you hit permission or symlink errors during
`apptainer build`, the fallback is to create a large raw disk image *file* on
the SSD (e.g. 250GB) and attach it to the Lima VM as a second, ext4-formatted
virtual disk — full native Linux filesystem semantics, still physically
stored on the SSD. Flag it here if we hit this and we'll set it up.
