To obtain candidate drugs for a disease-associated gene we query multiple datasets:

- [DGIdb](https://dgidb.org/) (Drug-Gene Interaction Database) GraphQL API
    
    Through `query_open_targets.py` to obtain a TSV file
    - Query drugs by target gene
    - Query target genes by drug

- [OpenTargets](https://opentargets.org/) GraphQL API

    Through `query_dgidb.py` to obtain a TSV file
    - Query drugs by target gene
    - Query target genes by drug

- [OptimusKG](https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/IYNGEV) parquet files

    Through `query_optimuskg.py` and `query_optimuskg_gene-drug.py` to get TXT file reports
    - Query drugs by target gene
    - Query candidate drugs by gene interaction partners
    - Rank candidate drugs by list of phenotypes (and flag risk candidate drugs)
    - Query candidate drugs by pathway signal
    - Query two-hop target genes by drug
    - Query gene-drug shared pathways

Required packages to perform the queries are defined in `env.yaml`.
Using OptimusKG first requires setting up the database with duckdb with `setup_optimuskg.py` with the dataset parquet files downloaded locally (we follow this approach given an access error to the online dataset with the `optimuskg` package as of Oct 2026).
