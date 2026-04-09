# Tool Router

## Purpose
Define single dispatch path and enforcement sequence.

## Execution Flow
1. Validate tool id and availability.
2. Validate args against schema.
3. Enforce permission and policy checks.
4. Route confirmation-required calls to approval boundary.
5. Dispatch to native/MCP/skill adapter.
6. Normalize adapter output into `ToolResult`.

## Constraints
- No tool execution outside router.
- No raw exception propagation to loop.
- Router must preserve correlation ids (`requestId`, `runId`, `callId`).

## Related Documents
- [Confirmation and Side-Effect Policy](./confirmation-and-side-effect-policy.md)
- [Tool Result Contract](./tool-result-contract.md)
- [Mailbox and Approval Flow](../03_agent/mailbox-and-approval-flow.md)
