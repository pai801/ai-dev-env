---
name: my-apply
description: Use when implementing an OpenSpec change or a multi-task plan with @coder/@reviewer subagents — especially when task count is high, when throughput matters, or when a prior apply run was too slow.
---

# my-apply — Wave-Based Implementation Orchestration

## Overview

Orchestrate implementation of an OpenSpec change or multi-task plan by dispatching `@coder` and `@reviewer` subagents in **waves**, not one task at a time.

**Core principle:** serialize at the **wave**, not the task. Tasks that touch disjoint packages run in parallel; only true conflicts (same package, shared files, cross-package symbol dependencies) force serialization. The main agent never writes code and never runs tests or builds — but it does read (git status/diff, grep, file reads, `openspec status`) to compute isolation groups and gate checks.

**Cost model (why this exists):** dispatch count dominates wall-clock time. Per-task double review, per-task full test runs, and unconditional fresh-coder retries multiply cost by the task count. This skill cuts cost on four axes: wave parallelism, milestone-level quality review, incremental verification, and severity-graded retries.

## When to Use

- Implementing an OpenSpec change with many tasks, or any multi-task plan.
- When a previous apply run was serial and slow.
- When tasks span multiple packages/modules.

**When NOT to use:** single-task changes (just dispatch one `@coder`), or when `@coder`/`@reviewer` subagents are not configured.

## The Two Knobs

### rigor — how heavy the contract is

| rigor | Use for | Contract | TDD |
|---|---|---|---|
| light | mechanical migration / refactor / move | `my-contracts`（light 档） | no |
| standard | ordinary feature work | `my-contracts`（standard 档） | no |
| strict | greenfield / high risk / new interfaces | `my-contracts`（strict 档） | yes |

Recommend a rigor from the change type; let the user override. `rigor` is an input parameter to `my-contracts`, not a skill or agent selector.

### concurrency — how wide the waves are

| concurrency | Isolation unit | Behavior |
|---|---|---|
| serial | — | one task per wave (safety fallback) |
| pkg (default) | Go package / module | different packages in parallel, same package serial |
| auto | planner-decided | Phase 0 computes groups and waves |

## Core Model

- **Task** — one entry in `tasks.md` (OpenSpec remains the source of truth).
- **Unit** — a group of tasks in the **same package** with disjoint files and no symbol dependency, given to one `@coder`.
- **Wave** — a set of Units whose packages are mutually disjoint. **Units in a wave run in parallel; waves run serially.**
- **Barrier** — the join point ending a wave: compile + affected-package tests. No Unit starts until the previous wave's Barrier passes.

Serialization granularity moves from "task" to "wave": N tasks collapse to roughly the number of phases.

## Execution Flow

```
Phase 0  Plan (once)
  @architecter produces:
    ① per-task file list — direct changes AND indirectly affected files
       (registration/enumeration snapshot tests, count/order assertions)
    ② complexity class (simple/standard/complex)
    ③ rigor per task + that tier's contract
       (strict also delivers a test contract)
    ④ gate tasks — every precondition that must be proven before coding
       (credentials, environment, external reachability), each with a
       verifiable command and an expected result
  Main agent computes independently:
    ⑤ isolation groups + serialization barriers, derived from ①'s
       file/symbol overlaps and dependencies
  Main agent validates independently:
    - no file/symbol overlap within a group
    - every task classified
    - every spec requirement maps to a task
    - rigor tier consistency and coverage
    - every gate task has a command that can be run NOW
  Fail → send back to @architecter

  GATE RULE (hard): no coding wave starts until every gate task has
  recorded evidence. A gate that cannot be verified is a contract
  defect — stop, or run a minimal spike task first. Never proceed on
  an unverified premise, and never accept "assume it works" or
  "proceed on the recommended path" as a substitute for evidence.
  Gate evidence is produced by @utility (command + captured output) and
  persisted to docs/evidence/gates-<change-or-batch>.md; the main agent
  verifies the file exists and the expected result is present.

Phase 1  Wave execution
  for each wave:
    - dispatch N @coder concurrently (background), packages disjoint;
      state each task's rigor and contract explicitly
    - light: run the equivalence assertions
    - standard: implement the interface/data structures and run the
      affected tests
    - strict: write the failing test first, capture RED output; implement
      to pass, capture GREEN output; REFACTOR, capture the re-run — all
      three persisted to the Unit evidence file (see Evidence)
    - tiers within the same Unit are verified item by item; strict
      must not be skipped by another tier
    - join all → Barrier: compile + affected-package tests (@utility)
    - re-run the Barrier after any fix that changes production files;
      pure test additions do not require a re-run

Phase 2  Review
  - spec review: per task by default. Homogeneous light tasks in the same
    wave may be merged into ONE reviewer dispatch, but it must check every
    task's equivalence assertions individually — merging is a dispatch
    optimization, never a sampling shortcut. A merged dispatch must still
    emit one verdict line per task. Strict tasks are always
    reviewed per task.
  - quality review: once per milestone (merged diff)
  - missing evidence (including a missing strict evidence file) → block
    the next wave and rework

Phase 3  Verify
  - task level: affected-package tests
  - milestone level: full regression

Phase 4  Close
  - OpenSpec change: run `/opsx:verify <change>` if that command exists;
    otherwise fall back to `openspec validate --strict <change>` +
    `openspec status <change>` + a spec→task coverage count.
  - Ad-hoc batch (no OpenSpec change): dispatch `@finaler` as the delivery
    gate, then prompt the user for the commit/archive decision. Never force
    an OpenSpec verification step onto a batch that has none.
  - OpenSpec changes only: prompt my-archive
```

