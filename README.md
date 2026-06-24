# Development Team Agents — Complete Architecture

This document defines the complete architecture for a multi-agent development team system built with Claude Code subagents and skills. It is the single source of truth for generating all files.

---

## System Overview

A team of 6 specialized agents that simulate a software development workflow with strict information boundaries, file-based coordination, and human approval at every handoff. Each agent runs as a completely independent `claude --agent <name>` session — no shared memory, coordinating exclusively through files on disk. Skills provide reusable knowledge that agents consume using a router + progressive disclosure pattern. Hooks print the exact `claude --agent <name>` command to run next; the human approves before running it.

### Core Principles

- **Single responsibility**: Each agent has one job, one input, one output, one handoff rule
- **Information boundaries**: Agents only access the files they need — no agent sees everything
- **Human in the loop**: Hooks suggest the next step; the human approves before proceeding
- **PRD as source of truth**: All downstream docs derive from `prd.md` through the Doc-Sync agent — no other agent modifies downstream planning docs
- **Propose before apply**: System-level changes (skills, agent definitions) go through a staging/review process
- **Progressive disclosure**: SKILL.md files stay lean (under 500 lines) as routers; detailed content lives in workflows/, references/, templates/, and scripts/ — loaded only when needed
- **`.env` is never read by any agent**: Agents may only check for the file's *existence* — never read its contents. Secret values (API keys, passwords, tokens) stay exclusively with the human. `.env.example` (no secrets, placeholder values only) may be read by agents that need to verify variable names.
- **Git as rollback safety net**: Every agent commits its work before stopping; every handoff is a clean rollback point

### Skill Architecture Pattern

Every skill follows this structure (not all folders required for every skill):

```
skill-name/
├── SKILL.md          # Router + essential principles (under 500 lines)
├── workflows/        # Step-by-step procedures (FOLLOW)
├── references/       # Domain knowledge (READ)
├── templates/        # Output structures (COPY + FILL)
└── scripts/          # Reusable code (EXECUTE)
```

SKILL.md uses semantic XML tags, not markdown headings:
- `<objective>` — what this skill does
- `<essential_principles>` — rules that always apply
- `<routing>` — maps tasks to workflows/references
- `<quick_start>` — immediate actionable guidance
- `<success_criteria>` — how to know it worked

---

## Agents

### PM

