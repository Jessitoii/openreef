Objective
---------

Transform OpenReef from a fragmented prototype into a cohesive, production-grade agent platform.

Guiding Principles
------------------

*   One production runtime path
    
*   Vertical completion over horizontal expansion
    
*   No UI without working backend
    
*   No placeholders in core systems
    
*   Every feature must be testable
    

Phase 0 — Project Discipline
----------------------------

*   Create and maintain roadmap, status, decisions, gap tracker
    
*   Enforce branch strategy
    
*   Enforce scoped Codex tasks
    

Done when:

*   All docs exist and are actively updated
    

Phase 1 — Runtime Consolidation
-------------------------------

Goal: Establish a single production inference + agent execution path

Tasks:

*   Select primary inference path (LiteRT or Dart wrapper)
    
*   Remove or isolate secondary path
    
*   Define unified agent execution flow
    

Done when:

*   Only one runtime path is used in production
    
*   No duplicate execution logic exists
    

Phase 2 — Agent Core Stabilization
----------------------------------

Goal: Make agent loop reliable and safe

Tasks:

*   Implement circuit breaker
    
*   Implement mailbox-based approval system
    
*   Implement 3-layer context compaction
    
*   Normalize tool execution loop
    

Done when:

*   No infinite loops
    
*   Tool failures handled safely
    
*   Approval required tools are gated correctly
    

Phase 3 — Memory Engine
-----------------------

Goal: Real semantic memory system

Tasks:

*   Replace keyword scan with vector search
    
*   Implement MEMORY.md pointer index
    
*   Implement after-turn memory extraction
    
*   Enforce strict write discipline
    

Done when:

*   Memory retrieval works semantically
    
*   Failed turns do not pollute memory
    

Phase 4 — Skills Runtime
------------------------

Goal: Skills affect agent behavior

Tasks:

*   Implement skill registry
    
*   Implement skill gating
    
*   Inject active skills into context
    

Done when:

*   Installed skills influence agent output
    

Phase 5 — Trigger System
------------------------

Goal: Automation engine executes agent tasks

Tasks:

*   Implement SCHEDULE, INTERVAL, BOOT, MANUAL triggers
    
*   Connect triggers to agent execution
    

Done when:

*   Trigger fires result in real agent actions
    

Phase 6 — MCP Integration
-------------------------

Goal: External tool ecosystem integration

Tasks:

*   Implement tool discovery
    
*   Merge MCP tools into registry
    
*   Connect MCP events to triggers
    

Done when:

*   MCP tools usable by agent
    

Phase 7 — Native Tools MVP
--------------------------

Goal: Real device control capabilities

Tasks:

*   Implement core tool set (phone, sms, files, clipboard)
    
*   Integrate permissions and confirmations
    

Done when:

*   Agent can execute real device actions
    

Phase 8 — UI Productization
---------------------------

Goal: UI reflects real system capabilities

Tasks:

*   Approval dialogs
    
*   Trigger management UI
    
*   Skill management UI
    
*   MCP onboarding UI
    

Done when:

*   No misleading UI
    

Phase 9 — Security & Reliability
--------------------------------

Goal: Production readiness

Tasks:

*   Secure storage
    
*   Audit logging
    
*   Performance optimizations
    
*   Test coverage
    

Done when:

*   System is stable and secure
    

Phase 10 — Advanced Features
----------------------------

Goal: Extend capabilities

Tasks:

*   Voice pipeline
    
*   AutoDream
    
*   Advanced multi-agent
    

Done when:

*   Core system remains stable under extensions