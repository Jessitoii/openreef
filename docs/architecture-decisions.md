ADR-001: Single Runtime Path
----------------------------

Status: ACCEPTED (for current codebase)

Current State

- Production runtime implementation is Dart-side:
  - `lib/models/litert_bridge.dart` using `flutter_gemma`.
- The reachable production call chain is Dart-side:
  - `lib/main.dart` initializes `FlutterGemma`, creates `LiteRtBridge`, and injects `LiteRtAgentModelAdapter`.
  - User prompt flow is `chat_screen.dart` -> `chat_workspace_controller.dart` -> `agent_loop_chat_session.dart` -> `agent_loop.dart` -> `agent_model_adapter.dart` -> `litert_bridge.dart`.
- Kotlin LiteRT runtime bridge has been removed from the app module (GAP-001 Task 3).

Decision

- Use a single production runtime path: Dart-side `LiteRtBridge` backed by `flutter_gemma`.

Rationale

- This is the only end-to-end path currently wired into agent execution and chat UX response delivery.
- Keeping the currently wired path avoids behavior change while resolving ownership ambiguity.

Consequences

- Primary files to keep as production path:
  - `lib/main.dart`
  - `lib/models/litert_bridge.dart`
  - `lib/agent/agent_model_adapter.dart`
  - `lib/agent/agent_loop.dart`
  - `lib/ui/agent_loop_chat_session.dart`
- `MainActivity` contains no LiteRT runtime registration.
- No secondary production runtime path remains in the app module after Task 3 cleanup.

ADR-002: Mailbox Approval System
--------------------------------

Status: REQUIRED

Current State

- Main-agent and sub-agent approvals now present the same user-visible policy: every manifest-specified `requiresConfirmation` tool waits for an approve/reject decision.
- `lib/main.dart` wires `MainAgentApprovalController.confirmToolCall`, so the main-agent flow still relies on the session/controller callback path that feeds the chat UI.
- `lib/agent/mailbox.dart` owns the sub-agent approval queue, publishes timeout/reject resolutions, and guarantees mailbox cleanup when a request is approved, rejected, or times out.
- `ToolRouter` distinguishes only between main/sub sessions; the policy remains manifest-driven while routing sub-agent calls through the mailbox back to the same approval UX.

Decision

- Approval policy is consistent across both main-agent and sub-agent paths: `requiresConfirmation` always means the user or mailbox resolves the call before execution.
- Sub-agent approval is mailbox-owned, including timeout-driven rejection and cleanup of pending state.
- Main-agent approval currently uses the session/controller callback path that renders the chat-surface card, so approval state remains outside the widget tree.
- Full internal plumbing unification remains a longer-term architectural direction, but the current implementation already satisfies the documented policy requirements for GAP-007 closure.

Rationale

- The chat session keeps approval state localized while the mailbox ensures sub-agent determinism.
- Keeping the policy flag manifest-driven prevents implicit bypasses when new tools are added.

Consequences

- Future work may still unify the plumbing, but the current split is documented explicitly for maintainers.
ADR-003: Semantic Memory
------------------------

Status: REQUIRED

Decision:Memory must use vector-based retrieval.

Rationale:Keyword matching is insufficient.

ADR-004: Progressive Skill Injection
------------------------------------

Status: REQUIRED

Decision:Only relevant skills are injected into context.

Rationale:Prevents context overload.

ADR-005: Trigger → Agent Execution
----------------------------------

Status: REQUIRED

Decision:Triggers must execute agent tasks, not standalone actions.

Rationale:Maintains consistent behavior.

ADR-006: Agent Loop Hardening Policy
------------------------------------

Status: ACCEPTED

Current State

- `lib/agent/agent_loop.dart` enforces bounded loop execution with blocked fingerprint tracking plus an iteration cap so rejected/no-progress loops and repeated exception loops freeze deterministically.
- `AgentLoopResult` now carries `SessionResult.completed`, `SessionResult.frozen`, and `SessionResult.failed`, with `reason` strings populated for `generation_failure`, `compaction_failure`, and safety stops.
- `_applyCompaction(...)` catches summarizer failures, compacts tool errors, and still returns consistent context via `_safeSummarize()`/`_fallbackSummary()` so compaction no longer escapes the guarded failure path.

Decision

- Keep loop execution bounded by fingerprint no-progress detection plus deterministic scaffolding so repeated blocked steps freeze instead of looping.
- Maintain deterministic terminal states and preserve the `reason` field for external consumers.
- Continue treating compaction as loop-integrated but guard it with safe summarization fallbacks and metadata to avoid unhandled failures.

Rationale

- Blocking repeated stuck patterns keeps the agent responsive without new architectural layers.
- Deterministic states let UI/activity telemetry and future safety surfaces reason about terminal outcomes.
- Safe compaction ensures long conversations can still shrink history without crashing the loop.

Consequences

- The implemented guard rails stay as current production behavior.
- Compaction fallbacks now belong to `lib/context/compactor.dart`, and token accounting elsewhere only surfacing adjustments if absolutely required.
- GAP-002 is now closed, so changes to this ADR must preserve the implemented protections before reopening the gap.
ADR-007: MCP Secret Boundary and Endpoint Trust
-----------------------------------------------

Status: ACCEPTED

Current State

- `lib/mcp/mcp_connection_store.dart` persists MCP endpoints as stable ids plus sanitized endpoint descriptors instead of raw URLs.
- MCP secrets are stored only through the platform-backed secret store wired in `lib/mcp/mcp_secret_store.dart` and Android `MainActivity` / `OpenReefSecureStore.kt`.
- `lib/mcp/mcp_connections_controller.dart` loads persisted endpoints as disconnected state first and only auto-connects trusted endpoints.
- `lib/mcp/mcp_sse_transport.dart` validates negotiated POST endpoints so the announced write endpoint cannot silently cross origin or downgrade transport trust.

Decision

- Secrets are never persisted in plaintext MCP endpoint records.
- Keystore-backed secure storage is the only valid persistence location for MCP secrets.
- Persisted endpoint descriptors use a stable internal id and must not use normalized URLs as identifiers.
- Trust is explicit: only endpoints that pass validation and are persisted by user action are eligible for trusted reconnect behavior.
- Legacy credential-bearing endpoints migrate conservatively; if extraction is not lossless, reconnect requires manual secret re-entry rather than silent semantic changes.

Rationale

- Raw credential-bearing URLs created an avoidable local secret-leak boundary.
- Separating stable identity, sanitized descriptor data, and secure secret material keeps reconnect functional without persisting high-sensitivity fields in plaintext.
- Explicit trust prevents silent outbound connections to legacy or partially migrated endpoints.

Consequences

- Persisted MCP reconnect behavior is stricter than before, especially for legacy endpoints.
- Some legacy endpoints now require manual secret re-entry after migration when exact reconstruction is not provably lossless.
- Broader encryption-at-rest work for chat and memory remains outside this ADR and GAP-010 Phase 1 scope.
