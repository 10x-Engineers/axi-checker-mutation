#!/usr/bin/env python3
"""Qualify a checker set against the mutant catalog.

    python3 harness/qualify.py --checkers llm_opus -j 8
    python3 harness/qualify.py --checkers llm_opus --only aw-valid-drop

Every mutant gets exactly one verdict:
  CORRECT       a rule mapped to the mutant's clause fired within `window` cycles
  LATE          something fired, but the wrong rule, the right one too late, or only the
                observed-bus data scoreboard (a downstream mismatch)
  MISSED        nothing new fired
  NOT_INJECTED  the mutant's trigger never occurred (excluded from the denominator)
  BROKEN        the real-path data check failed -- an interposer fault, never a verdict
  ERROR         the simulation did not run to completion (no results.xml)

Each legal perturbation (catalog/legal.toml) is graded CLEAN or FLAGGED: a rule that
fires on legal traffic is a false positive.

A rule that already fires on the clean run is noise: it is reported as a false
positive and can never earn a kill, or a checker that always fires would kill everything.
"""

import argparse
import concurrent.futures as cf
import json
import os
import re
import signal
import subprocess
import sys
import tomllib
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLK_PS = 10_000       # tb/test_axi.py drives a 10 ns clock; Verilator reports times in ps
RUN_TIMEOUT_S = 300   # a run takes seconds; a hang is an ERROR, never a wait

FIRE = re.compile(r"^\[(\d+)\] %Error: \S+ Assertion failed in tb_top\.u_chk\.(\S+?): "
                  r"'(?:assert|assume)' failed\.", re.M)
INJECT = re.compile(r"^\[MUT\] INJECT id=\S* t=(\d+)", re.M)
SCOREBOARD = re.compile(r"OBS_MISMATCH t=(\d+)")
SB = "obs_scoreboard"  # the downstream data check: a fire here is never a CORRECT kill


def load_toml(path):
    with open(path, "rb") as f:
        return tomllib.load(f)


def plusargs(m):
    args = [f"+mut_id={m['id']}"]
    for pfx, slot in (("mut_", m), ("mut2_", m.get("companion"))):
        if slot is None:
            continue
        for k in ("chan", "op", "nth", "tfield", "tval", "xfield", "xval", "stall"):
            if k in slot:
                args.append(f"+{pfx}{k}={slot[k]}")
    return args


def run(checkers, tag, pargs, skip_build, waves=False):
    build = ROOT / "build" / (checkers + ("-waves" if waves else ""))
    test_dir = build / "runs" / tag
    test_dir.mkdir(parents=True, exist_ok=True)
    log = test_dir / "sim.log"
    cmd = [sys.executable, str(ROOT / "tb" / "run.py"), "--checkers", checkers,
           "--build-dir", str(build), "--test-dir", str(test_dir)]
    if waves:
        cmd.append("--waves")
    if skip_build:
        cmd.append("--skip-build")
    if pargs:
        cmd += ["--plusarg", *pargs]
    env = dict(os.environ, COCOTB_LOG_LEVEL="WARNING")
    timed_out = False
    with open(log, "w") as f:
        # Own process group, so a timeout also kills the simulator cocotb started.
        p = subprocess.Popen(cmd, stdout=f, stderr=subprocess.STDOUT, env=env, cwd=ROOT,
                             start_new_session=True)
        try:
            p.wait(timeout=RUN_TIMEOUT_S)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(p.pid, signal.SIGKILL)
            p.wait()
    text = log.read_text(errors="replace")
    passed, ran = False, False
    xml = test_dir / "results.xml"
    if xml.exists():
        cases = list(ET.parse(xml).getroot().iter("testcase"))
        ran = bool(cases)
        passed = ran and not any(c.find("failure") is not None or c.find("error") is not None
                                 for c in cases)
    fires = [(int(t), name.rsplit(".", 1)[-1]) for t, name in FIRE.findall(text)]
    fires += [(int(t), SB) for t in SCOREBOARD.findall(text)]
    fires.sort()
    inj = INJECT.findall(text)
    if timed_out:
        ran = passed = False
    return {"timed_out": timed_out, "ran": ran, "passed": passed, "fires": fires,
            "inject": int(inj[0]) if inj else None, "log": str(log)}


def clauses_of(rulemap, rule):
    v = rulemap.get(rule, [])
    return set([v] if isinstance(v, str) else v)


