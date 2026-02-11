# 压测失败排查指南

## 1. 如何拿到失败原因

当前日志里只有结尾的 `numSuccess=4 numFailure=4` 和 `failed to run 4 tests`，**具体失败原因在更早的 ERROR 行**（`Failed to run test` 和 `err=...`）。请保留完整 stdout/stderr：

```bash
# 保存完整日志到文件，便于搜索 ERROR 和 err=
./run.sh both 2>&1 | tee run.log
# 然后查看失败原因
grep -E "ERROR|Failed to run test|err=" run.log
```

或在 run.sh 里临时改为（自动写日志）：

```bash
./bin/base-bench run ... 2>&1 | tee "$OUTPUT_DIR/run.log"
```

---

## 2. 常见失败原因与应对

| 现象 / 错误信息 | 可能原因 | 解决方案 |
|-----------------|----------|----------|
| `MinBaseFeeNotAllowedBeforeJovian` | reth 认为链在 Jovian 之前，不允许 payload 带 minBaseFee | 已通过 ensureMantleChainConfig 补全 `mantleArsiaTime`；若仍出现，可临时在 MantleCompat 下不传 MinBaseFee（见 sequencer_consensus.go 历史改动）。 |
| `MissingMinBaseFeeInPayloadAttributes` | reth 认为链在 Jovian 之后，要求 payload 必须带 minBaseFee | 已恢复在 payload 中发送 MinBaseFee；确保 chain.json 中有 mantleArsiaTime（ensureMantleChainConfig）。 |
| `failed to propose block` / `context deadline exceeded` | getPayload 超时（如 240s），常见为 reth 组块卡死或过慢 | 已修 mantle-reth 的 assemble_block 无限递归；确认使用 tag v2.2.0-beta.1 并重新编译。 |
| funding 相关 / receipt 找不到 | Mantle 10 字段 DepositTx 与 receipt 哈希不一致 | 已用 Mantle RLP + AddRawSequencerTxs + Keccak256Hash(rawBytes) 查 receipt；确认 `--mantle-compat` 已传。 |
| `withdrawals pre-Shanghai` 等 | chain 配置缺少 Mantle 时间导致 Shanghai/withdrawals 判断错误 | 已用 ensureMantleChainConfig 补全 mantleEverestTime、mantleSkadiTime、mantleLimbTime、mantleArsiaTime。 |
| `Unable to create '...index.lock'` | 子模块 git 锁文件残留 | `rm -f .git/modules/repos/mantle-op-geth/index.lock .git/modules/repos/mantle-reth/index.lock`，run.sh 已含自动清理。 |
| `L1 attributes transaction data does not have Arsia selector` | Mantle op-geth (mantle-arsia) 要求 L1 属性 tx 使用 Arsia 的 4 字节 selector | 已在 MantleCompat 下使用 MantleArsiaL1AttributesSelector (0x49e72383) 构造 L1 属性 data；确保已重新编译 base-bench。 |
| 4 个失败且无明确 ERROR | 可能是 geth 或 reth 某一侧 4 个 gas_limit 全失败 | 用上面方法保存完整日志，看是 geth 还是 reth、以及 err= 后面的具体错误。 |

---

## 3. 你当前这次（4 pass + 4 fail）可以这样查

- 用 **完整日志** 确认是哪些 run 失败（例如全是 geth 或全是 reth）：
  ```bash
  ./run.sh both 2>&1 | tee run.log
  grep -B2 "Failed to run test" run.log
  ```
- 看每个 `err=` 内容，再对照上表处理。
- 若日志已滚动掉，请**重跑一次**并带上 `2>&1 | tee run.log`，再发 `run.log` 里与失败相关的片段（含 ERROR 和 err=）以便精确定位。
