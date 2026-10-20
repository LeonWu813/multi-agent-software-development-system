# Recording the Human's Decisions on Integration-Review Items

Run this when the human tells you their decision on one or more `PROPOSED` items in `project-planning/integration-review.md` — e.g. "INT-001 approve, INT-002 reject, INT-003 defer to phase 3". You record decisions; you never make them.

1. Read `project-planning/integration-review.md` and the Module Map in `project-planning/status.md`.
2. For every item the human named — including `DEFERRED` rows from earlier phases that they decide again — set Status to exactly what they said: `APPROVED`, `REJECTED`, `DEFERRED`, or — at the final checkpoint only — `ACCEPTED (KNOWN ISSUE)` for a deferred row the human accepts as a known issue (PM lists it in the README). Add their reason (or "no reason given") and the date to Notes. If the human's wording is ambiguous ("maybe later", "looks fine"), ask before writing — you run as a direct session and can ask.
3. For every `APPROVED` item, fill **Assigned Module**: the module whose Source Path (Module Map) contains the code the fix changes. Propose it and get the human's confirmation in this session. If the fix touches code owned by more than one module, the fix splits into one row per owner — say so and ask the human how to split before assigning. Name the split rows with a letter suffix (`INT-003` → `INT-003a`, `INT-003b`) and set the original to `SPLIT` with the note "split into INT-003a/b" — `SPLIT` counts as closed for the checkpoint gate, and the split rows carry the work.
4. For every `APPROVED` item whose fix changes code another module depends on, add `blast-radius first` to Notes — the coordinator runs `/pstack:blast-radius` before the Engineer starts (see the project `CLAUDE.md`). If that blast-radius report changes the plan, the human runs you again with it; review it as an `on-demand-review` and record any change to the row here.
5. Leave items the human did not mention as `PROPOSED`. Never infer a decision.
6. Update Last Action (`mode: record-decisions`, `result: success`) in `status.md`.
7. Commit:
   ```bash
   git add project-planning/integration-review.md project-planning/status.md
   git commit -m "tech-lead(record-decisions): <IDs>"
   ```
8. Tell the human, per approved item, the command to run next: `claude --agent engineer-mod-<assigned> "integration-fix <ID>"` (after the coordinator's blast-radius step where Notes say so). If no item was approved and none is still `PROPOSED`, the next step is `claude --agent pm` for checkpoint.
