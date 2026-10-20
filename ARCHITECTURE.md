# Development Team Agents — Complete Architecture

This document defines the complete architecture for a multi-agent development team system built with Claude Code agents, skills, and hooks. It is the single source of truth for generating all files.

---

## System Overview

A team of 6 specialized agents that simulate a software development workflow with strict information boundaries, file-based coordination, and human approval at every handoff. Each agent runs as a completely independent `claude --agent <name>` session — no shared memory, coordinating exclusively through files on disk. Skills provide reusable knowledge that agents consume using a router + progressive disclosure pattern. Hooks print the exact `claude --agent <name>` command to run next; the human approves before running it. The default Claude Code session acts as the **coordinator**: it diagnoses, tells the human which agent to run, and runs the pstack review steps whose findings Tech Lead reads — it never edits an owned artifact itself.

### Core Principles

- **Single responsibility**: Each agent has one job, one input, one output, one handoff rule
- **Information boundaries**: Agents only access the files they need — no agent sees everything
- **Human in the loop**: Hooks suggest the next step; the human approves before proceeding
- **PRD as source of truth**: All downstream docs derive from `prd.md` through the Doc-Sync agent — no other agent modifies downstream planning docs
- **Propose before apply**: System-level changes (skills, agent definitions) go through a staging/review process
- **Progressive disclosure**: SKILL.md files stay lean (under 500 lines) as routers; detailed content lives in workflows/, references/, templates/, and scripts/ — loaded only when needed
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

Every framework agent runs as its own direct session, started by the human: `claude --agent <name>`. The coordinator (the default Claude Code session) never starts framework agents as subagents — a subagent cannot ask the human anything, so PM's approvals, QA's UI sign-off, and Tech Lead's evidence requests would break, and the handoff hook's message reaches only the human. The coordinator tells the human which agent to run and what to say to it, and runs the pstack steps itself (see Handoff Chains → pstack Steps).

### PM

- **File**: `.claude/agents/pm.md` (model: opus)
- **Single Responsibility**: Own `prd.md` + all user communication
- **Tools**: Read, Write, Grep, Glob, Bash, Skill (allowlist: `prd-format`, `pstack:sharpen`, `pstack:unslop`, `pstack:technical-writing` — enforced by `pstack-guard.sh`). `sharpen` runs once at the start of init; `unslop`/`technical-writing` only on prose PM wrote or changed in this invocation, wording only — every ID, number, and AC must mean the same afterwards
- **Write Scope**: `prd.md`; project-level `status.md` PM sections only (Last Action, Build Config, PM Updates, Module Map — PM is the only agent `pstack-guard.sh` lets change it — Checkpoint History, Decisions (user decisions that are not PRD content, e.g. "defer offline mode to v2"), Skill Recommendations, and Current Phase — advance only, at checkpoint); `modules/mod-*/` directory + `.gitkeep` creation only (never files inside a module directory); `README.md` at the project root, final checkpoint only
- **Read-only exceptions**: `production.md` and `setup.md` for the final README; `integration-review.md` for the checkpoint gate; `modules/*/status.md` in change and checkpoint mode (escalations and QA results live there)
- **Skills Used**: prd-format
- **Invocation**: `claude --agent pm`, usually with the mode word the hook prints (`"iterate"`, `"finalize"`, `"change"`, `"checkpoint"`). Without one, PM picks the mode from where the project is, top rule first; when both checkpoint and change apply, checkpoint wins (a change the user also wants comes after it)
- **Modes**:
  - `init` (no `project-planning/` yet): run `pstack:sharpen` on the request, then restate the goal in two or three sentences and wait for the user to correct it; run `scripts/init-project.sh`; gather requirements through numbered questions; fill `prd.md` from `templates/prd.tmpl.md`; review against `references/anti-patterns.md` and the quality checklist; confirm with the user before writing; commit. Next: Tech Lead
  - `iterate` (PRD drafted, `[INIT]` not yet tagged): apply Tech Lead feedback or user edits using the pre-sync iteration protocol — no `[TRIVIAL]`/`[SUBSTANTIVE]` tags. Notes in PM Updates which Tech Lead Reviews entry each change answers (never writes in Tech Lead Reviews). A `Proposed Convention:` the user approves goes into section 9 Adopted Conventions as the next `CONV-NNN` right away — the initial sync copies it
  - `finalize` (user gave final approval): **setup gate** — a `### Setup Confirmation` block must exist in Tech Lead Reviews and no `### Setup Changed` entry may be newer than it; write Build Config (`Build:` / `Lint:` / `Test:`); propose and confirm the **Module Map** — a `mod-<kebab-name>` directory and a **Source Path** per module (no path claimed by two modules, and none nested inside another — `src/` and `src/ui/` cannot both appear; shared code has one owner module) plus a `Project files: <dir> | <paths>` line naming the one module that owns the root-level files no Source Path covers (package manifests, lockfiles, `.env.example`, CI config) — then create each directory with `.gitkeep`; tag a PM Updates entry `[INIT]`. Next: Doc-Sync
  - `change` (`[INIT]` already tagged): a requirements change from the user, an escalation read from `modules/<mod>/status.md`, or Doc-Sync's `[AMBIGUITY]`/`[CONFLICT]`/`[BLOCKER]` questions in Sync Reports. Smallest change, quality checklist, confirm with the user, tag `[TRIVIAL]` or `[SUBSTANTIVE]` (answers to Doc-Sync questions are always `[SUBSTANTIVE]` and list each marker they resolve). A Tech Lead convention the user approved goes into PRD section 9 **Adopted Conventions** as the next `CONV-NNN`, citing its Tech Lead Reviews entry, tagged `[SUBSTANTIVE]`. A changed build, lint, or test command updates `## Build Config` and is tagged `[TRIVIAL] Build Config changed`, so Doc-Sync's passthrough copies it into `production.md` (which `self-check.sh` and `run-qa.sh` read). A new module gets its directory, Source Path, and Module Map row before the handoff. Increments the PRD revision
  - `checkpoint` (`[INIT]` tagged, every module in the current phase passed QA, and every integration-review row for the phase resolved): **gate** — `integration-review.md` must exist, Tech Lead Reviews must have an Integration & Optimization Review entry for the current phase, and every row for the phase must be `CONFIRMED CLOSED`, `REJECTED`, `DEFERRED`, or `NO ISSUES`; anything else (`PROPOSED` through `HUMAN VERIFIED`) is open and stops the checkpoint. Then compile module results, present them, get explicit approval, write `Phase <N> approved — <date> — commit: <hash>` to Checkpoint History, and advance `## Current Phase` to the next phase. On the final phase: write `README.md` per `references/readme-standards.md` (confirmed with the user) and record `result: project-complete`
- **Input**: User requirements, change requests, escalations in `modules/*/status.md`, Doc-Sync questions in Sync Reports, Tech Lead Reviews
- **Output**: Approved `prd.md` + tagged change summary in `status.md`
- **Handoff**:
  - After `init`: → Tech Lead (init review)
  - After `iterate`: → Tech Lead (pre-sync review) if the changes are architectural; otherwise PM `finalize` once the user approves
  - After `finalize`: → Doc-Sync (initial sync)
  - After `change`: → coordinator runs `/pstack:how`, then Tech Lead (change review) if architectural; otherwise → Doc-Sync
  - After `checkpoint`: → `engineer-mod-<first module of the new Current Phase> "implement"` (specs for every phase already exist from the initial sync), or project complete
- **Constraints**:
  - Never writes to `prd.md` without explicit user approval — silence, "maybe", or a follow-up question is not approval
  - Never tags `[INIT]` without a `### Setup Confirmation` entry in `status.md` (and none superseded by a newer `### Setup Changed`) — a coordinator's or anyone's assertion is not enough; the artifact must be in the file
  - Never runs checkpoint without the phase-end review complete — same standard: the file must show it
  - Never makes technical decisions — PM decides *what*, Tech Lead decides *how*
  - If requirements are ambiguous, asks numbered questions and waits; no `[DECISION NEEDED]` markers remain at handoff
  - Runs the full quality checklist before every handoff, not just the first draft
  - Never touches `production.md`, `modules/*/spec.md`, `integration-review.md` (except the read at checkpoint), source code, or `.claude/` files (its own `~/.claude/skills/prd-format/` is the exception)
  - Commits before stopping: `git commit -m "pm(<mode>): <summary>"`

### Doc-Sync

- **File**: `.claude/agents/doc-sync.md` (model: sonnet)
- **Single Responsibility**: Translate `prd.md` content into downstream planning docs — nothing more, nothing less
- **Tools**: Read, Write, Grep, Glob, Bash (no `Skill` — `pstack-guard.sh` gives Doc-Sync an empty allowlist; it must never run a rewriting skill on its output)
- **Write Scope**: `production.md`; `modules/*/spec.md`; `modules/*/status.md` (created with empty Engineering Progress + QA Results sections at initial sync and when a module is added); project-level `status.md` Last Action, Sync Reports, Phase Plan, Skill Recommendations, and Current Phase (set once, at initial sync — PM advances it after that); `.claude/agents/engineer-<dir>.md` and `.claude/agents/qa-<dir>.md` (generated wrappers)
- **Skills Used**: doc-sync-methodology
- **Invocation**: `claude --agent doc-sync`, after every PM tag (`[INIT]`, `[SUBSTANTIVE]`, `[TRIVIAL]` — trivial included)
- **Input**: `prd.md` (read-only) + PM Updates, Module Map, and Build Config in `status.md`
- **Output**: Updated downstream docs + sync report in `status.md`
- **Workflow Selection** (from the PM Updates tag):
  - `[INIT]`: follow `workflows/initial-sync.md`
  - `[SUBSTANTIVE]`: follow `workflows/delta-sync.md` — syncs **every** PM Updates entry dated after the last Sync Report, oldest first
  - `[TRIVIAL]`: passthrough — propagate the wording to affected docs, write a brief sync note, skip `verify-sync.sh`. A `[TRIVIAL] Build Config changed` entry means: copy `status.md` Build Config into `production.md` Shared Conventions again
  - No tag or unclear tag: write an `[AMBIGUITY]` entry to Sync Reports and stop
- **Per-module wrappers**: for each module, Doc-Sync generates `engineer-<dir>.md` and `qa-<dir>.md`, where `<dir>` is the Module Map directory (`mod-login` → `engineer-mod-login`). They are built from `~/.claude/agent-templates/engineer.md` and `qa.md`: the template's frontmatter `tools` and `model` lines are copied exactly and its body verbatim, `name:` is set to the wrapper name, and the wrapper hardcodes the module's spec path, its Source Path, and read access to each dependency module's `status.md`. A delta sync regenerates the wrappers of every module whose Source Path, dependencies, or directory changed, so no wrapper names an old Source Path. After a sync that adds a wrapper, the human opens a new terminal so it loads
- **Handoff**: `result: success` → human reviews the sync report → `engineer-mod-<first module in the Phase Plan not yet built> "implement"`. `result: needs-pm` → `pm "change"` before any engineering starts
- **Post-Sync**: Run `scripts/verify-sync.sh` until it exits 0 (initial and substantive syncs only). **BLOCKER exception**: if every remaining `[FAIL]` concerns a module skipped with a `[BLOCKER]` (missing directory or Module Map row — Doc-Sync cannot create directories), stop looping, record `result: needs-pm`, and commit
- **Constraints**:
  - Translator, not interpreter — restructure and distribute PRD content only, never add or infer
  - Every concern goes back to PM, never into the docs: gaps, risks, or better ideas become an `[AMBIGUITY]` or `[CONFLICT]` marker plus a Sync Reports entry. Whenever any such marker or a `[BLOCKER]` is placed, the handoff message lists them and Last Action records `result: needs-pm`
  - Integration Points come only from an explicit PRD integration requirement, never from a bare `Dependencies` field — otherwise `[AMBIGUITY]` + forced PM handoff
  - Shared Conventions in `production.md` come only from `status.md` Build Config and PRD section 9 Adopted Conventions (verbatim, with CONV IDs) — never from Tech Lead Reviews
  - Never modifies `prd.md`; never communicates with the user directly; never runs `pstack:unslop`, `pstack:technical-writing`, or any rewriting skill on its output
  - Delta only on substantive syncs; never deletes a module spec — a removed module gets a `[REMOVED IN PRD REVISION <N>]` notice
  - Never modifies PM Updates, Tech Lead Reviews, Decisions, Module Map, Build Config, or Checkpoint History
  - May write skill recommendations to `status.md ## Skill Recommendations` — one brief entry: pattern + why
  - Commits before stopping: `git add project-planning/ .claude/agents/ && git commit -m "doc-sync(<initial|delta|trivial>): <summary>"`

### Tech Lead

- **File**: `.claude/agents/tech-lead.md` (model: opus)
- **Single Responsibility**: Architectural advisory — evaluate feasibility, identify risks, recommend decisions. Never decides, never implements
- **Tools**: Read, Write, Grep, Glob, Bash, Edit (no `Skill` — empty allowlist in `pstack-guard.sh`; pstack findings reach it as files in `project-planning/pstack-findings/`)
- **Write Scope**:
  - `status.md` — Tech Lead Reviews, Skill Recommendations, and Last Action
  - `project-planning/setup.md`, `docker-compose.yml` (backend projects only), and `.gitignore` (created first, before `.env.example`) — created in init review; updated only (a) in a pre-sync review when the tech stack or infrastructure changed, or (b) after `[INIT]`, in an on-demand review where the human approves the change in the session (e.g. QA found `setup.md` out of step with the real infrastructure). Every update adds a `### Setup Changed — <date>` entry listing what the human must redo and records `result: setup-changed`
  - `.env.example` (backend projects only) — created in init review (and updated in a pre-sync review that changes setup). After `[INIT]` it belongs to the project files owner (Module Map `Project files:` line), whose Engineer adds new variables
  - `project-planning/integration-review.md` — creates it from the template; owns `PROPOSED` / `NO ISSUES` / `CONFIRMED CLOSED`; records the human's `APPROVED` / `REJECTED` / `DEFERRED` decisions (with Assigned Module) and `HUMAN VERIFIED` exactly as the human states them in the session. Never sets `IN PROGRESS`, `FIXED – AWAITING QA`, or `QA VERIFIED`
  - `modules/<mod>/status.md` — only the single `AC-<ID>: ESCALATED TO TECH LEAD — open` line, only during a repeat-failure review of that module
