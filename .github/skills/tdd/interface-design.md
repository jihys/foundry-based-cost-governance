# Interface Design for Testability

Good interfaces make testing natural:

1. **Accept dependencies, don't create them**

   ```typescript
   // Testable
   function processOrder(order, paymentGateway) {}

   // Hard to test
   function processOrder(order) {
     const gateway = new StripeGateway();
   }
   ```

2. **Return results, don't produce side effects**

   ```typescript
   // Testable
   function calculateDiscount(cart): Discount {}

   // Hard to test
   function applyDiscount(cart): void {
     cart.total -= discount;
   }
   ```

3. **Small surface area**
   - Fewer methods = fewer tests needed
   - Fewer params = simpler test setup

## Orchestrator Module Interface Rules

Design module boundaries so tests can exercise behavior through the same public interface production callers use.

1. **Accept upstream decisions as data**

   Deterministic modules should not call LLMs or reinterpret user text. Pass checkpointed interpretation snapshots, memory policies, visible surfaces, authored DAGs, or canonical batches as explicit inputs. Build canonical queries/keys from the checkpointed inputs rather than deriving them from loose session state.

2. **Inject adapters and stores**

   Keep stores, caches, tool connectors, approval gates, and clock/id providers injectable. Unit and integration tests can then use in-memory fakes or scripted adapters without mocking internal collaborators.

3. **Return envelopes, not side-channel state**

   Prefer explicit result objects that include status, warnings, trace references, and output type metadata. Returning a structured envelope avoids callers needing to inspect private state or implicit side-channel fields.

4. **Preserve ownership boundaries**

   A module interface should not ask callers to provide or consume concepts the module does not own. For example, Memory should not accept raw natural-language matching callbacks, and Planner should not receive raw API adapter endpoints.

5. **Make invalid paths hard to call**

   Runtime components should accept only canonical, validated batches rather than raw proposals. Context assembly should receive a planner-facing tool surface representation rather than raw registry entries. Public cache reads should require a public-safe canonical key, not a loose session partial match.
