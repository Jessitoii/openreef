# Context Assembly

## Purpose
Define deterministic context compiler pipeline.

## Execution Flow
`plan → retrieve → reduce → render → consume → post_turn_persist`

1. Build `ContextPlan` from mode/policy/source.
2. Retrieve in order: runtime/system blocks, tool exposure, skills, memories, history, standing orders.
3. Reduce in order: stale tool outputs, long history compression, section overage compaction.
4. Render `CompiledContextPackage` with section accounting and audit trace.
5. Loop consumes package.
6. Post-turn memory formation generates write candidates.

## Constraints
- No opaque heuristic-only assembly without audit trace.
- Token budget overruns must fail explicitly after reduction attempts.

## Related Documents
- `docs/04_context-memory/compaction-strategy.md`
- `docs/04_context-memory/memory-write-discipline.md`