- **Skills Used**: coding-conventions (reference), integration-review (phase-end review, record decisions, confirm fix) — both read as files, not through the `Skill` tool
- **pstack findings**: when a findings file exists for the invocation, Tech Lead reads it as evidence, checks every finding against the code or docs, adds a `pstack input:` line naming the file, and lists which findings it accepted (with its own location and failure scenario) and rejected (with a reason). If the project `CLAUDE.md` calls for a findings file and none exists, it says so at the top of the review and continues
- **Modes** (Last Action `mode`):
  - `init-review` — mandatory review of the first PRD draft (`production.md` does not exist yet): checks installed tool versions against the Tech Stack, evaluates feasibility, risks, dependencies, gaps, shared conventions, and overlapping modules; creates `.gitignore`, `setup.md` (ending with a Setup Confirmation section, and naming the exact build command — Build Config does not exist yet), and for backend projects `.env.example` and `docker-compose.yml`. Init is stack-neutral: `.gitignore` entries come from the PRD tech stack (always `.env`, IDE/OS files, logs; plus Java/Maven, Node/Vite, Python — `__pycache__/`, `.venv/`, `.pytest_cache/` and the like — and any other build, cache, or coverage output the stack produces); `setup.md` covers every API key or secret the PRD needs, with no stack-specific steps baked in
  - `pre-sync-review` — re-review of a PM `iterate` revision the human judged architectural; reviews only what changed. If the revision changes the tech stack or infrastructure, updates `setup.md` (and the infrastructure files), adds a `### Setup Changed — <date>` entry listing what the human must redo, and records `result: setup-changed`
  - `setup-confirmation` — the human says "Setup is complete": verifies that every service `docker-compose.yml` defines is running (`docker compose ps`, backend) or that the build command named in `setup.md` exits cleanly (frontend-only), checks `.env` for existence and gitignore status only, and records `### Setup Confirmation — <date>` stating what it ran and saw. Also used after `[INIT]`, when an on-demand review changed setup
  - `change-review` — a mid-project PRD change the human judged architectural
  - `on-demand-review` — an Engineer `blocked-technical` blocker (from `modules/<mod>/status.md` Engineering Progress), a QA pattern suggesting a design problem, QA-reported setup drift (`setup.md` out of step with the real infrastructure — Tech Lead updates it with the human's approval, `result: setup-changed`), or a blast-radius report that changes the plan for an integration fix
  - `integration-review` — mandatory phase-end review after every module in the current phase passes QA; `result: clean` (a `NO ISSUES` row) or `issues-found`
  - `record-decisions` — the human's approve / reject / defer decisions on `PROPOSED` items (`workflows/record-decisions.md`)
  - `confirm-fix` — records `HUMAN VERIFIED` from the human's own statement ("INT-003 verified: …") on a `QA VERIFIED` item, re-checks the failure scenario, then sets `CONFIRMED CLOSED` or sends it back to `APPROVED`
  - `repeat-failure-review` — the same AC failed a 3rd time, or failed again under an open escalation marker; Last Action also records `module:` and `ac: <AC-ID>`
  - Every mode may also record `result: needs-human` when it is waiting on the human, and any mode that changed setup files records `result: setup-changed`
- **Shared code ownership**: when modules overlap (init review, or whenever a module is added), Tech Lead proposes an **owner** before engineering starts. Shared code has exactly one owner module: an existing module that naturally owns it (the video player belongs in `mod-player`, `mod-feed` depends on it), or, when none fits, a new module named for what it is (`mod-header`, `mod-ui-kit` — never `mod-shared`), placed earlier in the Phase Plan. Tech Lead names the owner and its proposed Source Path; PM adds a new module through a PRD change. If modules already built hold copies of the code, moving it is not part of that PRD change: after Doc-Sync creates the owner, Tech Lead logs one `integration-review.md` row per module that must delete its copy and use the owner, so each goes through the normal fix → QA → human → confirm loop. Merging modules is a separate, explicitly higher-impact recommendation
- **Conventions**: proposed as `Proposed Convention:` lines in Tech Lead Reviews. They reach `production.md` only one way: the user approves → PM adds them to PRD section 9 Adopted Conventions → Doc-Sync copies them into Shared Conventions
- **Input**: `prd.md` + `production.md` (if it exists) + `status.md` + `integration-review.md` + pstack findings + for blocker/repeat-failure reviews, the relevant `modules/<mod>/status.md` and `spec.md`
- **Output**: Findings in `status.md` Tech Lead Reviews (Concerns, Recommendations, Approved, Proposed Shared Conventions) + infrastructure files at init + `integration-review.md` rows at phase end
- **Handoff**: always returns to the human (see the hook's per-mode messages under Hooks)
- **Constraints**:
  - Never reads, greps, or uses the contents of `.env` — existence and gitignore checks only
  - Advisory only — never writes to `prd.md`, `production.md`, or `modules/*/spec.md`; never implements anything
  - Every module in the phase must be read before an integration review is complete — no sampling
  - Never closes an `integration-review.md` item without `HUMAN VERIFIED`, and records that only from the human's own statement in the session
  - A fix or optimization that changes user-facing behavior is a PRD change → PM, not an integration-review item
  - On a repeat-failure review: requires real evidence of which layer caused the bug, never a guessed diagnosis; asks the human for a specific check if the evidence does not exist yet. Stays the owner of that AC until QA flips the marker to resolved
  - Appends to Skill Recommendations; never edits other agents' entries
  - Commits before stopping: `git commit -m "tech-lead(<mode>): <summary>"` (init review and any review that changed setup files also stage `setup.md`, `.gitignore`, and the backend infrastructure files)

### Engineer

- **File**: `.claude/agent-templates/engineer.md` (base template, model: sonnet) → generated `.claude/agents/engineer-<dir>.md` per module. Always run the wrapper, never the base template
- **Single Responsibility**: Implement one assigned module
- **Tools**: Read, Write, Edit, Bash, Grep, Glob, Skill (allowlist: `coding-conventions`, `engineer-checklist`, `pstack:tdd`, `pstack:deslop`, `pstack:typescript-best-practices`). These serve the spec and never widen it
- **Write Scope**: source code within the module's **Source Path** (its Module Map row) + the project files (manifests, lockfiles, `.env.example`, CI config on the Module Map `Project files:` line) if this module is their owner + its own planning files: `modules/<dir>/status.md` (Engineering Progress — never its `spec.md`), project-level `status.md` (Last Action and Skill Recommendations), and `integration-review.md` (`Status`/`Notes` on rows assigned to this module, `IN PROGRESS`/`FIXED – AWAITING QA` only). Ownership is decided by longest matching path. The rules live in one shared helper, `engineer-checklist/scripts/module_scope.py`, and are enforced twice: `self-check.sh` fails on any change outside the scope, and `pstack-guard.sh` blocks Write/Edit calls outside it at the tool level (and blocks every write when the module has no Module Map row)
- **Skills Used**: coding-conventions, engineer-checklist
- **Invocation**: `claude --agent engineer-mod-<name> "<word>"` — the mode comes from the first word, which the hook always prints: `"implement"`, `"bugfix"` (including `"bugfix — follow Tech Lead's repeat-failure diagnosis for AC-NNN"`), or `"integration-fix <INT-ID>"`. With no word, Engineer decides from the module's history (an `APPROVED` integration-review row assigned to it → integration-fix; QA failures newer than its last entry → bugfix; otherwise implement) and says which it chose in Engineering Progress
- **Modes** (Last Action `mode`, the bare word only — an INT-ID goes in Engineering Progress): `implement`, `bugfix`, `integration-fix`
- **Input**: `production.md` + its own `modules/<dir>/spec.md` + its own `modules/<dir>/status.md` + dependency modules' `status.md` (read-only) + Tech Lead's diagnosis when fixing an AC under an open escalation marker + the assigned `integration-review.md` row for an integration fix
- **Output**: Working code + self-check results in `modules/<dir>/status.md` Engineering Progress
- **Self-Check Process**: Step 0 on the project's first module only — infrastructure pre-flight (`.env` presence if `setup.md` requires it, every service `setup.md` lists is reachable; on failure `result: needs-human`). Then `self-check.sh` (build, lint, tests, write-scope check), the project's integration-test command if `production.md` or `setup.md` names one, and the judgment items. The checklist is stack-neutral: universal items always apply; items under "Only if your stack matches" (Jest + real DB teardown, LLM model IDs and prompt budgets, Spring Boot actuator/CORS/`@Order`, container architecture, React Native safe areas) apply only when the module uses that stack, and Engineer says which it skipped
- **Results** (Last Action `result`): `success`, `blocked-dependency` (a module this one depends on has not passed QA), `blocked-technical` (cross-module design problem or a library not in `production.md`), `needs-human`
- **Handoff**: `success` → `qa-mod-<name> "verify"` (implement), `"regression"` (bugfix), or `"integration-fix-verify <INT-ID>"` (integration-fix). `blocked-dependency` → finish the dependency first (`pm "change"` if the phase order is wrong). `blocked-technical` → `tech-lead "engineer blocker in mod-<name>"`
- **Constraints**:
  - Reads only `production.md` and its assigned spec — no `prd.md`, no other module's spec. Any cross-module mounting condition it needs is already named in its spec's Integration Points
  - Scope = Requirements + Acceptance Criteria. The spec's Context explains *why* and never widens scope; behavior a user story implies but no AC covers is logged as a scope question for PM
  - If blocked by something outside its Source Path, writes the blocker to Engineering Progress and stops — never improvises or works across the boundary
  - No dependencies outside the `production.md` tech stack
  - Under an open repeat-failure escalation marker, implements per Tech Lead's diagnosis; without the diagnosis in hand, stops and asks the human for it
  - On an integration-review fix, touches only its own row and only moves it to `IN PROGRESS` / `FIXED – AWAITING QA`
  - Commits before stopping: `git commit -m "engineer-mod-<name>(<implement|bugfix|integration-fix>): <summary>"` — the exact `engineer-<dir>(` prefix is required, since `self-check.sh` uses it to find the module's own commits

### QA

- **File**: `.claude/agent-templates/qa.md` (base template, model: sonnet) → generated `.claude/agents/qa-<dir>.md` per module. Always run the wrapper
- **Single Responsibility**: Verify one module against its spec
- **Tools**: Read, Write, Bash, Grep, Glob, Skill (allowlist: `qa-checklist`, the project's `verify` skill)
- **Write Scope**: `modules/<dir>/status.md` QA Results (plus flipping an existing Tech Lead escalation marker to `— resolved <date>` when its own verification of that AC passes) + project-level `status.md` (Last Action and Skill Recommendations) + `integration-review.md` (`QA VERIFIED`, or back to `APPROVED` with a note, on rows assigned to this module). Never edits source code
- **Skills Used**: qa-checklist; `verify` (if `.claude/skills/verify/SKILL.md` exists) to check each AC in the running app, citing its evidence
- **Invocation**: `claude --agent qa-mod-<name> "<word>"` — the workflow comes from the invocation word:
  - `verify` → `qa-checklist/workflows/functional-test.md`
  - `regression` → `qa-checklist/workflows/regression-test.md`
  - `integration-fix-verify <INT-ID>` → `regression-test.md` against that `integration-review.md` row
  - `ui-results: <what the human observed>` → QA stopped earlier with `result: needs-human` and a test script; it records the human's reported outcome per AC exactly as stated ("AC-023: PASS — reported by the human <date>"), classifies any failures, routes as usual, and keeps the `mode` it recorded when it stopped
  - No word: QA decides from the module's history and says why in the first line of QA Results. The workflow is recorded as Last Action `mode`, as the bare word (`verify`, `regression`, `integration-fix-verify` — the INT-ID goes in QA Results)
- **Input**: `production.md` + its own `spec.md` + the code + its own `modules/<dir>/status.md`
- **Output**: Per-AC pass/fail with reproducible failure descriptions in `modules/<dir>/status.md`
- **Testing Process**: `run-qa.sh` (which fails when no test command is configured), then the judgment items. Server-side modules need a real running server — real endpoint calls and stored state, not just unit tests. UI modules need the `verify` skill, or a written test script handed to the human for sign-off with `result: needs-human` (the human answers with `"ui-results: …"`); QA never declares PASS on an AC nobody exercised in the running UI. Setup drift (`setup.md` ports or variables out of step with `docker-compose.yml` / `.env.example`) is a FAIL routed to Tech Lead, who owns `setup.md`; a variable missing from `.env.example` goes to the project files owner's Engineer
- **Results** (Last Action `result`): `success`, `bugs-found`, `spec-issue`, `setup-drift` (setup.md out of step with the infrastructure → Tech Lead), `repeat-failure` (with `ac: <AC-ID>` in Last Action, so the hook checks that AC's escalation marker), `needs-human`. One run records one result; when ACs fail for different reasons the precedence is **`spec-issue` > `repeat-failure` > `bugs-found`**, every failure is still listed, and the handoff message names the others
- **Handoff**:
  - Pass, more modules remain in the phase → `engineer-mod-<next-module> "implement"`
  - Pass, last module of the phase → coordinator runs `/pstack:thermos` → Tech Lead (integration review). Never straight to PM
  - Bugs (1st/2nd failure of this AC) → Engineer
  - 3rd failure, or an escalation marker already open → Tech Lead (repeat-failure review); on the first escalation the coordinator runs `/pstack:how` + `/pstack:why` first
  - Spec issue → PM
  - Integration fix verified → the human verifies it, then tells Tech Lead `"<INT-ID> verified: <what you checked>"`; fix does not hold → `engineer-mod-<name> "integration-fix <INT-ID>"`
  - Needs human sign-off → the human runs the test script, then `qa-mod-<name> "ui-results: …"`
- **Constraints**:
  - Verifies against the spec, not assumptions; every failure has input, expected, and actual
  - Spec problems go to PM, never to Engineer
  - Checks for an open escalation marker and counts prior failures of the AC before every bug-routing decision; never creates the marker
  - `QA VERIFIED` is not closed — the human and then Tech Lead still have to confirm
  - Commits before stopping: `git commit -m "qa-mod-<name>: <pass|fail> — <summary>"`

### Retrospective

- **File**: `.claude/agents/retrospective.md` (model: opus)
- **Single Responsibility**: Propose system improvements from project learnings
- **Tools**: Read, Write, Grep, Glob, Bash (no `Skill` — empty allowlist)
- **Write Scope**: `project-planning/retrospective/` only (`proposed-changes.md` and `drafts/<name>.proposal.md`)
- **Skills Used**: none
- **Invocation**: **manual only** — the human runs `claude --agent retrospective` when they want it; its description tells Claude never to invoke it automatically. It writes no Last Action block, and `handoff.sh` has no Retrospective branch, so no hook message follows it
- **Input**: project-level `status.md` (Skill Recommendations as primary input, Tech Lead Reviews, PM Updates) + all `modules/*/status.md` files + current skill and agent files (read-only) + user feedback
- **Output**: One proposal per candidate in `drafts/` (Evidence, Proposed Change, Target File, Impact, Risk) + a summary in `proposed-changes.md`, ordered by impact
- **Handoff**: Always to the human, who reviews `proposed-changes.md` and selectively applies approved proposals
- **Constraints**:
  - Never writes directly to `.claude/skills/` or `.claude/agents/`; read-only on every planning doc, `status.md` included
  - Every proposal traces back to specific incidents in `status.md`; vague Skill Recommendations are noted as "needs clarification", not dropped
  - Commits proposals before stopping: `git add project-planning/retrospective/ && git commit -m "retrospective: <summary>"`

---

## Skills

### prd-format

- **Location**: `.claude/skills/prd-format/`
- **Used By**: PM
- **Purpose**: PRD authoring conventions — template, writing standards, quality criteria

#### SKILL.md (router + essential principles)
- Essential principles: PRD is the single source of truth, IDs on everything (US-XXX, MOD-XXX, AC-NNN), `[DECISION NEEDED]` markers for unresolved items, no implementation details in PRD (one exception: section 9 Adopted Conventions), always confirm with the user before writing, non-goals are mandatory
- Routing:
  - Creating new PRD → read `templates/prd.tmpl.md`, copy and fill. After filling, review against `references/anti-patterns.md` before running quality checklist
  - Need writing guidance → read `references/writing-standards.md`
  - Reviewing PRD quality → use quality checklist in SKILL.md
  - Updating existing PRD → follow change protocol in SKILL.md
  - Scaffolding project directory → run `scripts/init-project.sh` (also scaffolds root `CLAUDE.md` from `templates/CLAUDE.tmpl.md` with Coordinator Instructions)
  - Identifying what not to do / catching PRD mistakes → read `references/anti-patterns.md`
  - Producing the project README (final checkpoint only) → read `references/readme-standards.md`
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
  - Finalization only: `[INIT]` tag, Build Config, Module Map with directory and Source Path for every module (no path claimed twice, none nested inside another) plus a `Project files:` line naming one owner module; Phase Plan and Current Phase left blank for Doc-Sync
- Change protocol (stays in SKILL.md since it's used every time):
  - **Pre-sync iteration** (before the first Doc-Sync): targeted change, user approval, note in PM Updates which Tech Lead Reviews entry it answers, no `[TRIVIAL]`/`[SUBSTANTIVE]` tags, Last Action `mode: iterate`
  - **Post-sync update**: re-read full PRD, smallest change, next available IDs, ask the user trivial vs substantive and tag accordingly, increment the revision, re-run the full quality checklist; a new module gets a directory, Source Path, and Module Map row before Doc-Sync runs
- Quick start: `pstack:sharpen` and a two-or-three-sentence restatement of the goal come first (step 0 of drafting); finalization covers Build Config, the Module Map (directories + non-overlapping Source Paths, shared code owned by exactly one module, one project files owner), and the setup gate (Setup Confirmation present, no newer Setup Changed)

#### templates/prd.tmpl.md
- Blank PRD skeleton with all required sections and placeholder text
- Sections: 1 Project Overview, 2 Goals & Non-Goals, 3 User Stories, 4 Tech Stack, 5 Architecture Overview, 6 Module Breakdown, 7 Phases & Milestones, 8 Acceptance Criteria, 9 Adopted Conventions
- Section 9 Adopted Conventions is the one place "how" is allowed: each `CONV-NNN` entry is a Tech Lead convention the user approved, citing the Tech Lead Reviews entry it came from. Doc-Sync copies every entry verbatim into `production.md` Shared Conventions — the only path a convention takes into `production.md`
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
- Implicit dependencies now also covers the "declared dependency is not a specified integration" case: a `Dependencies: MOD-X` field alone never justifies a concrete integration/conditional-mounting entry — that requires its own explicit PRD requirement, with a before/after example matching the `module-spec.tmpl.md` Integration Points section
- Dropping human-gate conditions when handing off to the next agent: the coordinator (or the human) summarizes a handoff and silently loses a gate such as "complete setup.md first" — every gate is surfaced to the user, and PM checks the Setup Confirmation artifact itself
- Missing non-goals: failing to explicitly exclude things stakeholders might assume are in scope (e.g., not stating that i18n is out of scope when the product name sounds global, or not stating that offline support is excluded for a mobile-first product)
- Architecture Overview boundary: the Architecture Overview may reference technologies named in the Tech Stack section (e.g., labeling a component as "PostgreSQL" or "Claude API") because the section describes *what communicates with what*. However, it must not introduce library names, SDK references, or configuration details that aren't in the Tech Stack — those are implementation details that belong in `production.md`

#### references/readme-standards.md
- Essential sections and quality checklist for the `README.md` PM writes at the final checkpoint, sourced from `prd.md`, `production.md`, and `setup.md`

#### templates/CLAUDE.tmpl.md
- Coordinator Instructions: defines the default Claude Code session (not any `.claude/agents/*` agent) as a coordinator with no independent write scope
- **Run mode**: the human runs every framework agent directly (`claude --agent <name>`); the coordinator never starts them as subagents, and gives the human the exact command and what to tell the agent
- Contains the ownership table (which agent owns which artifact and how to invoke it — source code by the module whose Source Path contains it), the hard no-direct-edit rule, the "every PM tag goes through Doc-Sync" rule, and forbidden/correct examples
- **Required pstack steps**: the trigger table for the coordinator-run pstack steps (`how`, `thermos`, `blast-radius`, `how` + `why`, `create-verification-skill`), findings saved and committed to `project-planning/pstack-findings/` (and the verify skill committed as `pstack(create-verification-skill)`, since uncommitted output shows up in every self-check and handoff warning), a blast-radius report that changes the plan going back through `tech-lead "on-demand review of <INT-ID> blast-radius"`, the "deliver findings, never fix" rule with a `git status` check after each step, and the list of file-changing pstack skills the coordinator never runs on owned artifacts
- Scaffolded to `<project-root>/CLAUDE.md` by `init-project.sh` — auto-loaded into every default session opened at that root
- If a `CLAUDE.md` already exists at project root, `init-project.sh` does not overwrite it — it prints a note telling the human to merge the Coordinator Instructions section manually

#### templates/global-CLAUDE.tmpl.md
- Source for `~/.claude/CLAUDE.md`: a safety-net version of the coordinator rule for when a project has no ownership-aware `CLAUDE.md`. Applies whenever `project-planning/status.md` exists. Not copied by any script — deployed by hand

#### scripts/init-project.sh
- Creates the `project-planning/` folder structure:
  - `project-planning/prd.md` (copied from template)
  - `project-planning/status.md` (from status template — includes Last Action, Current Phase, Phase Plan, Build Config, PM Updates, Tech Lead Reviews, Sync Reports, Decisions, Module Map (with a Source Path column and a commented `Project files: <dir> | <paths>` example line), Checkpoint History, and Skill Recommendations sections — all empty at scaffold time; Last Action has `agent`/`mode`/`module`/`result`/`timestamp` keys and no commit field. Engineering Progress and QA Results are module-level and are NOT in this file)
  - `project-planning/modules/` (empty directory)
  - `project-planning/retrospective/` and `retrospective/drafts/` (empty directories)
  - `project-planning/pstack-findings/` is not scaffolded — the coordinator creates it with the first findings file
- Also copies `templates/CLAUDE.tmpl.md` to `<project-root>/CLAUDE.md` (skipped, with a warning, if one already exists)
- Idempotent — safe to run if some dirs already exist
- Takes project root path as argument
- Includes defensive check: verifies `templates/prd.tmpl.md` and `templates/CLAUDE.tmpl.md` exist at the resolved skill path before copying — exits with a clear error if not found (guards against symlink or relocation issues)

### doc-sync-methodology

- **Location**: `.claude/skills/doc-sync-methodology/`
- **Used By**: Doc-Sync
- **Purpose**: Complete rulebook for translating PRD content into downstream docs

#### SKILL.md (router + essential principles)
- Essential principles: translator not interpreter, never add/infer/remove, `[AMBIGUITY]` / `[CONFLICT]` markers for gaps and contradictions, delta-only updates, never creates module directories (PM does — a missing directory is a `[BLOCKER]`)
- Mapping rules (stays in SKILL.md since it's used every time):
  - `prd.md` Project Overview + Tech Stack + Architecture Overview → `production.md`
  - `prd.md` Module Breakdown (per module) + related User Stories + Acceptance Criteria → `modules/<dir>/spec.md` (`<dir>` from the Module Map)
  - `prd.md` Phases & Milestones → `status.md` Phase Plan (and Current Phase = first phase, initial sync only)
  - `prd.md` Adopted Conventions (CONV-NNN, verbatim) + `status.md` Build Config → `production.md` Shared Conventions
  - `prd.md` explicit cross-module integration requirements → the Integration Points section of both affected specs (never inferred from a bare `Dependencies` field)
- Routing:
  - First sync (no production.md exists) → follow `workflows/initial-sync.md`
  - Update after PRD change tagged `[SUBSTANTIVE]` → follow `workflows/delta-sync.md`
  - Update after PRD change tagged `[TRIVIAL]` → passthrough: propagate wording change to affected downstream docs (`[TRIVIAL] Build Config changed`: re-copy Build Config into Shared Conventions), write brief sync note to `status.md`, skip `verify-sync.sh`
  - Need translation rule details → read `references/translation-rules.md`
  - Creating new files → use templates from `templates/`
  - Verifying sync → run `scripts/verify-sync.sh`

#### workflows/initial-sync.md
- Step-by-step procedure for first-time sync when no downstream docs exist:
  1. Read full `prd.md`
  2. Create `production.md` from `templates/production.tmpl.md`, fill with PRD content per mapping rules — Shared Conventions from Build Config plus every Adopted Conventions entry verbatim
  3. For each module in PRD Module Breakdown: look up its directory in the Module Map (missing → `[BLOCKER]`, skip the module); create `modules/<dir>/spec.md` from `templates/module-spec.tmpl.md`; create `modules/<dir>/status.md` (empty `## Engineering Progress` + `## QA Results`); generate `.claude/agents/engineer-<dir>.md` and `qa-<dir>.md` from `~/.claude/agent-templates/` (template `tools` and `model` copied exactly, body verbatim, spec path + Source Path + dependency status files hardcoded)
  4. Write Phase Plan to `status.md` and set Current Phase to the first phase — the only time Doc-Sync writes it
  5. Write sync report to `status.md` listing every file created
  6. Run `scripts/verify-sync.sh`
  7. If verification fails, fix issues and re-run — except when every remaining `[FAIL]` concerns a `[BLOCKER]`-skipped module: then record `result: needs-pm` and commit

#### workflows/delta-sync.md
- Step-by-step procedure for updating downstream docs after a PRD change:
  1. Read **every** PM Updates entry dated after the last Sync Report, oldest first (PM may log several changes before Doc-Sync runs)
  2. Read current `prd.md`
  3. Identify which downstream files are affected — including Adopted Conventions changes (→ Shared Conventions) and PM answers to earlier `[AMBIGUITY]`/`[CONFLICT]`/`[BLOCKER]` markers (→ each file holding a listed marker)
  4. For each affected file: read current version, apply only the delta, preserve unaffected sections; replace a resolved marker with the PRD's new text verbatim
  5. If change adds a new module: create new spec from template; create `modules/<dir>/status.md` (empty template); generate `engineer-<dir>.md` and `qa-<dir>.md` exactly as initial sync does; tell the human to open a new terminal so the new agents load. The same applies to a module skipped at an earlier sync with a `[BLOCKER]` that PM has since fixed: its spec, status file, and agents are written now and the BLOCKER is listed as resolved
  5a. If a module's Source Path, dependencies, or directory changed: regenerate its `engineer-<dir>.md` and `qa-<dir>.md` from the templates so the hardcoded paths match the Module Map again
  6. If change removes a module: add a `[REMOVED IN PRD REVISION <N>]` notice and note removal in sync report (do not delete spec or status.md — human decides)
  7. Ensure every new US-ID appears in at least one spec
  8. Write sync report to `status.md`
  9. Run `scripts/verify-sync.sh` until it exits 0, with the same `[BLOCKER]` exception as initial sync

#### templates/production.tmpl.md
- Expected structure for `production.md`:
  - Project Summary (from PRD Project Overview)
  - Tech Stack (from PRD Tech Stack — exact match required)
  - Architecture (from PRD Architecture Overview)
  - Shared Conventions (from two sources only: `status.md` Build Config — the `Build:`/`Lint:`/`Test:` keys `self-check.sh` and `run-qa.sh` read — and every PRD section 9 `CONV-NNN` entry, verbatim with its ID. Never from Tech Lead Reviews directly)
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
  - Integration Points (populated only from an explicit PRD integration requirement, never inferred from the Dependencies field — covers both component embedding and conditional mounting; see `references/translation-rules.md` "Integration Points Rule" for the `[AMBIGUITY]` + forced-PM-handoff fallback when the PRD doesn't specify one)

#### references/translation-rules.md
- Detailed integrity guardrails with examples:
  - "Use PostgreSQL" → write "Use PostgreSQL" (not "Use PostgreSQL because it's better for relational data")
  - "Support user authentication" → write "Support user authentication" (not "Implement JWT-based user authentication")
  - How to write `[AMBIGUITY]` markers: `[AMBIGUITY: PRD says "fast response" but doesn't specify a target — needs measurable threshold from PM]`
  - How to handle PRD contradictions: mark both locations with `[CONFLICT]` and log to status.md
  - Examples of acceptable restructuring vs. prohibited interpretation
  - **Integration Points Rule**: fill from an explicit PRD integration requirement only, never from a bare `Dependencies` field; if a dependency has no stated integration detail, write `[AMBIGUITY: ...]` into the spec AND override the normal handoff message to force a PM invocation before any engineering starts — the one mapping rule with a forced-handoff exception

#### scripts/verify-sync.sh
- Automated self-verification script that checks:
  - Every MOD-ID in `prd.md` has a corresponding `modules/<dir>/spec.md` file
  - No spec files exist without a matching Module Map entry (specs of removed modules, marked `[REMOVED IN PRD REVISION <N>]`, are skipped — they stay for history)
  - Tech stack section in `production.md` matches `prd.md` tech stack exactly (text comparison)
  - Every US-ID in `prd.md` appears in the `## Related User Stories` section of at least one module spec (only that section is read, up to the next `##` heading)
  - No `[AMBIGUITY]` markers exist without a corresponding entry in `status.md`
  - Phase Plan in `status.md` lists the same phases as `prd.md` — phase names are the `### Phase …` headings inside the PRD's Phases section, and the Phase Plan section runs to the next `##` heading
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
  - Commit messages: conventional commits format (`type(scope): description`) for code-level commits within a module; handoff commits use the agent-role prefix (`engineer-mod-login(implement): …`, `qa-mod-login: pass — …`, `pm(init): …`), and Engineers keep the exact `engineer-<dir>(<mode>):` prefix because `self-check.sh` uses it to find the module's own commits
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
  - Step 0 (first module of the project only): infrastructure pre-flight before writing any code — `.env` exists if `setup.md` requires one (presence only), and every service `setup.md` lists is reachable using the check `setup.md` gives. On failure: stop, report to the user, Last Action `result: needs-human`
  - Step 1: run `scripts/self-check.sh` for automated items
  - Step 2: review the automated output
  - Step 3: run the project's integration tests, if `production.md` Shared Conventions or `setup.md` names an integration-test command — against the project's test database or environment, never dev or production. Must pass before handoff
  - Step 4: manually verify judgment-based items below
  - Step 5: log everything; Step 6: all pass → QA, any fail → fix and re-run from Step 1, out-of-scope → blocker and stop
- Automated items (verified by script):
  - Build/compile succeeds without errors
  - Linter passes (if configured in production.md)
  - Existing tests pass
  - No files changed outside the module's write scope (Source Path, project files if it owns them, its own planning files) — uncommitted, untracked, and the module's own committed changes all count
- Judgment-based items (verified manually by Engineer), stack-neutral:
  - **Always**: every spec requirement implemented; Integration Points wiring implemented and conditional-mounting conditions verified within the engineer's own module only; integration tests mount the real production configuration for any AC with a UI entry point; framework-hook mocks reflect the real production ancestor; layer-diagnosis gate before fixing a runtime bug (otherwise a blocker listing hypotheses); one-line impact note before a fix; mock fidelity for option-gated API fields; untyped/unmockable query DSLs exercised against a real backend and recorded; edge cases; no hardcoded config; conventions followed; no dependencies outside the tech stack; readable code; another module's schema read from its migration/contract, never inferred from names; no TRACE/DEBUG framework logging in committed config
  - **Only if your stack matches** (skip the rest and say so in Engineering Progress): Jest + real DB teardown in `beforeEach`; LLM model IDs read from env, and prompt token budgets (`references/llm-prompt-context-budget.md`); Spring Boot actuator dependency, health-endpoint `permitAll`, `setAllowedOriginPatterns`, and `@Order` on `@RestControllerAdvice`; pinned container image architecture; React Native / Expo safe-area insets
- Output: log all results (automated + integration + manual) to `modules/<dir>/status.md` Engineering Progress section with pass/fail per item
- Living document: updated via Retrospective agent proposals after each completed work cycle

#### references/llm-prompt-context-budget.md
- Design decisions an Engineer resolves before building a feature that concatenates user-supplied text into an LLM prompt: token budget, truncation strategy, and how the limit is enforced

#### scripts/self-check.sh
- Automated pre-QA verification script:
  - Reads `production.md` to find build command, lint command, test command
  - Runs build → reports pass/fail
  - Runs linter → reports pass/fail
  - Runs existing tests → reports pass/fail
  - Checks the module's write scope through `module_scope.py`. The list of changed files is snapshotted at the start of the script, **before** build and test run, so their output (caches, bytecode, coverage) is never mistaken for the engineer's work. The snapshot covers uncommitted and untracked files plus every file changed by the module's own `engineer-<dir>(…)` commits since the last commit that was not this engineer's, so committed out-of-scope work is caught too. Skips the check when no Source Path is recorded
- Framework-agnostic: reads commands from `production.md` rather than hardcoding `npm` or `pip`
- Takes module name and project root as arguments
- Outputs structured report to stdout
- Exit code 0 = all automated checks pass

#### scripts/module_scope.py
- The Module Map scope rules, shared by `self-check.sh` and the `pstack-guard.sh` hook so the two never disagree
- Parses the `status.md` Module Map table (HTML comments skipped) and the `Project files: <dir> | <paths>` line
- `module_scope.py check <status.md> <module-dir> <path>`: exit 0 in scope, 1 outside it (reason on stdout — e.g. which module owns the path), 2 the module has no Module Map row, 3 the Module Map has no Source Path column (older project; the caller decides)
- `module_scope.py paths <status.md> <module-dir>`: prints the module's Source Paths, plus the project files if it owns them
- Write scope = Source Paths + owned project files + `modules/<dir>/` (except `spec.md`, which is always blocked) + `project-planning/status.md` + `project-planning/integration-review.md`. Ownership goes to the longest matching path, so a nested path still has a single owner

### qa-checklist

- **Location**: `.claude/skills/qa-checklist/`
- **Used By**: QA
- **Purpose**: Verification items for testing a module

#### SKILL.md (checklist + routing)
- Essential principles: verify against the spec (not against assumptions), test observable behavior, every failure needs a specific reproducible description, spec ambiguity escalates to PM, never edit source code, server-side modules require a real running server (start it with the `setup.md` run command, or the `verify` skill), UI modules require the `verify` skill or a human sign-off (`result: needs-human`)
- Routing:
  - First-time module verification → follow `workflows/functional-test.md`
  - Re-verification after bug fix → follow `workflows/regression-test.md`
  - Running automated tests → use `scripts/run-qa.sh`
  - Checking known gotchas → read `references/common-failure-patterns.md`
- Core checklist items:
  - Functional: every requirement in module spec has a corresponding verification
  - Edge cases: error states, empty inputs, boundary values, invalid data
  - Integration: module works with shared conventions in `production.md`
  - Spec compliance: no features implemented that aren't in spec (gold-plating check)
  - Spec coverage: no spec requirements left unimplemented
- Output: log results to `modules/<module-name>/status.md` QA Results section with pass/fail per item and specific failure descriptions
- If failure appears to be spec problem (not implementation bug), flag separately for PM escalation
- Living document: updated via Retrospective agent proposals

#### workflows/functional-test.md
- Step-by-step for first-time module verification:
  1. Read `modules/<dir>/spec.md` completely
  2. Read `production.md` for shared conventions and integration points
  2a. **Backend modules only**: ports in `setup.md` match `docker-compose.yml`, and every env var `setup.md` references exists in `.env.example`. A mismatch is a FAIL: `setup.md`/`docker-compose.yml` drift goes to Tech Lead ("setup drift — next: `claude --agent tech-lead`"), a variable missing from `.env.example` to the project files owner's Engineer
  3. List every requirement and acceptance criterion from the spec
  4. For each requirement: design a verification approach (automated test, manual check, or both)
  5. Run `scripts/run-qa.sh` for automated checks
  5a. **Server-side modules**: start the server with the `setup.md` run command (or the `verify` skill), call each endpoint in the Input/Output Contract with realistic inputs, verify responses and stored state, stop the server. If it fails to start, stop and report — no AC passes without a running server
  5b. **UI modules**: run each AC through the `verify` skill if it can drive the UI; otherwise write a test script per AC (steps, expected result, failure condition) ending with "Human sign-off required", record `result: needs-human`, and stop until the user reports results
  6. Manually verify judgment-based items
  7. Document results per-requirement in `modules/<dir>/status.md`
  8. Classify any failures: implementation bug vs spec issue

#### workflows/regression-test.md
- Step-by-step for re-verification after a bug fix (`regression`) or an integration-review fix (`integration-fix-verify <INT-ID>`):
  1. Read the bug description from `modules/<dir>/status.md` QA Results section
  2. Verify the specific bug is fixed
  3. Re-run all previously passing tests to check for regressions
  4. Run `scripts/run-qa.sh`
  5. Focus extra attention on code adjacent to the fix
  6. Append a new `### QA Run N — Regression — <date>` block inside `## QA Results` (never a new `##` section)
- **Integration-fix variant**: the assigned `integration-review.md` row replaces the QA Results entry — its Description and Location are the failure scenario to reproduce — and on success QA sets the row to `QA VERIFIED` (or back to `APPROVED` with a note)
- **Repeat-failure check, built into the workflow, before routing a failed fix to Engineer**: an `AC-NNN: ESCALATED TO TECH LEAD — open` line for this AC routes to Tech Lead (`result: repeat-failure`, `ac: AC-NNN`) — no re-count after the first escalation; with no marker, the 3rd failure of the AC across QA Results routes to Tech Lead the same way; otherwise back to Engineer (`result: bugs-found`). A verification that passes on an AC with an open marker flips it to resolved.

#### scripts/run-qa.sh
- Automated test runner and report generator:
  - Reads `production.md` to find the `Test:` command (Doc-Sync copies it from `status.md` Build Config); a command wrapped in quotes is unquoted, and the rest of the line is kept as written
  - **Fails** (not warns) when `production.md` is missing or has no test command — if the project truly has no tests, the human must say so and QA records it in QA Results
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
- Also includes (added via Retrospective proposals from real project incidents): Express 4 synchronous throws in middleware, SPA/API route namespace collisions, Spring Boot actuator health and `@RestControllerAdvice` ordering, mock hides a production mount-context incompatibility, wrong-layer diagnosis, mock-fidelity gap for option-gated API fields, untyped/unmockable query DSLs, verbose framework logging left in production config, "it's the infrastructure" when only your network fails, and content under the notch (React Native / Expo) — each with an identifying condition and a check
- Living document: primary target for Retrospective agent proposals — grows with project-specific patterns over time

---

### integration-review

- **Location**: `.claude/skills/integration-review/`
- **Used By**: Tech Lead
- **Purpose**: Cross-module conflict, information-leak, and optimization review — run once per phase, after all modules in that phase pass QA, before PM's checkpoint for that phase

#### SKILL.md (router + principles)
- Essential principles: advisory only (findings are proposals, never implemented by Tech Lead), Concerns/Recommendations split mirrors Tech Lead's existing review format, leakage checks go beyond the database (caches, logs, exports, background jobs, shared config), every finding needs a specific location and concrete failure scenario, findings that imply a requirements change escalate to PM instead of being tracked here
- Routing:
  - First review for a phase → follow `workflows/phase-review.md`
  - Human gives approve / reject / defer decisions → follow `workflows/record-decisions.md`
  - Re-invoked to close out an approved, fixed item → follow `workflows/confirm-fix.md`
  - Need the conflict/leak checklist → read `references/cross-module-checklist.md`
  - Deciding if something is a worthwhile optimization → read `references/optimization-criteria.md`
  - `integration-review.md` doesn't exist yet → copy `templates/integration-review.tmpl.md`
  - Automated first-pass scan → run `scripts/scan-integration.sh`

#### workflows/phase-review.md
- Step-by-step for the first review of a phase: read every module in the phase in full, run `scripts/scan-integration.sh`, apply both reference checklists, create `integration-review.md` from template if missing, carry forward every row still `DEFERRED` from an earlier phase (listed again for the human to decide; its status is left for `record-decisions` to change), log one `PROPOSED` row per finding with Assigned Module left blank (or a single `NO ISSUES` row, "No issues found — phase <N> reviewed <date>"), write a summary pointer to `status.md` Tech Lead Reviews, record Last Action `mode: integration-review` with `result: issues-found` or `result: clean`, commit
- Tells the human that every row — Concerns, Recommendations, and carried-forward `DEFERRED` rows — needs an approve, reject, or defer before PM's checkpoint, given as `claude --agent tech-lead "decisions: INT-001 approve, INT-002 reject, ..."`
- **Scope split**: conflict/leak checks (`cross-module-checklist.md`) are scoped to the current phase's modules only — new interactions only exist between modules new to each other. The duplication check (`optimization-criteria.md`) is explicitly NOT phase-scoped — it compares lightweight Purpose/Tech Stack summaries across every module shipped so far, deep-reading only modules flagged as suspiciously similar, since duplication has no phase boundary

#### workflows/record-decisions.md
- Step-by-step for recording the human's decisions (e.g. "INT-001 approve, INT-002 reject, INT-003 defer"): set each named item — including `DEFERRED` rows from earlier phases the human decides again — to exactly `APPROVED`, `REJECTED`, or `DEFERRED` with the reason and date; ask when the wording is ambiguous; for every `APPROVED` item fill **Assigned Module** — the module whose Source Path contains the code the fix changes — confirmed with the human. A fix spanning modules splits into one row per owner, named with a letter suffix (`INT-003` → `INT-003a`, `INT-003b`), and the original is marked `CONFIRMED CLOSED` with "split into INT-003a/b" once both exist; add `blast-radius first` to Notes when the fix changes code another module depends on (if the blast-radius report changes the plan, the human runs Tech Lead again with it as an `on-demand-review`); leave unmentioned items `PROPOSED`; Last Action `mode: record-decisions`, `result: success`; commit
- Tells the human, per approved item: `claude --agent engineer-mod-<assigned> "integration-fix <ID>"` (after the coordinator's blast-radius step where noted), or PM checkpoint when nothing is approved or still `PROPOSED`

#### workflows/confirm-fix.md
- Step-by-step for closing out an item: if it is `QA VERIFIED` and the human states in the session that they verified it, record `HUMAN VERIFIED` with the date and the human's own words (ask — never infer); anything earlier than `QA VERIFIED` stops with what it is waiting for; re-check the original failure scenario against current code; set `CONFIRMED CLOSED` if resolved, or bounce back to `APPROVED` with a note if not; Last Action `mode: confirm-fix`, `result: success`; commit

#### templates/integration-review.tmpl.md
- Structure for `project-planning/integration-review.md`: status legend, and a findings table (ID, Phase, Category, Description, Location, Tech Lead Rationale & Trade-offs, Status, Assigned Module, Notes)
- Status lifecycle: `PROPOSED` → `APPROVED` / `REJECTED` / `DEFERRED` → `IN PROGRESS` → `FIXED – AWAITING QA` → `QA VERIFIED` → `HUMAN VERIFIED` → `CONFIRMED CLOSED`
- Ownership split by status, same pattern as `modules/*/status.md`: Tech Lead owns `PROPOSED`/`NO ISSUES`/`CONFIRMED CLOSED` and records the human's `APPROVED`/`REJECTED`/`DEFERRED` decisions (plus Assigned Module) and the human's `HUMAN VERIFIED` exactly as the human states them; Engineer owns `IN PROGRESS`/`FIXED – AWAITING QA` on rows assigned to it; QA owns `QA VERIFIED` (or sends back to `APPROVED`)
- PM's checkpoint gate: every row for the phase must be `CONFIRMED CLOSED`, `REJECTED`, `DEFERRED`, or `NO ISSUES`. Recommendations are gated like Concerns — each needs an explicit approve, reject, or defer. A `DEFERRED` row stops blocking its own phase but is listed again in every later phase's review until the human approves or rejects it

#### references/cross-module-checklist.md
- Living document, same pattern as `qa-checklist/references/common-failure-patterns.md`
- Conflicts: shared route/config/symbol collisions, migration ordering conflicts, divergent use of the same shared dependency, Shared Conventions drift, unimplemented cross-module Integration Points
- Leakage: data access boundary bypasses, cache key scoping, logs exposing another module's sensitive fields, exports/reports not filtered to authorization, background jobs not re-validating context, shared config/secret namespace collisions

#### references/optimization-criteria.md
- Opens by framing this as the safety net, not the primary mechanism — duplication should ideally be proposed by Tech Lead at spec time (init review or when a module is added), before engineering starts; see the Tech Lead "Overlapping modules" step
- Criteria a proposal must pass before being logged: visible only from the whole-system view (not catchable by a single module's own QA), has a concrete trade-off (not just a preference), doesn't change user-facing behavior, has a clear owner
- Duplicated logic is proposed as a move to a single owner module (an existing natural owner, or a new module named for what it is), stating the duplication, the proposed owner and Source Path, and the extraction cost
- Explicit non-goals: style preferences, anything a single module's cycle would already catch, speculative suggestions, anything that changes product behavior rather than how it's built

#### scripts/scan-integration.sh
- Automated first-pass scan, explicitly a lead list rather than a verdict — every hit still needs Tech Lead's manual judgment
- Reads module directories and Source Paths from the rows of the `status.md` Module Map table only — HTML comments and the format example are skipped (all modules ever shipped, not phase-filtered — the Module Map has no phase concept of its own)
- Scans every Source Path in the Module Map (falling back to `src/` when none are recorded), dropping roots nested inside another so no file is counted twice
- Checks: migration filename/prefix collisions across common migration directory names, Integration Points file references that don't resolve to an actual file, duplicate route/endpoint literals (`.get`/`.post`/`.put`/`.patch`/`.delete`/`.route`) — each route counted across all files, with the files holding every duplicate listed — module Purpose lines printed together for duplication eyeballing, duplicate exported component/function names (JS/TS exports and Python `def`/`class`) across the scanned roots (all heuristic greps, tech-stack agnostic)
- Always exits 0, even on an empty result (it runs without `set -e`/`-u`) — never fails the build; this is advisory tooling, not a gate

---

## Hooks

Both hooks are registered under `"hooks"` in `~/.claude/settings.json` (account-level) or a project's `.claude/settings.json`. Claude Code does not load a standalone `hooks.json` outside plugins; the repo ships the entries to merge in `.claude/hooks/settings-hooks.json` (which also carries two optional macOS `osascript` notifications on `Notification` and `Stop`). Both scripts need `jq`, must be executable (`chmod +x`), and stay silent outside a dev-team-agent project (one with `project-planning/status.md`).

### handoff.sh

- **Location**: `.claude/hooks/handoff.sh` (project source); `~/.claude/hooks/handoff.sh` (account-level copy)
- **Registered Events**: `Stop` (fires when a `claude --agent X` session finishes a turn — the primary path, since the human runs every agent directly) and `SubagentStop`
- **Behavior**:
  - Exits immediately when `stop_hook_active` is true (no loops)
  - Finds the project root from subdirectories: resolves `git rev-parse --show-toplevel` from the hook's `cwd`, and outside git (or when that root has no `project-planning/status.md`) walks up the parent directories, so a session that ran `cd src` still finds `project-planning/status.md`
  - Parses the `## Last Action` block in `status.md` (`agent`, `mode`, `result`, `module`, and `ac` for repeat failures) and, for some messages, `## Current Phase` (its first non-comment line — comments may span several lines), `## Checkpoint History`, and whether a PM Updates entry is tagged `[INIT]`
  - Writes every command as `claude --agent <name> "<word>"`, so it pastes into any shell, with the start word the agent picks its mode from: Engineer `implement` / `bugfix` / `integration-fix <INT-ID>`; QA `verify` / `regression` / `integration-fix-verify <INT-ID>` / `ui-results: …`; PM `iterate` / `finalize` / `change` / `checkpoint`; Tech Lead a short phrase (`"initial PRD review"`, `"Setup is complete"`, `"decisions: …"`, `"repeat-failure review AC-NNN"`, …)
  - **Shows each Last Action once**: it fingerprints the Last Action block into `.git/handoff-last-shown` (or `project-planning/handoff-last-shown` outside git), so the repeated Stop/SubagentStop firings after every turn stay silent until an agent records a new Last Action
  - Builds a per-agent, per-mode, per-result "Next →" message (table below) and returns it as JSON `{"systemMessage": ...}` — plain stdout from a Stop hook goes to the debug log, not the user
  - Appends a warning listing every uncommitted change in the repo (source code and generated agents included) if the agent did not commit before stopping
  - Names the coordinator's pstack step in the message where one is required (`how`, `thermos`, `how` + `why`, `blast-radius`), and during phase 1 — while `.claude/skills/verify/SKILL.md` does not exist and no checkpoint is recorded — adds an optional hint to have the coordinator run `/pstack:create-verification-skill`
  - Unknown agents (and Retrospective, which writes no Last Action) produce no message
  - Never auto-invokes the next agent — always waits for the human to run the command

### pstack-guard.sh

- **Location**: `.claude/hooks/pstack-guard.sh`; `~/.claude/hooks/pstack-guard.sh` (account-level copy)
- **Registered Event**: `PreToolUse`, matcher `Skill|Edit|Write|MultiEdit|NotebookEdit`
- **Active only** in a dev-team-agent project (project root resolved from subdirectories, with or without git, same as `handoff.sh`) and only for agent calls — main-session calls carry no `agent_type` and pass through; `CLAUDE.md` governs the coordinator
- **Per-agent skill allowlists**: the `Skill` tool is all-or-nothing, so the hook checks `tool_input.skill` against the calling agent's list and blocks everything else with exit 2:

  | Agent | Allowed skills |
  |---|---|
  | `pm` | `prd-format`, `pstack:sharpen`, `pstack:unslop`, `pstack:technical-writing` |
  | `engineer-*` | `coding-conventions`, `engineer-checklist`, `pstack:tdd`, `pstack:deslop`, `pstack:typescript-best-practices` |
  | `qa-*` | `qa-checklist`, `verify` |
  | `tech-lead`, `doc-sync`, `retrospective` | none |
  | any other (non-framework) agent | any |

- **No writes under `~/.claude`**: every agent, framework or not, is blocked from writing hooks, skills, or agent definitions under `~/.claude`. Framework files change only on the human's explicit instruction, in the coordinator session
- **Module Map is PM's**: a Write/Edit of `project-planning/status.md` by any agent other than `pm` is blocked if it would change the `## Module Map` section (the hook applies the edit to the current file and compares the section before and after), so no agent can widen its own scope
- **Engineer write scope**: an `engineer-*` agent's Write/Edit/MultiEdit/NotebookEdit calls are checked with `engineer-checklist/scripts/module_scope.py` (the same rules `self-check.sh` uses): allowed inside its module's Source Path, the project files it owns, and its own planning files (`project-planning/modules/<dir>/` except `spec.md`, `project-planning/status.md`, `project-planning/integration-review.md`). Anything else in the project is blocked with a message naming the owner and telling it to record a `blocked-technical` blocker. It fails closed: a module with no Module Map row has no write scope until PM adds one. Paths outside the project are not blocked; an older Module Map with no Source Path column falls back to the prompt rules
- **Read-only reviewers**: any subagent that is not a framework agent (pstack's `general-purpose`, `pstack:effort-*`, `pstack:thermo-*` reviewers) may write in the project only under `project-planning/pstack-findings/` (outside the project, except `~/.claude`, is not blocked). Paths are resolved with `realpath` first, so `../` and symlinks cannot escape
- **Other framework agents** (PM, Doc-Sync, Tech Lead, QA, Retrospective) keep their prompt-defined write scopes apart from the `~/.claude` and Module Map rules; the hook does not otherwise check their file writes
- Needs `python3` (for `realpath`, the Module Map comparison, and `module_scope.py`, which it reads from `~/.claude/skills/engineer-checklist/scripts/`)
- **Not covered**: shell commands and the coordinator's own session — the coordinator's `git status` check after each pstack step covers those

### Handoff Messages

`handoff.sh` prints `Handoff — <agent> (<mode>, <result>)` followed by `Next → <message>`. The messages below are its actual branches (paraphrased where long):

| Just Finished (agent / mode / result) | Hook Suggests (Next →) |
|---|---|
| any agent except QA, `result: needs-human` | `<agent> is waiting on you` — read its last message (and its `status.md` entry), do what it asks, then run `claude --agent <agent>` and give it your answer |
| qa-mod-X, `result: needs-human` | QA needs your sign-off — run its test script (in QA Results), then: `claude --agent qa-mod-X "ui-results: <which ACs passed, which failed and how>"` |
| pm / `init` | `claude --agent tech-lead "initial PRD review"` |
| pm / `iterate` | Review the revised PRD. Architectural changes: `claude --agent tech-lead "pre-sync re-review"`. Otherwise, once you approve: `claude --agent pm "finalize"` |
| pm / `finalize` | `claude --agent doc-sync` — initial sync |
| pm / `change` | Architectural impact: have the coordinator run `/pstack:how` on the affected code (saved to `project-planning/pstack-findings/`), then `claude --agent tech-lead "change review"`. Otherwise: `claude --agent doc-sync` |
| pm / `checkpoint` | `Now in <Current Phase>. Next: claude --agent engineer-<first module of this phase> "implement"` (see Phase Plan) |
| pm / `checkpoint` / `project-complete` | Project complete — README.md written. Optional: `claude --agent retrospective` |
| tech-lead / any mode / `setup-changed` | Setup changed (see Setup Changed in Tech Lead Reviews). Redo the listed `setup.md` steps, then: `claude --agent tech-lead "Setup is complete"` |
| tech-lead / `init-review` | Complete every step in `project-planning/setup.md`, then: `claude --agent tech-lead "Setup is complete"` |
| tech-lead / `pre-sync-review` | Read the re-review. Changes requested: `claude --agent pm "iterate"`. You approve the PRD: `claude --agent pm "finalize"` |
| tech-lead / `setup-confirmation`, before `[INIT]` | `claude --agent pm "iterate"` to apply Tech Lead's feedback, or `claude --agent pm "finalize"` if there is none and you approve the PRD |
| tech-lead / `setup-confirmation`, after `[INIT]` | Setup re-confirmed. Resume the step that found the drift (usually: `claude --agent qa-<module> "verify"`) |
| tech-lead / `change-review` | Read the review. Accept as-is: `claude --agent doc-sync`. PRD needs revising: `claude --agent pm "change"` |
| tech-lead / `on-demand-review` | Read the review. Minor adjustment: `claude --agent engineer-<module> "bugfix"`. PRD-level change: `claude --agent pm "change"` |
| tech-lead / `integration-review` / `clean` | No integration issues this phase. Next: `claude --agent pm "checkpoint"` |
| tech-lead / `integration-review` / `issues-found` | Review `integration-review.md` and decide every row (Concerns and Recommendations), then: `claude --agent tech-lead "decisions: INT-001 approve, INT-002 reject, INT-003 defer"` |
| tech-lead / `record-decisions` | For each APPROVED item: `claude --agent engineer-<Assigned Module> "integration-fix <INT-ID>"` (rows noted `blast-radius first`: the coordinator runs `/pstack:blast-radius` before that). Nothing approved and nothing PROPOSED: `claude --agent pm "checkpoint"` |
| tech-lead / `confirm-fix` | Every row for this phase CONFIRMED CLOSED, REJECTED, DEFERRED or NO ISSUES: `claude --agent pm "checkpoint"`. Otherwise continue the next open row |
| tech-lead / `repeat-failure-review` | Tech Lead's diagnosis is in Tech Lead Reviews. Next: `claude --agent engineer-<module> "bugfix — follow Tech Lead's repeat-failure diagnosis for <AC>"` (module and AC from Last Action), or `claude --agent pm "change"` if it needs a requirements change |
| tech-lead / other | Read the latest entry in Tech Lead Reviews and decide the next agent |
| doc-sync / `needs-pm` | Doc-Sync left unresolved PRD questions (see Sync Reports). `claude --agent pm "change"` before any engineering starts |
| doc-sync / `success` | Review the sync report. If it generated new agents, open a new terminal so they load. Then: `claude --agent engineer-<first module in the Phase Plan not yet built> "implement"` |
| engineer-mod-X / `implement` / `success` | `claude --agent qa-mod-X "verify"` |
| engineer-mod-X / `bugfix` / `success` | `claude --agent qa-mod-X "regression"` |
| engineer-mod-X / `integration-fix` / `success` | `claude --agent qa-mod-X "integration-fix-verify <INT-ID from integration-review.md>"` |
| engineer-mod-X / `blocked-dependency` | A module this one depends on has not passed QA yet — finish it first (see Phase Plan). If the phase order is wrong: `claude --agent pm "change"` |
| engineer-mod-X / `blocked-technical` | `claude --agent tech-lead "engineer blocker in mod-X"` — cross-module or tech-stack blocker in Engineering Progress |
| qa-mod-X / `verify` or `regression` / `success` | Next module in the Phase Plan: `claude --agent engineer-<next module> "implement"`. If this was the last module of the phase: the coordinator runs `/pstack:thermos` on the phase's changes (saved to `project-planning/pstack-findings/`), then `claude --agent tech-lead "phase-end integration review"` [+ the phase-1 verify-skill hint] |
| qa-mod-X / `bugs-found` | `claude --agent engineer-mod-X "bugfix"` — failures are in QA Results |
| qa-mod-X / `spec-issue` | `claude --agent pm "change: spec issue from qa-mod-X"` — PRD update needed |
| qa-mod-X / `setup-drift` | `claude --agent tech-lead "on-demand review: setup drift found by qa-mod-X"` |
| qa-mod-X / `repeat-failure`, `ac:` names an AC with an open `ESCALATED TO TECH LEAD — open` marker | `<AC> is already escalated — claude --agent tech-lead "repeat-failure review <AC>"` (Tech Lead stays the owner until it passes) |
| qa-mod-X / `repeat-failure`, `ac:` names an AC with no open marker | First escalation of `<AC>` — the coordinator runs `/pstack:how` and `/pstack:why` on the failing path (saved to `project-planning/pstack-findings/`), then `claude --agent tech-lead "repeat-failure review <AC>"` |
| qa-mod-X / `repeat-failure`, no `ac:` recorded | Repeat failure — if this AC has no open marker yet, the coordinator runs `/pstack:how` and `/pstack:why` first; then `claude --agent tech-lead "repeat-failure review <AC-ID>"` |
| qa-mod-X / `integration-fix-verify` / `success` | Verify the fix yourself, then: `claude --agent tech-lead "<INT-ID> verified: <what you checked>"` |
| qa-mod-X / `integration-fix-verify` / not success | The integration fix does not hold yet — `claude --agent engineer-mod-X "integration-fix <INT-ID>"` |
| Retrospective, or any unknown agent | no message |

---

## Write Access Matrix

| File | PM | Doc-Sync | Tech Lead | Engineer | QA | Retrospective |
|---|---|---|---|---|---|---|
| `prd.md` | ✅ Write | 🔒 Read | 🔒 Read | ❌ No access | ❌ No access | 🔒 Read |
| `production.md` | 🔒 Read (final README only) | ✅ Write | 🔒 Read | 🔒 Read | 🔒 Read | 🔒 Read |
| `status.md` (project-level) | ✅ Write (Last Action, Build Config, PM Updates, Module Map — the only agent `pstack-guard.sh` lets change it — Checkpoint History, Decisions, Skill Recommendations; Current Phase — advance at checkpoint) | ✅ Write (Last Action, Sync Reports, Phase Plan, Skill Recommendations; Current Phase — initial sync only) | ✅ Write (Last Action, Tech Lead Reviews, Skill Recommendations) | ✅ Write (Last Action, Skill Recommendations) | ✅ Write (Last Action, Skill Recommendations) | 🔒 Read |
| `modules/*/status.md` (module-level) | 🔒 Read (change, checkpoint) | ✅ Write (creates during sync) | ✅ Write (one escalation-marker line only, repeat-failure review) | ✅ Write (Engineering Progress, assigned only) | ✅ Write (QA Results, assigned only, plus flipping Tech Lead's marker to resolved) | 🔒 Read |
| `modules/mod-*/` directories | ✅ Create (+ `.gitkeep` only) | ❌ Never creates | ❌ No access | ❌ No access | ❌ No access | ❌ No access |
| `project-planning/setup.md` | 🔒 Read (final README only) | ❌ No access | ✅ Write (init review; pre-sync review when setup changed; after `[INIT]`, an on-demand review the human approves) | 🔒 Read | 🔒 Read | 🔒 Read |
| `.gitignore`, `docker-compose.yml` | ❌ No access | ❌ No access | ✅ Write (same rule as `setup.md`) | 🔒 Read | 🔒 Read | ❌ No access |
| `.env.example` | ❌ No access | ❌ No access | ✅ Write (init review; pre-sync review when setup changed) | ✅ Write (after `[INIT]`, project files owner only) | 🔒 Read | ❌ No access |
| Project files (manifests, lockfiles, CI config on the Module Map `Project files:` line) | ❌ No access | ❌ No access | 🔒 Read | ✅ Write (project files owner only — `module_scope.py`) | 🔒 Read | ❌ No access |
| `.env` | ❌ No access | ❌ No access | Existence + gitignore check only | Presence check only | Presence check only | ❌ No access |
| `modules/*/spec.md` | ❌ No access | ✅ Write | 🔒 Read | 🔒 Read (assigned only) | 🔒 Read (assigned only) | 🔒 Read |
| `project-planning/integration-review.md` | 🔒 Read (checkpoint gate only) | ❌ No access | ✅ Write (create; PROPOSED / NO ISSUES / CONFIRMED CLOSED; records the human's APPROVED / REJECTED / DEFERRED + Assigned Module and HUMAN VERIFIED) | ✅ Write (IN PROGRESS / FIXED – AWAITING QA, assigned rows only) | ✅ Write (QA VERIFIED or back to APPROVED, assigned rows only) | ❌ No access |
| Source code | ❌ No access | ❌ No access | 🔒 Read (reviews) | ✅ Write (own Source Path only — `module_scope.py`, enforced by `self-check.sh` + `pstack-guard.sh`) | 🔒 Read | ❌ No access |
| `README.md` (final) | ✅ Write (final checkpoint) | ❌ No access | ❌ No access | ❌ No access | ❌ No access | ❌ No access |
| `.claude/skills/*` (`~/.claude` writes blocked for every agent by `pstack-guard.sh`) | ❌ No access | ❌ No access | ❌ No access | ❌ No access | ❌ No access | 🔒 Read |
| `.claude/agents/*` | ❌ No access | ✅ Write (`engineer-<dir>.md` + `qa-<dir>.md` only) | ❌ No access | ❌ No access | ❌ No access | 🔒 Read |
| `project-planning/pstack-findings/*` | ❌ No access | ❌ No access | 🔒 Read | ❌ No access | ❌ No access | 🔒 Read |
| `.claude/skills/verify/` | ❌ No access | ❌ No access | ❌ No access | ❌ No access | 🔒 Use via `Skill` (never edit) | 🔒 Read |
| `retrospective/*` | ❌ No access | ❌ No access | ❌ No access | ❌ No access | ❌ No access | ✅ Write |

**Coordinator** (the default Claude Code session — not any `.claude/agents/*` agent): ❌ No access to any row above. It reads freely to diagnose, but every write goes through the owning agent, per the ownership table in the project's root `CLAUDE.md` (scaffolded by `init-project.sh`, see prd-format skill). Two pstack rows are the coordinator's: it writes `project-planning/pstack-findings/*` (output of the Required pstack steps in `CLAUDE.md`, never a fix) and creates `.claude/skills/verify/` only when the human says yes. pstack's own reviewer subagents may write nowhere in the project except `pstack-findings/` — `pstack-guard.sh` enforces this. The other exception is `.claude/skills/*` and non-generated `.claude/agents/*.md`, which the coordinator may create/edit itself, but only on explicit human instruction following a reviewed Retrospective proposal — see Project-Level Skill Creation Workflow.

---

## File Structure

```
.claude/
├── agents/
│   ├── pm.md                                      # PM agent definition
│   ├── doc-sync.md                                # Doc-Sync agent definition
│   ├── tech-lead.md                               # Tech Lead agent definition
│   └── retrospective.md                           # Retrospective agent definition
├── agent-templates/                               # Outside agents/ so Claude Code does not load them as agents
│   ├── engineer.md                                # Engineer base template — Doc-Sync reads ~/.claude/agent-templates/engineer.md
│   └── qa.md                                      # QA base template — Doc-Sync reads ~/.claude/agent-templates/qa.md
├── skills/
│   ├── prd-format/
│   │   ├── SKILL.md                               # Router + principles + quality checklist
│   │   ├── templates/
│   │   │   ├── prd.tmpl.md                        # Blank PRD skeleton (sections 1–9, incl. Adopted Conventions)
│   │   │   ├── CLAUDE.tmpl.md                     # Coordinator Instructions — scaffolded to project root
│   │   │   └── global-CLAUDE.tmpl.md              # Source for ~/.claude/CLAUDE.md safety net (deployed by hand)
│   │   ├── references/
│   │   │   ├── writing-standards.md               # Detailed writing guidance + examples
│   │   │   ├── anti-patterns.md                   # Common mistakes with corrections
│   │   │   └── readme-standards.md                # Final-checkpoint README standards
│   │   └── scripts/
│   │       └── init-project.sh                    # Scaffolds project-planning/ directory + root CLAUDE.md
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
│   │   ├── references/
│   │   │   └── llm-prompt-context-budget.md       # Token budget for prompts built from user text
│   │   └── scripts/
│   │       ├── self-check.sh                      # Automated pre-QA checks (incl. write-scope check)
│   │       └── module_scope.py                    # Module Map scope rules shared by self-check.sh + pstack-guard.sh
│   ├── qa-checklist/
│   │   ├── SKILL.md                               # Checklist + routing
│   │   ├── workflows/
│   │   │   ├── functional-test.md                 # First-time verification procedure
│   │   │   └── regression-test.md                 # Re-verification after a bug fix or integration fix
│   │   ├── scripts/
│   │   │   └── run-qa.sh                          # Automated test runner + reporter
│   │   └── references/
│   │       └── common-failure-patterns.md         # Known gotchas (living doc)
│   └── integration-review/
│       ├── SKILL.md                               # Router + principles — Tech Lead's phase-end review rulebook
│       ├── workflows/
│       │   ├── phase-review.md                    # First-time review procedure for a phase
│       │   ├── record-decisions.md                # Recording the human's approve/reject/defer + Assigned Module
│       │   └── confirm-fix.md                     # Recording HUMAN VERIFIED and closing out an item
│       ├── templates/
│       │   └── integration-review.tmpl.md         # Structure for project-planning/integration-review.md
│       ├── references/
│       │   ├── cross-module-checklist.md          # Conflict + leak checklist (living doc)
│       │   └── optimization-criteria.md           # What qualifies as a worthwhile optimization proposal
│       └── scripts/
│           └── scan-integration.sh                # Automated first-pass scan (lead list, not a verdict)
└── hooks/
    ├── handoff.sh                                 # Stop/SubagentStop hook for handoffs
    ├── pstack-guard.sh                            # PreToolUse guard: skill allowlists, ~/.claude + Module Map protection, engineer write scope, read-only pstack reviewers
    └── settings-hooks.json                        # Hook entries to merge into settings.json

CLAUDE.md                                           # Created by init-project.sh from CLAUDE.tmpl.md — Coordinator
                                                     # Instructions (ownership rules); auto-loaded by every default session

.claude/                                            # Project-level, inside each project
├── agents/
│   ├── engineer-mod-<name>.md                      # Generated by Doc-Sync — never hand-edit; open a new terminal to load
│   └── qa-mod-<name>.md
└── skills/verify/                                  # Optional — coordinator creates it in phase 1 with
                                                     # /pstack:create-verification-skill, only if the human says yes

project-planning/                                   # Created by PM via init-project.sh
├── prd.md                                          # Single source of truth — only PM writes
├── production.md                                   # Shared tech context — only Doc-Sync writes
├── status.md                                       # Coordination hub — multiple agents write sections
├── setup.md                                        # Environment runbook — only Tech Lead writes
├── integration-review.md                           # Created by Tech Lead on first phase-end review — cross-module
│                                                    # conflict/leak/optimization findings; PM's checkpoint gate reads it
├── pstack-findings/                                # Coordinator-run pstack step output; Tech Lead reads, nobody edits
│   └── <date>-<skill>-<topic>.md
├── modules/
│   ├── mod-<name>/                                 # Directory named by PM in the Module Map
│   │   ├── .gitkeep                                # Created by PM at finalize
│   │   ├── spec.md                                 # Only Doc-Sync writes, Engineer + QA read
│   │   └── status.md                               # Doc-Sync creates; Engineer writes Engineering Progress; QA writes QA Results
│   └── mod-<other>/
│       ├── spec.md
│       └── status.md
└── retrospective/                                  # Only Retrospective agent writes here
    ├── proposed-changes.md                         # Summary of all proposals with rationale
    └── drafts/                                     # One structured proposal per candidate
        ├── <descriptive-name>.proposal.md
        └── (other proposals as needed)
```

---

## Handoff Chains

### pstack Steps (coordinator-run, before certain handoffs)

The human runs every framework agent directly (`claude --agent <name>`); agents never start other agents. Where a handoff benefits from a multi-agent pstack review, the coordinator runs it first in its own session, saves the output to `project-planning/pstack-findings/`, commits it, and tells the human which agent to run next and which findings file to mention. The project `CLAUDE.md` ("Required pstack steps") is the source of truth; `handoff.sh` repeats the step in its message.

| Handoff point | pstack step | Then |
|---|---|---|
| PM change with architectural impact | `how` on the affected code | `tech-lead` change review |
| QA pass, last module of the phase | `thermos` (diff from the last checkpoint commit, phase 1: `doc-sync(initial)`, limited to the phase's Source Paths) | `tech-lead` integration review |
| Approved integration fix changing code another module depends on | `blast-radius` (probe scripts outside the project, no arena) | risks change the plan: `tech-lead "on-demand review of <INT-ID> blast-radius"`; otherwise `engineer-mod-<name> "integration-fix <INT-ID>"` |
| QA repeat-failure, first escalation of that AC | `how` + `why` | `tech-lead` repeat-failure review |
| Phase 1, app runs, human approves | `create-verification-skill` (the coordinator commits `.claude/skills/verify/` as `pstack(create-verification-skill)`) | QA uses `verify` from then on |

PM runs `pstack:sharpen` itself at the start of init. Findings are delivered, never applied: Tech Lead checks each one against the code and records which it accepted or rejected, the human decides, and the owner changes the file.

### Init Flow (once per project)

```
User
 ↓ provides requirements
 [HUMAN RUNS: claude --agent pm]
PM [init]
 ↓ runs pstack:sharpen on the request, restates the goal in 2–3 sentences, waits for the user's correction
 ↓ runs init-project.sh to scaffold project-planning/ + root CLAUDE.md
 ↓ gathers requirements (numbered questions), fills prd.md from template, anti-patterns + quality checklist
 ↓ user approves the draft → commits: git commit -m "pm(init): draft PRD for <project>"
 [Stop → hook: 'claude --agent tech-lead "initial PRD review"']
 [HUMAN RUNS: claude --agent tech-lead "initial PRD review"]
Tech Lead [init-review]
 ↓ checks installed tool versions against the Tech Stack
 ↓ reviews PRD (feasibility, risks, dependencies, gaps, proposed conventions, shared-code owners), writes findings to Tech Lead Reviews
 ↓ creates .gitignore (first), project-planning/setup.md; backend projects also .env.example + docker-compose.yml
 ↓ commits: git commit -m "tech-lead(init-review): <summary>"
 [Stop → hook: 'Complete every step in project-planning/setup.md, then: claude --agent tech-lead "Setup is complete"']
 [HUMAN COMPLETES setup.md — install deps, dev server and build (frontend-only); or keys, .env, docker compose up -d (backend)]
 [HUMAN RUNS: claude --agent tech-lead "Setup is complete"]
Tech Lead [setup-confirmation]
 ↓ verifies: every docker-compose.yml service running (backend) or the build command named in setup.md (frontend-only); .env existence + gitignore only
 ↓ records ### Setup Confirmation — <date> under ## Tech Lead Reviews
 ↓ commits: git commit -m "tech-lead(setup-confirmed): environment verified, PM green light issued"
 [Stop → hook: 'claude --agent pm "iterate" to apply Tech Lead's feedback, or claude --agent pm "finalize" if there is none and you approve the PRD']
 [HUMAN RUNS: claude --agent pm "iterate"]
PM [iterate]  (repeat as needed)
 ↓ applies Tech Lead feedback / user edits via the pre-sync iteration protocol — no [TRIVIAL]/[SUBSTANTIVE] tags
 ↓ notes in PM Updates which Tech Lead Reviews entry each change answers; an approved Proposed Convention becomes the next CONV-NNN now
 ↓ commits: git commit -m "pm(iterate): <summary>"
 [Stop → hook: 'Architectural changes: claude --agent tech-lead "pre-sync re-review". Otherwise, once you approve: claude --agent pm "finalize"']
 ├── Architectural revision → [HUMAN RUNS: claude --agent tech-lead "pre-sync re-review"]
 │    Tech Lead [pre-sync-review]
 │     ↓ reviews only what changed since the init review
 │     ├── setup unchanged → result: success
 │     │    [hook: 'Changes requested: claude --agent pm "iterate". You approve the PRD: claude --agent pm "finalize"']
 │     └── tech stack / infrastructure changed → updates setup.md (+ infra files), adds ### Setup Changed — <date>,
 │          result: setup-changed
 │          [hook: 'Redo the listed setup.md steps, then: claude --agent tech-lead "Setup is complete"']
 │          → Tech Lead [setup-confirmation] again → PM
 └── User gives final approval → [HUMAN RUNS: claude --agent pm "finalize"]
PM [finalize]
 ↓ setup gate: ### Setup Confirmation present, no newer ### Setup Changed — otherwise stop
 ↓ writes Build Config (Build: / Lint: / Test:)
 ↓ proposes + confirms the Module Map: MOD-ID → mod-<name> directory → Source Path (no overlap, no nesting),
   plus the Project files: <owner> | <paths> line; creates each directory + .gitkeep
 ↓ tags a PM Updates entry [INIT]
 ↓ commits: git commit -m "pm(finalize): PRD ready for doc-sync"
 [Stop → hook: "claude --agent doc-sync — initial sync"]
 [HUMAN RUNS: claude --agent doc-sync]
Doc-Sync [initial]
 ↓ follows initial-sync workflow
 ↓ creates production.md (Shared Conventions = Build Config + Adopted Conventions) + module specs (with Context section)
 ↓ creates modules/<dir>/status.md (empty Engineering Progress + QA Results) per module
 ↓ generates .claude/agents/engineer-<dir>.md + qa-<dir>.md from ~/.claude/agent-templates/
 ↓ writes Phase Plan + Current Phase (first phase), sync report; runs verify-sync.sh
 ↓ commits: git commit -m "doc-sync(initial): <summary>"
 ├── result: needs-pm → [hook: 'claude --agent pm "change" before any engineering starts'] → PM [change] → Doc-Sync [delta]
 └── result: success → [hook: 'Review the sync report. If it generated new agents, open a new terminal so they load.
                         Then: claude --agent engineer-<first module in the Phase Plan not yet built> "implement"']
 [HUMAN OPENS a new terminal so the generated agents load, then RUNS: claude --agent engineer-mod-<first> "implement"]
Engineer [implement]  (via claude --agent engineer-mod-<name> "implement")
 ↓ first module of the project: infrastructure pre-flight (needs-human on failure)
 ↓ implements within its Source Path (+ project files if it owns them), runs self-check.sh + integration tests + judgment items
 ↓ logs results to modules/<dir>/status.md, updates Last Action
 ↓ commits: git commit -m "engineer-mod-<name>(implement): <summary>"
 [Stop → hook: 'claude --agent qa-mod-<name> "verify"']
 [HUMAN RUNS: claude --agent qa-mod-<name> "verify"]
QA [verify]  (via claude --agent qa-mod-<name>)
 ↓ follows functional-test workflow, runs run-qa.sh, live server / verify skill / human sign-off as the module needs
 ↓ logs results to modules/<dir>/status.md, updates Last Action
 ↓ commits: git commit -m "qa-mod-<name>: pass — <summary>"
 [Stop → hook: next module (see Phase Plan), or — last module of the phase — the phase-end loop below]
```

### Phase-End Loop (every phase)

```
QA passes the last module of the phase
 [hook: 'the coordinator runs /pstack:thermos on the phase's changes ..., then claude --agent tech-lead "phase-end integration review"']
Coordinator
 ↓ runs /pstack:thermos (diff from the last Checkpoint History commit — phase 1: doc-sync(initial) — limited to the phase's Source Paths)
 ↓ saves project-planning/pstack-findings/<date>-thermos-phase-<N>.md, checks git status, commits
 [HUMAN RUNS: claude --agent tech-lead "phase-end integration review"]
Tech Lead [integration-review]
 ↓ reads every module in the phase + the thermos findings, runs scan-integration.sh
 ↓ applies cross-module-checklist.md + optimization-criteria.md
 ↓ lists DEFERRED rows from earlier phases again for a new decision
 ↓ logs PROPOSED rows to project-planning/integration-review.md — or one NO ISSUES row
 ↓ commits: git commit -m "tech-lead(integration-review): phase <N> — <counts>"
 ├── result: clean → [hook: 'claude --agent pm "checkpoint"'] → PM [checkpoint]
 └── result: issues-found
      [hook: 'decide every row (Concerns and Recommendations), then:
              claude --agent tech-lead "decisions: INT-001 approve, INT-002 reject, INT-003 defer"']
      [HUMAN RUNS: claude --agent tech-lead "decisions: ..."]
     Tech Lead [record-decisions]
      ↓ sets APPROVED / REJECTED / DEFERRED exactly as said; asks if ambiguous; unmentioned items stay PROPOSED
      ↓ fills Assigned Module per APPROVED item from the Module Map Source Path (confirmed with the human);
        a fix spanning modules splits into INT-003a / INT-003b, one per owner
      ↓ notes "blast-radius first" where the fix changes code another module depends on
      ↓ commits
      [hook: 'per APPROVED item: claude --agent engineer-<Assigned Module> "integration-fix <INT-ID>"']
      For each APPROVED item:
       (if "blast-radius first") Coordinator runs /pstack:blast-radius → pstack-findings/<date>-blast-radius-<INT-ID>.md
                                 → claude --agent tech-lead "on-demand review of <INT-ID> blast-radius" if the risks change the plan
       Engineer [integration-fix]  → IN PROGRESS → FIXED – AWAITING QA
        [hook: 'claude --agent qa-mod-<name> "integration-fix-verify <INT-ID>"']
       QA [integration-fix-verify] → QA VERIFIED (or back to APPROVED → Engineer again)
        [hook: 'Verify the fix yourself, then: claude --agent tech-lead "<INT-ID> verified: <what you checked>"']
       Human verifies the fix themselves
       Tech Lead [confirm-fix]
        ↓ records HUMAN VERIFIED from the human's statement (date + their words)
        ↓ re-checks the failure scenario → CONFIRMED CLOSED (or back to APPROVED)
        [hook: 'Every row for this phase CONFIRMED CLOSED, REJECTED, DEFERRED or NO ISSUES: claude --agent pm "checkpoint"']
 [HUMAN RUNS: claude --agent pm "checkpoint"]
PM [checkpoint]
 ↓ gate: Integration & Optimization Review entry exists for the phase, and every row for the phase is
   CONFIRMED CLOSED / REJECTED / DEFERRED / NO ISSUES — otherwise stop and list what each open item waits for
 ↓ reads all modules/*/status.md, presents results, gets explicit approval
 ↓ writes "Phase <N> approved — <date> — commit: <hash>" to Checkpoint History, advances Current Phase
 ↓ final phase: writes README.md (confirmed with the user), result: project-complete
 ↓ commits: git commit -m "pm(checkpoint): phase <N> approved"
 ├── more phases → [hook: 'Now in <phase>. Next: claude --agent engineer-<first module of this phase> "implement"']
 └── project-complete → [hook: "Project complete — README.md written. Optional: claude --agent retrospective"]
```

Optional, phase 1 only: while `.claude/skills/verify/` does not exist, the hook's QA-pass message suggests the coordinator run `/pstack:create-verification-skill` once the app runs — only with the human's yes. QA uses `verify` from then on.

### Standard Change Flow (post-sync — Doc-Sync has run at least once)

```
User requests change  OR  Engineer/QA escalates an issue  OR  Doc-Sync left needs-pm questions
 [HUMAN RUNS: claude --agent pm]
PM [change]
 ↓ re-reads prd.md; reads the escalation in modules/<mod>/status.md or the questions in Sync Reports
 ↓ smallest change, quality checklist, confirms with user
 ↓ a changed build/lint/test command: updates Build Config, tags [TRIVIAL] Build Config changed
 ↓ asks user: trivial or substantive? Tags PM Updates [TRIVIAL] / [SUBSTANTIVE]
   (answers to Doc-Sync questions are always [SUBSTANTIVE] and list each marker they resolve;
    an approved Tech Lead convention becomes the next CONV-NNN in section 9 Adopted Conventions)
 ↓ new module: directory + Source Path + Module Map row; increments the PRD revision
 ↓ commits: git commit -m "pm(change): <summary>"
 [Stop → hook: 'Architectural impact: the coordinator runs /pstack:how ..., then claude --agent tech-lead "change review". Otherwise: claude --agent doc-sync']
 ├── Architectural impact:
 │    Coordinator runs /pstack:how on the affected code → pstack-findings/<date>-how-<topic>.md, commits
 │    [HUMAN RUNS: claude --agent tech-lead "change review"]
 │    Tech Lead [change-review]  (repeats the overlapping-modules scan if a module was added)
 │     [hook: 'Accept as-is: claude --agent doc-sync. PRD needs revising: claude --agent pm "change"']
 └── Otherwise → [HUMAN RUNS: claude --agent doc-sync]
Doc-Sync
 ↓ [TRIVIAL]: passthrough — propagate wording (or re-copy Build Config), brief sync note, skip verify-sync.sh
 ↓ [SUBSTANTIVE]: delta-sync of every PM Updates entry since the last Sync Report; new modules (and modules
   skipped earlier with a [BLOCKER] PM has fixed) get spec + status.md + wrappers; modules whose Source Path
   or dependencies changed get their wrappers regenerated
 ↓ commits: git commit -m "doc-sync(<trivial|delta>): <summary>"
 [Stop → hook: 'claude --agent engineer-<first module in the Phase Plan not yet built> "implement"' — or pm "change" on needs-pm]
 [HUMAN RUNS (in a new terminal if new agents were generated): claude --agent engineer-mod-<name> "implement"]
engineer-mod-X → qa-mod-X → … → Phase-End Loop → PM [checkpoint]
```

### On-Demand Tech Lead (anytime)

```
Engineer records result: blocked-technical  OR  QA flags a pattern or setup drift  OR  human sees an architectural concern
 [hook (blocked-technical): 'claude --agent tech-lead "engineer blocker in mod-<name>"']
 [HUMAN RUNS: claude --agent tech-lead "<what to review>"]
Tech Lead [on-demand-review]
 ↓ reads relevant docs + blocker (including modules/<mod>/status.md if needed)
 ↓ writes findings to Tech Lead Reviews, updates Last Action
 ↓ setup drift: updates setup.md / docker-compose.yml / .gitignore with the human's approval,
   adds ### Setup Changed — <date>, result: setup-changed → human redoes the steps →
   Tech Lead [setup-confirmation] → hook: resume the step that found the drift (usually QA "verify")
 ↓ commits: git commit -m "tech-lead(on-demand-review): <concern>"
 [Stop → hook: 'Minor adjustment: claude --agent engineer-<module> "bugfix". PRD-level change: claude --agent pm "change"']
 [HUMAN DECIDES]
 ├── Minor adjustment → claude --agent engineer-mod-<name> "bugfix"
 └── PRD-level change → claude --agent pm "change"
```

An Engineer `blocked-dependency` result does not go to Tech Lead: the hook tells the human to finish the dependency module first, or run PM if the phase order itself is wrong. A bug that has failed QA 3 times on the same AC follows a dedicated version of this flow, with Tech Lead staying the owner of that AC until it resolves — see Bug Fix Loop below.

### Bug Fix Loop

```
QA finds bugs (1st failure on this AC) — result: bugs-found
 ↓ logs specific failures (Input / Expected / Actual) to modules/<dir>/status.md
 ↓ commits: git commit -m "qa-mod-<name>: fail — <summary>"
 [Stop → hook: 'claude --agent engineer-mod-<name> "bugfix" — failures are in QA Results']
 [HUMAN RUNS: claude --agent engineer-mod-<name> "bugfix"]
Engineer [bugfix] (attempt 1)
 ↓ states the observed layer + evidence, writes a one-line impact note, fixes, re-runs self-check.sh
 ↓ commits: git commit -m "engineer-mod-<name>(bugfix): <summary>"
 [Stop → hook: 'claude --agent qa-mod-<name> "regression"']
 [HUMAN RUNS: claude --agent qa-mod-<name> "regression"]
QA [regression]
 ↓ follows regression-test workflow, appends a ### QA Run N — Regression block
 ↓ commits
 ├─ PASS → done
 ├─ FAIL (2nd failure) → same loop back to Engineer (attempt 2)
 └─ FAIL (3rd failure, or an escalation marker is already open) — result: repeat-failure, ac: <AC-ID>
      QA does NOT route back to Engineer again
      ├── no open marker (first escalation):
      │    [hook: 'First escalation of <AC> — the coordinator runs /pstack:how and /pstack:why ..., then
      │            claude --agent tech-lead "repeat-failure review <AC>"']
      │    Coordinator saves pstack-findings/<date>-how-why-<AC-ID>.md, commits
      └── marker for that AC already open: [hook: '<AC> is already escalated — claude --agent tech-lead "repeat-failure review <AC>"']
      [HUMAN RUNS: claude --agent tech-lead "repeat-failure review <AC>"]
     Tech Lead [repeat-failure-review]
      ↓ requires real evidence of which layer caused the bug (asks the human for a specific check if missing)
      ↓ writes ### Repeat-Failure Review — <AC-ID> to Tech Lead Reviews
      ↓ first time only: writes "AC-<ID>: ESCALATED TO TECH LEAD — open" to modules/<dir>/status.md
      ↓ Last Action records module: and ac: <AC-ID>; commits
      [hook: 'claude --agent engineer-<module> "bugfix — follow Tech Lead's repeat-failure diagnosis for <AC>"', or pm "change"]
      [HUMAN RUNS: that command, with Tech Lead's diagnosis in hand]
     Engineer [bugfix] (implements per Tech Lead's diagnosis, not an independent attempt)
      ↓ commits
      [HUMAN RUNS: claude --agent qa-mod-<name> "regression"]
     QA [regression]
      ├─ PASS → flips the marker to "— resolved <date>", done
      └─ FAIL again → routes straight back to Tech Lead (marker still open, no new 3-count)
```

When one run has failures of different kinds, QA records a single result by precedence — `spec-issue` > `repeat-failure` > `bugs-found` — lists every failure, and names the others in its handoff so the human can route them after the first is resolved.

### Retrospective (manual only, after phase or project completion)

```
[Human runs: claude --agent retrospective]
Retrospective
 ↓ reads project-level status.md + all modules/*/status.md + current skills/agents
 ↓ writes structured proposals to project-planning/retrospective/drafts/
 ↓ updates proposed-changes.md summary
 ↓ commits: git commit -m "retrospective: <summary>"
 [No hook message — Retrospective writes no Last Action; it tells the human directly to review proposed-changes.md]
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

**Key invariant**: No agent ever writes to `.claude/skills/` (and `pstack-guard.sh` blocks every agent from writing anywhere under `~/.claude`). Doc-Sync is the only agent that may write to `.claude/agents/`, and only to generate per-module engineer and QA wrappers (`engineer-mod-*.md`, `qa-mod-*.md`) — not to modify any other agent definition. All other `.claude/agents/` changes and all `.claude/skills/` changes require explicit human instruction. Claude Code applies skill and agent changes only after explicit human instruction using the `create-agent-skills` skill.

---

## Status.md Structure

Status is split across two tiers: one project-level file and one per-module file.

### Project-Level: `project-planning/status.md`

The coordination hub for project-wide state. Every agent except Retrospective writes Last Action here before stopping (so `handoff.sh` has one place to parse). PM, Doc-Sync, and Tech Lead write their respective sections here; any agent except Retrospective may append to Skill Recommendations. There are no Engineering Progress or QA Results sections in this file — they live in the module-level files. The skeleton is created by `init-project.sh`.

```markdown
# Project Status

## Last Action
<!-- Machine-readable block. Updated by every agent except Retrospective before stopping.
     handoff.sh parses this section to determine the next suggestion. `mode` is always the bare
     word (an INT-ID goes in the agent's own section, not here). No commit field: git log has the hash. -->
agent: [pm|doc-sync|tech-lead|engineer-mod-<name>|qa-mod-<name>]
mode: [pm: init|iterate|finalize|change|checkpoint — doc-sync: initial|delta|trivial — tech-lead: init-review|pre-sync-review|setup-confirmation|change-review|on-demand-review|integration-review|record-decisions|confirm-fix|repeat-failure-review — engineer: implement|bugfix|integration-fix — qa: verify|regression|integration-fix-verify]
module: [module directory name or "n/a"]
result: [success|needs-human — plus pm: project-complete — doc-sync: needs-pm — tech-lead: setup-changed|clean|issues-found — engineer: blocked-dependency|blocked-technical — qa: bugs-found|setup-drift|spec-issue|repeat-failure]
ac: [only for qa repeat-failure and tech-lead repeat-failure-review: the AC-ID — the hook checks that AC's escalation marker]
timestamp: [ISO 8601]

## Current Phase
<!-- Set by Doc-Sync at initial sync; PM advances it at each checkpoint. Blank until the initial sync. -->
[Phase name/number, which modules are in scope]

## Phase Plan
<!-- Written by Doc-Sync during initial sync — PM must leave this section blank -->
[Derived from PRD Phases & Milestones by Doc-Sync]

## Build Config
<!-- Filled by PM at finalize. PM asks the user for the project's build, lint, and test
     commands and writes them here. Doc-Sync copies these to production.md Shared Conventions
     during the initial sync. Leave a value blank if that step doesn't apply. -->
Build: [build command]
Lint:  [lint command]
Test:  [test command]

## PM Updates
[Change summaries: what changed in PRD, when, why. Pre-sync revisions cite the Tech Lead Reviews entry they answer (untagged). Finalization tagged [INIT]. Subsequent changes tagged [TRIVIAL] or [SUBSTANTIVE]; answers to Doc-Sync questions list each marker they resolve]

## Tech Lead Reviews
[Tech Lead's own entries: ### Review, ### Setup Confirmation, ### Setup Changed, ### Integration & Optimization Review — Phase <N>, ### Repeat-Failure Review — <AC-ID>; Proposed Conventions; pstack input lines]

## Sync Reports
[Doc-Sync output: what was synced, files created/modified, [AMBIGUITY]/[CONFLICT]/[BLOCKER] markers, verify-sync.sh result]

## Decisions
[Owned by PM. Audit trail for user decisions that are not PRD content (e.g. "defer offline mode to v2"), resolved disagreements, and key choices. Each entry: what was decided, who decided (human/PM/Tech Lead), the rationale, and which IDs are affected]

## Module Map
<!-- Filled by PM at finalize, after the user confirms directory names and source paths.
     Updated by PM when modules are added or renamed during change requests.
     Source Path is the code this module owns: the Engineer's write scope, the self-check
     boundary, and what pstack-guard.sh enforces. Several paths are comma-separated.
     Shared code belongs to exactly one module. No two Source Paths may overlap or nest
     (src/ and src/ui/ cannot both appear). Only PM may change this section (pstack-guard.sh).
     Project files are root-level files no single module's code lives in (manifests, lockfiles,
     .env.example, CI config); one module owns them all — one line, directly under the table. -->
| MOD-ID  | Directory        | Module Name    | Source Path              |
|---------|------------------|----------------|--------------------------|
| MOD-001 | mod-login        | User Login     | src/login/               |

Project files: mod-login | package.json, package-lock.json, .env.example, .github/

## Checkpoint History
[Phase completion confirmations from user, with git commit hash for each checkpoint]

## Skill Recommendations
<!-- PM, Doc-Sync, Tech Lead, Engineer, and QA may append an entry here when they notice a recurring pattern, useful convention,
     or gap worth codifying as a skill. No agent may edit or remove another agent's entries.
     Retrospective reads this as a primary input. Human reviews at checkpoint or anytime. -->
<!-- Format per entry:
     Pattern: <what was observed>
     Why: <why it should be a skill>
     Agent: <who logged it> -->
```

### Module-Level: `project-planning/modules/mod-xxx/status.md`

One file per module. Created by Doc-Sync during initial sync (and when a new module is added). Engineer writes Engineering Progress; QA writes QA Results (each regression run as a `### QA Run N — Regression — <date>` block inside `## QA Results`). Tech Lead may add only the `AC-<ID>: ESCALATED TO TECH LEAD — open` line, which QA flips to `— resolved <date>`. PM reads these files in change and checkpoint mode.

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
| 3 | `.claude/skills/prd-format/templates/CLAUDE.tmpl.md` | Coordinator Instructions (run mode, ownership rules, Required pstack steps) scaffolded to project root |
| 4 | `.claude/skills/prd-format/templates/global-CLAUDE.tmpl.md` | Source for the `~/.claude/CLAUDE.md` safety net (deployed by hand) |
| 5 | `.claude/skills/prd-format/references/writing-standards.md` | Detailed writing guidance with good/bad examples |
| 6 | `.claude/skills/prd-format/references/anti-patterns.md` | Common PRD mistakes with corrections |
| 7 | `.claude/skills/prd-format/references/readme-standards.md` | Final-checkpoint README standards |
| 8 | `.claude/skills/prd-format/scripts/init-project.sh` | Scaffolds project-planning/ directory + root CLAUDE.md |
| 9 | `.claude/skills/doc-sync-methodology/SKILL.md` | Router + mapping rules + principles |
| 10 | `.claude/skills/doc-sync-methodology/workflows/initial-sync.md` | First sync step-by-step |
| 11 | `.claude/skills/doc-sync-methodology/workflows/delta-sync.md` | Change propagation step-by-step |
| 12 | `.claude/skills/doc-sync-methodology/templates/production.tmpl.md` | Structure for production.md |
| 13 | `.claude/skills/doc-sync-methodology/templates/module-spec.tmpl.md` | Structure for module specs |
| 14 | `.claude/skills/doc-sync-methodology/references/translation-rules.md` | Integrity guardrails with examples |
| 15 | `.claude/skills/doc-sync-methodology/scripts/verify-sync.sh` | Automated sync verification |
| 16 | `.claude/skills/coding-conventions/SKILL.md` | Default conventions + routing |
| 17 | `.claude/skills/coding-conventions/references/style-examples.md` | Before/after code examples |
| 18 | `.claude/skills/engineer-checklist/SKILL.md` | Checklist items + process |
| 19 | `.claude/skills/engineer-checklist/references/llm-prompt-context-budget.md` | Token budget for prompts built from user text |
| 20 | `.claude/skills/engineer-checklist/scripts/self-check.sh` | Automated pre-QA checks (incl. write-scope check) |
| 21 | `.claude/skills/engineer-checklist/scripts/module_scope.py` | Module Map scope rules shared by `self-check.sh` and `pstack-guard.sh` |
| 22 | `.claude/skills/qa-checklist/SKILL.md` | Checklist + routing |
| 23 | `.claude/skills/qa-checklist/workflows/functional-test.md` | First-time verification procedure |
| 24 | `.claude/skills/qa-checklist/workflows/regression-test.md` | Re-verification after a bug fix or integration fix (incl. repeat-failure check) |
| 25 | `.claude/skills/qa-checklist/scripts/run-qa.sh` | Automated test runner + reporter |
| 26 | `.claude/skills/qa-checklist/references/common-failure-patterns.md` | Known gotchas (living doc) |
| 27 | `.claude/skills/integration-review/SKILL.md` | Router + principles for the phase-end review |
| 28 | `.claude/skills/integration-review/workflows/phase-review.md` | First-time review procedure for a phase |
| 29 | `.claude/skills/integration-review/workflows/record-decisions.md` | Recording the human's approve / reject / defer decisions + Assigned Module |
| 30 | `.claude/skills/integration-review/workflows/confirm-fix.md` | Recording HUMAN VERIFIED and closing out an item |
| 31 | `.claude/skills/integration-review/templates/integration-review.tmpl.md` | Structure for project-planning/integration-review.md |
| 32 | `.claude/skills/integration-review/references/cross-module-checklist.md` | Conflict + leak checklist (living doc) |
| 33 | `.claude/skills/integration-review/references/optimization-criteria.md` | Optimization proposal criteria |
| 34 | `.claude/skills/integration-review/scripts/scan-integration.sh` | Automated first-pass scan (lead list, not a verdict) |

### Agents (create second — they reference skills)

| # | File | Description |
|---|---|---|
| 35 | `.claude/agents/pm.md` | PM agent definition |
| 36 | `.claude/agents/doc-sync.md` | Doc-Sync agent definition |
| 37 | `.claude/agents/tech-lead.md` | Tech Lead agent definition |
| 38 | `.claude/agents/retrospective.md` | Retrospective agent definition |
| 39 | `.claude/agent-templates/engineer.md` | Engineer base template — kept outside `agents/` so Claude Code does not load it as an agent; Doc-Sync reads this to generate per-module wrappers |
| 40 | `.claude/agent-templates/qa.md` | QA base template — kept outside `agents/` so Claude Code does not load it as an agent; Doc-Sync reads this to generate per-module wrappers |

> **Note**: Per-module engineer and QA agent wrappers (`engineer-mod-<name>.md`, `qa-mod-<name>.md`) are generated dynamically by Doc-Sync during each sync — they are not manually created files and are not included in this static manifest.

### Hooks & Config (create third)

| # | File | Description |
|---|---|---|
| 41 | `.claude/hooks/handoff.sh` | Stop/SubagentStop handoff hook |
| 42 | `.claude/hooks/pstack-guard.sh` | PreToolUse guard: skill allowlists, `~/.claude` and Module Map protection, engineer write scope, read-only pstack reviewers |
| 43 | `.claude/hooks/settings-hooks.json` | Hook entries to merge into `settings.json` |

**Total: 43 files**

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
- Retrospective is kept manual by its description ("MANUAL INVOCATION ONLY … never invoke automatically"); it has no `disable-model-invocation` line, and it records no Last Action
- Every agent is written to be run directly by the human (`claude --agent <name>`), so it can ask the human questions; none starts another agent
- Scope tools per agent as specified in the Write Access Matrix; skill access beyond that is set in `pstack-guard.sh`'s allowlists, since the `Skill` tool cannot be scoped per agent
- `engineer.md` and `qa.md` are **base templates** in `.claude/agent-templates/` (outside `agents/`, so Claude Code does not load them as agents). Doc-Sync generates thin per-module wrappers (`engineer-<dir>.md`, `qa-<dir>.md`, e.g. `engineer-mod-login.md`) from `~/.claude/agent-templates/` during each sync that adds a module, and regenerates them when a module's Source Path, dependencies, or directory changes. Each wrapper: (a) copies the template's frontmatter `tools` and `model` lines exactly and sets `name:` to the wrapper name, (b) uses the template's system prompt body verbatim, (c) hardcodes the assigned spec path (`modules/<dir>/spec.md`) and the module's Source Path from the Module Map, (d) hardcodes read access to the dependency modules' `modules/<dep-dir>/status.md` files. Never run a base template directly — always use the per-module wrapper

### Agent Definition Rules

These rules prevent gaps between what skills teach and what agents enforce. Apply them when creating or updating any agent definition.

**Constraint mirroring**:
- If a skill contains a critical rule (e.g., "always confirm with user before writing"), that rule must also appear as an explicit constraint in every agent that uses that skill. Skill-level rules are suggestions; agent-level constraints are enforced. Don't rely on the agent reading the skill carefully — duplicate the non-negotiable rules

**Write scope exhaustiveness**:
- Every file an agent can create or modify must be listed in its Write Scope. If the agent commits to git, `status.md` must be in its Write Scope (since Last Action is updated there). If a workflow requires creating a new file type (e.g., a new module spec), the write scope must cover the directory pattern (`modules/*/spec.md`), not just the known filenames

**Information boundary justification**:
- If an agent is denied access to a file, consider whether the agent's workflows will frequently need context from that file. If so, the file they *do* have access to must carry that context forward (e.g., the module spec's Context section carries forward PRD rationale so the Engineer doesn't need `prd.md`). Every information boundary should have a corresponding "context bridge" in the downstream doc

### Generating Hooks
- Use the `create-hooks` skill for both hooks
- `handoff.sh`: register on `Stop` (primary — every framework agent runs as a direct `claude --agent` session) and `SubagentStop`. It resolves the project root from subdirectories (with or without git), reads `status.md` Last Action (including `ac:`), shows each new Last Action once (fingerprint in `.git/handoff-last-shown`), and prints the per-mode suggestion from the Handoff Messages table
- `pstack-guard.sh`: register on `PreToolUse` with matcher `Skill|Edit|Write|MultiEdit|NotebookEdit`; exit 2 with a reason on stderr to block. It reads the scope rules from `~/.claude/skills/engineer-checklist/scripts/module_scope.py`, so skills must be installed
- Both need `jq` (`pstack-guard.sh` also `python3`); make executable with `chmod +x`
- Register under `"hooks"` in `.claude/settings.json` (project) or `~/.claude/settings.json` (account-level) — never a standalone `hooks.json`, which Claude Code does not load outside plugins
- Show the user its message as JSON `systemMessage`; plain stdout from a Stop hook only reaches the debug log

### Script Conventions
- All scripts are bash, POSIX-compatible where possible
- All scripts take project root path as argument (don't assume cwd)
- All scripts output structured results to stdout
- Exit code 0 = success, non-zero = failure with details
- Scripts read configuration from `production.md` rather than hardcoding tools/commands
- All scripts must be executable (`chmod +x`)

### Git Commit Convention
- Every agent commits its work before it stops — each handoff is a clean rollback point. Last Action has no commit hash: `git log` gives the real one (recording a hash and then amending would record a commit that no longer exists).
- Commit message format: `<agent-name>(<mode-or-module>): <one-line summary>`
  - Examples: `pm(init): draft PRD for payment service`, `doc-sync(delta): synced MOD-004 addition`, `tech-lead(integration-review): phase 2 — 1 concern, 2 recommendations`, `engineer-mod-orders(implement): implement order processing`, `qa-mod-orders: pass — all 12 acceptance criteria verified`, `pstack(thermos): phase 1` (coordinator, findings only), `pstack(create-verification-skill): verify skill`
  - Engineers must use the exact `engineer-<dir>(<implement|bugfix|integration-fix>):` prefix — `self-check.sh` walks back through the commits with that prefix to scope-check committed work
- Agents commit only files within their write scope — never stage files outside their access boundary
- `handoff.sh` warns about any uncommitted change in the repo when it shows a handoff
- Checkpoint History entries in `status.md` record the git commit hash alongside phase completion notes, providing named rollback points for major milestones
- To roll back to a previous handoff: `git log --oneline` to find the handoff commit, then `git revert <hash>` or `git reset --hard <hash>` depending on whether the rollback itself should be tracked

### Order of Creation
1. Skills first (agents reference them) — files 1-34
2. Agents second (hooks reference agent names) — files 35-40 (base templates in `agent-templates/`)
3. Hooks and config third — files 41-43
4. `project-planning/` folder structure is created per-project by PM via `init-project.sh`
5. Per-module agent wrappers (`engineer-mod-*.md`, `qa-mod-*.md`) are generated by Doc-Sync during the initial sync — not manually created

### Installation
After all files are created and reviewed in the staging directory:
```bash
mkdir -p ~/.claude/agents ~/.claude/agent-templates ~/.claude/skills ~/.claude/hooks
cp -r .claude/agents/.          ~/.claude/agents/
cp -r .claude/agent-templates/. ~/.claude/agent-templates/   # Doc-Sync reads the base templates from here
cp -r .claude/skills/.          ~/.claude/skills/
cp -r .claude/hooks/.           ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
# Merge the entries in .claude/hooks/settings-hooks.json into the "hooks" key of ~/.claude/settings.json
# (registers handoff.sh on Stop/SubagentStop and pstack-guard.sh on PreToolUse; the osascript
#  notification entries are optional and macOS-only)
# Optional: deploy prd-format/templates/global-CLAUDE.tmpl.md as ~/.claude/CLAUDE.md (safety net)
# Optional: install the pstack plugin for the coordinator-run pstack steps
```

To start a new project:
```bash
cd ~/projects/my-new-app
claude --agent pm
```