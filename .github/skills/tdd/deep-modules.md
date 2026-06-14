# Deep Modules

From "A Philosophy of Software Design":

**Deep module** = small interface + lots of implementation

```
┌─────────────────────┐
│   Small Interface   │  ← Few methods, simple params
├─────────────────────┤
│                     │
│                     │
│  Deep Implementation│  ← Complex logic hidden
│                     │
│                     │
└─────────────────────┘
```

**Shallow module** = large interface + little implementation (avoid)

```
┌─────────────────────────────────┐
│       Large Interface           │  ← Many methods, complex params
├─────────────────────────────────┤
│  Thin Implementation            │  ← Just passes through
└─────────────────────────────────┘
```

When designing interfaces, ask:

- Can I reduce the number of methods?
- Can I simplify the parameters?
- Can I hide more complexity inside?

## Orchestrator Deep Modules

For orchestrator module work, a module is deep when callers get a stable, narrow public interface while the module hides policy enforcement, canonicalization, ordering, validation, trace, or replay details inside it.

Use the deletion test:

- If deleting the module makes complexity vanish, it was probably shallow.
- If deleting the module spreads the same rules across Context Assembly, Planner, Scheduler, Runtime, and Final Output, the module is earning its keep.

Good deep module candidates (described generically):

- A query/key-canonicalization boundary: callers provide checkpointed interpretation and policy; the boundary hides canonicalization, sanitization, signature/key rules, and public-cache-key formation.
- A state persistence boundary: callers read/write committed turn state; the boundary hides isolation hashing, plan-slot ordering, cache status, warnings, and safe payload handling.
- A surface-filtering boundary: callers request a planner-visible surface; the boundary hides raw registry details, feature/integration gating, prompt-time filtering, and surface hashing.
- A coordination/admission boundary: callers provide an authored task/DAG; the boundary hides admission logic, ready-node calculation, input binding, batch splitting, and canonical batch creation.
- A dispatch boundary: callers hand canonical, validated batches to be executed; the boundary hides dispatch-time validation, connector calls, and result normalization/envelope creation.

Shallow warning signs:

- A module only forwards fields from one DTO to another.
- Callers must know internal registry, adapter, cache, or trace formats to use it correctly.
- Safety rules are repeated in multiple callers instead of enforced once inside the module.
- The public interface exposes implementation choices such as raw endpoints, headers, connector objects, or private helper names.
