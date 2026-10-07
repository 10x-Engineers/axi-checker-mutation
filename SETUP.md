# Setup

[中文](SETUP.zh.md)

Complete these steps **before the session** (about 30 minutes). Everything is free and open source.

## 1. Laptop

| OS | Install |
|---|---|
| Ubuntu 22.04 / 24.04 | `sudo apt install git curl` |
| macOS 13+ (Intel or Apple silicon) | `xcode-select --install` |
| Windows 10 / 11 | WSL2 with Ubuntu 22.04 / 24.04, then as for Ubuntu, inside WSL |

8 GB RAM, 4 GB free disk.

## 2. Verilator 5.052 and Python, from conda-forge

Install Miniforge (skip this if you already have conda or mamba):

```bash
curl -LO https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh
bash Miniforge3-$(uname)-$(uname -m).sh -b -p ~/miniforge3
source ~/miniforge3/bin/activate
```

Create the environment. Use **exactly Verilator 5.052**:

```bash
conda create -y -n axi -c conda-forge verilator=5.052 python=3.12
conda activate axi
pip install cocotb==2.1.0 cocotbext-axi==0.1.28 pytest pypdf
```

In every new terminal: `source ~/miniforge3/bin/activate axi`.

**In mainland China**, use the Tsinghua mirrors:

| Step | Mirror |
|---|---|
| Miniforge | `https://mirrors.tuna.tsinghua.edu.cn/github-release/conda-forge/miniforge/LatestRelease/Miniforge3-$(uname)-$(uname -m).sh` |
| `conda create` | replace `-c conda-forge` with `--override-channels -c https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge` |
| `pip install` | add `-i https://pypi.tuna.tsinghua.edu.cn/simple` |

## 3. Repository and check

```bash
git clone https://github.com/10x-Engineers/axi-checker-mutation.git
cd axi-checker-mutation
./check_env.sh
```

It must print **ALL PASS**.

## 4. Bring

- **The AXI specification:** ARM IHI 0022 Issue L, free from <https://developer.arm.com/documentation/ihi0022/l/>.
- **Any LLM:** a chat account, an API key for an OpenAI-compatible endpoint, or a local model under Ollama. Optional: reference checkers are provided.
- **Optional, for Lab 2:** a waveform viewer, [Surfer](https://surfer-project.org) or GTKWave.

## If `check_env.sh` fails

| Message | Fix |
|---|---|
| `verilator not on PATH` | `source ~/miniforge3/bin/activate axi` |
| `SVA evaluation smoke test` | `verilator --version` must print 5.052; recreate the environment as in step 2 |
| `Verilator's C++ compiler ... not found` | install the tools in step 1 |
