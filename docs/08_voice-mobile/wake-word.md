# Wake Word

## Purpose
Define the wake/STT/agent/TTS execution chain and runtime boundaries for voice-triggered interaction.

## Scope
In scope:
- wake detection to execution intake handoff
- VAD capture boundary
- transcript routing semantics

Out of scope:
- claiming GA readiness

## Responsibilities
- detect wake events and capture utterance boundaries.
- convert audio to transcript input.
- route transcript through unified execution intake.

## Core Concepts
- voice path is an input source to existing executor; it is not a separate runtime path.
- wake, VAD, STT, and TTS are independently failure-prone stages with explicit fallback behavior.

## Core Data Models
### WakeEvent
- `wakeEventId`, `detectedAt`, `engine`, `confidence`, `deviceState`

### VoiceCaptureSession
- `captureId`, `wakeEventId`, `startedAt`, `endedAt`, `vadState`, `audioRef`

### TranscriptInput
- `captureId`, `text`, `sttConfidence`, `language`, `timestamp`

## Execution Flow (Target)
1. Wake engine detects phrase and emits `WakeEvent`.
2. Capture session starts; VAD determines end of utterance.
3. STT produces `TranscriptInput`.
4. Transcript enters unified intake as `ephemeral_request`.
5. Agent response projected to UI; optional TTS playback.
6. Listener returns to ready state.

## Failure Modes
- false wake detection → ignore path with telemetry marker.
- VAD never reaches end state → timeout capture and discard.
- STT failure → prompt retry or fallback to typed input.
- executor unavailable → queue/reject per policy with user-visible state.

## Constraints
- no direct loop invocation from wake pipeline.
- wake path must respect same policy and session projection boundaries as typed input.

## Invariants
- each wake capture maps to at most one transcript submission.
- failures are stage-local and explicitly reported.

## Observability
- wake detect rates and false positives
- VAD timeout rates
- STT confidence distribution
- transcript-to-request submission success rate

## Maturity
- current status: partial/experimental.
- end-to-end GA readiness remains incomplete.

## Related Documents
- [Voice Overview](./voice-overview.md)
- [Execution Model](../02_system/execution-model.md)
- [Mobile Native Integration](./mobile-native-integration.md)

## Open Questions
- default fallback UX for repeated wake/STT failures on constrained devices.
