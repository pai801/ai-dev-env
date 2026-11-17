---
name: my-contracts
description: Use when you have a spec or requirements for a multi-step task, before touching code.
  Outputs architectural contracts at one of three rigor tiers (light / standard / strict),
  selected by the caller. light = source→target map + equivalence assertions; standard =
  interface signatures + data structures + complexity classification, no TDD; strict =
  adds test contracts and requires RED-GREEN-REFACTOR TDD. Never outputs implementation bodies.
---

# My Contracts

## Overview

Write **architectural contracts** assuming the engineer is skilled but needs clear boundaries. Document everything they need to know: which files to touch, what the public interface looks like, what data structures are involved, and — at the strict tier — what tests must pass. **Never** give them the implementation body.

The depth of the contract is controlled by a single input: the **rigor tier** (`light` / `standard` / `strict`) selected by the caller for each task. The tier changes how thick the contract is. It never changes the fact that this skill writes contracts, not code.

**Announce at start:** "I'm using the my-contracts skill to create the architectural contract."

**Context:** If working in an isolated worktree, it should have been created via the `superpowers:using-git-worktrees` skill at execution time.

**Save contracts to:** `docs/contracts/YYYY-MM-DD-<feature-name>.md`
- (User preferences for contract location override this default)

## Rigor Tiers

rigor is chosen **per task by the caller** — the main agent decides the tier and passes it to `@architecter`, which loads this skill at that tier. The tier is never inferred from an agent name, and the same `@architecter` produces all three tiers. `@architecter` may output a **tier suggestion** per task (see the rules below), but the caller's tier is authoritative.

| Rigor | Contract depth | TDD | Applies to |
|-------|----------------|-----|------------|
| **light** | Source → Target file map + equivalence assertions | No | Mechanical migration / refactor / move |
| **standard** | Interface signatures + docstrings, data structures, complexity classification, implementation steps; **no test contract** | No | General feature development |
| **strict** | Interface signatures + docstrings, data structures, **test contracts**, no implementation bodies | **Yes** (RED → GREEN → REFACTOR) | Greenfield / high-risk / new interfaces |

**Tier suggestion rules (for the per-task tier suggestion):**
- **light** — a purely mechanical change: moving/renaming files, extracting a module, relocating code between layers, or porting with no intended behavior change. No new public interface and no new behavior.
- **standard** — new or changed behavior behind a clear interface, moderate risk, where existing or affected tests can validate the result.
- **strict** — greenfield modules, new public interfaces, or any high-risk surface (payments, auth, data mutation, database schema, API compatibility), or whenever correctness must be proven by a written test contract.
- **Default to `standard` when uncertain.**
- **Any task with a high-risk characteristic becomes `strict`**, even if it looks small.
- Record the reason for every tier choice so the caller can verify it.

**A missing tier blocks everything.** If the caller has not supplied a rigor tier, stop and ask — never guess, and do not produce a contract or hand off for dispatch.

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate contracts — one per subsystem. Each contract should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure — but if a file you're modifying has grown unwieldy, including a split in the contract is reasonable.

**Scan for indirectly affected files.** The file list covers not only the
files whose code changes, but every file whose *assertions* change as a
consequence: registration/enumeration snapshot tests, global count/order
assertions, descriptor manifests, route tables. When a task adds a new
registration (a channel, plugin, handler, enum member), the project's
snapshot tests are expected to change — list them explicitly. A contract
that omits them stalls at implementation time.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Gate Tasks

A **gate** is a precondition that must be proven before any coding wave
starts — a credential, an environment capability, an external service's
reachability, a signed-in session, a feature flag.

Every contract MUST surface its gates as explicit tasks, each with a
verifiable command and an expected result. Gates are verified first,
before any coding work.

- A gate task has no implementation body — its deliverable is evidence.
- If a gate cannot be expressed as a verifiable command, that is a
  **contract defect**: stop and return the contract to the caller rather
  than writing the rest of it on an unproven premise.
- Never write "assume the credential works", "proceed on the recommended
  path", or any other substitute for gate evidence.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes).** One contract field per step — a file mapping, an interface signature, a data structure, or a test contract — never a whole task in a single step.

## Contract Document Header

**Every contract MUST start with this header:**

````markdown
# [Feature Name] Architectural Contract

**Rigor:** [light | standard | strict]

> **CRITICAL:** This document defines contracts only. Implementation bodies must be derived by the implementer. Do NOT copy code from this contract as implementation.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
````

## Complexity Classification

Every task MUST be classified by complexity:

- **Simple**: Straightforward logic, no external dependencies, single responsibility, can be implemented in 10-20 minutes. Max 3-5 simple tasks can be batched together if they belong to the same module and have no inter-dependencies.
- **Standard**: Moderate complexity, may involve 1-2 dependencies, requires focused attention, 20-40 minutes.
- **Complex**: High complexity, multiple dependencies, cross-module coordination, algorithmic challenges, or high risk. Must be implemented individually with full context.

