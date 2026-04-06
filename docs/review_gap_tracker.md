Usage Rules
-----------

*   One gap can map to multiple files.
    
*   A gap is not done until code, validation, and documentation are all updated.
    
*   Placeholder replacements are not complete unless wired into the production runtime.
    
*   Every closed gap must include tests or an explicit reason why test coverage is not yet possible.
    

GAP-001: Multiple Runtime Paths
-------------------------------

Status: OPENPriority: CRITICALOwner: Core Runtime

### Problem

Multiple inference/runtime paths exist, creating duplicated architecture and unclear production behavior.

### User Impact

*   Debugging becomes ambiguous
    
*   Performance behavior is inconsistent
    
*   Future feature work risks attaching to the wrong runtime path
    

### Target Outcome

One clearly defined production inference path and one agent execution path.

### Affected Files

*   lib/models/litert\_bridge.dart
    
*   android/app/src/main/kotlin/\*\*/LiteRtLmBridge.kt
    
*   lib/main.dart
    
*   Any bootstrap/service files selecting model runtime
    

### Required Actions

*   Audit every runtime entrypoint and document current usage
    
*   Choose the production runtime path
    
*   Remove, isolate, or hard-deprecate the non-production path
    
*   Ensure app bootstrap uses only the chosen runtime
    
*   Update docs to reflect the final runtime decision
    

### Validation

*   flutter analyze
    
*   Run app bootstrap and verify only one runtime path initializes
    
*   Smoke-test one full prompt → response cycle
    

### Done Criteria

*   Only one runtime path is reachable in production code
    
*   No duplicate bootstrap logic remains
    
*   Architecture decision doc updated
    

GAP-002: Broken Agent Loop
--------------------------

Status: OPENPriority: CRITICALOwner: Agent Core

### Problem

The main loop lacks robust error handling, bounded retry behavior, and proactive compaction safeguards.

### User Impact

*   Risk of stuck sessions
    
*   Risk of runaway loops and battery drain
    
*   Poor recovery from tool-call failures
    

### Target Outcome

A bounded, recoverable, production-safe agent loop.

### Affected Files

*   lib/agent/agent\_loop.dart
    
*   lib/context/compactor.dart
    
*   lib/agent/session\_result.dart
    
*   lib/agent/tool\_router.dart
    

### Required Actions

*   Add circuit breaker for consecutive failures
    
*   Add tool error appending path to context
    
*   Add multi-layer compaction checks inside the loop
    
*   Add frozen/error terminal states where missing
    
*   Ensure loop exits cleanly on unrecoverable failure
    

### Validation

*   Unit tests for failure threshold behavior
    
*   Unit tests for tool error recovery path
    
*   Unit tests for compaction trigger thresholds
    
*   flutter analyze
    

### Done Criteria

*   Loop cannot run indefinitely on repeated tool failure
    
*   Compaction is triggered before context failure
    
*   Session state is visible and deterministic
    

GAP-003: Weak Memory System
---------------------------

Status: OPENPriority: CRITICALOwner: Memory

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

Status: OPENPriority: HIGHOwner: Skills Runtime

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

Status: OPENPriority: HIGHOwner: Automation

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
    
*   Unit tests for trigger fire → task execution path
    
*   Manual test: scheduled trigger results in visible agent task
    
*   flutter analyze
    

### Done Criteria

*   Trigger fires produce real execution
    
*   Trigger state can be inspected
    
*   Trigger system is not dead plumbing
    

GAP-006: MCP Not Integrated
---------------------------

Status: OPENPriority: HIGHOwner: MCP

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

Status: OPENPriority: CRITICALOwner: Agent Safety

### Problem

Sensitive tools are either hard-rejected, bypass confirmation, or can stall forever.

### User Impact

*   Sensitive actions are unusable or unsafe
    
*   Sub-agent workflows can deadlock
    

### Target Outcome

A single approval system that works for main-agent and sub-agent paths.

### Affected Files

*   lib/main.dart
    
*   lib/agent/tool\_router.dart
    
*   lib/agent/mailbox.dart
    
*   lib/agent/subagent/ files
    
*   lib/ui/ files responsible for approval UX
    

### Required Actions

*   Add mailbox request/resolve flow
    
*   Route all requiresConfirmation tools through the same policy path
    
*   Replace hardcoded rejection with real user approval UI
    
*   Add timeout/reject handling for unresolved requests
    
*   Ensure sub-agent approvals return to parent/main flow correctly
    

### Validation

*   Unit tests for main-agent approval
    
*   Unit tests for sub-agent approval + reject + timeout
    
*   Manual test with one sensitive tool call from main and sub-agent
    
*   flutter analyze
    

### Done Criteria

*   Sensitive tools never bypass policy
    
*   Approval requests are resolvable and do not hang forever
    

GAP-008: UI Misalignment
------------------------

Status: OPENPriority: HIGHOwner: Product Surface

### Problem

The UI communicates capabilities that the runtime does not actually provide.

### User Impact

