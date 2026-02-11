# Base Benchmark 性能测试总结

本文档基于当前仓库代码与 `output/` 内测试结果整理，说明测试目的、方法、指标含义及实际结果。

---

## 一、测试主要做什么

在 **OP Stack 风格 L2**（本仓库使用 Mantle 兼容的 op-geth / op-reth）上，对**执行层客户端**做**建块（Sequencer）与验证（Validator）**性能基准测试：

- **建块**：在固定块间隔与 gas limit 下，客户端通过 `engine_forkchoiceUpdatedV3` + `engine_getPayloadV4` 产出区块的延迟与吞吐。
- **验证**：另一节点通过 `engine_newPayloadV4` 回放这些区块的延迟与吞吐。
- **负载**：**Transfer-only**（纯 ETH 转账），用于建立「执行 + 状态更新」的基线，便于同条件对比不同客户端。

**当前 run.sh 行为**：使用 `repos/mantle-op-geth`（分支 mantle-arsia）与 `repos/mantle-reth`（tag v2.2.0-beta.1），在 `--mantle-compat` 下跑同一套配置，对比两者表现。

---

## 二、怎么做的（方法论）

### 2.1 配置来源

- **主配置**：`configs/public/basic.yml`（both）、`basic-mantle-geth.yml`（仅 geth）、`basic-mantle-reth.yml`（仅 reth）。
- **变量矩阵**：
  - `node_type`: geth | reth
  - `gas_limit`: 20M, 30M, 60M, 90M
  - `num_blocks`: 10
  - `payload`: transfer-only
- **块间隔**：`BlockTime: 1s`（`runner/benchmark/benchmark.go` 中 `DefaultParams.BlockTime`），即 **Block Time Milliseconds = 1000**，目标约 **1 秒出一个块**。

### 2.2 单次 Run 流程（代码依据）

1. **准备**：用项目根目录 `genesis.json` 生成 chain 配置；Mantle 兼容时执行 `ensureMantleChainConfig` 补全 `mantleEverestTime`、`mantleSkadiTime`、`mantleLimbTime`、`mantleArsiaTime`。
2. **Sequencer 阶段**（`runner/network/sequencer_benchmark.go`）：
   - 启动一个 sequencer 节点（geth 或 reth），写入 `chain.json` 与 JWT 等。
   - 先出 **1 个 setup 块**（GasLimitSetup = 1e9），用于设定链上 gas limit。
   - 按 1 秒间隔循环 **10 次**（`params.NumBlocks`）：
     - 调用 `transactionWorker.SendTxs()` 向 mempool 注入 transfer 交易；
     - `consensusClient.Propose()` 内部：`updateForkChoice` → `time.Sleep(BlockTime)` → `getBuiltPayload` → `newPayload`；
     - 每块后 `metricsCollector.Collect(ctx, blockMetrics)`，并 `time.Sleep(1000*time.Millisecond)`（与 BlockTime 一致）。
   - 采集的延迟写入 `BlockMetrics`（如 `latency/get_payload`、`latency/update_fork_choice`、`latency/send_txs`、`gas/per_second` 等），geth 另从 `/debug/metrics` 拉取 `chain/*` 指标（如 `chain/inserts.50-percentile`）。
3. **Validator 阶段**（`runner/network/validator_benchmark.go`）：
   - 启动一个 validator 节点，先将 sequencer 产出的 setup 块用 `engine_newPayloadV4` 追齐，再对后续 10 个 payload 依次执行 `newPayload`，并采集每块验证耗时与 gas/s。
4. **输出**：每个 run 对应 `output/<outputDir>/`：`result-sequencer.json`、`result-validator.json`、`metrics-sequencer.json`、`metrics-validator.json`、日志压缩包；汇总写入 `output/metadata.json`。

### 2.3 指标含义（与 report 一致）

- **metadata.json 中 result 字段**（每个 run 一条）：
  - `sequencerMetrics`：
    - `forkChoiceUpdated`：FCU 调用耗时（秒）。
    - `getPayload`：getPayload 调用耗时（秒）。
    - `sendTxs`：发送当批交易的耗时（秒）。
    - `gasPerSecond`：建块阶段每秒处理的 gas（基于块内 GasUsed / 建块耗时）。
  - `validatorMetrics`：
    - `newPayload`：单次 newPayload 调用耗时（秒）。
    - `gasPerSecond`：验证阶段每秒处理的 gas。