**Classification rules:**
- Default to `standard` if uncertain.
- A task with ANY high-risk characteristic automatically becomes `complex`.
- Simple tasks in the same module with sequential dependencies may share the same `batch-id`. The strict tier records the `batch-id` explicitly on each task.
- Tasks at the `light` tier are mechanical by definition and are normally `simple`.

## Task Structure

Every task uses the same skeleton. The fields that follow `**Files:**` depend on the tier:

| Tier | Fields (in addition to `Files`) |
|------|---------------------------------|
| **light** | Source → Target Map, Equivalence Assertions |
| **standard** | Interface Contract, Data Structure Contract, Implementation Steps |
| **strict** | Interface Contract, Data Structure Contract, Test Contract |

### Task N: [Component Name]

**light tier template:**

````markdown
### Task N: [Component Name]

**Complexity:** simple

**Files:**
- Move: `src/old.py` → `src/new.py`
- Modify: `src/caller.py:12-30`

**Source → Target Map:**

| Source | Target | Notes |
|--------|--------|-------|
| `src/old.py` | `src/new.py` | [what moves verbatim; what is renamed or re-exported] |
| `src/caller.py:12-30` | `src/caller.py:12-30` | [import path updated to the new target] |

**Equivalence Assertions:**
- [ ] Behavior: [observable behavior that must be identical before and after]
- [ ] Verify: `<command>`
- [ ] Behavior: [another observable behavior that must be unchanged]
- [ ] Verify: `<command>`
````

The Source → Target Map is exhaustive: every touched source path appears exactly once with its target. Equivalence Assertions are the light tier's replacement for tests — each one names a behavior that must not change and a command that demonstrates it (a test command, a build, an API/snapshot diff). The light tier produces **no interface contract and no test contract**, and requires **no TDD**.

**standard tier template:**

````markdown
### Task N: [Component Name]

**Complexity:** [simple | standard | complex]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`

**Interface Contract:**

```python
def function_name(param: ParamType) -> ReturnType:
    """
    [Detailed description of what this function does]

    Args:
        param: [Description and constraints]

    Returns:
        [Description of return value]

    Raises:
        [Exception types and when they are raised]

    Examples:
        >>> function_name(sample_input)
        expected_output
    """
    pass  # Implementation to be filled by implementer
```

**Data Structure Contract:**

```python
class DataModel:
    """
    [Description of this data structure]

    Attributes:
        field: Type  # [Description and constraints]
    """
    field: Type
```

**Implementation Steps:**
- [ ] **Step 1: Review interface and data structure contracts**
- [ ] **Step 2: Implement the function body** (engineer chooses algorithm and approach)
- [ ] **Step 3: Verify the implementation matches the signature and docstring**
````

**strict tier template:**

````markdown
### Task N: [Component Name]

**Batch:** [batch-id] | **Complexity:** simple | standard | complex

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Interface Contract:**

```python
def process_payment(amount: Decimal, currency: str) -> PaymentResult:
    """Process payment. amount > 0, currency is ISO 4217 code."""
    ...  # IMPLEMENTATION: Derive through TDD. Do NOT write implementation here.
```

**Data Structure Contract:**

```python
class PaymentResult:
    """Payment processing outcome."""
    transaction_id: str  # Unique UUID
    status: PaymentStatus  # PENDING | COMPLETED | FAILED
```

**Test Contract:**

```python
def test_process_payment_success():
    # G: amount=100.00, currency="USD" | W: process_payment | T: returns PaymentResult with status=COMPLETED
    result = process_payment(Decimal("100.00"), "USD")
    assert result.status == PaymentStatus.COMPLETED

def test_process_payment_rejects_negative_amount():
    # G: amount=-10.00 | W: process_payment | T: raises ValueError
    with pytest.raises(ValueError):
        process_payment(Decimal("-10.00"), "USD")
```

**TDD Cycle:** RED → GREEN → REFACTOR
````

**Docstring style (part of the Interface Contract field):**
- **standard** — full `Args` / `Returns` / `Raises` sections. Document every parameter, return value, and raised exception, plus a usage example for non-trivial functions.
- **strict** — concise, one line only. Type annotations and the test contract carry the rest. Constraints follow the period, comma-separated (e.g. `amount > 0, currency is ISO 4217 code`). No `Args`/`Returns`/`Raises` sections. Exception detail only when non-obvious.

## Comment Rules

Comments must follow these rules:

**Docstring comments (required for all public interfaces):**
- Must describe what the function does, not how it does it
- Must document all parameters, return values, and exceptions
- Must include usage examples for non-trivial functions
- Verbosity follows the tier — see Docstring style in Task Structure

**Inline comments (required for complex logic):**
- Explain "why", not "what"
- Mark workarounds, hacks, or non-obvious decisions
- Keep comments close to the code they describe

**Code structure comments:**
- Use module-level docstrings to explain file responsibility
- Use class docstrings to explain the role of the class
- Use section headers (e.g., `# --- Private Helpers ---`) for long files

