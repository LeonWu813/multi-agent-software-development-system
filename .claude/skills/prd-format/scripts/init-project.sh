#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# init-project.sh
# Scaffolds the project-planning/ directory for a new project.
# Usage: init-project.sh [PROJECT_ROOT]
#   PROJECT_ROOT defaults to the current working directory if not supplied.
# ---------------------------------------------------------------------------

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SKILL_DIR/templates/prd.tmpl.md"
CLAUDE_TEMPLATE="$SKILL_DIR/templates/CLAUDE.tmpl.md"
SETTINGS_TEMPLATE="$SKILL_DIR/templates/settings.tmpl.json"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: Template not found at $TEMPLATE" >&2
  echo "       Ensure the prd-format skill is fully installed before running this script." >&2
  exit 1
fi

if [[ ! -f "$CLAUDE_TEMPLATE" ]]; then
  echo "ERROR: Template not found at $CLAUDE_TEMPLATE" >&2
  echo "       Ensure the prd-format skill is fully installed before running this script." >&2
  exit 1
fi

if [[ ! -f "$SETTINGS_TEMPLATE" ]]; then
  echo "ERROR: Template not found at $SETTINGS_TEMPLATE" >&2
  echo "       Ensure the prd-format skill is fully installed before running this script." >&2
  exit 1
fi

PROJECT_ROOT="${1:-$(pwd)}"

if [[ -f "$PROJECT_ROOT" ]]; then
  echo "ERROR: PROJECT_ROOT '$PROJECT_ROOT' is a file, not a directory." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helper: print status line
# ---------------------------------------------------------------------------
created() { echo "Created:                  $1"; }
skipped() { echo "Skipped (already exists): $1"; }

# ---------------------------------------------------------------------------
# Create directory structure (idempotent)
# ---------------------------------------------------------------------------
DIRS=(
  "$PROJECT_ROOT/project-planning"
  "$PROJECT_ROOT/project-planning/modules"
  "$PROJECT_ROOT/project-planning/retrospective"
  "$PROJECT_ROOT/project-planning/retrospective/drafts"
)

for dir in "${DIRS[@]}"; do
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
    created "$dir/"
  else
    skipped "$dir/"
  fi
done

# ---------------------------------------------------------------------------
# Copy prd.md from template (skip if already exists)
# ---------------------------------------------------------------------------
PRD_DEST="$PROJECT_ROOT/project-planning/prd.md"
if [[ ! -f "$PRD_DEST" ]]; then
  cp "$TEMPLATE" "$PRD_DEST"
  created "$PRD_DEST"
else
  skipped "$PRD_DEST"
fi

# ---------------------------------------------------------------------------
# Copy CLAUDE.md from template (skip if already exists — never overwrite a
# project's existing CLAUDE.md; if one exists, tell the human to merge by hand)
# ---------------------------------------------------------------------------
CLAUDE_DEST="$PROJECT_ROOT/CLAUDE.md"
if [[ ! -f "$CLAUDE_DEST" ]]; then
  cp "$CLAUDE_TEMPLATE" "$CLAUDE_DEST"
  created "$CLAUDE_DEST"
else
  skipped "$CLAUDE_DEST"
  echo "  NOTE: $CLAUDE_DEST already exists and was not modified. Manually merge the" >&2
  echo "        Coordinator Instructions section from $CLAUDE_TEMPLATE so ownership" >&2
  echo "        rules are enforced in this project." >&2
fi

# ---------------------------------------------------------------------------
# Copy .claude/settings.json from template: allow rules for the writes the flow
# always needs (project-planning/ files, git add/commit/tag), so Claude Code's
# auto-mode permission check does not refuse a PM apply pass or an agent commit.
# Never modify an existing file — permission rules are the human's; list what
# is missing instead.
# ---------------------------------------------------------------------------
SETTINGS_DEST="$PROJECT_ROOT/.claude/settings.json"
if [[ ! -f "$SETTINGS_DEST" ]]; then
  mkdir -p "$PROJECT_ROOT/.claude"
  cp "$SETTINGS_TEMPLATE" "$SETTINGS_DEST"
  created "$SETTINGS_DEST"
