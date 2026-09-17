Small, curated, git-tracked project inputs — distinct from references/
(large downloaded reference data, gitignored) and from data/InitialData/
(the raw challenge dataset, gitignored). Files here are meant to be
version-controlled and easy to hand-edit.

genes.txt — candidate gene panel used by
VCF_pipeline/008-MVAGenePanel/bin/run_mva_gene_panel.sh to filter variants
down to genes associated with Mosaic Variegated Aneuploidy (MVA) syndrome,
matching the phenotype doc's "chromosomal instability disorder" framing
(and the hackathon's own name). One HGNC gene symbol per line, no header,
no blank lines — read via awk into a bcftools -i filter expression.
Edit this file to change the panel; no script changes needed.