def grade(m, res, noise, rulemap):
    if not res["ran"]:
        why = f"timed out after {RUN_TIMEOUT_S} s" if res["timed_out"] else "did not complete"
        return "ERROR", f"simulation {why}; see {res['log']}", []
    if not res["passed"]:
        return "BROKEN", f"real-path data check failed; see {res['log']}", []
    t0 = res["inject"]
    if t0 is None:
        return "NOT_INJECTED", "trigger never occurred", []
    window = m.get("window", 1) * CLK_PS
    new = [(t, r) for t, r in res["fires"] if r not in noise]
    pre = sorted({r for t, r in new if t < t0})
    post = [(t, r) for t, r in new if t >= t0]
    want = set(m["clauses"])
    ok = [(t, r) for t, r in post if clauses_of(rulemap, r) & want and t - t0 <= window]
    if ok:
        t, r = ok[0]
        return "CORRECT", f"{r} @ +{(t - t0) // CLK_PS} cyc", pre
    masked = sorted({r for t, r in res["fires"]
                     if r in noise and clauses_of(rulemap, r) & want and t0 <= t <= t0 + window})
    note = f" (right rule {', '.join(masked)} is noise on the clean run)" if masked else ""
    if post:
        t, r = post[0]
        why = ("downstream data mismatch" if r == SB
               else "late" if clauses_of(rulemap, r) & want else "wrong rule")
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
    if SB in noise:
        sys.exit(f"the observed-bus scoreboard fired on the clean run: {clean['log']}")

    legal = load_toml(ROOT / "catalog" / "legal.toml")["perturbation"]
    if args.only:
        legal = [p for p in legal if p["id"] in args.only]
    with cf.ThreadPoolExecutor(args.j) as ex:
        futs = {m["id"]: ex.submit(run, args.checkers, m["id"], plusargs(m), True)
                for m in catalog + legal}
        results = {k: f.result() for k, f in futs.items()}

    rows, pre_fp = [], set()
    for m in catalog:
        verdict, detail, pre = grade(m, results[m["id"]], noise, rulemap)
        pre_fp.update(pre)
        rows.append({"id": m["id"], "class": m["class"], "clauses": m["clauses"],
                     "verdict": verdict, "detail": detail, "pre_injection_fires": pre})

    # A legal perturbation must leave every checker silent: any rule that fires on it
    # and not on the clean run is a false positive, whenever it fires.
    legal_rows = []
    for p in legal:
        res = results[p["id"]]
        if not res["ran"]:
            v, det = "ERROR", f"simulation did not complete; see {res['log']}"
        elif not res["passed"]:
            v, det = "BROKEN", f"real-path data check failed; see {res['log']}"
        elif res["inject"] is None:
            v, det = "NOT_INJECTED", "trigger never occurred"
        else:
            if any(r == SB for _, r in res["fires"]):
                sys.exit(f"the observed-bus scoreboard fired on legal perturbation {p['id']}")
            fired = sorted({r for _, r in res["fires"] if r not in noise})
            v, det = ("FLAGGED", ", ".join(fired)) if fired else ("CLEAN", "")
        legal_rows.append({"id": p["id"], "why": p["why"], "verdict": v, "detail": det})

    # A partial run (--only) must not overwrite the full results that matrix.py reads.
    out = ROOT / "build" / args.checkers / ("qualify_only.json" if args.only else "qualify.json")
    out.write_text(json.dumps({"checkers": args.checkers, "noise": dict(noise),
                               "rows": rows, "legal": legal_rows}, indent=2))

    print(f"\n## Checker set: {args.checkers}\n")
    print("| mutant | class | verdict | detail |\n|---|---|---|---|")
    for r in rows:
        print(f"| {r['id']} | {r['class']} | **{r['verdict']}** | {r['detail']} |")
    graded = [r for r in rows if r["verdict"] in ("CORRECT", "LATE", "MISSED")]
    c = Counter(r["verdict"] for r in rows)
    print(f"\nCORRECT {c['CORRECT']}/{len(graded)} · LATE {c['LATE']} · MISSED {c['MISSED']}"
          f" · NOT_INJECTED {c['NOT_INJECTED']} · BROKEN {c['BROKEN']} · ERROR {c['ERROR']}")
    print("\n| legal perturbation | verdict | rules that fired |\n|---|---|---|")
    for r in legal_rows:
        print(f"| {r['id']} | **{r['verdict']}** | {r['detail']} |")
    lc = Counter(r["verdict"] for r in legal_rows)
    print(f"\nLegal perturbations: CLEAN {lc['CLEAN']}/{len(legal_rows)} · FLAGGED {lc['FLAGGED']}"
          f" · NOT_INJECTED {lc['NOT_INJECTED']} · BROKEN {lc['BROKEN']} · ERROR {lc['ERROR']}")
    print(f"False positives on clean traffic: {len(noise)} rules ({sum(noise.values())} fires)")
    for r, n in noise.most_common():
        print(f"  - {r} [{rulemap.get(r, '?')}] x{n}")
    if pre_fp:
        print(f"Fired on legal back-pressure before any injection: {', '.join(sorted(pre_fp))}")
    print(f"\n{out}")
    return 1 if c["BROKEN"] or c["ERROR"] or lc["BROKEN"] or lc["ERROR"] else 0


if __name__ == "__main__":
    sys.exit(main())
