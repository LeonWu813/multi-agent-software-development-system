# Phase-End Integration & Optimization Review

Run this the first time Tech Lead is invoked for a phase — i.e. all modules in the current phase have `PASS` in their `status.md` QA Results, and PM has not yet run checkpoint mode for that phase.

1. Read `project-planning/status.md` — confirm the current phase and which modules belong to it (Module Map + Phase Plan).
2. Read every module's `spec.md` and `status.md` for modules in the current phase, in full. Do not sample — a conflict between two modules is invisible if you only read one of them.
3. Read `project-planning/production.md` Shared Conventions and Tech Stack — this is the baseline every module should already follow; deviations between modules are a common source of conflicts.
4. Run the automated first pass:
   ```bash
   bash ~/.claude/skills/integration-review/scripts/scan-integration.sh <project-root>
   ```
   Treat its output as a lead list, not a verdict — every hit still needs manual judgment before becoming a finding.
5. Work through `references/cross-module-checklist.md` for conflicts and information leakage.
6. Work through `references/optimization-criteria.md` for optimization opportunities. Skip anything that fails the criteria there — do not log speculative or stylistic suggestions.
7. If `project-planning/integration-review.md` does not exist yet, create it from `templates/integration-review.tmpl.md`.
8. For each finding, append a row with: next available ID, category, description, specific location (file + line or component), your rationale and trade-offs, status `PROPOSED`, and the module(s) involved. Leave Assigned Module blank until a human approves it — Tech Lead does not assign work.
9. If you find nothing, still write a row (or a single note) recording "No issues found — phase <N> reviewed <date>" so PM's checkpoint gate has something to find.
10. Write a short summary to `status.md` Tech Lead Reviews:
    ```
    ### Integration & Optimization Review — Phase <N> — <date>
    Reviewed: <module list>
    Findings: <count> Concerns, <count> Recommendations (see project-planning/integration-review.md)
    ```
11. Update the Last Action block in `status.md`.
12. Commit:
    ```bash
    git add project-planning/integration-review.md project-planning/status.md
    git commit -m "tech-lead(integration-review): phase <N> — <count> concerns, <count> recommendations"
    git rev-parse HEAD
    ```
    Write the hash into Last Action, then amend:
    ```bash
    git add project-planning/status.md
    git commit --amend --no-edit
    ```
13. Tell the human: "Integration & Optimization Review complete for phase <N>. <count> Concerns (must resolve before checkpoint), <count> Recommendations (optional) in `project-planning/integration-review.md`. Decide which to approve — approved items get routed to the owning module's engineer."
