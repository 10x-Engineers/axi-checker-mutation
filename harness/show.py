#!/usr/bin/env python3
"""Run ONE mutant (or the clean traffic) against one checker set and explain the result.

    python3 harness/show.py --checkers llm_haiku                      # clean run: fire table
    python3 harness/show.py --checkers llm_haiku --mutant b-valid-drop
    python3 harness/show.py --checkers llm_haiku --mutant b-valid-drop --waves

--waves builds a separate traced snapshot and prints the VCD path; open it with
`surfer <file>` or `gtkwave <file>` and look at tb_top.obs_* around the INJECT time.
"""

import argparse
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import qualify  # noqa: E402

ROOT = qualify.ROOT


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkers", required=True)
    ap.add_argument("--mutant", help="id from catalog/mutants.toml or catalog/legal.toml")
    ap.add_argument("--waves", action="store_true")
    args = ap.parse_args()

    entries = {m["id"]: m for m in qualify.load_toml(ROOT / "catalog" / "mutants.toml")["mutant"]}
    entries.update({p["id"]: p for p in qualify.load_toml(ROOT / "catalog" / "legal.toml")["perturbation"]})
    m = entries.get(args.mutant) if args.mutant else None
    if args.mutant and m is None:
        sys.exit(f"unknown mutant '{args.mutant}'; ids are in catalog/*.toml")
    rmap_path = ROOT / "checkers" / args.checkers / "rules.toml"
    rulemap = qualify.load_toml(rmap_path)["rules"] if rmap_path.exists() else {}

    tag = (args.mutant or "clean") + ("-waves" if args.waves else "")
    res = qualify.run(args.checkers, tag, qualify.plusargs(m) if m else [], skip_build=False,
                      waves=args.waves)
    print(f"\nchecker set : {args.checkers}")
    print(f"run         : {args.mutant or 'clean traffic, no mutant'}")
    if m:
        print(f"what        : {m.get('why') or ', '.join(m['clauses'])}")
    print(f"real path   : {'data intact' if res['passed'] else 'DATA CHECK FAILED'}")
    if m:
        t0 = res["inject"]
        print(f"injected at : {t0 // qualify.CLK_PS} cycles ({t0} ps)" if t0 is not None
              else "injected at : never (trigger not reached)")
    print("\nrule fired                                  clause            count  first @cycle")
    first, n = {}, Counter()
    for t, r in res["fires"]:
        n[r] += 1
        first.setdefault(r, t)
    for r, t in sorted(first.items(), key=lambda kv: kv[1]):
        clause = ", ".join(sorted(qualify.clauses_of(rulemap, r))) or "-"
        print(f"  {r:42s} {clause:16s} {n[r]:6d}  {t // qualify.CLK_PS}")
    if not first:
        print("  (nothing fired)")
    if m:
        clean = qualify.run(args.checkers, "clean", [], skip_build=True, waves=args.waves)
        noise = Counter(r for _, r in clean["fires"])
        if "clauses" in m:
            verdict, detail, pre = qualify.grade(m, res, noise, rulemap)
            print(f"\nVERDICT     : {verdict}  {detail}")
            if pre:
                print(f"              (fired before injection, on legal back-pressure: {', '.join(pre)})")
        else:
            new = sorted({r for _, r in res["fires"] if r not in noise})
            print(f"\nVERDICT     : {'FLAGGED  ' + ', '.join(new) if new else 'CLEAN'}  (legal perturbation)")
    print(f"\nlog: {res['log']}")
    if args.waves:
        vcd = sorted(Path(res["log"]).parent.glob("*.vcd")) + sorted(Path(res["log"]).parent.glob("*.fst"))
        print(f"waves: {vcd[0] if vcd else '(no trace file found)'}")


if __name__ == "__main__":
    main()
