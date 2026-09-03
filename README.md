# Rare Disease, Real Kid — MVA Hackathon 2026

Submission window:
24 Aug 2026 – 24 Oct 2026.

## Setup

### 1. Clone the repo

Clone the repo and move into its directory

```bash
git clone git@github.com:JReneWong/Xocolatl_MX.git
cd Xocolatl_MX
```

### (Optional) Setup VM

We use a Nextflow pipeline to run analysis on the provided dataset.

The pipeline can either use Apptainer or micromamba/conda to handle environments.

If using Apptainer, consider it only runs on Linux. If you're using MacOS you can follow the next steps to setup a Linux VM.

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

You should now be inside an Ubuntu VM, perform the rest of the steps within the VM. If you configured an external drive it will be mounted at the path you defined in the yaml file.

If you need to resize the VM you can do so by stopping the VM, editing the config yaml file and starting it again.

```bash
limactl stop hackathon
# edit lima/hackathon-vm.yaml: raise cpus/memory
limactl start hackathon
```

</details>

### 2. Install Nextflow

Follow [seqera's docs on installing Nextflow](https://docs.seqera.io/nextflow/install). 

### 3. Environment setup

Use either Apptainer or micromamba/conda

<details>
<summary>Aptainer</summary>

Install apptainer

```bash
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:apptainer/ppa
sudo apt update
sudo apt install -y apptainer
apptainer --version
```

Run the command from the directory you want the image to be created at

```shell
apptainer build container/hackathon.sif container/hackathon.def
```

This builds a `.sif` image. Building can take a while and use a fair bit of RAM/CPU.

The image contains three micromamba environments. Environment dependencies are defined in the yaml files under `container/`.

- **`/opt/env`** — Python 3.11 environment, alignment, variant calling, QC, pipeline. Added to `PATH`.
- **`/opt/r-env`** — R environment. Added to `PATH`.
- **`/opt/vep-env`** - Ensembl VEP.

After building, capture the version manifest:

```bash
bash scripts/record_versions.sh
```
</details>

<details>
<summary>Conda/Micromamba</summary>

Follow either [micromamba](https://mamba.readthedocs.io/en/latest/installation/micromamba-installation.html)'s (recommended) or [conda](https://docs.conda.io/projects/conda/en/latest/user-guide/install/index.html)'s docs on installation.

You do not have to create the environments as Nextflow will handle them as needed. You could however create them and then configure Nextflow to use existing environments.

Environment dependencies are defined in the yaml files under `container/`.

- **`env`** — Python 3.11 environment, alignment, variant calling, QC, pipeline.
- **`r-env`** — R environment.
- **`vep-env`** - Ensembl VEP.

</details>


### 4. Download the challenge data (~85GB)

```bash
bash scripts/download_data.sh
```

### 4b. Download reference data (genome, dbSNP, ClinVar, VEP cache)

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


### 5. Run the pipeline

The Nextflow pipeline's configuration and files live under `pipeline/`

Default configuration and profiles are defined in `pipeline/nextflow.config`, you can modify them if needed.

The configuration provides three different profiles to run the pipeline, `apptainer` to use a container image, and `micromamba` and `conda` to use virtual environments.

Run the pipeline as

```bash
# Nextflow will use the container image built in the previous steps
nextflow run pipeline/main.nf -profile apptainer
```

or

```bash
# Nextflow will create the virtual environments as required
# replace `micromamba` for `conda` if you're using conda
nextflow run pipeline/main.nf -profile micromamba
```

The default entrypoint for the pipeline runs QC. Run specific workflows with `-entry WORKFLOW_NAME`.

Specify parameters in the command line by adding `--param_name my_param_value`.
E.g.
```bash
nextflow run pipeline/main.nf -profile apptainer --fastq path_to_fastq.gz
```
