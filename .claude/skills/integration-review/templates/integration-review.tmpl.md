# Integration & Optimization Review

<!-- Created by Tech Lead on the first phase-end review. One row per finding — never
     embed findings inline in module status.md files. Status transitions are split by
     owner, mirroring modules/*/status.md:
       - Tech Lead owns: PROPOSED, NO ISSUES, SPLIT, CONFIRMED CLOSED — and records the human's
         decisions (APPROVED / REJECTED / DEFERRED, plus Assigned Module) and the human's
         verification (HUMAN VERIFIED) exactly as the human states them
       - Engineer owns:  IN PROGRESS, FIXED – AWAITING QA (only on rows assigned to it)
       - QA owns:        QA VERIFIED (or sends back with a note)
     A finding that implies a user-facing requirement change does not belong here —
     it should have been escalated to PM's change flow instead. -->

## Status Legend

`PROPOSED` → `APPROVED` / `REJECTED` / `DEFERRED` → `IN PROGRESS` → `FIXED – AWAITING QA` → `QA VERIFIED` → `HUMAN VERIFIED` → `CONFIRMED CLOSED`

PM's checkpoint gate for a phase requires every row in the file — any phase — to be `CONFIRMED CLOSED`, `REJECTED`, `DEFERRED`, `SPLIT` (replaced by its letter-suffixed rows), or `NO ISSUES`. Any row in between (`PROPOSED` through `HUMAN VERIFIED`) is still open and blocks the checkpoint. Concerns and Recommendations are gated the same way — every Recommendation needs an explicit approve, reject, or defer too; severity doesn't change the mechanism, only how much scrutiny the human gives before deciding. A `DEFERRED` row stops blocking its own phase but is listed again in every later phase's review until the human approves or rejects it.

## Findings

| ID | Phase | Category | Description | Location | Tech Lead Rationale & Trade-offs | Status | Assigned Module | Notes |
|---|---|---|---|---|---|---|---|---|
<!-- Example row:
| INT-000 | 1 | Conflict | mod-a and mod-b migrations share timestamp prefix 003 with undefined apply order | supabase/migrations/003_*.sql (both modules) | Apply order is filesystem-dependent; could silently corrupt schema on a fresh clone. Fix: renumber one migration. Low cost, no behavior change. | PROPOSED | | |
-->
