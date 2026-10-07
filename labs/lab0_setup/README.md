# Lab 0: Setup and a clean run (15 min)

[中文](README.zh.md)

## 0.1 Check the environment

```bash
./check_env.sh
```

Run it during the opening talk. It must print **ALL PASS**. Look at `tools/sva_smoke/`: what is it testing, and why would a
checker author care?

## 0.2 Run the bench without checkers

```bash
python3 harness/show.py --checkers none
```

The stimulus is in `tb/test_axi.py`. All of it is legal AXI4.

## 0.3 Run it with checkers

```bash
python3 harness/show.py --checkers llm_haiku
python3 harness/show.py --checkers llm_opus
python3 harness/show.py --checkers pulp_axi
```

1. Does anything fire? The traffic is legal, so every fire needs an explanation.
2. For each rule that fires, read it in `checkers/<set>/axi_checker_set.sv`, find the rule
   in IHI 0022 Issue L, and decide: design bug or checker bug?
3. Before Lab 1, write down which set you expect to catch the most violations, and why.

✅ Done when `check_env.sh` prints ALL PASS and you have answered 0.3.
