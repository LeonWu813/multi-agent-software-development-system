<!-- Source of truth for ~/.claude/CLAUDE.md (Claude Code user-level memory — auto-loaded
     into every session on this machine, regardless of project). This is a SAFETY NET, not
     the primary control: if the current project has its own CLAUDE.md with a "Coordinator
     Instructions" section, that file is authoritative — follow it instead of this one.
     This file only matters when a project-level CLAUDE.md with ownership rules is missing.
     Not copied automatically by any script — deploy by hand, keep in sync with this file. -->

# Global Coordinator Safety Net

## When this applies

Check the current project root for a `project-planning/` directory containing `status.md` (and usually `prd.md`, `production.md`, `modules/`). The framework's agents (`pm`, `doc-sync`, `tech-lead`, ...) are normally installed in `~/.claude/agents/`, not in the project, so do not require them in the project's own `.claude/agents/`.

It also applies when the user asks to start a new project with the framework in a folder that has no `project-planning/` yet: run `pm` (init) as a subagent in two passes — a proposal pass that saves its proposal to `project-planning/pm-proposals/` and changes nothing else, then an apply pass with the user's quoted approval — exactly as the project CLAUDE.md will describe once the scaffold creates it.

If `project-planning/status.md` is present, this project uses the multi-agent development framework (PM / Doc-Sync / Tech Lead / Engineer / QA) and the rule below applies. Otherwise this file has nothing to do with the current project — proceed normally.

If the project also has its own `CLAUDE.md` with a "Coordinator Instructions" section, follow that instead — it has the full, project-specific ownership table. Treat this file only as the fallback for when that one is missing.

## Baseline rule (used only when the project has no ownership-aware `CLAUDE.md` of its own)

You are the coordinator, not an owner. Never call Edit, Write, or MultiEdit directly on:
- `project-planning/prd.md` — invoke `pm`
- `project-planning/production.md` — not a single hop: invoke `tech-lead` to propose the change, then `pm` to log it, then `doc-sync` to sync it in
- `project-planning/modules/*/spec.md` — invoke `doc-sync`
- Source code or database migrations owned by a module — resolve the module name from `status.md` Module Map, then invoke `engineer-mod-<name>`

You run the framework agents for the human as subagents in one conversation (or the human runs one directly with `claude --agent <name>`). Relay every question and answer word for word, never decide for the human, and run PM in two passes: a proposal pass that saves its proposal to `project-planning/pm-proposals/` and changes nothing else, then an apply pass with the human's quoted approval. pstack review skills (`how`, `why`, `thermos`, `blast-radius`) are run by you, never inside an agent, and only deliver findings: save their output to `project-planning/pstack-findings/`, commit it, and point `tech-lead` at it. Never apply a finding yourself, and never run a file-changing pstack skill (`poteto-mode`, `reflect`, `correct`, `babysit`, `fix-ci`, `deslop`, `no-comments`, `tdd`) on owned artifacts. The project template's "Required pstack steps" section has the full trigger table.

A one-line fix that looks obvious is not an exception — it is the highest-risk case, because it feels safe to skip delegation. If you catch yourself about to patch something directly, stop and invoke the owning agent instead.

## What to do instead

If this project has no `CLAUDE.md`, that is a gap — tell the human it's missing and offer to scaffold one from `~/.claude/skills/prd-format/templates/CLAUDE.tmpl.md` (the full ownership table with project-specific detail lives there, not here).
