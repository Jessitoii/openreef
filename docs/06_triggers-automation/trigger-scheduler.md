# Trigger Scheduler

## Purpose
Define timing semantics, missed-fire handling, jitter tolerance, and queue/backpressure interaction for scheduled trigger sources.

## Ownership Boundaries
- Scheduler owns time-based event emission (`schedule`, `interval`).
- Arbitration/executor own concurrency, duplicate handling, and run conflict decisions.
- Scheduler does not bypass arbitration or dispatch directly into loop.

## Timing Behavior
- Schedules emit normalized `TriggerEvent` objects at configured cadence.
- Intervals are measured from last successful fire timestamp (not UI refresh timing).
- Scheduler records `scheduledAt` and `firedAt` for drift analysis.

## Missed-Fire Handling
| Condition | Behavior |
|---|---|
| App/service paused then resumed | emit one catch-up event if within configured grace window |
| Missed window exceeds grace | skip missed fire and record `missed_fire_skipped` |
| Multiple missed interval slots | coalesce to one catch-up event with metadata count |

## Drift/Jitter Tolerance
- Scheduler allows bounded fire jitter; out-of-bound drift is logged.
- Repeated drift beyond tolerance raises scheduler health warning.
- Drift correction must not create event storms; correction paths pass through arbitration.

## Backpressure and Queue Interaction
- If arbitration/executor queue is saturated, scheduler marks event as deferred or dropped per policy.
- Scheduler records queue latency and drop/defer reasons.
- Scheduler never retries indefinitely; retries are bounded by execution policy.

## Failure Modes
- Invalid schedule config: disable trigger definition and emit validation diagnostics.
- Clock/timezone anomalies: log anomaly and avoid duplicate same-slot emissions.
- Executor unavailable: defer/queue per policy, then retry within bounds.

## Related Documents
- [Trigger Lifecycle](./trigger-lifecycle.md)
- [Execution Policy](../02_system/execution-policy.md)
