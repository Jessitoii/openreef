# Trigger Scheduler

## Purpose
Define operational timing behavior for schedule/interval trigger emission.

## Scope
In scope:
- cadence and timestamp semantics
- missed-fire handling
- drift/jitter tolerance
- backpressure interaction

Out of scope:
- arbitration decision logic

## Responsibilities
- emit normalized time-based `TriggerEvent`s.
- preserve scheduler timing metadata for diagnostics.
- prevent storm behavior under drift/recovery conditions.

## Core Concepts
- scheduler emits events; arbitration/executor decide concurrency handling.
- missed-fire handling is bounded and explicit.
- drift correction cannot bypass policy and queue limits.

## Core Data Models
### SchedulerTick
- `triggerId`, `scheduledAt`, `firedAt`, `tickSource`, `clockSkewEstimate?`

### MissedFireRecord
- `triggerId`, `missedAt`, `recoveryAction` (`catch_up|skip|coalesce`), `reason`

## Timing Semantics
- schedule triggers fire at configured slot boundaries.
- interval triggers measure from last successful emission.
- each emission includes `scheduledAt` and `firedAt` timestamps.
- app-closed periodic polling on Android is only supported by the unique WorkManager-backed worker at 15 minutes or above.
- trigger-specific overrides take precedence over the global poll setting, then the default 15 minutes.
- intervals below 15 minutes are rejected for app-closed periodic polling unless a real AlarmManager repeating path exists.

## Missed-Fire Handling
| Condition | Action |
|---|---|
| app paused then resumes within grace | emit single catch-up event |
| missed window exceeds grace | skip and record reason |
| multiple missed interval ticks | coalesce to one event with count metadata |

## Drift/Jitter Tolerance
- bounded jitter tolerated per trigger config.
- out-of-bound drift logged as scheduler health signal.
- repeated drift triggers degraded scheduler health status.

## Backpressure and Queue Interaction
- if arbitration/executor backlog is saturated, scheduler marks event deferred/dropped per policy.
- deferred events carry original `scheduledAt` for latency calculations.
- scheduler retries are bounded and policy-governed.

## Execution Flow
1. Evaluate schedule/interval due set.
2. Emit scheduler ticks.
3. Apply missed-fire recovery logic if needed.
4. Attach timing metadata and emit normalized events.
5. Hand off to trigger lifecycle arbitration.

## Failure Modes
- invalid schedule configuration → disable trigger and emit diagnostics.
- clock anomalies/timezone jump → suppress duplicate slot emissions and log anomaly.
- prolonged executor unavailability → bounded defer/drop path with reason.

## Constraints
- scheduler does not dispatch directly to loop.
- scheduler cannot override arbitration/policy outcomes.

## Invariants
- each emitted event includes stable trigger id and timing metadata.
- recovery logic never emits unbounded catch-up storms.

## Observability
- schedule drift distribution
- missed-fire counts by action
- deferred/drop counts due to backpressure
- scheduler health status transitions

## Related Documents
- [Trigger Lifecycle](./trigger-lifecycle.md)
- [Execution Policy](../02_system/execution-policy.md)

## Open Questions
- default grace windows by trigger class and device power state.
