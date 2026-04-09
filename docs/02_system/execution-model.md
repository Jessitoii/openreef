# Execution Model

## Purpose
Define lifecycle modes, model relationships, legal transitions, executor/loop boundaries, and terminal result contract.

## Scope
In scope: intake normalization, classification output, request composition, run/workflow state, terminal result emission.
Out of scope: multi-engine orchestration and distributed execution.

## Core Data Models
- **ExecutionInput**: `inputId`, `sourceType`, `sourceRef`, `payload`, `receivedAt`, `actorId?`.
- **ExecutionClassifier output**: `mode`, `classificationReason`, `confidenceLevel`.
- **ExecutionRequest**: `requestId`, `agentId`, `mode`, `source`, `inputPayload`, `policy`, `createdAt`, plus optional `sessionId`, `triggerContext`, `runContext`, `workflowContext`.
- **RunState**: `runId`, `requestIdOrigin`, `status`, `mode`, `sessionId?`, `workflowId?`, `currentStepIndex`, `variables`, `lastAction`, `lastToolResultRef?`, `waitingReason?`, `resumeToken?`, `retryCount`, `createdAt`, `updatedAt`, `completedAt?`, `terminalReason?`.
- **WorkflowDefinition**: `workflowId`, `version`, `triggerBindingRules`, `steps`, `conditionRules`, `defaultPolicy`, `metadata`.
- **WorkflowRun**: `runId`, `workflowId`, `workflowVersionSnapshot`, `status`, `currentStepIndex`, `boundVariables`, `policySnapshot`, `historyRef`, `timestamps`.
- **ExecutionResult**: `requestId`, `runId?`, `terminalStatus`, `statusReason`, `toolOutcomeSummary`, `stateTransitionLogRef`, `visibilityContract`, `finalResponse?`.

## Model Relationships
1. `ExecutionInput` is normalized then classified once.
2. Classifier output + source payload become one `ExecutionRequest`.
3. Executor creates/loads `RunState` for persistent/triggered/resume paths.
4. `WorkflowDefinition` is static; `WorkflowRun` snapshots definition+policy at start.
5. Shared loop emits actions; executor applies legal state transitions.
6. Executor emits terminal `ExecutionResult` for all requests.

## State Transitions
### Mode usage
- `ephemeral_request`: short-lived chat execution, no durable lifecycle required.
- `persistent_request`: durable run, suspend/resume legal when policy allows.
- `resume_request`: resumes existing run from resumable status only.
- `triggered_request`: trigger/event intake; creates or resumes run per policy.

### Mode legality
- `ephemeral_request` cannot become persistent in-request.
- `persistent_request` can continue only through new `resume_request`.
- `triggered_request` can map to `resume_request` when bound run exists.

### Run lifecycle state machine summary
`created → queued → running → waiting_for_tool → running`

`running → waiting_for_confirmation → running`

`running → waiting_input | waiting_event → suspended → queued → running`

`running → retry_scheduled → queued → running`

Terminal: `running → completed | failed | frozen`; and `queued|running|suspended → cancelled`.

Illegal transitions:
- any terminal state → non-terminal
- resume without matching `runId` and resumable state

## Execution Flow
1. Normalize source payload to `ExecutionInput`.
2. Classify into mode.
3. Build `ExecutionRequest` with bound policy.
4. Executor validates legality and persistence requirements.
5. Executor loads/creates run/workflow state as required.
6. Executor invokes shared loop.
7. Loop returns actions/outcomes; executor commits legal transitions.
8. Executor emits and persists `ExecutionResult` projection.

## Failure Modes
- Invalid classification output: reject as failed (`classification_invalid`).
- Missing resume binding: reject as failed (`missing_run_binding`).
- Illegal transition request from loop: fail or freeze per policy.
- Persistent-state write failure: fail with explicit persistence reason.
- Result delivery/projection failure: fail with inspectable reason.

## Constraints
- Executor owns lifecycle legality and persistence.
- Loop cannot change mode.
- Terminal outcomes must always emit structured `ExecutionResult`.

## Observability
Record `requestId`, `runId?`, `mode`, policy hash, transition log entries, terminal reason, and visibility projection outcome.

## Related Documents
- [Execution Policy](./execution-policy.md)
- [Agent Loop](../03_agent/agent-loop.md)
- [Session Lifecycle](../03_agent/session-lifecycle.md)