- **File**: `.claude/agents/pm.md`
- **Single Responsibility**: Own `prd.md` + all user communication
- **Tools**: Read, Grep, Glob, Write
- **Write Scope**: `prd.md`, project-level `status.md` (PM sections: Last Action, Build Config, PM Updates, Module Map, Checkpoint History, Skill Recommendations), and `README.md` (final checkpoint only). PM must NOT write to Phase Plan, Current Phase, Tech Lead Reviews, Sync Reports, or Decisions in project-level `status.md` — those belong to other agents. Engineering Progress and QA Results live in module-level `modules/*/status.md`, not in project-level `status.md`.
- **Skills Used**: prd-format
- **Invocation**: auto or manual
- **Modes**:
  - `init`: Gather requirements from user, generate `prd.md` using `prd-format/templates/prd.tmpl.md`, run `scripts/init-project.sh` to scaffold `project-planning/`, iterate with user and Tech Lead using the pre-sync iteration protocol (no `[TRIVIAL]`/`[SUBSTANTIVE]` tagging — downstream docs don't exist yet). Once user gives final approval: ask for build/lint/test commands and write to `status.md` Build Config; populate the Module Map in `status.md`; tag PM Updates `[INIT]`. The `[INIT]` tag signals the PRD is finalized and ready for Doc-Sync
  - `change`: Receive change request (from user or escalated from Engineer/QA) after Doc-Sync has run at least once. Update `prd.md`, confirm with user. Ask user whether the change is **trivial** (wording-only, no structural impact on modules/dependencies/phases) or **substantive**. Tag the change summary in `status.md` with `[TRIVIAL]` or `[SUBSTANTIVE]` accordingly — this determines whether Doc-Sync runs the full delta-sync or a lightweight passthrough
  - `checkpoint`: Review phase results with user, collect approval before next phase. On the **final phase**: produce `README.md` at project root — read `references/readme-standards.md`, source content from `prd.md` + `production.md` + `setup.md`, confirm draft with user before writing
- **Input**: User requirements, change requests, escalations from Engineer/QA via `modules/*/status.md` (module-level status files)
- **Output**: Approved `prd.md` + change summary written to `status.md`
- **Handoff**:
  - After `init`: → Tech Lead (mandatory architectural review for first PRD)
  - After `change`: → Doc-Sync (with note to human: "consider Tech Lead review first if architecturally significant")
  - After `checkpoint`: → Doc-Sync if new phase starts, or project complete
- **Constraints**:
  - Never touches `production.md` or `modules/*/spec.md` directly
  - Never makes technical decisions without Tech Lead input
  - Always confirms changes with user before writing to `prd.md`
  - If requirements are ambiguous, asks numbered questions and waits — does not assume
  - **Never tags [INIT] without a recorded Setup Confirmation** — before tagging [INIT], PM reads `project-planning/status.md` and checks for a `### Setup Confirmation` block written by Tech Lead. If no such block exists, PM stops and tells the user to complete setup and re-invoke Tech Lead first. Verbal confirmation alone is not sufficient — the block must be present in `status.md`
  - **Never writes to Phase Plan, Current Phase, Tech Lead Reviews, Sync Reports, or Decisions in project-level `status.md`** — those sections belong to other agents. PM init leaves Phase Plan and Current Phase blank; Doc-Sync populates them during the initial sync. Engineering Progress and QA Results live in module-level `modules/*/status.md`. During checkpoint, PM reads all `modules/*/status.md` files to compile phase results.
  - May write skill recommendations to `status.md ## Skill Recommendations` when it notices a recurring pattern or convention worth codifying — one brief entry per observation: pattern + why it should be a skill
  - Commits all changes to git before stopping: `git add prd.md status.md && git commit -m "pm(<mode>): <summary>"`

### Doc-Sync

- **File**: `.claude/agents/doc-sync.md`
- **Single Responsibility**: Translate `prd.md` content into downstream planning docs — nothing more, nothing less
- **Tools**: Read, Grep, Glob, Write, Bash
- **Write Scope**: `production.md`, `modules/*/spec.md`, `modules/*/status.md` (creates empty template during each sync), project-level `status.md` (sync report section), `.claude/agents/engineer-mod-<name>.md` and `.claude/agents/qa-mod-<name>.md` (generated during each sync)
- **Skills Used**: doc-sync-methodology
- **Invocation**: auto or manual
- **Input**: `prd.md` (read-only) + change description from `status.md`
- **Output**: Updated downstream docs + sync report in `status.md`
- **Workflow Selection**:
  - First sync (no `production.md` exists yet): follow `workflows/initial-sync.md`
  - Subsequent syncs with `[SUBSTANTIVE]` tag: follow `workflows/delta-sync.md`
  - Subsequent syncs with `[TRIVIAL]` tag: passthrough — propagate the wording change to affected downstream docs without running the full delta-sync workflow or `verify-sync.sh`. Write a brief sync note to `status.md`
- **Handoff**: → Human reviews sync report → Engineer (per module)
- **Post-Sync**: Run `scripts/verify-sync.sh` to programmatically verify sync integrity before declaring complete (skip for `[TRIVIAL]` passthrough)
- **Constraints**:
  - Translator, not interpreter — restructure and distribute PRD content only, never add or infer
  - If PRD is ambiguous on a point, write `[AMBIGUITY]` marker in the downstream doc and log to `status.md` for PM to resolve
  - Never modify `prd.md`
  - Never communicate with user directly
  - Never add technical details, implementation suggestions, or architectural decisions not explicitly stated in `prd.md`
  - When PRD changes, apply only the delta — do not rewrite sections unaffected by the change
  - Run `scripts/verify-sync.sh` before declaring sync complete (substantive syncs only)
  - During initial sync and when modules are added: create `modules/<mod>/status.md` (empty Engineering Progress + QA Results template) and generate `engineer-mod-<name>.md` + `qa-mod-<name>.md` in `.claude/agents/`
  - May write skill recommendations to `status.md ## Skill Recommendations` when it notices a recurring translation pattern or gap in the sync rulebook worth codifying — one brief entry: pattern + why it should be a skill
  - Commits all changes to git before stopping: `git add production.md modules/ project-planning/status.md .claude/agents/engineer-mod-*.md .claude/agents/qa-mod-*.md && git commit -m "doc-sync(<initial|delta|trivial>): <summary>"`

### Tech Lead

- **File**: `.claude/agents/tech-lead.md`
- **Single Responsibility**: Architectural advisory — evaluate feasibility, identify risks, recommend decisions
- **Tools**: Read, Grep, Glob, Bash
- **Write Scope**: `status.md` (Tech Lead review section) + `.gitignore`, `project-planning/setup.md`, `.env.example`, `docker-compose.yml` (all init review only — `.gitignore` created first)
- **Skills Used**: coding-conventions (reference)
- **Invocation**: mandatory during PM `init` flow (first PRD), setup confirmation re-invocation (init only), on-demand otherwise
- **Input**: `prd.md` + `production.md` + project-level `status.md` + for on-demand blocker reviews, the relevant `modules/<mod>/status.md`
- **Output**: Findings written to `status.md` + `setup.md` + `.env.example` + `docker-compose.yml` produced during init review
- **Handoff**: Always returns to human. During init review: human completes Round 1 setup (API keys, VAPID keys, fill `.env`, `docker compose up -d`), then re-invokes Tech Lead for setup confirmation. Tech Lead verifies infrastructure running and records confirmation in `status.md`, then human invokes PM. For other reviews: human decides whether to route findings to PM (for PRD changes) or directly to Engineer (for minor adjustments)
- **When Invoked**:
  - Mandatory: during PM `init` flow (first PRD creation)
  - Setup confirmation (init only): after human completes setup — re-invoked with "Setup is complete". Run `docker compose ps`, verify postgres + redis show running, record Setup Confirmation in `status.md`, then tell human to invoke PM
  - On-demand: when human judges a change has architectural impact, when Engineer reports a cross-module blocker, when QA reports a pattern suggesting design problems
- **Constraints**:
  - Advisory only — never writes to `prd.md`, `production.md`, or `modules/*/spec.md`
  - Articulates recommendations clearly but lets PM/human decide
  - Does not implement application code
  - During init review: (1) run `java -version`, `node --version`, `npm --version`, `docker --version`, `docker compose version` — flag any version mismatches with PRD tech stack as conditions for PM to resolve; (2) produce `project-planning/setup.md` (full infrastructure runbook), `.env.example` (all required env vars with placeholder values, no secrets), and `docker-compose.yml` (all required services — postgres, redis — with correct versions and ports from PRD); (3) instruct user to fill `.env` from `.env.example` and run `docker compose up -d`, then re-invoke Tech Lead with "Setup is complete"
  - **Never reads `.env`** — existence check only. Secret values stay exclusively with the human
  - During setup confirmation: run `docker compose ps` to verify all services show running status. If any service is not running, stop and tell user to fix before re-confirming. Record `### Setup Confirmation` block in `status.md` only when all services are UP
  - May write skill recommendations to `status.md ## Skill Recommendations` when it identifies a recurring architectural pattern or convention that should be shared across modules — one brief entry: pattern + why it should be a skill
  - Commits review findings + infrastructure files on init: `git add status.md project-planning/setup.md .env.example docker-compose.yml && git commit -m "tech-lead(review): <summary>"`
  - Commits setup confirmation separately: `git add status.md && git commit -m "tech-lead(setup-confirmed): environment verified, PM green light issued"`

### Engineer

- **File**: `.claude/agents/engineer.md`
- **Single Responsibility**: Implement one assigned module
- **Tools**: Read, Write, Edit, Bash, Grep, Glob
- **Write Scope**: Source code in working directory + `modules/<assigned-module>/status.md` (Engineering Progress section) + project-level `status.md` (Last Action block only). May read dependency modules' `modules/<dep>/status.md` to verify dependency QA status (read-only). The base `engineer.md` is a template; Doc-Sync generates a thin per-module wrapper (`engineer-mod-<name>.md`) for each module during sync — always invoke the wrapper, not the base agent.
- **Skills Used**: coding-conventions, engineer-checklist
- **Invocation**: via `claude --agent engineer-mod-<name>` (per-module wrapper generated by Doc-Sync)
- **Input**: `production.md` (read) + assigned `modules/module-X/spec.md` (read) + own `modules/<assigned-module>/status.md` (read/write)
- **Output**: Working code + self-check results logged to `modules/<assigned-module>/status.md`
- **Self-Check Process**: Run `engineer-checklist/scripts/self-check.sh` for automated checks, run integration tests (`npm run test:integration`), then manually verify judgment-based items from the checklist
- **Handoff**: → QA (with code path + production.md + module spec)
- **Constraints**:
  - Only reads `production.md` and its assigned `modules/module-X/spec.md` — no access to `prd.md` or other module specs. May read dependency modules' `modules/<dep>/status.md` to check if dependencies passed QA.
  - If blocked by something outside module scope, writes blocker to `modules/<assigned-module>/status.md` and stops — does not improvise or work around
  - Never modifies planning docs (except `modules/<assigned-module>/status.md` for self-check results and blockers, and project-level `status.md` for the Last Action block only)
  - **Pre-flight infrastructure check before writing any code**: verify `.env` exists (presence only — never read contents), database connection succeeds, and `UPLOAD_DIR` exists and is writable. If any check fails, stop and report to user — do not proceed to implementation
  - Runs self-check against engineer-checklist before declaring done
  - May write skill recommendations to `status.md ## Skill Recommendations` when it encounters a coding pattern, gotcha, or convention worth codifying — one brief entry: pattern + why it should be a skill
  - Commits all changes to git before stopping: `git add <module-source-files> modules/<name>/status.md project-planning/status.md && git commit -m "engineer-mod-<name>(<mode>): <summary>"`

### QA

- **File**: `.claude/agents/qa.md`
- **Single Responsibility**: Verify one module against its spec
- **Tools**: Read, Bash, Grep, Glob
- **Write Scope**: `modules/<assigned-module>/status.md` (QA results section) + project-level `status.md` (Last Action block only). The base `qa.md` is a template; Doc-Sync generates a thin per-module wrapper (`qa-mod-<name>.md`) for each module during sync — always invoke the wrapper, not the base agent.
- **Skills Used**: qa-checklist
- **Invocation**: via `claude --agent qa-mod-<name>` (per-module wrapper generated by Doc-Sync)
- **Input**: `production.md` + `modules/module-X/spec.md` + engineer's code output + own `modules/<assigned-module>/status.md`
- **Output**: Test results in `modules/<assigned-module>/status.md` (pass/fail + specific details)
- **Workflow Selection**:
  - First-time verification: follow `qa-checklist/workflows/functional-test.md`
  - Re-verification after bug fix: follow `qa-checklist/workflows/regression-test.md`
- **Testing Process**: Run `qa-checklist/scripts/run-qa.sh` for automated tests, then manually verify judgment-based items
- **Handoff**:
  - Pass → PM checkpoint
  - Bugs found → Engineer (with specific failure descriptions in `status.md`)
  - Spec ambiguity or spec-level issue → PM change flow (not Engineer — this may require PRD update)
- **Constraints**:
  - Never edits source code
  - Never modifies planning docs other than `modules/<assigned-module>/status.md` (QA results section) and project-level `status.md` (Last Action block only)
  - If a bug might be a spec problem rather than an implementation problem, escalates to PM rather than sending back to Engineer
  - **Backend modules (MOD-001–003): real server required for PASS** — code inspection and unit tests alone are not sufficient. QA must start the server, hit real endpoints with curl and sample fixture files, and verify actual HTTP responses and database state
  - **MOD-004 (frontend): human checkpoint** — QA cannot verify a React UI via CLI. QA produces a written test script (what to navigate, click, and verify) and hands off to the user. QA does not declare PASS on ACs it cannot exercise in a browser
  - May write skill recommendations to `status.md ## Skill Recommendations` when it encounters a recurring failure pattern or verification gap worth codifying — one brief entry: pattern + why it should be a skill
  - Commits QA results to git before stopping: `git add modules/<name>/status.md project-planning/status.md && git commit -m "qa-mod-<name>: <pass|fail> — <summary>"`

### Retrospective

- **File**: `.claude/agents/retrospective.md`
- **Single Responsibility**: Propose system improvements from project learnings
- **Tools**: Read, Grep, Glob, Write
- **Write Scope**: `project-planning/retrospective/` only
- **Skills Used**: none
- **Invocation**: **manual only** (`disable-model-invocation: true`) — only runs when user explicitly invokes
- **Input**: project-level `status.md` (full history, including `## Skill Recommendations`) + all `modules/*/status.md` files (Engineering Progress + QA Results history) + user feedback + current skill and agent files (read-only)
- **Output**: Proposed changes in `project-planning/retrospective/` with clear rationale for each
- **Handoff**: Always to human. Human reviews `proposed-changes.md` and selectively applies approved proposals to actual skill/agent files
- **Constraints**:
  - Never writes directly to `.claude/skills/` or `.claude/agents/`
  - Proposals only — all changes require human review and manual application
  - Each proposal must trace back to specific incidents or patterns in `status.md`
  - Commits proposals to git before stopping: `git add project-planning/retrospective/ && git commit -m "retrospective: <summary>"`

---

## Skills

### prd-format

- **Location**: `.claude/skills/prd-format/`
- **Used By**: PM
- **Purpose**: PRD authoring conventions — template, writing standards, quality criteria, and README production standards

#### SKILL.md (router + essential principles)
- Essential principles: PRD is the single source of truth, IDs on everything (US-XXX, MOD-XXX), `[DECISION NEEDED]` markers for unresolved items, no implementation details in PRD
- Routing:
  - Creating new PRD → read `templates/prd.tmpl.md`, copy and fill. After filling, review against `references/anti-patterns.md` before running quality checklist
  - Need writing guidance → read `references/writing-standards.md`
  - Reviewing PRD quality → use quality checklist in SKILL.md
  - Updating existing PRD → follow change protocol in SKILL.md
  - Scaffolding project directory → run `scripts/init-project.sh`
  - Identifying what not to do / catching PRD mistakes → read `references/anti-patterns.md`
- Quality checklist (stays in SKILL.md since it's used every time):
  - Every section present and non-empty
  - Every user story has unique ID and acceptance criteria
  - Every module has unique ID, maps to at least one user story, states dependencies
  - Every Acceptance Criterion has a unique `AC-NNN` ID
  - Acceptance Criteria are grouped under the correct MOD-ID (or US-ID if finer granularity is used)
  - Every phase references modules by ID and has completion milestone
  - No `[DECISION NEEDED]` markers remain
  - No implementation details
  - Tech stack entries are specific (name + version)
  - Non-goals explicitly stated
  - All HTML comments from template removed
  - Change summary written to `status.md` (if update)
- Change protocol (stays in SKILL.md since it's used every time):
  - Re-read full PRD before any edit
  - Make smallest change that addresses the request
  - Assign next available IDs for new items
  - Note in `status.md` if change affects module boundaries, dependencies, or phase plan
  - Re-run the full quality checklist on the updated PRD before declaring complete

#### templates/prd.tmpl.md
- Blank PRD skeleton with all required sections and placeholder text
- Sections: Project Overview, Goals & Non-Goals, User Stories, Tech Stack, Architecture Overview, Module Breakdown, Phases & Milestones, Acceptance Criteria
- Each section includes brief inline guidance comments like `<!-- List 3-5 measurable goals as bullet points -->`
- Acceptance Criteria section shows ACs grouped by MOD-ID (default) with a commented example showing the alternative: grouping by US-ID when finer granularity is needed
- Includes a revision header at the top: `**Revision**: 1 | **Last Updated**: <date>` — PM increments the revision number on every change. Gives Doc-Sync and Tech Lead a quick way to confirm they're reading the latest version without parsing `status.md`

#### references/writing-standards.md
- Detailed guidance on writing measurable, specific, declarative requirements
- Good vs bad examples for each standard
- How to write user stories with proper acceptance criteria
- How to define module boundaries and dependencies clearly
- How to write effective non-goals (explicit exclusions that prevent scope creep), with good/bad examples:
  - Bad: "We won't do everything" → Good: "Multi-tenancy is out of scope for v1"
  - Bad: "Performance optimization" → Good: "Sub-100ms p99 latency is not a goal; the target is < 500ms"
  - Bad: "Mobile app" → Good: "Native iOS/Android apps are out of scope; the web UI must be responsive down to 320px"

#### references/anti-patterns.md
- Common PRD mistakes with concrete before/after examples
- Combining what and how, implicit dependencies, vague acceptance criteria, scope bleed, orphan requirements, gold-plating specs
- Missing non-goals: failing to explicitly exclude things stakeholders might assume are in scope (e.g., not stating that i18n is out of scope when the product name sounds global, or not stating that offline support is excluded for a mobile-first product)
- Architecture Overview boundary: the Architecture Overview may reference technologies named in the Tech Stack section (e.g., labeling a component as "PostgreSQL" or "Claude API") because the section describes *what communicates with what*. However, it must not introduce library names, SDK references, or configuration details that aren't in the Tech Stack — those are implementation details that belong in `production.md`

#### references/readme-standards.md
- Writing standards and quality checklist for producing `README.md` at final project checkpoint
- Essential sections: title + one-liner, description (problem before installation), features, tech stack table, architecture + data flow, local setup, scripts table
- Optional high-value sections: key design decisions, domain architecture, troubleshooting
- Writing tone rules: friendly and direct, no condescending language ("easy", "simple", "just"), short paragraphs, all commands in code blocks
- Common mistakes to avoid: no description, missing setup, outdated info, walls of text
- Quality checklist: accuracy verified against `production.md` and `setup.md`; no condescending language; all commands in code blocks

#### scripts/init-project.sh
- Creates the `project-planning/` folder structure:
  - `project-planning/prd.md` (copied from template)
  - `project-planning/status.md` (from status template — includes Last Action, Current Phase, Phase Plan, Build Config, PM Updates, Tech Lead Reviews, Sync Reports, Decisions, Module Map, Checkpoint History, and Skill Recommendations sections — all empty at scaffold time. Engineering Progress and QA Results are module-level and are NOT in this file)
  - `project-planning/modules/` (empty directory)
  - `project-planning/retrospective/` (empty directory)
- Idempotent — safe to run if some dirs already exist
- Takes project root path as argument
- Includes defensive check: verifies `templates/prd.tmpl.md` exists at the resolved skill path before copying — exits with a clear error if not found (guards against symlink or relocation issues)

### doc-sync-methodology

- **Location**: `.claude/skills/doc-sync-methodology/`
- **Used By**: Doc-Sync
- **Purpose**: Complete rulebook for translating PRD content into downstream docs

#### SKILL.md (router + essential principles)
- Essential principles: translator not interpreter, never add/infer/remove, `[AMBIGUITY]` markers for gaps, delta-only updates
- Mapping rules (stays in SKILL.md since it's used every time):
  - `prd.md` Project Overview + Tech Stack + Architecture Overview → `production.md`
  - `prd.md` Module Breakdown (per module) + related User Stories + Acceptance Criteria → `modules/module-X/spec.md`
  - `prd.md` Phases & Milestones → `status.md` (phases section)
- Routing:
  - First sync (no production.md exists) → follow `workflows/initial-sync.md`
  - Update after PRD change tagged `[SUBSTANTIVE]` → follow `workflows/delta-sync.md`
  - Update after PRD change tagged `[TRIVIAL]` → passthrough: propagate wording change to affected downstream docs, write brief sync note to `status.md`, skip `verify-sync.sh`
  - Need translation rule details → read `references/translation-rules.md`
  - Creating new files → use templates from `templates/`
  - Verifying sync → run `scripts/verify-sync.sh`

#### workflows/initial-sync.md
- Step-by-step procedure for first-time sync when no downstream docs exist:
  1. Read full `prd.md`
  2. Create `production.md` from `templates/production.tmpl.md`, fill with PRD content per mapping rules
  3. For each module in PRD Module Breakdown: create `modules/module-X/spec.md` from `templates/module-spec.tmpl.md`, fill with relevant PRD content; create `modules/module-X/status.md` (empty Engineering Progress + QA Results template); generate `engineer-mod-<name>.md` and `qa-mod-<name>.md` in `.claude/agents/`
  4. Write phase plan to `status.md`
  5. Write sync report to `status.md` listing every file created
  6. Run `scripts/verify-sync.sh`
  7. If verification fails, fix issues and re-run

#### workflows/delta-sync.md
- Step-by-step procedure for updating downstream docs after a PRD change:
  1. Read change description from `status.md` (PM writes this)
  2. Read current `prd.md`
  3. Identify which downstream files are affected by the change
  4. For each affected file: read current version, apply only the delta, preserve unaffected sections
  5. If change adds a new module: create new spec from template; create `modules/<new-mod>/status.md` (empty template); generate `engineer-mod-<name>.md` and `qa-mod-<name>.md` in `.claude/agents/`
  6. If change removes a module: note removal in sync report (do not delete spec or status.md — human decides)
  7. Write sync report to `status.md`
  8. Run `scripts/verify-sync.sh`

#### templates/production.tmpl.md
- Expected structure for `production.md`:
  - Project Summary (from PRD Project Overview)
  - Tech Stack (from PRD Tech Stack — exact match required)
  - Architecture (from PRD Architecture Overview)
  - Shared Conventions (from Tech Lead recommendations, populated after first Tech Lead review)
  - Module Index (list of all modules with IDs, names, and one-line descriptions for cross-reference)

#### templates/module-spec.tmpl.md
- Expected structure for module spec files:
  - Module ID & Name
  - Purpose (one paragraph)
  - Context (populated by Doc-Sync: the business problem this module addresses, the full text of related user stories — not just IDs — and any relevant non-goals that bound what the module should *not* do. Gives the Engineer the "why" without needing access to `prd.md`)
  - Related User Stories (list of US-IDs from PRD)
  - Requirements (extracted from PRD Module Breakdown + related User Story acceptance criteria)
  - Input/Output Contract (from PRD module definition)
  - Dependencies (list of MOD-IDs this module depends on)
  - Acceptance Criteria (combined from PRD module and user story criteria)

#### references/translation-rules.md
- Detailed integrity guardrails with examples:
  - "Use PostgreSQL" → write "Use PostgreSQL" (not "Use PostgreSQL because it's better for relational data")
  - "Support user authentication" → write "Support user authentication" (not "Implement JWT-based user authentication")
  - How to write `[AMBIGUITY]` markers: `[AMBIGUITY: PRD says "fast response" but doesn't specify a target — needs measurable threshold from PM]`
  - How to handle PRD contradictions: mark both locations with `[CONFLICT]` and log to status.md
  - Examples of acceptable restructuring vs. prohibited interpretation

#### scripts/verify-sync.sh
- Automated self-verification script that checks:
  - Every MOD-ID in `prd.md` has a corresponding `modules/module-X/spec.md` file
  - No spec files exist without a matching MOD-ID in `prd.md`
  - Tech stack section in `production.md` matches `prd.md` tech stack exactly (text comparison)
  - Every US-ID in `prd.md` appears in at least one module spec
  - No `[AMBIGUITY]` markers exist without a corresponding entry in `status.md`
  - Phase plan in `status.md` lists the same phases as `prd.md`
- Outputs pass/fail report to stdout
- Takes `project-planning/` path as argument
- Exit code 0 = pass, non-zero = fail with details

### coding-conventions

- **Location**: `.claude/skills/coding-conventions/`
- **Used By**: Engineer, Tech Lead (reference)
- **Purpose**: Shared coding standards that all engineers follow

#### SKILL.md (principles + routing)
- Essential principles: consistency over personal preference, follow `production.md` for project-specific overrides, these are defaults that apply when `production.md` doesn't specify otherwise
- Default conventions:
  - Naming: camelCase for variables/functions, PascalCase for classes/components, UPPER_SNAKE_CASE for constants, descriptive names over abbreviations
  - Files: group by feature/module not by type, one component/class per file, index files for public API only
  - Error handling: fail fast, no silent catches, propagate errors with context, use typed errors where language supports it
  - Logging: structured logging (key-value), log levels (debug/info/warn/error), no sensitive data in logs
  - Testing: one test file per source file, test behavior not implementation, descriptive test names
  - Commit messages: conventional commits format (`type(scope): description`)
- Routing:
  - Need concrete examples → read `references/style-examples.md`
  - Always also read `production.md` for project-specific conventions that override these defaults
- Note: this is a living document — updated via the Retrospective review process

#### references/style-examples.md
- Concrete before/after code examples for each convention
- Examples in JavaScript/TypeScript and Python (the two most common stacks)
- Good naming vs bad naming examples
- Error handling patterns with code
- Test structure examples
- Commit message examples

### engineer-checklist

- **Location**: `.claude/skills/engineer-checklist/`
- **Used By**: Engineer
- **Purpose**: Self-check items to verify before handing off to QA

#### SKILL.md (checklist + process)
- Process:
  - Step 0: pre-flight infrastructure check before writing any code — `.env` exists (presence only, never read contents), DB connects, `UPLOAD_DIR` exists and is writable. Stop and report if any check fails
  - Step 1: run `scripts/self-check.sh` for automated items
  - Step 2: run integration tests (`npm run test:integration`) — uses `DATABASE_URL_TEST`, Claude API mocked. Must pass before handoff
  - Step 3: manually verify judgment-based items below
- Automated items (verified by script):
  - Build/compile succeeds without errors
  - Linter passes (if configured in production.md)
  - Existing tests pass
  - No files modified outside assigned module scope
- Judgment-based items (verified manually by Engineer):
  - Every requirement in the module spec is implemented
  - Edge cases are handled (empty inputs, boundary values, error states)
  - No hardcoded values that should be configurable
  - Code follows conventions in coding-conventions skill and `production.md`
  - No dependencies introduced that aren't in `production.md` tech stack
  - Code is readable — another engineer could understand it without explanation
- Output: log all results (automated + integration + manual) to `modules/<module-name>/status.md` Engineering Progress section with pass/fail per item
- Living document: updated via Retrospective agent proposals after each completed work cycle

#### scripts/self-check.sh
- Automated pre-QA verification script:
  - Reads `production.md` to find build command, lint command, test command
  - Runs build → reports pass/fail
  - Runs linter → reports pass/fail
  - Runs existing tests → reports pass/fail
  - Checks git diff to verify no files outside assigned module directory were modified
- Framework-agnostic: reads commands from `production.md` rather than hardcoding `npm` or `pip`
- Takes module name and project root as arguments
- Outputs structured report to stdout
- Exit code 0 = all automated checks pass

### qa-checklist

- **Location**: `.claude/skills/qa-checklist/`
- **Used By**: QA
- **Purpose**: Verification items for testing a module

#### SKILL.md (checklist + routing)
- Essential principles: verify against the spec (not against assumptions), test observable behavior, every failure needs a specific reproducible description, backend modules require real server verification, MOD-004 requires human sign-off
- Routing:
  - First-time module verification → follow `workflows/functional-test.md`
  - Re-verification after bug fix → follow `workflows/regression-test.md`
  - Running automated tests → use `scripts/run-qa.sh`
  - Checking known gotchas → read `references/common-failure-patterns.md`
- Core checklist items:
  - Functional: every requirement in module spec has a corresponding verification
  - Edge cases: error states, empty inputs, boundary values, invalid data
  - Integration: module works with shared conventions in `production.md`
  - Infrastructure (backend modules only): `setup.md` ports match `docker-compose.yml`; all env vars referenced in `setup.md` exist in `.env.example` — catches drift between the Tech Lead's infrastructure runbook and what Engineer actually implemented
  - Spec compliance: no features implemented that aren't in spec (gold-plating check)
  - Spec coverage: no spec requirements left unimplemented
- Output: log results to `modules/<module-name>/status.md` QA Results section with pass/fail per item and specific failure descriptions
- If failure appears to be spec problem (not implementation bug), flag separately for PM escalation
- Living document: updated via Retrospective agent proposals

#### workflows/functional-test.md
- Step-by-step for first-time module verification:
  1. Read `modules/module-X/spec.md` completely
  2. Read `production.md` for shared conventions and integration points
  2a. **Backend modules only**: verify `setup.md` matches infrastructure config — ports in `docker-compose.yml` match `setup.md`, all env vars in `setup.md` exist in `.env.example`. Log any mismatch as a FAIL and route to Engineer.
  3. List every requirement and acceptance criterion from the spec
  4. For each requirement: design a verification approach (automated test, manual check, or both)
  5. Run `scripts/run-qa.sh` for automated checks
  5a. **Backend modules only (MOD-001–003)**: start the server, run curl against each endpoint with real sample fixture files, verify HTTP responses and database state. Stop and report if server fails to start. Record each call and response in the module-level status.md
  5b. **MOD-004 (frontend)**: produce a written test script in the module-level status.md covering every AC with specific navigation steps and verification criteria. End with "Human sign-off required." Do not declare PASS until user explicitly confirms
  6. Manually verify judgment-based items
  7. Document results per-requirement in `modules/module-X/status.md`
  8. Classify any failures: implementation bug vs spec issue

#### workflows/regression-test.md
- Step-by-step for re-verification after bug fix:
  1. Read the bug description from `modules/module-X/status.md` QA Results section
  2. Verify the specific bug is fixed
  3. Re-run all previously passing tests to check for regressions
  4. Run `scripts/run-qa.sh`
  5. Focus extra attention on code adjacent to the fix
  6. Update `modules/module-X/status.md` QA Results

#### scripts/run-qa.sh
- Automated test runner and report generator:
  - Reads `production.md` to find test command
  - Runs the test suite
  - Parses test output for pass/fail counts
  - Checks that module exports/interfaces match spec's Input/Output Contract
  - Generates structured report to stdout
- Takes module name and project root as arguments
- Exit code 0 = all automated tests pass

#### references/common-failure-patterns.md
- Starts nearly empty with a few universal patterns:
  - Off-by-one errors in loops and array indexing
  - Null/undefined handling at module boundaries
  - Async operations without proper error handling
  - Hardcoded values that should come from config
  - Missing input validation
- Living document: primary target for Retrospective agent proposals — grows with project-specific patterns over time

---

## Hooks

### handoff.sh

- **Location**: `.claude/hooks/handoff.sh` (project source); `~/.claude/hooks/handoff.sh` (account-level copy)
- **Registered Events**: `Stop` (primary — fires when a `claude --agent X` CLI session ends), `SubagentStop` (secondary — fires when a Task-tool subagent stops)
- **Registration**: `.claude/hooks.json` (project-level) or `~/.claude/hooks.json` (account-level)
- **Behavior**:
  - Parses the `## Last Action` block in `status.md` (machine-readable fields: agent, mode, module, result, commit) to determine which agent just finished and what happened
  - Checks for uncommitted changes in the stopping agent's write scope — if found, prints a warning: `⚠️ Uncommitted changes detected. The agent should have committed before stopping.`
  - Prints the suggested `claude --agent <name>` command to STDOUT (appears in Claude Code transcript)
  - Never auto-invokes the next agent — always waits for human to run the command
  - Must be executable (`chmod +x`)

### Handoff Messages

| Just Finished | Status Context | Hook Suggests |
|---|---|---|
| PM (init) | PRD created, first time | `✅ PM completed initial PRD. Next: claude --agent tech-lead` |
| Tech Lead (init review) | Init review complete, setup.md + .env.example + docker-compose.yml created | `✅ Tech Lead review complete. Fill .env from .env.example, run docker compose up -d, then re-invoke Tech Lead with: "Setup is complete"` |
| Tech Lead (setup confirmed) | docker compose ps verified — postgres + redis UP | `✅ Setup confirmed and recorded. Next: claude --agent pm` |
| PM (finalize after Tech Lead) | PRD approved by user | `✅ PRD finalized. Next: claude --agent doc-sync` |
| PM (change) | PRD updated mid-project | `✅ PM updated PRD. Next: claude --agent doc-sync (Consider claude --agent tech-lead first if this change has architectural impact.)` |
| Doc-Sync | Sync complete | `✅ Doc-Sync complete. Review sync report in status.md. Next: claude --agent engineer-mod-[module-name]` |
| Engineer | Implementation + self-check done | `✅ Engineer completed [module-name]. Self-check logged to modules/[module-name]/status.md. Next: claude --agent qa-mod-[module-name]` |
| QA (pass) | Module passed all checks | `✅ QA passed [module-name]. Next: claude --agent pm (Or claude --agent engineer-mod-[next-module] if more modules remain in this phase.)` |
| QA (bugs) | Bugs found | `⚠️ QA found bugs in [module-name]. See modules/[module-name]/status.md. Next: claude --agent engineer-mod-[module-name]` |
| QA (spec issue) | Spec-level problem | `⚠️ QA found a spec-level issue in [module-name]. See modules/[module-name]/status.md. Next: claude --agent pm` |
| Retrospective | Proposals written | `✅ Retrospective complete. Review proposals in project-planning/retrospective/proposed-changes.md. Apply approved changes manually.` |

---

## Write Access Matrix

| File | PM | Doc-Sync | Tech Lead | Engineer | QA | Retrospective |
|---|---|---|---|---|---|---|
| `prd.md` | ✅ Write | 🔒 Read | 🔒 Read | ❌ No access | ❌ No access | 🔒 Read |
| `README.md` | ✅ Write (final checkpoint only) | ❌ No access | ❌ No access | ❌ No access | ❌ No access | ❌ No access |
| `production.md` | ❌ No access | ✅ Write | 🔒 Read | 🔒 Read | 🔒 Read | 🔒 Read |
| `status.md` (project-level) | ✅ Write (PM sections) | ✅ Write (sync report) | ✅ Write (review section) | ✅ Write (Last Action only) | ✅ Write (Last Action only) | 🔒 Read |
| `modules/*/status.md` (module-level) | 🔒 Read (checkpoint) | ✅ Write (creates during sync) | 🔒 Read (on-demand) | ✅ Write (assigned only) | ✅ Write (assigned only) | 🔒 Read |
| `project-planning/setup.md` | ❌ No access | ❌ No access | ✅ Write (init only) | 🔒 Read | 🔒 Read | 🔒 Read |
| `.env.example` | ❌ No access | ❌ No access | ✅ Write (init only) | 🔒 Read | 🔒 Read | ❌ No access |
| `docker-compose.yml` | ❌ No access | ❌ No access | ✅ Write (init only) | 🔒 Read | 🔒 Read | ❌ No access |
| `.env` | ❌ Never | ❌ Never | ❌ Never (existence check only via docker compose ps) | ❌ Existence check only — never read contents | ❌ Never | ❌ Never |
| `modules/*/spec.md` | ❌ No access | ✅ Write | ❌ No access | 🔒 Read (assigned only) | 🔒 Read (assigned only) | 🔒 Read |
| Source code | ❌ No access | ❌ No access | ❌ No access | ✅ Write | 🔒 Read | ❌ No access |
| `.claude/skills/*` | ❌ No access | ❌ No access | ❌ No access | ❌ No access | ❌ No access | 🔒 Read |
| `.claude/agents/*` | ❌ No access | ✅ Write (engineer-mod-*.md + qa-mod-*.md only) | ❌ No access | ❌ No access | ❌ No access | 🔒 Read |
| `retrospective/*` | ❌ No access | ❌ No access | ❌ No access | ❌ No access | ❌ No access | ✅ Write |

---

## File Structure

```
.claude/
├── agents/
│   ├── pm.md                                      # PM agent definition
│   ├── doc-sync.md                                # Doc-Sync agent definition
│   ├── tech-lead.md                               # Tech Lead agent definition
│   ├── retrospective.md                           # Retrospective agent definition
│   ├── templates/
│   │   ├── engineer.md                            # Engineer base template — NOT directly invokable; Doc-Sync reads this to generate per-module wrappers
│   │   └── qa.md                                  # QA base template — NOT directly invokable; Doc-Sync reads this to generate per-module wrappers
│   ├── engineer-mod-<name>.md                     # Generated by Doc-Sync — one per module
│   └── qa-mod-<name>.md                           # Generated by Doc-Sync — one per module
├── skills/
│   ├── prd-format/
│   │   ├── SKILL.md                               # Router + principles + quality checklist
│   │   ├── templates/
│   │   │   └── prd.tmpl.md                        # Blank PRD skeleton
│   │   ├── references/
│   │   │   ├── writing-standards.md               # Detailed writing guidance + examples
│   │   │   └── anti-patterns.md                   # Common mistakes with corrections
│   │   └── scripts/
│   │       └── init-project.sh                    # Scaffolds project-planning/ directory
│   ├── doc-sync-methodology/
│   │   ├── SKILL.md                               # Router + mapping rules + principles
│   │   ├── workflows/
│   │   │   ├── initial-sync.md                    # First sync procedure
│   │   │   └── delta-sync.md                      # Change propagation procedure
│   │   ├── templates/
│   │   │   ├── production.tmpl.md                 # Structure for production.md
│   │   │   └── module-spec.tmpl.md                # Structure for module specs
│   │   ├── references/
│   │   │   └── translation-rules.md               # Integrity guardrails with examples
│   │   └── scripts/
│   │       └── verify-sync.sh                     # Automated sync verification
│   ├── coding-conventions/
│   │   ├── SKILL.md                               # Default conventions + routing
│   │   └── references/
│   │       └── style-examples.md                  # Before/after code examples
│   ├── engineer-checklist/
│   │   ├── SKILL.md                               # Checklist items + process
│   │   └── scripts/
│   │       └── self-check.sh                      # Automated pre-QA checks
│   └── qa-checklist/
│       ├── SKILL.md                               # Checklist + routing
│       ├── workflows/
│       │   ├── functional-test.md                 # First-time verification procedure
│       │   └── regression-test.md                 # Re-verification after bug fix
│       ├── scripts/
│       │   └── run-qa.sh                          # Automated test runner + reporter
│       └── references/
│           └── common-failure-patterns.md         # Known gotchas (living doc)
├── hooks/
│   └── handoff.sh                                 # Stop/SubagentStop hook for handoffs
└── hooks.json                                     # Hook registration

project-planning/                                   # Created by PM via init-project.sh
├── prd.md                                          # Single source of truth — only PM writes
├── production.md                                   # Shared tech context — only Doc-Sync writes
├── status.md                                       # Coordination hub — multiple agents write sections
├── modules/
│   ├── module-1/
│   │   ├── spec.md                                 # Only Doc-Sync writes, Engineer + QA read
│   │   └── status.md                               # Engineer writes Engineering Progress; QA writes QA Results; PM reads at checkpoint
│   ├── module-2/
│   │   ├── spec.md
│   │   └── status.md
│   └── module-3/
│       ├── spec.md
│       └── status.md
└── retrospective/                                  # Only Retrospective agent writes here
    ├── proposed-changes.md                         # Summary of all proposals with rationale
    └── drafts/                                     # Individual proposed diffs
        ├── engineer-checklist.diff.md
        ├── qa-checklist.diff.md
        └── (other proposals as needed)
```

---

## Handoff Chains

### Init Flow (once per project)

```
User
 ↓ provides requirements
PM [init mode — drafting]
 ↓ runs init-project.sh to scaffold project-planning/
 ↓ creates prd.md from template, iterates with user
 ↓ commits draft: git commit -m "pm(init): draft PRD for <project>"
 [Stop → hook prints: "claude --agent tech-lead"]
 [HUMAN REVIEWS PRD → RUNS: claude --agent tech-lead]
Tech Lead [init review]
 ↓ runs java -version, node --version, docker --version — flags version mismatches with PRD as conditions
 ↓ reviews PRD feasibility, writes findings to status.md
 ↓ produces .gitignore (first — protection in place before user creates .env)
 ↓ produces .env.example (all required env vars, placeholder values only — no secrets)
 ↓ produces docker-compose.yml (postgres + redis at versions/ports from PRD)
 ↓ produces project-planning/setup.md (full infrastructure runbook)
 ↓ updates Last Action in status.md
 ↓ commits: git commit -m "tech-lead(review): initial PRD review"
 [Stop → hook prints: "Fill .env from .env.example, run docker compose up -d, then re-invoke Tech Lead with 'Setup is complete'"]
 [HUMAN: obtains API keys, generates VAPID keys, fills .env from .env.example]
 [HUMAN: runs docker compose up -d — postgres + redis containers start, DB created automatically]
 [HUMAN RE-INVOKES: claude --agent tech-lead (says "Setup is complete")]
Tech Lead [setup confirmation]
 ↓ runs docker compose ps — verifies postgres + redis show running status
 ↓ records ### Setup Confirmation block in status.md
 ↓ commits: git commit -m "tech-lead(setup-confirmed): environment verified, PM green light issued"
 [Stop → hook prints: "claude --agent pm"]
 [HUMAN RUNS: claude --agent pm]
PM [init mode — pre-sync iteration]
 ↓ incorporates Tech Lead feedback using pre-sync iteration protocol
 ↓ no [TRIVIAL]/[SUBSTANTIVE] tagging — downstream docs don't exist yet
 ↓ iterates with user until final approval
 ↓ (loop back to Tech Lead if architectural changes were significant)
 ↓ commits: git commit -m "pm(init): incorporated review feedback"
 [HUMAN GIVES FINAL APPROVAL]
PM [init mode — finalization]
 ↓ populates Build Config in status.md (asks user for build/lint/test commands)
 ↓ populates Module Map in status.md (proposes directory names, user confirms)
 ↓ tags PM Updates entry [INIT] — signals PRD is finalized
 ↓ updates Last Action in status.md
 ↓ commits: git commit -m "pm(init): finalized PRD, ready for doc-sync"
 [Stop → hook prints: "claude --agent doc-sync"]
 [HUMAN RUNS: claude --agent doc-sync]
Doc-Sync
 ↓ follows initial-sync workflow
 ↓ creates production.md + module specs (with Context section) from templates
 ↓ creates modules/*/status.md (empty Engineering Progress + QA Results template per module)
 ↓ generates engineer-mod-<name>.md + qa-mod-<name>.md in .claude/agents/ for each module
 ↓ runs verify-sync.sh, writes sync report to status.md
 ↓ updates Last Action in status.md
 ↓ commits: git commit -m "doc-sync(initial): created production.md + N module specs + per-module agents"
 [Stop → hook prints: "claude --agent engineer-mod-module-1"]
 [HUMAN REVIEWS SYNC REPORT → RUNS: claude --agent engineer-mod-module-1]
Engineer [module-1]  (via claude --agent engineer-mod-module-1)
 ↓ implements module, runs self-check.sh + manual checks
 ↓ logs results to modules/module-1/status.md, updates Last Action in project-level status.md
 ↓ commits: git commit -m "engineer-mod-module-1(implement): implementation complete"
 [Stop → hook prints: "claude --agent qa-mod-module-1"]
 [HUMAN RUNS: claude --agent qa-mod-module-1]
QA [module-1]  (via claude --agent qa-mod-module-1)
 ↓ follows functional-test workflow, runs run-qa.sh
 ↓ logs results to modules/module-1/status.md, updates Last Action in project-level status.md
 ↓ commits: git commit -m "qa-mod-module-1: pass"
 [Stop → hook depends on pass/fail]
 [HUMAN REVIEWS RESULTS]
PM [checkpoint]  (via claude --agent pm)
 ↓ reads all modules/*/status.md files to compile phase results
 ↓ reviews phase results with user, confirms before next phase
 ↓ records git commit hash in Checkpoint History
```

### Standard Change Flow (post-sync — Doc-Sync has run at least once)

```
User requests change  OR  Engineer/QA escalates issue
 ↓
PM [change mode]
 ↓ updates prd.md, confirms with user
 ↓ asks user: trivial or substantive? Tags status.md accordingly
 ↓ commits: git commit -m "pm(change): <summary>"
 [Stop → hook prints: "claude --agent doc-sync (or claude --agent tech-lead first if architectural)"]
 [HUMAN DECIDES: claude --agent doc-sync directly, or claude --agent tech-lead first]
Doc-Sync
 ↓ reads [TRIVIAL] or [SUBSTANTIVE] tag from status.md
 ↓ [TRIVIAL]: passthrough — propagate wording, skip verify-sync.sh
 ↓ [SUBSTANTIVE]: follows full delta-sync workflow; if modules added, creates modules/*/status.md + generates per-module agents
 ↓ commits: git commit -m "doc-sync(<trivial|delta>): <summary>"
 [Stop → hook prints: "claude --agent engineer-mod-[module-name]"]
 [HUMAN REVIEWS → RUNS: claude --agent engineer-mod-[module-name]]
claude --agent engineer-mod-X → claude --agent qa-mod-X → claude --agent pm [checkpoint]
```

### On-Demand Tech Lead (anytime)

```
Human identifies architectural concern or Engineer reports blocker
 ↓
[Human runs: claude --agent tech-lead]
Tech Lead
 ↓ reads relevant docs + blocker (including modules/<mod>/status.md if needed)
 ↓ writes findings to status.md, updates Last Action
 ↓ commits: git commit -m "tech-lead(review): <concern>"
 [Stop → hook prints: "Review Tech Lead findings in status.md"]
 [HUMAN DECIDES]
 ├── Minor adjustment → tell Engineer: claude --agent engineer-mod-<name>
 └── PRD-level change → claude --agent pm [change mode]
```

### Bug Fix Loop

```
QA finds bugs
 ↓ logs specific failures to modules/module-X/status.md, updates Last Action in project-level status.md
 ↓ commits: git commit -m "qa-mod-module-X: fail — <summary>"
 [Stop → hook prints: "claude --agent engineer-mod-module-X"]
 [HUMAN RUNS: claude --agent engineer-mod-module-X]
Engineer
 ↓ fixes bugs, re-runs self-check.sh
 ↓ commits: git commit -m "engineer-mod-module-X(bugfix): bug fixes for <issues>"
 [Stop → hook prints: "claude --agent qa-mod-module-X"]
 [HUMAN RUNS: claude --agent qa-mod-module-X]
QA [re-verify]
 ↓ follows regression-test workflow
 ↓ commits: git commit -m "qa-mod-module-X: <pass|fail> — regression test"
 ↓ pass or fail again
```

### Retrospective (manual only, after phase or project completion)

```
[Human runs: claude --agent retrospective]
Retrospective
 ↓ reads project-level status.md + all modules/*/status.md + current skills/agents
 ↓ writes structured proposals to project-planning/retrospective/drafts/
 ↓ updates proposed-changes.md summary
 [Stop → hook prints: "Review proposals in project-planning/retrospective/proposed-changes.md"]
 [HUMAN REVIEWS proposed-changes.md]
 [HUMAN SELECTIVELY APPLIES approved proposals — see Project-Level Skill Creation Workflow below]
```

---

## Project-Level Skill Creation Workflow

Any agent can observe a pattern worth codifying. The flow from observation to applied skill:

```
1. Agent encounters a recurring pattern, useful convention, or gap
   ↓ writes one brief entry to status.md ## Skill Recommendations
     Format: "Pattern: <what was observed> | Why: <why it should be a skill> | Agent: <who>"

2. Human reviews ## Skill Recommendations at any checkpoint or on demand

3. Human invokes Retrospective
   ↓ reads status.md ## Skill Recommendations + full history + current skill/agent files
   ↓ writes a structured proposal for each recommendation to
     project-planning/retrospective/drafts/<skill-name>.proposal.md
   ↓ summarises all proposals in project-planning/retrospective/proposed-changes.md
   (Retrospective never writes to .claude/ — proposals only)

4. Human reviews project-planning/retrospective/drafts/<proposal>.md
   and decides which proposals to apply

5. Human tells Claude Code directly (not through any subagent):
   "Use the create-agent-skills skill to create a project-level skill
    based on project-planning/retrospective/drafts/<proposal-file>.md"

6. Claude Code (as itself, not as any subagent) creates the skill under
   <project-root>/.claude/skills/<skill-name>/
   following the standard skill architecture pattern (SKILL.md + workflows/ + references/ + scripts/)

7. All agents automatically pick up the new skill on next invocation
   (reference it by name in their agent definition or invoke it inline)
```

**Key invariant**: No agent ever writes to `.claude/skills/`. Doc-Sync is the only agent that may write to `.claude/agents/`, and only to generate per-module engineer and QA wrappers (`engineer-mod-*.md`, `qa-mod-*.md`) — not to modify any other agent definition. All other `.claude/agents/` changes and all `.claude/skills/` changes require explicit human instruction. Claude Code applies skill and agent changes only after explicit human instruction using the `create-agent-skills` skill.

---

## Status.md Structure

Status is split across two tiers: one project-level file and one per-module file.

### Project-Level: `project-planning/status.md`

The coordination hub for project-wide state. Every agent writes Last Action here before stopping (so `handoff.sh` has one place to parse). PM, Doc-Sync, and Tech Lead write their respective sections here. Engineering Progress and QA Results are **not** in this file — they live in the module-level files.

```markdown
# Project Status

## Last Action
<!-- Machine-readable block. Updated by every agent before stopping.
     handoff.sh parses this section to determine the next suggestion. -->
agent: [pm|doc-sync|tech-lead|engineer-mod-<name>|qa-mod-<name>|retrospective]
mode: [init|change|checkpoint|delta|trivial|review|implement|bugfix|verify|regression|propose]
module: [module directory name or "n/a"]
result: [success|bugs-found|spec-issue|blocked|proposals-written]
commit: [git commit hash]
timestamp: [ISO 8601]

## Current Phase
<!-- Written by Doc-Sync during initial sync — PM must leave this section blank -->
[Phase name/number, which modules are in scope]

## Phase Plan
<!-- Written by Doc-Sync during initial sync — PM must leave this section blank -->
[Derived from PRD Phases & Milestones by Doc-Sync]

## Build Config
<!-- Filled by PM during init. PM asks the user for the project's build, lint, and test
     commands and writes them here. Doc-Sync copies these to production.md Shared Conventions
     during the initial sync. Leave a value blank if that step doesn't apply. -->
Build: [build command]
Lint:  [lint command]
Test:  [test command]

## PM Updates
[Change summaries: what changed in PRD, when, why. Initial creation tagged [INIT]. Subsequent changes tagged [TRIVIAL] or [SUBSTANTIVE]]

## Tech Lead Reviews
[Findings, recommendations, approved/flagged items]

## Sync Reports
[Doc-Sync output: what was synced, any ambiguities found]

## Decisions
[Audit trail for resolved disagreements and key choices. Each entry: what was decided, who decided (human/PM/Tech Lead), the rationale, and which IDs are affected]

## Module Map
<!-- Filled by PM during init. Maps MOD-IDs to directory names for Doc-Sync and Engineer.
     Updated by PM when modules are added or renamed during change requests. -->
| MOD-ID | Directory | Module Name |
|--------|-----------|-------------|

## Checkpoint History
[Phase completion confirmations from user, with git commit hash for each checkpoint]

## Skill Recommendations
<!-- Any agent may append an entry here when it notices a recurring pattern, useful convention,
     or gap worth codifying as a skill. No agent may edit or remove another agent's entries.
     Retrospective reads this as a primary input. Human reviews at checkpoint or anytime. -->
<!-- Format per entry:
     Pattern: <what was observed>
     Why: <why it should be a skill>
     Agent: <who logged it> -->
```

### Module-Level: `project-planning/modules/mod-xxx/status.md`

One file per module. Created by Doc-Sync during initial sync (and when a new module is added). Engineer writes Engineering Progress; QA writes QA Results. PM reads all module-level status files during checkpoint reviews.

```markdown
# mod-xxx Status

## Engineering Progress
<!-- Written by engineer-mod-xxx. Self-check results (automated + integration + manual),
     blocker entries. Updated before every engineer commit. -->
<!-- Format: pass/fail per checklist item; blockers prefixed with [BLOCKER] -->

## QA Results
<!-- Written by qa-mod-xxx. Pass/fail per acceptance criterion with specific failure details.
     Updated before every QA commit. -->
<!-- Format: AC-NNN: pass — or — AC-NNN: fail — <specific reproducible description> -->
```

---

## File Manifest

Complete list of files to create, in order:

### Skills (create first — agents reference them)

| # | File | Description |
|---|---|---|
| 1 | `.claude/skills/prd-format/SKILL.md` | Router + principles + quality checklist + change protocol |
| 2 | `.claude/skills/prd-format/templates/prd.tmpl.md` | Blank PRD skeleton with placeholder text |
| 3 | `.claude/skills/prd-format/references/writing-standards.md` | Detailed writing guidance with good/bad examples |
| 4 | `.claude/skills/prd-format/references/anti-patterns.md` | Common PRD mistakes with corrections |
| 4a | `.claude/skills/prd-format/references/readme-standards.md` | README writing standards and quality checklist — used by PM at final checkpoint |
| 5 | `.claude/skills/prd-format/scripts/init-project.sh` | Scaffolds project-planning/ directory |
| 6 | `.claude/skills/doc-sync-methodology/SKILL.md` | Router + mapping rules + principles |
| 7 | `.claude/skills/doc-sync-methodology/workflows/initial-sync.md` | First sync step-by-step |
| 8 | `.claude/skills/doc-sync-methodology/workflows/delta-sync.md` | Change propagation step-by-step |
| 9 | `.claude/skills/doc-sync-methodology/templates/production.tmpl.md` | Structure for production.md |
| 10 | `.claude/skills/doc-sync-methodology/templates/module-spec.tmpl.md` | Structure for module specs |
| 11 | `.claude/skills/doc-sync-methodology/references/translation-rules.md` | Integrity guardrails with examples |
| 12 | `.claude/skills/doc-sync-methodology/scripts/verify-sync.sh` | Automated sync verification |
| 13 | `.claude/skills/coding-conventions/SKILL.md` | Default conventions + routing |
| 14 | `.claude/skills/coding-conventions/references/style-examples.md` | Before/after code examples |
| 15 | `.claude/skills/engineer-checklist/SKILL.md` | Checklist items + process |
| 16 | `.claude/skills/engineer-checklist/scripts/self-check.sh` | Automated pre-QA checks |
| 17 | `.claude/skills/qa-checklist/SKILL.md` | Checklist + routing |
| 18 | `.claude/skills/qa-checklist/workflows/functional-test.md` | First-time verification procedure |
| 19 | `.claude/skills/qa-checklist/workflows/regression-test.md` | Re-verification after bug fix |
| 20 | `.claude/skills/qa-checklist/scripts/run-qa.sh` | Automated test runner + reporter |
| 21 | `.claude/skills/qa-checklist/references/common-failure-patterns.md` | Known gotchas (living doc) |

### Agents (create second — they reference skills)

| # | File | Description |
|---|---|---|
| 22 | `.claude/agents/pm.md` | PM agent definition |
| 23 | `.claude/agents/doc-sync.md` | Doc-Sync agent definition |
| 24 | `.claude/agents/tech-lead.md` | Tech Lead agent definition |
| 25 | `.claude/agents/retrospective.md` | Retrospective agent definition |
| 26 | `.claude/agents/templates/engineer.md` | Engineer base template — not directly invokable; Doc-Sync reads this to generate per-module wrappers |
| 27 | `.claude/agents/templates/qa.md` | QA base template — not directly invokable; Doc-Sync reads this to generate per-module wrappers |

> **Note**: Per-module engineer and QA agent wrappers (`engineer-mod-<name>.md`, `qa-mod-<name>.md`) are generated dynamically by Doc-Sync during each sync — they are not manually created files and are not included in this static manifest.

### Hooks & Config (create third)

| # | File | Description |
|---|---|---|
| 28 | `.claude/hooks/handoff.sh` | Stop/SubagentStop handoff hook |
| 29 | `.claude/hooks.json` | Hook registration |

**Total: 30 files**

---

## Implementation Notes for Claude Code

### Skill Authoring Conventions
- Use the `create-agent-skills` skill for authoring guidance
- SKILL.md uses semantic XML tags (`<objective>`, `<essential_principles>`, `<routing>`, `<success_criteria>`), not markdown headings in the body
- SKILL.md under 500 lines — split detailed content into workflows/, references/, templates/, scripts/
- Descriptions should be "pushy" — include specific trigger phrases so Claude Code knows when to load the skill
- Load only what's needed: SKILL.md routes to the right workflow/reference, workflows specify which references to read

### Skill Integrity Rules

These rules prevent structural gaps that silently degrade skill quality. Apply them when creating or updating any skill.

**Routing completeness**:
- Every routing entry for a *creation* task must include the relevant reference material at the point of use — not just as a separate lookup. If anti-patterns or writing standards exist, the creation route must say "review against X before finalizing," not assume the author will think to check separately
- If a reference file exists in the skill, it must appear in at least one routing entry. Orphan references are invisible to the agent

**Checklist–ID consistency**:
- If the skill introduces an ID scheme (US-NNN, MOD-NNN, AC-NNN, or any custom ID), the quality checklist must validate *every* ID type: uniqueness, correct grouping, and cross-reference integrity. Don't validate some IDs and silently skip others

**Template–standards alignment**:
- Every pattern described in a writing-standards or reference doc must be demonstrated in the corresponding template. If the standards say "you can group ACs by module or by user story," the template must show both (the default inline, the alternative as a commented example). Standards without template backing get ignored
- Templates should include metadata headers for downstream consumers (revision number, last-updated date, or any field that helps other agents confirm they're reading the current version)
- Templates should note cleanup requirements (e.g., "remove all HTML comments before handoff") and the quality checklist must verify that cleanup happened

**Change protocol re-validation**:
- Any skill with both a quality checklist and a change protocol must require re-running the full checklist after every change — not just before initial handoff. Changes can silently break previously-passing checks

**Principle–reference coverage**:
- Every concept named in `<essential_principles>` must have corresponding guidance in `references/` or `workflows/`. If "non-goals" are called out as important, there must be writing guidance for non-goals and an anti-pattern for missing non-goals. Principles without reference backing are aspirational, not actionable

**Script defensiveness**:
- Every script that resolves paths (to templates, configs, or other skill files) must include a defensive check: verify the target file exists before operating, and exit with a clear error message if not found. Never assume directory structure is intact — symlinks, relocations, and partial installations happen

### Generating Agents
- Use the `create-subagents` skill for each agent file
- Agent definitions should be concise — the system prompt portion should focus on role, constraints, and handoff rules
- Reference skills by name in the system prompt (e.g., "Read and follow the prd-format skill")
- Retrospective agent must have `disable-model-invocation: true` in frontmatter
- Scope tools per agent as specified in the Write Access Matrix
- `engineer.md` and `qa.md` are **base templates** — Doc-Sync generates thin per-module wrappers (`engineer-mod-<name>.md`, `qa-mod-<name>.md`) during each sync. Each wrapper: (a) references the same engineer-checklist and coding-conventions skills, (b) hardcodes the assigned module path (`modules/mod-<name>/spec.md`) in its constraints so the agent can only read its assigned module spec, (c) hardcodes read access to the dependency modules' `modules/<dep>/status.md` files based on the module's dependency list, (d) uses the same system prompt body as the base agent. Never invoke the base `engineer.md` or `qa.md` directly for module work — always use the per-module wrapper.

### Agent Definition Rules

These rules prevent gaps between what skills teach and what agents enforce. Apply them when creating or updating any agent definition.

**Constraint mirroring**:
- If a skill contains a critical rule (e.g., "always confirm with user before writing"), that rule must also appear as an explicit constraint in every agent that uses that skill. Skill-level rules are suggestions; agent-level constraints are enforced. Don't rely on the agent reading the skill carefully — duplicate the non-negotiable rules

**Write scope exhaustiveness**:
- Every file an agent can create or modify must be listed in its Write Scope. If the agent commits to git, `status.md` must be in its Write Scope (since Last Action is updated there). If a workflow requires creating a new file type (e.g., a new module spec), the write scope must cover the directory pattern (`modules/*/spec.md`), not just the known filenames

**Information boundary justification**:
- If an agent is denied access to a file, consider whether the agent's workflows will frequently need context from that file. If so, the file they *do* have access to must carry that context forward (e.g., the module spec's Context section carries forward PRD rationale so the Engineer doesn't need `prd.md`). Every information boundary should have a corresponding "context bridge" in the downstream doc

### Generating Hooks
- Use the `create-hooks` skill for the handoff hook
- Register on `Stop` (primary, fires for CLI sessions) and `SubagentStop` (secondary, fires for Task-tool subagents) events
- The hook reads `status.md` to determine context and prints the appropriate suggestion
- Make executable with `chmod +x`
- Register in `.claude/hooks.json` (project) or `~/.claude/hooks.json` (account-level)

### Script Conventions
- All scripts are bash, POSIX-compatible where possible
- All scripts take project root path as argument (don't assume cwd)
- All scripts output structured results to stdout
- Exit code 0 = success, non-zero = failure with details
- Scripts read configuration from `production.md` rather than hardcoding tools/commands
- All scripts must be executable (`chmod +x`)

### Git Commit Convention
- Every agent commits its work before `SubagentStop` fires — each handoff is a clean rollback point
- Commit message format: `<agent-name>(<mode-or-module>): <one-line summary>`
  - Examples: `pm(init): initial PRD for payment service`, `doc-sync(delta): synced MOD-004 addition`, `engineer-mod-module-2(implement): implement order processing`, `qa-mod-module-2: pass — all 12 acceptance criteria verified`
- Agents commit only files within their write scope — never stage files outside their access boundary
- `handoff.sh` checks for uncommitted changes in the stopping agent's write scope and warns if found
- Checkpoint History entries in `status.md` record the git commit hash alongside phase completion notes, providing named rollback points for major milestones
- To roll back to a previous handoff: `git log --oneline` to find the handoff commit, then `git revert <hash>` or `git reset --hard <hash>` depending on whether the rollback itself should be tracked

### Order of Creation
1. Skills first (agents reference them) — files 1-21
2. Agents second (hooks reference agent names) — files 22-27 (base templates only)
3. Hooks and config third — files 28-29
4. `project-planning/` folder structure is created per-project by PM via `init-project.sh`
5. Per-module agent wrappers (`engineer-mod-*.md`, `qa-mod-*.md`) are generated by Doc-Sync during the initial sync — not manually created

### Installation
After all files are created and reviewed in the staging directory:
```bash
cp -r .claude/agents/ ~/.claude/agents/
cp -r .claude/skills/ ~/.claude/skills/
cp -r .claude/hooks/ ~/.claude/hooks/
# Merge hook entries into existing ~/.claude/hooks.json (Stop and SubagentStop events)
```

To start a new project:
```bash
cd ~/projects/my-new-app
claude --agent pm
```