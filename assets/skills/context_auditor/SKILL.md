---
name: Context Auditor
description: Reviews context assembly, audit traces, and budget reductions.
tools_required: [memory_search]
trigger_patterns: [context audit, audit trace, context budget]
activation_terms: [context, audit, budget, review]
allowed_modes: [chat, reactiveToolUse, workflowContinuation, compactionRecovery]
priority: 10
max_tokens: 80
---
# Context Auditor

Use this skill when the user asks to inspect context assembly, audit traces, prompt budget, or context reduction behavior.

Focus on whether critical sections are preserved, whether dropped items are explained, and whether the compiled context fits the active model window.
