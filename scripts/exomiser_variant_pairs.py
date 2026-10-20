"""
Create hackathon submission csv file

Usage:
    python exomiser_variant_pairs.py <proband_id> <exomiser_jsonl> <output_csv>
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

def to_variant(v):
    return [v["contigName"], str(v["start"]), v["ref"], v["alt"]]

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

def read_results(exomiser_jsonl):
    results = {}
    with open(exomiser_jsonl) as fh:
        for line in fh:
            gene = json.loads(line)
            gene_score, variants = pick_variants(gene)
            if not variants:
                continue
            key = (gene["geneSymbol"], gene_score["modeOfInheritance"])
            results[key] = {
                "epcr": gene_score["combinedScore"],
                "variants": variants,
            }
    return results

proband_id, exomiser_jsonl, output_csv = sys.argv[1:]

results = read_results(exomiser_jsonl)

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
        
        writer.writerow([proband_id] + first + second + [f"{result['epcr']:.4f}", "", ""])
