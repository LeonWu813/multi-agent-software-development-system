#!/usr/bin/env bash
# verify-sync.sh — Doc-Sync integrity checker
# Requires: bash 3.2+ (macOS system bash compatible; no associative arrays)
# Usage: ./verify-sync.sh <path-to-project-planning-directory>
#
# Runs 6 checks against the project-planning directory.
# Prints [PASS] or [FAIL] for each check, then a summary line.
# Exit 0 = all checks passed. Exit 1 = one or more checks failed.

set -euo pipefail

PLANNING_DIR="${1:-}"

# ── Argument validation ───────────────────────────────────────────────────────

if [[ -z "$PLANNING_DIR" ]]; then
  echo "ERROR: No path provided."
  echo "Usage: $0 <path-to-project-planning-directory>"
  exit 1
fi

if [[ ! -d "$PLANNING_DIR" ]]; then
  echo "ERROR: Directory not found: $PLANNING_DIR"
  exit 1
fi

PRD="$PLANNING_DIR/prd.md"

if [[ ! -f "$PRD" ]]; then
  echo "ERROR: prd.md not found at $PRD"
  echo "The project-planning directory must contain prd.md."
  exit 1
fi

PRODUCTION="$PLANNING_DIR/production.md"
MODULES_DIR="$PLANNING_DIR/modules"
STATUS="$PLANNING_DIR/status.md"

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=6

