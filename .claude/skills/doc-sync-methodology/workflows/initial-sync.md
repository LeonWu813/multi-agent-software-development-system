# Initial Sync Workflow

Use this workflow on the first sync, when no downstream docs (production.md, modules/) exist yet. Follow every step in order. Do not skip steps or reorder them.

---

## Steps

1. **Read full prd.md**

   Read the entire prd.md from the project-planning directory. Identify all of the following before writing anything:
   - Project Overview
   - Tech Stack
   - Architecture Overview
   - Module Breakdown (every module listed)
   - User Stories (every US-ID and full text)
   - Acceptance Criteria (every AC entry, noting which module or US it belongs to)
   - Phases & Milestones

   If prd.md does not exist at the expected path, stop and write an error entry to status.md. Do not proceed.

2. **Create production.md from templates/production.tmpl.md**

   Copy the template to production.md at the project-planning root. Fill every section using the mapping rules in SKILL.md:
   - Project Summary ← PRD Project Overview (full text, verbatim)
   - Tech Stack ← PRD Tech Stack (exact match; one row per entry; name + version; no additions)
   - Architecture ← PRD Architecture Overview (full text, verbatim)
   - Module Index ← one row per module from PRD Module Breakdown (MOD-ID, name, one-line description)
   - Shared Conventions ← read the `## Build Config` section from `status.md`. Copy the Build, Lint, and Test values exactly. Omit any key whose value is blank. If all three are blank, write `_Build config not yet provided — PM must fill in status.md Build Config._`

   Set "Last Synced from PRD Revision" to the revision number found in prd.md, or `[AMBIGUITY: PRD has no revision number]` if none is present.

   Apply AMBIGUITY and CONFLICT markers as needed per SKILL.md essential_principles. Do not add any content not present in prd.md.

3. **Write spec.md for each module using the Module Map**

   Read the `## Module Map` table from `status.md` to find the directory name for each module. Doc-Sync does NOT create directories — they must already exist (created by PM). Apply all translation decisions in this step according to `references/translation-rules.md`.

   For each module in prd.md's Module Breakdown:
   - Look up its directory in the Module Map. If a module's MOD-ID is missing from the map or its directory does not exist on disk, write `[AMBIGUITY: MOD-XXX has no directory in the Module Map — PM must create the directory and update status.md before this module can be synced]` in the sync report and skip that module.
   - Copy `templates/module-spec.tmpl.md` to `modules/<dir>/spec.md`.
   - Fill each section:
     - Module ID & Name ← PRD module identifier and name
     - Purpose ← PRD module description paragraph (verbatim)
     - Context ← populate with all three required elements:
       1. The business problem this module addresses (drawn from PRD Goals or the rationale stated in related user stories — copy the exact PRD text, do not paraphrase)
       2. Full text of each related user story (not just the US-ID — copy the complete story text so the Engineer has everything they need without opening prd.md)
       3. Any non-goals from the PRD that explicitly bound what this module must NOT do
     - Related User Stories ← list every US-ID associated with this module
     - Requirements ← extracted from PRD module requirements and related user story acceptance criteria; each item is one testable statement copied from the PRD
     - Input / Output Contract ← from PRD module definition; if PRD does not specify, write `[AMBIGUITY: PRD does not define the input/output contract for this module]`
     - Dependencies ← MOD-IDs this module depends on, as stated in PRD; if none stated, write `none`
     - Acceptance Criteria ← combined from PRD module criteria and related user story criteria; format each as `AC-NNN: The system shall [observable behavior] when [condition]`

   Apply AMBIGUITY and CONFLICT markers wherever the PRD is vague or contradictory.

   After filling all sections, remove every HTML template comment (`<!-- ... -->`) from the spec.md file. The spec handed to Engineer must contain only real content.

4. **Write phase plan to status.md Phase Plan section**

   Locate or create the `## Phase Plan` section in status.md. Extract the Phases & Milestones from prd.md and copy them into this section. Preserve the PRD's phase names, milestone names, and any stated dates or ordering exactly. Do not add durations, priorities, or commentary not in the PRD.

5. **Write sync report to status.md Sync Reports section**

   Append a new entry to the `## Sync Reports` section of status.md with the following structure:

   ```
   ### Sync Report — Initial Sync — <date>
   **Sync type:** initial
   **PRD Revision:** <revision>
   **Files created:**
   - production.md
   - modules/mod-001/spec.md
   - (one line per file actually created)
   **AMBIGUITY markers logged:**
   - (list each, or "none")
   **CONFLICT markers logged:**
   - (list each, or "none")
   ```

6. **Run scripts/verify-sync.sh <project-planning-path>**

   Execute the verification script, passing the absolute path to the project-planning directory as the first argument. Review its output. The script prints one `[PASS]` or `[FAIL]` line per check and a summary line.

7. **If verification fails, fix and re-run**

   For each `[FAIL]` line reported by verify-sync.sh:
   - Read the specific check description.
   - Return to the relevant file and correct only the failing condition.
   - Do not touch sections that are unrelated to the failure.
   - Re-run verify-sync.sh.
   - Repeat until the script exits 0.

   Do not declare the initial sync complete until verify-sync.sh exits 0.

---

## Completion

When verify-sync.sh exits 0, the initial sync is complete. Commit with:

```
git add production.md modules/ status.md && git commit -m "doc-sync(initial): <one-line summary of what was synced>"
```
