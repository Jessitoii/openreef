# ADR-010: Normalized ToolResult Contract

## Status
Accepted

## Context
Inconsistent tool result shapes make continuation logic, persistence, and observability brittle.

## Decision
Use a normalized closed-status `ToolResult` contract for all tool outcomes.

## Rationale
Standardized statuses (`success`, `rejected`, `validation_error`, `execution_error`, `timeout`, `unavailable`, `blocked_by_policy`) enable deterministic loop and policy behavior.

## Consequences
- Non-success reasons must remain structured and visible.
- Adapter-specific errors are mapped into normalized categories.

## Alternatives Considered
- Adapter-specific freeform result shapes.

## Related Documents
- [Tool Result Contract](../05_tools/tool-result-contract.md)
- [Tool Router](../05_tools/tool-router.md)
