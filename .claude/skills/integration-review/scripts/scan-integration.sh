#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# scan-integration.sh
# Automated first-pass scan for cross-module conflicts. This is a LEAD LIST,
# not a verdict — every hit still needs Tech Lead's manual judgment before it
# becomes a finding in integration-review.md. Never fails the build; always
# exits 0. Tech-stack agnostic — checks are heuristic greps, not compiler-level.
#
# Usage: scan-integration.sh [PROJECT_ROOT]
#   PROJECT_ROOT defaults to the current working directory if not supplied.
# ---------------------------------------------------------------------------

PROJECT_ROOT="${1:-$(pwd)}"
STATUS_MD="$PROJECT_ROOT/project-planning/status.md"

if [[ ! -f "$STATUS_MD" ]]; then
  echo "ERROR: $STATUS_MD not found — is PROJECT_ROOT correct?" >&2
  exit 1
fi

echo "=== Integration Scan — $PROJECT_ROOT ==="
echo ""

# ---------------------------------------------------------------------------
# 1. Module directories from the Module Map in status.md
# ---------------------------------------------------------------------------
MODULE_DIRS=$(grep -oE '\| mod-[a-z0-9-]+' "$STATUS_MD" | tr -d '| ' | sort -u || true)

if [[ -z "$MODULE_DIRS" ]]; then
  echo "No module directories found in status.md Module Map — nothing to scan."
  exit 0
fi

echo "Modules found: $(echo "$MODULE_DIRS" | tr '\n' ' ')"
echo ""

# ---------------------------------------------------------------------------
# 2. Migration filename/prefix collisions (common migration directory names)
# ---------------------------------------------------------------------------
echo "--- Migration filename collisions ---"
FOUND_MIGRATIONS=0
for dir in "$PROJECT_ROOT/supabase/migrations" "$PROJECT_ROOT/migrations" "$PROJECT_ROOT/db/migrations"; do
  if [[ -d "$dir" ]]; then
    FOUND_MIGRATIONS=1
    echo "Checking $dir"
    ls "$dir" 2>/dev/null | sed -E 's/^([0-9]+).*/\1/' | sort | uniq -d | while read -r prefix; do
      echo "  POTENTIAL CONFLICT: multiple migrations share prefix '$prefix':"
      ls "$dir" | grep "^$prefix" | sed 's/^/    /'
    done
  fi
done
[[ "$FOUND_MIGRATIONS" -eq 0 ]] && echo "  No standard migration directory found — skip or check manually."
echo ""

# ---------------------------------------------------------------------------
# 3. Integration Points referenced files — check existence
# ---------------------------------------------------------------------------
echo "--- Integration Points file references ---"
for dir in $MODULE_DIRS; do
  SPEC="$PROJECT_ROOT/project-planning/modules/$dir/spec.md"
  [[ -f "$SPEC" ]] || continue
  REFS=$(awk '/^## Integration Points/{flag=1; next} /^## /{flag=0} flag' "$SPEC" | grep -oE '`[a-zA-Z0-9_./-]+\.[a-zA-Z]+`' | tr -d '`' | sort -u || true)
  for ref in $REFS; do
    if [[ -n "$ref" && ! -f "$PROJECT_ROOT/$ref" ]]; then
      echo "  $dir spec references '$ref' — file not found at that path (may be unimplemented or path changed)"
    fi
  done
done
echo ""

# ---------------------------------------------------------------------------
# 4. Duplicate route/endpoint string literals across module source directories
# ---------------------------------------------------------------------------
echo "--- Possible duplicate route/endpoint definitions ---"
if command -v grep >/dev/null 2>&1; then
  grep -rnoE "(\.get|\.post|\.put|\.delete|\.route)\(['\"][a-zA-Z0-9/_-]+['\"]" \
    --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" \
    "$PROJECT_ROOT/src" 2>/dev/null | sort | uniq -c | sort -rn | awk '$1 > 1' | head -20 || true
fi
echo ""

echo "=== Scan complete — treat every line above as a candidate, not a confirmed finding ==="
exit 0