else
  skipped "$SETTINGS_DEST"
  MISSING=$(python3 - "$SETTINGS_TEMPLATE" "$SETTINGS_DEST" <<'PY' 2>/dev/null || true
import json, sys
want = json.load(open(sys.argv[1]))["permissions"]["allow"]
try:
    have = json.load(open(sys.argv[2])).get("permissions", {}).get("allow", [])
except (OSError, ValueError, AttributeError):
    have = []
print("\n".join(r for r in want if r not in have))
PY
)
  if [[ -n "$MISSING" ]]; then
    echo "  NOTE: $SETTINGS_DEST was not modified. Without these allow rules, Claude Code's" >&2
    echo "        permission check may refuse agents' planning writes and commits. Add them to" >&2
    echo "        \"permissions\": { \"allow\": [...] } yourself:" >&2
    while IFS= read -r rule; do echo "          \"$rule\"" >&2; done <<< "$MISSING"
  fi
fi

# ---------------------------------------------------------------------------
# Create status.md from heredoc (skip if already exists)
# ---------------------------------------------------------------------------
STATUS_DEST="$PROJECT_ROOT/project-planning/status.md"
if [[ ! -f "$STATUS_DEST" ]]; then
  cat > "$STATUS_DEST" << 'EOF'
# Project Status

## Last Action
<!-- Machine-readable block — handoff.sh parses this section -->
agent:
mode:
module:
result:
timestamp:

## Current Phase
<!-- Set by Doc-Sync at initial sync; PM advances it at each checkpoint and updates it when a change adds a module to the current phase. -->


## Phase Plan


## Build Config
<!-- Filled by PM at finalize. PM asks the user for the project's build, lint, and test
     commands and writes them here. Doc-Sync copies these to production.md Shared Conventions
     during the initial sync. Leave a value blank if that step doesn't apply. -->

Build:
Lint:
Test:

## PM Updates


## Tech Lead Reviews


## Sync Reports


## Decisions


## Module Map

<!-- Filled by PM at finalize, after the user confirms directory names and source paths.
     Source Path is the code this module owns (folders, files, or filename patterns such as
     supabase/migrations/*_mod_003_* when one folder holds several modules' files): the Engineer's write scope, the self-check
     boundary, and what pstack-guard.sh enforces. Shared code belongs to exactly one module.
     Format:
     | MOD-ID  | Directory        | Module Name    | Source Path              |
     |---------|------------------|----------------|--------------------------|
     | MOD-001 | mod-login        | User Login     | src/login/               |
     Source Paths should not overlap or nest (src/ and src/ui/). Where one folder holds several
     modules' files, use filename patterns; the most specific match owns each file.

     Project files are root-level files no single module's code lives in (manifests,
     lockfiles, .env.example, CI config). One module owns them all; its Engineer is the only
     one who may change them. One line, directly under the table:
     Project files: mod-login | package.json, package-lock.json, .env.example, .github/
-->

## Checkpoint History


## Skill Recommendations

EOF
  created "$STATUS_DEST"
else
  skipped "$STATUS_DEST"
fi

# ---------------------------------------------------------------------------
# Git: every agent commits its work, so the project must be a repository
# ---------------------------------------------------------------------------
if ! git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$PROJECT_ROOT" init -q && echo "  created  git repository at $PROJECT_ROOT"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "Project planning scaffold complete."
echo "Next steps:"
echo "  1. Open $PRD_DEST and fill in every section."
echo "  2. Mark unresolved items with [DECISION NEEDED: <description>]."
echo "  3. Review the completed draft against references/anti-patterns.md."
echo "  4. Run the quality checklist in SKILL.md before handoff."
echo "  5. $CLAUDE_DEST was scaffolded with Coordinator Instructions (ownership"
echo "     rules for planning docs and source code) — keep this section intact."
echo "  6. $SETTINGS_DEST pre-approves planning writes and git add/commit/tag."
echo "     Project allow rules apply once you accept the workspace trust dialog."

exit 0
