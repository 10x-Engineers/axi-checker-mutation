# Third-party files

Copied unmodified from upstream, under their own licences.

| File | Upstream | Commit | Licence |
|---|---|---|---|
| `verilog-axi/rtl/axi_ram.v` | <https://github.com/alexforencich/verilog-axi> | `516bd5d` | MIT (`verilog-axi/COPYING`) |
| `pulp-axi/src/axi_pkg.sv` | <https://github.com/pulp-platform/axi> | `70b8e54` | Solderpad Hardware License 0.51 (`pulp-axi/LICENSE`) |
| `pulp-axi/src/axi_intf.sv` | <https://github.com/pulp-platform/axi> | `70b8e54` | Solderpad Hardware License 0.51 (`pulp-axi/LICENSE`) |

`axi_ram.v` is the design under test. `axi_pkg.sv` is compiled with the `pulp_axi` checker set.
`axi_intf.sv` is read only by `tools/import_pulp.py`, which generates `checkers/pulp_axi/`.
