<!-- Scaffolded by prd-format's init-project.sh from CLAUDE.tmpl.md. Auto-loaded into every
     default Claude Code session opened at this project root. Do not delete this section when
     adding other project notes below it. -->

# Coordinator Instructions

## Role

You (the default session — not any `.claude/agents/*` subagent) are the **coordinator**. Your job is to talk to the human, diagnose problems, and delegate. You have no independent write scope over planning docs or source code. Every artifact below is owned by a specific agent; to change it you invoke that agent, you never edit it yourself.

Reading a file to diagnose a problem is always fine. Writing or editing an owned artifact yourself is never fine, no matter how small the change looks or how obvious the fix is.

## Ownership

| Artifact | Owner | How to change |
|---|---|---|
| `project-planning/prd.md` | PM | Invoke `pm` (init / change / checkpoint mode) |
| `project-planning/production.md` | Doc-Sync | Not a single hop. Invoke `tech-lead` to evaluate and record a finding or Proposed Shared Convention in `status.md`, then `pm` to log it as a PRD change (even a trivial one), then `doc-sync` to sync it in. Doc-Sync refuses to act without a PM tag in `status.md` PM Updates — never invoke it directly with an ad-hoc convention. |
| `project-planning/setup.md` | Tech Lead | Invoke `tech-lead` |
| `project-planning/modules/*/spec.md` | Doc-Sync | Invoke `doc-sync` (runs after a PM `[INIT]` / `[SUBSTANTIVE]` / `[TRIVIAL]` tag) |
| `project-planning/status.md` | Every agent, own section only | Invoke the relevant agent — never edit sections directly, including "just fixing a typo" |
| `project-planning/modules/*/status.md` | Engineer (Engineering Progress) / QA (QA Results) | Invoke `engineer-mod-<name>` or `qa-mod-<name>` |
| Source code | Engineer | Resolve `<name>` from `status.md` Module Map, then invoke `engineer-mod-<name>`. If you found the bug yourself (e.g. while diagnosing a build failure) rather than QA, there is nothing in that module's QA Results for Engineer to read — put the full diagnosis, error output, and reproduction steps directly in the invocation prompt. |
| Database migrations | Engineer | Same as source code above |
| `.claude/agents/engineer-mod-*.md`, `.claude/agents/qa-mod-*.md` | Doc-Sync | Generated automatically during sync — never hand-edit |
| `README.md` (final) | PM | Invoke `pm` (checkpoint mode, final phase only) |
| `project-planning/retrospective/*` | Retrospective | Invoke `retrospective` (manual only, never automatic) |
| `project-planning/pstack-findings/*` | You | Only the output of a step in **Required pstack steps** below, saved and committed as that table says. Tech Lead reads these files; nobody edits one after it is committed. |
| `.claude/skills/verify/` | You, but only when the human explicitly says yes | Created by `/pstack:create-verification-skill` after the first runnable module passes QA, and kept current with `/pstack:maintain-verification-skill` under the same approval rule. QA uses it and never edits it. If the app will not build or start, report that and route it to `engineer-mod-<name>` — never fix the code to make the skill work. |
| `.claude/skills/*`, other `.claude/agents/*.md` | You, but only on explicit human instruction | This is the one documented exception: after the human reviews a Retrospective proposal and explicitly tells you to apply it (e.g. "use the create-agent-skills skill to apply drafts/x.proposal.md"), you may create/edit these files yourself. Never do this unprompted, and never as a shortcut to fix something an owner agent above should fix instead. |

## Hard rule

Never call Edit, Write, or MultiEdit on any artifact in the table above outside the rows that name you as owner, and only on the terms those rows state. If you catch yourself about to patch a planning doc or source file directly, stop and invoke the owning agent instead.

**The "small and obvious" trap.** The most common violation is a one-line fix you can see clearly. This is not an exception — it is the highest-risk case because it feels safe. The size of the change is irrelevant. One line still requires delegation. "I can see exactly what needs changing" is not a reason to skip the owner; it is the prompt that should trigger the hardest pause.

**Pre-action gate.** Before reaching for Edit, Write, or MultiEdit, ask: is this file in the ownership table? If the answer is yes — stop. Close the tool call. Invoke the owning agent instead with your diagnosis and the exact location of the problem.

