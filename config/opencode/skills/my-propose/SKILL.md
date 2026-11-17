---
name: my-propose
description: 提案流程技能。由用户主动调用，执行：brainstorming 头脑风暴→设计确认→openspec-propose 输出产物→提示使用 my-apply。
---

# my-propose — 提案流程

用户主动调用 `my-propose` 后，按以下流程执行：

```
用户调用 my-propose
    ↓
加载 brainstorming skill，与用户头脑风暴
    ↓
获得设计确认
    ↓
将设计内容作为输入，加载 openspec-propose skill 输出提案产物
    ↓
提示用户：使用 my-apply skill 进入实现阶段
```

## Checklist

必须为以下每一项创建 todo 并按顺序完成：

1. **宣布启动** — "正在使用 my-propose skill 执行提案流程"

2. **加载 brainstorming skill** — 调用 `skill` 工具加载 brainstorming
   - 按 brainstorming skill 流程与用户讨论需求、约束、方案
   - 所有提问必须使用 `question` tool 给出选项（多选一），禁止纯文本提问让用户打字
   - 产出设计文档并获得用户明确确认

3. **设计确认** — 用户明确批准设计后进入下一步

4. **保存设计文档** — 将 brainstorming 产出的设计文档保存至 `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`

5. **调用 openspec-propose skill** — 以设计文档内容作为输入，调用 `skill` 工具加载 openspec-propose
   - 将设计结论作为上下文提供给 openspec-propose
   - 确认 `openspec` CLI 工具可用（`which openspec`）
   - 调用 `openspec new change "<kebab-case-name>"` 创建 change
   - 按其流程依次生成 proposal.md、design.md、specs/*/spec.md、tasks.md 等提案产物

6. **输出汇总 & 提示 my-apply** — 向用户展示产物清单，并提示：
   > "提案产物已就绪。使用 `my-apply` skill 进入实现阶段。"

## Guardrails

- 未完成 brainstorming 前，禁止加载 openspec-propose
- 设计确认必须获得用户明确认可，不能默认通过
- 必须先保存 brainstorming 产出的设计文档，再加载 openspec-propose
- **插件依赖检查**：加载 brainstorming 或 openspec-propose 时，若 skill 工具返回失败（技能不存在/未安装），立即中断流程，提示用户：
  > "缺少依赖技能：`<技能名>`。请先安装对应的 skill 插件后再重试。"
- **CLI 依赖检查**：使用 openspec-propose 前必须检查 `openspec` CLI 是否可用。若不可用，中断并提示：
  > "缺少 CLI 工具：`openspec`。请先安装 openspec CLI。"
- **错误恢复**：任一环节出错（openspec CLI 失败、brainstorming 中断、产物生成失败），输出错误详情并给出恢复方案（重试 / 手动修复后继续 / 回退），等待用户决策
