---
name: tdd
description: Test-driven development with red-green-refactor loop. Use when user wants to build features or fixes using TDD, mentions "red-green-refactor", wants integration tests, asks for test-first development, or implements orchestrator modules.
---

# Test-Driven Development

## Philosophy

**Core principle**: Tests should verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't.

**Good tests** are integration-style: they exercise real code paths through public APIs. They describe _what_ the system does, not _how_ it does it. A good test reads like a specification - "user can checkout with valid cart" tells you exactly what capability exists. These tests survive refactors because they don't care about internal structure.

**Bad tests** are coupled to implementation. They mock internal collaborators, test private methods, or verify through external means (like querying a database directly instead of using the interface). The warning sign: your test breaks when you refactor, but behavior hasn't changed. If you rename an internal function and tests fail, those tests were testing implementation, not behavior.

See [tests.md](tests.md) for examples and [mocking.md](mocking.md) for mocking guidelines.

## Anti-Pattern: Horizontal Slices

**DO NOT write all tests first, then all implementation.** This is "horizontal slicing" - treating RED as "write all tests" and GREEN as "write all code."

This produces **crap tests**:

- Tests written in bulk test _imagined_ behavior, not _actual_ behavior
- You end up testing the _shape_ of things (data structures, function signatures) rather than user-facing behavior
- Tests become insensitive to real changes - they pass when behavior breaks, fail when behavior is fine
- You outrun your headlights, committing to test structure before understanding the implementation

**Correct approach**: Vertical slices via tracer bullets. One test → one implementation → repeat. Each test responds to what you learned from the previous cycle. Because you just wrote the code, you know exactly what behavior matters and how to verify it.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
  ...
```

## Workflow

### Entry Points by Work Type

- **New behavior**: RED -> GREEN -> REFACTOR.
- **Bug fix**: reproduction RED -> fix GREEN -> REFACTOR.
- **Refactor**: GREEN baseline -> characterization test if needed -> small refactor -> GREEN -> repeat.

Refactoring does not always start RED. It starts by proving existing behavior is protected, then changing structure while behavior stays green.

### 1. Planning

When exploring the codebase, use the project's domain glossary so that test names and interface vocabulary match the project's language, and respect ADRs in the area you're touching.

Before writing any code:

- [ ] Identify the source spec, root/product PRD, module PRD, and issue for this slice
- [ ] Confirm with user what interface changes are needed
- [ ] Confirm with user which behaviors to test (prioritize)
- [ ] Identify opportunities for [deep modules](deep-modules.md) (small interface, deep implementation)
- [ ] Design interfaces for [testability](interface-design.md)
- [ ] List the behaviors to test (not implementation steps)
- [ ] Get user approval on the plan

Ask: "What should the public interface look like? Which behaviors are most important to test?"

**You can't test everything.** Confirm with the user exactly which behaviors matter most. Focus testing effort on critical paths and complex logic, not every possible edge case.

### 2. Tracer Bullet

Write ONE test that confirms ONE thing about the system:

```
RED:   Write test for first behavior → test fails
GREEN: Write minimal code to pass → test passes
```

This is your tracer bullet - proves the path works end-to-end.

### 3. Incremental Loop

For each remaining behavior:

```
RED:   Write next test → fails
GREEN: Minimal code to pass → passes
```

Rules:

- One test at a time
- Only enough code to pass current test
- Don't anticipate future tests
- Keep tests focused on observable behavior

### 4. Refactor

After all tests pass, look for [refactor candidates](refactoring.md):

- [ ] Extract duplication
- [ ] Deepen modules (move complexity behind simple interfaces)
- [ ] Apply SOLID principles where natural
- [ ] Consider what new code reveals about existing code
- [ ] Run tests after each refactor step

**Never refactor while RED.** Get to GREEN first.

## Orchestrator Module Workflow

Use this workflow when implementing orchestrator modules such as Memory, Tool System, Context Assembly, Planner, Scheduler, Runtime Loop, or Final Output.

### 1. Lock the module boundary

Start from the source-of-truth ladder, then name the module's public interface before writing tests:

```text
spec -> PRD -> module PRD -> issue
```

- **Spec**: architecture and technical source for the module role, runtime handoffs, and system constraints.
- **PRD**: product/runtime invariants inherited by every orchestrator module.
- **Module PRD**: module boundary, public interface, module-owned invariants, and acceptance criteria.
- **Issue**: thin implementation slice for the next observable behavior.

- What this module owns
- What this module explicitly does not own
- Which upstream inputs are already interpreted, validated, or checkpointed
- Which outputs downstream modules may rely on
- Which invariants are inherited from the product/runtime PRD, source spec, ADRs, and `AGENTS.md`

Do not test behavior outside the module boundary. If a behavior belongs upstream or downstream, pass a checkpointed snapshot, structured policy, fake adapter result, or explicit input into the module under test.

### 2. Use contract-first tracer bullets

Use the ladder to choose the next behavior, not to write a batch of tests. Each RED/GREEN cycle should advance one externally observable behavior through the public interface:

1. Contract/model test for stable shapes and invariants.
2. Unit test for deterministic local behavior.
3. Integration test through the real module stack with in-memory collaborators.
4. E2E test for one representative turn-level or workflow-level path, only after the public boundary is green.

Keep the TDD cycle strict: one RED test, one minimal GREEN implementation, refactor only after GREEN, then repeat. Avoid horizontal slices such as "all model tests, then all service code, then all runtime code." The test should respond to what the previous cycle taught you.

### 3. Colocate module-owned tests

Module-owned tests follow the repository's test layout. When no repo-specific layout exists, place them under the module boundary:

```text
<module-package>/tests/
    unit/
    integration/
    e2e/
    support/
