# Base Benchmark 测试说明（对标 OKX Adventure 结构）

## 1. 仓库介绍

- **仓库**：https://github.com/base/benchmark  
- **Base Benchmark** 是围绕 Base（基于 OP Stack 的 L2）的执行层性能测试框架，包含：
  - **benchmark**：CLI 入口与配置（`benchmark/cmd`、`config`、`flags`）
  - **runner**：核心压测逻辑（sequencer/validator 建块与验证、Geth/Reth 客户端、指标采集）
  - **configs**：YAML 测试配置（public/、examples/）
  - **report**：交互式报告（React 看板、图表）
  - **run.sh**（本仓库定制）：一键用 Mantle 兼容的 op-geth / op-reth 跑压测

下面说的「测试」主要指 **run.sh 驱动的、configs/public/basic 系列** 的性能测试。

### 1.1 测试说明

Base Benchmark 面向 **OP Stack L2 执行层**（本仓库为 Mantle 兼容的 op-geth / op-reth），用于：

- **建块性能**：在固定块间隔（1s）与 gas limit 下，通过 `engine_forkchoiceUpdated` + `engine_getPayload` 测 Sequencer 建块延迟与 gas/s。
- **验证性能**：通过 `engine_newPayload` 测 Validator 回放同一批 payload 的延迟与 gas/s。
- **对比**：同一负载（Transfer-only）、同一配置下对比 op-geth 与 op-reth 的建块/验证表现。

典型用途：对比 op-geth 与 op-reth 作为 L2 执行层时的建块与验证基线性能（不测「链上 TPS 上限」，而是测单块构建与验证的延迟与吞吐）。

### 1.2 测试场景

当前 run.sh 使用的场景为 **Transfer-only 执行速度**（configs/public/basic.yml 及其 Mantle 变体）：

- **负载**：纯 Native 转账（无合约调用）；payload 类型 `transfer-only`。
- **变量矩阵**：
  - `node_type`：geth | reth（或通过 basic-mantle-geth.yml / basic-mantle-reth.yml 只跑一种）
  - `gas_limit`：20M、30M、60M、90M（4 档）
  - `num_blocks`：10（每个 run 出 10 个正式块，不含 1 个 setup 块）
- **块间隔**：BlockTime = 1s（Block Time Milliseconds = 1000），即约 1 秒出一个块。

每个 run 流程：1 个 setup 块（设 gas limit）→ 10 个块，每块前向 mempool 发一批 transfer，再 FCU → getPayload → newPayload，并采集延迟与 gas/s。

### 1.3 核心流程简述

1. **准备（每个 run 开始前）**  
   - 读 config（YAML）、genesis.json；为 sequencer 生成数据目录、chain.json、JWT；Mantle 兼容时对 chain.json 补全 `mantleEverestTime`、`mantleSkadiTime`、`mantleLimbTime`、`mantleArsiaTime`。  
   - 启动 sequencer 节点（geth 或 reth），等待 RPC 就绪。

