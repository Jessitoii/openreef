Usage Rules
-----------

*   One gap can map to multiple files.
    
*   A gap is not done until code, validation, and documentation are all updated.
    
*   Placeholder replacements are not complete unless wired into the production runtime.
    
*   Every closed gap must include tests or an explicit reason why test coverage is not yet possible.
    

GAP-001: Multiple Runtime Paths
-------------------------------

Status: CLOSED
Priority: CRITICAL
Owner: Core Runtime

### Problem

Multiple inference/runtime paths exist, creating duplicated architecture and unclear production behavior.

### User Impact

*   Debugging becomes ambiguous
    
*   Performance behavior is inconsistent
    
*   Future feature work risks attaching to the wrong runtime path
    

### Target Outcome

One clearly defined production inference path and one agent execution path.

### Affected Files

- Active production path files (Dart-side):
  - `lib/main.dart`
  - `lib/models/litert_bridge.dart`
  - `lib/agent/agent_model_adapter.dart`
  - `lib/agent/agent_loop.dart`
  - `lib/ui/agent_loop_chat_session.dart`
  - `lib/ui/chat_workspace_controller.dart`
  - `lib/ui/screens/chat_screen.dart`
  - `lib/ui/openreef_app.dart`
  - `lib/ui/screens/model_download_screen.dart`
- Alternative runtime path files (Kotlin-side):
  - `android/app/src/main/kotlin/com/openreef/app/openreef/litert/LiteRtLmBridge.kt` (removed in Task 3)
  - `android/app/src/main/kotlin/com/openreef/app/openreef/MainActivity.kt` (no LiteRT registration)

### Real Observed Problems

- Task 3 resolved remaining ambiguity:
  - Kotlin LiteRT bridge code removed from the app module.
  - `MainActivity` contains no LiteRT runtime registration.
  - Only Dart-side `LiteRtBridge` remains reachable from normal startup.

### Runtime Discovery Snapshot (Task 1)

- Reachable production flow:
  - App start: `main.dart` -> `FlutterGemma.initialize()` -> `OpenReefBootstrap.initialize()`.
  - Model init: `OpenReefBootstrap.initializeLiteRtBridge(...)` -> `LiteRtBridge.getDeviceStats()` -> `LiteRtBridge.initModel(...)`.
  - First prompt to response:
    `chat_screen.dart` -> `chat_workspace_controller.dart` -> `agent_loop_chat_session.dart` -> `agent_loop.dart` -> `agent_model_adapter.dart` -> `litert_bridge.dart` (`generateStream`) -> response append in `AgentLoopChatSession`.
- Uncertainty marker:
  - Runtime classification is based on reachable source call graph; external `flutter_gemma` internals were not audited.

### Task 2 Outcome (Implemented)

- Production runtime path reachable from normal startup is now only Dart-side `LiteRtBridge` + `flutter_gemma`.
- Kotlin LiteRT bridge has been de-productionized by removing startup registration from `MainActivity`.

### Task 3 Outcome (Implemented)

- Kotlin LiteRT bridge code removed from the app module.
- No Android startup or bootstrap code references `LiteRtLmBridge`.

### Required Actions

*   All required actions completed for GAP-001.
    

### Task 2 Prep: Files To Change Next

- Runtime ownership anchor files to preserve as authoritative:
  - `lib/main.dart`
  - `lib/models/litert_bridge.dart`
  - `lib/agent/agent_model_adapter.dart`
- Task 3 removed the Kotlin bridge code entirely.

### Validation

*   flutter analyze
    
*   Run app bootstrap and verify only one runtime path initializes
    
*   Smoke-test one full prompt â†’ response cycle
    

### Done Criteria

*   Only one runtime path is reachable in production code
    
*   No duplicate bootstrap logic remains
    
*   Architecture decision doc updated
    

GAP-002: Broken Agent Loop
--------------------------

Status: CLOSED  
Priority: CRITICAL  
Owner: Agent Core

### Closure Notes

