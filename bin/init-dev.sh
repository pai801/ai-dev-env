#!/usr/bin/env bash
#
# 在具体开发项目中初始化 openspec / codegraph / semble 三件套。
#
# 用法: init-dev [项目路径] [-n|--dry-run] [-y|--yes]
#
# 设计原则：
#   - 每步幂等，重复执行不会重复写入
#   - 任一工具缺失只记录不中断（能跑几步跑几步）
#   - 绝不删除项目内任何非本脚本创建的路径
#
set -uo pipefail

PROJECT=""
DRY_RUN=0
ASSUME_YES=0

# ── 输出 ────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK=$'\033[32m'; C_SKIP=$'\033[90m'; C_WARN=$'\033[31m'
  C_ADD=$'\033[36m'; C_CLEAN=$'\033[35m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_OK=''; C_SKIP=''; C_WARN=''; C_ADD=''; C_CLEAN=''; C_DIM=''; C_RST=''
fi

info()  { printf '%s\n' "$*"; }
ok()    { printf '%s[OK]%s %s\n'    "$C_OK"    "$C_RST" "$*"; }
skip()  { printf '%s[SKIP]%s %s\n'  "$C_SKIP"  "$C_RST" "$*"; }
warn()  { printf '%s[WARN]%s %s\n'  "$C_WARN"  "$C_RST" "$*" >&2; }
miss()  { printf '%s[MISS]%s %s\n'  "$C_WARN"  "$C_RST" "$*" >&2; }
add()   { printf '%s[ADD]%s %s\n'   "$C_ADD"   "$C_RST" "$*"; }
clean() { printf '%s[CLEAN]%s %s\n' "$C_CLEAN" "$C_RST" "$*"; }
dry()   { printf '%s[DRY] %s%s\n'   "$C_DIM"   "$*"     "$C_RST"; }

usage() {
  cat <<'EOF'
用法: init-dev [项目路径] [选项]

在指定项目中初始化 openspec / codegraph / semble 三件套。
项目路径省略时使用当前目录。

选项:
  -h, --help     显示本帮助
  -n, --dry-run  只打印将要执行的动作，不写任何文件
  -y, --yes      跳过交互确认

执行内容:
  1. openspec init   （已存在 openspec/ 目录则跳过）
  2. codegraph       （已存在 .codegraph/ 则增量索引，否则 init -i）
  3. .gitignore      追加 .codegraph/（仅 git 仓库）
  4. semble          仅验证可用性，不在项目内创建文件

说明:
  - 所有步骤幂等，可重复执行
  - codegraph 若误建 .cursor/rules/codegraph.mdc，且 .cursor 是本次新建的，会自动清理
  - 不会对非 git 目录执行 git init
EOF
}

# ── 参数解析 ────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    usage; exit 0 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    -y|--yes)     ASSUME_YES=1 ;;
    -*)           warn "未知参数: $1"; info "使用 --help 查看用法"; exit 1 ;;
    *)
      if [ -n "$PROJECT" ]; then
        warn "只能指定一个项目路径（已指定: $PROJECT）"
        exit 1
      fi
      PROJECT="$1"
      ;;
  esac
  shift
done

[ -n "$PROJECT" ] || PROJECT="$(pwd)"

# ── 前置检查 ────────────────────────────────────────────────────────
if [ ! -e "$PROJECT" ]; then
  warn "项目路径不存在: $PROJECT"
  exit 1
fi
if [ ! -d "$PROJECT" ]; then
  warn "项目路径不是目录: $PROJECT"
  exit 1
fi
PROJECT="$(cd "$PROJECT" && pwd -P)"

info "项目: $PROJECT"
[ "$DRY_RUN" -eq 1 ] && info "模式: dry-run（不写入任何文件）"
info ""

