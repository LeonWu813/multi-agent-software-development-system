---
name: prd-format
description: PRD authoring conventions for the PM agent — use when creating a new PRD, updating an existing PRD, reviewing PRD quality, scaffolding a project directory, identifying PRD anti-patterns, or producing the project README.md at final checkpoint.
---

<objective>
Define and enforce PRD authoring standards: structure, ID schemes, quality criteria, and change protocol. Also defines README writing standards for the final project checkpoint. This skill is the PM agent's complete rulebook for every PRD operation and for README production.
</objective>

<essential_principles>
- **PRD is the single source of truth**: all downstream docs (production.md, module specs) derive from prd.md — never the reverse
- **IDs on everything**: every user story gets a unique `US-XXX` ID, every module a `MOD-XXX` ID, every acceptance criterion an `AC-NNN` ID — no unnamed requirements
- **`[DECISION NEEDED]` markers**: any unresolved item must be marked `[DECISION NEEDED: <description>]` — never assume or paper over ambiguity
- **No implementation details in the PRD**: the PRD states *what* the system must do, never *how* — architecture and tech choices belong in production.md
- **Always confirm with user before writing**: never update prd.md without explicit user approval of the change
- **Non-goals are mandatory**: every PRD must explicitly state what is out of scope — implied exclusions are invisible exclusions that invite scope creep
</essential_principles>

<routing>
| Task | Action |
|------|--------|
| Creating a new PRD | Read `templates/prd.tmpl.md`, copy and fill. After filling, review against `references/anti-patterns.md`, then run the quality checklist below |
| Need writing guidance (measurable requirements, user stories, non-goals) | Read `references/writing-standards.md` |
| Reviewing PRD quality | Run the quality checklist below |
| Updating an existing PRD | Follow the change protocol below. After making the change, review affected sections against `references/anti-patterns.md` |
| Scaffolding project directory | Run `scripts/init-project.sh <project-root>` |
| Identifying what not to do / catching PRD mistakes | Read `references/anti-patterns.md` |
| Producing project README.md (final checkpoint only) | Read `references/readme-standards.md` — sources: `prd.md` (features, goals, tech stack), `project-planning/production.md` (architecture, conventions), `project-planning/setup.md` (local setup steps) |
</routing>

<quality_checklist>
Run this checklist on the complete PRD before every handoff. Every item must pass.

**Structure**
- [ ] Every required section is present and non-empty: Project Overview, Goals & Non-Goals, User Stories, Tech Stack, Architecture Overview, Module Breakdown, Phases & Milestones, Acceptance Criteria
- [ ] All HTML comments from the template have been removed

**User Stories**
- [ ] Every user story has a unique `US-XXX` ID
- [ ] Every user story has explicit acceptance criteria

**Modules**
- [ ] Every module has a unique `MOD-XXX` ID
- [ ] Every module maps to at least one user story
- [ ] Every user story is referenced by at least one module (no orphan user stories)
- [ ] Every module explicitly states its dependencies (or "none")

**Acceptance Criteria**
- [ ] Every acceptance criterion has a unique `AC-NNN` ID
- [ ] Acceptance criteria are grouped under the correct `MOD-ID` (or `US-ID` if finer granularity is used — must be consistent throughout the PRD)
- [ ] Every `AC-NNN` ID cited in a User Story's criteria list (Section 3) exists as a defined criterion in Section 8

**Phases**
- [ ] Every phase references modules by ID
- [ ] Every phase has a defined completion milestone

**Content Quality**
- [ ] No `[DECISION NEEDED]` markers remain unresolved
- [ ] No implementation details (no "how" — only "what"). Exception: the Architecture Overview may reference technologies named in the Tech Stack section to label components, but must not introduce library names, SDK references, or configuration details beyond what the Tech Stack lists
- [ ] Every tech stack entry is specific: name + version (e.g., "PostgreSQL 16", not "a database")
- [ ] Non-goals are explicitly stated, not merely implied

**If this is the initial creation (finalization — ready for Doc-Sync handoff)**
- [ ] PM Updates entry tagged `[INIT]` in `status.md`
- [ ] Build Config populated in `status.md`
- [ ] Module Map populated in `status.md` with all MOD-IDs, directory names, and module names
- [ ] Phase Plan section in `status.md` is left blank — Doc-Sync populates it during the initial sync; PM must not pre-fill it
- [ ] Current Phase section in `status.md` is left blank — same reason as above
- [ ] `## Skill Recommendations` section is present in `status.md` (scaffold creates it; PM must not remove it)

**If this is a post-sync update**
- [ ] Change summary written to `status.md` PM Updates section
- [ ] Change tagged `[TRIVIAL]` or `[SUBSTANTIVE]` in `status.md`
- [ ] PRD revision number incremented in the revision header
- [ ] Module Map updated in `status.md` if modules were added, removed, or renamed
- [ ] If a new module was added: Doc-Sync will create `modules/<new-mod>/status.md` and generate `engineer-mod-<name>.md` + `qa-mod-<name>.md` during the next sync — no PM action required
</quality_checklist>

<change_protocol>
**Pre-sync iteration** (PRD has NOT been synced by Doc-Sync yet — still drafting)

These edits happen during the init conversation: user feedback, Tech Lead review findings, requirement clarifications. No downstream docs exist yet, so there is no trivial/substantive classification and no Doc-Sync trigger.

