"""
Query OptimusKG by gene

Usage:
    python query_optimuskg.py <gene_id> [--db-dir <db_dir>] [--report <report_path>] [--phenotypes <phenotypes_file>]
"""

import argparse
import pathlib
import sys
import pandas as pd
import duckdb

MIN_DISEASE_SCORE = 0.3
MAX_PATHWAY_SIZE = 300
ACTIVATING = r"ACTIVATOR|^AGONIST|PARTIAL_AGONIST|POSITIVE_|OPENER|STABILISER"
NONFUNC = r"SUBSTRATE|ENZYME|CARRIER|TRANSPORTER|BINDING_AGENT"
INHIBITORY = r"INHIBITOR|ANTAGONIST|BLOCKER|DEGRADER|NEGATIVE_|INVERSE_AGONIST"

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("gene_id", help="Ensembl gene ID")
parser.add_argument("--db-dir", type=pathlib.Path, default=pathlib.Path("."),
                    help="directory containing optimuskg.duckdb (default: current directory)")
parser.add_argument("--report", type=pathlib.Path,
                    help="write the report to this file instead of stdout")
parser.add_argument("--phenotypes", type=pathlib.Path,
                    help="text file with one patient phenotype per line (HPO ID or name); "
                         "lines starting with # are ignored")
args = parser.parse_args()

gene_id = args.gene_id
db_dir = args.db_dir
report_path = args.report

phenotype_terms = []
if args.phenotypes:
    phenotype_terms = [l.strip() for l in args.phenotypes.read_text().splitlines()
        if l.strip() and not l.strip().startswith("#")]

def report(title, table=None, out=sys.stdout, **kwargs):
    print(f"\n### {title} ###\n", file=out)
    if table is None: return
    if isinstance(table, (pd.DataFrame, pd.Series)):
        text = table.to_string(**kwargs) if not table.empty else "(none)"
    else:
        text = str(table)
    print(text, file=out)

DB_PATH = pathlib.Path(db_dir) / "optimuskg.duckdb"

con = duckdb.connect(DB_PATH)

con.execute("""
    CREATE OR REPLACE TEMP VIEW nbr AS
    SELECT "from" AS src, "to" AS dst, label, relation, properties FROM edges
    UNION ALL
    SELECT "to"   AS src, "from" AS dst, label, relation, properties FROM edges
""")

NAME = """coalesce(json_extract_string(n.properties, '$.symbol'),
    json_extract_string(n.properties, '$.name'),
    n.id)"""

genes = con.execute(f"""
    SELECT n.id, {NAME} AS symbol
    FROM nodes n
    WHERE n.label = 'GEN' AND n.id = ?
""", [gene_id]).df()
if genes.empty:
    sys.exit(f"Gene with ID {gene_id} not found.")
gene = genes.iloc[0]

