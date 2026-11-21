#!/usr/bin/env bash
# mlr 安装脚本：把 mlr 放到 /usr/local/bin 并可选立即启动
set -euo pipefail

RAW="${MLR_RAW:-https://raw.githubusercontent.com/yourname/mihomo-relay/main}"
DEST="${MLR_DEST:-/usr/local/bin/mlr}"

if [ "$(id -u)" != "0" ] && [ "${MLR_ALLOW_NONROOT:-0}" != "1" ]; then
  echo "请用 root 运行（调试可设 MLR_ALLOW_NONROOT=1）" >&2; exit 1
fi

if [ -f "$(dirname "$0")/mlr" ]; then
  src="$(dirname "$0")/mlr"
  echo "[..] 使用本地文件 $src"
else
  tmp="$(mktemp)"
  echo "[..] 从 $RAW/mlr 下载"
  curl -fsSL --max-time 60 -o "$tmp" "$RAW/mlr" || { echo "下载失败" >&2; exit 1; }
  src="$tmp"
fi

bash -n "$src" || { echo "语法检查失败，已中止" >&2; exit 1; }
install -m 755 "$src" "$DEST"
echo "[OK] 已安装到 $DEST"
echo
echo "下一步：直接执行  mlr  进入交互菜单"
