# Lab 3: Extend the catalog, fix a checker (30 min)

[中文](README.zh.md)

## 3.1 A catalog entry (5 min)

```toml
[[mutant]]
id = "excl-len32"
class = "exclusive"
clauses = ["EXCL_LEN"]      # key in catalog/clauses.toml
chan = "AR"                 # channel to corrupt
op = "OVERRIDE"             # VALID_DROP | GLITCH | OVERRIDE | HS_DELAY | SWAP
tfield = "ARADDR"           # trigger: the beat where this field...
tval = "1000"               # ...has this value
xfield = "ARLOCK"           # field to change...
xval = "1"                  # ...to this value (observed bus only)
```

A mutant must break a **MUST** rule, cited by section and page, and must be injected (not
`NOT_INJECTED`).

## 3.2 Write a mutant (15 min)

Pick one:

| Rule (IHI 0022 Issue L) | |
|---|---|
| §A3.1.1 p.43 | Size must not exceed the data width |
| §A3.1.4 p.47 | a WRAP start address must be aligned to Size |
| §A6.3.4 p.112 | no mix of OKAY and EXOKAY in one exclusive read |
| your own | any MUST that the stimulus in `tb/test_axi.py` can trigger |

1. Add the clause to `catalog/clauses.toml` if it is new.
2. Add the mutant to `catalog/mutants.toml`.
3. Check that it is injected:
   ```bash
   python3 harness/qualify.py --checkers llm_opus --only <your-id>
   ```
4. Update each set's `rules.toml` for rules that check your clause, then run all sets.

## 3.3 Fix a checker (10 min, stretch)

```bash
cp -r checkers/llm_opus checkers/my_fix
```

Pick a mutant that `llm_opus` misses. Add a rule to `checkers/my_fix/axi_checker_set.sv`, map
it in `rules.toml`, and run:

```bash
python3 harness/qualify.py --checkers my_fix
```

Done when that mutant is CORRECT **and** every legal perturbation is still CLEAN.

## Finished early?

- Write a mutant for §A4.7.2 p.84 (region identifier).
- Add a legal perturbation to `catalog/legal.toml` that you think some checker will flag.
