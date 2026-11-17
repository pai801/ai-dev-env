#!/usr/bin/env bash
#
# 个人 AI 编码环境一键安装脚本
#
# 默认以符号链接方式安装（仓库即生效源），--copy 改为复制。
# 目标已存在时自动备份为 <name>.bak-YYYYMMDD-HHMMSS，绝不删除用户目录。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$SCRIPT_DIR"

MODE="link"        # link | copy
DRY_RUN=0
UNINSTALL=0
ASSUME_YES=0
SKIP_DEPS=0

# ── 输出 ────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK=$'\033[32m'; C_SKIP=$'\033[90m'; C_BAK=$'\033[33m'
  C_WARN=$'\033[31m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_OK=''; C_SKIP=''; C_BAK=''; C_WARN=''; C_DIM=''; C_RST=''
fi

info() { printf '%s\n' "$*"; }
ok()   { printf '%s[OK]%s %s\n'   "$C_OK"   "$C_RST" "$*"; }
skip() { printf '%s[SKIP]%s %s\n' "$C_SKIP" "$C_RST" "$*"; }
bak()  { printf '%s[BAK]%s %s\n'  "$C_BAK"  "$C_RST" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_WARN" "$C_RST" "$*" >&2; }
dry()  { printf '%s%s%s\n'         "$C_DIM"  "$*"      "$C_RST"; }

usage() {
  cat <<'EOF'
用法: ./install.sh [选项]

将本仓库的 opencode / zed 配置安装到当前用户的主目录。

选项:
  -h, --help        显示本帮助
  -n, --dry-run     只打印将要执行的动作，不写任何文件
  -c, --copy        复制模式（默认使用符号链接）
  -u, --uninstall   卸载：删除指向本仓库的软链，并恢复最新备份
  -y, --yes         跳过交互确认
  --skip-deps       跳过依赖安装，只装配置

依赖安装（默认执行，已存在则跳过）:
  uv          curl -LsSf https://astral.sh/uv/install.sh | sh
  semble      uv tool install semble
  codegraph   npm i -g @colbymchenry/codegraph
  openspec    npm i -g @fission-ai/openspec
  node 不会被自动安装：缺失时 codegraph / openspec 会安装失败，请先自行安装。

默认安装目标:
  config/opencode/opencode.jsonc  -> ~/.config/opencode/opencode.jsonc
  config/opencode/AGENTS.md       -> ~/.config/opencode/AGENTS.md
  config/opencode/AGENTS.md       -> ~/.config/zed/AGENTS.md
  config/opencode/agents/*.md     -> ~/.config/opencode/agents/
  config/opencode/skills/*/       -> ~/.agents/skills/
  config/zed/settings.json        -> ~/.config/zed/settings.json
  bin/init-dev.sh                 -> ~/.local/bin/init-dev

说明:
  - 目标已存在且不是指向本仓库的软链时，会先备份为 <name>.bak-YYYYMMDD-HHMMSS
  - 重复执行是幂等的，不会产生多余备份
  - 不会修改任何 shell 配置文件（.zshrc / .bashrc 等）
  - 不会执行 rm -rf 删除用户目录
  - --uninstall 只卸载配置与 init-dev，不会卸载任何依赖工具
EOF
}

# ── 参数解析 ────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)      usage; exit 0 ;;
    -n|--dry-run)   DRY_RUN=1 ;;
    -c|--copy)      MODE="copy" ;;
    -u|--uninstall) UNINSTALL=1 ;;
    -y|--yes)       ASSUME_YES=1 ;;
    --skip-deps)    SKIP_DEPS=1 ;;
    *) warn "未知参数: $1"; info "使用 --help 查看用法"; exit 1 ;;
  esac
  shift
done

