# Reference repos for Base/Mantle client compatibility

These submodules are for **comparison and debugging** only. They are not used in the benchmark build.

- **mantle-op-geth** – [mantlenetworkio/op-geth](https://github.com/mantlenetworkio/op-geth): Mantle’s op-geth fork (e.g. `DepositTx` RLP and L1 info format).
- **mantle-reth** – [mantle-xyz/reth](https://github.com/mantle-xyz/reth): Mantle’s reth fork (chain config, payload validation).

Used to track differences that cause errors such as `rlp: too few elements for types.DepositTx` or `withdrawals pre-Shanghai` when running Base benchmark against Mantle clients.