*   Product feels deceptive or broken
    
*   Users cannot distinguish real features from placeholders
    

### Target Outcome

UI truthfully reflects implemented capabilities and operational state.

### Affected Files

*   lib/ui/app\_shell.dart
    
*   lib/ui/settings\_screen.dart
    
*   lib/ui/skills\_screen.dart
    
*   lib/ui/mcp\_connections\_screen.dart
    
*   Any future trigger or approval screens
    

### Required Actions

*   Remove or relabel cosmetic/incomplete controls
    
*   Add missing approval UI where required
    
*   Add trigger management surface only once backend exists
    
*   Add runtime status messaging for voice, MCP, skills, and automation
    
*   Prevent non-functional settings from looking production-ready
    

### Validation

*   Manual UX review against backend reality
    
*   Widget/screen tests where practical
    
*   flutter analyze
    

### Done Criteria

*   No visible feature claims exceed implemented backend behavior
    
*   Critical runtime states are visible to users
    

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

*   lib/mock\_chat\_session.dart
    
*   lib/background/auto\_dream\_worker.dart
    
*   android/app/src/main/kotlin/\*\*/AutoDreamWorker.kt
    
*   android/app/src/main/kotlin/\*\*/WakeWordService.kt
    
*   Any stub summarizer or no-op production service files
    

### Required Actions

*   Inventory placeholder files and classify as remove / replace / isolate
    
*   Remove mock use from production paths
    
*   Replace stub logic where the feature is being kept in MVP scope
    
*   Mark unfinished features experimental if they cannot yet be completed
    

### Validation

*   Search repo for known placeholder markers
    
*   Manual runtime verification that no mock path is used in production startup
    
*   flutter analyze
    

### Done Criteria

*   Production startup and core runtime do not rely on mocks/stubs/no-ops
    
*   Remaining placeholders are clearly isolated from shipping paths
    

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
    
*   lib/chat/chat\_session\_repository.dart
    
*   lib/mcp/mcp\_connection\_store.dart
    
*   Settings/privacy files under lib/settings/
    
*   Any secure storage bridge files
    

### Required Actions

*   Audit all persisted user/system data classes
    
*   Move secrets and credentials to secure storage where appropriate
    
*   Define encryption-at-rest strategy for sensitive local data
    
*   Add data lifecycle controls: export, delete, retention where feasible
    
*   Add audit trail requirements for tool execution and approvals
    

### Validation

*   Manual storage audit
    
*   Unit tests for storage adapters where possible
    
*   Manual verification of export/delete flows once implemented
    
*   flutter analyze
    

### Done Criteria

*   Plaintext storage of high-sensitivity secrets is removed or justified temporarily
    
*   Privacy operations are on a defined implementation path
    

GAP-011: Voice Pipeline Not Runnable
------------------------------------

Status: OPENPriority: MEDIUMOwner: Voice

### Problem

Wake-word and voice interaction are documented as full flows, but the current implementation is blocked by placeholders and missing execution steps.

### User Impact

*   Voice settings appear fake
    
*   Wake-word feature cannot be trusted
    

### Target Outcome

A minimal runnable wake → capture → transcribe → agent → speak flow, or explicit experimental isolation.

### Affected Files

*   android/app/src/main/kotlin/\*\*/WakeWordService.kt
    
*   lib/voice/audio\_service.dart
    
*   Wake-word bridge/service files under lib/voice/
    
*   Relevant settings UI files
    

### Required Actions

*   Remove hardcoded placeholder credential assumptions from shipping path
    
*   Implement actual detection success/failure reporting
    
*   Wire detection to transcript/invocation flow or mark feature experimental/off
    
*   Align TTS engine behavior with real supported engines
    

### Validation

*   Manual device test for start/stop/result states
    
*   Unit tests for state transitions where possible
    
*   flutter analyze
    

### Done Criteria

*   Voice path is either honestly disabled or minimally functional end-to-end
    

GAP-012: AutoDream Not Operational
----------------------------------

Status: OPENPriority: MEDIUMOwner: Background Memory

### Problem

Nightly consolidation is documented but currently stubbed on both Dart and Android sides.

### User Impact

*   Memory system lacks background maintenance
    
*   Documentation overstates capability
    

### Target Outcome

A real scheduled consolidation worker or explicit de-scoping from MVP.

### Affected Files

*   lib/background/auto\_dream\_worker.dart
    
*   android/app/src/main/kotlin/\*\*/AutoDreamWorker.kt
    
*   Work registration/bootstrap files
    
*   lib/memory/ integration points
    

### Required Actions

*   Decide whether AutoDream is MVP or post-MVP
    
*   If MVP: implement scheduler registration, gate checks, and minimal consolidation path
    
*   If not MVP: remove product claims and isolate code as planned future work
    

### Validation

*   Manual verification that worker is scheduled or explicitly disabled
    
*   Unit tests for gate logic where possible
    
*   flutter analyze
    

### Done Criteria

*   AutoDream is either real or honestly removed from current product scope