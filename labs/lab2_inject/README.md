# Lab 2: Anatomy of a kill (30 min)

[中文](README.zh.md)

## 2.1 The interposer (5 min)

Read the header of `rtl/axi_mut_interposer.sv`. Answer:
- Which bus do the checkers watch, and which do the manager and DUT use?
- What is the only thing the interposer does to the real traffic, and why is that legal?

## 2.2 One violation on the waveform (10 min)

```bash
python3 harness/show.py --checkers llm_opus --mutant aw-valid-drop --waves
surfer <the .vcd path it prints>        # or gtkwave
```

Plot `obs_awvalid`, `obs_awready`, `m_axi_awvalid`, `s_axi_awvalid` around the INJECT time.
- Which sentence of the spec does the observed bus break?
- What did the real manager and the DUT each see?
- Which rule fired, and on which cycle?

## 2.3 Verdicts (15 min)

Run each and explain the verdict:

```bash
python3 harness/show.py --checkers llm_opus  --mutant aw-valid-drop
python3 harness/show.py --checkers llm_haiku --mutant b-before-wlast-hs
python3 harness/show.py --checkers llm_opus  --mutant same-id-read-swap
python3 harness/show.py --checkers llm_opus  --mutant exokay-after-intervening-write
python3 harness/show.py --checkers llm_opus  --mutant diff-id-read-swap
```

For each: which clause is involved, who noticed, and why? Mutant definitions are in
`catalog/mutants.toml` and `catalog/legal.toml`.

## Finished early?

Run `python3 harness/matrix.py pulp_axi llm_opus`. Compare `ar-4kb-cross` with
`ar-4kb-cross-after-wrap`. Explain the difference.
