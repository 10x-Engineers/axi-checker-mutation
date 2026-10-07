Write a SystemVerilog AXI4 protocol checker, with a functional coverage model, from the AMBA AXI
Protocol Specification.

Inputs (the ONLY files you may read):
- spec/IHI0022L_partA_ch1-6.txt: ARM IHI 0022 Issue L, Part A chapters A1-A6, as text.
- port_list.sv: the module header you must implement, exactly as given (name, parameters, ports).
- lint.sh: `bash lint.sh <your output dir>` runs Verilator --lint-only on your file.

Scope: AXI4 only. Ignore AXI5 extensions (atomics, MTE, snoop/DVM, wakeup, poison, credited
transport, and the like). The checker is passive: it observes one AXI4 interface between one
Manager and one Subordinate and must flag any behaviour of EITHER side that the specification
forbids. ACLK rising edge; ARESETn active-low.

Deliver <output dir>/axi_checker_set.sv containing module axi_checker_set with the port list as given:
1. Concurrent SVA assertions for every rule you can derive from the specification that is checkable
   from these signals. Use auxiliary logic (counters, per-ID tables, FIFOs) where a rule needs state.
2. Above each assertion, a comment `// SPEC: <section> p.<page>: <the rule, in a few words>`.
3. Give every assertion a unique label. Use `assert property (...)`, not immediate asserts.
4. A functional coverage model as labelled `cover property` statements, each with a `// SPEC:` comment.
5. It must pass lint.sh with no %Error. Target Verilator 5.05x: concurrent assertions with |->, |=>,
   ##N, ##[m:n], $past, $stable, $rose, $fell, disable iff are supported.

Do not read, search or list any other file or directory, and do not use the web. When done, reply
with a short summary: number of assertions, number of covers, and which rule areas you covered.