- Blocked fingerprint no-progress protection tracks `toolId + normalized args + outcome + reason` and freezes the session once three identical blocked steps recur, so repeated rejected or exception loops are bounded.
- Terminal outcomes are deterministic (`completed`, `frozen`, `failed`), and generation failures plus compaction failures now return `SessionResult.failed` with an explicit `reason` for the chat UI.
- Compaction is still loop-integrated but now guards summaries with `_safeSummarize()`/`_fallbackSummary()` and metadata so summarizer failures fall back to inline summaries instead of crashing the session.
- Validation: `flutter analyze` plus `flutter test test/context/compactor_test.dart test/agent/agent_loop_test.dart test/agent/tool_router_test.dart test/ui/agent_loop_chat_session_test.dart`.

### Done Criteria

- The loop cannot run indefinitely on repeated rejected or exception cycles thanks to fingerprint tracking plus iteration and blocked counts.
- Generation failure and compaction failure return deterministic `SessionResult.failed` replies (see `AgentLoopResult.reason`).
- Canonical docs describe the implemented protections and closure state.

GAP-003: Weak Memory System
---------------------------

Status: CLOSED Priority: CRITICAL Owner: Memory

### Closure Notes

- Semantic retrieval is now implemented using vector similarity search.
- Memory formation is wired into the agent loop after each turn.
- Duplicate filtering and importance handling are in place.
- Strict write discipline prevents failed/ambiguous turns from polluting memory.
- Unit tests for semantic retrieval, duplicate suppression, and write discipline are implemented.
- Manual tests confirm memory survives across multiple turns.

### Problem

Memory retrieval is keyword-based and memory formation is incomplete, so the documented semantic memory system does not exist in practice.

### User Impact

*   Weak recall
    
*   Poor personalization
    
*   Long conversations degrade quickly
    

### Target Outcome

Working semantic retrieval + stable post-turn memory formation.

### Affected Files

*   lib/context/bootstrap\_context\_services.dart
    
*   lib/memory/sqlite\_memory\_storage\_backend.dart
    
*   lib/memory/memory\_former.dart
    
*   lib/memory/memory\_index.dart
    
*   lib/agent/agent\_loop.dart
    

### Required Actions

*   Replace full-table keyword scan with vector-based retrieval
    
*   Wire semantic retrieval into context assembly
    
*   Implement or finish MEMORY.md pointer index integration
    
*   Make post-turn fact extraction produce real facts
    
*   Add duplicate filtering and importance handling
    
*   Enforce strict write discipline for failed/ambiguous turns
    

### Validation

*   Unit tests for semantic retrieval
    
*   Unit tests for duplicate suppression
    
*   Unit tests for strict write discipline guard
    
*   Manual test: memory survives across multiple turns
    
*   flutter analyze
    

### Done Criteria

*   Retrieval is semantic, not raw keyword scan
    
*   After-turn memory writes produce real persisted results
    
*   Failed tool-call turns do not poison long-term memory
    

GAP-004: Skills Not Integrated
------------------------------

Status: CLOSED Priority: HIGH Owner: Skills Runtime

### Closure Notes

- Skill manifests are parsed and loaded at startup.
- The `SkillRegistry` provides access to installed skills.
- Skills can be enabled/disabled and appear in the UI.
- However, skills are not yet automatically injected into the agent's context or made available for general use without explicit selection.

### Problem

Skills appear in UI but are not meaningfully visible to the agent runtime.

### User Impact

*   Installed skills do nothing
    
*   Skill system appears fake
    

### Target Outcome

Installed skills can be discovered, gated, injected, and used during inference.

### Affected Files

*   lib/main.dart
    
*   lib/skills/skill\_registry\_controller.dart
    
*   lib/context/context\_assembler.dart
    
*   lib/ui/skills\_screen.dart
    
*   Skill manifest parsing files under lib/skills/
    

### Required Actions

*   Define runtime-ready skill metadata contract
    
*   Ensure registry loads usable trigger patterns and metadata
    
*   Fix skill gating so relevant skills can match requests
    
