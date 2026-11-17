> 本文为 my-apply-flow（方案拟更名 my-apply）的设计期文档，记录 2026-09-24 的演进动机与决策，
> 其中引用的 my-simple-apply / writing-contracts / simple-contracts / @simple-architect
> 属于合并退役对象；实施状态以主仓 docs/2026-09-24-apply-contracts-architect-合并方案.md 的验收记录为准。

> **当前状态 delta（2026-09-25 起生效，冲突时以 SKILL.md 为准）**：
> - 隔离分组与串行屏障由**主 agent** 计算，`@architecter` 不产出；
> - 子agent 名为 `@architecter`，契约技能为 `my-contracts`（三档 light/standard/strict）；
> - 本设计文档全文（§1–§12）为历史记录；其中 `@simple-architect` 等退役术语散见于 §2/§6/§8/§12，均不代表当前实现；
> - 不再委托 SDD；Phase 4 收尾按 SKILL.md 的 OpenSpec / ad-hoc 双分支执行。

# my-apply-flow 设计文档

- **状态**：已通过设计评审，待实现
- **日期**：2026-09-24
- **交付物**：`~/.agents/skills/my-apply-flow/SKILL.md`（取代 `my-simple-apply`）

---

## 1. 背景

现有三套实现阶段编排技能，演进主线为：

`my-apply`（薄编排，循环全交 SDD）→ `my-apply-contracts`（契约先行 + 严格 TDD + 分层派发）→ `my-simple-apply`（去掉 TDD，其余骨架原样复制）。

三套技能只在「严格度」一根轴上变化（要不要计划、要不要契约、要不要 TDD），**没有任何一套在「并发度」轴上做过事**。执行骨架（`@coder → spec 审查 → quality 审查`、逐任务、严格串行）在 `my-apply-contracts` 阶段一次性锁死，`my-simple-apply` 只换了契约类型，骨架逐字继承。

实测后果：一个 55 任务的 change（private-channel-kit）跑约 20 小时仅完成 37 个任务。慢不是执行者的问题，而是骨架本身就是 O(任务数) 串行 × 每任务两审，且全流程没有任何并发模型。

### 1.1 根因清单

| 根因 | 表现 |
|---|---|
| 派发单元 = 单个任务 | 55 个串行点 |
| 每任务 2 次审查 | ≥110 次审查派发 |
| 每任务全量测试 | 55 次全量回归 |
| 任何驳回 → fresh coder | 单次小修付出整轮重建代价 |
| 契约一刀切（1589 行） | 机械迁移任务背负重资产 |
| advisory 也阻断 | 风格问题触发重试与人工裁决 |
| 派发者归属模糊 | 文本既说「交给 SDD」又说「主 agent 直接派发」 |

---

## 2. 目标与非目标

### 目标
- 在保证实现正确、可审计的前提下，把实现阶段的**墙钟时间**显著下降（目标：同类 change 下降一个数量级）。
- 合并为**单一技能**，日常只有一个入口，消除多技能路由混乱。
- 保留原有优点：契约与验收分离、审查阶段隔离、OpenSpec 为真源、Blocked 重启机制、术语一致性。

### 非目标
- 不修改 OpenSpec 的 `tasks.md` / `specs` / `design.md`；OpenSpec 仍是任务真源。
- 不引入新的 subagent 类型（复用 `@simple-architect` / `@coder` / `@reviewer` / `@utility`）。
- 不改变「主 agent 绝不下场写代码/跑测试」的铁律。

---

## 3. 设计决策（均已确认）

| # | 决策点 | 选择 |
|---|---|---|
| D1 | 技能定位 | 统一单技能，取代 `my-simple-apply` |
| D2 | 并发模型 | 有界并发 + 隔离分组 |
| D3 | 审查模型 | spec 逐任务 + quality 按里程碑 |
| D4 | 验证范围 | 增量验证 + 里程碑全量 |
| D5 | 契约模型 | 分级契约：迁移轻 / 新接口重 |
| D6 | 重试模型 | 分级重试：小改复用会话 / 大错 fresh |
| D7 | 隔离粒度 | **以 Go 包/模块为隔离单位**（同包串行） |

> D7 说明：Go 的编译单元是「包」而非「文件」。同包内两个并行 @coder 改不同文件时，A 的中间态语法错误会让 B 的 `go test ./pkg` 假失败。因此并发隔离单位定为**包**，同包任务串行。

---

## 4. 核心模型

- **Task** — OpenSpec `tasks.md` 中的一条（真源不变）。
- **Unit（派发单元）** — 同一包内、文件互不重叠、无符号依赖的一组 Task，交给一个 `@coder`。
- **Wave（波次）** — 一组包互不相交、可并发的 Unit。**波内并行，波间串行。**
- **Barrier（屏障）** — 波次收尾的同步点：编译 + 受影响包测试。所有并发写者必须先完成，Barrier 才执行。

**串行粒度从「任务」上移到「波次」**：原 55 个串行点降为约等于「阶段数」。

### 4.1 强制串行点（识别规则）
- 同一包内的多个 Task。
- 共享文件被多任务触碰（如 `trae/adaptor.go`、`registry`）。
- 跨包符号依赖：若 Task B 依赖 Task A 新引入/修改的导出符号，则 B 必须排在 A 之后。
- 共享依赖包（如 `internal/channelkit`）被多任务修改时，相关任务串行化。

