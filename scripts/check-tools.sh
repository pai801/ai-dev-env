#!/usr/bin/env bash
#
# 依赖检测：必需项（git / node>=20 / opencode / uv / semble / codegraph）缺失时 exit 1，
# 推荐项（openspec）缺失仅提示。
#
set -uo pipefail

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK=$'\033[32m'; C_MISS=$'\033[31m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_OK=''; C_MISS=''; C_DIM=''; C_RST=''
fi

MISSING_REQUIRED=0
MISSING_OPTIONAL=0

# 打印版本号，失败不中断（取首行并截断，避免多行噪音）
print_version() {
  local cmd="$1" out=""
  case "$cmd" in
    # semble 不支持 --version，改从 uv tool list 取
    semble) out="$(uv tool list 2>/dev/null | grep -E '^semble ' | head -n 1 || true)" ;;
    *)      out="$("$cmd" --version 2>/dev/null | head -n 1 || true)" ;;
  esac
  [ -n "$out" ] || out="(版本未知)"
  printf '%s\n' "$out" | cut -c1-80
}

check() {
  local name="$1" hint="$2" required="$3"
  if command -v "$name" >/dev/null 2>&1; then
    printf '%s[OK]%s   %-12s %s%s%s\n' "$C_OK" "$C_RST" "$name" "$C_DIM" "$(print_version "$name")" "$C_RST"
  else
    printf '%s[MISS]%s %-12s %s\n' "$C_MISS" "$C_RST" "$name" "$hint"
    if [ "$required" = "1" ]; then
      MISSING_REQUIRED=$((MISSING_REQUIRED + 1))
    else
      MISSING_OPTIONAL=$((MISSING_OPTIONAL + 1))
    fi
  fi
}

# Node 主版本号检查（>= 20）
check_node_version() {
  command -v node >/dev/null 2>&1 || return 0
  local major
  major="$(node --version 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/' || true)"
  case "$major" in
    ''|*[!0-9]*) return 0 ;;
  esac
  if [ "$major" -lt 20 ]; then
    printf '%s[WARN]%s node 版本过低（当前 v%s，需要 >= 20）\n' "$C_MISS" "$C_RST" "$major"
    MISSING_REQUIRED=$((MISSING_REQUIRED + 1))
  fi
}

echo "── 必需 ──────────────────────────────"
check git       "安装: brew install git / apt install git" 1
check node      "安装: brew install node / 或使用 nvm 安装 Node 20+" 1
check_node_version
check opencode  "安装: curl -fsSL https://opencode.ai/v2/install | bash 或 npm i -g @opencode/cli" 1
check uv        "安装: curl -LsSf https://astral.sh/uv/install.sh | sh（semble 依赖）" 1
check semble    "安装: uv tool install semble（AGENTS.md 工具协议依赖）" 1
check codegraph "安装: npm i -g @colbymchenry/codegraph" 1

echo ""
echo "── 推荐 ──────────────────────────────"
check openspec  "安装: npm i -g @fission-ai/openspec（my-propose / my-archive 依赖）" 0

echo ""
if [ "$MISSING_REQUIRED" -eq 0 ]; then
  echo "必需依赖齐全（git / node / opencode / uv / semble / codegraph）。"
  if [ "$MISSING_OPTIONAL" -gt 0 ]; then
    echo "有 $MISSING_OPTIONAL 个推荐项缺失，相关功能会降级。"
  fi
  exit 0
fi

echo "缺少 $MISSING_REQUIRED 个必需依赖（git / node / opencode / uv / semble / codegraph），请先安装。"
exit 1
