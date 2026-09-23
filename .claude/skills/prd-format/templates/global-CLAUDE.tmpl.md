<!-- Source of truth for ~/.claude/CLAUDE.md (Claude Code user-level memory — auto-loaded
     into every session on this machine, regardless of project). This is a SAFETY NET, not
     the primary control: if the current project has its own CLAUDE.md with a "Coordinator
     Instructions" section, that file is authoritative — follow it instead of this one.
     This file only matters when a project-level CLAUDE.md with ownership rules is missing.
     Not copied automatically by any script — deploy by hand, keep in sync with this file. -->

# Global Coordinator Safety Net

## When this applies

Check the current project root for:
- `.claude/agents/pm.md`, `.claude/agents/doc-sync.md`, `.claude/agents/tech-lead.md` (or similarly named specialized agents), AND
- a `project-planning/` directory (`prd.md`, `production.md`, `status.md`, `modules/`)

If both are present, this project uses the multi-agent development framework (PM / Doc-Sync / Tech Lead / Engineer / QA) and the rule below applies. If neither is present, this file has nothing to do with the current project — proceed normally.

If the project also has its own `CLAUDE.md` with a "Coordinator Instructions" section, follow that instead — it has the full, project-specific ownership table. Treat this file only as the fallback for when that one is missing.

## Baseline rule (used only when the project has no ownership-aware `CLAUDE.md` of its own)

You are the coordinator, not an owner. Never call Edit, Write, or MultiEdit directly on:
- `project-planning/prd.md` — invoke `pm`
- `project-planning/production.md` — not a single hop: invoke `tech-lead` to propose the change, then `pm` to log it, then `doc-sync` to sync it in
- `project-planning/modules/*/spec.md` — invoke `doc-sync`
- Source code or database migrations owned by a module — resolve the module name from `status.md` Module Map, then invoke `engineer-mod-<name>`

A one-line fix that looks obvious is not an exception — it is the highest-risk case, because it feels safe to skip delegation. If you catch yourself about to patch something directly, stop and invoke the owning agent instead.

## What to do instead

If this project has no `CLAUDE.md`, that is a gap — tell the human it's missing and offer to scaffold one from `~/.claude/skills/prd-format/templates/CLAUDE.tmpl.md` (the full ownership table with project-specific detail lives there, not here).
