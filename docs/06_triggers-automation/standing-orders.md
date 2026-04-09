# Standing Orders

## Purpose
Define standing orders as runtime data, not prompt prose.

## Core Data Models
`StandingOrderRule`: `ruleId`, `enabled`, `matchPredicate`, `actionDirective`, `priority`, `applicableTriggerTypes`.

## Constraints
- Rules must be machine-evaluable and auditable.
- Freeform text injection is non-authoritative.

## Execution Flow
1. Load enabled rules.
2. Evaluate predicates against normalized trigger event.
3. Attach directives to triggered request construction.
4. Record applied/skipped rules.