## Test Contract Limits (strict tier only)

Test contract count is tiered by task complexity:

| Task Type | Test Contracts | Coverage |
|-----------|----------------|----------|
| **simple** | 0–1 | Happy path only (or none for pure data structures) |
| **standard** | 1–2 | Happy path + boundary case |
| **complex** | 1–3 | Happy path + boundary case + error case |

**Rules:**
- **simple**: Pure type definitions, getters, or trivial pass-throughs may need 0 tests. One happy path is enough if behavior is non-trivial.
- **standard**: At minimum 1 happy path. Add 1 boundary case if the interface has meaningful edges (empty input, zero, null, type coercion).
- **complex**: At minimum 1 happy path. Boundary and error cases are strongly recommended; all 3 are required if the interface handles critical paths (payments, auth, data mutation).

**If more than the tier maximum is genuinely needed**, add a comment with rationale:
```python
# 3 tests: state machine with 3 valid transitions (see spec REQ-7)
```

**Never write exhaustive test matrices in the contract** — boundary discovery is the implementer's job during TDD.

Test contract comments use the **G|W|T format only** — no full sentences, no Given/When/Then labels:
```python
def test_name():
    # G: [preconditions] | W: [action] | T: [expected outcome]
```

## The Iron Rule: No Implementation Bodies

**Every step must contain only contracts — never implementation logic.** These are **contract failures** — never write them:

- Function bodies with logic (`return`, `for`, `if`, `while`, `try`, `with`, `async`, etc.)
- Algorithm details, internal state machines, caching strategies
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases" (without a test contract)
- "Write tests for the above" (without an actual test contract)
- "Similar to Task N" (repeat the contract — the implementer may be reading tasks out of order)
- References to types, functions, or methods not defined in any task

This section is retained in full. The placeholder restriction below takes effect **only at the strict tier**; the `light` and `standard` tiers use the `pass` placeholder.

**Valid placeholder bodies by tier:**
- **light / standard:** `pass  # Implementation to be filled by implementer` is the only valid function body.
- **strict:** `...` or `# IMPLEMENTATION: ...` is the only valid function body. `pass  # ...` is **NOT** allowed at the strict tier — the implementer must derive the body through RED-GREEN-REFACTOR TDD.

**Strict tier TDD cycle (inline):**
- **RED** — write the failing test from the test contract first, run it, and capture the failure output as evidence.
- **GREEN** — write the minimal implementation that makes the test pass, run it, and capture the passing output as evidence.
- **REFACTOR** — clean up without changing behavior, then re-run the tests and capture the still-passing output.

**Evidence is persisted, not narrated.** Each Unit's strict evidence goes to
`docs/evidence/<unit-id>-red-green.md` — per task, the exact command and its
captured output for RED, GREEN, and the post-REFACTOR re-run. A reviewer
must be able to replay the commands and see the same results. Evidence that
exists only in a chat reply is not evidence.

**RED that cannot fail.** When a task overrides or extends an already-working
base, some test contracts may pass before any new code is written. Mark those
`# already-satisfied by <base>` and keep the genuinely failing ones as the RED
set. An honest partial RED is correct; fabricating a failure is not.

## Self-Review

After writing the complete contract, look at the spec with fresh eyes and check the contract against it. This is a checklist you run yourself — not a subagent dispatch.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that defines its interface, data structure, or — at the light tier — its source → target mapping and equivalence assertions? List any gaps.

**2. Type consistency:** Do the types, method signatures, and property names you used in later tasks match what you defined in earlier tasks? A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

**3. Completeness check:** Are all file paths exact? Are all interface signatures complete with type annotations and docstrings? Are all data structures defined with their fields? Is every task classified with a complexity level? Do the file lists include the indirectly affected snapshot/registration tests?

**4. Complexity classification check:** Are simple tasks truly simple (no cross-module deps, straightforward logic)? Are complex tasks properly isolated (not batched)?

**5. Gate coverage:** Does every gate have a verifiable command and an expected result? No unverifiable premise survives into the contract.

**Strict tier — additional checks:**

**6. Implementation body scan:** Search your contract for red flags — any function body that contains logic instead of `...`. Fix them.

**7. Test completeness:** Does every interface that needs a test contract have one, within its tier maximum, in G|W|T format? Are docstrings concise (one line)?

**8. Placeholder scan:** Search for "TBD", "TODO", "implement later", "fill in details". Contracts must be complete. Fix them.

**9. Test contract count:** Does any interface exceed its tier maximum without rationale? simple tasks should not have >1, standard not >2, complex not >3.

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Execution Handoff

After saving the contract, report to the invoking agent:

```
Contract complete and saved to `docs/contracts/<feature-name>.md`.
Total tasks: [N]
Complexity breakdown: [X simple, Y standard, Z complex]
Rigor used: [light | standard | strict]
Self-review: All checks passed.
Ready for implementation.
```
