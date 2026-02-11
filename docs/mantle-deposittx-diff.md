# Mantle vs Base: DepositTx RLP 差异

## 结论

Mantle 的 op-geth 在 `DepositTx` 上比 Base/OP 多 **2 个 RLP 字段**，解码时期望 10 个元素，而 Base benchmark 只编码 8 个，导致错误：

`transaction 0 is not valid: rlp: too few elements for types.DepositTx`

## 字段对比

| 顺序 | Base (ethereum-optimism/op-geth) | Mantle (mantlenetworkio/op-geth) |
|------|---------------------------------|----------------------------------|
| 1 | SourceHash | SourceHash |
| 2 | From | From |
| 3 | To | To |
| 4 | Mint | Mint |
| 5 | Value | Value |
| 6 | Gas | Gas |
| 7 | IsSystemTransaction | IsSystemTransaction |
| 8 | Data | **EthValue** (L2 BVM_ETH mint tag) |
| 9 | - | Data |
| 10 | - | **EthTxValue** (L2 BVM_ETH tx tag, `rlp:"optional"`) |

Mantle 独有字段（见 `repos/mantle-op-geth/core/types/deposit_tx.go`）：

- `EthValue *big.Int \`rlp:"nil"\``：L2 BVM_ETH mint 标记
- `EthTxValue *big.Int \`rlp:"optional"\``：L2 BVM_ETH 转账标记

## 兼容方式

启用 `--mantle-compat` 或环境变量 `BASE_BENCH_MANTLE_COMPAT=true` 时，benchmark 会将 L1 信息 DepositTx 按 Mantle 的 10 字段顺序做 RLP 编码（EthValue / EthTxValue 以 nil 编码），使 Mantle op-geth 能正确解码。
