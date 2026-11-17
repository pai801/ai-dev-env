# ai-dev-env

一套可复刻的 AI 编码环境：OpenCode 全局配置 + Zed 配置 + 自定义 agents + 自定义 skills，全部收在一个仓库里。新电脑 `git clone` 后跑一次 `install.sh` 即可复刻。

---

## 包含什么

| 类别 | 内容 |
|---|---|
| OpenCode 全局配置 | `opencode.jsonc`（provider 骨架、MCP 声明位）、`AGENTS.md`（用户级 AI 编码指令） |
| 自定义 agents（7 个） | `architecter`、`coder`、`reviewer`、`docer`、`finaler`、`code-simplifier`、`utility` |
| 自研 skills（4 个） | `my-propose`、`my-contracts`、`my-apply`、`my-archive` |
| 编辑器配置 | Zed `settings.json`（context_servers、language_models） |

`config/opencode/AGENTS.md` 同时被安装为 OpenCode 的用户级指令和 Zed 的 `AGENTS.md`，两个编辑器共享同一套规范。

## 快速开始

### 前置条件

需要先安装 OpenCode 本体（`install.sh` 不会安装它）：

```bash
curl -fsSL https://opencode.ai/v2/install | bash
# 或
npm i -g @opencode/cli
```

验证：`opencode --version`

其余依赖（uv / semble / codegraph / openspec）由 `install.sh` 自动检测并安装，已存在的会跳过。

### 克隆并安装

```bash
git clone <your-repo-url> ~/work/github/ai-dev-env
cd ~/work/github/ai-dev-env
./install.sh --dry-run    # 先空跑看计划
./install.sh              # 确认后执行
```

`--dry-run` 只打印将要创建的链接和写入的文件，不会改动磁盘。建议每次都先空跑一遍。

## install.sh 参数

| 参数 | 作用 |
|---|---|
| `-n, --dry-run` | 空跑，只打印计划不写文件 |
| `-c, --copy` | 复制模式（默认是符号链接） |
| `-u, --uninstall` | 卸载，删除本仓库创建的软链 |
| `-y, --yes` | 跳过交互确认 |
| `--skip-deps` | 跳过依赖自动安装，只装配置 |
| `-h, --help` | 帮助 |

### 软链模式 vs 复制模式

- **软链模式（默认）**：目标路径指向仓库内的文件。之后在仓库里 `git pull`，配置立即生效，无需重装。
- **复制模式（`--copy`）**：把文件真实复制到目标路径。配置独立于仓库，仓库移动或删除不影响已安装的配置，但后续更新需要重新执行 `install.sh --copy`。

## 安装映射表

| 仓库内 | 安装到 |
|---|---|
| `config/opencode/opencode.jsonc` | `~/.config/opencode/opencode.jsonc` |
| `config/opencode/AGENTS.md` | `~/.config/opencode/AGENTS.md` |
| `config/opencode/AGENTS.md` | `~/.config/zed/AGENTS.md` |
| `config/opencode/agents/*.md` | `~/.config/opencode/agents/` |
| `config/opencode/skills/*/` | `~/.agents/skills/` |
| `config/zed/settings.json` | `~/.config/zed/settings.json` |
| `bin/init-dev.sh` | `~/.local/bin/init-dev` |

安装前会备份已存在的同名文件（`*.bak-<时间戳>`），不会静默覆盖。

## 安装后必做

1. **配置 provider**
   编辑 `~/.config/opencode/opencode.jsonc`，接入你自己的模型服务。完整示例见 [`docs/provider-example.md`](docs/provider-example.md)。
   密钥一律用环境变量引用，禁止硬编码：

   ```jsonc
   "apiKey": "{env:MY_PROVIDER_API_KEY}"
   ```

2. **检查依赖**

   ```bash
   ./scripts/check-tools.sh
   ```

   缺什么会直接列出来，按提示补齐即可（见下节）。

3. **重启 OpenCode**，或在会话内执行 `/reload` 让配置生效。

4. **Zed 用户**：确认 `~/.config/zed/settings.json` 里 `context_servers` 的 `codegraph` / `semble` 可用；不可用时先装对应 CLI，或从配置里移除该条目。

