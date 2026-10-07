<!-- REVIEW: machine-drafted translation of README.md; needs a native speaker's review before release -->
# 动手实验

[English](README.md)

请先完成 [SETUP.zh.md](../SETUP.zh.md)。可以自带任意大语言模型（可选）。

| 实验 | 时间 | |
|---|---|---|
| [0：环境与干净运行](lab0_setup/README.zh.md) | 15 分钟 | 检查工具链，运行测试平台 |
| [1：用您的大模型生成检查器](lab1_generate/README.zh.md) | 35 分钟 | 生成、接入、度量 |
| [2：一次"杀死"的剖析](lab2_inject/README.zh.md) | 30 分钟 | 在波形上看一次违规；四种判定 |
| [3：扩展目录，修复检查器](lab3_your_mutant/README.zh.md) | 30 分钟 | 写一个变异体；弥补一个漏洞 |

每个实验都可以独立完成。如果某一步卡住，请改用参考检查器集继续。

## 工作原理

```
 cocotb AXI 主设备 ─m_*─► [ 插入器 ] ─s_*─► axi_ram（被测设计）
                              │
                              └─ obs_* ─► 被测检查器集
                                       └► 数据记分板
```

插入器（interposer）在检查器观察的总线上放入一个协议违规（即一个*变异体*），真实流量不受影响。每次运行得到一个判定：

| 判定 | 含义 |
|---|---|
| **CORRECT 正确检出** | 被破坏条款对应的规则在变异体的时间窗口内触发 |
| **LATE 延迟检出** | 规则不对、时间太晚，或只有数据记分板发现 |
| **MISSED 漏检** | 没有任何东西发现 |
| **FLAGGED 误报** | 在合法扰动上有规则触发 |

## 检查器集

| 名称 | |
|---|---|
| `none` | 不加检查器（对照组） |
| `pulp_axi` | PULP `axi` 接口断言（开源） |
| `llm_haiku`、`llm_sonnet`、`llm_opus`、`llm_kimi_k3` | 由大模型根据 `checkers/llm_prompt/` 生成的参考检查器集 |
| `ucagent_kimi_k3` | 由万众一芯 UCAgent（使用 Kimi-k3）根据 RTL 与规范生成；白盒检查器，详见其 `PROVENANCE.md` |
