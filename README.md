# Multi-Agent Software Development System

A team of six specialized AI agents that plan, build, and QA software through a
controlled, human-approved workflow. Each agent runs as an independent
[Claude Code](https://docs.claude.com/en/docs/claude-code) session with a single
responsibility, coordinating entirely through files on disk — no shared memory,
no black box. A human reviews and approves every handoff.

**It produces real software.** This system designed, implemented, and QA'd
**[TabVault](https://tab-vault.com)**, a deployed full-stack tab/notes manager.
→ [TabVault repo](https://github.com/LeonWu813/tab-management)

---

## How it works

Each agent does one job, sees only the files its role needs, and commits its work
to git before stopping. The human runs every agent directly as its own session
(`claude --agent <name>`), so agents can ask the human questions; no agent starts
another. Every agent records the exact command to run next (`next:` in `status.md`,
where it stays for later), and a `Stop` hook prints it, ready to paste
(`claude --agent <name> "<start word>"`, e.g. `claude --agent qa-mod-login "verify"`;
anything the human fills in is an UPPERCASE placeholder such as `INT-ID`; the hook
falls back to its own per-mode default when `next:` is missing) — and the human
decides whether to run it. The default Claude Code session acts
as a coordinator: it tells the human which agent to run and runs the pstack review
steps (saved to `project-planning/pstack-findings/`) that Tech Lead reads, but never
edits an owned file itself. Every handoff is an atomic git commit, so any step can be
rolled back cleanly, and every phase checkpoint is tagged `checkpoint-<N>`.

```mermaid
flowchart TD
    U([User requirements]) --> PM1[PM init: sharpen, restate goal, write prd.md]
    PM1 --> TL[Tech Lead: architectural review, produce setup runbook]
    TL --> H1{{Human: complete setup, Tech Lead confirms}}
    H1 --> PMI[PM iterate: apply review feedback]
    PMI -->|architectural| TL2[Tech Lead: pre-sync review]
    TL2 --> PMI
    PMI -->|user approves| PM2[PM finalize: Module Map + Source Paths, tag INIT]
    PM2 --> DS[Doc-Sync: translate PRD into module specs,<br/>generate per-module Engineer + QA agents]
    DS --> ENG[Engineer: implement one assigned module]
    ENG --> QA[QA: verify module against its spec]
    QA -->|next module| ENG
    QA -->|bug found| ENG
    QA -->|3rd failure of same AC,<br/>or identical 2nd| TLR[Tech Lead: repeat-failure review]
    TLR --> ENG
    QA -->|spec issue| PM3[PM change flow: update PRD]
    ENG -->|spec issue| PM3
    PM3 -->|ARCHITECTURAL| TLC[Tech Lead: change review]
    TLC --> DS
    PM3 --> DS
    QA -->|last module of phase| IR[Tech Lead: integration review<br/>+ human decisions, fixes, verification]
    IR --> CP[PM checkpoint: review phase with user]
    CP -->|next phase| ENG
    CP -->|complete| DONE([Project complete])
    DONE -.manual.-> RETRO[Retrospective: propose system improvements]
    RETRO -.proposals.-> H2{{Human: review and selectively apply}}

    classDef human fill:#f4e4c1,stroke:#b8975a,color:#000;
    class H1,H2 human;
```

*A human approval gate sits on every arrow — the hook suggests the next step; the
human runs it.*

---

## Design principles

The interesting engineering isn't the code the agents write — it's the system that
makes them produce correct software reliably. Four ideas do most of the work:

- **Single responsibility.** Each agent has one job, one input, one output, one
  handoff rule. Small, scoped agents are easier to constrain and to reason about, so
  a mistake stays contained.
- **Least-privilege information boundaries.** Each agent reads and writes only the
  files its role requires. The Engineer never sees the PRD; it sees its module spec,
  which carries forward just enough context. No agent sees everything.
- **Human in the loop at every handoff.** The system proposes the next action; the
  human approves before it runs. Nothing is applied without review.
- **Git as a rollback safety net.** Every handoff is an atomic commit, so any step
  is a clean point to revert to. Progressive-disclosure skills (lean router files
  that load detailed workflows only when needed) keep each agent's context
  token-efficient.

---

## The six agents

| Agent | Responsibility | Can write |
|-------|----------------|-----------|
| **PM** | Owns the PRD and all user communication | `prd.md`, its `status.md` sections, final `README.md` |
| **Doc-Sync** | Translates the PRD into downstream specs; generates per-module Engineer/QA agents | `production.md`, module specs and status files, generated agents |
| **Tech Lead** | Architectural advisory: feasibility, risks, setup runbook, phase-end integration review | `status.md` (reviews), `setup.md` and infrastructure files, `integration-review.md` |
| **Engineer** | Implements one assigned module | its module's Source Path, the root project files if its module owns them, its own module status |
| **QA** | Verifies one module against its spec | its module's QA results |
| **Retrospective** | Proposes system improvements from project history (manual only) | `retrospective/` proposals |

Engineer and QA are base templates (in `.claude/agent-templates/`); Doc-Sync generates
a thin per-module wrapper for each (`engineer-mod-<name>`, `qa-mod-<name>`), hard-coding
which module spec, Source Path, and dependencies that instance may use. Source Paths
(folders, files, or filename patterns such as `supabase/migrations/*_mod_003_*`)
never overlap, and one module owns the root project files (manifests, lockfiles,
`.env.example`, CI config). A `PreToolUse` hook enforces each agent's skill allowlist
(framework agents other than Doc-Sync may also use the project's own `.claude/skills/`), keeps each Engineer's writes inside its module's scope (the same rules `self-check.sh`
uses), lets only PM change the Module Map, and blocks every agent from writing under
`~/.claude`. Shell writes never pass through that hook, so the handoff hook re-runs the
scope check whenever an Engineer stops: any file outside the module's scope replaces the
next step with a "Scope violation … Fix first" message that sends the Engineer back in
`scope-fix` mode to undo exactly those changes; once the scope is clean, the hook itself
routes back to the step that was interrupted. The check does not trust commit messages:
the handoff hook records a base commit at every stop where HEAD moved, and an Engineer's
changes are everything since the last base someone else recorded. Every agent commit
still carries its role prefix (`engineer-mod-login(implement): …`) so the history reads
clearly; the coordinator's own commits start `coordinator(<what>): …` and the human's
manual commits `human: …`, and files changed only by those two are left out of the check.

---

## Run it

```bash
# Install agents, base templates, skills, and hooks
mkdir -p ~/.claude/agents ~/.claude/agent-templates ~/.claude/skills ~/.claude/hooks
cp -r .claude/agents/.          ~/.claude/agents/
cp -r .claude/agent-templates/. ~/.claude/agent-templates/
cp -r .claude/skills/.          ~/.claude/skills/
cp -r .claude/hooks/.           ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
# Merge the entries in .claude/hooks/settings-hooks.json into the "hooks" key of
# ~/.claude/settings.json (Claude Code does not load a standalone hooks.json)
# This registers handoff.sh (next-step messages and the Engineer scope re-check, on
# Stop/SubagentStop) and pstack-guard.sh (on PreToolUse: skill allowlists, Engineer write
# scope, Module Map and ~/.claude protection, read-only pstack reviewers). Both need jq
# and python3. Optional: install the pstack plugin for the review steps listed under
# "Required pstack steps" in the scaffolded CLAUDE.md.

# Start a new project (PM's init scaffolds project-planning/ and CLAUDE.md, and runs
# git init if the folder is not a repository yet)
cd ~/projects/my-new-app
claude --agent pm
```

From there, follow the command each hook prints, approving each handoff. Run each
agent yourself in its own session — don't have the default session start agents as
subagents. Open a new terminal after Doc-Sync generates new per-module agents so they load.

---

## Repo structure

```
.claude/
├── agents/           # PM, Doc-Sync, Tech Lead, Retrospective (+ generated per-module wrappers in each project)
├── agent-templates/  # Engineer and QA base templates Doc-Sync builds the wrappers from
├── skills/           # Reusable knowledge: router SKILL.md + workflows/references/templates/scripts
└── hooks/            # handoff.sh (next command, Engineer scope re-check), pstack-guard.sh (allowlists, write scope, Module Map), settings-hooks.json
ARCHITECTURE.md  # Full design spec — the deep dive
```

For the complete design — every agent's constraints, the skill architecture, the
sync rulebook, and the git/rollback conventions — see **[ARCHITECTURE.md](./ARCHITECTURE.md)**.

---

## Status

<!-- Be honest here — this section backs your "did you really build this?" answer.
     Edit to match what's actually running vs. specified. Example below. -->

The six agent definitions, skills, and handoff hooks are implemented and were used
end to end to build [TabVault](https://tab-vault.com). And more going on~
