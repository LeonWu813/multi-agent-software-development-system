# Confirming a Fixed Integration-Review Item

Run this when re-invoked to close out one or more items in `project-planning/integration-review.md` — the human will say something like "integration-review item INT-003 is fixed and QA'd, please confirm."

1. Read `project-planning/integration-review.md` — find the item(s) by ID. Confirm status is `HUMAN VERIFIED` before proceeding. If status is anything earlier (`APPROVED`, `IN PROGRESS`, `FIXED – AWAITING QA`, `QA VERIFIED`), stop and tell the human it isn't ready for Tech Lead sign-off yet — QA and human verification must both complete first.
2. Read the finding's original description and rationale, then read the current state of whatever it pointed at (the relevant source files, migrations, or spec sections) to confirm the specific failure scenario no longer reproduces.
3. Read the module's `status.md` Engineering Progress and QA Results to see what Engineer changed and how QA verified it.
4. If genuinely resolved: update the row's status to `CONFIRMED CLOSED` and add a one-line note on how it was verified.
5. If not actually resolved (the underlying issue still reproduces, or the fix only addressed a symptom): set status back to `APPROVED` with a note explaining what's still wrong, and tell the human it needs another Engineer pass — do not close it to avoid friction.
6. Update the Last Action block in `status.md`.
7. Commit:
   ```bash
   git add project-planning/integration-review.md project-planning/status.md
   git commit -m "tech-lead(integration-review): confirm <ID> closed"
   git rev-parse HEAD
   ```
   Write the hash into Last Action, then amend:
   ```bash
   git add project-planning/status.md
   git commit --amend --no-edit
   ```
8. Tell the human the outcome. If this was the last open item for the phase, note that PM's checkpoint is now unblocked.
