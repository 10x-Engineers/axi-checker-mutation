#!/usr/bin/env python3
"""Qualify a checker set against the mutant catalog.

    python3 harness/qualify.py --checkers hand_written -j 8
    python3 harness/qualify.py --checkers hand_written --only aw-valid-drop

Every mutant gets exactly one verdict:
  CORRECT       a rule mapped to the mutant's clause fired within `window` cycles
  LATE          something fired, but the wrong rule, or the right one too late
  MISSED        nothing new fired
  NOT_INJECTED  the mutant's trigger never occurred (excluded from the denominator)
  BROKEN        the real-path data check failed -- an interposer fault, never a verdict
  ERROR         the simulation did not run to completion (no results.xml)

A rule that already fires on the clean run is noise: it is reported as a false
positive and can never earn a kill, or a checker that always fires would kill everything.
"""

import argparse
import concurrent.futures as cf
import json
import os
import re
import subprocess
import sys
import tomllib
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLK_PS = 10_000  # tb/test_axi.py drives a 10 ns clock; Verilator reports times in ps

FIRE = re.compile(r"^\[(\d+)\] %Error: \S+ Assertion failed in tb_top\.u_chk\.(\S+?): "
                  r"'(?:assert|assume)' failed\.", re.M)
INJECT = re.compile(r"^\[MUT\] INJECT id=\S* t=(\d+)", re.M)


def load_toml(path):
    with open(path, "rb") as f:
        return tomllib.load(f)


def plusargs(m):
    args = [f"+mut_id={m['id']}", f"+mut_chan={m['chan']}", f"+mut_op={m['op']}"]
    for k in ("nth", "tfield", "tval", "xfield", "xval", "stall"):
        if k in m:
            args.append(f"+mut_{k}={m[k]}")
    return args


def run(checkers, tag, pargs, skip_build):
    test_dir = ROOT / "build" / checkers / "runs" / tag
    test_dir.mkdir(parents=True, exist_ok=True)
    log = test_dir / "sim.log"
    cmd = [sys.executable, str(ROOT / "tb" / "run.py"), "--checkers", checkers,
           "--test-dir", str(test_dir)]
    if skip_build:
        cmd.append("--skip-build")
    if pargs:
        cmd += ["--plusarg", *pargs]
    env = dict(os.environ, COCOTB_LOG_LEVEL="WARNING")
    with open(log, "w") as f:
        subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, env=env, cwd=ROOT)
    text = log.read_text(errors="replace")
    passed, ran = False, False
    xml = test_dir / "results.xml"
    if xml.exists():
        cases = list(ET.parse(xml).getroot().iter("testcase"))
        ran = bool(cases)
        passed = ran and not any(c.find("failure") is not None or c.find("error") is not None
                                 for c in cases)
    fires = [(int(t), name.rsplit(".", 1)[-1]) for t, name in FIRE.findall(text)]
    inj = INJECT.findall(text)
    return {"ran": ran, "passed": passed, "fires": fires,
            "inject": int(inj[0]) if inj else None, "log": str(log)}


def grade(m, res, noise, rulemap):
    if not res["ran"]:
        return "ERROR", f"simulation did not complete; see {res['log']}", []
    if not res["passed"]:
        return "BROKEN", f"real-path data check failed; see {res['log']}", []
    t0 = res["inject"]
    if t0 is None:
        return "NOT_INJECTED", "trigger never occurred", []
    window = m.get("window", 1) * CLK_PS
    new = [(t, r) for t, r in res["fires"] if r not in noise]
    pre = sorted({r for t, r in new if t < t0})
    post = [(t, r) for t, r in new if t >= t0]
    ok = [(t, r) for t, r in post if rulemap.get(r) in m["clauses"] and t - t0 <= window]
    if ok:
        t, r = ok[0]
        return "CORRECT", f"{r} @ +{(t - t0) // CLK_PS} cyc", pre
    masked = sorted({r for t, r in res["fires"]
                     if r in noise and rulemap.get(r) in m["clauses"] and t0 <= t <= t0 + window})
    note = f" (right rule {', '.join(masked)} is noise on the clean run)" if masked else ""
    if post:
        t, r = post[0]
        why = "wrong rule" if rulemap.get(r) not in m["clauses"] else "late"
        return "LATE", f"{why}: {r} [{rulemap.get(r, '?')}] @ +{(t - t0) // CLK_PS} cyc{note}", pre
    return "MISSED", f"no new rule fired{note}", pre


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkers", required=True)
    ap.add_argument("--only", nargs="*", help="mutant ids")
    ap.add_argument("-j", type=int, default=os.cpu_count() or 4)
    args = ap.parse_args()

    catalog = load_toml(ROOT / "catalog" / "mutants.toml")["mutant"]
    clauses = load_toml(ROOT / "catalog" / "clauses.toml")
    for m in catalog:
        unknown = [c for c in m["clauses"] if c not in clauses]
        if unknown:
            sys.exit(f"{m['id']}: unknown clause {unknown}")
    if args.only:
        catalog = [m for m in catalog if m["id"] in args.only]
    rmap_path = ROOT / "checkers" / args.checkers / "rules.toml"
    rulemap = load_toml(rmap_path)["rules"] if rmap_path.exists() else {}

    clean = run(args.checkers, "clean", [], skip_build=False)
    if not clean["ran"] or not clean["passed"]:
        sys.exit(f"clean run did not pass: {clean['log']}")
    if clean["inject"] is not None:
        sys.exit("clean run reported an injection -- interposer armed without +mut_chan")
    noise = Counter(r for _, r in clean["fires"])

    with cf.ThreadPoolExecutor(args.j) as ex:
        futs = {m["id"]: ex.submit(run, args.checkers, m["id"], plusargs(m), True)
                for m in catalog}
        results = {k: f.result() for k, f in futs.items()}

    rows, pre_fp = [], set()
    for m in catalog:
        verdict, detail, pre = grade(m, results[m["id"]], noise, rulemap)
        pre_fp.update(pre)
        rows.append({"id": m["id"], "class": m["class"], "clauses": m["clauses"],
                     "verdict": verdict, "detail": detail, "pre_injection_fires": pre})

    out = ROOT / "build" / args.checkers / "qualify.json"
    out.write_text(json.dumps({"checkers": args.checkers, "noise": dict(noise),
                               "rows": rows}, indent=2))

    print(f"\n## Checker set: {args.checkers}\n")
    print("| mutant | class | verdict | detail |\n|---|---|---|---|")
    for r in rows:
        print(f"| {r['id']} | {r['class']} | **{r['verdict']}** | {r['detail']} |")
    graded = [r for r in rows if r["verdict"] in ("CORRECT", "LATE", "MISSED")]
    c = Counter(r["verdict"] for r in rows)
    print(f"\nCORRECT {c['CORRECT']}/{len(graded)} · LATE {c['LATE']} · MISSED {c['MISSED']}"
          f" · NOT_INJECTED {c['NOT_INJECTED']} · BROKEN {c['BROKEN']} · ERROR {c['ERROR']}")
    print(f"False positives on clean traffic: {len(noise)} rules ({sum(noise.values())} fires)")
    for r, n in noise.most_common():
        print(f"  - {r} [{rulemap.get(r, '?')}] x{n}")
    if pre_fp:
        print(f"Fired on legal back-pressure before any injection: {', '.join(sorted(pre_fp))}")
    print(f"\n{out}")
    return 1 if c["BROKEN"] or c["ERROR"] else 0


if __name__ == "__main__":
    sys.exit(main())
