---
name: integration-review
description: Cross-module conflict, information-leak, and optimization review — used by the Tech Lead agent after all modules in a phase pass QA, before PM's checkpoint for that phase.
---

<objective>
Verify that all modules in the current phase work together safely — no conflicts between modules, no information leakage across module/tenant boundaries — and surface genuine optimization opportunities. Every finding is a proposal, not a fix. Tech Lead never implements here, same as everywhere else.
</objective>

<essential_principles>
- **Advisory only**: every finding is a row in `project-planning/integration-review.md`; the human decides what gets approved. Never implement a fix yourself.
- **Conflicts and leaks are Concerns; optimizations are Recommendations** — the same severity split Tech Lead already uses in `status.md` reviews.
- **Boundary leakage is not just the database.** Check caches, logs, exports, background jobs, and shared config for missing module/tenant context too — a module can leak data through a shared cache key or log line just as easily as through a query.
- **Every finding needs a specific location and a concrete failure scenario.** "Modules might conflict" is not a finding. "MOD-002's migration `003_add_index.sql` and MOD-004's `003_seed_data.sql` share the timestamp prefix `003` — apply order is undefined" is.
- **Scope discipline**: if a finding actually implies a change to user-facing requirements, it does not belong here — escalate to PM's change flow instead of tracking it as an integration-review item.
- **Never edit source code or any planning doc** other than `project-planning/integration-review.md` and the Tech Lead Reviews section of `status.md`.
</essential_principles>

<routing>
| Task | Action |
| --- | --- |
| First review for a phase (all modules just passed QA) | Follow `workflows/phase-review.md` |
| Re-invoked to close out an approved, fixed item | Follow `workflows/confirm-fix.md` |
| Need the conflict/leak checklist | Read `references/cross-module-checklist.md` |
| Deciding if something is a worthwhile optimization proposal | Read `references/optimization-criteria.md` |
| `project-planning/integration-review.md` doesn't exist yet | Copy `templates/integration-review.tmpl.md` |
| Automated first-pass scan | Run `scripts/scan-integration.sh <project-root>` |
</routing>

<quick_start>
1. Read every module's `spec.md` and `status.md` for modules in the current phase.
2. Run `scripts/scan-integration.sh <project-root>` for an automated first pass.
3. Apply `references/cross-module-checklist.md` for conflicts/leaks and `references/optimization-criteria.md` for optimizations.
4. Write findings as new `PROPOSED` rows in `project-planning/integration-review.md` (create from template if missing).
5. Write a short summary + pointer in `status.md` Tech Lead Reviews so PM's checkpoint gate can find it.
</quick_start>

<success_criteria>
- Every module in the current phase has been read in full, not skimmed.
- `scripts/scan-integration.sh` has been run and its output considered.
- Every finding has: category (Conflict / Leak / Optimization), a specific location, a concrete failure scenario, and — for optimizations — a stated trade-off.
- `project-planning/integration-review.md` is updated with new `PROPOSED` rows, or carries an explicit "no issues found" note if there are none.
- `status.md` Tech Lead Reviews has a pointer to the review (PM's checkpoint gate looks for this).
- Git commit: `git add project-planning/integration-review.md project-planning/status.md && git commit -m "tech-lead(integration-review): <summary>"`
</success_criteria>
