# ADR-001: Unified Execution Model

## Status
Accepted

## Context
OpenReef had lifecycle ambiguity across chat, triggers, and resume behavior, with risk of prompt-driven mode drift and inconsistent runtime legality.

## Decision
Adopt one unified execution model centered on `ExecutionRequest → Executor → AgentLoop → ToolRouter → ExecutionResult`, with explicit request modes and executor-owned lifecycle legality.

## Rationale
A single lifecycle model enables consistent policy enforcement, terminal-state semantics, and observability across all execution sources.

## Consequences
- One executor and one shared loop become non-negotiable architecture constraints.
- Lifecycle mode transitions must be explicit and validated.
- UI projection consumes structured terminal results, not inferred prompt outcomes.

## Alternatives Considered
- Separate runtime paths by source (chat vs trigger vs resume).
- Prompt-only lifecycle inference inside loop prompts.

## Related Documents
- [Execution Model](../02_system/execution-model.md)
- [Execution Policy](../02_system/execution-policy.md)
- [Unified Execution Model](../unified-execution-model.md)

## Notes
This ADR is the root decision for downstream execution and policy ADRs.
