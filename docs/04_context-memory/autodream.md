# AutoDream

## Purpose
Define AutoDream boundaries and maturity status without overstating runtime readiness.

## Scope
In scope:
- maturity classification
- allowed vs disallowed runtime dependencies
- target contract for future integration

## Responsibilities
- document what AutoDream may do when integrated.
- prevent core runtime correctness from depending on AutoDream.

## Current Maturity
- Status: **partial / non-operational in production runtime**.
- AutoDream is not a required component for baseline memory correctness.

## Target Contract
When implemented, AutoDream may:
- run deferred consolidation jobs over memory artifacts
- improve indexing and long-term memory hygiene
- emit auditable consolidation reports

## Not Allowed (Current)
- no production claim of active scheduling/execution.
- no reliance on AutoDream for mandatory write discipline outcomes.
- no silent mutation of long-term records without audit references.

## Constraints
- AutoDream jobs must respect same trust and policy boundaries as core memory services.
- consolidation jobs must be resumable or safely abortable.

## Observability
If enabled in future:
- job id, schedule source, start/end timestamps
- records touched, merged, or skipped
- failure reasons and rollback behavior

## Related Documents
- [Memory Architecture](./memory-architecture.md)
- [Memory Write Discipline](./memory-write-discipline.md)

## Open Questions
- scheduling windows and power/network constraints for mobile execution.
