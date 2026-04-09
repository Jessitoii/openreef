# Agent Loop

## Purpose
Define strict loop semantics for plan/decide/act/continue execution.

## Responsibilities
Loop may:
- plan step actions
- choose next action from allowed set
- request tool calls via router
- request persistence/suspend/finalization via executor boundary

Loop may not:
- reclassify mode
- bypass router, policy, or approval boundaries
- directly persist illegal transitions

## Core Data Models
- `LoopAction`: `respond|tool_call|structured_llm_step|persist_state_request|suspend_request|finish_request|fail_request`
- `LoopStepRecord`: step index, action type, reason, outcome, optional tool ref and token usage.
- `LoopControl`: max steps, max tool calls, timeout, blocked-fingerprint limit.

## Execution Flow
1. Check limits/timeouts.
2. Prepare context snapshot.
3. Plan step.
4. Decide action.
5. Execute through allowed boundary.
6. Record step.
7. Evaluate continuation/termination.

## Failure Modes
- no-progress fingerprint saturation → freeze.
- timeout or unrecoverable context failure → fail.
- repeated tool exceptions → fail/freeze per policy.

## Constraints
Bounded iteration and blocked-progress detection are mandatory.

## Related Documents
- [Tool Router](../05_tools/tool-router.md)
- [Context Assembly](../04_context-memory/context-assembly.md)
- [Execution Model](../02_system/execution-model.md)
