#!/usr/bin/env bash
# Checks that this machine can run the tutorial labs. Prints one line per check, then
# ALL PASS or the list of failures. Run it from the repo root, with the environment
# you will use in the session already active (conda activate axi).
set -u
cd "$(dirname "$0")"
ROOT=$(pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=()

ok()   { printf '  [PASS] %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; fails+=("$1"); }
note() { printf '         %s\n' "$1"; }

echo "Checking the environment in $ROOT"

if command -v verilator >/dev/null; then
  ok "verilator: $(verilator --version)"
else
  bad "verilator not on PATH (conda activate axi; see SETUP.md step 2)"
fi

# The compiler Verilator was configured with, which is not necessarily the one on PATH.
if command -v verilator >/dev/null; then
  cxx=$(sed -n 's/^CXX *= *//p' "$(verilator --getenv VERILATOR_ROOT)/include/verilated.mk" | awk '{print $1}')
  if [ -n "$cxx" ] && command -v "$cxx" >/dev/null; then
    ok "C++ compiler used by Verilator: $("$cxx" --version 2>/dev/null | head -1)"
  else
    bad "Verilator's C++ compiler '${cxx:-?}' not found (Ubuntu: sudo apt install build-essential; macOS: xcode-select --install)"
  fi
fi

if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
  ok "python3 $(python3 -c 'import sys; print(sys.version.split()[0])') at $(command -v python3)"
else
  bad "python3 >= 3.11 required (conda activate axi)"
fi

if v=$(python3 -c 'import cocotb; print(cocotb.__version__)' 2>/dev/null); then
  case "$v" in 2.1.*) ok "cocotb $v" ;; *) bad "cocotb $v found, 2.1.x required" ;; esac
else
  bad "cocotb not installed in this python (pip install cocotb==2.1.0)"
fi
if python3 -c 'import cocotbext.axi' 2>/dev/null; then
  ok "cocotbext-axi $(python3 -c 'import importlib.metadata as m; print(m.version("cocotbext-axi"))')"
else
  bad "cocotbext-axi not installed (pip install cocotbext-axi==0.1.28)"
fi

# The simulator must evaluate SVA correctly, or correct checkers are silently disarmed.
if command -v verilator >/dev/null; then
  if verilator --binary --assert --timing -Wno-fatal -Wno-lint -Wno-style \
       tools/sva_smoke/sva_smoke.sv --top-module sva_smoke -Mdir "$TMP/smoke" -o V \
       >"$TMP/smoke.log" 2>&1; then
    "$TMP/smoke/V" +verilator+error+limit+100 2>&1 \
      | grep -oE '^\[[0-9]+\].*in sva_smoke\.[a-z_0-9]+' \
      | sed -E 's/^\[([0-9]+)\].*\.([A-Za-z0-9_]+)$/\1 \2/' | sort -u > "$TMP/smoke.got"
    if diff -q tools/sva_smoke/expected.txt "$TMP/smoke.got" >/dev/null; then
      ok "SVA evaluation smoke test"
    else
      bad "SVA evaluation smoke test: this Verilator mis-evaluates assertions"
      diff tools/sva_smoke/expected.txt "$TMP/smoke.got" | sed 's/^/         /'
      note "install verilator=5.052 from conda-forge (SETUP.md step 2)"
    fi
  else
    bad "could not build the SVA smoke test (see below)"
    tail -5 "$TMP/smoke.log" | sed 's/^/         /'
  fi
fi

# The lab bench itself, end to end, with no checkers.
if [ ${#fails[@]} -eq 0 ]; then
  if COCOTB_LOG_LEVEL=WARNING python3 tb/run.py --checkers none \
       --build-dir "$TMP/lab" >"$TMP/lab.log" 2>&1 \
     && grep -q 'testcase' "$TMP/lab/results.xml" 2>/dev/null \
     && ! grep -q '<failure' "$TMP/lab/results.xml"; then
    ok "lab bench builds and passes its clean run"
  else
    bad "lab bench clean run"
    tail -8 "$TMP/lab.log" | sed 's/^/         /'
  fi
fi

echo
if [ ${#fails[@]} -eq 0 ]; then
  echo "ALL PASS"
else
  echo "${#fails[@]} FAILED:"
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