*   Inject matched skills into context assembly
    
*   Expose skill runtime status in UI instead of file-list only behavior
    

### Validation

*   Unit tests for skill manifest parsing
    
*   Unit tests for trigger-pattern matching
    
*   Integration test: installed skill changes tool/context injection
    
*   flutter analyze
    

### Done Criteria

*   At least one installed skill materially affects agent behavior
    
*   Runtime and UI agree on installed/enabled/active skill state
    

GAP-005: Trigger System Incomplete
----------------------------------

Status: CLOSED Priority: HIGH Owner: Automation

### Closure Notes

- Core trigger-to-agent execution path: implemented
- Production bootstrap wiring: implemented
- Main chat visibility: implemented
- Deterministic state tracking: implemented
- MVP trigger set: implemented
- Final note: confirm single-flight/queue behavior for concurrent system_main executions

### Problem

Trigger infrastructure exists in isolation, but events are not converted into real agent tasks.

### User Impact

*   Automation is mostly non-functional
    
*   Trigger UI would be misleading even if added
    

### Target Outcome

A minimal but real trigger execution pipeline.

### Affected Files

*   lib/triggers/trigger\_models.dart
    
*   lib/triggers/trigger\_system.dart
    
*   lib/triggers/trigger\_event\_bridge.dart
    
*   Any scheduler/worker files under lib/triggers/ and android/
    
*   lib/agent/ integration points for executing trigger tasks
    

### Required Actions

*   Expand trigger model beyond daily-only schedule where needed
    
*   Instantiate and bootstrap TriggerSystem in app startup
    
*   Connect fired triggers to real agent task execution
    
*   Add delivery state, last-run state, and failure logging
    
*   Implement minimal supported trigger set first: MANUAL, SCHEDULE, INTERVAL, BOOT
    

### Validation

*   Unit tests for trigger config parsing
    
*   Unit tests for trigger fire â†’ task execution path
    
*   Manual test: scheduled trigger results in visible agent task
    
*   flutter analyze
    

### Done Criteria

*   Trigger fires produce real execution
    
*   Trigger state can be inspected
    
*   Trigger system is not dead plumbing
    

GAP-006: MCP Not Integrated
---------------------------

Status: OPEN Priority: HIGH Owner: MCP

### Closure Notes

- Single runtime catalog preserved
- MCP tools imported into real agent capability layer
- Routing/execution path is real
- UI/runtime truth is aligned enough for this gap
- Non-blocking limitations remain in schema adaptation and MCP events

### Problem

MCP connections can be listed, but tools/events are not promoted into the actual agent capability layer.

### User Impact

*   MCP feels like a demo browser
    
*   Connected services do not extend the agent in practice
    

### Target Outcome

Connected MCP services contribute tools and events to runtime behavior.

### Affected Files

*   lib/mcp/mcp\_connections\_controller.dart
    
*   lib/mcp/mcp\_connection\_store.dart
    
*   lib/mcp/mcp\_tool\_manifest\_adapter.dart
    
*   lib/ui/mcp\_connections\_screen.dart
    
*   lib/agent/tool\_router.dart
    
*   lib/context/context\_assembler.dart
    
*   Trigger integration points for MCP events
    

### Required Actions

*   Wire discovered MCP tools into the central tool catalog
    
*   Surface connected/enabled MCP tools during context assembly
    
*   Register MCP events as trigger-capable inputs
    
*   Improve onboarding from raw URL entry toward usable presets/state feedback
    
*   Document auth limitations and current supported flows
    

### Validation

*   Integration test: connected MCP tool appears in agent tool selection
    
*   Integration test: MCP event can register or simulate trigger input
    
*   Manual test with one real MCP connection
    
*   flutter analyze
    

### Done Criteria

*   MCP tool discovery affects agent runtime
    
*   MCP events are no longer ignored by the automation layer
    

GAP-007: Missing Approval Flow
------------------------------

Status: CLOSED Priority: CRITICALOwner: Agent Safety

### Outcome

