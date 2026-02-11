#!/usr/bin/env bash
# 使用本项目下 Mantle 子仓库的 op-geth 和 reth 跑 Base benchmark，直接执行压测
# https://github.com/base/benchmark
#
# 用法:
#   ./run.sh           # 同时测 Mantle geth + reth（默认）
#   ./run.sh both      # 同上
#   ./run.sh geth      # 仅测 Mantle geth
#   ./run.sh reth      # 仅测 Mantle reth

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RETH_BIN="${SCRIPT_DIR}/repos/mantle-reth/target/release/op-reth"
GETH_BIN="${SCRIPT_DIR}/repos/mantle-op-geth/build/bin/geth"
ROOT_DIR="./data-dir"
OUTPUT_DIR="./output"

# 根据参数选择测 geth / reth / 两者
MODE="${1:-both}"
case "$MODE" in
  geth)
    CONFIG="./configs/public/basic-mantle-geth.yml"
    MODE_DESC="仅 Mantle geth"
    ;;
  reth)
    CONFIG="./configs/public/basic-mantle-reth.yml"
    MODE_DESC="仅 Mantle reth"
    ;;
  both|"")
    CONFIG="./configs/public/basic.yml"
    MODE_DESC="Mantle geth + reth"
    ;;
  -h|--help)
    echo "用法: $0 [geth|reth|both]"
    echo "  geth  - 仅测 Mantle op-geth"
    echo "  reth  - 仅测 Mantle reth"
    echo "  both  - 同时测 geth 与 reth（默认）"
    exit 0
    ;;
  *)
    echo "错误: 未知参数 '$MODE'。用法: $0 [geth|reth|both]"
    exit 1
    ;;
esac

export BASE_BENCH_RETH_BIN="$RETH_BIN"
export BASE_BENCH_GETH_BIN="$GETH_BIN"
export BASE_BENCH_MANTLE_COMPAT=true

# 1. 确保 submodule 已拉取
if [[ ! -d repos/mantle-op-geth/.git ]] || [[ ! -d repos/mantle-reth/.git ]]; then
	echo "正在初始化 submodule (repos/mantle-op-geth, repos/mantle-reth)..."
	git submodule update --init --recursive repos/mantle-op-geth repos/mantle-reth 2>/dev/null || true
fi

# 1b. 固定子仓库版本：reth = tag v2.2.0-beta.1，geth = 分支 mantle-arsia
# 若上次 git 异常退出可能留下 index.lock，先清理避免 fatal: Unable to create '...index.lock'
rm -f .git/modules/repos/mantle-op-geth/index.lock .git/modules/repos/mantle-reth/index.lock 2>/dev/null || true
echo "检出 mantle-reth tag v2.2.0-beta.1..."
(cd repos/mantle-reth && git fetch --tags 2>/dev/null || true && git checkout v2.2.0-beta.1)
echo "检出 mantle-op-geth 分支 mantle-arsia..."
(cd repos/mantle-op-geth && git fetch origin mantle-arsia 2>/dev/null || true && git checkout mantle-arsia)

# 2. 强制重新编译 benchmark（保证 Go 代码修改生效）
echo "正在构建 base-bench..."
make build
[[ -x ./bin/base-bench ]] || { echo "错误: 构建后仍无 ./bin/base-bench"; exit 1; }

# 3. 检查必要文件
[[ -f genesis.json ]] || { echo "错误: 项目根目录缺少 genesis.json"; exit 1; }
[[ -f "$CONFIG" ]] || { echo "错误: 缺少配置 $CONFIG"; exit 1; }

# 4. Mantle 客户端：默认强制重新编译（保证当前分支被测试）
echo "正在构建 Mantle op-reth..."
(cd repos/mantle-reth && cargo build --release -p op-reth)
echo "正在构建 Mantle op-geth..."
(cd repos/mantle-op-geth && make geth)
[[ -x "$RETH_BIN" ]] || { echo "错误: 构建后仍无 reth: $RETH_BIN"; exit 1; }
[[ -x "$GETH_BIN" ]] || { echo "错误: 构建后仍无 geth: $GETH_BIN"; exit 1; }

# 5. 创建数据与输出目录
mkdir -p "$ROOT_DIR" "$OUTPUT_DIR"

# 6. 执行压测（日志同时写入 output/run.log，失败时可用 grep -E "ERROR|Failed to run test|err=" output/run.log 排查）
echo "模式: $MODE_DESC"
echo "配置: $CONFIG | 数据目录: $ROOT_DIR | 输出: $OUTPUT_DIR"
echo "Mantle geth: $GETH_BIN"
echo "Mantle reth: $RETH_BIN"
echo "---"
./bin/base-bench run \
  --config "$CONFIG" \
  --root-dir "$ROOT_DIR" \
  --output-dir "$OUTPUT_DIR" \
  --mantle-compat 2>&1 | tee "$OUTPUT_DIR/run.log"

echo "---"
echo "压测完成。结果目录: $OUTPUT_DIR"
echo "若失败可排查: grep -E 'ERROR|Failed to run test|err=' $OUTPUT_DIR/run.log"
echo "查看报告: cd report && npm install && npm run dev"
