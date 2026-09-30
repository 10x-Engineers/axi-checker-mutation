#!/usr/bin/env python3
"""Build and run the lab testbench for one checker set, optionally with one mutant.

    python3 tb/run.py --checkers hand_written                  # clean run
    python3 tb/run.py --checkers hand_written --plusarg +mut_chan=AW +mut_op=VALID_DROP

Each checker set gets its own build directory, so switching sets never recompiles
another set's snapshot. Mutants are plusargs, so one build serves the whole catalog.
"""

import argparse
import os
import sys
from pathlib import Path

from cocotb_tools.runner import get_runner

ROOT = Path(__file__).resolve().parent.parent
VAXI = ROOT / "third_party" / "verilog-axi" / "rtl"


def checker_sources(name):
    d = ROOT / "checkers" / name
    if not d.is_dir():
        sys.exit(f"no checker set '{name}' under {ROOT / 'checkers'}")
    flist = d / "files.f"
    srcs, incs = [], []
    if flist.exists():
        for line in flist.read_text().splitlines():
            line = os.path.expandvars(line.split("#", 1)[0].strip())
            if not line:
                continue
            if "$" in line:
                sys.exit(f"{flist}: unset environment variable in '{line}'")
            if line.startswith("+incdir+"):
                incs.append(Path(line[len("+incdir+"):]))
            else:
                srcs.append(Path(line) if Path(line).is_absolute() else d / line)
    srcs.append(d / "axi_checker_set.sv")
    return srcs, incs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkers", default="none")
    ap.add_argument("--plusarg", nargs="*", default=[])
    ap.add_argument("--build-dir", default=None)
    ap.add_argument("--test-dir", default=None)
    ap.add_argument("--waves", action="store_true")
    ap.add_argument("--skip-build", action="store_true",
                    help="reuse the checker set's existing build (parallel mutant runs)")
    args = ap.parse_args()

    chk_srcs, chk_incs = checker_sources(args.checkers)
    sources = [
        ROOT / "rtl" / "axi_mut_pkg.sv",
        ROOT / "rtl" / "axi_mut_chan.sv",
        ROOT / "rtl" / "axi_mut_interposer.sv",
        VAXI / "axi_ram.v",
        *chk_srcs,
        ROOT / "tb" / "tb_top.sv",
    ]
    build_dir = Path(args.build_dir or ROOT / "build" / args.checkers)
    runner = get_runner("verilator")
    if not args.skip_build:
        runner.build(
            sources=sources,
            includes=chk_incs,
            hdl_toplevel="tb_top",
            build_dir=build_dir,
            build_args=["--assert", "-Wno-fatal", "-Wno-lint", "-Wno-style",
                        "-Wno-MULTITOP", "--x-initial", "unique"],
            waves=args.waves,
        )
    runner.test(
        hdl_toplevel="tb_top",
        hdl_toplevel_lang="verilog",
        test_module="test_axi",
        test_dir=Path(args.test_dir or build_dir),
        build_dir=build_dir,
        # Keep running past a failed assertion: every fire is evidence for grading.
        plusargs=["+verilator+error+limit+100000", *args.plusarg],
        waves=args.waves,
    )


if __name__ == "__main__":
    sys.path.insert(0, str(ROOT / "tb"))
    os.environ["PYTHONPATH"] = f"{ROOT / 'tb'}{os.pathsep}{os.environ.get('PYTHONPATH', '')}"
    main()
