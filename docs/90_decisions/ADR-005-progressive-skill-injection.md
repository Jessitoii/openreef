# ADR-005: Progressive Skill Injection by Relevance and Budget

## Status
Accepted

## Context
Injecting all skills into every run causes context overload and weakens determinism.

## Decision
Inject only relevant enabled skills per turn, bounded by context budget and policy constraints.

## Rationale
Progressive, selective injection preserves context budget and reduces irrelevant tool/action exposure.

## Consequences
- Activation decisions must be explicit (`activated` or skipped with reason).
- Skill injection remains bounded and policy-aware.

## Alternatives Considered
- Always-on full skill injection.

## Related Documents
- [Skills Overview](../07_skills/skills-overview.md)
- [Skill Lifecycle](../07_skills/skill-lifecycle.md)
- [Context Assembly](../04_context-memory/context-assembly.md)