# 工具可用性
HAVE_OPENSPEC=0; HAVE_CODEGRAPH=0; HAVE_SEMBLE=0
command -v openspec  >/dev/null 2>&1 && HAVE_OPENSPEC=1
command -v codegraph >/dev/null 2>&1 && HAVE_CODEGRAPH=1
command -v semble    >/dev/null 2>&1 && HAVE_SEMBLE=1

[ "$HAVE_OPENSPEC"  -eq 0 ] && miss "openspec 未安装，请先运行 ai-dev-env 的 install.sh"
[ "$HAVE_CODEGRAPH" -eq 0 ] && miss "codegraph 未安装，请先运行 ai-dev-env 的 install.sh"
[ "$HAVE_SEMBLE"    -eq 0 ] && miss "semble 未安装，请先运行 ai-dev-env 的 install.sh"

# ── 交互确认 ────────────────────────────────────────────────────────
if [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
  printf '在 %s 初始化 openspec / codegraph? [Y/n] ' "$PROJECT"
  read -r ans || ans=""
  case "$ans" in
    n|N|no|NO) info "已取消"; exit 0 ;;
  esac
  info ""
fi

# ── 结果记录 ────────────────────────────────────────────────────────
ST_OPENSPEC="未安装"
ST_CODEGRAPH="未安装"
ST_GITIGNORE="跳过"
ST_SEMBLE="未安装"
FAILED=0

# 执行命令，失败时只回显尾部 5 行
run_cmd() {
  local log rc
  log="$(mktemp "${TMPDIR:-/tmp}/init-dev.XXXXXX")"
  bash -c "$1" >"$log" 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    warn "命令失败（exit $rc）: $1"
    tail -n 5 "$log" 2>/dev/null | sed 's/^/  /' || true
  fi
  rm -f "$log"
  return "$rc"
}

# ── 1. openspec ─────────────────────────────────────────────────────
if [ "$HAVE_OPENSPEC" -eq 1 ]; then
  if [ -d "$PROJECT/openspec" ]; then
    skip "openspec 已初始化"
    ST_OPENSPEC="已初始化"
  elif [ "$DRY_RUN" -eq 1 ]; then
    dry "openspec init --tools opencode,zed --no-animation \"$PROJECT\""
    ST_OPENSPEC="将初始化"
  else
    # 优先用带 --tools/--no-animation 的非交互形式，旧版本不支持时回退
    if run_cmd "openspec init --tools opencode,zed --no-animation \"$PROJECT\""; then
      ok "openspec 初始化完成"
      ST_OPENSPEC="新建"
    else
      warn "带 --tools/--no-animation 的调用失败，回退到 openspec init（可能进入交互流程）"
      if [ -t 0 ]; then
        if run_cmd "openspec init \"$PROJECT\""; then
          ok "openspec 初始化完成（回退模式）"
          ST_OPENSPEC="新建"
        else
          warn "[FAIL] openspec 初始化失败"
          ST_OPENSPEC="失败"
          FAILED=$((FAILED + 1))
        fi
      else
        warn "[FAIL] 非交互环境下无法回退，请手动执行 openspec init \"$PROJECT\""
        ST_OPENSPEC="失败"
        FAILED=$((FAILED + 1))
      fi
    fi
  fi
fi

