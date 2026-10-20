# Delta Sync Workflow

Use this workflow after any [SUBSTANTIVE] PRD change — a change that alters requirements, adds or removes modules or user stories, changes acceptance criteria, or revises the tech stack or architecture. Follow every step in order.

A [TRIVIAL] change (typo fix, minor wording clarification that doesn't alter meaning) does NOT use this workflow. For trivial changes, propagate the wording, write a brief sync note to status.md, and stop.

---

## Steps

1. **Read the change description from status.md PM Updates section**

   Find the last `## Sync Reports` entry, then read **every** `## PM Updates` entry dated after it — PM may have logged several changes (for example a change, then a revision after Tech Lead's review) before you run. Sync all of them, oldest first. For each entry, understand:
   - What specifically changed in prd.md
   - Why it was tagged [SUBSTANTIVE]
   - Which sections of prd.md were modified (look for references to module IDs, US-IDs, AC numbers, or named sections)

   If no PM Updates entry exists for this change, read the prd.md diff if available, or read the full prd.md and compare against the current downstream docs to determine what is out of sync. Do not guess — if the scope of change is unclear, mark the affected sections with `[AMBIGUITY: scope of PRD change not documented in PM Updates]`.

2. **Read current prd.md in full**

   Read the entire prd.md to have the authoritative current state. Do not rely solely on the PM Updates description. The full read is required to detect any related changes the PM may not have listed explicitly.

3. **Identify affected downstream files using SKILL.md mapping rules**

   For each change identified in step 1, map it to the affected file(s):
   - Change to Project Overview, Tech Stack, or Architecture → production.md is affected
   - Change to Module Breakdown for MOD-XXX → modules/<dir>/spec.md is affected
   - Change to a User Story → every module spec that references that US-ID is affected
   - Change to Acceptance Criteria → the module spec(s) where those AC entries appear are affected
   - Change to Phases & Milestones → status.md Phase Plan section is affected
   - Change to Adopted Conventions → production.md Shared Conventions is affected (copy the entry verbatim, keeping its ID)
   - A `[TRIVIAL] Build Config changed` entry in the same window → copy status.md Build Config into production.md Shared Conventions again
   - A PM Updates entry that answers your earlier `[AMBIGUITY]`/`[CONFLICT]`/`[BLOCKER]` questions → each file holding one of the listed markers is affected
   - Addition of a new module → a new spec.md must be created
   - Removal of a module → the spec.md must be noted (not deleted)

   Write a list of affected files before proceeding to step 4.

4. **For each affected file: apply only the delta**

   Read the current version of the file. Apply all translation decisions according to `references/translation-rules.md`. Apply only the sections that need to change based on the PRD delta. Rules:
   - Do not rewrite sections that are unaffected by the change.
   - Do not alter formatting, wording, or structure of unaffected sections.
   - Carry forward any existing AMBIGUITY or CONFLICT markers that are still valid.
   - Remove AMBIGUITY or CONFLICT markers only if the PRD change explicitly resolves them — a PM Updates entry listing the marker it resolves counts. Replace the marker with the PRD's new text, verbatim.
   - Add new AMBIGUITY or CONFLICT markers if the change introduces new vagueness or contradictions.
   - Update "Last Synced from PRD Revision" to the new PRD revision number.

5. **If the change adds a new module: write spec using Module Map**

   - Read the `## Module Map` in `status.md` to find the new module's directory (PM should have created it and updated the map before handing off to Doc-Sync).
   - If the new module's MOD-ID is missing from the Module Map or its directory does not exist on disk, write a blocker in the sync report: `[BLOCKER: MOD-XXX directory not in Module Map — PM must name and create the module directory and update status.md before Doc-Sync can write the spec]`. Do not create the directory. Stop processing this module.
   - Copy `templates/module-spec.tmpl.md` to `modules/<dir>/spec.md`.
   - Fill all sections following the same rules as initial-sync.md step 3. Remove all HTML template comments from the completed spec.
   - Add the new module as a row in production.md's Module Index table (MOD-ID, Module Name, Directory, Description).
   - Create `modules/<dir>/status.md` and generate `.claude/agents/engineer-<dir>.md` and `.claude/agents/qa-<dir>.md` exactly as initial-sync.md step 3 describes (template frontmatter `tools` and `model` copied unchanged).
   - In your handoff message, tell the human to open a new terminal before running the new agents, so they load. Regenerated agents (step 5a) count too.
   - If the PRD change says the new module takes over code that other modules already hold, end your handoff with: `claude --agent tech-lead "log migration rows for <owner dir>"` — Tech Lead logs one integration-review row per module that must give up its copy.
   - The same applies to a module you skipped at an earlier sync with a `[BLOCKER]` that PM has since fixed (its MOD-ID is now in the Module Map): write its spec, status file, and agents now, and list the BLOCKER as resolved in the sync report.

5a. **Regenerate the agents of changed modules.** If a module's Source Path, dependencies, or directory changed in the Module Map or the PRD, regenerate its `engineer-<dir>.md` and `qa-<dir>.md` from the templates so the hardcoded paths match the Module Map again. Never leave a wrapper that names an old Source Path.

6. **If the change removes a module: note the removal — do NOT delete the file**

   - Add a notice at the top of the removed module's spec.md:
     ```
     > [REMOVED IN PRD REVISION <N>]: This module was removed from prd.md. This file is preserved for historical reference. The module is no longer active.
     ```
   - Remove the module's row from production.md's Module Index table.
   - Note the removal in the sync report (step 8).
   - Do not delete the file. The human makes that decision.

7. **If the change adds new user stories: ensure each US-ID appears in at least one module spec**

   For each new US-ID in prd.md:
   - Identify which module(s) the user story belongs to per PRD Module Breakdown.
   - Add the US-ID to the Related User Stories list in the relevant spec.md.
   - Add the full text of the user story to the Context section of the relevant spec.md.
   - Propagate any new acceptance criteria from the user story into the Acceptance Criteria section of the spec.

8. **Write sync report to status.md Sync Reports section**

   Append a new entry to `## Sync Reports`:

   ```
   ### Sync Report — Delta Sync — <date>
   **Sync type:** delta
   **PRD Revision:** <new revision>
   **PM Update reference:** <date/title of the PM Updates entry that triggered this sync>
   **Files modified:**
   - production.md — <one-line description of what changed>
   - modules/<dir>/spec.md — <one-line description of what changed>
   - (one line per file actually modified)
   **Files created:**
   - (list, or "none")
   **Module removals noted:**
   - (list, or "none")
   **AMBIGUITY markers added:**
   - (list each new one, or "none")
   **AMBIGUITY markers resolved:**
   - (list each resolved one, or "none")
   **CONFLICT markers added:**
   - (list each, or "none")
   ```

9. **Run scripts/verify-sync.sh <project-planning-path>**

   Execute the verification script with the absolute path to the project-planning directory. Review all `[PASS]` and `[FAIL]` lines.

10. **If verification fails, fix and re-run before declaring complete**

    For each `[FAIL]` line:
    - Read the check description.
    - Return to the specific file and fix only the failing condition.
    - Do not touch unrelated sections.
    - Re-run verify-sync.sh.
    - Repeat until verify-sync.sh exits 0.

    Do not declare the delta sync complete until verify-sync.sh exits 0 — with the same exception as initial-sync.md: if every remaining `[FAIL]` concerns a module carrying a `[BLOCKER]` from this sync, record Last Action `result: needs-pm` and commit.

---

## Completion

When verify-sync.sh exits 0, the delta sync is complete. Commit with:

```
git add project-planning/ .claude/agents/   # generated wrappers live in .claude/agents/
git commit -m "doc-sync(delta): <one-line summary of what changed>"
```
