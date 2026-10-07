<!-- REVIEW: machine-drafted translation of SETUP.md; needs a native speaker's review before release -->
# 安装

[English](SETUP.md)

请在**教程开始前**完成以下步骤（约 30 分钟）。所有工具都是免费开源的。

## 1. 笔记本电脑

| 系统 | 安装 |
|---|---|
| Ubuntu 22.04 / 24.04 | `sudo apt install git curl` |
| macOS 13+（Intel 或 Apple 芯片） | `xcode-select --install` |
| Windows 10 / 11 | 安装 WSL2 与 Ubuntu 22.04 / 24.04，然后在 WSL 中按 Ubuntu 的步骤操作 |

内存 8 GB，可用磁盘 4 GB。

## 2. Verilator 5.052 与 Python（来自 conda-forge）

**在中国大陆，请使用清华镜像**（每一步的镜像写法见下表）。

安装 Miniforge（如已有 conda 或 mamba 可跳过）：

```bash
curl -LO https://mirrors.tuna.tsinghua.edu.cn/github-release/conda-forge/miniforge/LatestRelease/Miniforge3-$(uname)-$(uname -m).sh
bash Miniforge3-$(uname)-$(uname -m).sh -b -p ~/miniforge3
source ~/miniforge3/bin/activate
```

创建环境。请**严格使用 Verilator 5.052**：

```bash
conda create -y -n axi --override-channels -c https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge verilator=5.052 python=3.12
conda activate axi
pip install -i https://pypi.tuna.tsinghua.edu.cn/simple cocotb==2.1.0 cocotbext-axi==0.1.28 pytest pypdf
```

每次打开新终端：`source ~/miniforge3/bin/activate axi`。

**不在中国大陆**时，使用官方源：

| 步骤 | 官方源 |
|---|---|
| Miniforge | `https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh` |
| `conda create` | 把镜像参数换成 `-c conda-forge` |
| `pip install` | 去掉 `-i ...` |

## 3. 代码仓库与检查

```bash
git clone https://github.com/10x-Engineers/axi-checker-mutation.git
cd axi-checker-mutation
./check_env.sh
```

必须显示 **ALL PASS**。

## 4. 请准备

- **AXI 规范：** ARM IHI 0022 Issue L，可在 <https://developer.arm.com/documentation/ihi0022/l/> 免费下载。
- **任意大语言模型：** 对话账号、兼容 OpenAI 接口的 API 密钥，或用 Ollama 运行的本地模型。可选：实验中提供了参考检查器。
- **可选，用于实验 2：** 波形查看器 [Surfer](https://surfer-project.org) 或 GTKWave。

## `check_env.sh` 失败时

| 提示 | 解决方法 |
|---|---|
| `verilator not on PATH` | `source ~/miniforge3/bin/activate axi` |
| `SVA evaluation smoke test` | `verilator --version` 必须显示 5.052；按第 2 步重新创建环境 |
| `Verilator's C++ compiler ... not found` | 安装第 1 步中的工具 |