2. **Sequencer 阶段（Run）**  
   - 出 1 个 setup 块（GasLimitSetup = 1e9）。  
   - 循环 10 次（NumBlocks）：  
     - SendTxs：向 mempool 注入 transfer 交易；  
     - Propose：`updateForkChoice(payloadAttrs)` → `Sleep(BlockTime)` → `getBuiltPayload` → `newPayload`；  
     - 记录 latency（update_fork_choice、get_payload、send_txs）、gas/per_block、gas/per_second；  
     - 从节点拉取指标（geth：`/debug/metrics` 的 chain/*；reth：`/metrics` 的 reth_sync_*）。  
   - 汇总为 sequencer 的 forkChoiceUpdated、getPayload、sendTxs、gasPerSecond（见 metadata.json）。

3. **Validator 阶段**  
   - 启动 validator 节点，用 sequencer 产出的 payload 从 setup 块起依次 `engine_newPayloadV4` 回放；  
   - 每块记录 newPayload 延迟与 gas/s，汇总为 validator 的 newPayload、gasPerSecond。

4. **指标含义**  
   - **gasPerSecond**：建块/验证阶段「该 run 内总 gas / 总耗时」的汇总，单位 gas/s。  
   - **getPayload / newPayload / forkChoiceUpdated / sendTxs**：对应 API 调用的平均耗时，单位秒。  
   - 统计的是**单 run 内 10 个块**的延迟与吞吐，不是长时间链上 TPS；报告中的「Inserts」等来自 geth 的 `chain/inserts.50-percentile`，reth 未映射到同一 key，故 reth 在这些图上无数据。

### 1.4 主要配置

| 配置来源 | 含义 | 典型值 |
|----------|------|--------|
| configs/public/basic.yml | 测试矩阵（payload、node_type、num_blocks、gas_limit） | node_type: geth, reth；gas_limit: 20M/30M/60M/90M；num_blocks: 10 |
| run.sh 环境变量 | 客户端二进制与 Mantle 兼容 | BASE_BENCH_GETH_BIN、BASE_BENCH_RETH_BIN、BASE_BENCH_MANTLE_COMPAT=true |
| runner 默认 | BlockTime、GasLimitSetup | BlockTime 1s；GasLimitSetup 1e9 |
| genesis.json | 链配置（项目根目录） | 需含 Mantle 时间等（ensureMantleChainConfig 会补全） |

CLI 参数（run.sh 已写死）：`--config`、`--root-dir`、`--output-dir`、`--mantle-compat`。

### 1.5 使用方式

在项目根目录：

```bash
# 同时测 Mantle geth + reth（8 个 run：4 gas_limit × 2 客户端）
./run.sh
# 或
./run.sh both

# 仅测 Mantle geth（4 个 run）
./run.sh geth

# 仅测 Mantle reth（4 个 run）
./run.sh reth

# 帮助
./run.sh -h
```

run.sh 会：初始化/检出子模块（mantle-op-geth 分支 mantle-arsia、mantle-reth tag v2.2.0-beta.1）→ 强制编译 base-bench、op-reth、op-geth → 执行 `bin/base-bench run ...`，日志同时写入 `output/run.log`。

查看报告：

```bash
cd report && npm install && npm run dev
# 浏览器打开提示的 URL，导入 output 目录或 metadata
```

### 1.6 注意事项

- **链与二进制**：run.sh 使用本地 genesis.json 与子模块内的 op-geth/op-reth；若要对已有网络（如 QA）压测，需改配置/代码指向该网络 RPC，当前 run.sh 是「本地起节点 + 本地压测」。
- **Mantle 兼容**：必须传 `--mantle-compat`；L1 属性 tx 使用 Arsia selector，DepositTx 用 10 字段 RLP，chain 补全 Mantle 时间字段；否则 geth 会报 L1 attributes 无 Arsia selector。
- **子模块版本**：run.sh 固定 reth = v2.2.0-beta.1、geth = mantle-arsia；修改版本需改 run.sh 或子模块检出逻辑。
- **失败排查**：`grep -E 'ERROR|Failed to run test|err=' output/run.log`；详见 `docs/TROUBLESHOOTING.md`。

---

## 2. 测试结果

以下结果来自**本地 devnet 式压测**（run.sh + genesis.json + Mantle op-geth/op-reth），非 QA 网络。  
数据取自 `output/metadata.json` 中批次 **test-1770628001426957**（8/8 通过，Geth 与 Reth 各 4 个 gas_limit run）。

### 2.1 Reth（Mantle op-reth v2.2.0-beta.1）

- **环境**：run.sh 默认（本地 sequencer + validator，BlockTime 1s，Transfer-only）。
- **结果汇总**（4 个 run：20M/30M/60M/90M gas limit）：

| 项目 | 数值 |
|------|------|
| Sequencer gasPerSecond（平均） | 约 10.5M（20M）～ 46.5M（90M） gas/s |
| Sequencer getPayload 延迟 | 约 4～16 ms |
| Sequencer forkChoiceUpdated | 约 1.3～2.1 ms |
| Validator newPayload 延迟 | 约 7～27 ms |
| Validator gasPerSecond | 约 1.5e9～1.78e9 gas/s |

- **结论简述**：Reth 在建块侧 getPayload、sendTxs 延迟更低，gasPerSecond 略高于同 gas limit 下的 Geth；验证侧与 Geth 同量级。报告内「Inserts」等 chain/* 图仅来自 Geth，Reth 无对应数据。

### 2.2 Geth（Mantle op-geth mantle-arsia）

- **环境**：同上。
- **结果汇总**（4 个 run）：

| 项目 | 数值 |
|------|------|
| Sequencer gasPerSecond（平均） | 约 10.3M（20M）～ 44.2M（90M） gas/s |
| Sequencer getPayload 延迟 | 约 11～43 ms |
| Sequencer forkChoiceUpdated | 约 8～26 ms |
| Validator newPayload 延迟 | 约 9～33 ms |
| Validator gasPerSecond | 约 1.24e9～1.44e9 gas/s |

- **结论简述**：Geth 建块与验证均完成，getPayload 与 FCU 延迟高于 Reth；metrics 中有 chain/inserts、chain/execution 等细粒度子阶段指标，便于做建块瓶颈分析。

### 2.3 与 OKX Adventure 的差异

- **Base Benchmark**：固定块间隔 1s、固定 10 块/run，测的是**建块/验证 API 的延迟与单 run 内 gas/s**，不直接给出「链上 BTPS/TPS」；客户端由 run.sh 启动本地节点，负载由 benchmark 内 SendTxs + Propose 控制。  
- **OKX Adventure**：对已有 RPC（如 QA5/QA6）持续发交易，用 eth_getBlockByNumber 统计链上区块交易数，得到 Average/Max/Min BTPS 和总确认笔数，更贴近「链上吞吐与稳定性」。  
两者可互补：Base 看单机建块/验证能力与延迟；Adventure 看整链在高压下的 TPS 与稳定性。

---

## 3. Next

- [ ] 若要对 QA/主网等已有网络做「链上 TPS」压测，可参考 OKX Adventure 的 native-bench 方式，或在本仓库增加「对外 RPC + 轮询区块统计 BTPS」的模式。  
- [ ] 统一 Reth 与 Geth 的指标命名或映射，使 report 中「Inserts」等图能同时展示 Reth（例如将 reth_sync_* 映射到 chain/* 或增加 reth 专用图表）。  
- [ ] 增加更多 payload 类型（如 ERC20、合约调用）或更长 num_blocks/不同 BlockTime，以丰富对比维度。
