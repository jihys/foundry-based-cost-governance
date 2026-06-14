# Refactor Candidates

Refactoring is behavior-preserving structural change. Start from GREEN: prove the current public behavior is protected before changing internals.

If current behavior is not protected, add characterization tests through public interfaces first. These tests lock observable behavior, not private helpers, collaborator call counts, or the current internal shape.

Make one small structural change at a time, then run focused tests. If the intended behavior changes, stop treating the work as refactoring and create a new behavior or bug-fix TDD slice.

For orchestrator modules, good refactor slices include splitting state persistence internals, extracting coordination ready-node logic, or separating dispatch validation from connector dispatch while keeping public behavior stable.

After TDD cycle, look for:

- **Duplication** → Extract function/class
- **Long methods** → Break into private helpers (keep tests on public interface)
- **Shallow modules** → Combine or deepen
- **Feature envy** → Move logic to where data lives
- **Primitive obsession** → Introduce value objects
- **Existing code** the new code reveals as problematic
