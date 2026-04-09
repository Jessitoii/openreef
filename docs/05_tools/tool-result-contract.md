# Tool Result Contract

## Purpose
Define normalized tool outcome schema and required failure categories.

## Core Data Models
`ToolResult` minimum fields:
- `callId`, `toolId`, `status`, `durationMs`, `observabilityRef`
- optional `outputPayload`, `errorCode`, `errorMessage`, `policyReason`

## Status Categories
- `success`
- `rejected`
- `validation_error`
- `execution_error`
- `timeout`
- `unavailable`
- `blocked_by_policy`

## Context Injection Rules
Inject into context:
- `toolId`
- normalized `status`
- bounded structured output summary
- policy/error reason for non-success

## Persistence Rules
Persist into run state:
- call metadata
- normalized status
- reference to full audit payload

## Constraints
Rejection reason, policy block reason, timeout, and unavailable categories must never be hidden in prose.
