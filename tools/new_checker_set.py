#!/usr/bin/env python3
"""Bring your own checker set, from any LLM or written by hand.

    python3 tools/new_checker_set.py my_qwen --from ~/Downloads/axi_checker_set.sv
    python3 tools/new_checker_set.py my_qwen           # file already in checkers/my_qwen/

1. copies the file to checkers/<name>/axi_checker_set.sv (it must implement
   checkers/llm_prompt/port_list.sv exactly);
2. lints it with Verilator;
3. drafts checkers/<name>/rules.toml: which catalog clause each assertion checks.
   The draft is keyword-based, from the label, the property and its // SPEC: comment,
   and is only a starting point -- REVIEW IT, because the verdicts depend on it.
   A rule the drafter cannot place is OTHER: its fires still count, but only as LATE.
Then run:  python3 harness/qualify.py --checkers <name>
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Label/comment keyword rules, most specific first: (clause, all-of, any-of).
KEYS = [
    ("EXCL_FAIL_OKAY",        ["exokay"], ["needs_excl", "monitor", "intervening", "earlier exclusive read", "fail"]),
    ("EXCL_READ_NO_MIX",      [], ["mix", "all_beats", "every beat", "every read data", "exokay_consistent"]),
    ("EXCL_WRITE_AFTER_READ", ["excl"], ["read_done", "after_read", "rd_first", "read part", "read has completed"]),
    ("EXCL_POW2",             ["excl"], ["pow"]),
    ("EXCL_ALIGN",            ["excl"], ["align"]),
    ("EXCL_LEN",              ["excl"], ["len"]),
    ("EXOKAY_WRITE",          ["exokay"], ["_b_", "bresp", "write"]),
    ("EXOKAY_READ",           ["exokay"], ["_r_", "rresp", "read"]),
    ("SAMEID_ORDER",          [], ["same_id", "same id", "inorder", "in_order"]),
    ("NO_4KB_CROSS",          ["4k"], ["cross", "bound"]),
    ("BURST_RESERVED",        ["burst"], ["reserved"]),
    ("WRAP_LEN",              ["wrap"], ["len"]),
    ("FIXED_LEN",             ["fixed"], ["len"]),
    ("DEP_B_AFTER_W",         [], ["bid", "b_id", "bvalid_after", "b_after", "write_resp"]),
    ("WLAST",                 [], ["wlast", "w_last", "w_no_early", "beats_beyond", "leading_w", "w_leading", "w_first_len"]),
    ("RLAST",                 [], ["rlast", "r_last", "r_no_early"]),
    ("DEP_R_AFTER_AR",        [], ["rid", "r_id", "rvalid_before", "read_resp"]),
]
SKIP = {"reset", "rst", "known", "cache", "region", "size", "strb", "strobe", "aligned", "bytes"}
HOLD_PAST = re.compile(r"(\w*valid)\s*\|->\s*##1\s*\(?\s*\1\s*\|\|\s*\$past", re.I)
FOUR_KB = re.compile(r">>\s*12\b|\b4096\b|'h1000\b|'hfff\b", re.I)
STABLE = re.compile(r"\$stable")
HOLD = re.compile(r"(\w*valid)\s*&&\s*!\s*\w*ready\s*\)?\s*(\|=>\s*\(?\s*\1\b|\|->\s*##1\s*\(?\s*\1\b)", re.I)


def _match(text):
    for clause, need, anyof in KEYS:
        if all(n in text for n in need) and any(a in text for a in anyof):
            return clause
    return None


def classify(label, prop, comment):
    lab, com = label.lower(), comment.lower()
    if (HOLD.search(prop) or HOLD_PAST.search(prop)) and "$stable" not in prop:
        return "HS_VALID_HOLD"
    if STABLE.search(prop):
        return "HS_INFO_STABLE"
    if SKIP & set(lab.split("_")) and not any(k in lab for k in ("excl", "exokay", "wrap", "4k")):
        return "OTHER"
    c = _match(lab) or _match(com) or ("NO_4KB_CROSS" if FOUR_KB.search(prop) else None)
    if c in ("WLAST", "RLAST") and "early" in lab:
        return [c, "EARLY_TERM"]
    return c or "OTHER"


def assertions(sv):
    lines = sv.split("\n")
    out = []
    for i, l in enumerate(lines):
        m = re.match(r"\s*(\w+)\s*:\s*assert\s+property", l)
        if not m:
            continue
        comment = ""
        for j in range(i - 1, max(i - 8, -1), -1):
            if "//" in lines[j]:
                comment = lines[j].split("//", 1)[1].strip()
                break
            if lines[j].strip():
                break
        prop = ""
        for k in range(i, min(i + 12, len(lines))):   # the statement, up to its ';'
            prop += " " + lines[k].split("//", 1)[0]
            if ";" in lines[k].split("//", 1)[0]:
                break
        out.append((m.group(1), prop, comment))
    return out


def draft(sv):
    return [(lab, classify(lab, prop, com), com) for lab, prop, com in assertions(sv)]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name")
    ap.add_argument("--from", dest="src")
    ap.add_argument("--force", action="store_true", help="overwrite an existing rules.toml")
    args = ap.parse_args()

    d = ROOT / "checkers" / args.name
    dst = d / "axi_checker_set.sv"
    if args.src:
        d.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(args.src, dst)
    if not dst.exists():
        sys.exit(f"{dst} not found; pass --from <file.sv>")
    sv = dst.read_text(errors="replace")

    p = subprocess.run(["verilator", "--lint-only", "--assert", "-Wno-fatal", "-Wno-lint", "-Wno-style",
                        "--top-module", "axi_checker_set", str(dst)], capture_output=True, text=True)
    errs = [l for l in (p.stdout + p.stderr).splitlines() if "%Error" in l]
    print(f"lint: {'clean' if not errs else f'{len(errs)} error(s)'}")
    for e in errs[:15]:
        print("  " + e)

    rows = draft(sv)
    rules = d / "rules.toml"
    if rules.exists() and not args.force:
        print(f"{rules} exists; not overwriting (use --force)")
    else:
        body = ["# DRAFT by tools/new_checker_set.py: review every line against the assertion it names.",
                "# Clause keys are defined in catalog/clauses.toml; OTHER = not a catalog clause.", "[rules]"]
        for lab, c, com in rows:
            val = "[" + ", ".join(f'"{x}"' for x in c) + "]" if isinstance(c, list) else f'"{c}"'
            body.append(f"{lab} = {val}" + (f"  # {com[:90]}" if com else ""))
        rules.write_text("\n".join(body) + "\n")
        print(f"drafted {rules.relative_to(ROOT)} for {len(rows)} assertions "
              f"({sum(1 for _, c, _ in rows if c == 'OTHER')} OTHER)")
    print(f"next: python3 harness/qualify.py --checkers {args.name}")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
