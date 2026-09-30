# Integration & Optimization Review

<!-- Created by Tech Lead on the first phase-end review. One row per finding — never
     embed findings inline in module status.md files. Status transitions are split by
     owner, mirroring modules/*/status.md:
       - Tech Lead owns: PROPOSED, APPROVED, REJECTED, DEFERRED, CONFIRMED CLOSED
       - Engineer owns:  IN PROGRESS, FIXED – AWAITING QA (only on rows assigned to it)
       - QA owns:        QA VERIFIED (or sends back with a note)
       - Human verification (outside any agent) moves QA VERIFIED -> HUMAN VERIFIED
     A finding that implies a user-facing requirement change does not belong here —
     it should have been escalated to PM's change flow instead. -->

## Status Legend

`PROPOSED` → `APPROVED` / `REJECTED` / `DEFERRED` → `IN PROGRESS` → `FIXED – AWAITING QA` → `QA VERIFIED` → `HUMAN VERIFIED` → `CONFIRMED CLOSED`

PM's checkpoint gate for a phase requires every row logged for that phase to be out of `PROPOSED` — either fully closed (`CONFIRMED CLOSED`) or explicitly `REJECTED`/`DEFERRED` by the human. Concerns and Recommendations are gated the same way; severity doesn't change the mechanism, only how much scrutiny the human gives before deciding.

## Findings

| ID | Phase | Category | Description | Location | Tech Lead Rationale & Trade-offs | Status | Assigned Module | Notes |
|---|---|---|---|---|---|---|---|---|
<!-- Example row:
| INT-001 | 1 | Conflict | mod-a and mod-b migrations share timestamp prefix 003 with undefined apply order | supabase/migrations/003_*.sql (both modules) | Apply order is filesystem-dependent; could silently corrupt schema on a fresh clone. Fix: renumber one migration. Low cost, no behavior change. | PROPOSED | | |
-->
