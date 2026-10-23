"""
Query OptimusKG drug-gene interactions

Usage:
    python query_optimuskg_gene-drug.py <gene_id> [--db-dir <db_dir>] [--report <report_path>] [--drug <drug1> <drug2> ...]
"""

import argparse
import pathlib
import sys
import pandas as pd
import duckdb

MIN_DISEASE_SCORE = 0.3
MAX_PATHWAY_SIZE = 300

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("gene_id", help="Ensembl gene ID")
parser.add_argument("--db-dir", type=pathlib.Path, default=pathlib.Path("."),
                    help="directory containing optimuskg.duckdb (default: current directory)")
parser.add_argument("--report", type=pathlib.Path,
                    help="write the report to this file instead of stdout")
parser.add_argument("--drug", nargs="+", default=[], help="Chembl IDs or drug names")

args = parser.parse_args()

gene_id = args.gene_id
db_dir = args.db_dir
report_path = args.report
drug_list = args.drug

def report(title=None, table=None, out=sys.stdout, **kwargs):
    if title:
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

SYMBOL = "json_extract_string(n.properties, '$.symbol')"
NAME = "json_extract_string(n.properties, '$.name')"
genes = con.execute(f"""
    SELECT n.id, {SYMBOL} AS symbol
    FROM nodes n
    WHERE n.label = 'GEN' AND n.id = ?
""", [gene_id]).df()
if genes.empty:
    sys.exit(f"Gene with ID {gene_id} not found.")
gene = genes.iloc[0]

out = open(report_path, "w") if report_path else sys.stdout
with out:
    report(f"Gene: {gene.symbol} ({gene.id})", out=out)
    for drug_term in drug_list:
        report(table="----------------", out=out)
        drugs = con.execute(f"""
            SELECT n.id, {NAME} AS name
            FROM nodes n
            WHERE n.label = 'DRG'
            AND (upper(n.id) = upper(?) OR upper({NAME}) = upper(?) OR n.properties ILIKE ?)
            LIMIT 10
        """, [drug_term, drug_term, f'%"{drug_term}"%']).df()
        if drugs.empty:
            report(f"No matching drugs found for {drug_term}", out=out)
            continue
        drug = drugs.iloc[0]
        report(f"Drug: {drug['name']} ({drug.id})", out=out)

        # Direct edges
        direct = con.execute(f"""
            SELECT e.dst AS gene_id, {SYMBOL} AS symbol, e.relation, e.properties
            FROM nbr e JOIN nodes n ON n.id = e.dst
            WHERE e.src = ? AND e.label = 'DRG-GEN'
            AND e.dst = ?
        """, [drug.id, gene.id]).df()
        report(f"Direct {drug['name']} -> target edges:", direct, out=out)

        # Targets
        alltg = con.execute(f"""
            SELECT e.dst AS gene_id, {SYMBOL} AS symbol,
                string_agg(DISTINCT e.relation, ', ') AS relations
            FROM nbr e JOIN nodes n ON n.id = e.dst
            WHERE e.src = ? AND e.label = 'DRG-GEN'
            GROUP BY 1, 2 ORDER BY symbol
        """, [drug.id]).df()
        report(f"All {len(alltg)} annotated {drug['name']} gene targets:", alltg, out=out)

        # two hop
        two_hop = con.execute(f"""
            WITH tg AS (SELECT DISTINCT dst AS gene_id FROM nbr WHERE src = ? AND label = 'DRG-GEN')
            SELECT json_extract_string(t.properties,  '$.symbol') AS drug_target,
                de.relation                                    AS drug_action,
                e.relation                                     AS gene_gene_relation,
                e.dst                                          AS endpoint_id,
                json_extract_string(g2.properties, '$.symbol') AS endpoint_symbol
            FROM tg
            JOIN nodes t  ON t.id   = tg.gene_id
            JOIN nbr   de ON de.src = ? AND de.dst = tg.gene_id AND de.label = 'DRG-GEN'
            JOIN nbr   e  ON e.src  = tg.gene_id AND e.label = 'GEN-GEN'
            JOIN nodes g2 ON g2.id  = e.dst
            WHERE e.dst = ?
        """, [drug.id, drug.id, gene.id]).df()
        report(f"Two-hop ({drug['name']} target --GEN-GEN--> endpoint):", two_hop, out=out)

        # shared pathway
        shared_pw = con.execute(f"""
            WITH tg AS (SELECT DISTINCT dst AS gene_id FROM nbr WHERE src = ? AND label = 'DRG-GEN'),
            endp AS (
                SELECT n.id AS gene_id, {SYMBOL} AS sym
                FROM nodes n WHERE n.id = ?
            )
            SELECT ep.sym AS endpoint_gene,
                {NAME.replace('n.', 'pn.')} AS pathway,
                string_agg(DISTINCT json_extract_string(tn.properties, '$.symbol'), ', ')
                    AS shared_drug_targets,
                (SELECT count(DISTINCT x.dst) FROM nbr x
                    WHERE x.src = p1.dst AND x.label = 'PWY-GEN') AS pathway_size
            FROM endp ep
            JOIN nbr p1   ON p1.src = ep.gene_id AND p1.label = 'PWY-GEN'
            JOIN nbr p2   ON p2.src = p1.dst     AND p2.label = 'PWY-GEN'
            JOIN tg       ON tg.gene_id = p2.dst
            JOIN nodes tn ON tn.id = tg.gene_id
            JOIN nodes pn ON pn.id = p1.dst
            GROUP BY 1, 2, p1.dst
            HAVING pathway_size <= {MAX_PATHWAY_SIZE}
            ORDER BY pathway_size
        """, [drug.id, gene.id]).df()
        report(f"Shared pathways (<= {MAX_PATHWAY_SIZE} genes):", shared_pw, out=out)
