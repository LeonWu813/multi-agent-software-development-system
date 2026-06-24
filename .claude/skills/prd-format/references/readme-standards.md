# README Writing Standards

Reference for PM when producing `README.md` at final project checkpoint.

---

## Essential Sections (must have all)

| Section | What goes in it |
|---|---|
| Title + one-liner | Project name and one sentence describing what it does and who it's for |
| Description | The problem it solves and why it exists — before installation; no assumed context |
| Features | Bullet list of every user-facing capability; one line per feature |
| Tech Stack | Table: Component \| Name + Version \| Notes — match `production.md` exactly |
| Architecture | How the layers connect; data flow for each major operation; a diagram if helpful |
| Local Setup | Step-by-step; all prerequisites listed first; every command in a code block |
| Scripts | Table of every runnable command with a one-line description |

---

## Optional High-Value Sections

- **Key Design Decisions** — explain non-obvious choices (why this tech, why this pattern); saves future maintainers from re-litigating settled decisions
- **Domain Architecture** — directory layout with one-line descriptions; useful for codebases with non-obvious structure
- **Troubleshooting** — common setup failures and their fixes

---

## Writing Standards

**Tone**
- Friendly and direct — write like a colleague explaining to someone new on the team
- No corporate-speak, no marketing language
- Never use: "easy", "simple", "just", "obviously", "trivially" — these make readers feel stupid when they get stuck

**Formatting**
- Short paragraphs — 3 to 5 lines maximum, one concept per paragraph
- Use headers, bullet lists, and code blocks — never walls of text
- All terminal commands in fenced code blocks (` ``` `)
- Aim for 500–1500 words total; longer README with clear structure beats a short one that omits setup

**Accuracy**
- Setup steps must match `project-planning/setup.md` exactly
- Tech stack table must match `project-planning/production.md` exactly
- Scripts table must match actual `package.json` scripts (or equivalent)
- Never describe behavior that hasn't been implemented

---

## Quality Checklist

Run before committing `README.md`:

- [ ] Title and one-line description at the top — tells a newcomer what this is in one sentence
- [ ] Description explains the *problem* it solves before explaining how to install it
- [ ] Features section covers all user-facing capabilities from the PRD
- [ ] Tech stack table present — component, name+version, notes column
- [ ] Architecture section includes data flow for the main operations
- [ ] Local setup lists all prerequisites first, then numbered steps, every command in a code block
- [ ] Scripts table covers all runnable commands
- [ ] No condescending language ("easy", "simple", "just", "obvious")
- [ ] Setup steps verified accurate against `project-planning/setup.md`
- [ ] Tech stack verified accurate against `project-planning/production.md`
- [ ] All code blocks use fenced markdown syntax
