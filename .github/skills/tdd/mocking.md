# When to Mock

Mock at **system boundaries** only:

- External APIs (payment, email, etc.)
- Databases (sometimes - prefer test DB)
- Time/randomness
- File system (sometimes)

Don't mock:

- Your own classes/modules
- Internal collaborators
- Anything you control

## Orchestrator Detroit vs London Boundary

Use Detroit/classicist TDD inside deterministic modules. Use real code plus in-memory fakes and assert returned results or persisted state.

Detroit fits:

- Deterministic behaviors like canonical query/key building for state queries
- State persistence and read/write ordering semantics
- Privacy sanitization and canonicalization logic
- Surface canonicalization and visibility rules
- Coordination/admission and ready-node calculation
- Canonicalization/normalization of dispatch batches and result envelopes

Use London/mockist TDD only at non-deterministic or external boundaries.

London fits:

- LLM clients
- external commerce APIs
- auth/session providers
- approval freshness gates
- durable workflow/checkpoint stores
- real connector dispatch
- timeout, retry, and network failure behavior

After a mocked boundary returns a validated structured result, pass that result into real deterministic module code. Do not keep mocking internal pure logic just because the upstream source was external.

## Designing for Mockability

At system boundaries, design interfaces that are easy to mock:

**1. Use dependency injection**

Pass external dependencies in rather than creating them internally:

```typescript
// Easy to mock
function processPayment(order, paymentClient) {
  return paymentClient.charge(order.total);
}

// Hard to mock
function processPayment(order) {
  const client = new StripeClient(process.env.STRIPE_KEY);
  return client.charge(order.total);
}
```

**2. Prefer SDK-style interfaces over generic fetchers**

Create specific functions for each external operation instead of one generic function with conditional logic:

```typescript
// GOOD: Each function is independently mockable
const api = {
  getUser: (id) => fetch(`/users/${id}`),
  getOrders: (userId) => fetch(`/users/${userId}/orders`),
  createOrder: (data) => fetch('/orders', { method: 'POST', body: data }),
};

// BAD: Mocking requires conditional logic inside the mock
const api = {
  fetch: (endpoint, options) => fetch(endpoint, options),
};
```

The SDK approach means:
- Each mock returns one specific shape
- No conditional logic in test setup
- Easier to see which endpoints a test exercises
- Type safety per endpoint
