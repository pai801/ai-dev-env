#!/usr/bin/env bash
#
# 提交前自检：扫描仓库中的敏感信息，命中即 exit 1。
#
# 注意：本脚本自身包含检测规则字面量，因此扫描时排除自身。
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SELF_NAME="scan-secrets.sh"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_ERR=$'\033[31m'; C_OK=$'\033[32m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_ERR=''; C_OK=''; C_DIM=''; C_RST=''
fi

# 待扫描文件列表（排除 .git、node_modules、本脚本）
FILES=()
while IFS= read -r -d '' f; do
  FILES+=("$f")
done < <(
  find "$REPO_ROOT" \
    \( -name .git -o -name node_modules \) -prune -o \
    -type f ! -name "$SELF_NAME" -print0
)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "没有可扫描的文件。"
  exit 0
fi

TOTAL=0

# 占位符（文档示例）不算泄漏：仅放行真正的占位写法，避免放过真实密钥
PLACEHOLDER='(\.\.\.|<[^>]*>|YOUR_[A-Z0-9_]*|your-[a-z0-9-]+|\$\{[A-Za-z_])'

report() {
  # $1=类别 $2=正则 $3=是否过滤占位符(1=过滤)
  local label="$1" pattern="$2" allow_placeholder="${3:-0}" hits
  hits="$(grep -nHE -- "$pattern" "${FILES[@]}" 2>/dev/null || true)"
  [ -n "$hits" ] || return 0

  # 公网 IP 需要排除回环/未指定地址
  if [ "$label" = "公网 IP" ]; then
    hits="$(printf '%s\n' "$hits" | grep -vE '127\.0\.0\.1|0\.0\.0\.0|localhost' || true)"
    [ -n "$hits" ] || return 0
  fi

  # 密钥类规则放行文档里的占位符示例
  if [ "$allow_placeholder" = "1" ]; then
    hits="$(printf '%s\n' "$hits" | grep -vE "$PLACEHOLDER" || true)"
    [ -n "$hits" ] || return 0
  fi

  printf '%s── %s ──%s\n' "$C_ERR" "$label" "$C_RST"
  printf '%s\n' "$hits" | while IFS= read -r line; do
    # 去掉仓库根前缀，输出相对路径
    printf '  %s\n' "${line/#$REPO_ROOT\//}"
  done
  TOTAL=$((TOTAL + $(printf '%s\n' "$hits" | wc -l | tr -d ' ')))
}

# 绝对路径（本地用户目录泄漏）
report "绝对路径" '(/Users/|/home/[a-z])'

# 公网 IPv4
report "公网 IP" '(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)'

# 常见密钥样式
report "密钥样式" '(sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{16,}|gho_[A-Za-z0-9]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN[A-Z ]*PRIVATE KEY)' 1

# 明文密码 / API Key 赋值
report "明文密码键" '(password[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']+["'"'"']|PASSWORD[[:space:]]*[:=]|API_KEY[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']+["'"'"'])' 1

# 个人 / 公司 / 私有服务标识
report "个人/公司标识" '(rafe|pintadao|fish\.cab|agnes-ai|siliconflow|longcat)'

echo ""
if [ "$TOTAL" -gt 0 ]; then
  printf '%s发现 %s 处敏感信息，禁止提交%s\n' "$C_ERR" "$TOTAL" "$C_RST"
  echo "请清理后重试。"
  exit 1
fi

printf '%s未发现敏感信息，可以提交。%s\n' "$C_OK" "$C_RST"
exit 0
