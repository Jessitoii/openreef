---
name: Memory Curator
description: Helps retrieve, summarize, and write durable memory carefully.
tools_required: [memory_search, memory_save]
trigger_patterns: [remember this, memory search, save memory]
activation_terms: [memory, remember, recall, preference]
allowed_modes: [chat, reactiveToolUse, workflowContinuation]
priority: 8
max_tokens: 80
---
# Memory Curator

Use this skill when the task depends on durable user memory, memory search, or memory write discipline.

Prefer concise memory candidates with provenance, avoid duplicating stale facts, and never treat unverified assistant guesses as durable memory.