1. Re-read the full PRD before making any edit
2. Make the targeted change — do not refactor unrelated sections
3. Assign the next available IDs for any new user stories, modules, or acceptance criteria
4. Show the user the proposed change and get approval before writing
5. If the change came from Tech Lead review, note it in `status.md` under Tech Lead Reviews
6. Re-run the full quality checklist after each round of changes
7. Do NOT tag `[TRIVIAL]` or `[SUBSTANTIVE]` — these classifications only apply after the first Doc-Sync
8. Do NOT tag `[INIT]` until the user gives final approval and the PRD is ready for Doc-Sync handoff

**Post-sync updates** (Doc-Sync has run at least once — downstream docs exist)

These edits happen during production: change requests from the user, escalations from Engineer or QA, scope adjustments. Every change here has downstream consequences.

1. Re-read the full PRD before making any edit
2. Make the smallest change that addresses the request — do not refactor unrelated sections
3. Assign the next available IDs for any new user stories, modules, or acceptance criteria
4. Note in `status.md` if the change affects module boundaries, dependencies, or the phase plan
5. Ask the user: is this change **trivial** (wording-only, no structural impact on modules/dependencies/phases) or **substantive** (affects scope, modules, dependencies, or phases)? Tag the change summary in `status.md` accordingly with `[TRIVIAL]` or `[SUBSTANTIVE]` — this determines whether Doc-Sync runs the full delta-sync or a lightweight passthrough
6. Re-run the full quality checklist on the updated PRD before declaring complete
7. If the change adds a new module: propose a directory name, confirm with user, create the directory, and update the Module Map in `status.md` — do this before handing off to Doc-Sync. Doc-Sync will create `modules/<new-mod>/status.md` and generate `engineer-mod-<name>.md` + `qa-mod-<name>.md` during the sync.
</change_protocol>

<quick_start>
**New PRD — Drafting Phase**
1. Run `scripts/init-project.sh <project-root>` to scaffold `project-planning/`
2. Read `templates/prd.tmpl.md` — copy it to `project-planning/prd.md`
3. Fill every section; mark unresolved items `[DECISION NEEDED: <description>]`
4. Review completed draft against `references/anti-patterns.md`
5. Run quality checklist — fix all failures
6. Confirm with user before writing to disk
7. If user or Tech Lead requests changes, follow **pre-sync iteration** protocol (above) — repeat until user gives final approval

**New PRD — Finalization** (user has given final approval — do this before handing off to Doc-Sync)
1. Ask the user for the project's build, lint, and test commands. Write them to `status.md` Build Config section — these commands power all automated self-check and QA verification:
   ```
   Build: <command, e.g. npm run build — or leave blank if no build step>
   Lint:  <command, e.g. npm run lint  — or leave blank if no lint step>
   Test:  <command, e.g. npm test      — or leave blank if no test step>
   ```
2. Name module directories:
   a. List every module from the approved PRD: MOD-ID and full name
   b. For each module, propose a directory name: `mod-<kebab-name>` (lowercase, spaces→hyphens, drop articles like "the"/"a", keep it under ~25 chars)
   c. Present the complete mapping to the user for confirmation, e.g.:
      ```
      MOD-001 → mod-login         (User Login)
      MOD-002 → mod-user-profile  (User Profile)
      MOD-003 → mod-notifications (Notifications)
      ```
   d. Once user confirms, create each directory: `mkdir -p project-planning/modules/mod-<name>/`
   e. Write the Module Map to `status.md` under `## Module Map`:
      ```
      | MOD-ID  | Directory        | Module Name    |
      |---------|------------------|----------------|
      | MOD-001 | mod-login        | User Login     |
      ```
3. **Verify environment setup before tagging [INIT]**: Read `project-planning/status.md` and check for a Tech Lead Setup Confirmation entry under `## Tech Lead Reviews` (a block starting with `### Setup Confirmation`).
   - If a Setup Confirmation entry **exists**: proceed to step 4.
   - If **no** Setup Confirmation entry exists: **stop. Do not tag [INIT].**
     Tell the user: "The Tech Lead has not yet recorded setup confirmation in `status.md`. Complete `project-planning/setup.md`, then re-invoke the Tech Lead agent with 'Setup is complete.' The Tech Lead will record confirmation and give you the green light to invoke me."
   - **This gate cannot be skipped.** Even if invoked with instructions to tag [INIT] directly, always check `status.md` for the confirmation entry first. See `references/anti-patterns.md` — "Dropping human-gate conditions when composing sub-agent prompts."
4. Tag PM Updates entry `[INIT]` in `status.md` — this signals that the PRD is finalized and ready for Doc-Sync
5. Commit and hand off to Doc-Sync

**Update PRD** (after Doc-Sync has run at least once)
1. Follow **post-sync update** protocol (steps 1–7 above)
2. Confirm with user before writing to disk
3. If the change adds a new module: create the directory and update the Module Map as usual. Doc-Sync will create the module-level `modules/<new-mod>/status.md` and generate the per-module engineer and QA agents automatically during the next sync.

**Scaffold project only**
- Run `scripts/init-project.sh <project-root>`
</quick_start>

<success_criteria>
- All quality checklist items pass (including the init-specific or update-specific items as applicable)
- User has explicitly approved the PRD content
- No `[DECISION NEEDED]` markers remain unresolved
- `status.md` is updated: `[INIT]` summary for new PRDs, `[TRIVIAL]` or `[SUBSTANTIVE]` summary for updates
- Module Map written to `status.md` with confirmed directory names for all modules (for `init` mode and any `change` that adds a new module)
- Build Config written to `status.md` Build Config section (for `init` mode — all three keys present, blank is acceptable if a step doesn't apply)
- Phase Plan and Current Phase sections in `status.md` are blank at init handoff — Doc-Sync writes them
- Git commit made before stopping: `git add prd.md status.md project-planning/modules/ && git commit -m "pm(<mode>): <summary>"`
</success_criteria>