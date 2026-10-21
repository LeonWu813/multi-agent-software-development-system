# Development Team Agents — Complete Architecture

This document defines the complete architecture for a multi-agent development team system built with Claude Code agents, skills, and hooks. It is the single source of truth for generating all files.

---

## System Overview

A team of 6 specialized agents that simulate a software development workflow with strict information boundaries, file-based coordination, and human approval at every decision. Each agent runs with its own fresh context — no shared memory, coordinating exclusively through files on disk. Skills provide reusable knowledge that agents consume using a router + progressive disclosure pattern. The default Claude Code session acts as the **coordinator**: in **one-conversation mode** it runs the framework agents for the human as subagents, one after another, following each agent's `next:` line, and stops for the human at every decision point (every PM change, integration-review decisions, QA sign-off, setup, any `needs-human`); it also diagnoses and runs the pstack review steps whose findings Tech Lead reads — it never edits an owned artifact itself. Hooks print the exact `claude --agent <name> "<word>"` command for the next step; in one-conversation mode the coordinator runs it as a subagent, and the human can still run any agent directly as its own session under the same rules.

### Core Principles

- **Single responsibility**: Each agent has one job, one input, one output, one handoff rule
- **Information boundaries**: Agents only access the files they need — no agent sees everything
- **Human in the loop**: Every decision is the human's — the coordinator relays agents' questions and the human's answers word for word, and PM changes nothing without the human's quoted approval
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