out = open(report_path, "w") if report_path else sys.stdout
with out:
    #---------------------------------- 
    # Drugs acting directly on the gene

    direct = con.execute(f"""
        SELECT e.dst AS drug_id, {NAME} AS drug, e.relation
        FROM nbr e JOIN nodes n ON n.id = e.dst
        WHERE e.src = ? AND e.label = 'DRG-GEN'
    """, [gene_id]).df()
    report(f"Drugs acting directly on {gene.symbol}", direct if not direct.empty else "  (none)", out=out)

    #----------------------------------
    # Associated diseases

    diseases = con.execute(f"""
        SELECT e.dst AS disease_id, {NAME} AS disease,
            TRY_CAST(json_extract(e.properties, '$.evidence_score') AS DOUBLE) AS score
        FROM nbr e JOIN nodes n ON n.id = e.dst
        WHERE e.src = ? AND e.label = 'DIS-GEN'
        ORDER BY score DESC NULLS LAST
    """, [gene.id]).df()
    report(f"Top diseases associated with {gene.symbol}", diseases.head(20), out=out)

    con.register("gene_diseases", diseases[diseases.score >= MIN_DISEASE_SCORE])

    #----------------------------------
    # Candidate drugs

    cands = con.execute(f"""
        WITH partners AS (
            SELECT DISTINCT dst AS gene_id
            FROM nbr WHERE src = ? AND label = 'GEN-GEN'
        ),
        hits AS (
            SELECT e.dst AS drug_id, p.gene_id, e.relation
            FROM partners p JOIN nbr e ON e.src = p.gene_id AND e.label = 'DRG-GEN'
        ),
        indicated AS (
            SELECT e.src AS drug_id, count(*) AS n_known_indications
            FROM nbr e JOIN gene_diseases d ON d.disease_id = e.dst
            WHERE e.label = 'DRG-DIS' AND e.relation = 'INDICATION'
            GROUP BY 1
        ),
        phase AS (
            SELECT src AS drug_id,
                max(TRY_CAST(json_extract(properties, '$.highest_clinical_trial_phase') AS DOUBLE)) AS max_phase
            FROM nbr WHERE label = 'DRG-DIS' GROUP BY 1
        )
        SELECT h.drug_id,
            {NAME.replace('n.', 'dn.')} AS drug,
            count(DISTINCT h.gene_id)                         AS n_partner_targets,
            string_agg(DISTINCT {NAME.replace('n.', 'gn.')}, ', ') AS partner_targets,
            string_agg(DISTINCT h.relation, ', ')              AS actions,
            p.max_phase,
            coalesce(i.n_known_indications, 0)                AS n_known_indications
        FROM hits h
        JOIN nodes dn ON dn.id = h.drug_id
        JOIN nodes gn ON gn.id = h.gene_id
        LEFT JOIN phase p     ON p.drug_id = h.drug_id
        LEFT JOIN indicated i ON i.drug_id = h.drug_id
        GROUP BY h.drug_id, drug, p.max_phase, i.n_known_indications
        ORDER BY n_partner_targets DESC, max_phase DESC NULLS LAST
    """, [gene_id]).df()
    con.register("cands", cands)
    
    report(f"Candidate drugs via {gene.symbol} interaction partners (top 30)", cands.head(30), out=out)

    patient = None
    if len(phenotype_terms):
        con.register("patient_terms", pd.DataFrame({"term": phenotype_terms}))
        matched = con.execute(f"""
                SELECT t.term, n.id AS phe_id, {NAME} AS phenotype
                FROM patient_terms t
                LEFT JOIN nodes n
                    ON n.label = 'PHE'
                    AND (upper(n.id) = upper(t.term)
                        OR upper(replace(n.id, '_', ':')) = upper(t.term)
                        OR lower({NAME}) = lower(t.term))
            """).df()
        matched = matched.dropna(subset=["phe_id"])
        con.register("patient_matched", matched)

        report("Matched phenotype terms", matched, out=out)

        con.execute("""
            CREATE OR REPLACE TEMP TABLE phen AS
            SELECT DISTINCT phe_id, phenotype FROM patient_matched
        """)

        # Genes in the spindle-assembly / mitotic checkpoint
        con.execute(f"""
            CREATE OR REPLACE TEMP TABLE checkpoint_genes AS
            SELECT DISTINCT e.dst AS gene_id
            FROM nodes n JOIN nbr e ON e.src = n.id AND e.label = 'BPO-GEN'
            WHERE n.label = 'BPO'
            AND ({NAME} ILIKE '%spindle assembly checkpoint%' OR {NAME} ILIKE '%mitotic%checkpoint%')
        """)

        # Drugs that inhibit any checkpoint gene
        con.execute(f"""
            CREATE OR REPLACE TEMP TABLE checkpoint_inhibitors AS
            SELECT e.dst AS drug_id, string_agg(DISTINCT {NAME}, ', ') AS inhibited_checkpoint_genes
            FROM checkpoint_genes g
            JOIN nbr e   ON e.src = g.gene_id AND e.label = 'DRG-GEN'
            JOIN nodes n ON n.id = g.gene_id
            WHERE regexp_matches(e.relation, '{INHIBITORY}')
            GROUP BY 1
        """)

        con.execute("""
            CREATE OR REPLACE TEMP TABLE drug_phen AS
            SELECT e.src AS drug_id,
            count(DISTINCT CASE WHEN e.relation IN ('INDICATION','OFF_LABEL_USE') THEN e.dst END) AS n_phen_treated,
            string_agg(DISTINCT CASE WHEN e.relation IN ('INDICATION','OFF_LABEL_USE') THEN p.phenotype END, ', ') AS phen_treated,
            count(DISTINCT CASE WHEN e.relation IN ('ADVERSE_DRUG_REACTION','CONTRAINDICATION') THEN e.dst END) AS n_phen_risk,
            string_agg(DISTINCT CASE WHEN e.relation IN ('ADVERSE_DRUG_REACTION','CONTRAINDICATION') THEN p.phenotype END, ', ') AS phen_risk
            FROM nbr e JOIN phen p ON p.phe_id = e.dst
            WHERE e.label = 'DRG-PHE'
            GROUP BY 1
        """)

        patient = con.execute(f"""
            WITH pool AS (
                SELECT drug_id FROM cands UNION SELECT drug_id FROM drug_phen
            )
            SELECT pool.drug_id,
                {NAME} AS drug,
                coalesce(c.n_partner_targets, 0)   AS n_partner_targets,
                c.partner_targets,
                coalesce(dp.n_phen_treated, 0)     AS n_phen_treated,
                dp.phen_treated,
                coalesce(dp.n_phen_risk, 0)        AS n_phen_risk,
                dp.phen_risk,
                ci.inhibited_checkpoint_genes,
                ci.drug_id IS NOT NULL             AS checkpoint_risk
            FROM pool
            JOIN nodes n ON n.id = pool.drug_id
            LEFT JOIN cands c                  ON c.drug_id  = pool.drug_id
            LEFT JOIN drug_phen dp             ON dp.drug_id = pool.drug_id
            LEFT JOIN checkpoint_inhibitors ci ON ci.drug_id = pool.drug_id
            ORDER BY checkpoint_risk ASC,
                    n_phen_risk ASC,
                    n_phen_treated DESC,
                    n_partner_targets DESC
        """).df()
        con.register("patient", patient)

        report("Phenotype-aware candidates (top 30, safest/most relevant first)", patient.head(30), out=out)

        flagged = patient[patient.checkpoint_risk]
        report("Flagged candidates (checkpoint risk)", flagged.head(15), out=out)

    #---------------------------------- 
    # Pathways

    BLOCKED_TRANSITION = "mitotic metaphase/anaphase transition"

    seed = con.execute(f"""
        SELECT n.id, json_extract_string(n.properties, '$.name') AS name
        FROM nbr e JOIN nodes n ON n.id = e.dst
        WHERE e.src = ? AND e.label = 'BPO-GEN' AND n.label = 'BPO'
        AND json_extract_string(n.properties, '$.name') ILIKE '%checkpoint%'
    """, [gene.id]).df()
    report(f"{gene.symbol} checkpoint processes", seed, out=out)
    con.register("seed_terms", seed)

    ## "mitotic spindle assembly checkpoint signaling" -> "spindle assembly checkpoint"
    CHECKPOINT = seed.name.iloc[0].replace("mitotic ", "").replace(" signaling", "")

    con.execute(f"""
        CREATE OR REPLACE TEMP TABLE role_terms AS
        WITH RECURSIVE desc_terms(id) AS (          -- seed + IS_A descendants
            SELECT id FROM seed_terms
            UNION
            SELECT b."from" FROM edges b JOIN desc_terms d ON b."to" = d.id
            WHERE b.label = 'BPO-BPO' AND b.relation = 'IS_A'
        ),
        named AS (
            SELECT n.id, n.label, json_extract_string(n.properties, '$.name') AS name
            FROM nodes n WHERE n.label IN ('BPO', 'CCO')
        )
        SELECT id, name,
        CASE
            WHEN id IN (SELECT id FROM desc_terms)                              THEN 'maintains'
            WHEN name ILIKE 'positive regulation of %{CHECKPOINT}%'
            OR name ILIKE 'activation of %{CHECKPOINT}%'
            OR name ILIKE 'negative regulation of {BLOCKED_TRANSITION}'
            OR name IN ('mitotic checkpoint complex',
                        'mitotic spindle assembly checkpoint MAD1-MAD2 complex') THEN 'maintains'
            WHEN name ILIKE 'negative regulation of %{CHECKPOINT}%'
            OR name ILIKE 'deactivation of %{CHECKPOINT}%'
            OR name ILIKE 'positive regulation of {BLOCKED_TRANSITION}'
            OR name IN ('anaphase-promoting complex',
                        'anaphase-promoting complex-dependent catabolic process',
                        'mitotic sister chromatid separation')             THEN 'silences'
            WHEN name ILIKE 'regulation of %{CHECKPOINT}%'                       THEN 'undirected'
        END AS role
        FROM named
        WHERE role IS NOT NULL AND name NOT ILIKE '%meio%'
    """)

    con.execute(f"""
        CREATE OR REPLACE TEMP TABLE derived_roles AS
        WITH hits AS (
            SELECT e.dst AS gene_id, t.role, t.name AS term
            FROM role_terms t JOIN nbr e ON e.src = t.id AND e.label IN ('BPO-GEN', 'CCO-GEN')
        ),
        per_gene AS (
            SELECT gene_id,
                bool_or(role = 'maintains')  AS m,
                bool_or(role = 'silences')   AS s,
                string_agg(DISTINCT term, '; ') AS evidence
            FROM hits GROUP BY 1
        )
        SELECT p.gene_id, upper(json_extract_string(n.properties, '$.symbol')) AS symbol,
        CASE
            WHEN p.gene_id = '{gene.id}' THEN 'maintains'   -- the seed defines the role
            WHEN m AND s THEN 'complex'
            WHEN m       THEN 'maintains'
            WHEN s       THEN 'silences'
            ELSE              'complex'                      -- undirected regulation only
        END AS role,
        p.evidence
        FROM per_gene p JOIN nodes n ON n.id = p.gene_id
    """)

    roles = con.execute("SELECT * FROM derived_roles ORDER BY role, symbol").df()
    MAINTAINS = roles.loc[roles.role == "maintains", "symbol"].tolist() # keep the spindle checkpoint ON
    SILENCES  = roles.loc[roles.role == "silences",  "symbol"].tolist() # switch it OFF or execute anaphase
    COMPLEX   = roles.loc[roles.role == "complex",   "symbol"].tolist() # mixed roles

    con.register("gene_roles", pd.DataFrame(
        [(g, "maintains") for g in MAINTAINS] +
        [(g, "silences") for g in SILENCES] +
        [(g, "complex") for g in COMPLEX],
        columns=["symbol", "role"]))

    ## gene pathways, smallest first
    pw = con.execute(f"""
        WITH pw AS (SELECT DISTINCT dst AS pwy_id FROM nbr WHERE src = ? AND label = 'PWY-GEN')
        SELECT pw.pwy_id, {NAME} AS pathway,
            (SELECT count(DISTINCT x.dst) FROM nbr x
                WHERE x.src = pw.pwy_id AND x.label = 'PWY-GEN') AS n_genes
        FROM pw JOIN nodes n ON n.id = pw.pwy_id
        ORDER BY n_genes
    """, [gene.id]).df()
    pw["used"] = pw.n_genes <= MAX_PATHWAY_SIZE
    if not pw.used.any():
        pw.loc[pw.index[:3], "used"] = True
    report(f"{gene.symbol} pathways (used = specific enough to analyse):", pw, out=out)
    con.register("kept_pw", pw[pw.used])

    ## genes in those pathways
    con.execute(f"""
        CREATE OR REPLACE TEMP TABLE pw_genes AS
        SELECT DISTINCT e.dst AS gene_id, {NAME} AS gene, coalesce(r.role, 'other') AS role
        FROM kept_pw k
        JOIN nbr e   ON e.src = k.pwy_id AND e.label = 'PWY-GEN'
        JOIN nodes n ON n.id = e.dst AND n.label = 'GEN'
        LEFT JOIN gene_roles r ON upper({NAME}) = r.symbol
    """)
    report("Pathway genes by curated role:",
        con.execute("SELECT role, count(*) AS n, string_agg(gene, ', ') AS genes "
                    "FROM pw_genes WHERE role <> 'other' GROUP BY role").df(), out=out)

    ## drug -> pathway gene edges
    con.execute(f"""
        CREATE OR REPLACE TEMP TABLE pw_drug_edges AS
        SELECT e.dst AS drug_id, g.gene, g.role, e.relation,
        CASE
            WHEN regexp_matches(e.relation, '{INHIBITORY}') THEN 'inhibits'
            WHEN regexp_matches(e.relation, '{ACTIVATING}') THEN 'activates'
            WHEN regexp_matches(e.relation, '{NONFUNC}')    THEN 'non_functional'
            WHEN regexp_matches(coalesce(CAST(json_extract(e.properties, '$.relation_assertions') AS VARCHAR), ''),
                                '{INHIBITORY}') THEN 'inhibits (per source assertion)'
            ELSE 'unknown'
        END AS direction
        FROM pw_genes g JOIN nbr e ON e.src = g.gene_id AND e.label = 'DRG-GEN'
    """)

    ## per-drug pathway summary and signal
    con.execute("""
        CREATE OR REPLACE TEMP TABLE pw_summary AS
        WITH agg AS (
        SELECT drug_id,
            count(DISTINCT gene) AS n_pathway_genes,
            string_agg(DISTINCT CASE WHEN role='maintains' AND direction LIKE 'inhibits%' THEN gene END, ', ') AS inhibits_maintainers,
            string_agg(DISTINCT CASE WHEN role='silences'  AND direction='activates'       THEN gene END, ', ') AS activates_silencers,
            string_agg(DISTINCT CASE WHEN role='silences'  AND direction LIKE 'inhibits%' THEN gene END, ', ') AS inhibits_silencers,
            string_agg(DISTINCT CASE WHEN role='maintains' AND direction='activates'       THEN gene END, ', ') AS activates_maintainers,
            string_agg(DISTINCT CASE WHEN role IN ('maintains','silences') AND direction='unknown' THEN gene END, ', ') AS unknown_on_checkpoint,
            string_agg(DISTINCT CASE WHEN role='complex' AND direction <> 'non_functional'
                                    THEN gene || ' (' || direction || ')' END, ', ') AS complex_role_hits
        FROM pw_drug_edges GROUP BY 1
        )
        SELECT *,
        CASE
            WHEN inhibits_maintainers IS NOT NULL OR activates_silencers IS NOT NULL
                THEN 'RISK: weakens checkpoint'
            WHEN inhibits_silencers IS NOT NULL OR activates_maintainers IS NOT NULL
                THEN 'HYPOTHESIS: compensatory direction'
            WHEN unknown_on_checkpoint IS NOT NULL OR complex_role_hits IS NOT NULL
                THEN 'REVIEW: direction unclear'
            ELSE 'pathway proximity only'
        END AS pathway_signal
        FROM agg
    """)

    ## Ranked drugs by pathway signal
    ranked = con.execute(f"""
        WITH pool AS (SELECT drug_id FROM pw_summary)
        SELECT pool.drug_id, {NAME} AS drug,
            coalesce(s.pathway_signal, 'not in gene pathways') AS pathway_signal,
            coalesce(s.pathway_signal, '') LIKE 'RISK%' AS any_risk,
            coalesce(s.n_pathway_genes, 0)   AS n_pathway_genes,
            s.inhibits_silencers, s.activates_maintainers,
            s.inhibits_maintainers, s.activates_silencers,
            s.unknown_on_checkpoint, s.complex_role_hits
        FROM pool
        JOIN nodes n            ON n.id = pool.drug_id
        LEFT JOIN pw_summary s  ON s.drug_id = pool.drug_id
        ORDER BY any_risk ASC,
                (coalesce(s.pathway_signal, '') LIKE 'HYPOTHESIS%') DESC,
                (coalesce(s.pathway_signal, '') LIKE 'REVIEW%') ASC,
                n_pathway_genes DESC
    """).df()
    
    report("Drugs by pathway signal", ranked.pathway_signal.value_counts(), out=out)
    report("Ranking (top 30)", ranked[~ranked.any_risk].head(30), out=out)

    if patient is not None:
        patient_ranked = con.execute(f"""
            WITH pool AS (SELECT drug_id FROM patient UNION SELECT drug_id FROM pw_summary)
            SELECT pool.drug_id, {NAME} AS drug,
                coalesce(s.pathway_signal, 'not in gene pathways') AS pathway_signal,
                coalesce(p.checkpoint_risk, false) OR coalesce(s.pathway_signal, '') LIKE 'RISK%' AS any_risk,
                coalesce(p.n_phen_treated, 0) AS n_phen_treated, p.phen_treated,
                coalesce(p.n_phen_risk, 0)    AS n_phen_risk,    p.phen_risk,
                coalesce(p.n_partner_targets, 0) AS n_partner_targets, p.partner_targets,
                coalesce(s.n_pathway_genes, 0)   AS n_pathway_genes,
                s.inhibits_silencers, s.activates_maintainers,
                s.inhibits_maintainers, s.activates_silencers, p.inhibited_checkpoint_genes,
                s.unknown_on_checkpoint, s.complex_role_hits
            FROM pool
            JOIN nodes n            ON n.id = pool.drug_id
            LEFT JOIN patient p     ON p.drug_id = pool.drug_id
            LEFT JOIN pw_summary s  ON s.drug_id = pool.drug_id
            ORDER BY any_risk ASC,
                    n_phen_risk ASC,
                    (coalesce(s.pathway_signal, '') LIKE 'HYPOTHESIS%') DESC,
                    n_phen_treated DESC,
                    (coalesce(s.pathway_signal, '') LIKE 'REVIEW%') ASC,
                    n_pathway_genes DESC
        """).df()

        report("Drugs by pathway signal (+phenotypes)", patient_ranked.pathway_signal.value_counts(), out=out)
        report("Ranking (top 30) (phenotypes)", patient_ranked[~patient_ranked.any_risk].head(30), out=out)