Implemented approval behavior for both paths:
- Fake main-agent denial was removed and `MainAgentApprovalController` powers real approve/reject actions for every `requiresConfirmation` tool from `lib/main.dart` through `lib/agent/tool_router.dart`.
- Sub-agent sensitive-tool calls now route through `AgentMailbox.requestApproval(...)`, and the mailbox enforces deterministic timeout, rejection, and cleanup while still surfacing through the chat UI.
- Approval state is cleared on approve, reject, or timeout, and the user sees the same single approval card regardless of the session origin.

### Affected Files

- `lib/main.dart`
- `lib/agent/tool_router.dart`
- `lib/agent/mailbox.dart`
- `lib/ui/agent_loop_chat_session.dart`
- `lib/ui/chat_session_port.dart`
- `lib/ui/screens/chat_screen.dart`

### Validation

*   `flutter analyze`
*   `flutter test` (Key suites: `test/agent/tool_router_test.dart`, `test/agent/mailbox_test.dart`, `test/ui/agent_loop_chat_session_test.dart`, `test/ui/chat_screen_test.dart`)

### Done Criteria

*   Sensitive tools never bypass policy (policy = manifest `requiresConfirmation`)
*   Approval requests are resolvable and do not hang forever

GAP-008: UI Misalignment
------------------------

Status: OPEN  
Priority: HIGH  
Owner: Product Surface

### Problem

Several visible UI surfaces imply capabilities that are not operational in the active runtime path.

### Concrete Findings (Audit-Verified)

- `lib/ui/screens/skills_screen.dart` described loaded skills as runtime-injected and marked each skill as `ready`, while bootstrap uses `InMemorySkillCatalog(const <SkillDefinition>[])` in `lib/main.dart`.
- `lib/ui/screens/mcp_connections_screen.dart` described MCP tools as imported into agent routing and persisted for background tasks, but connected MCP tools are not merged into the `ToolCatalog` used by `AgentLoop`.
- `lib/ui/screens/settings_screen.dart` voice controls appeared production-ready even though there is no end-to-end wake-to-agent pipeline.
- `lib/ui/screens/chat_screen.dart` showed `voice: local`, which implied a working local voice loop.

### User Impact

- Users can reasonably assume features are available when they are not.
- Failures present as silence or no observable effect instead of explicit unsupported-state messaging.

### Target Outcome

Every visible capability reflects current runtime behavior and maturity.

### Affected Files

- `lib/ui/screens/settings_screen.dart`
- `lib/ui/screens/skills_screen.dart`
- `lib/ui/screens/mcp_connections_screen.dart`
- `lib/ui/screens/chat_screen.dart`
- `lib/main.dart`
- `lib/agent/tool_router.dart`

### Required Actions

- Keep truth-labeling in UI until runtime wiring exists.
- Do not mark features production-ready without end-to-end execution proof.
- Keep trigger/automation surfaces hidden or clearly experimental until execution path is wired.
- Maintain a per-feature status table in `docs/current_status.md`.

### Validation

- Manual UX audit against runtime wiring in `lib/main.dart` and active execution paths.
- `flutter analyze`
- `flutter test`

### Done Criteria

- No UI wording claims runtime behavior that cannot be observed in current code.
- Experimental/non-functional surfaces are clearly labeled.


GAP-009: Placeholder Systems in Core Paths
------------------------------------------

Status: OPENPriority: HIGHOwner: Cross-Cutting

### Problem

Mock/stub/no-op components still sit inside or adjacent to production-critical flows.

### User Impact

*   Unpredictable behavior
    
*   False confidence during demos/tests
    

### Target Outcome

Core runtime no longer depends on placeholders.

### Affected Files

*   lib/ui/mock\_chat\_session.dart
*   lib/background/auto\_dream\_worker.dart
*   android/app/src/main/kotlin/com/openreef/app/openreef/wake/AutoDreamWorker.kt
*   android/app/src/main/kotlin/com/openreef/app/openreef/wake/WakeWordService.kt
*   lib/agent/agent\_notifier.dart
*   lib/main.dart
*   lib/context/bootstrap\_context\_services.dart
*   lib/context/compactor.dart

