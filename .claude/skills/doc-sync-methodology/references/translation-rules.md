# Translation Rules Reference

Detailed integrity guardrails for the Doc-Sync agent. Apply these rules on every sync — initial or delta. When in doubt about whether an action is permitted, check the "Acceptable vs Prohibited" section below.

---

## Core Translation Rule

**Translator, not interpreter.** Copy and restructure PRD content; never add intent, rationale, or implied detail.

The downstream docs are a structured redistribution of prd.md content — not an enhancement of it. If the PRD does not say it, the downstream doc must not say it.

**Correct examples:**

| PRD says | Downstream doc says | Verdict |
| --- | --- | --- |
| "Use PostgreSQL" | "Use PostgreSQL" | CORRECT |
| "Support user authentication" | "Support user authentication" | CORRECT |
| "Response time should be acceptable" | `[AMBIGUITY: PRD says "acceptable response time" but does not specify a measurable threshold — needs PM clarification]` | CORRECT |

**Incorrect examples:**

| PRD says | Downstream doc says | Verdict |
| --- | --- | --- |
| "Use PostgreSQL" | "Use PostgreSQL because it's better for relational data" | WRONG — added rationale not in PRD |
| "Support user authentication" | "Implement JWT-based user authentication" | WRONG — added implementation detail not in PRD |
| "Fast API responses" | "API responses under 200ms" | WRONG — invented a specific threshold |
| "Secure storage" | "Encrypt data at rest using AES-256" | WRONG — added a specific technique not in PRD |

---

## AMBIGUITY Markers

**When to use:** The PRD is vague, uses relative terms without measurable thresholds, references something by name without defining it, or leaves a required field undefined (e.g., no input/output contract, no version number, no module dependency list).

**Format:**
```
[AMBIGUITY: <plain-English description of what is missing or undefined, with a pointer to where in the PRD the vagueness occurs, and what the PM needs to provide>]
```

**Examples:**

```
[AMBIGUITY: PRD says "fast response" in MOD-002 requirements but does not specify a target latency — PM must define a measurable threshold]

[AMBIGUITY: PRD Tech Stack lists "Redis" but does not specify a version — PM must confirm the required version]

[AMBIGUITY: PRD does not define the input/output contract for MOD-004 — PM must specify what the module accepts and what it returns]

[AMBIGUITY: PRD has no revision number — cannot confirm sync currency]
```

**Rule:** Every AMBIGUITY marker placed in a downstream doc must have a corresponding entry in the status.md Sync Reports section for that sync run. An AMBIGUITY marker without a status.md entry is a silent corruption — the PM has no way to know it needs resolution.

**Never resolve an AMBIGUITY by guessing.** Leave the marker in place until the PM updates prd.md with a concrete answer.

---

## CONFLICT Markers

**When to use:** The PRD makes two statements about the same thing that cannot both be true simultaneously.

**Format:**
```
[CONFLICT: <description of the two contradictory statements, with exact locations in prd.md — PM must resolve before this section can be implemented>]
```

**Examples:**

```
[CONFLICT: PRD Module Breakdown (MOD-001) states "authentication is stateless"; PRD Architecture Overview states "sessions are stored server-side" — these are contradictory — PM must resolve]

[CONFLICT: PRD User Story US-007 states the module must support "up to 1,000 concurrent users"; PRD Acceptance Criteria AC-012 states "the system must support 10,000 concurrent users" — PM must confirm the correct figure]
```

**Rule:** Mark BOTH locations where the conflict appears in downstream docs. If the conflict spans production.md and a module spec, place a CONFLICT marker in both files. Log the conflict in the status.md Sync Reports section.

**Never resolve a CONFLICT by choosing one side.** Leave both markers in place until the PM revises prd.md.

---

## Acceptable vs Prohibited Restructuring

### Acceptable

These restructuring actions preserve PRD fidelity while improving navigability:

- **Splitting** a long PRD section across multiple spec files (e.g., distributing a combined acceptance criteria list into per-module specs)
- **Reformatting** a PRD prose list into a markdown table (e.g., tech stack as a table)
- **Grouping** acceptance criteria by module even if the PRD lists them in a flat global list
- **Extracting** user story full text into the Context section of a module spec, even though the PRD keeps it in a separate User Stories section
- **Normalizing** AC format to "The system shall [behavior] when [condition]" while preserving the exact behavioral statement from the PRD

### Prohibited

These actions corrupt the downstream docs even when they appear to improve them:

- **Adding an adjective** not in the PRD ("fast", "secure", "scalable", "simple", "robust") — these are not requirements
- **Combining** two PRD requirements into one statement — the Engineer needs to trace each requirement to its PRD source; merged requirements break that trace
- **Splitting** one PRD requirement into sub-requirements that were not sub-requirements in the PRD — this is fabrication, not restructuring
- **Inferring a module dependency** not stated in the PRD (e.g., "MOD-003 probably depends on MOD-001 for auth") — use an AMBIGUITY marker if a dependency seems implied but is not stated
- **Paraphrasing** user story text — copy it verbatim; paraphrasing changes meaning
- **Adding implementation suggestions** in comments or notes fields — the Doc-Sync agent is not an architect
- **Removing a requirement** because it seems redundant — it stays unless the PRD removes it