## Isolation Rules (the only hard constraints)

These are correctness, not process overhead. Violating them produces false test failures or broken builds.

- **Same package ⇒ serial.** Go compiles per package; one writer's intermediate syntax error makes another's `go test ./pkg` fail spuriously. Group same-package tasks into one Unit.
- **One writer per shared file.** If two tasks touch the same file (e.g. `registry.go`, `adaptor.go`), serialize them — preferably into the same Unit so one coder applies both edits.
- **Cross-package symbol dependency ⇒ order.** If Task B calls a symbol Task A introduces, B goes in a later wave than A.
- **Shared dependency package ⇒ serialize.** Tasks modifying a common imported package (`go.mod`, a shared internal package) must not run concurrently.

Everything else runs in parallel.

## Review and Severity

- **spec review — per task by default.** Homogeneous light tasks in the same wave may merge into one dispatch (one verdict line per task); strict is always per task. Cheap; verifies the interface/requirement is met.
- **quality review — per milestone.** Merge the milestone's diff and review once. Keep the milestone bounded; do not stretch it across the whole change.

Every review finding MUST be tagged:

- `[BLOCKING]` — must be fixed before the task/milestone is done.
- `[ADVISORY]` — recorded to a backlog, **never blocks**, never triggers a retry.

**Advisory backlog carrier:** one file per change/batch, written by the main agent — `openspec/changes/<change>/ADVISORY_BACKLOG.md` for an OpenSpec change, `docs/<batch>-advisory-backlog.md` for an ad-hoc batch. Advisories live there, not scattered across reviewer reports.

Review phases stay isolated: spec review outputs no code-quality opinions; quality review outputs no completeness opinions. The two-stage separation is retained — only its granularity changed.

## Retry (severity-graded)

| Finding | Action |
|---|---|
| `[ADVISORY]` | append to backlog; continue |
| `[BLOCKING]`, small (single file/function) | **reuse the same @coder session** (pass sessionID) for an incremental fix |
| `[BLOCKING]`, structural (interface/architecture mismatch) | **fresh @coder** — pass original requirements, contract, current repo state, and reviewer feedback |

The main agent classifies small-vs-structural from the finding's location. Fresh coder is for path-lock-in risk only; it is not the default.

## Verification

- **Task level:** run only the affected package(s): `go test ./<affected-pkg>/...`.
- **Milestone level:** one full regression run at each milestone boundary.
- Never run the full suite per task.

## Evidence (strict tier)

Strict-tier TDD evidence is **persisted, not narrated**. Each Unit that
contains strict tasks writes:

`docs/evidence/<unit-id>-red-green.md`

with, per task: the exact command and captured output for RED (failing),
GREEN (passing), and the post-REFACTOR re-run (still passing). The spec
reviewer reads this file and may replay the commands; it never re-derives
RED from scratch. A missing file, or commands that do not replay, is a
`[BLOCKING]` evidence gap.

Evidence that exists only inside a coder's chat reply is not evidence —
replies do not survive the session.

## Roles

| Role | Responsibility |
|---|---|
| `@architecter` | Phase 0 per-task contracts (file list, complexity, rigor recommendation, and each tier's contract; no waves/barriers, no implementation bodies) |
| `@coder` | implementation and fixes (reused or fresh session) |
| `@reviewer` | spec/quality review, output tagged with severity |
| `@utility` | Barrier execution (compile + tests), file writes |

- The main agent orchestrates directly; do **not** delegate the loop to SDD (it cannot express wave parallelism).
- The main agent only schedules and aggregates state; it never writes code and never runs tests or builds. Read-only exploration (git status/diff, grep, file reads, `openspec status`) is part of its job — isolation groups, gate checks, and the advisory backlog depend on it.
- Terminology: always `@architecter` / `@coder` / `@reviewer` / `@utility`.

## Red Flags — stop and re-check

- Dispatching one task at a time out of habit → recompute waves.
- Two concurrent `@coder`s touch the same package or shared file → serialize them.
- A review finding has no `[BLOCKING]`/`[ADVISORY]` tag → malformed; re-request.
- About to start a fresh `@coder` for a one-line fix → reuse the session instead.
- About to run the full suite for a single task → run only the affected package.
- An `[ADVISORY]` finding is blocking a task → move it to the backlog.
- Letting `@architecter` produce isolation groups or barriers → the main agent computes ⑤ itself.
- About to start a coding wave while a gate task has no evidence → stop; the gate is a contract defect.
- Accepting a strict task with no evidence file because the coder's reply describes RED/GREEN → not evidence; request the file.

## Quick Reference

| Decision | Rule |
|---|---|
| Parallel unit | package |
| Wave width | number of disjoint packages available |
| Join | Barrier: compile + affected-package tests |
| spec review | per task; homogeneous light may merge into one dispatch (one verdict line per task), never sample |
| quality review | per milestone |
| test scope | affected package per task; full at milestone |
| small blocking fix | reuse @coder session |
| structural blocking fix | fresh @coder |
| advisory | backlog, never blocks |
| gate | no coding wave until every gate has recorded evidence |
| strict evidence | `docs/evidence/<unit-id>-red-green.md` per Unit |
| advisory carrier | `ADVISORY_BACKLOG.md` (change) / `docs/<batch>-advisory-backlog.md` |
| close | `/opsx:verify` if present, else `openspec validate --strict`; ad-hoc → @finaler |
| main agent commands | read-only OK; never writes code, never runs tests/builds |
| loop owner | main agent (not SDD) |
