---
name: my-archive
description: 归档流程技能。由用户主动调用或 my-apply 提示后调用，执行：清理中间产物→归档 openspec change→更新文档。
---

# my-archive — 归档流程

用户主动调用 `my-archive` 或收到 `my-apply` 的提示后，按以下流程执行：

```
用户调用 my-archive
    ↓
Step 1: 清理中间产物
    ↓
Step 2: 加载 openspec-archive-change skill，归档 openspec change
    ↓
Step 3: 派发 @docer 更新 README.md 及 docs/changelog.md
```

## 强制 Gate：归档前确认

在执行任何操作前，先确认与用户的意图一致。

如果是从 `my-apply` 流程衔接而来，上下文应包含 change name，优先使用该上下文。
否则询问用户需要归档哪个 openspec change，或从 `openspec list --json` 推断。

## Checklist

必须为以下每一项创建 todo 并按顺序完成：

1. **宣布启动** — "正在使用 my-archive skill 执行归档流程"

2. **清理中间产物** — 删除 `docs/superpowers/plans/` 与`docs/superpowers/specs/`目录：
   ```bash
   rm -rf docs/superpowers/plans/
   rm -rf docs/superpowers/specs/
   ```

3. **加载 openspec-archive-change skill** — 调用 `skill` 工具加载 openspec-archive-change
   - 按 openspec-archive-change 流程归档指定的 openspec change
   - 确认 `openspec` CLI 工具可用

4. **更新文档** — 派发 `@docer` 子 agent：
   - 更新 `README.md`（如有变动）
   - 更新 `docs/changelog.md`（记录本次变更）

5. **完成确认** — 向用户输出汇总：

   > "归档完成。已清理中间产物，openspec change `<name>` 已归档，文档已更新。"

## Guardrails

- 必须先清理中间产物，再归档 openspec change
- 归档后务必派发 `@docer` 更新文档
- **插件依赖检查**：加载 openspec-archive-change skill 或 `@docer` 子 agent 时，若返回失败，中断并提示缺少对应配置
- **错误恢复**：归档失败（如目标已存在）时，输出错误详情并给出恢复方案（重命名 / 覆盖确认 / 取消），等待用户决策
