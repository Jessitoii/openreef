# Migration Plan

## Purpose
Record controlled migration from `docs/intermediate-system-spec.md` into canonical multi-file structure.

## Steps
1. Preserve intermediate file as migration source.
2. Map concepts to authoritative files via `docs/00_meta/doc-map.md`.
3. Split contracts into domain files.
4. Remove duplicated contract details from non-authoritative files.
5. Route unresolved architecture decisions to `docs/90_decisions/README.md`.
6. Route partial implementation coverage items to `docs/99_gaps/README.md`.
7. Mark intermediate file as superseded.

## Validation
- No concept orphaned.
- No duplicate authoritative ownership.
- No reintroduction of deprecated runtime assumptions.
