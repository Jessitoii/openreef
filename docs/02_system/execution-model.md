# Execution Model

## Purpose
Define lifecycle semantics and model contracts for all execution sources routed through the single executor and shared loop.

## Scope
In scope:
- input normalization and mode classification
- request construction and policy binding
- persistent run/workflow state contracts
- legal transitions and terminal outcome emission

Out of scope:
- distributed execution
- multi-engine orchestration
- UI rendering details

## Responsibilities
- `ExecutionInput` is the intake normalization boundary.
- `ExecutionClassifier` assigns lifecycle mode once per request.
- `ExecutionRequest` is the only executor entry contract.
- Executor owns lifecycle legality and state persistence.
- Shared loop executes bounded actions but cannot reclassify mode.
- `ExecutionResult` is mandatory for all terminal outcomes.

## Core Concepts
- **Mode legality over prompt behavior**: lifecycle is data-driven, not inferred ad hoc by prompts.
- **Executor-owned transitions**: loop proposes actions; executor commits legal state transitions.
- **Persistent vs ephemeral isolation**: ephemeral requests do not create durable run lifecycle state.

## Core Data Models
### ExecutionInput
Required fields:
- `inputId`
- `sourceType` (`chat_user|trigger|resume_signal|system|mcp_event`)
- `sourceRef`
- `payload`
- `receivedAt`
- `actorId?`

### ExecutionClassifierOutput
Required fields:
- `mode` (`ephemeral_request|persistent_request|resume_request|triggered_request`)
- `classificationReason`
- `confidenceLevel` (`rule_based|llm_assisted_structured`)

### ExecutionRequest
Required fields:
- `requestId`, `agentId`, `mode`, `source`, `inputPayload`, `policy`, `createdAt`
Optional fields (as applicable):
- `sessionId`, `triggerContext`, `runContext`, `workflowContext`

### RunState
Required fields:
- `runId`, `requestIdOrigin`, `status`, `mode`, `currentStepIndex`
- `variables`, `lastAction`, `retryCount`
- `createdAt`, `updatedAt`, `completedAt?`, `terminalReason?`
Optional persistence helpers:
- `sessionId?`, `workflowId?`, `lastToolResultRef?`, `waitingReason?`, `resumeToken?`

Allowed status set:
`created|queued|running|waiting_for_tool|waiting_for_confirmation|waiting_input|waiting_event|suspended|retry_scheduled|completed|failed|frozen|cancelled`

### WorkflowDefinition
Required fields:
- `workflowId`, `version`, `triggerBindingRules`, `steps`, `conditionRules`, `defaultPolicy`, `metadata`

### WorkflowRun
Required fields:
- `runId`, `workflowId`, `workflowVersionSnapshot`, `status`, `currentStepIndex`
- `boundVariables`, `policySnapshot`, `historyRef`, `timestamps`

### ExecutionResult
Required fields:
- `requestId`, `terminalStatus`, `statusReason`, `toolOutcomeSummary`, `stateTransitionLogRef`, `visibilityContract`
Optional fields:
- `runId?`, `finalResponse?`

## Model Relationships
1. Intake normalizes source payload into `ExecutionInput`.
2. Classifier emits one mode decision.
3. Builder produces `ExecutionRequest` with policy snapshot.
4. Executor validates legality and creates/loads `RunState` when durable lifecycle is required.
5. Loop emits actions; executor commits legal transitions.
6. Executor emits terminal `ExecutionResult` and visibility projection.

## State Transitions
### Mode usage
- `ephemeral_request`: short-lived request, no durable run lifecycle required.
- `persistent_request`: durable execution that can suspend and resume.
- `resume_request`: resumes an existing run from resumable statuses only.
- `triggered_request`: trigger/event intake that creates or resumes run per policy.

### Mode legality
- `ephemeral_request` cannot transition to persistent in the same request.
- `persistent_request` continuation requires a new `resume_request`.
- `triggered_request` may map to resume only with an existing bound run.

### Lifecycle machine (summary)
`created → queued → running → waiting_for_tool → running`

`running → waiting_for_confirmation → running`

`running → waiting_input|waiting_event → suspended → queued → running`

`running → retry_scheduled → queued → running`

Terminal edges:
- `running → completed|failed|frozen`
- `queued|running|suspended → cancelled`

Illegal edges:
- terminal → non-terminal
- resume without `runId`
- resume from non-resumable status

## Execution Flow
1. Normalize source to `ExecutionInput`.
2. Classify mode.
3. Build `ExecutionRequest` with policy.
4. Validate request legality.
5. Create/load run and workflow snapshots (if applicable).
6. Invoke shared loop.
7. Apply loop actions through executor-owned transition rules.
8. Persist transitions and emit terminal `ExecutionResult`.

## Failure Modes
- classification invalid or unsupported mode → immediate fail.
- resume binding missing or stale run state → fail (`missing_run_binding`).
- illegal loop transition request → fail/freeze per policy.
- persistent write failure → terminal fail with persistence reason.
- visibility projection failure → terminal status preserved with projection error logged.

## Constraints
- one executor, one loop.
- lifecycle legality is executor-owned.
- all terminal outcomes must be structured and inspectable.
- ephemeral mode cannot create durable run lifecycle records.

## Invariants
- exactly one mode per request.
- every terminal request has `ExecutionResult`.
- every persistent run transition is reasoned and logged.
- run identifiers are immutable across resume transitions.

## Observability
Minimum telemetry:
- `requestId`, `runId?`, `mode`, `policyHash`
- transition log (`from`, `to`, `reason`, `timestamp`)
- terminal status and reason code
- visibility projection outcome

## Related Documents
- [Execution Policy](./execution-policy.md)
- [Agent Loop](../03_agent/agent-loop.md)
- [Session Lifecycle](../03_agent/session-lifecycle.md)

## Open Questions
- Final classifier implementation split and deterministic fallback behavior.
- Persistence schema/versioning details for run/workflow snapshots.