---

## 5. 两个旋钮

### 5.1 rigor（严格度）— 按 change 类型推荐，用户可覆盖

| 档 | 适用 | 契约 | TDD |
|---|---|---|---|
| `light` | 机械迁移 / 重构 / 搬迁 | 源→目标文件映射 + 等价断言 | 否 |
| `standard` | 一般功能开发 | `simple-contracts` | 否 |
| `strict` | 绿地 / 高风险 / 新接口 | `writing-contracts` | 是（RED-GREEN-REFACTOR） |

### 5.2 concurrency（并发度）

| 档 | 隔离单位 | 行为 |
|---|---|---|
| `serial` | — | 一任务一波（等价旧技能，保底） |
| `pkg`（默认） | Go 包/模块 | 不同包并行，同包串行 |
| `auto` | 规划器判定 | 规划阶段自动分组分波 |

---

## 6. 执行流程

```
Phase 0  规划（一次）
  @simple-architect 产出：
    ① 每任务的 Files 清单
    ② 复杂度分级（simple/standard/complex）
    ③ 契约分级（light/standard/strict）
    ④ 隔离分组 + 串行屏障识别
  主 agent 独立校验：
    - 隔离组内无文件/符号重叠
    - 每任务有分级
    - spec 全覆盖（每个需求映射到任务）
  失败 → 退回 @simple-architect 重写

Phase 1  波次执行
  对每一波：
    - 并行派发 N 个 @coder（background，包互不相交）
    - 全部完成后 → Barrier：编译 + 受影响包增量测试

Phase 2  审查
  - spec 审查：逐任务（只读，可并行）
  - quality 审查：每里程碑一次（合并该里程碑 diff）

Phase 3  验证
  - 任务级：受影响包测试（go test ./受影响包/...）
  - 里程碑级：全量回归

Phase 4  收尾
  - /opsx:verify <change>
  - 提示 my-archive
```

---

## 7. 分级重试

审查输出**强制**对每条结论标注 `[BLOCKING]` 或 `[ADVISORY]`。

| 类型 | 处理 |
|---|---|
| `[ADVISORY]` | 记入 backlog，**不阻断**、不触发重试 |
| `[BLOCKING]` 小范围（单文件/单函数） | **复用原 @coder 会话**（传 sessionID）做增量修复 |
| `[BLOCKING]` 方案性（接口/架构不符） | **fresh @coder**（防路径锁定），传原需求 + 契约 + 仓库状态 + 审查反馈 |

判定「小范围 vs 方案性」由主 agent 依据审查报告中的问题定位做，规则写入 SKILL.md。

---

## 8. 角色与边界

| 角色 | 职责 |
|---|---|
| `@simple-architect` | 规划与契约生成（含分级、分组、屏障识别） |
| `@coder` | 实现与修复（复用会话或 fresh） |
| `@reviewer` | spec / quality 审查，输出带 severity |
| `@utility` | 屏障执行（编译+测试）、文档落盘等杂务 |

- 主 agent **直接编排**，不再委托 SDD（SDD 不支持波次并发）。
- 主 agent 只做调度与状态汇总，绝不下场写代码/跑测试。
- 保留术语一致性约束：一律用 `@simple-architect` / `@coder` / `@reviewer`。

---

## 9. 保留 / 废除

**保留**：契约与验收分离、审查阶段隔离、OpenSpec 为真源、Blocked 重启机制、术语一致性。

**废除**：
- 绝对串行（改为波次并发）。
- 无条件 fresh coder（改为分级重试）。
- 逐任务 quality 审查（改为里程碑级）。
- 逐任务全量测试（改为增量 + 里程碑全量）。
- SDD 委托带来的派发者归属模糊。
- `AGENT_*` 角色映射表（不再委托 SDD，映射失去意义）。
- 「验证串行执行」步骤（已被受控并发取代）。

---

## 10. 交付物

1. `~/.agents/skills/my-apply-flow/SKILL.md` — 主技能文件。
2. 如需要，`~/.agents/skills/my-apply-flow/waves.md` — 并发/分组规则参考文件。

---

## 11. 风险与开放问题

- **同包任务仍串行**：kit 的 trae 9 个任务同包，波次加速有限；收益主要来自跨包（buddy vs trae）与审查/验证降本。
- **中间态冲突**：即便包不相交，`go.mod`/`go.sum`、共享依赖包仍可能被多任务同时改 → 已列为强制串行点，但需在规划阶段可靠识别。
- **里程碑 quality 审查的 diff 合并成本**：合并多个任务 diff 后审查，@reviewer 上下文变大；需在 SKILL.md 限定里程碑粒度。
- **并行 @coder 的文件锁/临时产物竞争**：同工作树并发写入需避免共享临时文件。
- **rigor 自动推荐失准**：需允许用户一键覆盖。

---

## 12. 验收标准

- 新技能可完整跑通一个 change：规划 → 波次执行 → 审查 → 验证 → 归档提示。
- 相比 `my-simple-apply`，同类多任务 change 的派发次数显著下降（目标 ≥50%）。
- 无回归：并发波次执行不引入编译/测试假失败。
- 术语一致：全程仅用 `@simple-architect` / `@coder` / `@reviewer`。
- 低优问题不再阻断：advisory 全部进 backlog。
