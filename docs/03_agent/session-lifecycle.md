# Session Lifecycle

## Purpose
Define how request/run lifecycle is projected into session-visible UI and history state.

## Session State Machine
`idle → processing → waiting_confirmation|waiting_input|waiting_event → suspended → resumed → processing → terminal`

Terminal states:
- `completed`
- `failed`
- `frozen`
- `cancelled`

## Projection Mapping (Run → Session/UI)
| Run transition | Session state | UI projection |
|---|---|---|
| `created/queued` | `processing` | queued/running indicator with request metadata |
| `running → waiting_for_confirmation` | `waiting_confirmation` | pending approval card/state |
| `running → waiting_input` | `waiting_input` | user-input-required prompt |
| `running → waiting_event` | `waiting_event` | external-event-wait marker |
| `suspended` | `suspended` | resumable run badge + reason |
| `completed` | `completed` | final response + completion metadata |
| `failed` | `failed` | explicit failure reason/state |
| `frozen` | `frozen` | blocked/no-progress terminal marker |
| `cancelled` | `cancelled` | cancellation reason |

## Rules
- Session projection must always follow `ExecutionResult.visibilityContract`.
- Failed/frozen outcomes must display structured reasons, not generic prose.
- Suspended sessions must retain resumable identifiers required for `resume_request`.

## Failure and Frozen Projection
- `failed`: render terminal error state with reason code and correlation id.
- `frozen`: render terminal blocked state with freeze reason and recovery hint.
- If UI projection fails, run remains terminal in storage and projection retry is logged.

## Related Documents
- [Execution Model](../02_system/execution-model.md)
- [Execution Policy](../02_system/execution-policy.md)