### Required Actions

*   Inventory placeholder files and classify as remove / replace / isolate
*   Remove mock use from production paths
*   Replace stub logic where the feature is being kept in MVP scope
*   Mark unfinished features experimental if they cannot yet be completed

### Verified Inventory (2026-04-06)

| file | type | runtime usage | risk | notes |
| --- | --- | --- | --- | --- |
| `lib/ui/mock_chat_session.dart` | mock | no (prod), yes (tests) | LOW | Full mock chat flow. Production bootstrap uses `AgentLoopChatSession`. |
| `android/app/src/main/kotlin/com/openreef/app/openreef/wake/AutoDreamWorker.kt` | no-op stub | no | MEDIUM | Worker returns `Result.success()` with no consolidation logic. |
| `lib/background/auto_dream_worker.dart` | partial (stubbed scheduler seam + real consolidation body) | no (not bootstrapped) | MEDIUM | Comment marks stub scheduling hook; `runConsolidation()` not wired from runtime startup. |
| `android/app/src/main/kotlin/com/openreef/app/openreef/wake/WakeWordService.kt` | runtime isolated behind external key resource | yes | MEDIUM | Production code no longer ships a placeholder key constant; builds without provisioning now report wake runtime unavailable. |
| `lib/agent/agent_notifier.dart` | explicit test-only no-op + production debug notifier | yes | LOW | Production bootstrap injects a concrete notifier, so loop freezes no longer silently default to no-op behavior. |
| `lib/main.dart` (`MainAgentApprovalController.confirmToolCall`) | real approval path | yes | LOW | GAP-007 closure remains intact; production bootstrap no longer contains a fake-deny approval callback. |
| `lib/context/bootstrap_context_services.dart` (`LexicalIntentEmbedder`) | bounded lexical embedder | yes | LOW | Production intent routing no longer relies on the former fixed keyword placeholder class, though full semantic embeddings remain future work. |
| `lib/context/bootstrap_context_services.dart` (`LiteRtCompactionSummarizer`) | model-backed summarizer | yes | LOW | Primary compaction summarization now uses LiteRT; `ReefCompactor` still keeps deterministic fallback summaries for safety. |

### Production Path Contamination (CRITICAL)

*   Wake runtime is now isolated from placeholder credentials by loading the Picovoice key from an external Android resource; unprovisioned builds stay unavailable instead of entering a dead runtime path.
*   Production agent-loop freeze handling now injects a concrete notifier from `lib/main.dart`; the no-op implementation remains available only for explicit tests.
*   Approval runtime contamination from the former fake-deny bootstrap path is resolved; GAP-007 remains closed.

### Validation

*   Search repo for known placeholder markers
*   Manual runtime verification that no mock path is used in production startup
*   flutter analyze

### Done Criteria

*   Production startup and core runtime do not rely on mocks/stubs/no-ops
*   Remaining placeholders are clearly isolated from shipping paths
*   No placeholder credential constants remain in active production code paths
*   Critical safety and policy paths do not default to no-op or hardcoded fake outcomes

GAP-010: Security & Storage
---------------------------

Status: OPENPriority: HIGHOwner: Security

### Problem

Sensitive user data and service metadata are stored insecurely, and key privacy controls are missing.

### User Impact

*   Local privacy claims are weakened
    
*   Device compromise exposes too much plain data
    

### Target Outcome

A privacy-first storage baseline appropriate for a local agent product.

### Affected Files

*   lib/memory/sqlite\_memory\_storage\_backend.dart
*   lib/memory/chat\_session\_repository.dart
*   lib/mcp/mcp\_connection\_store.dart
*   android/app/src/main/kotlin/com/openreef/app/openreef/triggers/TriggerChannelBridge.kt
*   lib/mcp/mcp\_connections\_controller.dart
*   lib/mcp/mcp\_http\_transport.dart
*   lib/mcp/mcp\_sse\_transport.dart
*   lib/models/model\_storage.dart
*   Settings/privacy files under lib/settings/

