#!/usr/bin/env bash
set -o pipefail   # no -e or -u: this is a lead list and must always reach the end (bash 3.2 errors on empty arrays under -u)

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
# Rows of the Module Map table only (comments and the Format example are skipped).
# Columns: | MOD-ID | Directory | Module Name | Source Path |
MAP_ROWS=$(awk -F'|' '
  /^## Module Map/ {inmap=1; next}
  inmap && /^## / {exit}
  inmap && /<!--/ {incomment=1}
  inmap && incomment { if (/-->/) incomment=0; next }
  inmap && /^\|/ {
    d=$3; sp=$5
    gsub(/[`[:space:]]/, "", d); sub(/^modules\//, "", d); sub(/\/$/, "", d)
    gsub(/`/, "", sp); gsub(/^[[:space:]]+|[[:space:]]+$/, "", sp)
    if (d != "" && d != "Directory" && d !~ /^-+$/) print d "\t" sp
  }' "$STATUS_MD")
MODULE_DIRS=$(printf '%s\n' "$MAP_ROWS" | cut -f1 | sed '/^$/d' | sort -u)

# Source roots to scan: every Source Path in the Module Map, or src/ if none are recorded
SCAN_ROOTS=()
while IFS= read -r sp; do
  IFS=',' read -ra parts <<< "$sp"
  for part in "${parts[@]}"; do
    part="${part#"${part%%[![:space:]]*}"}"; part="${part%"${part##*[![:space:]]}"}"; part="${part#./}"
    [[ -n "$part" && -e "$PROJECT_ROOT/$part" ]] && SCAN_ROOTS+=("$PROJECT_ROOT/$part")
  done
done < <(printf '%s\n' "$MAP_ROWS" | cut -f2)
[[ ${#SCAN_ROOTS[@]} -eq 0 && -d "$PROJECT_ROOT/src" ]] && SCAN_ROOTS=("$PROJECT_ROOT/src")
# Drop roots nested inside another root, so no file is scanned (and counted) twice
if [[ ${#SCAN_ROOTS[@]} -gt 1 ]]; then
  KEPT=()
  for r in "${SCAN_ROOTS[@]}"; do
    r="${r%/}"; nested=0
    for o in "${SCAN_ROOTS[@]}"; do
      o="${o%/}"
      [[ "$r" != "$o" && "$r" == "$o/"* ]] && nested=1
    done
    [[ $nested -eq 0 ]] && KEPT+=("$r")
  done
  SCAN_ROOTS=($(printf '%s\n' "${KEPT[@]}" | sort -u))
fi

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
ROUTE_RE="(\.get|\.post|\.put|\.patch|\.delete|\.route)\(['\"][a-zA-Z0-9/_:{}-]+['\"]"
if [[ ${#SCAN_ROOTS[@]} -gt 0 ]]; then
  # Count each route literal across all files (no file prefix), then list where duplicates live
  grep -rhoE "$ROUTE_RE" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" \
    "${SCAN_ROOTS[@]}" 2>/dev/null | sort | uniq -d | head -20 | while IFS= read -r route; do
      echo "  DUPLICATE: $route"
      grep -rlF "$route" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" \
        "${SCAN_ROOTS[@]}" 2>/dev/null | sort -u | sed "s#^$PROJECT_ROOT/#    #"
    done
fi
echo ""

# ---------------------------------------------------------------------------
# 5. Cross-phase duplication candidates — Purpose comparison across ALL modules
#    (not just the current phase; duplication has no phase boundary)
# ---------------------------------------------------------------------------
echo "--- Module purposes (eyeball for overlapping domains — e.g. two modules both touching video/upload/auth) ---"
for dir in $MODULE_DIRS; do
  SPEC="$PROJECT_ROOT/project-planning/modules/$dir/spec.md"
  [[ -f "$SPEC" ]] || continue
  PURPOSE=$(awk '/^## Purpose/{flag=1; next} /^## /{flag=0} flag' "$SPEC" | grep -v '^<!--' | grep -v '^$' | head -1 || true)
  [[ -n "$PURPOSE" ]] && echo "  $dir: $PURPOSE"
done
echo ""

echo "--- Possible duplicate component/function names across module source directories ---"
if [[ ${#SCAN_ROOTS[@]} -gt 0 ]]; then
  grep -rhoE "(export (default )?(function|const|class) |^def |^class )[A-Za-z0-9_]+" \
    --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" \
    "${SCAN_ROOTS[@]}" 2>/dev/null | \
    sed -E 's/.*(function|const|class|def) //' | sort | uniq -c | sort -rn | awk '$1 > 1' | head -20 || true
fi
echo ""

echo "=== Scan complete — treat every line above as a candidate, not a confirmed finding ==="
exit 0