## 依赖说明

| 依赖 | 分级 | 用途 | 安装 |
|---|---|---|---|
| `git` | 必需 | 克隆仓库、运行 `install.sh` | 系统包管理器 |
| `node` / `npm` | 必需 | 安装 OpenCode、codegraph、openspec（需 Node 20+） | `brew install node` 或 [nodejs.org](https://nodejs.org) |
| `opencode` | 必需 | 主体运行时 | `curl -fsSL https://opencode.ai/v2/install \| bash` 或 `npm i -g @opencode/cli` |
| `uv` | 必需 | 安装并运行 semble | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| `semble` | 必需 | 语义代码搜索（`AGENTS.md` 工具协议依赖） | `uv tool install semble` |
| `codegraph` | 必需 | 代码知识图谱索引 | `npm i -g @colbymchenry/codegraph` |
| `openspec` | 推荐 | `my-propose` / `my-archive` 的依赖 | `npm i -g @fission-ai/openspec` |

`install.sh` 默认按上表顺序自动安装缺失的依赖（`uv` → `semble` → `codegraph` → `openspec`），已存在的跳过并打印版本；`node` 不会被自动安装，缺失时 `codegraph` / `openspec` 会安装失败。

依赖安装失败**不会中断**配置安装：配置仍会全部装完，但脚本最终以非零退出码结束并汇总失败项。`--skip-deps` 可完全跳过依赖环节。推荐项（`openspec`）缺失只提示，不影响退出码。

## 目录结构

```
ai-dev-env/
├── install.sh                      # 安装/卸载入口
├── bin/
│   └── init-dev.sh                 # 在项目中初始化 openspec/codegraph/semble
├── scripts/
│   ├── check-tools.sh              # 依赖自检
│   └── scan-secrets.sh             # 提交前敏感信息扫描
├── config/
│   ├── opencode/
│   │   ├── opencode.jsonc          # 全局配置（provider 占位）
│   │   ├── AGENTS.md               # 用户级 AI 编码指令
│   │   ├── agents/                 # 7 个 subagent
│   │   └── skills/                 # 4 个自研 skill
│   └── zed/
│       └── settings.json           # Zed 配置
├── docs/
│   └── provider-example.md         # provider 接入示例
├── .gitignore
├── LICENSE
└── README.md
```

## 脱敏原则

本仓库定位是**可公开分享的骨架**，因此已剔除以下内容：

- 任何真实 provider 的 `baseURL`、`apiKey`、账号信息
- MCP server 的凭据与私有端点
- SSH / 远程连接配置
- 个人目录路径、内网 IP、公司信息

提交前建议自检一遍：

```bash
./scripts/scan-secrets.sh
```

## 自定义

### 加一个 agent

在 `config/opencode/agents/` 下新建 `<name>.md`，frontmatter 最少需要 `description`：

```markdown
---
description: 一句话说明这个 agent 干什么、什么时候该用它
mode: subagent
---

具体的系统提示词写在这里。
```

需要绑定特定模型时加 `model: provider/model`；不写则继承父会话的模型。

### 加一个 skill

在 `config/opencode/skills/` 下新建目录 `<skill-name>/`，内含 `SKILL.md`，frontmatter 最少需要 `name` 和 `description`：

```markdown
---
name: my-skill
description: 说明这个 skill 解决什么问题、什么情况下加载
---

正文写具体流程与约束。
```

`description` 是 skill 被自动检索匹配的唯一依据，写清楚触发场景比写长正文更重要。

改完重新执行 `./install.sh`（软链模式下新文件需要重新链接一次），或在会话内 `/reload`。

> **路径说明**：skill 统一安装到 `~/.agents/skills/`。如果你之前用旧版脚本装到了
> `~/.config/opencode/skills/`，那批旧软链不会被自动清理，可手动删除：
> `rm -f ~/.config/opencode/skills/{my-propose,my-contracts,my-apply,my-archive}`
> （只删软链，不要 `rm -rf` 整个目录）

## License

[MIT](LICENSE)
