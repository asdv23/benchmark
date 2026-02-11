# Geth "Discarding underpriced transaction" 验证说明

## 错误含义

日志：
```text
TRACE Discarding underpriced transaction  hash=41562a..1dd658 gasTipCap=100,000,000,000 gasFeeCap=100,000,000,000
```

在 op-geth（mantle-op-geth）中，该日志在 **交易池已满** 时打出：新交易只有在其「价格」**不高于**当前池子里**最便宜**的那笔时，才会被判定为 underpriced 并丢弃。

代码位置：`repos/mantle-op-geth/core/txpool/legacypool/legacypool.go` 第 741–746 行：

- 条件：`pool.all.Slots() + numSlots(tx) > GlobalSlots + GlobalQueue`（即池子满）
- 判定：`pool.priced.Underpriced(tx)` 为 true 时丢弃

排序/比较使用 **effective tip**（若已设置 baseFee）：  
`effectiveTip = min(gasTipCap, gasFeeCap - baseFee)`。

## RPC 验证结果（2025-02-10）

目标 RPC：`https://op-geth-sepolia-qa6.qa4.gomantle.org`

| 项 | 值 |
|----|-----|
| `eth_gasPrice` | 100,008 wei (~0.0001 Gwei) |
| `baseFeePerGas` (latest block) | 8 wei |
| `txpool_status` pending | **600,000** |
| `txpool_status` queued | 0 |
| 配置 GlobalSlots + GlobalQueue | 500,000 + 100,000 = **600,000** |

结论：**交易池已满**（pending 已达 600,000 slots）。此时任何新交易都会进入「池满」分支，只有出价**高于**当前池中最低 effective tip 的交易才会被接受；否则报 underpriced 并丢弃。

你当前这笔：gasTipCap = gasFeeCap = 100 Gwei，effective tip ≈ 100 Gwei。被拒说明：**池子里最便宜的那笔的 effective tip 已经 ≥ 100 Gwei**，所以 100 Gwei 的新交易被判定为「不高于最低价」而丢弃。

## 可行处理方式

1. **提高 gas 出价**  
   使用比当前池中最低价更高的 tip/feeCap，例如先试 **200 Gwei** 或更高（gasTipCap 与 gasFeeCap 都提高），看是否能进池。
2. **排查谁在占满池子**  
   用 `txpool_inspect` / `txpool_content` 看 pending 里是哪些地址、什么 gas 分布；若有压测或脚本在持续发高 gas 交易，需要限流或单独环境。
3. **扩大或放宽池子（需有节点控制权）**  
   - 适当增大 `--txpool.globalslots` / `--txpool.globalqueue`（你当前是 500000/100000）；或  
   - 等区块持续打包，使 pending 下降后再发 100 Gwei 的 tx。

## 本地验证「提高 gas 能否进池」

没有该链上已充值账户时无法真正上链，但可以用更高 gas 重发同一笔交易验证是否仍报 underpriced：

- 若改为 200 Gwei（或更高）后不再报 underpriced，说明就是「池满 + 当前出价不高于池内最低价」导致。
- 若仍报 underpriced，说明池内最低价已经很高，需要继续提高 gas 或先清/扩容池子。

## 如何清空 txpool（pending + queued）

Geth/op-geth **没有** 提供 RPC（如 `txpool_*` 或 `admin_*`）来清空交易池，只能通过停节点 + 删文件实现。

### 方法一：删 journal 后重启（推荐）

1. **停掉 geth**（优雅停机，确保 journal 已写入）。
2. **删除交易 journal 文件**（路径相对于 `--datadir`）：
   - `$GETH_DATA_DIR/transactions.rlp`（主交易 journal）
   - 若启用了 preconf：`$GETH_DATA_DIR/transactions.rlp.preconf`
3. **再启动 geth**。启动时不会从磁盘加载任何交易，pending 和 queued 都会是空的。

journal 路径可由 `--txpool.journal` 指定，默认是 `transactions.rlp`，会被解析到 datadir 下（见 `eth/backend.go` 里 `stack.ResolvePath(config.TxPool.Journal)`）。

### 方法二：仅重启（可能仍会恢复）

若未使用 journal（例如 `--txpool.nolocals` 且未开 `--txpool.journalremotes`），交易只存在内存里，**单纯重启** 会清空内存中的 pool。但若使用了 journal，重启时会从 `transactions.rlp` 重新加载交易，pool 又会被填满，所以需要配合**方法一**删除 journal。

### 小结

| 目标           | 做法                         |
|----------------|------------------------------|
| 清空所有 queue/pending | 停节点 → 删 `transactions.rlp`（及 `.preconf`）→ 再启动 |
| 避免以后再持久化 | 启动时加 `--txpool.journal ""`（或等价配置）禁用 journal |

---

## 参考

- Geth 池满与 underpriced 逻辑：`core/txpool/legacypool/legacypool.go`（约 740–746 行）、`list.go` 中 `Underpriced` / `underpricedFor`（约 593–622 行）。
- 堆按 effective tip 排序：`list.go` 中 `priceHeap.cmp`（约 512–525 行）。