**Run modes.** In **one-conversation mode** (the default flow) the coordinator — the default Claude Code session — runs every framework agent as a subagent in the same conversation (Agent tool, `subagent_type` = the agent's name, with its start word as the first line of its instructions). **Direct runs still work**: the human can start any agent as its own session (`claude --agent <name> "<word>"`), and both modes follow the same rules. Every command in the docs and the hook's messages is written in the `claude --agent` form; in one-conversation mode it means "start that agent as a subagent with the quoted word". The coordinator also runs the pstack steps itself (see Handoff Chains → pstack Steps).

A subagent cannot ask the human anything, so every agent carries a run-mode rule:
- **Resuming after `/clear`**: the coordinator starts every conversation by reading Last Action and resuming from `next:`; nothing the flow needs lives only in the conversation (PM's pending proposals are files in `project-planning/pm-proposals/`).
- **PM** runs in two passes. A **proposal pass** (no `Approved by <name>: "<exact words>"` quote in its instructions covering the change) changes nothing the proposal is about — no `prd.md`, no other `status.md` section; it saves the proposal and its questions to `project-planning/pm-proposals/<date>-<topic>.md`, writes a Last Action (`needs-human`, `next:` naming the file) and commits `pm(proposal): …`, so a `/clear` loses nothing —, no directories, no commit — and returns the exact proposed change (PRD text and status.md entries, verbatim) plus numbered questions, including every question its steps tell it to ask (trivial or substantive, architectural or not, Retrospective now or not, build commands, directory names). An **apply pass** (the quote is present) applies exactly what was approved, answers each question with the human's quoted words, and records `Approved by <name> in the coordinator session: "<quote>"` in the PM Updates entry; if the quote doesn't cover something, PM stops with `result: needs-human` and the question.
- **Tech Lead, Doc-Sync, Retrospective, Engineer, QA** (a `<run_modes>` block): as a subagent the agent never asks; whenever it would ask the user or needs something only the user can give (a decision, a device check, a sign-off, setup), it stops with `result: needs-human` (QA UI sign-off: `needs-signoff`) and puts the exact question or script in its final message. A user answer quoted in its instructions (`<name>: "<exact words>"`) counts as the user's own words and is recorded where the agent records any user decision; the coordinator's own wording never counts as the user's decision.

**The coordinator's loop.** Start the agent the flow calls for; when it returns, read the `## Last Action` block in `status.md` — its `next:` line names the next step; run any required pstack step; start the next agent; repeat until a stopping point. **Stopping points** (the human decides, the coordinator never does): PM, every time it changes something (proposal shown word for word, then the apply pass with the human's quoted approval; any change by the human means another proposal pass); integration-review decisions and the human's own verification of a fix (the human's words go to Tech Lead quoted exactly); QA `needs-signoff` (the human runs QA's test script, then QA runs again with `ui-results: <the human's exact words>`); setup steps (`setup.md`); any `needs-human`; any scope violation the agent can't resolve; and optional steps (verify skill, Retrospective offer), run only on a yes. **Relay rules**: questions and answers pass through verbatim in both directions; the coordinator never answers for the human, never fills a gap with its own judgment, and never drops or softens a condition an agent stated ("finish setup.md first" stays a condition); the human's words go into the next agent's instructions as `<name>: "<exact words>"`. **New agents**: when Doc-Sync generates agents for a new module, Claude Code may not see them until the session restarts; if a subagent type is unknown, the coordinator tells the human to run `claude --continue` in the project folder, which reopens the same conversation with the new agents loaded.

Every agent that writes a Last Action block (all but Retrospective) always records `next:` — the exact command for the next step, with the agent's start word, including any coordinator pstack step the project `CLAUDE.md` table requires, and naming real modules and IDs rather than placeholders whenever it knows them. The coordinator reads it to pick the next step, the handoff hook prints it, and because it stays in `status.md` it can be shown again later. The hook's own per-mode defaults remain as the fallback when `next:` is missing.

### PM

- **File**: `.claude/agents/pm.md` (model: opus)
- **Single Responsibility**: Own `prd.md` + all user communication
- **Tools**: Read, Write, Grep, Glob, Bash, Skill (allowlist: `prd-format`, `pstack:sharpen`, `pstack:unslop`, `pstack:technical-writing`, plus the project's own `.claude/skills/<name>/` skills — enforced by `pstack-guard.sh`). `sharpen` runs once at the start of init; `unslop`/`technical-writing` only on prose PM wrote or changed in this invocation, wording only — every ID, number, and AC must mean the same afterwards
- **Write Scope**: `prd.md`; project-level `status.md` PM sections only (Last Action, Build Config, PM Updates, Module Map — PM is the only agent `pstack-guard.sh` lets change it — Checkpoint History, Decisions (user decisions that are not PRD content, e.g. "defer offline mode to v2", or "verify skill: declined"), Skill Recommendations, and Current Phase — advanced at checkpoint, and also updated when a change adds a module to the current phase); `modules/mod-*/` directory + `.gitkeep` creation only (never files inside a module directory); `README.md` at the project root, final checkpoint only
- **Read-only exceptions**: `production.md` and `setup.md` for the final README; `integration-review.md` for the checkpoint gate; `modules/*/status.md` in change and checkpoint mode (escalations and QA results live there); the project `CLAUDE.md`, for its pstack-step table when writing `next:`
- **Skills Used**: prd-format
- **Invocation**: `claude --agent pm`, usually with the mode word the hook prints (`"iterate"`, `"finalize"`, `"change"`, `"checkpoint"`). As a subagent, PM runs in two passes — a proposal pass that saves its proposal to `project-planning/pm-proposals/` and changes nothing else, then an apply pass carrying `Approved by <name>: "<exact words>"` (see Run modes above); every "confirm with the user" below works that way in one-conversation mode. Without a mode word, PM picks the mode from where the project is, top rule first; when both checkpoint and change apply, checkpoint wins (a change the user also wants comes after it)
- **Modes**:
  - `init` (no `project-planning/` yet): run `pstack:sharpen` on the request, then restate the goal in two or three sentences and wait for the user to correct it; run `scripts/init-project.sh`; gather requirements through numbered questions; fill `prd.md` from `templates/prd.tmpl.md`; review against `references/anti-patterns.md` and the quality checklist; confirm with the user before writing; commit `project-planning/` together with the scaffolded root `CLAUDE.md`. Next: Tech Lead
  - `iterate` (PRD drafted, `[INIT]` not yet tagged): apply Tech Lead feedback or user edits using the pre-sync iteration protocol — no `[TRIVIAL]`/`[SUBSTANTIVE]` tags. Notes in PM Updates which Tech Lead Reviews entry each change answers (never writes in Tech Lead Reviews). A `Proposed Convention:` the user approves goes into section 9 Adopted Conventions as the next `CONV-NNN` right away — the initial sync copies it
  - `finalize` (user gave final approval): **setup gate** — a `### Setup Confirmation` block must exist in Tech Lead Reviews and no `### Setup Changed` entry may be newer than it; write Build Config (`Build:` / `Lint:` / `Test:`); propose and confirm the **Module Map** — a `mod-<kebab-name>` directory and a **Source Path** per module (folders, files, or filename patterns such as `supabase/migrations/*_mod_003_*` when one folder holds several modules' files; no path claimed by two modules, and none nested inside another — `src/` and `src/ui/` cannot both appear; shared code has one owner module) plus a `Project files: <dir> | <paths>` line naming the one module that owns the root-level files no Source Path covers (package manifests, lockfiles, `.env.example`, CI config) — then create each directory with `.gitkeep`; tag a PM Updates entry `[INIT]`. Next: Doc-Sync
  - `change` (`[INIT]` already tagged): a requirements change from the user, an escalation read from `modules/<mod>/status.md`, or Doc-Sync's `[AMBIGUITY]`/`[CONFLICT]`/`[BLOCKER]` questions in Sync Reports. Smallest change, quality checklist, confirm with the user, tag `[TRIVIAL]` or `[SUBSTANTIVE]` (answers to Doc-Sync questions are always `[SUBSTANTIVE]` and list each marker they resolve). Every PM Updates entry starts with exactly one first line, `- YYYY-MM-DD [TAG] [ARCHITECTURAL] <one-line summary>`, with details on indented lines below; tags appear only on that first line (the hook and Doc-Sync read it), never in prose elsewhere in the entry. PM also asks whether the change is **architectural** (it changes how the system is built — data model, module boundaries, integrations, tech stack) and, on a yes, adds `[ARCHITECTURAL]` to the PM Updates entry; the hook routes such a change to the coordinator's `/pstack:how` step and Tech Lead before Doc-Sync. A requirement an Engineer reported it cannot build as written (`result: spec-issue`) arrives here too, as `pm "change: spec issue from engineer-mod-<name>"`. A Tech Lead convention the user approved goes into PRD section 9 **Adopted Conventions** as the next `CONV-NNN`, citing its Tech Lead Reviews entry, tagged `[SUBSTANTIVE]`. A changed build, lint, or test command updates `## Build Config` and is tagged `[TRIVIAL] Build Config changed`, so Doc-Sync's passthrough copies it into `production.md` (which `self-check.sh` and `run-qa.sh` read). A new module gets its directory, Source Path, and Module Map row before the handoff (and the `## Current Phase` line is updated if it joins the current phase). When a change moves code from one module's Source Path to another's (e.g. a new owner module for shared code), the ACs about that code move to the new owner in the PRD too, confirmed with the user. Increments the PRD revision
  - `checkpoint` (`[INIT]` tagged, every module in the current phase passed QA, and every integration-review row resolved): **gate** — `integration-review.md` must exist, Tech Lead Reviews must have an Integration & Optimization Review entry for the current phase, and every row in the file — whatever its Phase column says, so a carried-forward row approved again in this phase still has to be closed — must be `CONFIRMED CLOSED`, `REJECTED`, `DEFERRED` (not at the final checkpoint), `SPLIT`, `ACCEPTED (KNOWN ISSUE)`, or `NO ISSUES`; anything else (`PROPOSED` through `HUMAN VERIFIED`) is open and stops the checkpoint. **Final phase only (step 1b)**: before anything else, every `DEFERRED` row is resolved — PM asks the user to approve it, reject it, or accept it as a known issue, then stops with `result: blocked` and `next: claude --agent tech-lead "decisions: INT-003 accept as known issue, INT-005 approve"` (the user's words); Tech Lead records them (an accepted row becomes `ACCEPTED (KNOWN ISSUE)`), approved rows go through the normal fix loop, and the checkpoint is run again once no row is `DEFERRED` or otherwise open. A blocked run writes nothing to Checkpoint History and creates no tag. Then compile module results, present them, get explicit approval, ask the user whether to run a short Retrospective on the phase (step 4a — asked before anything is written, so the checkpoint commit and tag include the answer: yes → `claude --agent retrospective "phase <N>"` goes in `next:` before the next phase's first Engineer; no → `retrospective: skipped` under this phase's Checkpoint History line), write `Phase <N> approved — <date> — commit: <hash>` to Checkpoint History, and advance `## Current Phase` to the next phase. On the final phase PM then writes `README.md` per `references/readme-standards.md` (confirmed with the user), listing every `ACCEPTED (KNOWN ISSUE)` row under "Known issues", and records `result: project-complete`. Results: `success`, `blocked` (a gate failed or `DEFERRED` rows await decisions), `project-complete` (final checkpoint). Every checkpoint commit is tagged `git tag checkpoint-<N>` as a rollback point (the human pushes it with `git push --tags`)
- **Input**: User requirements, change requests, escalations in `modules/*/status.md`, Doc-Sync questions in Sync Reports, Tech Lead Reviews
- **Output**: Approved `prd.md` + tagged change summary in `status.md`
- **Handoff**:
  - After `init`: → Tech Lead (init review)
  - After `iterate`: → Tech Lead (pre-sync review) if the changes are architectural; otherwise PM `finalize` once the user approves
  - After `finalize`: → Doc-Sync (initial sync)
  - After `change`: → coordinator runs `/pstack:how`, then Tech Lead (change review) if the entry is tagged `[ARCHITECTURAL]`; otherwise → Doc-Sync
  - After `checkpoint`: → `engineer-mod-<first module of the new Current Phase> "implement"` (specs for every phase already exist from the initial sync) — preceded, when `.claude/skills/verify/` exists, by the coordinator refreshing it with `/pstack:maintain-verification-skill` (with the human's OK) — or project complete. A `blocked` checkpoint (stopped at the gate, or final-phase `DEFERRED` rows awaiting decisions) announces no next phase: PM's `next:` names what to run (e.g. `tech-lead "decisions: …"`), and without one the hook points to PM's last message for what is still open
- **Constraints**:
  - Never writes to `prd.md` without explicit user approval — silence, "maybe", or a follow-up question is not approval
  - Never tags `[INIT]` without a `### Setup Confirmation` entry in `status.md` (and none superseded by a newer `### Setup Changed`) — a coordinator's or anyone's assertion is not enough; the artifact must be in the file
  - Never runs checkpoint without the phase-end review complete and no row anywhere in `integration-review.md` still open — same standard: the file must show it
  - Never makes technical decisions — PM decides *what*, Tech Lead decides *how*
  - If requirements are ambiguous, asks numbered questions and waits; no `[DECISION NEEDED]` markers remain at handoff
  - Runs the full quality checklist before every handoff, not just the first draft
  - Never touches `production.md`, `modules/*/spec.md`, `integration-review.md` (except the read at checkpoint), source code, or `.claude/` files (its own `~/.claude/skills/prd-format/` is the exception)
  - Commits before stopping: `git commit -m "pm(<mode>): <summary>"`; a checkpoint commit is also tagged `checkpoint-<N>`

### Doc-Sync

- **File**: `.claude/agents/doc-sync.md` (model: sonnet)
- **Single Responsibility**: Translate `prd.md` content into downstream planning docs — nothing more, nothing less
- **Tools**: Read, Write, Grep, Glob, Bash (no `Skill` — `pstack-guard.sh` gives Doc-Sync an empty allowlist; it must never run a rewriting skill on its output)
- **Template refresh**: without a PM tag, when asked (`claude --agent doc-sync "template refresh"`, or by the coordinator) after the framework's agent templates change, regenerates every per-module agent from the current templates and Module Map, touches no spec, `production.md` or PRD, and records `mode: template-refresh` with `next:` repeating the step that was next before.
- **Write Scope**: `production.md`; `modules/*/spec.md`; `modules/*/status.md` (created with empty Engineering Progress + QA Results sections at initial sync and when a module is added); project-level `status.md` Last Action, Sync Reports, Phase Plan, Skill Recommendations, and Current Phase (set once, at initial sync — PM advances it after that); `.claude/agents/engineer-<dir>.md` and `.claude/agents/qa-<dir>.md` (generated wrappers)
- **Skills Used**: doc-sync-methodology
- **Invocation**: `claude --agent doc-sync`, after every PM tag (`[INIT]`, `[SUBSTANTIVE]`, `[TRIVIAL]` — trivial included)
- **Input**: `prd.md` (read-only) + PM Updates, Module Map, and Build Config in `status.md`
- **Output**: Updated downstream docs + sync report in `status.md`
- **Workflow Selection** (from the PM Updates tag):
  - `[INIT]`: follow `workflows/initial-sync.md`
  - `[SUBSTANTIVE]`: follow `workflows/delta-sync.md` — syncs **every** PM Updates entry after the one named in the last Sync Report's `PM Update reference` (its cursor), in the order they appear (by position, not date) (a `[TRIVIAL] Build Config changed` entry in that window still re-copies Build Config)
  - `[TRIVIAL]`: passthrough — process every `[TRIVIAL]` entry added since the last Sync Report in one run, in the order they appear in PM Updates (position, not date — same-day entries are common), propagating each wording change to the affected docs only; write a brief sync note, skip `verify-sync.sh`. A `[TRIVIAL] Build Config changed` entry means: copy `status.md` Build Config into `production.md` Shared Conventions again
  - Mixed tags among the waiting entries: use the strongest — `[SUBSTANTIVE]` (delta sync, which also carries the trivial wording changes) over `[TRIVIAL]`
  - No tag or unclear tag: write an `[AMBIGUITY]` entry to Sync Reports and stop
- **Per-module wrappers**: for each module, Doc-Sync generates `engineer-<dir>.md` and `qa-<dir>.md`, where `<dir>` is the Module Map directory (`mod-login` → `engineer-mod-login`). They are built from `~/.claude/agent-templates/engineer.md` and `qa.md`: the template's frontmatter `tools` and `model` lines are copied exactly and its body verbatim, `name:` is set to the wrapper name, and the wrapper hardcodes the module's spec path, its Source Path, and read access to each dependency module's `status.md`. A delta sync regenerates the wrappers of every module whose Source Path, dependencies, or directory changed, so no wrapper names an old Source Path. After a sync that adds or regenerates a wrapper, the human opens a new terminal so it loads
- **Handoff**: `result: success` → human reviews the sync report → after the initial sync, `engineer-mod-<first module in the Phase Plan> "implement"`; after a delta sync, `next:` names the Engineer of every module whose spec changed — `"spec-update"` if the module has been built (whether or not it passed QA yet), `"implement"` if it has not been built. A wording-only `[TRIVIAL]` change that alters no requirement or AC needs no Engineer run: `next:` says so and repeats the step that was next before the change. A change only to `production.md` (e.g. a new CONV) names the modules whose code it affects, with `"spec-update"`, or none if it only applies to future work. If the sync created an owner module that takes over code other modules already hold, the handoff first sends the human to `tech-lead "log migration rows for <owner dir>"`. `result: needs-pm` → `pm "change"` before any engineering starts
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
  - `project-planning/integration-review.md` — creates it from the template; owns `PROPOSED` / `NO ISSUES` / `SPLIT` / `CONFIRMED CLOSED`, and `ACCEPTED (KNOWN ISSUE)` when the human accepts a `DEFERRED` row as a known issue at the final checkpoint; records the human's `APPROVED` / `REJECTED` / `DEFERRED` decisions (with Assigned Module) and `HUMAN VERIFIED` exactly as the human states them in the session. Never sets `IN PROGRESS`, `FIXED – AWAITING QA`, or `QA VERIFIED`
  - `modules/<mod>/status.md` — only the single `AC-<ID>: ESCALATED TO TECH LEAD — open` line, only during a repeat-failure review of that module
- **Skills Used**: coding-conventions (reference), integration-review (phase-end review, record decisions, confirm fix) — both read as files, not through the `Skill` tool
- **pstack findings**: when a findings file exists for the invocation, Tech Lead reads it as evidence, checks every finding against the code or docs, adds a `pstack input:` line naming the file, and lists which findings it accepted (with its own location and failure scenario) and rejected (with a reason). If the project `CLAUDE.md` calls for a findings file and none exists, it says so at the top of the review and continues
- **Modes** (Last Action `mode`):
  - `init-review` — mandatory review of the first PRD draft (`production.md` does not exist yet): checks installed tool versions against the Tech Stack, evaluates feasibility, risks, dependencies, gaps, shared conventions, and overlapping modules; creates `.gitignore`, `setup.md` (ending with a Setup Confirmation section, and naming the exact build command — Build Config does not exist yet), and for backend projects `.env.example` and `docker-compose.yml`. Init is stack-neutral: `.gitignore` entries come from the PRD tech stack (always `.env`, IDE/OS files, logs; plus Java/Maven, Node/Vite, Python — `__pycache__/`, `.venv/`, `.pytest_cache/` and the like — and any other build, cache, or coverage output the stack produces); `setup.md` covers every API key or secret the PRD needs, with no stack-specific steps baked in
  - `pre-sync-review` — re-review of a PM `iterate` revision the human judged architectural; reviews only what changed. If the revision changes the tech stack or infrastructure, updates `setup.md` (and the infrastructure files), adds a `### Setup Changed — <date>` entry listing what the human must redo, and records `result: setup-changed`
  - `setup-confirmation` — the human says "Setup is complete": verifies that every service `docker-compose.yml` defines is running (`docker compose ps`, backend) or that the build command named in `setup.md` exits cleanly (frontend-only), checks `.env` for existence and gitignore status only, and records `### Setup Confirmation — <date>` stating what it ran and saw. Also used after `[INIT]`, when an on-demand review changed setup — then `next:` names the agent to resume (e.g. `claude --agent qa-mod-auth "verify"`). The entry's closing line differs: before `[INIT]` "PM agent may now finalize and tag [INIT].", after `[INIT]` "Setup re-confirmed after the change listed in Setup Changed." (the hook detects `[INIT]` only in PM Updates, so this text does not confuse it)
  - `change-review` — a mid-project PRD change tagged `[ARCHITECTURAL]`. Records `next:` in Last Action — the exact next command, with the agent's start word (every mode records `next:`; for `change-review` and `on-demand-review` the hook's fallback just points at the review)
  - `on-demand-review` — an Engineer `blocked-technical` blocker (from `modules/<mod>/status.md` Engineering Progress), a QA pattern suggesting a design problem, QA-reported setup drift (`setup.md` out of step with the real infrastructure — Tech Lead updates it with the human's approval, `result: setup-changed`), a blast-radius report that changes the plan for an integration fix, or "log migration rows for <owner>" — after Doc-Sync created a new owner module for code other modules already hold, one `PROPOSED` integration-review row per module that must delete its copy and use the owner, with `next:` asking the human to decide them (`tech-lead "decisions: ..."`). Records `next:` like `change-review` (e.g. `next: claude --agent engineer-mod-auth "integration-fix INT-001a"`, or `next: claude --agent qa-mod-auth "verify"` when nothing needed changing)
  - `integration-review` — mandatory phase-end review after every module in the current phase passes QA; `result: clean` (a `NO ISSUES` row) or `issues-found`
  - `record-decisions` — the human's approve / reject / defer decisions on `PROPOSED` items (`workflows/record-decisions.md`) — and, at the final checkpoint only, `ACCEPTED (KNOWN ISSUE)` for a `DEFERRED` row the human accepts as a known issue; a fix spanning modules splits into letter-suffixed rows and the original becomes `SPLIT`
  - `confirm-fix` — records `HUMAN VERIFIED` from the human's own statement ("INT-003 verified: …") on a `QA VERIFIED` item, re-checks the failure scenario, then sets `CONFIRMED CLOSED` or sends it back to `APPROVED`
  - `repeat-failure-review` — the same AC failed a 3rd time, or failed again under an open escalation marker; Last Action also records `module:` and `ac: <AC-ID>`. The escalation marker is written on the first invocation for the AC since its last marker was resolved (or ever); when QA escalates several ACs at once, Tech Lead writes one marker per AC and one combined `### Repeat-Failure Review — AC-004, AC-008 — <date>` entry with a section per AC
  - Every mode may also record `result: needs-human` when it is waiting on the human, and any mode that changed setup files records `result: setup-changed`
- **Shared code ownership**: when modules overlap (init review, or whenever a module is added), Tech Lead proposes an **owner** before engineering starts. Shared code has exactly one owner module: an existing module that naturally owns it (the video player belongs in `mod-player`, `mod-feed` depends on it), or, when none fits, a new module named for what it is (`mod-header`, `mod-ui-kit` — never `mod-shared`), placed earlier in the Phase Plan. Tech Lead names the owner and its proposed Source Path; PM adds a new module through a PRD change. If modules already built hold copies of the code, moving it is not part of that PRD change (PM only moves the ACs about that code to the owner): after Doc-Sync creates the owner, the human runs `tech-lead "log migration rows for <owner>"` and Tech Lead logs one `integration-review.md` row per module that must delete its copy and use the owner, so each goes through the normal fix → QA → human → confirm loop. Merging modules is a separate, explicitly higher-impact recommendation
- **Conventions**: proposed as `Proposed Convention:` lines in Tech Lead Reviews. They reach `production.md` only one way: the user approves → PM adds them to PRD section 9 Adopted Conventions → Doc-Sync copies them into Shared Conventions
- **Input**: `prd.md` + `production.md` (if it exists) + `status.md` + `integration-review.md` + pstack findings + for blocker/repeat-failure reviews, the relevant `modules/<mod>/status.md` and `spec.md`
- **Output**: Findings in `status.md` Tech Lead Reviews (Concerns, Recommendations, Approved, Proposed Shared Conventions) + infrastructure files at init + `integration-review.md` rows at phase end
- **Handoff**: always returns to the human (see the hook's per-mode messages under Hooks)
- **Constraints**:
  - Never reads, greps, or uses the contents of `.env` — existence and gitignore checks only
  - Advisory only — never writes to `prd.md`, `production.md`, or `modules/*/spec.md`; never implements anything
  - Every module in the phase must be read before an integration review is complete — no sampling
  - Never closes an `integration-review.md` item without `HUMAN VERIFIED`, and records that only from the human's own statement in the session (`SPLIT` is not a close — each split row is closed this way)
  - A fix or optimization that changes user-facing behavior is a PRD change → PM, not an integration-review item
  - On a repeat-failure review: requires real evidence of which layer caused the bug, never a guessed diagnosis; asks the human for a specific check if the evidence does not exist yet. Stays the owner of that AC until QA flips the marker to resolved
  - Appends to Skill Recommendations; never edits other agents' entries
  - Commits before stopping: `git commit -m "tech-lead(<mode>): <summary>"` (init review and any review that changed setup files also stage `setup.md`, `.gitignore`, and the backend infrastructure files — `.env.example` and `docker-compose.yml` with one `git add` per file that exists)

### Engineer

- **File**: `.claude/agent-templates/engineer.md` (base template, model: sonnet) → generated `.claude/agents/engineer-<dir>.md` per module. Always run the wrapper, never the base template
- **Single Responsibility**: Implement one assigned module
- **Tools**: Read, Write, Edit, Bash, Grep, Glob, Skill (allowlist: `coding-conventions`, `engineer-checklist`, `pstack:tdd`, `pstack:deslop`, `pstack:typescript-best-practices`, plus the project's own `.claude/skills/<name>/` skills). These serve the spec and never widen it
- **Write Scope**: source code within the module's **Source Path** (its Module Map row) + the project files (manifests, lockfiles, `.env.example`, CI config on the Module Map `Project files:` line) if this module is their owner + its own planning files: `modules/<dir>/status.md` (Engineering Progress — never its `spec.md`), project-level `status.md` (Last Action and Skill Recommendations), and `integration-review.md` (`Status`/`Notes` on rows assigned to this module, `IN PROGRESS`/`FIXED – AWAITING QA` only). A Source Path may be a folder, a file, or a filename pattern (`supabase/migrations/*_mod_003_*`); when paths overlap, the most specific match (longest literal part) owns the file. The rules live in one shared helper, `engineer-checklist/scripts/module_scope.py`, and are enforced three times: `pstack-guard.sh` blocks Write/Edit calls outside it at the tool level (and blocks every write but `project-planning/status.md` — its Last Action, so the hook can route it to PM — when the module has no Module Map row); `self-check.sh` fails on any change outside the scope (`module_scope.py changed`); and `handoff.sh` runs that same `changed` check itself whenever an `engineer-*` agent stops, overriding the Engineer's result with a "Scope violation … Fix first: `engineer-mod-<name> "scope-fix"`" message on any out-of-scope file (and with a `pm "change: add <dir> to the Module Map"` message when the module has no Module Map row) — this catches shell writes the guard cannot see, and does not trust the Engineer's own self-check. Changes are attributed by a recorded base, not by commit messages: `handoff.sh` appends `<sha> <epoch> <agent>` to `<git-dir>/framework-handoff-log` at every Stop where HEAD moved, and the check compares the working tree with the latest entry written by anyone other than this Engineer. Only files changed solely by `human:` or `coordinator(` commits after the base are left out. With no git repository, or a Module Map with no Source Path column, the hook skips the check and says so in a `note:` line
- **Skills Used**: coding-conventions, engineer-checklist
- **Invocation**: `claude --agent engineer-mod-<name> "<word>"` — the mode comes from the first word, which the hook always prints: `"implement"`, `"bugfix"` (including `"bugfix — follow Tech Lead's repeat-failure diagnosis for AC-NNN"`), `"integration-fix <INT-ID>"`, `"spec-update"` (Doc-Sync changed the spec after the module was built: read the latest Sync Report and the spec's changed ACs, update the code to match, and say in Engineering Progress which ACs changed), or `"scope-fix"` (the handoff listed files changed outside the Source Path: undo exactly those changes and nothing else, rerun self-check, and set `next:` back to the QA step for the work that was interrupted — `verify` after implement, `regression` after a bugfix, `integration-fix-verify <INT-ID>` after an integration fix; the hook decides the actual return route itself, see Handoff). With no word, Engineer decides from the module's history (an `APPROVED` integration-review row assigned to it → integration-fix; QA failures newer than its last entry → bugfix; otherwise implement) and says which it chose in Engineering Progress
- **Modes** (Last Action `mode`, the bare word only — an INT-ID goes in Engineering Progress): `implement`, `bugfix`, `integration-fix`, `spec-update`, `scope-fix`
- **Input**: `production.md` + its own `modules/<dir>/spec.md` + its own `modules/<dir>/status.md` (on a bugfix, also its `### Open items` list — every open `bugs-found` item there is fixed too, unless it carries an open Tech Lead escalation marker) + dependency modules' `status.md` (read-only) + Tech Lead's diagnosis when fixing an AC under an open escalation marker + the assigned `integration-review.md` row for an integration fix
- **Output**: Working code + self-check results in `modules/<dir>/status.md` Engineering Progress
- **Self-Check Process**: Step 0 on the project's first module only — infrastructure pre-flight (`.env` presence if `setup.md` requires it, every service `setup.md` lists is reachable; on failure `result: needs-human`). Then `self-check.sh` (build, lint, tests, write-scope check), the project's integration-test command if `production.md` or `setup.md` names one, and the judgment items. The checklist is stack-neutral: universal items always apply; items under "Only if your stack matches" (Jest + real DB teardown, LLM model IDs and prompt budgets, Spring Boot actuator/CORS/`@Order`, container architecture, React Native safe areas) apply only when the module uses that stack, and Engineer says which it skipped
- **Results** (Last Action `result`): `success`, `blocked-dependency` (a module this one depends on has not passed QA), `blocked-technical` (cross-module design problem or a library not in `production.md`), `spec-issue` (the spec itself is the problem — two requirements contradict, an AC cannot be met as written, or something the module needs is missing; the exact issue goes in Engineering Progress and Engineer stops without guessing or building around it; partial work is committed as `engineer-<dir>(wip): <what is done>`, with Engineering Progress listing what is finished and what waits on the spec — nothing is stashed or discarded — and after the spec is fixed the Engineer is started with `implement` again and continues from that commit), `needs-human`
- **Handoff**: `success` → `qa-mod-<name> "verify"` (implement, and spec-update — checking the ACs Doc-Sync changed and re-running the rest for regressions), `"regression"` (bugfix), or `"integration-fix-verify <INT-ID>"` (integration-fix); when a bugfix succeeds on a module other modules depend on (their spec's `## Dependencies` names its MOD-ID), the hook puts a coordinator `/pstack:blast-radius` step on the fix's diff first (integration fixes get theirs before the fix, via record-decisions' `blast-radius first` note). `scope-fix` success → the hook decides the return route itself, ignoring the Engineer's `next:`: at every non-scope-fix Engineer stop it remembers the mode and result in `<git-dir>/framework-engineer-<dir>`, and on a clean scope-fix it routes by them — an interrupted `spec-issue` → `pm "change: spec issue from engineer-mod-<name>"`, `blocked-technical` → `tech-lead "engineer blocker in mod-<name>"`, `blocked-dependency` → finish the dependency first, `needs-human` → the human, otherwise by mode: bugfix → `"regression"` (plus the blast-radius step when other modules depend on this one), integration-fix → `"integration-fix-verify INT-ID"`, spec-update or implement → `"verify"`. The hook re-checks scope on that stop, and no extra regression run is added. `blocked-dependency` → finish the dependency first (`pm "change"` if the phase order is wrong). `blocked-technical` → `tech-lead "engineer blocker in mod-<name>"`. `spec-issue` → `pm "change: spec issue from engineer-mod-<name>"`. A scope violation found by the hook overrides all of these with `engineer-mod-<name> "scope-fix"`; a module with no Module Map row overrides them with `pm "change: add mod-<name> to the Module Map"`
- **Constraints**:
  - Reads only `production.md` and its assigned spec — no `prd.md`, no other module's spec. Any cross-module mounting condition it needs is already named in its spec's Integration Points
  - Scope = Requirements + Acceptance Criteria. The spec's Context explains *why* and never widens scope; behavior a user story implies but no AC covers is logged as a scope question for PM
  - If blocked by something outside its Source Path, writes the blocker to Engineering Progress and stops — never improvises or works across the boundary
  - If the spec cannot be built as written, records `spec-issue` and stops — PM fixes it at the source
  - No dependencies outside the `production.md` tech stack
  - Under an open repeat-failure escalation marker, implements per Tech Lead's diagnosis; without the diagnosis in hand, stops and asks the human for it
  - On an integration-review fix, touches only its own row and only moves it to `IN PROGRESS` / `FIXED – AWAITING QA`
  - Commits before stopping: `git commit -m "engineer-mod-<name>(<implement|bugfix|integration-fix|spec-update|scope-fix|wip>): <summary>"` — every commit, code commits included, carries the agent-role prefix (no plain `feat(x):`) so the history reads clearly. `module_scope.py changed` (run by `self-check.sh` and `handoff.sh`) does not attribute by prefix: its base is the latest `framework-handoff-log` entry written by anyone other than this Engineer, and everything changed since then counts as this Engineer's (falling back to the last commit not prefixed `engineer-<dir>` when there is no log yet)

### QA

- **File**: `.claude/agent-templates/qa.md` (base template, model: sonnet) → generated `.claude/agents/qa-<dir>.md` per module. Always run the wrapper
- **Single Responsibility**: Verify one module against its spec
- **Tools**: Read, Write, Bash, Grep, Glob, Skill (allowlist: `qa-checklist`, the project's `verify` skill, and any other project `.claude/skills/<name>/` skill)
- **Write Scope**: `modules/<dir>/status.md` QA Results (plus flipping an existing Tech Lead escalation marker to `— resolved <date>` when its own verification of that AC passes) + project-level `status.md` (Last Action and Skill Recommendations) + `integration-review.md` (`QA VERIFIED`, or back to `APPROVED` with a note, on rows assigned to this module). Never edits source code
- **Skills Used**: qa-checklist; `verify` (if `.claude/skills/verify/SKILL.md` exists) to check each AC in the running app, citing its evidence
- **Invocation**: `claude --agent qa-mod-<name> "<word>"` — the workflow comes from the invocation word:
  - `verify` → `qa-checklist/workflows/functional-test.md`
  - `regression` → `qa-checklist/workflows/regression-test.md`
  - `integration-fix-verify <INT-ID>` → `regression-test.md` against that `integration-review.md` row
  - `ui-results: <what the human observed>` → QA stopped earlier with `result: needs-signoff` and a test script; it records the human's reported outcome per AC exactly as stated ("AC-023: PASS — reported by the human <date>"), classifies any failures, routes as usual, and keeps the `mode` it recorded when it stopped
  - No word: QA decides from the module's history and says why in the first line of QA Results. The workflow is recorded as Last Action `mode`, as the bare word (`verify`, `regression`, `integration-fix-verify` — the INT-ID goes in QA Results)
- **Input**: `production.md` + its own `spec.md` + the code + its own `modules/<dir>/status.md`
- **Output**: Per-AC pass/fail with reproducible failure descriptions in `modules/<dir>/status.md`
- **Testing Process**: `run-qa.sh` (which fails when no test command is configured), then the judgment items. Server-side modules need a real running server — real endpoint calls and stored state, not just unit tests. UI modules need the `verify` skill, or a written test script handed to the human for sign-off with `result: needs-signoff` (the human answers with `"ui-results: …"`); QA never declares PASS on an AC nobody exercised in the running UI. Setup drift (`setup.md` ports or variables out of step with `docker-compose.yml` / `.env.example`) is a FAIL routed to Tech Lead, who owns `setup.md`; a variable missing from `.env.example` goes to the project files owner's Engineer. When the module's spec lists Dependencies, QA also runs `integration-review/scripts/scan-integration.sh` after its checks pass and copies any hit involving this module into QA Results under `### Integration notes (for Tech Lead)` — leads, not failures, which Tech Lead's phase-end review reads
- **Results** (Last Action `result`): `success`, `bugs-found`, `spec-issue`, `setup-drift` (setup.md out of step with the infrastructure → Tech Lead), `repeat-failure` (with `ac:` in Last Action listing every AC routed to Tech Lead in this run, comma-separated, so the hook checks each AC's escalation marker), `needs-signoff` (stopped for the human to run a UI test script), `needs-human` (blocked on anything else the human must do, e.g. the server will not start). One run records one result; when ACs fail for different reasons the precedence is **`spec-issue` > `setup-drift` > `repeat-failure` > `bugs-found`**, every failure is still listed, and every failure not routed this run goes in the module status file under `### Open items` inside `## QA Results` — exactly one such section, kept at the end of QA Results and updated in place — one line each (`- [ ] AC-012 bugs-found — <one-line description> (<date>)`). In every later run QA ticks the items its checks now pass (`- [x] … — passed <date>`) and keeps the rest; the hook lists the open items of every module in every handoff, whichever agent ran, until they are ticked
- **Handoff**:
  - Pass, more modules remain in the phase → `engineer-mod-<next-module> "implement"`
  - Pass, last module of the phase → coordinator runs `/pstack:thermos` → Tech Lead (integration review). Never straight to PM
  - Bugs (1st/2nd failure of this AC) → Engineer
  - 3rd failure, a 2nd failure whose observed output (`Actual=`, error message, or screenshot evidence) is identical to the 1st — the fix changed nothing visible — or an escalation marker already open → Tech Lead (repeat-failure review, `tech-lead "repeat-failure review AC-<ID>"`); on the first escalation QA's message names the coordinator's `/pstack:how` + `/pstack:why` step first. After a marker is flipped to resolved, the count starts fresh from that point
  - Spec issue → `pm "change: spec issue from qa-mod-<name>"`
  - Integration fix verified → the human verifies it (a coordinator stopping point), then Tech Lead gets `"<INT-ID> verified: <what you checked>"` in the human's words; fix does not hold → `engineer-mod-<name> "integration-fix <INT-ID>"`
  - Needs human sign-off → the coordinator shows the test script and waits; the human runs it and replies, then QA runs again with `qa-mod-<name> "ui-results: <the human's exact words>"`
- **Constraints**:
  - Verifies against the spec, not assumptions; every failure has input, expected, and actual
  - Spec problems go to PM, never to Engineer
  - Checks for an open escalation marker and counts prior failures of the AC before every bug-routing decision; never creates the marker
  - `QA VERIFIED` is not closed — the human and then Tech Lead still have to confirm
  - Commits before stopping: `git commit -m "qa-<dir>: <pass|fail|needs-signoff|needs-human> — <summary>"`

### Retrospective

- **File**: `.claude/agents/retrospective.md` (model: opus)
- **Single Responsibility**: Propose system improvements from project learnings
- **Tools**: Read, Write, Grep, Glob, Bash (no `Skill` — empty allowlist)
- **Write Scope**: `project-planning/retrospective/` only (`proposed-changes.md` and `drafts/<name>.proposal.md`)
- **Skills Used**: none
- **Invocation**: **manual only** — it runs only when the human asks for it: the human runs `claude --agent retrospective` directly, or says yes to the coordinator's Retrospective offer (an optional step); its description tells Claude never to invoke it automatically. It writes no Last Action block, and `handoff.sh` has no Retrospective branch, so no hook message follows it
- **Two scopes**: `phase <N>` — offered by PM at every checkpoint ("Run a short Retrospective on phase N now?", asked before the checkpoint is written, committed, and tagged), reads only that phase's entries and `git log checkpoint-<N-1>..checkpoint-<N>`, writes `phase-<N>-*.proposal.md` drafts; whole project — after the final checkpoint, skipping evidence earlier phase drafts already cover. A declined offer is noted under that phase's Checkpoint History line as `retrospective: skipped`. The hook adds the optional `claude --agent retrospective "phase <N>"` command to every successful checkpoint message — `<N>` is the real phase number, taken from the last `Phase N approved` line in Checkpoint History (bulleted lines count too) — unless a line after that one says `retrospective: skipped` (a skip under an earlier phase does not count).
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
  - **Post-sync update**: re-read full PRD, smallest change, next available IDs, ask the user trivial vs substantive and tag accordingly (plus `[ARCHITECTURAL]` when the user says the change alters how the system is built), writing the entry as `- YYYY-MM-DD [TAG] [ARCHITECTURAL] <one-line summary>` with tags only on that first line and details indented below, increment the revision, re-run the full quality checklist; a new module gets a directory, Source Path, and Module Map row before Doc-Sync runs
- Quick start: `pstack:sharpen` and a two-or-three-sentence restatement of the goal come first (step 0 of drafting); finalization covers Build Config, the Module Map (directories + non-overlapping Source Paths — folders, files, or filename patterns such as `supabase/migrations/*_mod_003_*` when one folder holds several modules' files — shared code owned by exactly one module, one project files owner), and the setup gate (Setup Confirmation present, no newer Setup Changed)

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
- **Run mode**: the coordinator runs the framework agents for the human as subagents in one conversation; the human can also run any agent directly as its own session (`claude --agent <name> "<word>"`), under the same rules. Every command in the template and the hook's messages carries the agent's start word (e.g. `claude --agent engineer-mod-login "bugfix"`); in one-conversation mode it means "start that agent as a subagent with the quoted word as the first line of its instructions"
- **Running the flow in one conversation**: the loop (start the agent as a subagent → read the Last Action `next:` line → run any required pstack step → start the next agent), the stopping points (PM every time it changes something, in a proposal pass and an apply pass carrying `Approved by <name>: "<exact words>"`; integration-review decisions and the human's own verification of a fix; QA `needs-signoff`, answered with `ui-results: <the human's exact words>`; setup steps; any `needs-human`; scope violations the agent can't resolve; optional steps such as the verify skill and the Retrospective offer, run only on a yes), the relay rules (verbatim in both directions, never answer for the human or fill a gap with the coordinator's judgment, never drop or soften an agent's condition, quote the human as `<name>: "<exact words>"`), and new agents (if a subagent type generated by Doc-Sync is unknown, the human runs `claude --continue` to reopen the same conversation with it loaded)
- Contains the ownership table (which agent owns which artifact and how to invoke it — source code by the module whose Source Path contains it; a `CLAUDE.md` row: the coordinator edits it only on explicit human instruction, PM's init commits the scaffolded version, project notes go below the Coordinator Instructions section, and that section changes only when the framework template does), the hard no-direct-edit rule, the "every PM tag goes through Doc-Sync" rule, the **Commit prefixes** rule (every agent commit starts with its agent-role prefix; the coordinator's own commits — applying a Retrospective proposal, editing `CLAUDE.md` — start `coordinator(<what>): …`, pstack output `pstack(<skill>): …`, and the human's manual commits `human: …`; the scope check records its own base at every handoff, so prefixes don't decide what an Engineer is blamed for, but files changed only by `coordinator(` or `human:` commits are left out of the next Engineer's check), and forbidden/correct examples
- **Required pstack steps**: the trigger table for the coordinator-run pstack steps (`how` for a PM change tagged `[ARCHITECTURAL]`, `thermos`, `blast-radius` after a bugfix to a module other modules depend on (the hook names them from each spec's `## Dependencies` section, matched to MOD-IDs through the Module Map) and before an approved integration fix noted "blast-radius first", `how` + `why`, `create-verification-skill` in the first phase the app runs unless the human declines — a "no" goes to PM's Decisions as "verify skill: declined" — and `maintain-verification-skill` at each PM checkpoint once the verify skill exists), findings saved and committed to `project-planning/pstack-findings/` (and the verify skill committed as `pstack(create-verification-skill)`, since uncommitted output shows up in every self-check and handoff warning), a blast-radius report that changes the plan going back through `tech-lead "on-demand review of <INT-ID> blast-radius"`, the "deliver findings, never fix" rule with a `git status` check after each step, and the list of file-changing pstack skills the coordinator never runs on owned artifacts
- Scaffolded to `<project-root>/CLAUDE.md` by `init-project.sh` — auto-loaded into every default session opened at that root
- If a `CLAUDE.md` already exists at project root, `init-project.sh` does not overwrite it — it prints a note telling the human to merge the Coordinator Instructions section manually

#### templates/global-CLAUDE.tmpl.md
- Source for `~/.claude/CLAUDE.md`: a safety-net version of the coordinator rule for when a project has no ownership-aware `CLAUDE.md`, including the one-conversation rule in short (the coordinator runs the agents as subagents, or the human runs one directly; relay every question and answer word for word, never decide for the human, run PM as a proposal pass then an apply pass with the human's quoted approval). Applies whenever `project-planning/status.md` exists. Not copied by any script — deployed by hand

#### scripts/init-project.sh
- Creates the `project-planning/` folder structure:
  - `project-planning/prd.md` (copied from template)
  - `project-planning/status.md` (from status template — includes Last Action, Current Phase, Phase Plan, Build Config, PM Updates, Tech Lead Reviews, Sync Reports, Decisions, Module Map (with a Source Path column, a comment saying a Source Path may be a folder, a file, or a filename pattern such as `supabase/migrations/*_mod_003_*` and that no two Source Paths may overlap or nest — and that if they do anyway, the scope check treats the longest matching path as the owner — and a commented `Project files: <dir> | <paths>` example line), Checkpoint History, and Skill Recommendations sections — all empty at scaffold time; Last Action has `agent`/`mode`/`module`/`result`/`timestamp` keys and no commit field. Engineering Progress and QA Results are module-level and are NOT in this file)
  - `project-planning/modules/` (empty directory)
  - `project-planning/retrospective/` and `retrospective/drafts/` (empty directories)
  - `project-planning/pstack-findings/` is not scaffolded — the coordinator creates it with the first findings file
- Also copies `templates/CLAUDE.tmpl.md` to `<project-root>/CLAUDE.md` (skipped, with a warning, if one already exists)
- Runs `git init` when the project root is not yet a git repository — every agent commits its work, so the project must be one
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
  1. Find the last Sync Report and its `PM Update reference` (the last PM Updates entry it synced), then read **every** PM Updates entry after that one, by position in the section rather than by date (same-day entries are common), in the order they appear (PM may log several changes before Doc-Sync runs)
  2. Read current `prd.md`
  3. Identify which downstream files are affected — including Adopted Conventions changes (→ Shared Conventions), a `[TRIVIAL] Build Config changed` entry in the same window (→ re-copy Build Config into Shared Conventions), and PM answers to earlier `[AMBIGUITY]`/`[CONFLICT]`/`[BLOCKER]` markers (→ each file holding a listed marker)
  4. For each affected file: read current version, apply only the delta, preserve unaffected sections; replace a resolved marker with the PRD's new text verbatim
  5. If change adds a new module: create new spec from template; create `modules/<dir>/status.md` (empty template); generate `engineer-<dir>.md` and `qa-<dir>.md` exactly as initial sync does; tell the human that if the new agents (including regenerated ones from 5a) can't be called yet, `claude --continue` reloads them in the same conversation. If the PRD change says the new module takes over code other modules already hold, the handoff ends with `claude --agent tech-lead "log migration rows for <owner dir>"`. The same applies to a module skipped at an earlier sync with a `[BLOCKER]` that PM has since fixed: its spec, status file, and agents are written now and the BLOCKER is listed as resolved
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
  - Commit messages: every agent commit, code commits included, starts with the agent-role prefix (`engineer-<dir>(<mode>): …`, `qa-<dir>: …`, `pm(<mode>): …`); no plain `feat(x):` commits from agents. Engineers keep the exact `engineer-<dir>(<mode>):` prefix so the history reads clearly; the scope check itself uses the handoff hook's recorded base, not commit messages. The human prefixes manual commits `human: …`.
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
- Commit message examples (Engineer examples use the agent-role prefix, e.g. `engineer-mod-auth(bugfix): …`)

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
  - No files changed outside the module's write scope (Source Path, project files if it owns them, its own planning files) — the working tree (committed, uncommitted, and untracked) compared with the module's base recorded by `handoff.sh`
- Quick start commit: `engineer-<dir>(<implement|bugfix|integration-fix|spec-update|scope-fix|wip>): <summary>`
- Judgment-based items (verified manually by Engineer), stack-neutral:
  - **Always**: every spec requirement implemented; Integration Points wiring implemented and conditional-mounting conditions verified within the engineer's own module only; integration tests mount the real production configuration for any AC with a UI entry point; framework-hook mocks reflect the real production ancestor; layer-diagnosis gate before fixing a runtime bug (otherwise a blocker listing hypotheses); one-line impact note before a fix; mock fidelity for option-gated API fields; untyped/unmockable query DSLs exercised against a real backend and recorded; edge cases; no hardcoded config; conventions followed; no dependencies outside the tech stack; readable code; another module's schema read from its migration/contract, never inferred from names; no TRACE/DEBUG framework logging in committed config
  - **Only if your stack matches** (skip the rest and say so in Engineering Progress): Jest + real DB teardown in `beforeEach`; LLM model IDs read from env, and prompt token budgets (`references/llm-prompt-context-budget.md`); Spring Boot actuator dependency, health-endpoint `permitAll`, `setAllowedOriginPatterns`, and `@Order` on `@RestControllerAdvice`; pinned container image architecture; React Native / Expo safe-area insets
- Output: log all results (automated + integration + manual) to `modules/<dir>/status.md` Engineering Progress section with pass/fail per item
- Living document: updated via Retrospective agent proposals after each completed work cycle

#### references/llm-prompt-context-budget.md
- Design decisions an Engineer resolves before building a feature that concatenates user-supplied text into an LLM prompt: token budget, truncation strategy, and how the limit is enforced

#### scripts/self-check.sh
- Automated pre-QA verification script:
  - Reads `production.md` to find build command, lint command, test command. A missing `production.md` is a **FAIL** (build, lint, and tests cannot run — Doc-Sync creates it at the initial sync)
  - Runs build → reports pass/fail
  - Runs linter → reports pass/fail
  - Runs existing tests → reports pass/fail. No test command in `production.md` is a **FAIL** (add `Test:` to Build Config via PM; if the project truly has no tests, the human must say so)
  - Checks the module's write scope by calling `module_scope.py changed <project-root> <module-dir>` — the same check `handoff.sh` runs when the Engineer stops. It runs at the start of the script, **before** build and test, so their output (caches, bytecode, coverage) is never mistaken for the engineer's work; the result is reported in the git-scope section. Passes when every change is in scope (printing any `note:` lines under the pass), fails listing each out-of-scope file with its reason, fails separately when the module has no Module Map row ("PM must add it before you build"), and skips when the Module Map has no Source Path column or the project is not a git repository
- Framework-agnostic: reads commands from `production.md` rather than hardcoding `npm` or `pip`
- Takes module name and project root as arguments
- Outputs structured report to stdout
- Exit code 0 = all automated checks pass

#### scripts/module_scope.py
- The Module Map scope rules, shared by `self-check.sh` and the `pstack-guard.sh` and `handoff.sh` hooks so they never disagree
- Parses the `status.md` Module Map table (HTML comments skipped) and the `Project files: <dir> | <paths>` line (also when it is bold or bulleted). Cells are cleaned of backticks and `**bold**` markers only — a single `*` stays, since filename patterns use it
- `module_scope.py check <status.md> <module-dir> <path>`: exit 0 in scope, 1 outside it (reason on stdout — e.g. which module owns the path), 2 the module has no Module Map row, 3 the Module Map has no Source Path column (older project; the caller decides). Paths are normalized first (`./`, `../`), and a `project-planning/modules/*/spec.md` path is blocked (exit 1) even when the Module Map has no Source Path column
- `module_scope.py paths <status.md> <module-dir>`: prints the module's Source Paths, plus the project files if it owns them
- `module_scope.py changed <project-root> <module-dir>`: compares the working tree (committed, uncommitted, and untracked) with the module's **base** and prints each changed file outside the scope with the reason. The base comes from the **base log** `handoff.sh` keeps in `<git-dir>/framework-handoff-log` — one `<sha> <epoch> <agent>` line appended at every Stop where HEAD moved, `<agent>` being the stopping session's `agent_type` or `coordinator` — and is the latest entry written by anyone other than `engineer-<dir>`. Without a log (older setups) it falls back to the last commit whose message does not start with `engineer-<dir>` (and to the empty tree when there is none). Commit messages therefore no longer decide attribution, with one exception: files changed in `base..HEAD` only by `human: …` or `coordinator(…)` commits are not counted. Diffs use `--relative`, so a project inside a larger git repository works. Renames count as a delete plus an add, and `git` output is read with `-z` everywhere, so file names with spaces are handled. An untracked file that is in no module's path, or older than the base (modified before it), is printed as a `note:` line (it was not created in this Engineer's session) and does not fail the check. Exit 0 all in scope, 1 not, 2 the module has no Module Map row, 3 no Source Path column. Shell writes are caught here, not by the guard
- `module_scope.py dependents <project-root> <module-dir>`: prints the modules whose `spec.md` `## Dependencies` section (HTML comments stripped) names this module's MOD-ID from the Module Map — `handoff.sh` uses it for the blast-radius step
- Write scope = Source Paths + owned project files + `modules/<dir>/` (except `spec.md`, which is always blocked) + `project-planning/status.md` + `project-planning/integration-review.md`. A Source Path is a file or folder (`src/login/`, matching itself and everything below it) or a filename pattern matched with `fnmatch` (`supabase/migrations/*_mod_003_*`). When paths overlap, the most specific match — the longest literal part before the first wildcard — owns the file, so a nested path still has a single owner

### qa-checklist

- **Location**: `.claude/skills/qa-checklist/`
- **Used By**: QA
- **Purpose**: Verification items for testing a module

#### SKILL.md (checklist + routing)
- Essential principles: verify against the spec (not against assumptions), test observable behavior, every failure needs a specific reproducible description, spec ambiguity escalates to PM, never edit source code, server-side modules require a real running server (start it with the `setup.md` run command, or the `verify` skill), UI modules require the `verify` skill or a human sign-off (`result: needs-signoff`)
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
  5b. **UI modules**: run each AC through the `verify` skill if it can drive the UI; otherwise write a test script per AC (steps, expected result, failure condition) ending with "Human sign-off required", record `result: needs-signoff`, and stop until the user reports results
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
- **Repeat-failure check, built into the workflow, before routing a failed fix to Engineer**: an `AC-NNN: ESCALATED TO TECH LEAD — open` line for this AC routes to Tech Lead (`result: repeat-failure`, `ac: AC-NNN`) — no re-count after the first escalation; with no marker, the 3rd failure of the AC across QA Results routes to Tech Lead the same way, and so does a 2nd failure whose observed output is identical to the 1st (the fix changed nothing visible); otherwise back to Engineer (`result: bugs-found`). A verification that passes on an AC with an open marker flips it to resolved.

#### scripts/run-qa.sh
- Automated test runner and report generator:
  - Reads `production.md` to find the `Test:` command (Doc-Sync copies it from `status.md` Build Config); Markdown bold (`**Test:**`) and a leading list marker are stripped, a command wrapped in quotes is unquoted (a wrapped `"…\"…\"…"` command has its inner `\"` unescaped), and the rest of the line is kept as written
  - **Fails** (not warns) when `production.md` is missing or has no test command — if the project truly has no tests, the human must say so and QA records it in QA Results
  - Runs the test suite
  - Parses test output for pass/fail counts, taking the number right next to `passing`/`failing` or `passed`/`failed` (not the first number on the line)
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
- Step-by-step for the first review of a phase: read every module in the phase in full, read every `### Integration notes (for Tech Lead)` block QA wrote in this phase's module status files (treated as leads, like the scan), run `scripts/scan-integration.sh`, apply both reference checklists, create `integration-review.md` from template if missing, carry forward every row still `DEFERRED` from an earlier phase (listed again for the human to decide; its status is left for `record-decisions` to change), log one `PROPOSED` row per finding with Assigned Module left blank (or, only when there is no finding and no carried-forward `DEFERRED` row, a single `NO ISSUES` row, "No issues found — phase <N> reviewed <date>"), write a summary pointer to `status.md` Tech Lead Reviews, record Last Action `mode: integration-review` with `result: clean` only in that no-finding case — any finding or carried-forward row means `result: issues-found` — commit
- Tells the human that every row — Concerns, Recommendations, and carried-forward `DEFERRED` rows — needs an approve, reject, or defer before PM's checkpoint, given as `claude --agent tech-lead "decisions: INT-001 approve, INT-002 reject, ..."`
- **Scope split**: conflict/leak checks (`cross-module-checklist.md`) are scoped to the current phase's modules only — new interactions only exist between modules new to each other. The duplication check (`optimization-criteria.md`) is explicitly NOT phase-scoped — it compares lightweight Purpose/Tech Stack summaries across every module shipped so far, deep-reading only modules flagged as suspiciously similar, since duplication has no phase boundary

#### workflows/record-decisions.md
- Step-by-step for recording the human's decisions (e.g. "INT-001 approve, INT-002 reject, INT-003 defer"): set each named item — including `DEFERRED` rows from earlier phases the human decides again — to exactly `APPROVED`, `REJECTED`, `DEFERRED`, or (at the final checkpoint only, for a deferred row the human accepts as a known issue, which PM lists in the README) `ACCEPTED (KNOWN ISSUE)`, with the reason and date; ask when the wording is ambiguous; for every `APPROVED` item fill **Assigned Module** — the module whose Source Path contains the code the fix changes — confirmed with the human. A fix spanning modules splits into one row per owner, named with a letter suffix (`INT-003` → `INT-003a`, `INT-003b`), and the original is set to `SPLIT` with "split into INT-003a/b" (`SPLIT` counts as closed for the checkpoint gate; the split rows carry the work); add `blast-radius first` to Notes when the fix changes code another module depends on (if the blast-radius report changes the plan, the human runs Tech Lead again with it as an `on-demand-review`); leave unmentioned items `PROPOSED`; Last Action `mode: record-decisions`, `result: success`; commit
- Tells the human, per approved item: `claude --agent engineer-mod-<assigned> "integration-fix <ID>"` (after the coordinator's blast-radius step where noted), or PM checkpoint when nothing is approved or still `PROPOSED`

#### workflows/confirm-fix.md
- Step-by-step for closing out an item: if it is `QA VERIFIED` and the human states in the session that they verified it, record `HUMAN VERIFIED` with the date and the human's own words (ask — never infer); anything earlier than `QA VERIFIED` stops with what it is waiting for; re-check the original failure scenario against current code; set `CONFIRMED CLOSED` if resolved, or bounce back to `APPROVED` with a note if not; Last Action `mode: confirm-fix`, `result: success`; commit

#### templates/integration-review.tmpl.md
- Structure for `project-planning/integration-review.md`: status legend, and a findings table (ID, Phase, Category, Description, Location, Tech Lead Rationale & Trade-offs, Status, Assigned Module, Notes). The commented example row is `INT-000`, outside the real ID sequence (findings start at `INT-001`), and is written `e.g. INT-000 | …` so it never starts with `| INT` and is not mistaken for a real row
- Status lifecycle: `PROPOSED` → `APPROVED` / `REJECTED` / `DEFERRED` → `IN PROGRESS` → `FIXED – AWAITING QA` → `QA VERIFIED` → `HUMAN VERIFIED` → `CONFIRMED CLOSED` (an approved row split by owner becomes `SPLIT`, replaced by its letter-suffixed rows)
- Ownership split by status, same pattern as `modules/*/status.md`: Tech Lead owns `PROPOSED`/`NO ISSUES`/`SPLIT`/`CONFIRMED CLOSED`, plus `ACCEPTED (KNOWN ISSUE)` when the human accepts a `DEFERRED` row as a known issue at the final checkpoint, and records the human's `APPROVED`/`REJECTED`/`DEFERRED` decisions (plus Assigned Module) and the human's `HUMAN VERIFIED` exactly as the human states them; Engineer owns `IN PROGRESS`/`FIXED – AWAITING QA` on rows assigned to it; QA owns `QA VERIFIED` (or sends back to `APPROVED`)
- PM's checkpoint gate: every row in the file — any phase — must be `CONFIRMED CLOSED`, `REJECTED`, `DEFERRED`, `SPLIT`, `ACCEPTED (KNOWN ISSUE)`, or `NO ISSUES`; the final checkpoint does not accept `DEFERRED`. Recommendations are gated like Concerns — each needs an explicit approve, reject, or defer. A `DEFERRED` row stops blocking its own phase but is listed again in every later phase's review until the human approves or rejects it

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
- Run by Tech Lead at phase end, and also by QA after a module whose spec lists Dependencies passes (hits go under `### Integration notes (for Tech Lead)` in QA Results)
- Reads module directories and Source Paths from the rows of the `status.md` Module Map table only — HTML comments and the format example are skipped (all modules ever shipped, not phase-filtered — the Module Map has no phase concept of its own)
- Scans every Source Path in the Module Map (falling back to `src/` when none are recorded), dropping roots nested inside another so no file is counted twice
- Checks: migration filename/prefix collisions across common migration directory names, Integration Points file references that don't resolve to an actual file, duplicate route/endpoint literals (`.get`/`.post`/`.put`/`.patch`/`.delete`/`.route`) — each route counted across all files, with the files holding every duplicate listed — module Purpose lines printed together for duplication eyeballing, duplicate exported component/function names (JS/TS exports and Python `def`/`class`) across the scanned roots (all heuristic greps, tech-stack agnostic)
- Always exits 0, even on an empty result (it runs without `set -e`/`-u`) — never fails the build; this is advisory tooling, not a gate

---

## Hooks

Both hooks are registered under `"hooks"` in `~/.claude/settings.json` (account-level) or a project's `.claude/settings.json`. Claude Code does not load a standalone `hooks.json` outside plugins; the repo ships the entries to merge in `.claude/hooks/settings-hooks.json` (which also carries two optional macOS `osascript` notifications on `Notification` and `Stop`). Both scripts need `jq` and `python3`, must be executable (`chmod +x`), and stay silent outside a dev-team-agent project (one with `project-planning/status.md`).

### handoff.sh

- **Result synonyms**: before routing, the hook normalizes the recorded `result:` (case, `_`, backticks) and maps common slips — `pass`/`passed`/`ok`/`done` → `success`, `fail`/`failed` → `bugs-found`, `need-human` → `needs-human`, and similar — showing the mapping in the message (`pass → read as success`)
- **Location**: `.claude/hooks/handoff.sh` (project source); `~/.claude/hooks/handoff.sh` (account-level copy)
- **Registered Events**: `SubagentStop` (fires when a framework agent run as a subagent in one-conversation mode finishes — the primary path) and `Stop` (fires when a direct `claude --agent X` session, or the coordinator's own session, finishes a turn)
- **Behavior**:
  - Exits immediately when `stop_hook_active` is true (no loops)
  - Finds the project root from subdirectories: resolves `git rev-parse --show-toplevel` from the hook's `cwd`, and outside git (or when that root has no `project-planning/status.md`) walks up the parent directories, so a session that ran `cd src` still finds `project-planning/status.md`
  - Parses the `## Last Action` block in `status.md` (`agent`, `mode`, `result`, `module`, `ac` for repeat failures — one AC or several, comma-separated — `next:`) and, for some messages, `## Current Phase` (its first non-comment line — comments may span several lines), `## Decisions` (for a verify-skill decline, matched loosely: "verify skill" followed by any wording starting "declin"), `## Checkpoint History` (the phase number — from the last `Phase N approved` line, bulleted lines included — and whether a line after that one says `retrospective: skipped`), whether an entry inside `## PM Updates` is tagged `[INIT]` (only that section counts — the Setup Confirmation text mentions `[INIT]` too), whether the first line of the latest PM Updates entry — which starts at the last dated bullet (`- 2026-…` or `- **2026-…`) or `###` heading — carries `[ARCHITECTURAL]` (the tag elsewhere in the entry does not count), and every `### Open items` section in every `modules/*/status.md`
  - **Base log**: at every Stop where HEAD has moved since the last entry, appends `<sha> <epoch> <agent>` to `<git-dir>/framework-handoff-log` (`<agent>` is the stopping session's `agent_type`, or `coordinator` for the main session). `module_scope.py changed` takes an Engineer's base from this log, so the scope check never relies on commit messages
  - **Engineer scope check**: whenever an `engineer-*` agent stops, the hook runs `module_scope.py changed` itself (shell writes never pass through `pstack-guard.sh`, and the Engineer's own self-check result is not trusted for this). Any out-of-scope file replaces every other message with "Scope violation — files changed outside <module>'s Source Path: <files> … Fix first: `claude --agent engineer-mod-X "scope-fix"` — it undoes only those changes; the hook re-checks and then returns you to the step that was interrupted" (if the work belongs to another module, the Engineer records `blocked-technical` instead). A module with no Module Map row (exit 2) replaces it with "`claude --agent pm "change: add mod-X to the Module Map"` before it builds anything". `note:` lines from the check (untracked files in no module's path or older than the base) are shown below the message. In a project that is not a git repository, or whose Module Map has no Source Path column, the check is skipped and a "scope check skipped" `note:` line says so. At every Engineer stop other than a scope-fix, the hook also remembers the mode and result in `<git-dir>/framework-engineer-<dir>`; when a `scope-fix` succeeds with a clean scope, the hook decides the return route from them itself and ignores the Engineer's `next:` (see the Handoff Messages table)
  - **`next:` field**: every agent now records `next:`, and the hook shows that exact command as is, ahead of its own default for the agent; only a scope violation (or missing Module Map row), the hook's own route after a clean `scope-fix`, and the `needs-human` / `needs-signoff` messages take precedence over it, and a Tech Lead `setup-changed` result always shows the redo-setup message instead. The per-mode defaults in the table below are the fallback when `next:` is missing
  - **Coordinator steps added even over `next:`**: a successful PM `change` whose latest PM Updates entry carries `[ARCHITECTURAL]` gets "[ARCHITECTURAL] change — first the coordinator runs `/pstack:how` on the affected code … Then: …", and a QA `repeat-failure` with first-escalation ACs gets "First escalation of <ACs> — first the coordinator runs `/pstack:how` and `/pstack:why` on the failing path … Then: …" — each only when the command does not already mention `pstack:how`
  - **Blast-radius prefix**: when an Engineer `bugfix` succeeds, or a clean `scope-fix` returns to an interrupted bugfix (and no scope violation was found), on a module that other modules depend on — `module_scope.py dependents` finds their `spec.md` `## Dependencies` naming its MOD-ID from the Module Map — the hook prefixes the next step, whoever wrote it, with "<module> is used by <dependents> — first the coordinator runs `/pstack:blast-radius` on this fix's diff (saved to `project-planning/pstack-findings/`). Then: …", unless the command already mentions blast-radius. Integration fixes are not prefixed here: they get blast-radius before the fix, through record-decisions' `blast-radius first` note
  - **Open QA items**: when any module's status file has unticked `- [ ]` lines under `### Open items`, every handoff message — whichever agent ran — ends with "Open QA items still waiting: <module> (<count>) … — listed under "### Open items" in each module's status.md. Once the step above is done: bugs-found items go to that module's Engineer ("bugfix"); repeat-failure and setup-drift items go to Tech Lead"
  - Writes every command as `claude --agent <name> "<word>"`, so it pastes into any shell, with the start word the agent picks its mode from: Engineer `implement` / `bugfix` / `integration-fix INT-ID` / `spec-update` / `scope-fix`; QA `verify` / `regression` / `integration-fix-verify INT-ID` / `ui-results: …`; PM `iterate` / `finalize` / `change` / `checkpoint`; Tech Lead a short phrase (`"initial PRD review"`, `"Setup is complete"`, `"decisions: …"`, `"repeat-failure review AC-NNN"`, …). Values the human must fill in are UPPERCASE placeholder words without angle brackets (`engineer-NEXT_MODULE`, `INT-ID`, `ASSIGNED_MODULE`, `WHAT YOU CHECKED`), so a pasted command never contains shell redirection characters
  - The `Handoff — <agent> (<mode>, <result>)` header always shows the recorded `mode`; a Tech Lead `setup-changed` result changes the route, not the displayed mode
  - **Shows each Last Action once**: it fingerprints the Last Action block into `.git/handoff-last-shown` (or `project-planning/handoff-last-shown` outside git), so the repeated Stop/SubagentStop firings after every turn stay silent until an agent records a new Last Action
  - Builds a per-agent, per-mode, per-result "Next →" message (table below) and returns it as JSON `{"systemMessage": ...}` — plain stdout from a Stop hook goes to the debug log, not the user
  - **One-conversation line**: on `SubagentStop` it adds one line under "Next →" telling the human who acts next — "(The coordinator will ask you before continuing.)" for a `needs-human`, `needs-signoff`, `blocked*`, `setup-changed`, or `issues-found` result, otherwise "(The coordinator runs this next step for you unless it needs your decision.)". A direct-run `Stop` gets no such line
  - Appends a warning listing every uncommitted change in the repo (source code and generated agents included) if the agent did not commit before stopping
  - Names the coordinator's pstack step in the message where one is required (`how`, `thermos`, `how` + `why`, `blast-radius`, `maintain-verification-skill` after a checkpoint when the verify skill exists), adds the optional `claude --agent retrospective "phase <N>"` offer to every successful checkpoint message (with the phase number from the last `Phase N approved` line; skipped when a line after it says `retrospective: skipped`, or when the command already names the retrospective), and — while `.claude/skills/verify/SKILL.md` does not exist and `## Decisions` does not record the verify skill as declined — adds an optional hint to the QA-pass message to have the coordinator run `/pstack:create-verification-skill` once the app runs (or to ask PM to record "verify skill: declined")
  - Unknown agents (and Retrospective, which writes no Last Action) produce no message
  - Never invokes the next agent itself — in one-conversation mode the coordinator starts it (reading `next:` from `status.md`, stopping at every point where the human decides); in a direct run the human runs the command

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

  On top of its list, every framework agent except Doc-Sync may also use the project's own skills — any `<project-root>/.claude/skills/<name>/SKILL.md` (e.g. `verify`, or one added from an approved Retrospective proposal); plugin-qualified (`x:y`) and path-like names never match this rule. Doc-Sync stays excluded because its output must remain a verbatim copy of the PRD. (Tech Lead and Retrospective have no `Skill` tool, so in practice this widens PM, Engineer, and QA.)

- **No writes under `~/.claude`**: every agent, framework or not, is blocked from writing hooks, skills, or agent definitions under `~/.claude`. Framework files change only on the human's explicit instruction, in the coordinator session
- **Module Map is PM's**: a Write/Edit of `project-planning/status.md` by any agent other than `pm` is blocked if it would change the `## Module Map` section (the hook applies the edit to the current file and compares the section before and after), so no agent can widen its own scope
- **Engineer write scope**: an `engineer-*` agent's Write/Edit/MultiEdit/NotebookEdit calls are checked with `engineer-checklist/scripts/module_scope.py` (the same rules `self-check.sh` uses): allowed inside its module's Source Path, the project files it owns, and its own planning files (`project-planning/modules/<dir>/` except `spec.md`, `project-planning/status.md`, `project-planning/integration-review.md`). Anything else in the project is blocked with a message naming the owner and telling it to record a `blocked-technical` blocker. It fails closed: a module with no Module Map row has no write scope until PM adds one — except `project-planning/status.md`, so the Engineer can still record its Last Action and the handoff hook can route it to PM. Paths outside the project are not blocked; an older Module Map with no Source Path column falls back to the prompt rules
- **Read-only reviewers**: any subagent that is not a framework agent (pstack's `general-purpose`, `pstack:effort-*`, `pstack:thermo-*` reviewers) may write in the project only under `project-planning/pstack-findings/` (outside the project, except `~/.claude`, is not blocked). Paths are resolved with `realpath` first, so `../` and symlinks cannot escape
- **Other framework agents** (PM, Doc-Sync, Tech Lead, QA, Retrospective) keep their prompt-defined write scopes apart from the `~/.claude` and Module Map rules; the hook does not otherwise check their file writes
- Needs `python3` (for `realpath`, the Module Map comparison, and `module_scope.py`, which it reads from `~/.claude/skills/engineer-checklist/scripts/`)
- **Not covered**: shell commands and the coordinator's own session — an Engineer's shell writes are caught by `handoff.sh`'s `module_scope.py changed` check when it stops, and the coordinator's `git status` check after each pstack step covers its own session

### Handoff Messages

`handoff.sh` prints `Handoff — <agent> (<mode>, <result>)` followed by `Next → <message>`, then (on `SubagentStop` only) the one-conversation line saying whether the coordinator carries on or asks the human first, then any scope-check `note:` lines, then the `Open QA items still waiting: …` line when any module has unticked open items. The messages below are its actual branches (paraphrased where long), in precedence order for the first four rows:

| Just Finished (agent / mode / result) | Hook Suggests (Next →) |
|---|---|
| engineer-mod-X, any result, `module_scope.py changed` finds an out-of-scope file | Scope violation — files changed outside mod-X's Source Path: <files and reasons>. Fix first: `claude --agent engineer-mod-X "scope-fix"` — it undoes only those changes; the hook re-checks and then returns you to the step that was interrupted (if the work belongs to another module, it records blocked-technical instead) |
| engineer-mod-X, any result, mod-X has no Module Map row | mod-X has no row in the status.md Module Map, so it has no Source Path. `claude --agent pm "change: add mod-X to the Module Map"` before it builds anything |
| any agent, `result: needs-human` | `<agent> is waiting on you` — read its last message (and its `status.md` entry), do what it asks, then run `claude --agent <agent>` and give it your answer |
| qa-mod-X, `result: needs-signoff` | QA needs your sign-off — run its test script (in QA Results), then: `claude --agent qa-mod-X "ui-results: WHICH ACS PASSED, WHICH FAILED AND HOW"` |
| any agent whose Last Action has `next:` (every agent writes it), result not `needs-human`/`needs-signoff`/`setup-changed`, and not a clean Engineer `scope-fix` | the `next:` command exactly as recorded — still prefixed with the `[ARCHITECTURAL]` `/pstack:how` step, the first-escalation `/pstack:how` + `/pstack:why` step, or the blast-radius step, and followed by the checkpoint additions, when those apply and the command does not already name them. The rows below are the fallback when `next:` is missing |
| pm / `init` | `claude --agent tech-lead "initial PRD review"` |
| pm / `iterate` | Review the revised PRD. Architectural changes: `claude --agent tech-lead "pre-sync re-review"`. Otherwise, once you approve: `claude --agent pm "finalize"` |
| pm / `finalize` | `claude --agent doc-sync` — initial sync |
| pm / `change`, latest PM Updates entry tagged `[ARCHITECTURAL]` | [ARCHITECTURAL] change — the coordinator runs `/pstack:how` on the affected code (saved to `project-planning/pstack-findings/`), then `claude --agent tech-lead "change review"`. When PM recorded its own `next:`, the `/pstack:how` step is still put in front of it unless it already names `pstack:how` |
| pm / `change`, not `[ARCHITECTURAL]` | `claude --agent doc-sync` |
| pm / `checkpoint` / `success` | `Now in <Current Phase>. Next: claude --agent engineer-FIRST_MODULE_OF_PHASE "implement"` (see Phase Plan); when `.claude/skills/verify/SKILL.md` exists, first "the coordinator refreshes the verify skill with `/pstack:maintain-verification-skill` (with your OK), then …"; ends with "Optional: a short Retrospective on the phase just closed — `claude --agent retrospective "phase <N>"`" (`<N>` from the last `Phase N approved` line) unless a line after it says `retrospective: skipped` or the command already names the retrospective |
| pm / `checkpoint` / `project-complete` | Project complete — README.md written. Optional: `claude --agent retrospective` |
| pm / `checkpoint` / `blocked` or any other result | The checkpoint did not complete (`<result>`) — read PM's last message for what is still open (a `blocked` final checkpoint normally records `next: claude --agent tech-lead "decisions: …"`, which is shown instead) |
| tech-lead / any mode / `setup-changed` | Setup changed (see Setup Changed in Tech Lead Reviews). Redo the listed `setup.md` steps, then: `claude --agent tech-lead "Setup is complete"` |
| tech-lead / `init-review` | Complete every step in `project-planning/setup.md`, then: `claude --agent tech-lead "Setup is complete"` |
| tech-lead / `pre-sync-review` | Read the re-review. Changes requested: `claude --agent pm "iterate"`. You approve the PRD: `claude --agent pm "finalize"` |
| tech-lead / `setup-confirmation`, before `[INIT]` | `claude --agent pm "iterate"` to apply Tech Lead's feedback, or `claude --agent pm "finalize"` if there is none and you approve the PRD |
| tech-lead / `setup-confirmation`, after `[INIT]` (tagged in PM Updates) | Setup re-confirmed. Resume where the work stopped: re-run the agent that reported the drift (usually QA for that module, with the same word it had) |
| tech-lead / `change-review` (no `next:` recorded) | Read the review. Accept as-is: `claude --agent doc-sync`. PRD needs revising: `claude --agent pm "change"` |
| tech-lead / `on-demand-review` (no `next:` recorded) | Read the review. Tech Lead names the next command in its review; if it didn't, PRD-level change: `claude --agent pm "change"` |
| tech-lead / `integration-review` / `clean` | No integration issues this phase. Next: `claude --agent pm "checkpoint"` |
| tech-lead / `integration-review` / `issues-found` | Review `integration-review.md` and decide every row (Concerns and Recommendations), then: `claude --agent tech-lead "decisions: INT-001 approve, INT-002 reject, INT-003 defer"` |
| tech-lead / `record-decisions` | For each APPROVED item: `claude --agent engineer-ASSIGNED_MODULE "integration-fix INT-ID"` (rows noted `blast-radius first`: the coordinator runs `/pstack:blast-radius` before that). Nothing approved and nothing PROPOSED: `claude --agent pm "checkpoint"` |
| tech-lead / `confirm-fix` | No row in integration-review.md still open (all CONFIRMED CLOSED, REJECTED, DEFERRED, SPLIT, ACCEPTED (KNOWN ISSUE) or NO ISSUES — DEFERRED not at the final checkpoint): `claude --agent pm "checkpoint"`. Otherwise continue the next open row |
| tech-lead / `repeat-failure-review` | Tech Lead's diagnosis is in Tech Lead Reviews. Next: `claude --agent engineer-<module> "bugfix — follow Tech Lead's repeat-failure diagnosis for <AC>"` (module and AC from Last Action; `engineer-MODULE` when no module is recorded), or `claude --agent pm "change"` if it needs a requirements change |
| tech-lead / other | Read the latest entry in Tech Lead Reviews and decide the next agent |
| doc-sync / `needs-pm` | Doc-Sync left unresolved PRD questions (see Sync Reports). `claude --agent pm "change"` before any engineering starts |
| doc-sync / `success` | Review the sync report. If it generated new agents and they can't be called yet, run claude --continue to reload them in the same conversation. Then: `claude --agent engineer-NEXT_MODULE "implement"` (the first module in the Phase Plan not yet built; if this sync created an owner module that takes over existing code, first `claude --agent tech-lead "log migration rows for OWNER_MODULE"`) |
| engineer-mod-X / `implement` / `success` | `claude --agent qa-mod-X "verify"` |
| engineer-mod-X / `bugfix` / `success` | `claude --agent qa-mod-X "regression"` |
| engineer-mod-X / `integration-fix` / `success` | `claude --agent qa-mod-X "integration-fix-verify INT-ID"` (the ID from integration-review.md) |
| engineer-mod-X / `spec-update` / `success` | `claude --agent qa-mod-X "verify"` — check the acceptance criteria Doc-Sync changed (see the latest Sync Report) and re-run the rest for regressions |
| engineer-mod-X / `scope-fix` / `success` (scope now clean) | Decided by the hook from the interrupted run's mode and result (`framework-engineer-<dir>`), ignoring the Engineer's `next:` — "Scope is clean again." then: `spec-issue` → `claude --agent pm "change: spec issue from engineer-mod-X"`; `blocked-technical` → `claude --agent tech-lead "engineer blocker in mod-X"`; `blocked-dependency` → finish that module first (see Phase Plan); `needs-human` → see Engineering Progress, then `claude --agent engineer-mod-X`; otherwise bugfix → `claude --agent qa-mod-X "regression"` (with the blast-radius prefix when others depend on mod-X), integration-fix → `"integration-fix-verify INT-ID"`, spec-update → `"verify"` (the ACs Doc-Sync changed), implement → `"verify"` |
| engineer-mod-X / `bugfix` / `success`, other modules depend on mod-X | the message above (or the recorded `next:`), prefixed with: mod-X is used by <dependents> — first the coordinator runs `/pstack:blast-radius` on this fix's diff (saved to `project-planning/pstack-findings/`). Then: … |
| engineer-mod-X / `spec-issue` | `claude --agent pm "change: spec issue from engineer-mod-X"` — the Engineer found a requirement it cannot build as written (see Engineering Progress) |
| engineer-mod-X / `blocked-dependency` | A module this one depends on has not passed QA yet — finish it first (see Phase Plan). If the phase order is wrong: `claude --agent pm "change"` |
| engineer-mod-X / `blocked-technical` | `claude --agent tech-lead "engineer blocker in mod-X"` — cross-module or tech-stack blocker in Engineering Progress |
| qa-mod-X / `verify` or `regression` / `success` | Next module in the Phase Plan: `claude --agent engineer-NEXT_MODULE "implement"`. If this was the last module of the phase: the coordinator runs `/pstack:thermos` on the phase's changes (saved to `project-planning/pstack-findings/`), then `claude --agent tech-lead "phase-end integration review"` [+ the verify-skill hint, until the skill exists or Decisions says "verify skill: declined"] |
| qa-mod-X / `bugs-found` (not `integration-fix-verify`) | `claude --agent engineer-mod-X "bugfix"` — failures are in QA Results |
| qa-mod-X / `spec-issue` (any mode) | `claude --agent pm "change: spec issue from qa-mod-X"` — PRD update needed |
| qa-mod-X / `setup-drift` (any mode) | `claude --agent tech-lead "on-demand review: setup drift found by qa-mod-X"` |
| qa-mod-X / `repeat-failure`, `ac:` lists one or more ACs | Each AC is checked against its own escalation marker in the module's `status.md` (a looser match: the AC-ID, then any text, then `ESCALATED TO TECH LEAD — open`). ACs without an open marker: "First escalation of <ACs> — the coordinator runs `/pstack:how` and `/pstack:why` on the failing path (saved to `project-planning/pstack-findings/`)." ACs with one: "Already escalated: <ACs> (Tech Lead stays the owner)." Then: `claude --agent tech-lead "repeat-failure review <all listed ACs>"`. When QA recorded its own `next:`, the first-escalation step is still put in front of it unless it already names `pstack:how` |
| qa-mod-X / `repeat-failure`, no `ac:` recorded | Repeat failure — if the AC has no open marker yet, the coordinator runs `/pstack:how` and `/pstack:why` first; then `claude --agent tech-lead "repeat-failure review AC-ID"` |
| qa-mod-X / `integration-fix-verify` / `success` | Verify the fix yourself, then: `claude --agent tech-lead "INT-ID verified: WHAT YOU CHECKED"` |
| qa-mod-X / `integration-fix-verify` / `bugs-found` | The integration fix does not hold yet — `claude --agent engineer-mod-X "integration-fix INT-ID"`. Every other result of an integration-fix verification routes the same as in any other mode |
| Retrospective, or any unknown agent | no message |

The messages are written for the human and in the `claude --agent` form. In one-conversation mode the coordinator runs each command as a subagent with the quoted start word, and every "you" step (setup, decisions, sign-off, verifying a fix, answering a `needs-human` question) is a stopping point where it shows the agent's exact words and waits.

---

## Write Access Matrix

| File | PM | Doc-Sync | Tech Lead | Engineer | QA | Retrospective |
|---|---|---|---|---|---|---|
| `prd.md` | ✅ Write | 🔒 Read | 🔒 Read | ❌ No access | ❌ No access | 🔒 Read |
| `production.md` | 🔒 Read (final README only) | ✅ Write | 🔒 Read | 🔒 Read | 🔒 Read | 🔒 Read |
| `status.md` (project-level) | ✅ Write (Last Action, Build Config, PM Updates, Module Map — the only agent `pstack-guard.sh` lets change it — Checkpoint History, Decisions, Skill Recommendations; Current Phase — advance at checkpoint, or when a change adds a module to the current phase) | ✅ Write (Last Action, Sync Reports, Phase Plan, Skill Recommendations; Current Phase — initial sync only) | ✅ Write (Last Action, Tech Lead Reviews, Skill Recommendations) | ✅ Write (Last Action, Skill Recommendations) | ✅ Write (Last Action, Skill Recommendations) | 🔒 Read |
| `modules/*/status.md` (module-level) | 🔒 Read (change, checkpoint) | ✅ Write (creates during sync) | ✅ Write (one escalation-marker line only, repeat-failure review) | ✅ Write (Engineering Progress, assigned only) | ✅ Write (QA Results, assigned only, plus flipping Tech Lead's marker to resolved) | 🔒 Read |
| `modules/mod-*/` directories | ✅ Create (+ `.gitkeep` only) | ❌ Never creates | ❌ No access | ❌ No access | ❌ No access | ❌ No access |
| `project-planning/setup.md` | 🔒 Read (final README only) | ❌ No access | ✅ Write (init review; pre-sync review when setup changed; after `[INIT]`, an on-demand review the human approves) | 🔒 Read | 🔒 Read | 🔒 Read |
| `.gitignore`, `docker-compose.yml` | ❌ No access | ❌ No access | ✅ Write (same rule as `setup.md`) | 🔒 Read | 🔒 Read | ❌ No access |
| `.env.example` | ❌ No access | ❌ No access | ✅ Write (init review; pre-sync review when setup changed) | ✅ Write (after `[INIT]`, project files owner only) | 🔒 Read | ❌ No access |
| Project files (manifests, lockfiles, CI config on the Module Map `Project files:` line) | ❌ No access | ❌ No access | 🔒 Read | ✅ Write (project files owner only — `module_scope.py`) | 🔒 Read | ❌ No access |
| `.env` | ❌ No access | ❌ No access | Existence + gitignore check only | Presence check only | Presence check only | ❌ No access |
| `modules/*/spec.md` | ❌ No access | ✅ Write | 🔒 Read | 🔒 Read (assigned only) | 🔒 Read (assigned only) | 🔒 Read |
| `project-planning/integration-review.md` | 🔒 Read (checkpoint gate only) | ❌ No access | ✅ Write (create; PROPOSED / NO ISSUES / SPLIT / CONFIRMED CLOSED / ACCEPTED (KNOWN ISSUE); records the human's APPROVED / REJECTED / DEFERRED + Assigned Module and HUMAN VERIFIED) | ✅ Write (IN PROGRESS / FIXED – AWAITING QA, assigned rows only) | ✅ Write (QA VERIFIED or back to APPROVED, assigned rows only) | ❌ No access |
| Source code | ❌ No access | ❌ No access | 🔒 Read (reviews) | ✅ Write (own Source Path only — `module_scope.py`, enforced by `pstack-guard.sh`, `self-check.sh`, and `handoff.sh` on every Engineer stop) | 🔒 Read | ❌ No access |
| `README.md` (final) | ✅ Write (final checkpoint) | ❌ No access | ❌ No access | ❌ No access | ❌ No access | ❌ No access |
| `.claude/skills/*` (`~/.claude` writes blocked for every agent by `pstack-guard.sh`) | ❌ No access | ❌ No access | ❌ No access | ❌ No access | ❌ No access | 🔒 Read |
| `.claude/agents/*` | ❌ No access | ✅ Write (`engineer-<dir>.md` + `qa-<dir>.md` only) | ❌ No access | ❌ No access | ❌ No access | 🔒 Read |
| `project-planning/pstack-findings/*` | ❌ No access | ❌ No access | 🔒 Read | ❌ No access | ❌ No access | 🔒 Read |
| Project skills `.claude/skills/<name>/` (e.g. `verify`) | 🔒 Use via `Skill` (never edit) | ❌ No access (blocked by `pstack-guard.sh`) | ❌ No access (no `Skill` tool) | 🔒 Use via `Skill` (never edit) | 🔒 Use via `Skill` (never edit) | 🔒 Read |
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
│   │       └── module_scope.py                    # Module Map scope rules shared by self-check.sh, pstack-guard.sh + handoff.sh
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
│   ├── engineer-mod-<name>.md                      # Generated by Doc-Sync — never hand-edit; `claude --continue` to load
│   └── qa-mod-<name>.md
└── skills/verify/                                  # Optional — coordinator creates it once the app runs with
                                                     # /pstack:create-verification-skill, only if the human says yes;
                                                     # refreshed at each checkpoint with /pstack:maintain-verification-skill

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

In one-conversation mode the coordinator runs every framework agent as a subagent (a direct `claude --agent <name>` run works the same way); agents never start other agents. Where a handoff benefits from a multi-agent pstack review, the coordinator runs it first in its own session, saves the output to `project-planning/pstack-findings/`, commits it, and then starts the next agent with the findings file named in its instructions. The project `CLAUDE.md` ("Required pstack steps") is the source of truth; `handoff.sh` repeats the step in its message.

| Handoff point | pstack step | Then |
|---|---|---|
| PM change tagged `[ARCHITECTURAL]` | `how` on the affected code | `tech-lead` change review |
| QA pass, last module of the phase | `thermos` (diff from the last checkpoint commit, phase 1: `doc-sync(initial)`, limited to the phase's Source Paths) | `tech-lead` integration review |
| An Engineer bugfix succeeded on a module other modules depend on (the hook names them from each spec's `## Dependencies` section) | `blast-radius` on that fix's diff (probe scripts outside the project, no arena) | risks: `tech-lead` on-demand review; otherwise the QA command the hook printed |
| An approved integration-review row noted "blast-radius first" (before the fix) | `blast-radius` on the planned fix | `tech-lead` if the plan changes, otherwise `engineer-<module> "integration-fix <INT-ID>"` |
| QA repeat-failure, first escalation of that AC | `how` + `why` | `tech-lead` repeat-failure review |
| The first phase in which the app runs, no verify skill yet, human approves (a "no" goes to PM's Decisions as "verify skill: declined") | `create-verification-skill` (the coordinator commits `.claude/skills/verify/` as `pstack(create-verification-skill)`) | QA uses `verify` from then on |
| Each PM checkpoint, verify skill exists, with the human's OK | `maintain-verification-skill` | the next phase's first Engineer |

PM runs `pstack:sharpen` itself at the start of init. Findings are delivered, never applied: Tech Lead checks each one against the code and records which it accepted or rejected, the human decides, and the owner changes the file.

In the flows below, `[COORDINATOR RUNS: claude --agent X "<word>"]` means the coordinator starts agent X as a subagent with that start word (in a direct run, the human runs the same command). `[HUMAN …]` marks a stopping point: the coordinator shows the agent's exact proposal, question, or script, waits, and passes the human's words on quoted as `<name>: "<exact words>"`. Every PM step that changes something is two runs — a proposal pass the human answers, then an apply pass carrying `Approved by <name>: "<exact words>"`.

### Init Flow (once per project)

```
User
 ↓ provides requirements to the coordinator
 [COORDINATOR RUNS: claude --agent pm — proposal passes until the human approves; each question relayed word for word]
PM [init]
 ↓ runs pstack:sharpen on the request, restates the goal in 2–3 sentences, waits for the user's correction
 ↓ runs init-project.sh to scaffold project-planning/ + root CLAUDE.md (and git init if the folder is not a repository)
 ↓ gathers requirements (numbered questions), fills prd.md from template, anti-patterns + quality checklist
 ↓ [HUMAN APPROVES the draft] → apply pass: commits project-planning/ + CLAUDE.md: git commit -m "pm(init): draft PRD for <project>"
 [Stop → hook: 'claude --agent tech-lead "initial PRD review"']
 [COORDINATOR RUNS: claude --agent tech-lead "initial PRD review"]
Tech Lead [init-review]
 ↓ checks installed tool versions against the Tech Stack
 ↓ reviews PRD (feasibility, risks, dependencies, gaps, proposed conventions, shared-code owners), writes findings to Tech Lead Reviews
 ↓ creates .gitignore (first), project-planning/setup.md; backend projects also .env.example + docker-compose.yml
 ↓ commits: git commit -m "tech-lead(init-review): <summary>"
 [Stop → hook: 'Complete every step in project-planning/setup.md, then: claude --agent tech-lead "Setup is complete"']
 [HUMAN COMPLETES setup.md — install deps, dev server and build (frontend-only); or keys, .env, docker compose up -d (backend)
  — a stopping point: the coordinator waits for the human to say it is done]
 [COORDINATOR RUNS: claude --agent tech-lead "Setup is complete"]
Tech Lead [setup-confirmation]
 ↓ verifies: every docker-compose.yml service running (backend) or the build command named in setup.md (frontend-only); .env existence + gitignore only
 ↓ records ### Setup Confirmation — <date> under ## Tech Lead Reviews ("PM agent may now finalize and tag [INIT].")
 ↓ commits: git commit -m "tech-lead(setup-confirmation): environment verified"
 [Stop → hook: 'claude --agent pm "iterate" to apply Tech Lead's feedback, or claude --agent pm "finalize" if there is none and you approve the PRD']
 [COORDINATOR RUNS: claude --agent pm "iterate" — proposal pass, HUMAN APPROVES, apply pass]
PM [iterate]  (repeat as needed)
 ↓ applies Tech Lead feedback / user edits via the pre-sync iteration protocol — no [TRIVIAL]/[SUBSTANTIVE] tags
 ↓ notes in PM Updates which Tech Lead Reviews entry each change answers; an approved Proposed Convention becomes the next CONV-NNN now
 ↓ commits: git commit -m "pm(iterate): <summary>"
 [Stop → hook: 'Architectural changes: claude --agent tech-lead "pre-sync re-review". Otherwise, once you approve: claude --agent pm "finalize"']
 ├── Architectural revision → [COORDINATOR RUNS: claude --agent tech-lead "pre-sync re-review"]
 │    Tech Lead [pre-sync-review]
 │     ↓ reviews only what changed since the init review
 │     ├── setup unchanged → result: success
 │     │    [hook: 'Changes requested: claude --agent pm "iterate". You approve the PRD: claude --agent pm "finalize"']
 │     └── tech stack / infrastructure changed → updates setup.md (+ infra files), adds ### Setup Changed — <date>,
 │          result: setup-changed
 │          [hook: 'Redo the listed setup.md steps, then: claude --agent tech-lead "Setup is complete"']
 │          → Tech Lead [setup-confirmation] again → PM
 └── [HUMAN GIVES final approval] → [COORDINATOR RUNS: claude --agent pm "finalize" — proposal pass (Build Config, Module Map),
      HUMAN APPROVES, apply pass]
PM [finalize]
 ↓ setup gate: ### Setup Confirmation present, no newer ### Setup Changed — otherwise stop
 ↓ writes Build Config (Build: / Lint: / Test:)
 ↓ proposes + confirms the Module Map: MOD-ID → mod-<name> directory → Source Path (no overlap, no nesting),
   plus the Project files: <owner> | <paths> line; creates each directory + .gitkeep
 ↓ tags a PM Updates entry [INIT]
 ↓ commits: git commit -m "pm(finalize): PRD ready for doc-sync"
 [Stop → hook: "claude --agent doc-sync — initial sync"]
 [COORDINATOR RUNS: claude --agent doc-sync]
Doc-Sync [initial]
 ↓ follows initial-sync workflow
 ↓ creates production.md (Shared Conventions = Build Config + Adopted Conventions) + module specs (with Context section)
 ↓ creates modules/<dir>/status.md (empty Engineering Progress + QA Results) per module
 ↓ generates .claude/agents/engineer-<dir>.md + qa-<dir>.md from ~/.claude/agent-templates/
 ↓ writes Phase Plan + Current Phase (first phase), sync report; runs verify-sync.sh
 ↓ commits: git commit -m "doc-sync(initial): <summary>"
 ├── result: needs-pm → [hook: 'claude --agent pm "change" before any engineering starts'] → PM [change] → Doc-Sync [delta]
 └── result: success → [hook: 'Review the sync report. If it generated new agents and they can't be called yet, run claude --continue to reload them in the same conversation.
                         Then: claude --agent engineer-NEXT_MODULE "implement"' (first module in the Phase Plan not yet built)]
 [COORDINATOR RUNS: claude --agent engineer-mod-<first> "implement" — if the new subagent type is unknown, the human runs
  claude --continue to reopen the same conversation with the generated agents loaded]
Engineer [implement]  (via claude --agent engineer-mod-<name> "implement")
 ↓ first module of the project: infrastructure pre-flight (needs-human on failure)
 ↓ implements within its Source Path (+ project files if it owns them), runs self-check.sh + integration tests + judgment items
 ↓ logs results to modules/<dir>/status.md, updates Last Action
 ↓ commits: git commit -m "engineer-mod-<name>(implement): <summary>"
 [Stop → hook: 'claude --agent qa-mod-<name> "verify"']
 [COORDINATOR RUNS: claude --agent qa-mod-<name> "verify"]
QA [verify]  (via claude --agent qa-mod-<name>)
 ↓ follows functional-test workflow, runs run-qa.sh, live server / verify skill / human sign-off as the module needs
 ↓ logs results to modules/<dir>/status.md, updates Last Action
 ↓ commits: git commit -m "qa-mod-<name>: pass — <summary>"   (needs-signoff when it handed the human a UI test script:
   [HUMAN RUNS the script] → COORDINATOR RUNS: claude --agent qa-mod-<name> "ui-results: <the human's exact words>")
 [Stop → hook: next module (see Phase Plan), or — last module of the phase — the phase-end loop below]
```

### Phase-End Loop (every phase)

```
QA passes the last module of the phase
 [hook: 'the coordinator runs /pstack:thermos on the phase's changes ..., then claude --agent tech-lead "phase-end integration review"']
Coordinator
 ↓ runs /pstack:thermos (diff from the last Checkpoint History commit — phase 1: doc-sync(initial) — limited to the phase's Source Paths)
 ↓ saves project-planning/pstack-findings/<date>-thermos-phase-<N>.md, checks git status, commits
 [COORDINATOR RUNS: claude --agent tech-lead "phase-end integration review"]
Tech Lead [integration-review]
 ↓ reads every module in the phase + the thermos findings, runs scan-integration.sh
 ↓ applies cross-module-checklist.md + optimization-criteria.md
 ↓ lists DEFERRED rows from earlier phases again for a new decision (any such row means issues-found)
 ↓ logs PROPOSED rows to project-planning/integration-review.md — or, with no finding and nothing carried forward, one NO ISSUES row
 ↓ commits: git commit -m "tech-lead(integration-review): phase <N> — <counts>"
 ├── result: clean → [hook: 'claude --agent pm "checkpoint"'] → PM [checkpoint]
 └── result: issues-found
      [hook: 'decide every row (Concerns and Recommendations), then:
              claude --agent tech-lead "decisions: INT-001 approve, INT-002 reject, INT-003 defer"']
      [HUMAN DECIDES every row — the coordinator shows the rows and waits]
      [COORDINATOR RUNS: claude --agent tech-lead "decisions: …" — the human's decisions quoted exactly]
     Tech Lead [record-decisions]
      ↓ sets APPROVED / REJECTED / DEFERRED (final checkpoint: or ACCEPTED (KNOWN ISSUE)) exactly as said; asks if ambiguous;
        unmentioned items stay PROPOSED
      ↓ fills Assigned Module per APPROVED item from the Module Map Source Path (confirmed with the human);
        a fix spanning modules splits into INT-003a / INT-003b, one per owner; the original becomes SPLIT
      ↓ notes "blast-radius first" where the fix changes code another module depends on
      ↓ commits
      [hook: 'per APPROVED item: claude --agent engineer-ASSIGNED_MODULE "integration-fix INT-ID"']
      For each APPROVED item:
       (if "blast-radius first") Coordinator runs /pstack:blast-radius → pstack-findings/<date>-blast-radius-<INT-ID>.md
                                 → claude --agent tech-lead "on-demand review of <INT-ID> blast-radius" if the risks change the plan
       Engineer [integration-fix]  → IN PROGRESS → FIXED – AWAITING QA
        [hook: 'claude --agent qa-mod-<name> "integration-fix-verify INT-ID"']
       QA [integration-fix-verify] → QA VERIFIED (or back to APPROVED, result: bugs-found → Engineer again;
                                    other results route as in any QA run)
        [hook: 'Verify the fix yourself, then: claude --agent tech-lead "INT-ID verified: WHAT YOU CHECKED"']
       [HUMAN VERIFIES the fix themselves — a stopping point]
       [COORDINATOR RUNS: claude --agent tech-lead "INT-ID verified: <the human's exact words>"]
       Tech Lead [confirm-fix]
        ↓ records HUMAN VERIFIED from the human's statement (date + their words)
        ↓ re-checks the failure scenario → CONFIRMED CLOSED (or back to APPROVED)
        [hook: 'No row in integration-review.md still open (all CONFIRMED CLOSED, REJECTED, DEFERRED, SPLIT,
                ACCEPTED (KNOWN ISSUE) or NO ISSUES — DEFERRED not at the final checkpoint): claude --agent pm "checkpoint"']
 [COORDINATOR RUNS: claude --agent pm "checkpoint" — proposal pass (results, Retrospective question), HUMAN APPROVES, apply pass]
PM [checkpoint]
 ↓ gate: Integration & Optimization Review entry exists for the phase, and every row in the file (any phase) is
   CONFIRMED CLOSED / REJECTED / DEFERRED (not at the final checkpoint) / SPLIT / ACCEPTED (KNOWN ISSUE) / NO ISSUES
   — otherwise stop (result: blocked) and list what each open item waits for
   (hook: PM's next:, or 'The checkpoint did not complete — read PM's last message for what is still open')
 ↓ final phase, step 1b: any DEFERRED row → the user approves, rejects, or accepts it as a known issue;
   PM stops with result: blocked, next: 'claude --agent tech-lead "decisions: INT-003 accept as known issue, INT-005 approve"'
   (nothing written to Checkpoint History, no tag) → Tech Lead [record-decisions] (accepted → ACCEPTED (KNOWN ISSUE);
   approved → the normal fix loop) → PM [checkpoint] again once no row is DEFERRED or otherwise open
 ↓ reads all modules/*/status.md, presents results, gets explicit approval
 ↓ writes "Phase <N> approved — <date> — commit: <hash>" to Checkpoint History, advances Current Phase
 ↓ final phase: writes README.md (confirmed with the user; every ACCEPTED (KNOWN ISSUE) row under "Known issues"),
   result: project-complete
 ↓ commits: git commit -m "pm(checkpoint): phase <N> approved", then git tag checkpoint-<N>
 ├── more phases → [hook: 'Now in <phase>. Next: claude --agent engineer-FIRST_MODULE_OF_PHASE "implement"'
 │                  — preceded by the coordinator's /pstack:maintain-verification-skill when the verify skill exists,
 │                  and followed by the optional 'claude --agent retrospective "phase <N>"' unless a line after the
 │                  last "Phase N approved" line in Checkpoint History says retrospective: skipped]
 └── project-complete → [hook: "Project complete — README.md written. Optional: claude --agent retrospective"]
```

Optional: while `.claude/skills/verify/` does not exist and `## Decisions` does not record "verify skill: declined", the hook's QA-pass message suggests the coordinator run `/pstack:create-verification-skill` once the app runs — only with the human's yes (a "no" is recorded by PM in Decisions, which silences the hint). QA uses `verify` from then on, and the coordinator refreshes it with `/pstack:maintain-verification-skill` at each checkpoint, with the human's OK.

### Standard Change Flow (post-sync — Doc-Sync has run at least once)

```
User requests change  OR  Engineer/QA escalates an issue (spec-issue → 'pm "change: spec issue from <agent>"')  OR  Doc-Sync left needs-pm questions
 [COORDINATOR RUNS: claude --agent pm "change" — proposal pass (the change + trivial/substantive and architectural
  questions), HUMAN APPROVES, apply pass]
PM [change]
 ↓ re-reads prd.md; reads the escalation in modules/<mod>/status.md or the questions in Sync Reports
 ↓ smallest change, quality checklist, confirms with user
 ↓ a changed build/lint/test command: updates Build Config, tags [TRIVIAL] Build Config changed
 ↓ asks user: trivial or substantive? Tags PM Updates [TRIVIAL] / [SUBSTANTIVE]
   (answers to Doc-Sync questions are always [SUBSTANTIVE] and list each marker they resolve;
    an approved Tech Lead convention becomes the next CONV-NNN in section 9 Adopted Conventions)
 ↓ asks user: architectural (data model, module boundaries, integrations, tech stack)? Yes → adds [ARCHITECTURAL]
 ↓ new module: directory + Source Path + Module Map row (+ Current Phase line if it joins the current phase)
 ↓ code moving to another module's Source Path: its ACs move to the new owner too; increments the PRD revision
 ↓ commits: git commit -m "pm(change): <summary>"
 [Stop → hook: PM's next: (with the /pstack:how step put in front of it when the latest PM Updates entry is
   [ARCHITECTURAL] and next: does not already name it) — fallback: '[ARCHITECTURAL] change — the coordinator runs
   /pstack:how ..., then claude --agent tech-lead "change review"', or 'claude --agent doc-sync' when not tagged]
 ├── [ARCHITECTURAL]:
 │    Coordinator runs /pstack:how on the affected code → pstack-findings/<date>-how-<topic>.md, commits
 │    [COORDINATOR RUNS: claude --agent tech-lead "change review"]
 │    Tech Lead [change-review]  (repeats the overlapping-modules scan if a module was added; records next:)
 │     [hook: the recorded next: command — or, without one, 'Accept as-is: claude --agent doc-sync. PRD needs revising: claude --agent pm "change"']
 └── Otherwise → [COORDINATOR RUNS: claude --agent doc-sync]
Doc-Sync
 ↓ mixed tags waiting since the last Sync Report: the strongest wins — [SUBSTANTIVE] (the delta sync carries the
   trivial wording changes too)
 ↓ [TRIVIAL]: passthrough — every waiting [TRIVIAL] entry in one run, in PM Updates position order (not date):
   propagate wording (or re-copy Build Config), brief sync note, skip verify-sync.sh
 ↓ [SUBSTANTIVE]: delta-sync of every PM Updates entry after the last Sync Report's "PM Update reference",
   by position (a [TRIVIAL] Build Config
   changed entry in that window still re-copies Build Config); new modules (and modules skipped earlier with a
   [BLOCKER] PM has fixed) get spec + status.md + wrappers; modules whose Source Path or dependencies changed
   get their wrappers regenerated
 ↓ commits: git commit -m "doc-sync(<trivial|delta>): <summary>"
 [Stop → hook: Doc-Sync's next:, naming the Engineer of every module whose spec changed — "spec-update" if it has
   been built (passed QA or not), "implement" if not built yet; none for a wording-only [TRIVIAL] change; for a
   production.md-only change, the affected modules with "spec-update" (fallback: 'claude --agent engineer-NEXT_MODULE
   "implement"') — or pm "change" on needs-pm]
   engineer-mod-X "spec-update" → qa-mod-X "verify" on the changed ACs (and the rest for regressions)
 ├── new owner module that takes over code other modules hold:
 │    [COORDINATOR RUNS: claude --agent tech-lead "log migration rows for <owner>"]
 │    Tech Lead [on-demand-review] logs one PROPOSED integration-review row per module that must give up its copy,
 │     next: 'claude --agent tech-lead "decisions: ..."' → record-decisions → the normal fix → QA → human → confirm loop
 [COORDINATOR RUNS: claude --agent engineer-mod-<name> "implement" (if new or regenerated agents are not yet loaded,
  the human runs claude --continue first)]
engineer-mod-X → qa-mod-X → … → Phase-End Loop → PM [checkpoint]
```

### On-Demand Tech Lead (anytime)

```
Engineer records result: blocked-technical  OR  QA flags a pattern or setup drift  OR  human sees an architectural concern
 [hook (blocked-technical): 'claude --agent tech-lead "engineer blocker in mod-<name>"']
 [COORDINATOR RUNS: claude --agent tech-lead "<what to review>"]
Tech Lead [on-demand-review]
 ↓ reads relevant docs + blocker (including modules/<mod>/status.md if needed)
 ↓ writes findings to Tech Lead Reviews, updates Last Action
 ↓ setup drift: updates setup.md / docker-compose.yml / .gitignore with the human's approval,
   adds ### Setup Changed — <date>, result: setup-changed → human redoes the steps →
   Tech Lead [setup-confirmation] ("Setup re-confirmed after the change listed in Setup Changed.") →
   hook: re-run the agent that reported the drift (usually QA for that module, with the same word it had)
 ↓ records next: — the exact next command, with the agent's start word
 ↓ commits: git commit -m "tech-lead(on-demand-review): <concern>"
 [Stop → hook: the recorded next: command (e.g. 'claude --agent engineer-mod-auth "integration-fix INT-001a"',
   'claude --agent qa-mod-auth "verify"'); without one: 'Tech Lead names the next command in its review;
   if it didn't, PRD-level change: claude --agent pm "change"']
 [COORDINATOR RUNS the recorded next: — the human decides first when it is a stopping point]
 ├── Command Tech Lead named → the coordinator runs it
 └── PRD-level change → claude --agent pm "change" (proposal pass, HUMAN APPROVES, apply pass)
```

An Engineer `blocked-dependency` result does not go to Tech Lead: the hook says to finish the dependency module first, or run PM if the phase order itself is wrong. A bug that has failed QA 3 times on the same AC follows a dedicated version of this flow, with Tech Lead staying the owner of that AC until it resolves — see Bug Fix Loop below.

### Bug Fix Loop

```
QA finds bugs (1st failure on this AC) — result: bugs-found
 ↓ logs specific failures (Input / Expected / Actual) to modules/<dir>/status.md
 ↓ commits: git commit -m "qa-mod-<name>: fail — <summary>"
 [Stop → hook: 'claude --agent engineer-mod-<name> "bugfix" — failures are in QA Results']
 [COORDINATOR RUNS: claude --agent engineer-mod-<name> "bugfix"]
Engineer [bugfix] (attempt 1)
 ↓ states the observed layer + evidence, writes a one-line impact note, fixes, re-runs self-check.sh
 ↓ commits: git commit -m "engineer-mod-<name>(bugfix): <summary>"
 [Stop → hook re-runs the scope check (a violation → 'Fix first: claude --agent engineer-mod-<name> "scope-fix"', which
   undoes only those changes; after it the hook re-checks and returns to "regression", with no extra regression run);
   otherwise 'claude --agent qa-mod-<name> "regression"', prefixed with the coordinator's /pstack:blast-radius
   on the fix's diff when other modules depend on this one]
 [COORDINATOR RUNS: claude --agent qa-mod-<name> "regression"]
QA [regression]
 ↓ follows regression-test workflow, appends a ### QA Run N — Regression block
 ↓ commits
 ├─ PASS → done
 ├─ FAIL (2nd failure, observed output differs from the 1st) → same loop back to Engineer (attempt 2)
 └─ FAIL (3rd failure; a 2nd failure with output identical to the 1st; or an escalation marker is already open)
    — result: repeat-failure,
    ac: <every AC routed to Tech Lead in this run, comma-separated>
      QA does NOT route back to Engineer again; the hook checks each listed AC's marker
      ├── ACs with no open marker (first escalation):
      │    [hook: 'First escalation of <ACs> — the coordinator runs /pstack:how and /pstack:why ...'
      │     — added in front of QA's own next: too, unless it already names pstack:how]
      │    Coordinator saves pstack-findings/<date>-how-why-<AC-ID>.md, commits
      ├── ACs whose marker is already open: [hook: 'Already escalated: <ACs> (Tech Lead stays the owner)']
      └── then, in either case: [hook: 'claude --agent tech-lead "repeat-failure review <ACs>"']
      [COORDINATOR RUNS: claude --agent tech-lead "repeat-failure review <ACs>"]
     Tech Lead [repeat-failure-review]
      ↓ requires real evidence of which layer caused the bug (if missing: needs-human with the specific check →
        [HUMAN RUNS the check] → the coordinator runs Tech Lead again with the human's quoted answer)
      ↓ writes ### Repeat-Failure Review — <AC-ID> to Tech Lead Reviews (several ACs: one combined entry, a section per AC)
      ↓ first invocation for the AC since its last marker was resolved (or ever): writes
        "AC-<ID>: ESCALATED TO TECH LEAD — open" to modules/<dir>/status.md (one per AC)
      ↓ Last Action records module: and ac: <AC-ID>; commits
      [hook: 'claude --agent engineer-<module> "bugfix — follow Tech Lead's repeat-failure diagnosis for <AC>"', or pm "change"]
      [COORDINATOR RUNS: that command, with Tech Lead's diagnosis named in the Engineer's instructions]
     Engineer [bugfix] (implements per Tech Lead's diagnosis, not an independent attempt)
      ↓ commits
      [COORDINATOR RUNS: claude --agent qa-mod-<name> "regression"]
     QA [regression]
      ├─ PASS → flips the marker to "— resolved <date>", done
      └─ FAIL again → routes straight back to Tech Lead (marker still open, no new 3-count)
   (once a marker is resolved, a later failure of that AC starts a fresh count)
```

When one run has failures of different kinds, QA records a single result by precedence — `spec-issue` > `setup-drift` > `repeat-failure` > `bugs-found` — lists every failure, and records every failure it did not route as a `- [ ]` line under `### Open items` in the module's QA Results, ticking them (`- [x] … — passed <date>`) in later runs once they pass. The hook adds "Open QA items still waiting: <module> (<count>) …" to every handoff, whichever agent ran, so the coordinator (or the human, in a direct run) can route them after the first is resolved.

### Retrospective (manual only, after phase or project completion)

```
[HUMAN ASKS for it, or says yes to the checkpoint offer] → [COORDINATOR RUNS: claude --agent retrospective "phase <N>"]
  (or the human runs it directly)
Retrospective
 ↓ reads project-level status.md + all modules/*/status.md + current skills/agents
 ↓ writes structured proposals to project-planning/retrospective/drafts/
 ↓ updates proposed-changes.md summary
 ↓ commits: git commit -m "retrospective: <summary>"
 [No hook message — Retrospective writes no Last Action; its final message (relayed by the coordinator) tells the human
  to review proposed-changes.md]
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
mode: [pm: init|iterate|finalize|change|checkpoint — doc-sync: initial|delta|trivial — tech-lead: init-review|pre-sync-review|setup-confirmation|change-review|on-demand-review|integration-review|record-decisions|confirm-fix|repeat-failure-review — engineer: implement|bugfix|integration-fix|spec-update|scope-fix — qa: verify|regression|integration-fix-verify]
module: [module directory name or "n/a"]
result: [success|needs-human — plus pm: blocked|project-complete — doc-sync: needs-pm — tech-lead: setup-changed|clean|issues-found — engineer: blocked-dependency|blocked-technical|spec-issue — qa: bugs-found|setup-drift|spec-issue|repeat-failure|needs-signoff]
ac: [only for qa repeat-failure (every AC routed to Tech Lead in the run, comma-separated) and tech-lead repeat-failure-review (the AC-ID) — the hook checks each AC's escalation marker]
next: [always — the exact next command(s) with the agent's start word, including any coordinator pstack step; the hook shows it as is]
timestamp: [ISO 8601]

## Current Phase
<!-- Set by Doc-Sync at initial sync; PM advances it at each checkpoint (and updates it when a change adds a module to the current phase). Blank until the initial sync. -->
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
[Change summaries: what changed in PRD, when, why. Each entry's first line is `- YYYY-MM-DD [TAG] [ARCHITECTURAL] <one-line summary>` (tags only there), details indented below. Pre-sync revisions cite the Tech Lead Reviews entry they answer (untagged). Finalization tagged [INIT]. Subsequent changes tagged [TRIVIAL] or [SUBSTANTIVE], plus [ARCHITECTURAL] when the user says the change alters how the system is built; answers to Doc-Sync questions list each marker they resolve]

## Tech Lead Reviews
[Tech Lead's own entries: ### Review, ### Setup Confirmation, ### Setup Changed, ### Integration & Optimization Review — Phase <N>, ### Repeat-Failure Review — <AC-ID> (or one combined entry for several ACs); Proposed Conventions; pstack input lines]

## Sync Reports
[Doc-Sync output: what was synced, files created/modified, [AMBIGUITY]/[CONFLICT]/[BLOCKER] markers, verify-sync.sh result]

## Decisions
[Owned by PM. Audit trail for user decisions that are not PRD content (e.g. "defer offline mode to v2", or "verify skill: declined", which silences the hook's verify-skill hint), resolved disagreements, and key choices. Each entry: what was decided, who decided (human/PM/Tech Lead), the rationale, and which IDs are affected]

## Module Map
<!-- Filled by PM at finalize, after the user confirms directory names and source paths.
     Updated by PM when modules are added or renamed during change requests.
     Source Path is the code this module owns: the Engineer's write scope, the self-check
     boundary, and what pstack-guard.sh enforces. Several paths are comma-separated; a path may
     be a folder, a file, or a filename pattern (supabase/migrations/*_mod_003_*) when one folder
     holds several modules' files.
     Shared code belongs to exactly one module. No two Source Paths may overlap or nest
     (src/ and src/ui/ cannot both appear). Only PM may change this section (pstack-guard.sh).
     Project files are root-level files no single module's code lives in (manifests, lockfiles,
     .env.example, CI config); one module owns them all — one line, directly under the table. -->
| MOD-ID  | Directory        | Module Name    | Source Path              |
|---------|------------------|----------------|--------------------------|
| MOD-001 | mod-login        | User Login     | src/login/               |

Project files: mod-login | package.json, package-lock.json, .env.example, .github/

## Checkpoint History
[Phase completion confirmations from user, with git commit hash for each checkpoint (the commit is also tagged checkpoint-<N>), plus "retrospective: skipped" under that phase's line when the human declined its Retrospective (the hook then omits the offer; only lines after the latest "Phase N approved" line count). A blocked checkpoint writes nothing here]

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

One file per module. Created by Doc-Sync during initial sync (and when a new module is added). Engineer writes Engineering Progress; QA writes QA Results (each regression run as a `### QA Run N — Regression — <date>` block inside `## QA Results`; exactly one `### Open items` section, kept at the end of QA Results, listing the failures not routed yet, `- [ ]` lines ticked to `- [x] … — passed <date>` once they pass, which `handoff.sh` lists in every handoff; and, for a module with Dependencies, a `### Integration notes (for Tech Lead)` block of scan hits that the phase-end review reads). Tech Lead may add only the `AC-<ID>: ESCALATED TO TECH LEAD — open` line, which QA flips to `— resolved <date>`. PM reads these files in change and checkpoint mode.

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
| 21 | `.claude/skills/engineer-checklist/scripts/module_scope.py` | Module Map scope rules shared by `self-check.sh`, `pstack-guard.sh`, and `handoff.sh` (incl. the `changed` scope check) |
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
- Every agent is written to run either way: as a subagent of the coordinator in one-conversation mode, or directly by the human (`claude --agent <name>`). PM's `<modes>` section carries the two-pass rule (a proposal pass that only saves a proposal file without `Approved by <name>: "<exact words>"`, then an apply pass that records the quote); every other agent (Tech Lead, Doc-Sync, Retrospective, and the Engineer and QA templates) carries a `<run_modes>` block: as a subagent never ask — stop with `needs-human` (QA UI sign-off: `needs-signoff`) and put the exact question or script in the final message; treat a quoted `<name>: "<exact words>"` answer as the user's own and record it; never treat the coordinator's own wording as the user's decision. None starts another agent
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
- `handoff.sh`: register on `SubagentStop` (primary — in one-conversation mode every framework agent runs as a subagent) and `Stop` (direct `claude --agent` sessions). It resolves the project root from subdirectories (with or without git), reads `status.md` Last Action (including `ac:` and `next:`) and every module's `### Open items`, shows each new Last Action once (fingerprint in `.git/handoff-last-shown`), appends to the scope-check base log `.git/framework-handoff-log` at every Stop where HEAD moved, remembers each Engineer's last mode and result in `.git/framework-engineer-<dir>`, runs `module_scope.py changed` after every Engineer stop (and `module_scope.py dependents` for the blast-radius step), and prints the recorded `next:` or the per-mode suggestion from the Handoff Messages table — plus, on `SubagentStop`, the one-conversation line saying whether the coordinator carries on or asks the human first
- `pstack-guard.sh`: register on `PreToolUse` with matcher `Skill|Edit|Write|MultiEdit|NotebookEdit`; exit 2 with a reason on stderr to block. It reads the scope rules from `~/.claude/skills/engineer-checklist/scripts/module_scope.py`, so skills must be installed
- Both need `jq` and `python3` (`handoff.sh` uses it for the scope check and the dependents lookup); make executable with `chmod +x`
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
  - Every agent commit — code commits included — starts with its agent-role prefix; agents never use plain conventional-commit types such as `feat(x):`. Engineers use `engineer-<dir>(<implement|bugfix|integration-fix|spec-update|scope-fix|wip>):` (`wip` for partial work committed before a `spec-issue` stop). Prefixes keep the history readable; they do not decide attribution. `module_scope.py changed` (run by `self-check.sh` and by `handoff.sh` on every Engineer stop) takes its base from the hook's `<git-dir>/framework-handoff-log` — the latest entry written by anyone other than that Engineer — and falls back to the last commit not prefixed `engineer-<dir>` only when there is no log yet
  - The coordinator's own commits (applying a Retrospective proposal, editing `CLAUDE.md`) start `coordinator(<what>): …`, and the human prefixes manual commits `human: …` (the project `CLAUDE.md` "Commit prefixes" rule). Files changed only by `human:` or `coordinator(` commits are left out of the next Engineer's scope check — the only prefixes the check reads
- Agents commit only files within their write scope — never stage files outside their access boundary
- `handoff.sh` warns about any uncommitted change in the repo when it shows a handoff
- Checkpoint History entries in `status.md` record the git commit hash alongside phase completion notes, and PM tags each checkpoint commit `checkpoint-<N>` (the human pushes tags with `git push --tags`), providing named rollback points for major milestones
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
PM's init scaffolds the project `CLAUDE.md`, which carries the coordinator instructions. From then on, open the default session (`claude`) in the project folder: it is the coordinator and runs every agent as a subagent in that one conversation. Running any agent directly still works the same way.

---

## Parked Ideas

Considered and deliberately not built. Revisit when the stated condition changes.

### Running modules in parallel (parked)

- **What it would give**: two or more Engineers building independent modules at the same time (e.g. `mod-feed` and `mod-profile` once their shared dependency has passed QA).
- **Why it doesn't work today**: one `## Last Action` block in `status.md` (parallel sessions overwrite each other's handoff), one working tree (each Engineer's self-check would flag the other's files, and commits could sweep them up), and one `status.md` both sessions edit.
- **What it would take**: a Last Action block per module in `modules/<dir>/status.md` (the hook already receives the stopping agent's name, so it can pick the right block); one git worktree and branch per parallel module, merged back after QA; a rule that only modules whose dependencies have all passed may run in parallel.
- **Revisit when**: a phase has several independent modules and the human actually wants to run agents side by side. Until then it adds a merge step to every module and saves nothing.