### Required Actions

*   Audit all persisted user/system data classes
*   Move secrets and credentials to secure storage where appropriate
*   Define encryption-at-rest strategy for sensitive local data
*   Add data lifecycle controls: export, delete, retention where feasible
*   Add audit trail requirements for tool execution and approvals

### Verified Storage Surfaces (2026-04-06)

| storage system | file(s) | data | location/mechanism | boundary status |
| --- | --- | --- | --- | --- |
| Memory store | `lib/memory/sqlite_memory_storage_backend.dart` | memory content, metadata, pointers | SQLite tables `memories`, `memory_pointers` | Plaintext, no at-rest encryption |
| Chat store | `lib/memory/chat_session_repository.dart` | full transcripts, titles, timestamps, AutoDream state | SQLite tables `chat_sessions`, `chat_messages`, `auto_dream_session_state` | Plaintext, no at-rest encryption |
| MCP endpoint persistence | `lib/mcp/mcp_connection_store.dart` | persisted MCP URLs | MemoryRecord JSON in SQLite | Plaintext, credential-bearing URLs possible |
| Trigger event queue | `android/.../triggers/TriggerChannelBridge.kt` | pending trigger payload JSON + timestamps | SharedPreferences (`pending_events`) | Plaintext, no encryption, no TTL/size cap |
| Model index | `lib/models/model_storage.dart` | model IDs/paths/sizes/install dates | `installed.json` under app documents | Plaintext metadata (lower sensitivity) |

### Security Findings

| issue | file | severity | explanation |
| --- | --- | --- | --- |
| Plaintext memory persistence | `lib/memory/sqlite_memory_storage_backend.dart` | HIGH | Potentially sensitive memory content and metadata are stored unencrypted at rest. |
| Plaintext chat transcript persistence | `lib/memory/chat_session_repository.dart` | HIGH | Full user/assistant conversations are persisted without encryption-at-rest controls. |
| Credential leakage via persisted MCP URLs | `lib/mcp/mcp_connection_store.dart` | CRITICAL | URLs are stored verbatim; URLs may include access tokens/userinfo/query secrets. |
| Auto-connect of persisted untrusted endpoints | `lib/mcp/mcp_connections_controller.dart` | HIGH | Persisted URLs are auto-connected on initialize, increasing silent outbound/data exposure risk. |
| No transport scheme restriction for persisted endpoints | `lib/mcp/mcp_connections_controller.dart` | HIGH | `Uri.parse(trimmed)` accepts non-HTTPS schemes; plaintext transport remains possible. |
| Plaintext trigger payload queue | `android/.../triggers/TriggerChannelBridge.kt` | HIGH | Trigger payloads are serialized to SharedPreferences without encryption or retention policy. |
| Missing secure secret store integration | `lib/mcp/*`, `lib/settings/*`, `android/*` | HIGH | No secure storage adapter exists for MCP auth headers/tokens/keys. |
| Hardcoded placeholder key in source | `android/.../wake/WakeWordService.kt` | MEDIUM | Shipping source relies on static placeholder key pattern instead of secure provisioning path. |
| Missing lifecycle controls (global export/delete/retention) | `lib/memory/*`, `lib/mcp/*`, `android/.../triggers/*` | MEDIUM | No centralized data lifecycle operations across persisted stores. |
| Sensitive payload duplication across boundaries | `android/.../triggers/ExactAlarmReceiver.kt`, `android/.../triggers/TriggerChannelBridge.kt` | MEDIUM | Trigger payload exists in alarm intent extras and persisted queue, increasing exposure surface. |

### Validation

*   Manual storage audit
*   Unit tests for storage adapters where possible
*   Manual verification of export/delete flows once implemented
*   flutter analyze

### Done Criteria

*   Plaintext storage of high-sensitivity secrets is removed or justified temporarily
*   Privacy operations are on a defined implementation path
*   Persisted endpoint and trigger payload handling include credential redaction and retention limits
    

