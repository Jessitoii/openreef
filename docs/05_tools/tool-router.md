# Tool Router

## Purpose
Define the single dispatch boundary for all tool execution paths.

## Scope
In scope:
- tool lookup and schema validation
- permission/confirmation enforcement hooks
- adapter dispatch and normalization handoff

Out of scope:
- tool-specific business logic internals

## Responsibilities
- validate tool id, availability, and argument schema.
- apply permission and confirmation checks before execution.
- dispatch to native, MCP, or skill adapters.
- return normalized `ToolResult` only.

## Core Concepts
- no direct tool execution outside router.
- structured normalization for every success/failure branch.
- correlation ids must persist across request/run/call scopes.
- model-visible callable tools are selected by `ContextAssembler` per turn and
  passed structurally into the model runtime; prompt `[AVAILABLE TOOLS]` text is
  secondary guidance only.

## Core Data Models
### ToolCall
- `callId`, `toolId`, `args`, `requestId`, `runId?`, `sessionKey`, `invokedAt`

### ToolManifest (runtime subset)
- `toolId`, `schema`, `requiredPermissions`, `requiresConfirmation`, `capabilityTags`, `availabilityState`

### Runtime Tool Declaration
- `ToolDefinition.id` is the canonical runtime function name returned by the
  model and routed back through `ToolRouter`.
- `ToolDefinition.argumentSchema` carries the schema used to build SDK tool
  declarations for selected tools.
- native, MCP, and skill-enabled normal router tools share the same declaration
  mapping surface.

### DispatchTrace
- `callId`, `adapterType`, `validationResult`, `policyBranch`, `durationMs`

## State Transitions
`received → validated → policy_checked → approval_gate? → dispatched → normalized_result`

Approval branch:
`approval_gate → pending_approval → approved|rejected|expired`

## Execution Flow
1. Resolve tool manifest.
2. Validate argument schema.
3. Evaluate permission and confirmation requirements.
4. If needed, route through confirmation/mailbox path.
5. Dispatch adapter invocation.
6. Normalize outcome to `ToolResult`.
7. Emit dispatch trace.

## Model Tool Calling Flow
1. `ContextAssembler` selects the turn-specific callable `ToolDefinition` set.
2. `AgentModelAdapter` passes those selected tools structurally alongside the
   rendered prompt.
3. `LiteRtBridge` maps selected definitions to SDK tool declarations and calls
   `createChat(tools: ...)`.
4. SDK function-call responses are parsed into `ToolCall`s.
5. `ToolRouter.dispatch()` remains the only execution boundary.

## Failure Modes
- unknown tool id/unavailable capability → `unavailable`.
- schema mismatch → `validation_error`.
- permission denied/policy blocked → `blocked_by_policy`.
- adapter exception → `execution_error`.
- timeout budget exceeded → `timeout`.

## Constraints
- raw adapter exceptions cannot surface directly to loop.
- router cannot mutate global policy; only enforce it.
- router cannot convert non-terminal approval states into success.

## Invariants
- each `ToolCall` yields exactly one terminal `ToolResult`.
- all `ToolResult`s include originating `callId` and `toolId`.

## Observability
- validation success/failure and reasons
- permission/approval branch chosen
- adapter type and duration
- normalized status distribution by tool

## Related Documents
- [Tool Result Contract](./tool-result-contract.md)
- [Confirmation and Side-Effect Policy](./confirmation-and-side-effect-policy.md)
- [Mailbox and Approval Flow](../03_agent/mailbox-and-approval-flow.md)

## Open Questions
- per-tool timeout override strategy versus global class defaults.
