"""
Query Open Targets
By gene, disease or drug

Usage:
    python query_open_targets.py [--gene <ensembl_id>] [--disease <mondo_id>] [--drug <chembl_id>] <output_tsv>

<ensembl_id> is an Ensembl gene ID, e.g. ENSG00000XXXXXX
<mondo_id> is a Mondo disease ID, e.g. MONDO:000XXXX
<chembl_id> is a ChEMBL drug ID, e.g. CHEMBLXXX
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

URL = "https://api.platform.opentargets.org/api/v4/graphql"

HEADER = [
    "query", "query_id", "drug_id", "drug_name", "drug_type",
    "max_clinical_stage", "action_types", "mechanisms_of_action",
    "target_genes", "target_ensembl_ids", "indications",
]

DRUG_FIELDS = """
    id name drugType
    mechanismsOfAction { rows { mechanismOfAction actionType targets { id approvedSymbol } } }
"""

TARGET_QUERY = """
query ($ensemblId: String!) {
  target(ensemblId: $ensemblId) {
    approvedSymbol
    tractability { label modality value }
    drugAndClinicalCandidates {
      rows {
        maxClinicalStage
        drug { %s }
        diseases { disease { id name } }
      }
    }
  }
}
""" % DRUG_FIELDS

DISEASE_QUERY = """
query ($efoId: String!) {
  disease(efoId: $efoId) {
    name
    drugAndClinicalCandidates {
      rows {
        maxClinicalStage
        drug { %s }
      }
    }
    associatedTargets(page: {index: 0, size: 10}) {
      rows { target { id approvedSymbol } score }
    }
  }
}
""" % DRUG_FIELDS

DRUG_QUERY = """
query ($chemblId: String!) {
  drug(chemblId: $chemblId) {
    %s
    maximumClinicalStage
    indications { rows { disease { id name } } }
  }
}
""" % DRUG_FIELDS

def graphql(query, variables):
    request = urllib.request.Request(
        URL,
        data=json.dumps({"query": query, "variables": variables}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=60, context=SSL_CONTEXT) as response:
        result = json.load(response)
    if result.get("errors"):
        sys.exit(f"ERROR: Open Targets query failed: {result['errors']}")
    return result["data"]

def drug_columns(row):
    drug = row["drug"]
    moas = drug["mechanismsOfAction"]["rows"] if drug["mechanismsOfAction"] else []
    targets = sorted({(t["approvedSymbol"], t["id"]) for m in moas for t in m["targets"]})
    return [
        drug["id"], drug["name"], drug["drugType"], row["maxClinicalStage"],
        ";".join(sorted({m["actionType"] for m in moas if m["actionType"]})),
        ";".join(sorted({m["mechanismOfAction"] for m in moas})),
        ";".join(symbol for symbol, _ in targets),
        ";".join(ensembl_id for _, ensembl_id in targets),
    ]

parser = argparse.ArgumentParser(description="Query Open Targets for drugs by gene, disease or drug")
parser.add_argument("--gene", help="Ensembl gene ID, e.g. ENSG00000XXXXXX")
parser.add_argument("--disease", help="Mondo ID, e.g. MONDO:000XXXX")
parser.add_argument("--drug", help="ChEMBL ID, e.g. CHEMBLXXX")
parser.add_argument("output_tsv")
args = parser.parse_args()
if not (args.gene or args.disease or args.drug):
    parser.error("give at least one of --gene, --disease, --drug")

rows = []

if args.gene:
    ensembl_id = args.gene.strip()
    target = graphql(TARGET_QUERY, {"ensemblId": ensembl_id})["target"]
    if target is None:
        sys.exit(f"ERROR: target {ensembl_id} not found in Open Targets")

    print(f"{target['approvedSymbol']} ({ensembl_id}) tractability:")
    modalities = {}
    for t in target["tractability"]:
        if t["value"]:
            modalities.setdefault(t["modality"], []).append(t["label"])
    for modality, labels in modalities.items():
        print(f"  {modality}: {', '.join(labels)}")
    if not modalities:
        print("  none")

    for row in target["drugAndClinicalCandidates"]["rows"]:
        # indications without a mapped disease come back as null
        indications = ";".join(
            sorted({d["disease"]["name"] for d in row["diseases"] or [] if d["disease"]})
        )
        rows.append(["target", ensembl_id] + drug_columns(row) + [indications])

if args.disease:
    efo_id = args.disease.strip().replace(":", "_")
    disease = graphql(DISEASE_QUERY, {"efoId": efo_id})["disease"]
    if disease is None:
        print(f"WARNING: disease {efo_id} not found in Open Targets", file=sys.stderr)
    else:
        print(f"{disease['name']} ({efo_id}) top associated targets:")
        for a in disease["associatedTargets"]["rows"]:
            target_ = a["target"]
            print(f"  {target_['approvedSymbol']}\t{target_['id']}\t{a['score']:.3f}")
        for row in disease["drugAndClinicalCandidates"]["rows"]:
            rows.append(["disease", efo_id] + drug_columns(row) + [disease["name"]])

if args.drug:
    chembl_id = args.drug.strip().upper()
    drug = graphql(DRUG_QUERY, {"chemblId": chembl_id})["drug"]
    if drug is None:
        print(f"WARNING: drug {chembl_id} not found in Open Targets", file=sys.stderr)
    else:
        print(f"{drug['name']} ({chembl_id}) mechanisms of action:")
        moas = drug["mechanismsOfAction"]["rows"] if drug["mechanismsOfAction"] else []
        for m in moas:
            targets = ", ".join(f"{t['approvedSymbol']} {t['id']}" for t in m["targets"])
            print(f"  {m['mechanismOfAction']}\t{targets}")
        if not moas:
            print("  none")
        indications = ";".join(
            sorted({i["disease"]["name"] for i in drug["indications"]["rows"] if i["disease"]})
        )
        row = {"drug": drug, "maxClinicalStage": drug["maximumClinicalStage"]}
        rows.append(["drug", chembl_id] + drug_columns(row) + [indications])

print(f"{len(rows)} drug rows written to {args.output_tsv}")

with open(args.output_tsv, "w", newline="") as fh:
    writer = csv.writer(fh, delimiter="\t")
    writer.writerow(HEADER)
    writer.writerows(rows)
