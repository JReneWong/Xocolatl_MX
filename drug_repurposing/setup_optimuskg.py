"""
Setup duckdb with local parquet files
"""

import argparse
import pathlib
import sys
import duckdb

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("data_dir", type=pathlib.Path,
                    help="directory with the OptimusKG nodes/edges parquet files")
parser.add_argument("--db-dir", type=pathlib.Path, default=pathlib.Path("."),
                    help="directory to write optimuskg.duckdb to (default: current directory)")
args = parser.parse_args()

DATA = args.data_dir
DB_PATH = args.db_dir / "optimuskg.duckdb"

def pick(*names):
    for n in names:
        p = DATA / n
        if p.exists():
            return p.as_posix()
    sys.exit(f"Could not find any of {names} in {DATA}")

con = duckdb.connect(DB_PATH)

tables = {r[0] for r in con.execute("SHOW TABLES").fetchall()}
if "nodes" not in tables:
    nodes_file = pick("nodes.parquet", "largest_connected_component_nodes.parquet")
    edges_file = pick("edges.parquet", "largest_connected_component_edges.parquet")
    print(f"Building {DB_PATH} from local parquet")
    con.execute(f"CREATE TABLE nodes AS SELECT * FROM read_parquet('{nodes_file}')")
    con.execute(f"CREATE TABLE edges AS SELECT * FROM read_parquet('{edges_file}')")
    con.execute('CREATE INDEX idx_nodes_id ON nodes(id)')
    con.execute('CREATE INDEX idx_edges_from ON edges("from")')
    con.execute('CREATE INDEX idx_edges_to ON edges("to")')
    con.execute('CREATE INDEX idx_edges_label ON edges(label)')

print("\nnodes columns:", con.execute("DESCRIBE nodes").df()[["column_name", "column_type"]].values.tolist())
print("edges columns:", con.execute("DESCRIBE edges").df()[["column_name", "column_type"]].values.tolist())

con.close()
