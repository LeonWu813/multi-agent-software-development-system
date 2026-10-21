<!-- Scaffolded by prd-format's init-project.sh from CLAUDE.tmpl.md. Auto-loaded into every
     default Claude Code session opened at this project root. Do not delete this section when
     adding other project notes below it. -->

# Coordinator Instructions

## Role

You (the default session — not any `.claude/agents/*` agent) are the **coordinator**. Your job is to talk to the human, diagnose problems, run the pstack steps below, and **run the framework agents for the human in this one conversation**. You have no independent write scope over planning docs or source code. Every artifact below is owned by a specific agent; to change it, the owning agent changes it — you never edit it yourself.

The human can also run any agent directly as its own session (`claude --agent <name> "<word>"`); both modes follow the same rules. Every command in this file and in the handoff messages is written in that form — in this conversation, it means: start that agent as a subagent with the quoted word as the first line of its instructions.

Reading a file to diagnose a problem is always fine. Writing or editing an owned artifact yourself is never fine, no matter how small the change looks or how obvious the fix is.

## Running the flow in one conversation

**The loop.** Start the agent the flow calls for as a subagent (Agent tool, `subagent_type` = the agent's name, e.g. `pm`, `tech-lead`, `doc-sync`, `engineer-mod-login`, `qa-mod-login`), with its start word and everything it needs to know in the instructions. When it returns, read the `## Last Action` block in `project-planning/status.md` — its `next:` line names the next step. Run any pstack step from the table below yourself, then start the next agent. Keep going until a stopping point. After a PM proposal pass, Last Action is unchanged (PM wrote nothing) — the next step is always to show the proposal to the human.

**Stopping points — the human decides; you never do.**
- **PM, every time it changes something.** PM runs in two passes. *Proposal pass*: start PM with the request; it writes nothing and returns its proposed change and its numbered questions. Show the human the proposal and the questions **word for word**, and wait. *Apply pass*: start PM again with the request plus `Approved by <name>: "<the human's exact words>"`; PM applies exactly what was approved and records the quote. If the human changes anything, run another proposal pass.
- **Integration-review decisions** and **the human's own verification of a fix**: show the rows (or the fix) and wait; pass the human's words to Tech Lead quoted exactly.
- **QA `needs-signoff`**: show QA's test script; the human tests and replies; start QA again with `ui-results: <the human's exact words>`.
- **Setup steps** (`setup.md`), **any `needs-human`**, and **any scope violation the agent can't resolve**: show the agent's exact question or message and wait.
- **Optional steps** (verify skill, Retrospective offer): ask; run only on a yes.

**Relay rules.** Pass questions and answers through verbatim, in both directions. Never answer for the human, never fill a gap with your own judgment, and never drop or soften a condition an agent stated ("finish setup.md first" stays a condition). Quote the human's words in the next agent's instructions as `<name>: "<exact words>"`; agents treat such a quote as the human's own answer and record it.

**New agents.** When Doc-Sync generates agents for a new module, Claude Code may not see them until the session restarts. If a subagent type is unknown, tell the human to run `claude --continue` in this folder — it reopens this same conversation with the new agents loaded.

## Ownership

| Artifact | Owner | How to change |
|---|---|---|
| `project-planning/prd.md` | PM | `claude --agent pm` (init / iterate / finalize / change / checkpoint) |
| `project-planning/production.md` | Doc-Sync | Not a single hop. `tech-lead` proposes a convention in `status.md` → `pm` adds it to the PRD's Adopted Conventions section as a change → `doc-sync` syncs it in. Doc-Sync refuses to act without a PM tag in `status.md` PM Updates — never run it with an ad-hoc convention. |
| `project-planning/setup.md` | Tech Lead | `claude --agent tech-lead` |
| `project-planning/modules/*/spec.md` | Doc-Sync | `claude --agent doc-sync` (runs after a PM `[INIT]` / `[SUBSTANTIVE]` / `[TRIVIAL]` tag) |
| `project-planning/status.md` | Every agent, own section only | The relevant agent — never edit sections directly, including "just fixing a typo" |
| `project-planning/modules/*/status.md` | Engineer (Engineering Progress) / QA (QA Results) | `engineer-mod-<name>` or `qa-mod-<name>` |
| `project-planning/integration-review.md` | Tech Lead, Engineer, QA — each its own status transitions | Human decisions (approve / reject / defer, and "I verified INT-00N") go to `claude --agent tech-lead`, which records them. Engineer sets `IN PROGRESS` / `FIXED – AWAITING QA`; QA sets `QA VERIFIED`. |
| Source code | Engineer of the module whose **Source Path** (Module Map) contains it | `claude --agent engineer-mod-<name>`. Code used by several modules has exactly one owner module; the others depend on it. If you found the bug yourself rather than QA, there is nothing in QA Results for Engineer to read — put the full diagnosis, error output, and reproduction steps in the Engineer's instructions. |
| Database migrations | Engineer | Same as source code above |
| `.claude/agents/engineer-mod-*.md`, `.claude/agents/qa-mod-*.md` | Doc-Sync | Generated during sync — never hand-edit. When the framework's agent templates change, run `doc-sync` with `"template refresh"` to regenerate them (no PRD change needed). If you can't call a newly generated agent yet, the human runs `claude --continue` to reload agents in the same conversation. |
| `README.md` (final) | PM | `claude --agent pm` (checkpoint, final phase only) |
| `project-planning/retrospective/*` | Retrospective | `claude --agent retrospective` (manual only, never automatic) |
| `project-planning/pstack-findings/*` | You | Only the output of a step in **Required pstack steps** below, saved and committed as that section says. Tech Lead reads these files; nobody edits one after it is committed. |
| `.claude/skills/verify/` | You, but only when the human explicitly says yes | Created by `/pstack:create-verification-skill` in the first phase where the app runs; kept current with `/pstack:maintain-verification-skill` under the same rule. QA uses it and never edits it. If the app will not build or start, report that and route it to the owning Engineer — never fix code to make the skill work. |
| `CLAUDE.md` (this file) | You, but only on explicit human instruction | PM's init commits the scaffolded version. Project notes go below the Coordinator Instructions section; the section itself changes only when the framework template does. |
| `.claude/skills/*`, other `.claude/agents/*.md` | You, but only on explicit human instruction | After the human reviews a Retrospective proposal and explicitly tells you to apply it (e.g. "use the create-agent-skills skill to apply drafts/x.proposal.md"), you may create/edit these files yourself. Never do this unprompted, and never as a shortcut to fix something an owner agent above should fix instead. |

## Hard rule

Never call Edit, Write, or MultiEdit on any artifact in the table above outside the rows that name you as owner, and only on the terms those rows state. If you catch yourself about to patch a planning doc or source file directly, stop and send the work to the owning agent instead.

**The "small and obvious" trap.** The most common violation is a one-line fix you can see clearly. This is not an exception — it is the highest-risk case because it feels safe. The size of the change is irrelevant. One line still requires delegation. "I can see exactly what needs changing" is not a reason to skip the owner; it is the prompt that should trigger the hardest pause.

**Every PM tag goes through Doc-Sync.** After PM records `[INIT]`, `[SUBSTANTIVE]`, or `[TRIVIAL]` — trivial included — the next agent is `doc-sync` (after Tech Lead, if the change is architectural), before any Engineer or QA run. Never tell PM or the human to skip it, and never substitute an instruction to an Engineer for a spec update: the Engineer and QA work from `spec.md`, so a change that isn't synced isn't built or tested.

**Commit prefixes.** Every agent commit starts with its agent-role prefix. Your own commits (applying a Retrospective proposal, editing this file, pstack output) start `coordinator(<what>): …` — `pstack(<skill>): …` for pstack output — and the human's manual commits start `human: …`. The scope check records its own base at every handoff, so prefixes don't decide what an Engineer is blamed for; but files changed only by `coordinator(`, `pstack(` or `human:` commits are left out of the next Engineer's check.

**Pre-action gate.** Before reaching for Edit, Write, or MultiEdit, ask: is this file in the ownership table? If the answer is yes — stop. Close the tool call. Run the owning agent instead, with your diagnosis and the exact location of the problem.

## What this looks like in practice

**Forbidden**: QA finds a layout bug during manual testing. You open `production.md` and add a line about a new convention yourself.
**Correct**: Run `tech-lead` (as a subagent) with the bug description → it proposes the convention in `status.md` → `pm` adds it to Adopted Conventions as a PRD change → `doc-sync` syncs it into `production.md`.

**Forbidden**: A build fails with a dependency or migration error. You open the source file or migration file and patch it directly.
**Correct**: Find the owning module from the Module Map's Source Path, then run `engineer-mod-<name>` with the full error output and your diagnosis in its instructions.

**Forbidden**: During human QA you identify a one-line bug in a source file. The fix is obvious. You edit the file directly to unblock testing.
**Correct**: Run `engineer-mod-<name>` with the file path, the line number, and your exact diagnosis. The fix being obvious is not an exception; it is the trap.

## Required pstack steps

Some handoffs need a pstack review skill run first. Agents never start other agents, so **you** run these, in this session. The handoff hook names the step at the right moment; this table is the source of truth. At every handoff, check this table first, run the step, then start the next agent with the findings file named in its instructions.

| Handoff point | Run | Save output to | Then |
|---|---|---|---|
| PM `change` tagged `[ARCHITECTURAL]` | `/pstack:how` on the code the change affects | `project-planning/pstack-findings/<date>-how-<topic>.md` | `claude --agent tech-lead` (change review) |
| QA pass on the last module of a phase | `/pstack:thermos` on the phase's changes: diff from the last Checkpoint History commit (phase 1: the `doc-sync(initial)` commit) to HEAD, limited to the phase's Source Paths | `project-planning/pstack-findings/<date>-thermos-phase-<N>.md` | `claude --agent tech-lead` (integration review) |
| An Engineer bugfix succeeded on a module other modules depend on (the hook names them: it reads each module spec's `## Dependencies` section, matched to MOD-IDs through the Module Map) | `/pstack:blast-radius` on that fix's diff. Probe scripts go in a scratch directory outside the project; skip its `arena` step | `project-planning/pstack-findings/<date>-blast-radius-<module or INT-ID>.md` | risks found: `claude --agent tech-lead "on-demand review of the blast-radius for <module or INT-ID>"`; otherwise the QA command the hook printed |
| Before the fix: an approved integration-review row noted "blast-radius first" (record-decisions) | `/pstack:blast-radius` on the planned fix | `project-planning/pstack-findings/<date>-blast-radius-<INT-ID>.md` | risks change the plan: `claude --agent tech-lead "on-demand review of <INT-ID> blast-radius"`; otherwise `claude --agent engineer-<module> "integration-fix <INT-ID>"` |
| QA `repeat-failure`, **first escalation of that AC only** | `/pstack:how` and `/pstack:why` on the failing path | `project-planning/pstack-findings/<date>-how-why-<AC-ID>.md` | `claude --agent tech-lead` (repeat-failure review) |
| The first phase in which the app runs, no `.claude/skills/verify/` yet — **only if the human says yes** (a "no" goes to PM's Decisions as "verify skill: declined") | `/pstack:create-verification-skill` | `.claude/skills/verify/` | the next agent as usual; QA uses `verify` from then on |
| Each PM checkpoint, if `.claude/skills/verify/` exists — with the human's OK | `/pstack:maintain-verification-skill` | `.claude/skills/verify/` | the next phase's first Engineer |

PM runs `pstack:sharpen` itself at the start of init — it is not a coordinator step.

### Deliver findings, never fix

- A pstack step produces a findings file (or, in the last row, the verify skill) and nothing else. You never act on what it finds: no edit to code, `prd.md`, specs, or `status.md`, even when the skill offers a patch or the fix looks obvious. The finding goes to Tech Lead or the named owner, the human decides, and the owner makes the change.
- After each step, run `git status`. If anything changed outside `project-planning/pstack-findings/` (and `.claude/skills/verify/` for the last row), stop and tell the human exactly what changed. Do not revert or commit it yourself.
- Commit the output before the next agent runs: `git add project-planning/pstack-findings/ && git commit -m "pstack(<skill>): <topic>"` — and for the verify skill, `git add .claude/skills/verify/ && git commit -m "pstack(create-verification-skill): verify skill"`. Uncommitted output shows up in every agent's self-check and handoff warning.

### pstack skills you never run on owned artifacts

`poteto-mode`, `reflect`, `correct`, `babysit`, `fix-ci`, `deslop`, `no-comments`, `tdd`, and `arena` or `swarm` on code — each changes files, and changes go through the owner. Never run `unslop` or `technical-writing` on anything Doc-Sync produced: its text must match the PRD exactly. Owners use the pstack skills on their own allowlist (PM: `sharpen`, `unslop`, `technical-writing`; Engineer: `tdd`, `deslop`, `typescript-best-practices`; QA: `verify`).

### What enforces this

- The `pstack-guard.sh` hook blocks: an agent calling any skill outside its allowlist; any agent writing under `~/.claude`; any agent but PM changing the status.md Module Map; an Engineer writing outside its module's Source Path and project files (or editing its own spec); and every non-framework subagent (pstack's reviewers) writing project files anywhere except `project-planning/pstack-findings/`.
- The hook does not see your own session or shell commands — the `git status` check above covers those.