# ── 2. codegraph ────────────────────────────────────────────────────
if [ "$HAVE_CODEGRAPH" -eq 1 ]; then
  cursor_existed=0
  [ -e "$PROJECT/.cursor" ] && cursor_existed=1

  if [ -d "$PROJECT/.codegraph" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      dry "codegraph index \"$PROJECT\"（增量）"
      ST_CODEGRAPH="将增量索引"
    else
      if run_cmd "codegraph index \"$PROJECT\""; then
        ok "codegraph 增量索引完成"
        ST_CODEGRAPH="增量索引"
      else
        warn "[FAIL] codegraph 增量索引失败"
        ST_CODEGRAPH="失败"
        FAILED=$((FAILED + 1))
      fi
    fi
  else
    if [ "$DRY_RUN" -eq 1 ]; then
      dry "codegraph init -i \"$PROJECT\""
      ST_CODEGRAPH="将初始化"
    else
      if run_cmd "codegraph init -i \"$PROJECT\""; then
        ok "codegraph 初始化完成"
        ST_CODEGRAPH="新建"
      else
        warn "[FAIL] codegraph 初始化失败"
        ST_CODEGRAPH="失败"
        FAILED=$((FAILED + 1))
      fi
    fi
  fi

  # 自动清理：仅当 .cursor 在 init 前不存在时才动它
  if [ "$DRY_RUN" -eq 0 ] && [ "$cursor_existed" -eq 0 ] && [ -d "$PROJECT/.cursor" ]; then
    stray="$PROJECT/.cursor/rules/codegraph.mdc"
    if [ -f "$stray" ]; then
      rm -f "$stray"
      clean "移除 codegraph 误创建的 .cursor/rules/codegraph.mdc"
      # 逐层回收本次新建的空目录（只删空目录，不会误删内容）
      for d in "$PROJECT/.cursor/rules" "$PROJECT/.cursor"; do
        if [ -d "$d" ] && [ -z "$(ls -A "$d" 2>/dev/null)" ]; then
          rmdir "$d" 2>/dev/null && clean "移除空目录 ${d#$PROJECT/}"
        fi
      done
    fi
  fi
fi

# ── 3. .gitignore ───────────────────────────────────────────────────
if [ -d "$PROJECT/.git" ]; then
  GI="$PROJECT/.gitignore"
  if [ -f "$GI" ] && grep -qE '^[[:space:]]*\.codegraph/?[[:space:]]*$' "$GI"; then
    skip ".gitignore 已包含 .codegraph/"
    ST_GITIGNORE="已存在"
  elif [ "$DRY_RUN" -eq 1 ]; then
    dry "向 \"$GI\" 追加 .codegraph/"
    ST_GITIGNORE="将追加"
  else
    # 原文件末尾无换行时先补一个，避免拼接成一行
    if [ -f "$GI" ] && [ -n "$(tail -c 1 "$GI" 2>/dev/null)" ]; then
      printf '\n' >> "$GI"
    fi
    printf '.codegraph/\n' >> "$GI"
    add ".gitignore 追加 .codegraph/"
    ST_GITIGNORE="已追加"
  fi
else
  info "非 git 仓库，跳过 .gitignore（未执行 git init，如需请手动 git init）"
  ST_GITIGNORE="非 git"
fi

# ── 4. semble ───────────────────────────────────────────────────────
if [ "$HAVE_SEMBLE" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    dry "semble search --help（仅验证可用性）"
    ST_SEMBLE="将验证"
  else
    if semble search --help >/dev/null 2>&1; then
      ok "semble 可用（首次 search 时自动建索引，索引缓存在用户目录）"
      ST_SEMBLE="可用"
    else
      warn "[FAIL] semble 不可用（semble search --help 执行失败）"
      ST_SEMBLE="失败"
      FAILED=$((FAILED + 1))
    fi
  fi
fi

# ── 汇总 ────────────────────────────────────────────────────────────
info ""
info "────────────────────────────────"
info "工具        状态"
info "openspec    $ST_OPENSPEC"
info "codegraph   $ST_CODEGRAPH"
info ".gitignore  $ST_GITIGNORE"
info "semble      $ST_SEMBLE"
info "────────────────────────────────"

if [ "$DRY_RUN" -eq 1 ]; then
  info "这是 dry-run，未写入任何文件。去掉 -n 即可真正执行。"
else
  info "下一步:"
  info "  - codegraph status \"$PROJECT\"   查看索引状态"
  info "  - openspec list                  查看已有变更提案"
fi

if [ "$FAILED" -gt 0 ]; then
  warn "有 $FAILED 项执行失败，请检查上面的输出。"
  exit 1
fi

exit 0
