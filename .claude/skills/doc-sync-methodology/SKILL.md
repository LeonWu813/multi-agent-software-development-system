---
name: doc-sync-methodology
description: Complete rulebook for translating PRD content into downstream planning docs (production.md and module specs) — used by the Doc-Sync agent after any PRD change.
---

<objective>
Translate prd.md content into downstream planning docs with perfect fidelity. Restructure and distribute — never add, infer, or remove. Every downstream doc traces back to an explicit PRD statement.
</objective>

<essential_principles>
- **Translator, not interpreter**: copy and restructure PRD content; never add technical details, adjectives, or rationale not in the PRD
- **Never add or infer**: if it's not in prd.md, it doesn't appear in any downstream doc
- **[AMBIGUITY] markers**: when PRD is vague or undefined, write `[AMBIGUITY: <description>]` in the affected doc and log to status.md — never guess
- **[CONFLICT] markers**: when PRD contradicts itself, mark both locations with `[CONFLICT: <description>]` and log to status.md
- **Delta-only updates**: apply only the changed sections; never rewrite sections unaffected by the change
- **Never creates module directories**: PM owns directory creation — read the `## Module Map` in `status.md` to find existing directories; if a directory is missing, write a blocker in the sync report and stop
- **Never modify prd.md**
- **Never communicate with the user directly**
</essential_principles>

<mapping_rules>
- `prd.md` Project Overview + Tech Stack + Architecture Overview → `production.md`
- `prd.md` Module Breakdown (per module) + related User Stories full text + Acceptance Criteria → `modules/<dir>/spec.md` (where `<dir>` is the directory name from the `## Module Map` in `status.md`)
- `prd.md` Phases & Milestones → `status.md` Phase Plan section
</mapping_rules>

<routing>
| Task | Action |
| --- | --- |
| First sync (no production.md exists) | Follow workflows/initial-sync.md |
| Update after [SUBSTANTIVE] PRD change | Follow workflows/delta-sync.md |
| Update after [TRIVIAL] PRD change | Passthrough: propagate wording to affected docs, write brief sync note to status.md, skip verify-sync.sh |
| Need translation rule details | Read references/translation-rules.md |
| Creating new files | Use templates from templates/ |
| Verifying sync | Run scripts/verify-sync.sh <project-planning-path> |
</routing>

<quick_start>
- First time (no production.md): read prd.md → follow workflows/initial-sync.md
- After [SUBSTANTIVE] change: read change description in status.md PM Updates → follow workflows/delta-sync.md
- After [TRIVIAL] change: propagate the wording change only → write sync note → done
- Always run verify-sync.sh after substantive syncs
</quick_start>

<success_criteria>
- scripts/verify-sync.sh exits 0 (for substantive syncs)
- No [AMBIGUITY] markers without a corresponding status.md entry
- All HTML template comments (`<!-- ... -->`) removed from production.md and every module spec
- Sync report written to status.md Sync Reports section
- Git commit: `git add production.md modules/ status.md && git commit -m "doc-sync(<initial|delta|trivial>): <summary>"`
</success_criteria>
