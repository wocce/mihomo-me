#!/usr/bin/env bash
# ==============================================================================
#  mlr 一键安装器
#    curl -fsSL https://raw.githubusercontent.com/WOCE/mihomo-me/main/install.sh | sudo bash
#  或仓库内：sudo bash install.sh
#  安装后命令：mlr （进入交互菜单）
# ==============================================================================
set -euo pipefail

RAW="${MLR_RAW:-https://raw.githubusercontent.com/WOCE/mihomo-me/main}"
DEST="${MLR_DEST:-/usr/local/bin/mlr}"
NO_RUN="${MLR_NO_RUN:-0}"

c_g=$'\033[32m'; c_r=$'\033[31m'; c_c=$'\033[36m'; c_0=$'\033[0m'
info() { printf '%s[ .. ]%s %s\n' "$c_c" "$c_0" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$c_g" "$c_0" "$*"; }
die()  { printf '%s[FAIL]%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }

if [ "$(id -u)" != "0" ] && [ "${MLR_ALLOW_NONROOT:-0}" != "1" ]; then
  die "请用 root 运行（调试可设 MLR_ALLOW_NONROOT=1）"
fi

# ---------- 取脚本本体 ----------
self_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo .)"
tmp=""
if [ -f "$self_dir/mlr" ]; then
  src="$self_dir/mlr"
  info "使用本地文件 $src"
else
  tmp="$(mktemp)"
  info "从 $RAW/mlr 下载"
  if ! curl -fsSL --retry 3 --max-time 60 -o "$tmp" "$RAW/mlr"; then
    for m in "https://ghfast.top/${RAW}/mlr" "https://gh-proxy.com/${RAW}/mlr"; do
      info "直连失败，尝试镜像"
      if curl -fsSL --retry 2 --max-time 60 -o "$tmp" "$m"; then break; fi
    done
  fi
  [ -s "$tmp" ] || die "下载 mlr 失败，检查网络"
  src="$tmp"
fi

# ---------- 校验并安装 ----------
bash -n "$src" || die "脚本语法检查失败，已中止（避免装坏）"
install -m 755 "$src" "$DEST"
[ -n "$tmp" ] && rm -f "$tmp"
ok "已安装到 $DEST"

# 便于 PATH 里 `mlr` 直接可用
case ":$PATH:" in
  *":$(dirname "$DEST"):"*) ;;
  *) { printf 'export PATH="%s:$PATH"\n' "$(dirname "$DEST")" > /etc/profile.d/mlr.sh; } 2>/dev/null || true ;;
esac

printf '\n  下一步：直接输入  %smlr%s  进入菜单\n\n' "$c_c" "$c_0"

# ---------- 尝试直接唤起菜单（管道安装时接管 /dev/tty）----------
if [ "$NO_RUN" = "1" ]; then exit 0; fi
if [ -t 0 ]; then
  exec "$DEST"
elif [ -r /dev/tty ]; then
  exec "$DEST" < /dev/tty
fi
