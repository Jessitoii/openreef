# Architecture Principles

## Non-negotiable principles

1. **One engine**: all execution sources route through a single executor.
2. **One shared loop**: iterative reasoning and tool actions use one loop contract.
3. **Explicit lifecycle semantics**: modes and state transitions are data-model driven.
4. **Policy over prompt magic**: runtime legality comes from `ExecutionPolicy`, not hidden prompt behavior.
5. **Truthful maturity labels**: partial systems are documented as partial.
6. **Single dispatch boundaries**: all tools run through one router with normalized results.
7. **Authoritative ownership**: each concept has one canonical documentation file.
8. **No second runtime path**: no alternate engine for triggers, voice, or skills.