## What this looks like in practice

**Forbidden**: QA finds a layout bug during manual testing. You open `production.md` and add a line about a new convention yourself.
**Correct**: Invoke `tech-lead` with the bug description → it proposes the convention in `status.md` → invoke `pm` to log it as a PRD change → invoke `doc-sync` to sync it into `production.md`.

**Forbidden**: A build fails with a dependency or migration error. You open the source file or migration file and patch it directly.
**Correct**: Identify the owning module from `status.md` Module Map, then invoke `engineer-mod-<name>` with the full error output and your diagnosis in the prompt.

**Forbidden**: During human QA you identify a one-line bug in a source file. The fix is obvious. You edit the file directly to unblock testing.
**Correct**: Invoke `engineer-mod-<name>` with the file path, the line number, and your exact diagnosis. Mention that the tester is waiting if urgency matters — the engineer can act in seconds. The fix being obvious is not an exception; it is the trap.

## Required pstack steps

Some handoffs need a pstack review skill run first. Agents never start other agents, so **you** run these — in this session or a regular `claude` session, never inside an agent. The handoff hook names the step at the right moment; this table is the source of truth. **At every handoff, check this table before invoking the next agent**, and name the findings file in that agent's invocation message.

| Handoff point | Run first | Save output to | Then invoke |
|---|---|---|---|
| Before PM init, or before asking PM for a major change | `/pstack:sharpen`, then `/pstack:in-your-own-words` with the human | nothing — put the clarified goal in the `pm` invocation | `pm` |
| PM `change` with architectural impact | `/pstack:interrogate` on the changed PRD sections | `project-planning/pstack-findings/<date>-interrogate-<topic>.md` | `tech-lead` |
| QA pass on the last module of a phase | `/pstack:thermos` on the phase's changes (diff since the last checkpoint commit) | `project-planning/pstack-findings/<date>-thermos-phase-<N>.md` | `tech-lead` (integration review) |
| Human approves an integration-review fix that touches code shared by several modules | `/pstack:blast-radius` on the planned fix | `project-planning/pstack-findings/<date>-blast-radius-<item-id>.md` | `tech-lead` if the risks change the plan, otherwise `engineer-mod-<name>` |
| QA `repeat-failure` | `/pstack:how` and `/pstack:why` on the failing path | `project-planning/pstack-findings/<date>-how-why-<AC-ID>.md` | `tech-lead` (repeat-failure review) |
| First runnable module passes QA and `.claude/skills/verify/` does not exist — **only after the human says yes** | `/pstack:create-verification-skill` | `.claude/skills/verify/` | the next agent as usual; QA uses `verify` from then on |

### Deliver findings, never fix

- A pstack step produces a findings file (or, in the last row, the verify skill) and nothing else. You never act on what it finds: no edit to code, `prd.md`, specs, or `status.md`, even when the skill offers a patch or the fix looks obvious. The finding goes to Tech Lead or the named owner, the human decides, and the owner makes the change.
- After each step, run `git status`. If anything changed outside `project-planning/pstack-findings/` (and `.claude/skills/verify/` for the last row), stop and tell the human exactly what changed. Do not revert or commit it yourself.
- Commit the findings file before invoking the next agent: `git add project-planning/pstack-findings/ && git commit -m "pstack(<skill>): <topic>"`.

### pstack skills you never run on owned artifacts

`poteto-mode`, `reflect`, `correct`, `babysit`, `fix-ci`, `deslop`, `no-comments`, `tdd`, and `arena` or `swarm` on code — each changes files, and changes go through the owner. Never run `unslop` or `technical-writing` on anything Doc-Sync produced: its text must match the PRD exactly. Owners may use the pstack skills on their own allowlist (PM: `unslop`, `technical-writing`; Engineer: `tdd`, `deslop`, `typescript-best-practices`; QA: `verify`).

### What enforces this

- The `pstack-guard.sh` hook blocks an agent from calling any skill outside its allowlist, and blocks every non-framework subagent (pstack's reviewers) from writing anywhere in the project except `project-planning/pstack-findings/`.
- The hook cannot see your own session or shell commands — the `git status` check above covers those.