```

Cross-module tests belong at the integration boundary that owns the flow, not inside whichever module happens to be edited first.

### 4. Promote discovered contracts

When a RED test clarifies a real contract, update the requirement artifact after the behavior is green:

- Product/runtime PRDs go in the configured PRD location from `docs/agents/issue-tracker.md`.
- Module PRDs are PRD artifacts for a specific module, stored in that same configured PRD location and linked to the source spec.
- Implementation acceptance criteria and follow-up slices go in the configured issue location from `docs/agents/issue-tracker.md`.
- Teammate-facing boundary explanations go in the module spec or progress report.

Tests should focus on public contracts and canonical inputs/outputs for the slice under test.

### Clean Code Refactor Bar

After GREEN, refactor until the code reveals intent, keeps boundaries explicit, and makes the correct behavior the easy path.

Core rules:

- Prefer clear names, small focused units, explicit data flow, and unsurprising control flow.
- Prefer the simplest design that removes real duplication and makes invalid states hard to represent.
- Improve only within the active slice; avoid cleverness, hidden side effects, speculative abstractions, and unrelated refactors.

Functions:

- A function should do one thing at one level of abstraction.
- Name functions after the domain action or decision they perform, not their mechanics.
- Prefer guard clauses over deeply nested conditionals.
- Keep inputs explicit; avoid hidden global state when a parameter or dependency can express the requirement.
- Return domain-shaped results or raise/return explicit errors; avoid ambiguous `None`/sentinel values unless the codebase standardizes them.

```python
# Avoid: mechanics, nesting, and ambiguous return shape.
def handle(user, cart):
    if user and cart and len(cart.items) > 0:
        if user.status == "active":
            return True
    return False

# Prefer: intention, guard clauses, and domain language.
def can_checkout(user: User, cart: Cart) -> bool:
    if not user.is_active:
        return False
    if not cart.items:
        return False
    return True
```

Classes and modules:

- A class/module should own one coherent responsibility and hide details behind a small public interface.
- Prefer composition and small collaborators over inheritance or broad manager classes.
- Keep state private and transitions explicit; expose behavior instead of leaking mutable internals.
- Split a class/module when callers need unrelated subsets of its API, or when changes for different reasons keep landing in the same place.

```python
# Avoid: vague ownership and mixed responsibilities.
class OrderManager:
    def validate(self, order: Order) -> None: ...
    def charge(self, order: Order) -> None: ...
    def send_email(self, order: Order) -> None: ...

# Prefer: explicit boundary and focused collaborators.
class CheckoutService:
    def __init__(self, payments: PaymentGateway, receipts: ReceiptSender) -> None:
        self._payments = payments
        self._receipts = receipts

    def complete(self, order: ValidOrder) -> CheckoutResult:
        payment = self._payments.charge(order.total)
        self._receipts.send(order.customer_email, payment.receipt_id)
        return CheckoutResult(order_id=order.id, receipt_id=payment.receipt_id)
```

## Checklist Per Cycle

```
[ ] Test describes behavior, not implementation
[ ] Test uses public interface only
[ ] Test would survive internal refactor
[ ] Code is minimal for this test
[ ] No speculative features added
```
