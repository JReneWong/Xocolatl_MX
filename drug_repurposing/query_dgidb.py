"""
Query DGIdb for drug-gene interactions by gene and/or by drug

Usage:
    python query_dgidb.py <output_tsv> [--gene <ensembl_id> ...] [--drug <drug> ...]

<ensembl_id> is an Ensembl gene ID, e.g. ENSG00000XXXXXX
<drug> is a drug name or ChEMBL ID, e.g. drugname or CHEMBLXXX
"""

import argparse
import csv
import json
import ssl
import sys
import urllib.request

try:
    import certifi
    SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    SSL_CONTEXT = ssl.create_default_context()

URL = "https://dgidb.org/api/graphql"

HEADER = [
    "query", "query_id", "gene_symbol", "gene_categories", "drug_name", "drug_id",
    "approved", "interaction_score", "interaction_types", "sources",
]

INTERACTION_FIELDS = """
    interactionScore
    interactionTypes { type directionality }
    sources { sourceDbName }
"""

GENE_MATCH_QUERY = """
query ($terms: [String!]!) {
  geneMatches(searchTerms: $terms) {
    directMatches { searchTerm matches { conceptId } }
  }
}
"""

DRUG_MATCH_QUERY = """
query ($terms: [String!]!) {
  drugMatches(searchTerms: $terms) {
    directMatches { searchTerm matches { conceptId } }
  }
}
"""

GENE_QUERY = """
query ($ids: [String!]!) {
  genes(conceptIds: $ids) {
    nodes {
      name conceptId
      geneCategories { name }
      interactions {
        drug { name conceptId approved }
        %s
      }
    }
  }
}
""" % INTERACTION_FIELDS

DRUG_QUERY = """
query ($ids: [String!]!) {
  drugs(conceptIds: $ids) {
    nodes {
      name conceptId approved
      interactions {
        gene { name geneCategories { name } }
        %s
      }
    }
  }
}
""" % INTERACTION_FIELDS


def graphql(query, variables):
    request = urllib.request.Request(
        URL,
        data=json.dumps({"query": query, "variables": variables}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=60, context=SSL_CONTEXT) as response:
        result = json.load(response)
    if result.get("errors"):
        sys.exit(f"ERROR: DGIdb query failed: {result['errors']}")
    return result["data"]


def resolve(match_query, key, terms):
    """Map each search term to its DGIdb concept IDs, warning for terms with no direct match"""
    # DGIdb upper-cases search terms in its response
    matches = graphql(match_query, {"terms": list(terms.values())})[key]["directMatches"]
    concepts = {}
    for m in matches:
        concepts.setdefault(m["searchTerm"], []).extend(c["conceptId"] for c in m["matches"])
    resolved = {}
    for query_id, term in terms.items():
        if term.upper() in concepts:
            resolved[query_id] = concepts[term.upper()]
        else:
            print(f"WARNING: {query_id} not found in DGIdb", file=sys.stderr)
    return resolved


def categories(gene):
    return ";".join(sorted(c["name"] for c in gene["geneCategories"]))


def interaction_columns(i):
    return [
        f"{i['interactionScore'] or 0:.3f}",
        ";".join(
            f"{t['type']}({t['directionality']})" if t["directionality"] else t["type"]
            for t in i["interactionTypes"]
        ),
        ";".join(s["sourceDbName"] for s in i["sources"]),
    ]


parser = argparse.ArgumentParser(description="Query DGIdb for drug-gene interactions")
parser.add_argument("output_tsv")
parser.add_argument("--gene", nargs="+", default=[], help="Ensembl gene IDs, e.g. ENSG00000XXXXXX")
parser.add_argument("--drug", nargs="+", default=[], help="drug names or ChEMBL IDs, e.g. drugname or CHEMBLXXX")
args = parser.parse_args()
if not (args.gene or args.drug):
    parser.error("give at least one of --gene, --drug")

rows = []

if args.gene:
    terms = {g.strip(): f"ensembl:{g.strip()}" for g in args.gene}
    resolved = resolve(GENE_MATCH_QUERY, "geneMatches", terms)
    ids = sorted({c for cs in resolved.values() for c in cs})
    genes = graphql(GENE_QUERY, {"ids": ids})["genes"]["nodes"] if ids else []
    by_concept = {gene["conceptId"]: gene for gene in genes}
    for ensembl_id, concept_ids in resolved.items():
        for gene in (by_concept[c] for c in concept_ids if c in by_concept):
            interactions = sorted(
                gene["interactions"],
                key=lambda i: (not i["drug"]["approved"], -(i["interactionScore"] or 0)),
            )
            if not interactions:
                rows.append(["gene", ensembl_id, gene["name"], categories(gene)] + [""] * 6)
            for i in interactions:
                drug = i["drug"]
                rows.append(
                    ["gene", ensembl_id, gene["name"], categories(gene),
                     drug["name"], drug["conceptId"], drug["approved"]]
                    + interaction_columns(i)
                )

if args.drug:
    # ChEMBL IDs only match with their prefix
    terms = {
        d.strip(): f"chembl:{d.strip()}" if d.strip().upper().startswith("CHEMBL") else d.strip()
        for d in args.drug
    }
    resolved = resolve(DRUG_MATCH_QUERY, "drugMatches", terms)
    ids = sorted({c for cs in resolved.values() for c in cs})
    drugs = graphql(DRUG_QUERY, {"ids": ids})["drugs"]["nodes"] if ids else []
    by_concept = {drug["conceptId"]: drug for drug in drugs}
    for query_id, concept_ids in resolved.items():
        for drug in (by_concept[c] for c in concept_ids if c in by_concept):
            interactions = sorted(drug["interactions"], key=lambda i: -(i["interactionScore"] or 0))
            if not interactions:
                rows.append(["drug", query_id, "", "", drug["name"], drug["conceptId"],
                             drug["approved"]] + [""] * 3)
            for i in interactions:
                gene = i["gene"]
                rows.append(
                    ["drug", query_id, gene["name"], categories(gene),
                     drug["name"], drug["conceptId"], drug["approved"]]
                    + interaction_columns(i)
                )

print(f"{len(rows)} rows written to {args.output_tsv}")

with open(args.output_tsv, "w", newline="") as fh:
    writer = csv.writer(fh, delimiter="\t")
    writer.writerow(HEADER)
    writer.writerows(rows)
