"""
Create hackathon submission csv file

Usage:
    python exomiser_variant_pairs.py <proband_id> <disease_id> <exomiser_jsonl> <output_csv>

<disease_id> is a disease ID, e.g. OMIM:000000 or ORPHA:000
"""

import csv
import json
import sys

HEADER = [
    "proband_id",
    "chrom_1", "pos_1", "ref_1", "alt_1",
    "chrom_2", "pos_2", "ref_2", "alt_2",
    "epcr",
    "finding_type", "notes"
]

RECESSIVE_MODES = {"AUTOSOMAL_RECESSIVE", "X_RECESSIVE"}

def format_contig(contig):
    if not contig.startswith("chr"):
        contig = "chr" + contig
    return contig

def to_variant(v):
    return [format_contig(v["contigName"]), str(v["start"]), v["ref"], v["alt"]]

def pick_variants(gene):
    """Return (gene_score, variants) for a gene's row.

    Prefer a compound-het pair (recessive mode with two contributing variants),
    otherwise the best-scoring mode with a single contributing variant.
    """
    scored = [
        gs for gs in gene.get("geneScores", []) if gs.get("contributingVariants")
    ]
    if not scored:
        return None, []
    for gs in scored:
        variants = gs["contributingVariants"]
        if gs["modeOfInheritance"] in RECESSIVE_MODES and len(variants) >= 2:
            return gs, [to_variant(v) for v in variants]
    best = max(scored, key=lambda gs: gs["combinedScore"])
    return best, [to_variant(best["contributingVariants"][0])]

def disease_score(gene, disease_id):
    """Best phenotypeEvidence score for the given disease ID, else 0."""
    scores = [0.0]
    for priority in gene.get("priorityResults", {}).values():
        for evidence in priority.get("phenotypeEvidence") or []:
            disease = evidence.get("model", {}).get("disease")
            if not disease:
                continue
            if disease.get("diseaseId", "").lower() == disease_id:
                scores.append(evidence["score"])
    return max(scores)

def read_results(exomiser_jsonl, disease_id):
    results = {}
    with open(exomiser_jsonl) as fh:
        for line in fh:
            gene = json.loads(line)
            gene_score, variants = pick_variants(gene)
            if not variants:
                continue
            key = (gene["geneSymbol"], gene_score["modeOfInheritance"])
            results[key] = {
                "epcr": disease_score(gene, disease_id),
                "variants": variants,
            }
    return results

proband_id, disease_id, exomiser_jsonl, output_csv = sys.argv[1:]
disease_id = disease_id.strip().lower()

results = read_results(exomiser_jsonl, disease_id)

with open(output_csv, "w", newline="") as fh:
    writer = csv.writer(fh)
    writer.writerow(HEADER)
    for (gene, moi), result in results.items():
        variants = result["variants"]
        if len(variants) > 2:
            print(
                f"WARNING: {gene} {moi} has {len(variants)} "
                "variants, keeping the first two",
                file=sys.stderr,
            )
        first = variants[0]
        second = variants[1] if len(variants) > 1 else [""] * 4
        finding_type = "primary" if result["epcr"] > 0 else "secondary"
        # notes is left empty to be filled in manually
        writer.writerow(
            [proband_id] + first + second + [f"{result['epcr']:.4f}", finding_type, ""]
        )
