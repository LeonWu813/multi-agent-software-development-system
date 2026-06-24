#!/usr/bin/env bash
# run-qa.sh — Automated QA runner for a single module
# Usage: run-qa.sh <module-name> <project-root>
# Exit 0 = all automated checks pass; Exit 1 = any failure

set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
MODULE_NAME="${1:-}"
PROJECT_ROOT="${2:-}"

if [[ -z "$MODULE_NAME" || -z "$PROJECT_ROOT" ]]; then
  echo "[ERROR] Usage: run-qa.sh <module-name> <project-root>"
  exit 1
fi

# Normalise project root (strip trailing slash)
PROJECT_ROOT="${PROJECT_ROOT%/}"

# ---------------------------------------------------------------------------
# Tracking
# ---------------------------------------------------------------------------
FAILURES=0

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; FAILURES=$((FAILURES + 1)); }
warn() { echo "[WARN] $*"; }
info() { echo "[INFO] $*"; }

echo "========================================"
echo " QA Runner — module: $MODULE_NAME"
echo " Project root: $PROJECT_ROOT"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Check 1: Module directory exists
# ---------------------------------------------------------------------------
MODULE_DIR="$PROJECT_ROOT/project-planning/modules/$MODULE_NAME"

if [[ -d "$MODULE_DIR" ]]; then
  pass "Module directory exists: $MODULE_DIR"
else
  fail "Module directory not found: $MODULE_DIR"
fi

# ---------------------------------------------------------------------------
# Check 2: Module spec exists
# ---------------------------------------------------------------------------
SPEC_FILE="$MODULE_DIR/spec.md"
if [[ -f "$SPEC_FILE" ]]; then
  pass "Module spec found: $SPEC_FILE"
else
  fail "Module spec not found at $SPEC_FILE — QA cannot verify without a spec"
fi

# ---------------------------------------------------------------------------
# Check 3: Read test command from production.md
# ---------------------------------------------------------------------------
PRODUCTION_MD="$PROJECT_ROOT/project-planning/production.md"
TEST_CMD=""

if [[ ! -f "$PRODUCTION_MD" ]]; then
  warn "production.md not found at $PRODUCTION_MD — skipping automated test run"
else
  # Try several common formats:
  #   Test: <cmd>
  #   Test Command: <cmd>
  #   test_command: <cmd>
  #   "test": "<cmd>"    (JSON-ish)
  TEST_CMD=$(grep -iE '^\s*(test command|test_command|test)\s*[:=]\s*' "$PRODUCTION_MD" \
    | head -1 \
    | sed -E 's/^\s*(test command|test_command|test)\s*[:=]\s*//I' \
    | sed 's/^["'"'"']//; s/["'"'"']$//' \
    | xargs) || true

  if [[ -z "$TEST_CMD" ]]; then
    warn "No test command found in $PRODUCTION_MD — skipping automated test run"
    warn "Add a line like 'Test Command: npm test' to production.md to enable this check"
  else
    info "Test command found: $TEST_CMD"
  fi
fi

# ---------------------------------------------------------------------------
# Check 4: Run the test suite (if command was found)
# ---------------------------------------------------------------------------
if [[ -n "$TEST_CMD" ]]; then
  echo ""
  echo "--- Running test suite ---"
  echo "  Command: $TEST_CMD"
  echo "  Working directory: $PROJECT_ROOT"
  echo ""

  # Capture stdout+stderr together; preserve exit code without set -e killing us
  TEST_OUTPUT=""
  TEST_EXIT=0
  TEST_OUTPUT=$(cd "$PROJECT_ROOT" && eval "$TEST_CMD" 2>&1) || TEST_EXIT=$?

  echo "$TEST_OUTPUT"
  echo ""
  echo "--- Test suite exit code: $TEST_EXIT ---"
  echo ""

  # ---------------------------------------------------------------------------
  # Parse pass/fail counts from common test runner output formats
  # Formats handled:
  #   "X tests passed, Y failed"        (generic)
  #   "X passing, Y failing"            (Mocha)
  #   "X passed, Y failed"              (Jest summary / pytest)
  #   "Tests: X passed, Y failed"       (Jest verbose)
  #   "X test(s) passed"                (no failures line)
  # ---------------------------------------------------------------------------
  PARSED_PASS=""
  PARSED_FAIL=""

  # Format: "X passing" / "Y failing" (Mocha style — two separate lines)
  if echo "$TEST_OUTPUT" | grep -qiE '[0-9]+ passing'; then
    PARSED_PASS=$(echo "$TEST_OUTPUT" | grep -iE '[0-9]+ passing' | grep -oE '[0-9]+' | head -1)
  fi
  if echo "$TEST_OUTPUT" | grep -qiE '[0-9]+ failing'; then
    PARSED_FAIL=$(echo "$TEST_OUTPUT" | grep -iE '[0-9]+ failing' | grep -oE '[0-9]+' | head -1)
  fi

  # Format: "X passed, Y failed" or "X tests passed, Y failed" (Jest/pytest/generic)
  if [[ -z "$PARSED_PASS" ]] && echo "$TEST_OUTPUT" | grep -qiE '[0-9]+ (tests? )?passed'; then
    PARSED_PASS=$(echo "$TEST_OUTPUT" | grep -iE '[0-9]+ (tests? )?passed' | grep -oE '[0-9]+' | head -1)
  fi
  if [[ -z "$PARSED_FAIL" ]] && echo "$TEST_OUTPUT" | grep -qiE '[0-9]+ (tests? )?failed'; then
    PARSED_FAIL=$(echo "$TEST_OUTPUT" | grep -iE '[0-9]+ (tests? )?failed' | grep -oE '[0-9]+' | head -1)
  fi

  # Report parsed counts
  if [[ -n "$PARSED_PASS" || -n "$PARSED_FAIL" ]]; then
    PASS_DISPLAY="${PARSED_PASS:-unknown}"
    FAIL_DISPLAY="${PARSED_FAIL:-0}"
    info "Parsed test results — passed: $PASS_DISPLAY, failed: $FAIL_DISPLAY"
  else
    warn "Could not parse pass/fail counts from test output — inspect output above manually"
  fi

  # Evaluate result
  if [[ $TEST_EXIT -eq 0 ]]; then
    if [[ -n "$PARSED_FAIL" && "$PARSED_FAIL" -gt 0 ]]; then
      fail "Test suite exited 0 but parsed $PARSED_FAIL failing test(s) — investigate output"
    else
      pass "Test suite passed (exit 0)"
    fi
  else
    fail "Test suite failed (exit $TEST_EXIT)"
  fi
else
  warn "Automated test run skipped — no test command configured"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
if [[ $FAILURES -eq 0 ]]; then
  echo "[PASS] All automated checks passed"
  echo "       Manual verification of judgment-based checklist items still required."
  echo "       See SKILL.md core_checklist."
else
  echo "[FAIL] $FAILURES automated check(s) failed — see above"
fi
echo "========================================"

exit $((FAILURES > 0 ? 1 : 0))