---

## Mapping Reference

Detailed guidance for each rule in SKILL.md `<mapping_rules>`.

### PRD Project Overview → production.md Project Summary

Copy the full text of the Project Overview section verbatim into the Project Summary section of production.md. If the PRD has a single paragraph, copy that paragraph. If it has multiple paragraphs or a bulleted list, preserve that structure. Do not add an executive summary or preamble.

### PRD Tech Stack → production.md Tech Stack table

Each entry in the PRD Tech Stack becomes one row in the production.md Tech Stack table. Rules:
- The "Component" column is the category label (e.g., "Database", "Backend runtime").
- The "Name + Version" column is the exact product name and version as written in the PRD.
- The "Notes" column is for any qualifier stated in the PRD (e.g., "LTS", "self-hosted"). Leave blank if none.
- If the PRD does not specify a version for an entry, place `[AMBIGUITY: PRD does not specify version]` in the Notes column.
- Do not add rows for technologies not mentioned in the PRD.

### PRD Module Breakdown → modules/mod-XXX/spec.md Context section

The Context section of each module spec requires three elements drawn from the PRD:

1. **Business problem** — look in the PRD Goals section, the PRD project overview, or the rationale embedded in user stories (e.g., "As a user, I need X *because* Y"). Copy the exact text. If the PRD does not state a business problem for this module specifically, write an AMBIGUITY marker.

2. **Full user story text** — for every US-ID listed as related to this module, copy the complete story text from the PRD's User Stories section. Do not reference the US-ID alone — the Engineer needs the full "As a [role], I want [goal] so that [reason]" text without opening prd.md.

3. **Non-goals** — if the PRD has a non-goals section or if individual modules have explicit "out of scope" statements, copy those verbatim for the relevant module. Non-goals are as important as goals for bounding implementation.

### PRD Phases & Milestones → status.md Phase Plan section

Copy phase names, milestone names, and any stated dates or sequencing exactly as they appear in the PRD. Present them in the same order as the PRD. Do not add estimated durations, priorities, or commentary. If the PRD uses a table for phases, reproduce the table. If it uses a list, reproduce the list. If phase names are ambiguous or dates are missing, apply AMBIGUITY markers rather than inventing values.

---

## Prohibited Actions

Two actions are absolutely prohibited regardless of context:

### 1. Never modify prd.md

`prd.md` is the source of truth. Doc-Sync is a consumer, not an owner. If `prd.md` contains an error, an ambiguity, or a conflict, the correct response is to place a marker in the downstream doc and log it to `status.md` for the PM to resolve.

Tempting-but-wrong actions:
- "This typo in prd.md is clearly wrong — I'll fix it while syncing." → **Do not.** Use an AMBIGUITY marker.
- "The PRD is missing a version number — I'll add the obvious one." → **Do not.** Use an AMBIGUITY marker.
- "I need to clarify this requirement before I can sync it." → **Do not edit prd.md.** Use an AMBIGUITY marker and stop.

### 2. Never communicate with the user directly

Doc-Sync cannot ask the PM or user questions directly. All communication goes through `status.md`:
- Ambiguities → `[AMBIGUITY: ...]` marker in the downstream doc + entry in status.md Sync Reports
- Conflicts → `[CONFLICT: ...]` markers in both downstream locations + entry in status.md Sync Reports
- Blockers (e.g., missing module directory) → `[BLOCKER: ...]` entry in status.md Sync Reports

The PM reads `status.md` after Doc-Sync completes and resolves each item.

---

## Delta-Only Rule

When a PRD changes, apply **only the sections that changed**. Never rewrite unaffected sections.

### What counts as "affected"

A section is affected if:
- Its content is directly derived from a PRD section that changed (per the mapping rules in SKILL.md)
- A new or removed MOD-ID, US-ID, or AC-NNN now applies to it
- An AMBIGUITY or CONFLICT marker in it has been resolved or created by the change

A section is NOT affected if:
- It happens to be on the same page as a changed section
- You would rewrite it for clarity, style, or completeness
- It "might" be wrong based on implied context from the change

### Why this matters

Over-broad rewrites introduce content drift:
- They replace exact PRD text with paraphrased text (violating the core translation rule)
- They risk overwriting AMBIGUITY or CONFLICT markers that are still valid
- They make it impossible to audit what the PRD change actually affected

### How to determine scope before editing

1. Read the PM Updates entry in status.md — it lists which PRD sections changed
2. Map changed sections to downstream files using SKILL.md mapping_rules
3. Write the list of affected files before making any edits
4. Edit only those files, only those sections