pass() { echo "[PASS] $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "[FAIL] $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ── Module Map helpers (bash 3.2 compatible — no associative arrays) ──────────

# lookup_dir_for_mod <MOD-ID>
# Reads status.md Module Map and prints the directory name for the given MOD-ID,
# or an empty string if the MOD-ID has no entry.
lookup_dir_for_mod() {
  local mod_id="$1"
  if [[ ! -f "$STATUS" ]]; then echo ""; return; fi
  awk -v target="$mod_id" '
    /^## Module Map/ { in_map=1; next }
    in_map && /^## /  { in_map=0; next }
    in_map && /^\|/ {
      n = split($0, cols, "|")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", cols[2])
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", cols[3])
      if (cols[2] == target && cols[3] != "" && cols[3] != "Directory" && cols[3] !~ /^-+$/) {
        print cols[3]; exit
      }
    }
  ' "$STATUS"
}

# dir_in_module_map <directory-name>
# Prints "1" if the directory name appears as a mapped value in the Module Map, "0" otherwise.
dir_in_module_map() {
  local dir_name="$1"
  if [[ ! -f "$STATUS" ]]; then echo "0"; return; fi
  local found
  found=$(awk -v target="$dir_name" '
    /^## Module Map/ { in_map=1; next }
    in_map && /^## /  { in_map=0; next }
    in_map && /^\|/ {
      n = split($0, cols, "|")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", cols[3])
      if (cols[3] == target && cols[3] != "" && cols[3] != "Directory" && cols[3] !~ /^-+$/) {
        print "1"; exit
      }
    }
  ' "$STATUS")
  echo "${found:-0}"
}

# ── Check 1 ───────────────────────────────────────────────────────────────────
# Every MOD-XXX ID in prd.md has an entry in the Module Map (status.md) AND
# the mapped directory contains a spec.md.

echo ""
echo "Running check 1: Every MOD-ID in prd.md has a Module Map entry and spec.md ..."

CHECK1_FAILED=0
MOD_IDS_IN_PRD=$(grep -o 'MOD-[0-9A-Za-z_-]*' "$PRD" | sort -u)

if [[ -z "$MOD_IDS_IN_PRD" ]]; then
  pass "Check 1: No MOD-IDs found in prd.md (nothing to verify)"
else
  for mod_id in $MOD_IDS_IN_PRD; do
    dir=$(lookup_dir_for_mod "$mod_id")
    if [[ -z "$dir" ]]; then
      echo "  MISSING MAP: $mod_id — not found in status.md Module Map"
      CHECK1_FAILED=1
    elif [[ ! -f "$MODULES_DIR/$dir/spec.md" ]]; then
      echo "  MISSING SPEC: $mod_id → modules/$dir/spec.md does not exist"
      CHECK1_FAILED=1
    fi
  done
  if [[ $CHECK1_FAILED -eq 0 ]]; then
    pass "Check 1: All MOD-IDs in prd.md have a Module Map entry and a spec.md"
  else
    fail "Check 1: One or more MOD-IDs are missing a Module Map entry or spec.md (see above)"
  fi
fi

# ── Check 2 ───────────────────────────────────────────────────────────────────
# No spec.md files exist for a directory that is not in the Module Map.

echo ""
echo "Running check 2: No orphan spec.md exists outside the Module Map ..."

CHECK2_FAILED=0

if [[ ! -d "$MODULES_DIR" ]]; then
  pass "Check 2: No modules/ directory found — nothing to check"
else
  while IFS= read -r spec_file; do
    dir_name=$(basename "$(dirname "$spec_file")")
    in_map=$(dir_in_module_map "$dir_name")
    if [[ "$in_map" != "1" ]]; then
      echo "  ORPHAN: $spec_file — directory '$dir_name' has no entry in status.md Module Map"
      CHECK2_FAILED=1
    fi
  done < <(find "$MODULES_DIR" -name "spec.md" 2>/dev/null)

  if [[ $CHECK2_FAILED -eq 0 ]]; then
    pass "Check 2: All spec.md files have a corresponding Module Map entry"
  else
    fail "Check 2: One or more spec.md files have no matching Module Map entry (see above)"
  fi
fi

# ── Check 3 ───────────────────────────────────────────────────────────────────
# Every entry in prd.md's Tech Stack section appears in production.md.
# Uses a line-by-line keyword check: each non-empty, non-header line in the
# Tech Stack section of prd.md must have at least one keyword present in production.md.

echo ""
echo "Running check 3: Every Tech Stack entry in prd.md appears in production.md ..."

if [[ ! -f "$PRODUCTION" ]]; then
  fail "Check 3: production.md does not exist at $PRODUCTION"
else
  CHECK3_FAILED=0
  IN_TECH_STACK=0

  while IFS= read -r line; do
    # Detect entry into Tech Stack section (handles ## and ### headings)
    if echo "$line" | grep -qi '##\+.*tech.stack\|##\+.*technology.stack'; then
      IN_TECH_STACK=1
      continue
    fi
    # Detect exit from Tech Stack section (next ## heading that is not a sub-heading of tech stack)
    if [[ $IN_TECH_STACK -eq 1 ]] && echo "$line" | grep -q '^##'; then
      if ! echo "$line" | grep -qi 'tech.stack\|technology.stack'; then
        IN_TECH_STACK=0
        continue
      fi
    fi

    if [[ $IN_TECH_STACK -eq 1 ]]; then
      # Skip blank lines, table separators, and header rows
      stripped=$(echo "$line" | tr -d '| \t-')
      if [[ -z "$stripped" ]] || echo "$line" | grep -q '^|[-| ]*$'; then
        continue
      fi
      # Skip table header rows that contain only generic column labels
      if echo "$line" | grep -qi '^\s*|\s*component\s*|\s*name\|^\s*|\s*technology\s*|\s*stack'; then
        continue
      fi

      # Extract the first meaningful token (product name) from the line.
      # For table rows like "| Database | PostgreSQL 15.3 | |", the second column is the name.
      # For bullet lines like "- PostgreSQL 15.3", the token is the first word after the bullet.
      keyword=""
      if echo "$line" | grep -q '|'; then
        # Table row: grab second column
        keyword=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}' | awk '{print $1}')
      else
        # Bullet or plain line
        keyword=$(echo "$line" | sed 's/^[[:space:]]*[-*]\?[[:space:]]*//' | awk '{print $1}')
      fi

      keyword=$(echo "$keyword" | tr -d '[:space:]')
      if [[ -z "$keyword" ]] || [[ ${#keyword} -lt 2 ]]; then
        continue
      fi

      if ! grep -qi "$keyword" "$PRODUCTION" 2>/dev/null; then
        echo "  MISSING: Tech Stack keyword '$keyword' (from prd.md line: $line) not found in production.md"
        CHECK3_FAILED=1
      fi
    fi
  done < "$PRD"

  if [[ $CHECK3_FAILED -eq 0 ]]; then
    pass "Check 3: All Tech Stack entries from prd.md appear in production.md"
  else
    fail "Check 3: One or more Tech Stack entries from prd.md are missing in production.md (see above)"
  fi
fi

# ── Check 4 ───────────────────────────────────────────────────────────────────
# Every US-XXX ID in prd.md appears in the "## Related User Stories" section
# of at least one modules/*/spec.md. A US-ID that only appears in prose (e.g.,
# the Context section) does not count — the module must formally claim it.

echo ""
echo "Running check 4: Every US-ID in prd.md is formally claimed in a Related User Stories section ..."

CHECK4_FAILED=0
US_IDS_IN_PRD=$(grep -o 'US-[0-9A-Za-z_-]*' "$PRD" | sort -u)

if [[ -z "$US_IDS_IN_PRD" ]]; then
  pass "Check 4: No US-IDs found in prd.md (nothing to verify)"
else
  if [[ ! -d "$MODULES_DIR" ]]; then
    fail "Check 4: US-IDs found in prd.md but modules/ directory does not exist"
    CHECK4_FAILED=1
  else
    for us_id in $US_IDS_IN_PRD; do
      found=0
      while IFS= read -r spec_file; do
        # Extract only the ## Related User Stories section of each spec
        section=$(awk '/^## Related User Stories/,/^## /' "$spec_file" 2>/dev/null)
        if echo "$section" | grep -q "$us_id"; then
          found=1
          break
        fi
      done < <(find "$MODULES_DIR" -name "spec.md" 2>/dev/null)

      if [[ $found -eq 0 ]]; then
        echo "  MISSING: $us_id is in prd.md but not listed in any module's Related User Stories section"
        CHECK4_FAILED=1
      fi
    done
    if [[ $CHECK4_FAILED -eq 0 ]]; then
      pass "Check 4: All US-IDs in prd.md are formally claimed in a Related User Stories section"
    else
      fail "Check 4: One or more US-IDs in prd.md are not formally claimed in any module spec (see above)"
    fi
  fi
fi

# ── Check 5 ───────────────────────────────────────────────────────────────────
# No [AMBIGUITY] marker in any downstream doc is missing from status.md Sync Reports.

echo ""
echo "Running check 5: All [AMBIGUITY] markers in downstream docs are logged in status.md ..."

if [[ ! -f "$STATUS" ]]; then
  # If no status.md exists, check whether any downstream docs have AMBIGUITY markers
  AMBIGUITY_IN_DOCS=$(grep -rl '\[AMBIGUITY:' "$PLANNING_DIR" --include="*.md" \
    --exclude="prd.md" --exclude="status.md" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$AMBIGUITY_IN_DOCS" -gt 0 ]]; then
    fail "Check 5: [AMBIGUITY] markers found in downstream docs but status.md does not exist"
  else
    pass "Check 5: No [AMBIGUITY] markers in downstream docs and no status.md (consistent)"
  fi
else
  CHECK5_FAILED=0
  # Collect all unique AMBIGUITY descriptions from downstream docs (not prd.md, not status.md)
  while IFS= read -r ambig_line; do
    # Extract the description inside the marker
    description=$(echo "$ambig_line" | grep -o '\[AMBIGUITY:[^]]*\]' | head -1)
    if [[ -z "$description" ]]; then
      continue
    fi
    # Extract a short keyword from the description for fuzzy matching in status.md
    # Use the first 40 characters of the description content
    keyword=$(echo "$description" | sed 's/\[AMBIGUITY: *//' | sed 's/\].*//' | cut -c1-40)
    if ! grep -qi "$keyword" "$STATUS" 2>/dev/null; then
      echo "  UNLOGGED: $description"
      echo "           (found in a downstream doc but no matching entry in status.md Sync Reports)"
      CHECK5_FAILED=1
    fi
  done < <(grep -rh '\[AMBIGUITY:' "$PLANNING_DIR" --include="*.md" \
    --exclude="prd.md" --exclude="status.md" 2>/dev/null)

  if [[ $CHECK5_FAILED -eq 0 ]]; then
    pass "Check 5: All [AMBIGUITY] markers in downstream docs are logged in status.md"
  else
    fail "Check 5: One or more [AMBIGUITY] markers in downstream docs are not logged in status.md (see above)"
  fi
fi

# ── Check 6 ───────────────────────────────────────────────────────────────────
# Phase names in prd.md Phases section appear in status.md Phase Plan section.

echo ""
echo "Running check 6: Phase names from prd.md appear in status.md Phase Plan ..."

if [[ ! -f "$STATUS" ]]; then
  fail "Check 6: status.md does not exist at $STATUS"
else
  CHECK6_FAILED=0
  IN_PHASES_PRD=0
  PHASE_NAMES=""

  # Extract phase names from prd.md Phases / Milestones section
  while IFS= read -r line; do
    if echo "$line" | grep -qi '##\+.*phase\|##\+.*milestone'; then
      IN_PHASES_PRD=1
      continue
    fi
    if [[ $IN_PHASES_PRD -eq 1 ]] && echo "$line" | grep -q '^##'; then
      if ! echo "$line" | grep -qi 'phase\|milestone'; then
        IN_PHASES_PRD=0
        continue
      fi
    fi
    if [[ $IN_PHASES_PRD -eq 1 ]]; then
      # Look for lines that name a phase: "Phase 1", "Phase One", "Milestone:", bold entries, etc.
      if echo "$line" | grep -qi 'phase[[:space:]]*[0-9a-zA-Z]\|milestone[[:space:]]*[0-9a-zA-Z]\|^\s*[-*]\s*\*\*'; then
        # Extract the meaningful part (strip markdown bullets and bold markers)
        phase_name=$(echo "$line" | sed 's/^[[:space:]]*[-*]\?[[:space:]]*//' \
                                  | sed 's/\*\*//g' \
                                  | sed 's/|//g' \
                                  | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
                                  | cut -c1-50)
        if [[ -n "$phase_name" ]] && [[ ${#phase_name} -gt 3 ]]; then
          PHASE_NAMES="${PHASE_NAMES}
${phase_name}"
        fi
      fi
    fi
  done < "$PRD"

  if [[ -z "$PHASE_NAMES" ]]; then
    pass "Check 6: No phase names found in prd.md Phases section (nothing to verify)"
  else
    # Check that status.md Phase Plan section contains each phase name
    IN_PHASE_PLAN_STATUS=0
    PHASE_PLAN_CONTENT=""

    while IFS= read -r line; do
      if echo "$line" | grep -qi '##\+.*phase.plan\|##\+.*phase plan'; then
        IN_PHASE_PLAN_STATUS=1
        continue
      fi
      if [[ $IN_PHASE_PLAN_STATUS -eq 1 ]] && echo "$line" | grep -q '^##'; then
        if ! echo "$line" | grep -qi 'phase.plan\|phase plan'; then
          IN_PHASE_PLAN_STATUS=0
          continue
        fi
      fi
      if [[ $IN_PHASE_PLAN_STATUS -eq 1 ]]; then
        PHASE_PLAN_CONTENT="${PHASE_PLAN_CONTENT}
${line}"
      fi
    done < "$STATUS"

    if [[ -z "$PHASE_PLAN_CONTENT" ]]; then
      fail "Check 6: status.md has no Phase Plan section (or it is empty)"
    else
      while IFS= read -r phase_name; do
        [[ -z "$phase_name" ]] && continue
        # Use first 20 chars as a fuzzy keyword
        keyword=$(echo "$phase_name" | cut -c1-20 | tr '[:upper:]' '[:lower:]')
        if ! echo "$PHASE_PLAN_CONTENT" | grep -qi "$keyword"; then
          echo "  MISSING: Phase name '$phase_name' (from prd.md) not found in status.md Phase Plan"
          CHECK6_FAILED=1
        fi
      done <<< "$PHASE_NAMES"
      if [[ $CHECK6_FAILED -eq 0 ]]; then
        pass "Check 6: All phase names from prd.md appear in status.md Phase Plan"
      else
        fail "Check 6: One or more phase names from prd.md are missing from status.md Phase Plan (see above)"
      fi
    fi
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "──────────────────────────────────────────────"
echo "Summary: ${PASS_COUNT}/${TOTAL} checks passed"
echo "──────────────────────────────────────────────"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "All checks passed. Sync is consistent."
  exit 0
else
  echo "${FAIL_COUNT} check(s) failed. Fix the issues above and re-run."
  exit 1
fi
