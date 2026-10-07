#!/usr/bin/env python3
"""Side-by-side kill matrix from the qualify.json of each checker set.

    python3 harness/matrix.py                      # every set run here, plus the reference results
    python3 harness/matrix.py llm_opus pulp_axi    # just these

A set's own run (build/<set>/qualify.json) is used when it exists; otherwise the reference
results shipped in results/<set>/qualify.json.
"""

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MARK = {"CORRECT": "C", "LATE": "L", "MISSED": "·", "NOT_INJECTED": "n/i", "BROKEN": "!", "ERROR": "E",
        "CLEAN": "ok", "FLAGGED": "FP"}


SOURCES = (("build", "this machine"), ("results", "reference"))


def find(name):
    for d, label in SOURCES:
        f = ROOT / d / name / "qualify.json"
        if f.exists():
            return f, label
    sys.exit(f"no results for '{name}': run  python3 harness/qualify.py --checkers {name}")


def union(data, key):
    rows = {}
    for d in data.values():
        for r in d.get(key, []):
            rows.setdefault(r["id"], r)
    return list(rows.values())


def main():
    names = sys.argv[1:] or sorted({p.parent.name for d, _ in SOURCES for p in (ROOT / d).glob("*/qualify.json")})
    data = {}
    for n in names:
        f, label = find(n)
        data[n] = json.loads(f.read_text())
        print(f"{n}: {label} ({f.relative_to(ROOT)})")
    rows, legal = union(data, "rows"), union(data, "legal")
    head = "| mutant | class | " + " | ".join(names) + " |"
    sep = "|---|---|" + "---|" * len(names)
    print("\nC = CORRECT, L = LATE, · = MISSED, - = not measured\n\n" + head + "\n" + sep)
    by = {n: {r["id"]: r for r in d["rows"]} for n, d in data.items()}
    for r in rows:
        print(f"| {r['id']} | {r['class']} | "
              + " | ".join(MARK[by[n][r["id"]]["verdict"]] if r["id"] in by[n] else "-" for n in names) + " |")
    lby = {n: {r["id"]: r for r in d.get("legal", [])} for n, d in data.items()}
    print("\n| legal perturbation | | " + " | ".join(names) + " |\n" + sep)
    for r in legal:
        print(f"| {r['id']} | | "
              + " | ".join(MARK[lby[n][r["id"]]["verdict"]] if r["id"] in lby[n] else "-" for n in names) + " |")
    print("\n| summary | | " + " | ".join(names) + " |\n" + sep)
    for label, fn in (
        ("CORRECT", lambda d: sum(r["verdict"] == "CORRECT" for r in d["rows"])),
        ("LATE", lambda d: sum(r["verdict"] == "LATE" for r in d["rows"])),
        ("MISSED", lambda d: sum(r["verdict"] == "MISSED" for r in d["rows"])),
        ("rules firing on clean traffic", lambda d: len(d["noise"])),
        ("legal perturbations flagged", lambda d: sum(r["verdict"] == "FLAGGED" for r in d.get("legal", []))),
    ):
        print(f"| {label} | | " + " | ".join(str(fn(data[n])) for n in names) + " |")
    classes = Counter(r["class"] for r in rows)
    print("\n| CORRECT by class | n | " + " | ".join(names) + " |\n" + sep)
    for c in classes:
        print(f"| {c} | {classes[c]} | " + " | ".join(
            str(sum(1 for r in data[n]["rows"] if r["class"] == c and r["verdict"] == "CORRECT"))
            for n in names) + " |")


if __name__ == "__main__":
    main()
