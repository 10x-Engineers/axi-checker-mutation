#!/bin/bash
# Syntax/elaboration check only: bash lint.sh <dir containing axi_checker_set.sv>
verilator --lint-only --assert -Wno-fatal -Wno-lint -Wno-style --top-module axi_checker_set "$1"/*.sv
