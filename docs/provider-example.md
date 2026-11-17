# 接入你自己的模型 Provider

本仓库不包含任何真实的 provider 配置。`opencode.jsonc` 里只有一个占位骨架，你需要填入自己的服务地址、模型名和密钥。

下面所有示例中的域名、模型名均为占位符，替换成你自己的即可。

---

## 一、OpenCode 侧

编辑 `~/.config/opencode/opencode.jsonc`，在 `provider` 下新增一个条目。示例使用 `@ai-sdk/openai-compatible`，适用于绝大多数兼容 OpenAI 接口的服务：

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "your-provider": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "My Provider",
      "options": {
        "baseURL": "https://your-api.example.com/v1",
        "apiKey": "{env:MY_PROVIDER_API_KEY}"
      },
      "models": {
        "your-model": {
          "name": "Your Model",
          "limit": {
            "context": 200000,
            "output": 32000
          },
          "options": {
            "reasoningEffort": "medium"
          }
        }
      }
    }
  }
}
```

### 关键字段说明

| 字段 | 作用 |
|---|---|
| `provider.<id>` | provider 的内部 ID，后续 `model` 字段写作 `<id>/<model-id>` |
| `npm` | 使用的 AI SDK 适配包，OpenAI 兼容接口统一用 `@ai-sdk/openai-compatible` |
| `options.baseURL` | 服务地址，通常以 `/v1` 结尾 |
| `options.apiKey` | 密钥引用，**必须**写成 `{env:VAR}` 形式 |
| `models.<model-id>` | 模型标识，需与服务端接受的 model 参数一致 |
| `limit.context` | 上下文窗口大小，影响压缩与截断策略 |
| `limit.output` | 单次响应的最大输出 token |
| `options` | 透传给 SDK 的额外参数，如 `reasoningEffort` |

### 密钥用环境变量，不要写死

```jsonc
"apiKey": "{env:MY_PROVIDER_API_KEY}"
```

然后在本机环境里导出：

```bash
export MY_PROVIDER_API_KEY="sk-..."
```

建议写进 `~/.zshrc` 或 `~/.bashrc`，**不要**提交到任何仓库。`{env:VAR}` 由 OpenCode 在启动时解析，变量缺失会导致该 provider 认证失败并给出明确报错。

### 定义 variants

某些模型支持多档推理强度。`variants` 用于在同一模型下预置若干可选配置：

```jsonc
"models": {
  "your-model": {
    "name": "Your Model",
    "limit": { "context": 200000, "output": 32000 },
    "variants": {
      "fast": {
        "options": { "reasoningEffort": "low" }
      },
      "deep": {
        "options": { "reasoningEffort": "high" }
      }
    }
  }
}
```

会话里即可在模型选择器中切换 `fast` / `deep`。`reasoningEffort` 的合法取值由服务端决定，常见为 `low` / `medium` / `high`。

### 验证配置

```bash
opencode models
```

能列出 `your-provider/your-model` 即表示配置被正确加载。也可在 OpenCode 会话内执行 `/models` 查看。

如果该 provider 完全没有出现，按顺序检查：

1. JSON 语法错误（`jsonc` 允许注释，但不允许尾逗号滥用）
2. `npm` 适配包名拼错
3. `baseURL` 不可达或缺少 `/v1`

如果出现了但请求报 401/403，通常是 `apiKey` 的环境变量未导出或已失效。

---

## 二、Zed 侧

Zed 使用独立的模型配置，位于 `~/.config/zed/settings.json` 的 `language_models` 下：

```jsonc
{
  "language_models": {
    "openai_compatible": {
      "your-provider": {
        "api_url": "https://your-api.example.com/v1",
        "available_models": [
          {
            "name": "your-model",
            "max_tokens": 200000,
            "max_output_tokens": 32000,
            "capabilities": {
              "tools": true,
              "images": false,
              "parallel_tool_calls": false,
              "chat_completions": true
            }
          }
        ]
      }
    }
  }
}
```

| 字段 | 作用 |
|---|---|
| `api_url` | 服务地址，与 OpenCode 侧保持一致 |
| `available_models[].name` | 传给服务端的模型标识 |
| `available_models[].max_tokens` | 上下文窗口 |
| `available_models[].max_output_tokens` | 单次响应的最大输出 token |
| `capabilities.tools` | 是否支持工具调用；agent 模式下必须为 `true` |
| `capabilities.images` | 是否支持图片输入 |
| `capabilities.parallel_tool_calls` | 是否支持并行工具调用，不确定时设为 `false` |
| `capabilities.chat_completions` | 是否走 `/chat/completions` 接口，OpenAI 兼容服务通常为 `true` |

密钥同样走环境变量。Zed 会读取 `OPENAI_API_KEY`，若你的服务用其他变量名，建议在本地未跟踪的配置里做映射，或直接在 `api_url` 指向的网关侧处理认证。

---

## 三、agents 的 model 字段

每个 agent 的 frontmatter 支持 `model` 字段，格式为 `provider/model`：

```markdown
---
description: 按契约实现代码
mode: subagent
model: your-provider/your-model
---
```

这里的 `your-provider` 必须与 `opencode.jsonc` 中 `provider` 下的 key 一致，`your-model` 必须是该 provider 的 `models` 下定义的 key。写错不会报错，只会静默回退到默认模型，表现为「配了但没生效」。

**删除 `model` 这一行**则该 agent 继承父会话当前使用的模型，这是更省心的默认做法——切换主模型时所有子 agent 一起跟随。

建议策略：

- 通用 agent（`coder`、`reviewer`）不写 `model`，跟随父会话
- 需要固定成本或能力的 agent（如轻量杂务）显式绑定便宜的模型

---

## 四、安全提醒

- **绝不提交密钥**。本仓库的 `.gitignore` 已排除 `.env` 与 `.env.*`，但环境变量文件本身就不该放进仓库目录。
- 配置里只出现 `{env:VAR}`，不出现字面量密钥。
- 如需保存本地私有配置，放在仓库之外，或用未被跟踪的本地文件，提交前跑一次：

  ```bash
  ./scripts/scan-secrets.sh
  ```

- 分享配置截图或粘贴到 issue 前，先检查 `baseURL` 是否暴露了内网域名或公司信息。
