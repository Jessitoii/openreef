# 03  Core Agent Engine

## Agent Loop
The Agent Loop has been enhanced based on the Claude Code leak to prevent infinite failure loops and handle token limits gracefully.

### The Loop Logic (v0.3)
```dart
AgentLoop.run(userMessage, {required String sessionKey}):
  context = contextEngine.assemble(...)
  response = litert.generate(context)
  
  int _consecutiveErrors = 0;
  const int _MAX_ERRORS = 3;        // [1] Circuit Breaker
  
  while response.hasToolCall:
    // ─── [1] Circuit Breaker ──────────────────────────────
    if (_consecutiveErrors >= _MAX_ERRORS) {
      await _freezeSession('circuit_breaker');
      await notify.send(title: 'Session Frozen', body: '3 consecutive errors occurred.');
      return SessionResult.frozen;
    }
    
    // ─── [2] 3-Layer Compaction ───────────────────────────
    final budget = contextEngine.estimateTokens(context);
    
    if (budget.oldToolResults > 0)
      context = compactor.microCompact(context);
      
    if (budget.ratio > 0.80)
      context = await compactor.autoCompact(context, reserveTokens: 2000, maxSummaryTokens: 4000);
      
    if (budget.remaining < 1500 || session.compactRequested)
      context = await compactor.fullCompact(context, reInjectRecentFiles: true, reInjectActiveSkills: true);
      
    // ─── [3] Mailbox Pattern ──────────────────────────────
    toolCall = response.extractToolCall()
    try {
      result = await toolRouter.dispatch(toolCall, sessionKey: sessionKey);
      context.appendToolResult(toolCall.id, result)
      _consecutiveErrors = 0;     
    } catch (e) {
      _consecutiveErrors++;
      context.appendToolError(toolCall.id, e);
    }
    response = litert.generate(context)
    
  contextEngine.afterTurn(turn)
  return response.text
```

## Context Engine: 4-Step Assembly Pipeline
The Context Engine decides what the model sees on every inference call to manage the context window effectively.

| Step | Name | Logic |
| :--- | :--- | :--- |
| **1** | **Intent Detection** | `queryVec = MiniLM.embed(userMessage)`. Compare against pre-computed intent cluster centroids. |
| **2** | **Tool Selection** | Deterministic cosine similarity routing. Select top 8 tools. Hard overrides: always include `session_status`, enforce confirmation tools. |
| **3** | **Skill Gating** | Keyword match. If any pattern matches, inject `SKILL.md` (max 2 skills, ~150 tok each). |
| **4** | **Budget Allocation** | Allocate remaining context: 60% conversation history, 30% memory retrieval, 10% standing orders. Reserve 1024 tokens for output. |

## Context Compaction
A 3-layer compaction architecture proactively manages the API context limit to prevent exhaustion.

| Layer | Trigger | API Call? | Cost |
| :--- | :--- | :--- | :--- |
| **MicroCompact** | Old tool results (> 5 turns) | No | < 5ms, battery friendly |
| **AutoCompact** | Budget > 80% full | Yes (`llm_task`) | ~500ms, asynchronous |
| **FullCompact** | < 1500 tok remain OR `/compact` | Yes (`llm_task`) | ~1-2s, rare |

## Memory Architecture

| Store | TTL | Storage | Purposes |
| :--- | :--- | :--- | :--- |
| **Short-Term** | 24 hours | SQLite (no vector) | Recent facts, tool results. |
| **Long-Term** | Permanent | `sqlite-vec` | User preferences, important facts. |
| **Episodic** | 30 days | SQLite | Conversation summaries (compact blocks). |
| **Skill State** | Permanent | SQLite + JSON | Per-skill persistent state (e.g. streaks). |

### MEMORY.md Pointer Pattern
To prevent "context entropy," a lightweight index (`MEMORY.md`) is always loaded in the system prompt. It costs ~100 tokens and points to larger memories, allowing the model to know what information it can retrieve.
```markdown
[MEMORY INDEX]
user_prefs      → memory:prefs_2026
health_data     → memory:health_log
contacts_key    → memory:contacts_vip
work_context    → memory:work_projects
[END INDEX]
```

### Strict Write Discipline
Memory is only saved after a *successful* tool call. Failed tool calls are skipped during the `MemoryFormer.process(turn)` fact extraction step to prevent memory corruption.

### AutoDream Worker
A nightly background job (via `WorkManager`) that runs to consolidate memory: resolves contradictory memories across sessions, turns ambiguous notes into facts, and prunes expired/low-importance tokens. It implements a 3-gate condition (Time, Session, Lock gates) before running to save battery.
