# Good and Bad Tests

## Good Tests

**Integration-style**: Test through real interfaces, not mocks of internal parts.

```typescript
// GOOD: Tests observable behavior
test("user can checkout with valid cart", async () => {
  const cart = createCart();
  cart.add(product);
  const result = await checkout(cart, paymentMethod);
  expect(result.status).toBe("confirmed");
});
```

Characteristics:

- Tests behavior users/callers care about
- Uses public API only
- Survives internal refactors
- Describes WHAT, not HOW
- One logical assertion per test

## Orchestrator Module Test Layers

Use these layers for module work:

- **Unit**: pure or near-pure deterministic behavior, such as privacy sanitization, canonical signatures, surface hashing, namespace separation, output type guards, and ready-node selection.
-- **Integration**: the real module stack with in-memory collaborators, such as a state persistence boundary with an in-memory store/cache, or an orchestrated dispatch stack that exposes a visible surface and can accept simulated prior outputs.
- **E2E**: one representative turn-level or workflow-level path after the public module boundary is green.

Module PRDs and issues may list many acceptance criteria. Treat them as a backlog of behaviors, then implement one tracer bullet at a time: one failing behavior test, minimal code to pass it, refactor after green, repeat.

For refactors, characterization tests describe existing observable behavior; new behavior tests describe intended behavior that does not exist yet.

Examples of good orchestrator module tests (phrased generically):

-- Canonical state-query keys are consistently produced for the same checkpointed snapshot regardless of mapping order.
-- A state persistence boundary persists provenance references in the documented ordering (e.g., plan-slot order) rather than relying on execution completion order.
-- A surface-filtering boundary hides internal/observation-only tools from the planner-facing surface.
-- A coordination/admission boundary rejects planner-authored nodes that are not present in the visible surface.
-- A dispatch boundary rejects invalid, uncanonicalized batches before connector dispatch.
- Result envelopes preserve declared output types and metadata; observation-type outputs are handled according to evidence/admission policy and are not treated as accepted customer evidence until admitted.

Avoid tests that assert private helper names, collaborator call counts, or raw implementation storage shape unless that storage shape is the documented public contract.

## Bad Tests

**Implementation-detail tests**: Coupled to internal structure.

```typescript
// BAD: Tests implementation details
test("checkout calls paymentService.process", async () => {
  const mockPayment = jest.mock(paymentService);
  await checkout(cart, payment);
  expect(mockPayment.process).toHaveBeenCalledWith(cart.total);
});
```

Red flags:

- Mocking internal collaborators
- Testing private methods
- Asserting on call counts/order
- Test breaks when refactoring without behavior change
- Test name describes HOW not WHAT
- Verifying through external means instead of interface

```typescript
// BAD: Bypasses interface to verify
test("createUser saves to database", async () => {
  await createUser({ name: "Alice" });
  const row = await db.query("SELECT * FROM users WHERE name = ?", ["Alice"]);
  expect(row).toBeDefined();
});

// GOOD: Verifies through interface
test("createUser makes user retrievable", async () => {
  const user = await createUser({ name: "Alice" });
  const retrieved = await getUser(user.id);
  expect(retrieved.name).toBe("Alice");
});
```