# ── 路径工具 ────────────────────────────────────────────────────────
# 解析软链链并规范化（macOS 无 readlink -f，用 cd -P 逐段解析）
resolve_path() {
  local p="$1" hops=0 l
  while [ -L "$p" ] && [ "$hops" -lt 40 ]; do
    l="$(readlink "$p")"
    case "$l" in
      /*) p="$l" ;;
      *)  p="$(dirname "$p")/$l" ;;
    esac
    hops=$((hops + 1))
  done
  if [ -d "$p" ]; then
    ( cd -P "$p" && pwd -P )
  elif [ -d "$(dirname "$p")" ]; then
    printf '%s/%s\n' "$(cd -P "$(dirname "$p")" && pwd -P)" "$(basename "$p")"
  else
    printf '%s\n' "$p"
  fi
}

is_link_into_repo() {
  [ -L "$1" ] || return 1
  case "$(resolve_path "$1")" in
    "$REPO_ROOT"/*) return 0 ;;
    *) return 1 ;;
  esac
}

same_content() {
  local a="$1" b="$2"
  if [ -d "$a" ] && [ -d "$b" ]; then
    diff -rq "$a" "$b" >/dev/null 2>&1
  elif [ -f "$a" ] && [ -f "$b" ]; then
    cmp -s "$a" "$b"
  else
    return 1
  fi
}

# 是否存在内容相同的备份
identical_backup_exists() {
  local dst="$1" b
  for b in "$dst".bak-*; do
    [ -e "$b" ] || continue
    same_content "$dst" "$b" && return 0
  done
  return 1
}

# 生成不冲突的备份路径：<dst>.bak-<TS>，已存在则依次尝试 -2、-3…
# 避免同一秒内重复运行时 mv 覆盖掉上一次备份的用户原文件
unique_bak_path() {
  local dst="$1" ts="$2" cand i=2
  cand="$dst.bak-$ts"
  while [ -e "$cand" ] || [ -L "$cand" ]; do
    cand="$dst.bak-$ts-$i"
    i=$((i + 1))
  done
  printf '%s\n' "$cand"
}

# ── 依赖安装 ────────────────────────────────────────────────────────
# 安装顺序即数组顺序：uv 必须在 semble 之前。
DEP_NAMES=(uv semble codegraph openspec)

dep_install_cmd() {
  case "$1" in
    uv)        printf '%s' 'curl -LsSf https://astral.sh/uv/install.sh | sh' ;;
    semble)    printf '%s' 'uv tool install semble' ;;
    codegraph) printf '%s' 'npm i -g @colbymchenry/codegraph' ;;
    openspec)  printf '%s' 'npm i -g @fission-ai/openspec' ;;
  esac
}

# 打印版本；semble 不支持 --version，改用 uv tool list
# dry-run 下禁止调用 uv（会创建 ~/.cache/uv），只报"已安装"
dep_version() {
  local name="$1" out=""
  case "$name" in
    semble)
      if [ "$DRY_RUN" -eq 1 ]; then
        out="(已安装)"
      else
        out="$(uv tool list 2>/dev/null | grep -E '^semble ' | head -n 1 || true)"
      fi
      ;;
    *)
      out="$("$name" --version 2>/dev/null | head -n 1 || true)"
      ;;
  esac
  [ -n "$out" ] || out="(版本未知)"
  printf '%s\n' "$out" | cut -c1-80
}

# uv 安装后可能落到 ~/.local/bin，本次进程内临时补进 PATH 以便立即验证
ensure_local_bin_on_path() {
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH"; export PATH ;;
  esac
}

# 执行安装命令，失败时只回显尾部 5 行，避免刷屏
run_install_cmd() {
  local cmd="$1" log
  log="$(mktemp "${TMPDIR:-/tmp}/ai-dev-env-dep.XXXXXX")"
  if bash -c "$cmd" >"$log" 2>&1; then
    rm -f "$log"
    return 0
  fi
  warn "安装命令失败: $cmd"
  info "  ── 输出末尾 ──"
  tail -n 5 "$log" 2>/dev/null | sed 's/^/  /' || true
  info "  ──────────────"
  rm -f "$log"
  return 1
}

n_dep_installed=0
n_dep_present=0
n_dep_failed=0

install_deps() {
  info "── 依赖 ──────────────────────────────"

  local name cmd node_ok=1 uv_ok=1
  command -v node >/dev/null 2>&1 || node_ok=0
  command -v uv >/dev/null 2>&1 || uv_ok=0
  if [ "$node_ok" -eq 0 ]; then
    warn "未检测到 node，codegraph / openspec 将无法安装（本脚本不会自动安装 node）"
  fi

  for name in "${DEP_NAMES[@]}"; do
    ensure_local_bin_on_path

    # 已存在：跳过
    if command -v "$name" >/dev/null 2>&1; then
      ok "$name $(dep_version "$name")（已存在）"
      n_dep_present=$((n_dep_present + 1))
      continue
    fi

    cmd="$(dep_install_cmd "$name")"

    # 依赖 node 的工具在 node 缺失时直接判定失败，不执行注定失败的命令
    case "$name" in
      codegraph|openspec)
        if [ "$node_ok" -eq 0 ]; then
          warn "[FAIL] $name 未安装，且缺少 node，无法自动安装（请先安装 node 后重跑）"
          n_dep_failed=$((n_dep_failed + 1))
          continue
        fi
        ;;
    esac

    # dry-run：只打印计划，绝不执行任何安装命令
    if [ "$DRY_RUN" -eq 1 ]; then
      # 本轮计划安装 uv，则 semble 视为可安装
      if [ "$name" = "semble" ] && [ "$uv_ok" -eq 0 ]; then
        printf '%s[DRY] 将安装 %s（%s，依赖本轮安装的 uv）%s\n' "$C_DIM" "$name" "$cmd" "$C_RST"
      else
        printf '%s[DRY] 将安装 %s（%s）%s\n' "$C_DIM" "$name" "$cmd" "$C_RST"
      fi
      n_dep_installed=$((n_dep_installed + 1))
      [ "$name" = "uv" ] && uv_ok=1
      continue
    fi

    # semble 依赖 uv：uv 本轮安装失败时直接失败
    if [ "$name" = "semble" ] && [ "$uv_ok" -eq 0 ]; then
      warn "[FAIL] semble 依赖 uv，但 uv 不可用，跳过安装"
      n_dep_failed=$((n_dep_failed + 1))
      continue
    fi

    info "安装 $name ..."
    if run_install_cmd "$cmd"; then
      ensure_local_bin_on_path
      if command -v "$name" >/dev/null 2>&1; then
        ok "$name $(dep_version "$name")（已安装）"
        n_dep_installed=$((n_dep_installed + 1))
        [ "$name" = "uv" ] && uv_ok=1
      else
        warn "[FAIL] $name 安装后仍不可用"
        n_dep_failed=$((n_dep_failed + 1))
      fi
    else
      warn "[FAIL] $name 安装失败"
      n_dep_failed=$((n_dep_failed + 1))
    fi
  done

  info ""
}

# ── 安装映射 ────────────────────────────────────────────────────────
# 输出 "源路径|目标路径"
plan_entries() {
  printf '%s|%s\n' "$REPO_ROOT/config/opencode/opencode.jsonc" "$HOME/.config/opencode/opencode.jsonc"
  printf '%s|%s\n' "$REPO_ROOT/config/opencode/AGENTS.md"      "$HOME/.config/opencode/AGENTS.md"
  printf '%s|%s\n' "$REPO_ROOT/config/opencode/AGENTS.md"      "$HOME/.config/zed/AGENTS.md"

  local f d
  for f in "$REPO_ROOT"/config/opencode/agents/*.md; do
    [ -e "$f" ] || continue
    printf '%s|%s\n' "$f" "$HOME/.config/opencode/agents/$(basename "$f")"
  done
  for d in "$REPO_ROOT"/config/opencode/skills/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    printf '%s|%s\n' "$d" "$HOME/.agents/skills/$(basename "$d")"
  done

  printf '%s|%s\n' "$REPO_ROOT/config/zed/settings.json" "$HOME/.config/zed/settings.json"

  printf '%s|%s\n' "$REPO_ROOT/bin/init-dev.sh" "$HOME/.local/bin/init-dev"
}

# ── 卸载 ────────────────────────────────────────────────────────────
do_uninstall() {
  local removed=0 restored=0 kept=0 line src dst latest
  info "卸载：仅移除指向 $REPO_ROOT 的软链"
  info "（不会卸载 uv / semble / codegraph / openspec 等依赖工具，需要时请自行卸载）"
  info ""

  while IFS='|' read -r src dst; do
    [ -n "$dst" ] || continue

    if [ -L "$dst" ] && is_link_into_repo "$dst"; then
      if [ "$DRY_RUN" -eq 1 ]; then
        dry "将删除软链 $dst"
        removed=$((removed + 1))
      else
        rm -f "$dst"
        ok "已删除软链 $dst"
        removed=$((removed + 1))
      fi

      latest="$(ls -1d "$dst".bak-* 2>/dev/null | sort | tail -n 1 || true)"
      if [ -n "$latest" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          dry "将恢复 $latest -> $dst"
        else
          mv "$latest" "$dst"
          ok "已恢复备份 $latest"
        fi
        restored=$((restored + 1))
      fi
    elif [ -e "$dst" ]; then
      warn "跳过 ${dst}（非本仓库软链，可能是复制模式安装或你自己的文件，请手动处理）"
      kept=$((kept + 1))
    else
      skip "不存在 $dst"
    fi
  done < <(plan_entries)

  info ""
  info "────────────────────────────────"
  info "移除软链: $removed 项    恢复备份: $restored 项    保留未动: $kept 项"
  info "依赖工具未做任何改动（uv / semble / codegraph / openspec 仍在原处）"
  info "────────────────────────────────"
  exit 0
}

if [ "$UNINSTALL" -eq 1 ]; then
  do_uninstall
fi

# ── 交互确认 ────────────────────────────────────────────────────────
if [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
  info ""
  if [ "$MODE" = "copy" ]; then
    info "模式: 复制（${REPO_ROOT} → \$HOME）"
  else
    info "模式: 符号链接（${REPO_ROOT} → \$HOME）"
  fi
  if [ "$SKIP_DEPS" -eq 1 ]; then
    info "依赖: 跳过（--skip-deps）"
  else
    info "依赖: 自动检测并安装缺失的 uv / semble / codegraph / openspec"
  fi
  printf '继续安装? [y/N] '
  read -r ans || ans=""
  case "$ans" in
    y|Y|yes|YES) ;;
    *) info "已取消"; exit 0 ;;
  esac
fi

if [ "$DRY_RUN" -eq 1 ]; then
  info "[dry-run] 仅打印计划，不写入任何文件"
  info ""
fi

# ── 依赖安装 ────────────────────────────────────────────────────────
if [ "$SKIP_DEPS" -eq 1 ]; then
  skip "跳过依赖安装"
  info ""
else
  install_deps
fi

# ── 安装 ────────────────────────────────────────────────────────────
TS="$(date +%Y%m%d-%H%M%S)"
n_install=0
n_backup=0
n_skip=0
n_warn=0

install_one() {
  local src="$1" dst="$2" bak_path

  if [ ! -e "$src" ]; then
    warn "源文件缺失，跳过: $src"
    n_warn=$((n_warn + 1))
    return 0
  fi

  # 已是指向本仓库的软链：直接跳过，不备份
  if is_link_into_repo "$dst"; then
    skip "已安装 $dst"
    n_skip=$((n_skip + 1))
    return 0
  fi

  # 复制模式下内容完全一致：跳过，避免重复备份
  if [ "$MODE" = "copy" ] && [ -e "$dst" ] && same_content "$src" "$dst"; then
    skip "内容一致 $dst"
    n_skip=$((n_skip + 1))
    return 0
  fi

  # 备份已存在的目标
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if identical_backup_exists "$dst"; then
      skip "已有相同内容备份，跳过备份 $dst"
      n_skip=$((n_skip + 1))
      if [ -d "$dst" ] && [ ! -L "$dst" ]; then
        warn "目标是非本仓库目录且已有同内容备份，为避免删除用户数据，跳过该项: $dst"
        n_warn=$((n_warn + 1))
        return 0
      fi
      if [ "$DRY_RUN" -eq 0 ]; then
        rm -f "$dst"
      fi
    else
      if [ "$DRY_RUN" -eq 1 ]; then
        dry "将备份 $dst → $(unique_bak_path "$dst" "$TS")"
      else
        bak_path="$(unique_bak_path "$dst" "$TS")"
        mv "$dst" "$bak_path"
        bak "已备份 $dst → $bak_path"
      fi
      n_backup=$((n_backup + 1))
    fi
  fi

  # 创建父目录并安装
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$MODE" = "copy" ]; then
      dry "将复制 $src → $dst"
    else
      dry "将链接 $src → $dst"
    fi
    n_install=$((n_install + 1))
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  if [ "$MODE" = "copy" ]; then
    if [ -d "$src" ]; then
      cp -R "$src" "$dst"
    else
      cp "$src" "$dst"
    fi
    ok "已复制 $dst"
  else
    ln -s "$src" "$dst"
    ok "已链接 $dst"
  fi
  n_install=$((n_install + 1))
}

info "开始安装（$([ "$MODE" = "copy" ] && echo 复制模式 || echo 符号链接模式)）"
info ""

while IFS='|' read -r src dst; do
  [ -n "$dst" ] || continue
  install_one "$src" "$dst"
done < <(plan_entries)

# ── 汇总 ────────────────────────────────────────────────────────────
info ""
info "────────────────────────────────"
info "安装: $n_install 项    备份: $n_backup 项    跳过: $n_skip 项    警告: $n_warn 项"
if [ "$SKIP_DEPS" -eq 1 ]; then
  info "依赖: 已跳过（--skip-deps）"
else
  info "依赖：已安装 $n_dep_installed 项 / 已存在 $n_dep_present 项 / 失败 $n_dep_failed 项"
fi
info "────────────────────────────────"

# ~/.local/bin 是否在 PATH 中（init-dev 与 uv 工具都落在这里）
path_warning() {
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) return 0 ;;
  esac
  warn "────────────────────────────────────────────"
  warn " $HOME/.local/bin 不在你的 PATH 中"
  warn " init-dev 与 uv/semble 都安装在这里，不加 PATH 将无法直接调用。"
  warn ""
  warn ' 请把下面这一行加入 ~/.zshrc（或 ~/.bashrc）：'
  warn ""
  warn '   export PATH="$HOME/.local/bin:$PATH"'
  warn ""
  warn " 然后执行 source ~/.zshrc 或新开终端。"
  warn " 本脚本不会自动修改你的 shell 配置文件。"
  warn "────────────────────────────────────────────"
}

if [ "$DRY_RUN" -eq 1 ]; then
  info "这是 dry-run，未写入任何文件。去掉 -n 即可真正执行。"
else
  path_warning
  info "下一步:"
  info "  1. 重启 opencode（或新开终端）使全局配置生效"
  info "  2. 检查 provider 配置：opencode.jsonc 中的 provider 需自行填写"
  info "     （密钥请用 {env:XXX} 环境变量引用，示例见 docs/provider-example.md）"
  info "  3. 运行 ./scripts/check-tools.sh 确认依赖齐全"
  info "  4. 进入任意项目执行 init-dev 初始化 openspec / codegraph / semble"
fi

# 配置已装好，但依赖不全时以非零退出，便于上层判断（dry-run 不据此报错）
if [ "$SKIP_DEPS" -eq 0 ] && [ "$DRY_RUN" -eq 0 ] && [ "$n_dep_failed" -gt 0 ]; then
  warn "有 $n_dep_failed 项依赖安装失败，配置已安装完成但功能可能不完整。"
  exit 1
fi

exit 0
