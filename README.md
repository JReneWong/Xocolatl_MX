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

If you need to resize the VM you can do so by editting the VM
e.g.
```bash
limactl edit hackathon --cpus 4
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

You do not have to create the environments as Nextflow will handle them as needed. You could however create them and then configure Nextflow to use existing environments, refer to their documentation for more information.

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

Run the script to download references to `data/references`

```bash
bash scripts/download_references.sh
```

This includes:
- Genome + BWA index from **Broad Institute's public GATK resource bundle** (~3.2GB + 6.4GB)
- dbSNP from **Broad Institute's public GATK resource bundle** (~1.6GB)
- ClinVar from **NCBI** (184MB)
- VEP cache from **ENSEMBL** (~26GB)
- Known sites resources from **Broad Institute's public GATK resource bundle** (~63MB + ~22MB)

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

The default entrypoint for the pipeline runs everything.

Run specific workflows with `-entry WORKFLOW_NAME`.

Specify parameters in the command line by adding `--param_name my_param_value`.
E.g.
```bash
nextflow run pipeline/main.nf -profile apptainer --fastqDir /path/to/dir_with_fastqs/
```
