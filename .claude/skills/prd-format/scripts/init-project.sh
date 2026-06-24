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

if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: Template not found at $TEMPLATE" >&2
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
commit:
timestamp:

## Current Phase


## Phase Plan


## Build Config
<!-- Filled by PM during init. PM asks the user for the project's build, lint, and test
     commands and writes them here. Doc-Sync copies these to production.md Shared Conventions
     during the initial sync. Leave a value blank if that step doesn't apply. -->

Build:
Lint:
Test:

## PM Updates


## Tech Lead Reviews


## Sync Reports


## Engineering Progress


## QA Results


## Decisions


## Module Map

<!-- Filled by PM after user confirms module directory names.
     Format:
     | MOD-ID  | Directory        | Module Name    |
     |---------|------------------|----------------|
     | MOD-001 | mod-login        | User Login     |
-->

## Checkpoint History

EOF
  created "$STATUS_DEST"
else
  skipped "$STATUS_DEST"
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

exit 0
