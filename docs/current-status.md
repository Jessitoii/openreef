# Current Status (Audit-Aligned)

Last audited: 2026-04-06

## Runtime Clarification (GAP-001 Task 3)

- Production inference abstraction: `lib/models/litert_bridge.dart`.
- Production inference call chain:
  - `lib/ui/screens/chat_screen.dart` -> `lib/ui/chat_workspace_controller.dart` -> `lib/ui/agent_loop_chat_session.dart` -> `lib/agent/agent_loop.dart` -> `lib/agent/agent_model_adapter.dart` -> `lib/models/litert_bridge.dart` (`generateStream`).
- Kotlin bridge status:
  - The Kotlin LiteRT bridge has been removed from the app module as part of Task 3.
  - `android/app/src/main/kotlin/com/openreef/app/openreef/MainActivity.kt` contains no LiteRT runtime registration.
- FlutterGemma delegation:
  - Current shipping path delegates model lifecycle and generation via `flutter_gemma` calls from `lib/models/litert_bridge.dart`.
- Parallel Dart-side inference path:
  - None found outside `lib/models/litert_bridge.dart` for production chat/inference execution.

## Approval Runtime Status (GAP-007 Task 3)
- Main-agent approval is now operational in production:
  - `lib/main.dart` injects `MainAgentApprovalController.confirmToolCall`, so every `requiresConfirmation` tool goes through a real user approval callback instead of the former fake deny.
  - The chat session surface still owns the pending approval state and renders the minimize approval prompt for `volume_set` (and any other manifest-defined sensitive tool) with approve/reject actions.
- Sub-agent approval now shares the same user-facing flow:
  - `lib/agent/tool_router.dart` sends sub-agent sensitive-tool calls into `AgentMailbox.requestApproval(...)`.
  - Mailbox approvals expire on a configurable timeout, resolve to a rejected result, and clean their pending state on approval, reject, or timeout.
  - `MainAgentApprovalController` listens for mailbox approval requests/resolutions and surfaces them through the existing chat UI, so the user sees one consistent experience for both paths.
- Policy alignment:
  - Both main-agent and sub-agent paths respect the same manifest-driven `requiresConfirmation` flag, so user-visible behavior is consistent regardless of the session origin.
  - Sub-agent approval cleanup is deterministic, and mailbox-driven timeouts now show the same rejected tool result as a manual denial.

## Feature Classification Matrix

| Feature Surface | UI Claim / User Expectation | Runtime Reality (Verified) | Status |
| :--- | :--- | :--- | :--- |
| Theme settings | Theme controls fully work | `SettingsController` updates app theme via `OpenReefApp` | PRODUCTION_READY |
| Skills registry UI | Skills are active/ready and injected on demand | UI can discover `SKILL.md` files, but `ContextAssembler` is bootstrapped with `InMemorySkillCatalog(const <SkillDefinition>[])` in `lib/main.dart`, so runtime skill injection path is inactive | NON_FUNCTIONAL |
| MCP connections UI | Connected MCP tools extend the agent | Connection/listing works in `McpConnectionsController`, but no integration into `ToolRouter`/`ToolCatalog` used by `AgentLoop` | PARTIAL |
| Voice settings + wake toggle | Wake + voice settings imply usable voice pipeline | Wake listener remains experimental and is now isolated behind a provisioned Picovoice key resource; without provisioning, runtime stays unavailable instead of entering a placeholder path. No wake -> capture -> STT -> agent -> TTS chain is wired yet. | EXPERIMENTAL / ISOLATED |
| TTS engine selector | Android/Kokoro selection affects spoken responses | Setting is stored only; no chat/agent path calls `AudioService.speak` | NON_FUNCTIONAL |
| Wake sensitivity slider | Sensitivity control affects detector behavior | Flutter now bridges sensitivity to the native wake service, but the control remains inactive while wake runtime is unavailable for builds without a provisioned Picovoice key | EXPERIMENTAL / PARTIAL |
| Trigger/automation runtime | Trigger infra implies proactive task execution | Exact-alarm and bridge delivery still exist, and the app now has a real unique WorkManager periodic polling worker for interval-based triggers that loads persisted snapshots and enqueues platform events when due | PARTIAL / IN PROGRESS |
| AutoDream background | Nightly consolidation runs in background | Dart consolidation logic exists but is never wired/scheduled from bootstrap; Android `AutoDreamWorker.kt` is a no-op success stub | STUB / MOCK / PLACEHOLDER |
| Sensitive-tool approvals | Sensitive actions prompt for approval and can complete safely | Main-agent approvals are wired through `MainAgentApprovalController`, sub-agent approvals resolve through `AgentMailbox`, and both surface through the same chat UI approval card | PRODUCTION_READY |

## Misleading Surface Risks

- Skills screen previously implied runtime activation (`ready`, injected on demand) although runtime catalog is empty.
- MCP screen previously implied router import and background task usage not present in active runtime.
- Voice controls previously appeared production-facing despite missing end-to-end execution chain.
- Chat header chip (`voice: local`) suggested active voice path.

## Recommended Product-Surface Policy

### Keep As-Is

- Theme controls.
- Core chat send/receive flow (non-voice).

### Mark As Experimental

- Voice settings block and voice-related chat hinting.
- Wake-word listener controls.

### Disable or Hide Until Wired

- Any UI that implies trigger/automation task execution.
- Any UI claim that MCP tools are routed into active agent tool execution.

### Post-MVP De-scope

- AutoDream background feature until scheduler registration plus real worker execution are both wired and validated end-to-end.

## Notes

- This status document reflects runtime behavior observed in current source, not architecture targets in planning documents.
- Classification rule applied: if a feature is not operational end-to-end in runtime, it is not production-ready.

## GAP-002 Agent Loop Hardening (Closed)

- Loop safety now relies on the blocked-fingerprint no-progress guard in `lib/agent/agent_loop.dart`: repeated rejected tool calls and repeated exception paths are tracked by the same fingerprint (toolId + canonical args + normalized outcome), and three identical blocked steps trigger a deterministic frozen stop rather than infinite looping.
- Terminal outcomes are explicit: success stays `SessionResult.completed`, repeated blocked safety stops remain `SessionResult.frozen`, and runtime failures map to `SessionResult.failed` with a minimal `reason`. `lib/ui/agent_loop_chat_session.dart` renders `failed` vs `frozen` distinctly so the UX no longer treats any failure as normal completion.
- Generation failures now return `SessionResult.failed` and the loop surfaces them through `_completeWithFailure`. Compaction failures are also caught, reported as `failed`, and no longer crash the session path.
- `ReefCompactor` now prunes `toolError` messages during micro compaction, tags summaries with compaction-level metadata, and falls back to a deterministic inline summary whenever the configured summarizer throws or yields empty text so compaction can never silently fail during normal operation.

### Closure Statement

- GAP-002 is closed because loop safety now enforces bounded rejected/no-progress cycles, repeated exceptions, deterministic failure terminals, and compaction safeguards (including summarizer fallback) without any code regressions.
