# Mobile Native Integration

## Purpose
Define native bridge boundaries, permission integration, and service-level constraints for mobile runtime capabilities.

## Scope
In scope:
- native invocation boundaries
- service and permission interplay
- security boundary requirements

Out of scope:
- platform UI implementation details

## Responsibilities
- expose native capabilities through tool-router-controlled interfaces.
- enforce permission and confirmation checks before sensitive operations.
- maintain stable service boundaries for background/foreground operations.

## Core Concepts
- native APIs are capability backends, not direct UI invocations.
- permission and confirmation policies remain centralized.
- method/event bridge calls require correlation and auditability.

## Core Data Models
### NativeInvocationRequest
- `invocationId`, `toolId`, `requestId`, `runId?`, `payload`, `requiredPermissions[]`

### NativeInvocationResult
- `invocationId`, `status`, `payloadRef?`, `errorCode?`, `durationMs`

### PermissionStateSnapshot
- `permission`, `granted`, `source`, `timestamp`

## Execution Flow
1. Tool router dispatches native-capability request.
2. Native bridge validates permission state.
3. Operation executes in appropriate service context.
4. Result normalized and returned to router.
5. Outcome persisted and projected.

## Failure Modes
- permission denied/revoked mid-run → blocked result with reason.
- service unavailable/background restriction → unavailable/timeout branch.
- bridge serialization failure → execution error with correlation id.

## Constraints
- no native call path that bypasses router/policy.
- sensitive native operations require explicit confirmation per policy class.
- bridge requests/results must remain schema-versioned.
- background trigger delivery must persist to a native queue first, then hand off to Flutter through the active event sink.
- Android app-closed periodic polling is supported only for WorkManager-backed cadences at 15 minutes or above.
- 5-14 minute app-closed polling remains unsupported unless a real AlarmManager-based repeating path is added.
- native poll state is owned by Android for the periodic worker path; Flutter may observe delivery events but does not own worker state.

## Invariants
- every native invocation has one correlation id chain.
- permission snapshots are attached to sensitive operation outcomes.

## Observability
- invocation success/failure rates by capability class
- permission denial counts and reasons
- bridge latency and timeout distributions

## Related Documents
- [Tool Router](../05_tools/tool-router.md)
- [Permissions Model](../10_security/permissions-model.md)
- [Confirmation and Side-Effect Policy](../05_tools/confirmation-and-side-effect-policy.md)

## Open Questions
- standardized handling for OEM-specific permission edge cases.