- **metrics-sequencer.json / metrics-validator.json**：按块号列出的详细 `ExecutionMetrics`，包含上述延迟（纳秒形式，如 `latency/get_payload`）以及客户端自身指标（geth：`chain/inserts.50-percentile` 等；reth：`reth_sync_*` 等）。报告中的「Inserts」等图表对应 `chain/inserts.50-percentile`，目前**仅 geth 采集并写入**，reth 使用不同指标名，故 reth 在这些图上无数据。

---

## 三、结果如何（基于 output 与日志）

### 3.1 历次运行概览（metadata.json）

| 批次 ID | 时间 | Geth (4 runs) | Reth (4 runs) | 说明 |
|--------|------|----------------|----------------|------|
| test-1770626696327728 | 08:44 | 4 失败 | 4 成功 | geth 报 L1 attributes 无 Arsia selector |
| test-1770627382037824 | 08:56 | 4 失败 | 4 成功 | 同上 |
| test-1770628001426957 | 09:06 | 4 成功 | 4 成功 | 修复 Arsia selector 后全部通过 |

以下数值均来自 **test-1770628001426957**（8/8 通过）。

### 3.2 Sequencer 关键指标（中位/汇总）

- **Block Time**：固定 1000 ms，即 1 秒出一个块。
- **gasPerSecond（建块）**（单位：gas/s）：
  - Geth：20M → 约 10.3M；30M → 约 15.4M；60M → 约 30.0M；90M → 约 44.2M。
  - Reth：20M → 约 10.5M；30M → 约 15.7M；60M → 约 31.1M；90M → 约 46.5M。
- **getPayload 延迟（秒）**：
  - Geth：约 0.011（20M）～ 0.043（90M）。
  - Reth：约 0.004（20M）～ 0.016（90M）。
- **forkChoiceUpdated（秒）**：两者多在 0.001～0.026 量级。
- **sendTxs（秒）**：与每块交易数相关，Geth 约 0.16～0.72 s，Reth 约 0.04～0.17 s（同一 gas limit 下 reth 建块更快，每块内 tx 略少时 sendTxs 更短）。

### 3.3 Validator 关键指标

- **newPayload 延迟（秒）**：
  - Geth：约 0.009～0.033。
  - Reth：约 0.007～0.027。
- **validator gasPerSecond**：约 1.2e9～1.8e9 gas/s 量级（两者接近）。

### 3.4 Geth 独有链上指标（metrics-sequencer.json）

- 例如 20M gas limit、BlockNumber 1：`chain/inserts.50-percentile` ≈ 1.3e6 ns，`chain/execution.50-percentile` ≈ 1.9e5 ns，`chain/account/reads.50-percentile` 等均有值。Reth 不写入 `chain/*` 同名 key，故报告里「Inserts」等仅显示 geth。

### 3.5 结论（专家视角）

- **目的**：在 1 秒块间隔、纯转账负载下，对比 Mantle op-geth 与 op-reth 的建块与验证延迟、吞吐。
- **方法**：标准 Engine API 流程、统一 genesis/chain、Mantle 兼容（Arsia L1 属性、10 字段 DepositTx、chain 补丁），方法正确。
- **结果**：在修复 Arsia selector、MinBaseFee、reth assemble_block 递归等问题后，**最新一次运行 8/8 通过**；Reth 在建块侧 getPayload 与 sendTxs 延迟更小、gasPerSecond 略高，Validator 侧两者在同一量级；Geth 提供更细的 chain/* 建块子阶段指标（Inserts、Execution 等），Reth 当前仅提供 reth_sync_* 等，报告需按客户端区分或做指标映射方可直接对比同类子阶段。

---

## 四、附录：关键代码与输出路径

- 运行入口：`run.sh` → `./bin/base-bench run --config ... --mantle-compat`。
- 配置：`configs/public/basic.yml`、`basic-mantle-geth.yml`、`basic-mantle-reth.yml`。
- 流程：`runner/service.go`（runTest）→ `runner/network/network_benchmark.go`（sequencer + validator）→ `runner/network/sequencer_benchmark.go`、`runner/network/consensus/sequencer_consensus.go`（Propose：FCU → Sleep(BlockTime) → getPayload → newPayload）。
- 指标汇总：`runner/network/types/types.go`（BlockMetricsToSequencerSummary / BlockMetricsToValidatorSummary）→ `runner/benchmark/result_metadata.go`（RunResult）→ `output/metadata.json`。
- 报告图表定义：`report/src/metricDefinitions.ts`（如 `chain/inserts.50-percentile` → Inserts）；geth 采集 `runner/clients/geth/metrics.go`，reth 采集 `runner/clients/reth/metrics.go`（仅 reth_* 指标名）。
