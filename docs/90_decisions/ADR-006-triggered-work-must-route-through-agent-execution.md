# ADR-006: Triggered Work Must Route Through Agent Execution

## Status
Accepted

## Context
Automation triggers can diverge into ad hoc execution paths, creating inconsistent behavior relative to chat execution.

## Decision
All trigger-originated work must normalize into `triggered_request` and execute through the same executor/loop/router stack.

## Rationale
A shared runtime path preserves policy consistency, observability, and terminal-state semantics.

## Consequences
- Trigger pipelines perform normalization/arbitration only; they do not bypass executor.
- Trigger conflict handling is policy-driven and explicit.

## Alternatives Considered
- Trigger-local standalone action executors.

## Related Documents
- [Trigger Lifecycle](../06_triggers-automation/trigger-lifecycle.md)
- [Execution Model](../02_system/execution-model.md)