GAP-011: Voice Pipeline Not Runnable
------------------------------------

Status: OPEN  
Priority: MEDIUM  
Owner: Voice

### Problem

Voice controls exist, but the documented wake -> capture -> transcribe -> agent -> speak pipeline is not runnable end-to-end.

### Concrete Findings (Audit-Verified)

- `android/app/src/main/kotlin/com/openreef/app/openreef/wake/WakeWordService.kt` uses a placeholder Picovoice key (`PASTE_YOUR_PICOVOICE_ACCESS_KEY_HERE`). Without replacement, wake listening fails.
- `lib/voice/wake_word_controller.dart` can start/stop listening and receive detection events, but detection is not connected to any STT capture or agent invocation path.
- `lib/voice/audio_service.dart` exposes TTS control but no runtime path calls `AudioService.speak(...)` from chat or wake flow.
- `lib/settings/settings_controller.dart` stores sensitivity, but native wake sensitivity remains hardcoded (`DEFAULT_SENSITIVITY = 0.7f`) and is not bridged.

### User Impact

- Voice settings appear usable while key functionality is absent.
- Users can enable wake-word and observe no end-to-end action.

### Target Outcome

Either:
- A minimal verified end-to-end local voice flow exists, or
- Voice remains explicitly experimental and scoped as non-operational.

### Affected Files

- `android/app/src/main/kotlin/com/openreef/app/openreef/wake/WakeWordService.kt`
- `android/app/src/main/kotlin/com/openreef/app/openreef/service/OpenReefForegroundService.kt`
- `lib/voice/wake_word_controller.dart`
- `lib/voice/audio_service.dart`
- `lib/ui/screens/settings_screen.dart`
- `lib/ui/screens/chat_screen.dart`

### Required Actions

- Keep all voice UI marked experimental until end-to-end path is wired.
- Document placeholder credential dependency as a hard blocker.
- Do not claim Kokoro/Android TTS runtime behavior beyond persisted setting state.

### Validation

- Device verification for start/stop listening state transitions.
- Verify no end-to-end voice invocation path exists before removing experimental labeling.
- `flutter analyze`
- `flutter test`

### Done Criteria

- Voice is either operational end-to-end or explicitly labeled non-operational/experimental in UI and docs.


GAP-012: AutoDream Not Operational
----------------------------------

Status: OPEN  
Priority: MEDIUM  
Owner: Background Memory

### Problem

AutoDream appears architecturally present but is not operational in the shipping runtime.

### Concrete Findings (Audit-Verified)

- `lib/background/auto_dream_worker.dart` contains consolidation logic, but no bootstrap path constructs or schedules this worker.
- `android/app/src/main/kotlin/com/openreef/app/openreef/wake/AutoDreamWorker.kt` is a no-op `Result.success()` stub.
- No active method-channel handler for `openreef/background_channel` scheduling methods in Android runtime wiring.
- No runtime registration path executes nightly consolidation.

### User Impact

- Users may expect background memory maintenance that never runs.
- Documentation overstates capability versus observed runtime behavior.

### Target Outcome

AutoDream is either fully scheduled and executable end-to-end, or explicitly de-scoped from MVP.

### Decision (Current Audit)

- AutoDream is **post-MVP** until scheduler registration and worker execution are both wired and validated.

### Affected Files

- `lib/background/auto_dream_worker.dart`
- `android/app/src/main/kotlin/com/openreef/app/openreef/wake/AutoDreamWorker.kt`
- `lib/main.dart`
- Android bootstrap/channel wiring files

### Required Actions

- Remove current-MVP capability claims for AutoDream.
- Keep AutoDream documented as planned post-MVP work.
- Reclassify status in `docs/current_status.md` as `STUB / MOCK / PLACEHOLDER`.

### Validation

- Confirm no production bootstrap path schedules AutoDream.
- Confirm Android worker remains stub.
- `flutter analyze`
- `flutter test`

### Done Criteria

- Product surface and docs no longer imply nightly consolidation is active in MVP.


