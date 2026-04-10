# Agent Loop

## Purpose
Define bounded loop execution semantics for planning, tool usage, and terminal action requests.

## Scope
In scope:
- step lifecycle
- action selection and execution ordering
- continuation/termination rules
- blocked-progress handling

Out of scope:
- mode classification
- policy authoring
- persistence backend operations

## Responsibilities
Loop may:
- plan and select allowed actions
- request tool calls through router only
- request persistence/suspend/finalization through executor boundary

Loop may not:
- reclassify lifecycle mode
- bypass policy/approval/router controls
- commit run transitions directly

## Core Concepts
- **bounded autonomy**: loop decides next action within strict limits.
- **progress requirement**: repeated no-progress signatures force freeze/fail path.
- **structured terminal intent**: loop emits finish/fail/suspend requests, executor enforces legality.

## Core Data Models
- `LoopAction`: `respond|tool_call|structured_llm_step|persist_state_request|suspend_request|finish_request|fail_request`
- `LoopStepRecord`: `stepIndex`, `actionType`, `decisionReason`, `actionOutcome`, `toolCallRef?`, `tokenUsage?`, `timestamp`
- `LoopControl`: `maxSteps`, `maxToolCalls`, `timeoutMs`, `blockedFingerprintLimit`

## State Transitions
Loop-local phases:
`init → prepare_context → plan_step → decide_action → execute_action → evaluate_continue`

Branches:
- `evaluate_continue → plan_step` (continue)
- `evaluate_continue → terminal` (complete/fail/freeze/suspend-request)

## Execution Flow
1. Validate control limits and timeout.
2. Prepare current context snapshot.
3. Generate plan fragment for current step.
4. Select allowed next action.
5. Execute action through boundary:
   - tool calls via router
   - persistence/suspend/finalization via executor request
6. Record step outcome.
7. Evaluate continuation conditions.

## Continuation Rules
Continue only if all remain true:
- timeout not exceeded
- steps/tool-call counts below policy limits
- no terminal action already requested
- blocked fingerprint threshold not exceeded

## Failure Modes
- repeated blocked/no-progress fingerprints → freeze request.
- timeout exceeded → fail request.
- repeated tool execution errors beyond tolerance → fail/freeze request.
- context preparation unrecoverable failure → fail request.

## Constraints
- iteration is bounded.
- step outcomes must be recorded.
- loop terminal output must be structured (no prose-only terminal status).

## Invariants
- each step has one recorded action type.
- every tool action has router correlation id.
- loop cannot transition lifecycle mode.

## Observability
Required telemetry:
- step count and tool-call count
- blocked fingerprint count
- continuation branch reason
- terminal request type and origin step

## Related Documents
- [Execution Model](../02_system/execution-model.md)
- [Tool Router](../05_tools/tool-router.md)
- [Context Assembly](../04_context-memory/context-assembly.md)

## Open Questions
- canonical blocked-fingerprint normalization across heterogeneous tool failures.
