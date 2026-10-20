#!/usr/bin/env bash
# self-check.sh — Pre-QA automated checks for Engineer agent
# Usage: self-check.sh <module-name> <project-root>

MODULE_NAME="${1:-}"
PROJECT_ROOT="${2:-}"

if [[ -z "$MODULE_NAME" || -z "$PROJECT_ROOT" ]]; then
  echo "Usage: $0 <module-name> <project-root>" >&2
  exit 1
fi

PRODUCTION_MD="$PROJECT_ROOT/project-planning/production.md"
MODULE_DIR="$PROJECT_ROOT/project-planning/modules/$MODULE_NAME"

if [[ ! -d "$PROJECT_ROOT" ]]; then
  echo "ERROR: project-root not found: $PROJECT_ROOT" >&2
  exit 1
fi

if [[ ! -d "$MODULE_DIR" ]]; then
  echo "ERROR: module directory not found: $MODULE_DIR" >&2
  echo "       Expected modules to live under project-planning/modules/<module-name>/" >&2
  exit 1
fi

# Scope check runs BEFORE build and test, so their output (caches, bytecode, coverage) is never
# mistaken for the engineer's work. module_scope.py is the same check handoff.sh runs when the
# Engineer stops: everything changed since the base the hook recorded at the last handoff.
SCOPE_PY="$(cd "$(dirname "$0")" && pwd)/module_scope.py"
SCOPE_OUT=""; SCOPE_RC=0
if git -C "$PROJECT_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
  SCOPE_OUT=$(python3 "$SCOPE_PY" changed "$PROJECT_ROOT" "$MODULE_NAME" 2>&1); SCOPE_RC=$?
else
  SCOPE_RC=4
fi

PASS_COUNT=0
FAIL_COUNT=0
FAILURES=()

pass() {
  echo "[PASS] $1"
  (( PASS_COUNT++ )) || true
}

fail() {
  echo "[FAIL] $1"
  (( FAIL_COUNT++ )) || true
  FAILURES+=("$1")
}

skip() {
  echo "[SKIP] $1"
}

# ---------------------------------------------------------------------------
# Extract commands from production.md
# ---------------------------------------------------------------------------
BUILD_CMD=""
LINT_CMD=""
TEST_CMD=""

if [[ ! -f "$PRODUCTION_MD" ]]; then
  fail "production.md not found at $PRODUCTION_MD — build, lint and tests cannot run (Doc-Sync creates it at the initial sync)"
else
  # Look for lines like "Build: <cmd>", "build: <cmd>", "Build Command: <cmd>", etc.
  BUILD_CMD=$(grep -iE '^\s*build(\s+command)?\s*:\s*.+' "$PRODUCTION_MD" \
    | head -1 | sed -E 's/^[^:]+:\s*//')
  LINT_CMD=$(grep -iE '^\s*lint(\s+command)?\s*:\s*.+' "$PRODUCTION_MD" \
    | head -1 | sed -E 's/^[^:]+:\s*//')
  TEST_CMD=$(grep -iE '^\s*test(\s+command)?\s*:\s*.+' "$PRODUCTION_MD" \
    | head -1 | sed -E 's/^[^:]+:\s*//')
fi

# ---------------------------------------------------------------------------
# Check 1: Build
# ---------------------------------------------------------------------------
if [[ -z "$BUILD_CMD" ]]; then
  skip "Build — no build command found in production.md"
else
  echo "--- Running build: $BUILD_CMD"
  set +e
  (cd "$PROJECT_ROOT" && eval "$BUILD_CMD" > /tmp/self-check-build.log 2>&1)
  BUILD_EXIT=$?
  set -e
  if [[ $BUILD_EXIT -eq 0 ]]; then
    pass "Build succeeded"
  else
    fail "Build failed (exit $BUILD_EXIT) — see /tmp/self-check-build.log"
    tail -20 /tmp/self-check-build.log | sed 's/^/  /'
  fi
fi

# ---------------------------------------------------------------------------
# Check 2: Lint
# ---------------------------------------------------------------------------
if [[ -z "$LINT_CMD" ]]; then
  skip "Lint — no lint command found in production.md"
else
  echo "--- Running lint: $LINT_CMD"
  set +e
  (cd "$PROJECT_ROOT" && eval "$LINT_CMD" > /tmp/self-check-lint.log 2>&1)
  LINT_EXIT=$?
  set -e
  if [[ $LINT_EXIT -eq 0 ]]; then
    pass "Lint passed"
  else
    fail "Lint failed (exit $LINT_EXIT) — see /tmp/self-check-lint.log"
    tail -20 /tmp/self-check-lint.log | sed 's/^/  /'
  fi
fi

# ---------------------------------------------------------------------------
# Check 3: Tests
# ---------------------------------------------------------------------------
if [[ -z "$TEST_CMD" ]]; then
  fail "Tests — no test command found in production.md (add 'Test:' to status.md Build Config via PM; if the project truly has no tests, the human must say so)"
else
  echo "--- Running tests: $TEST_CMD"
  set +e
  (cd "$PROJECT_ROOT" && eval "$TEST_CMD" > /tmp/self-check-test.log 2>&1)
  TEST_EXIT=$?
  set -e
  if [[ $TEST_EXIT -eq 0 ]]; then
    pass "Tests passed"
  else
    fail "Tests failed (exit $TEST_EXIT) — see /tmp/self-check-test.log"
    tail -20 /tmp/self-check-test.log | sed 's/^/  /'
  fi
fi

# ---------------------------------------------------------------------------
# Check 4: Git scope — no files changed outside module directory
# ---------------------------------------------------------------------------
echo "--- Checking git scope for module: $MODULE_NAME"

if ! git -C "$PROJECT_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
  skip "Git scope — $PROJECT_ROOT is not a git repository"
else
  STATUS_MD="$PROJECT_ROOT/project-planning/status.md"
  SOURCE_PATHS=$(python3 "$SCOPE_PY" paths "$STATUS_MD" "$MODULE_NAME" 2>/dev/null | paste -sd ',' - | sed 's/,/, /g')
  case "$SCOPE_RC" in
    0) pass "Git scope — every change is within $MODULE_NAME's scope (${SOURCE_PATHS:-no paths}, plus its planning files)"
       [ -n "$SCOPE_OUT" ] && printf '%s\n' "$SCOPE_OUT" | sed 's/^/  /' ;;
    2) fail "Git scope — $MODULE_NAME has no row in the status.md Module Map; PM must add it before you build" ;;
    3) skip "Git scope — the status.md Module Map has no Source Path column (add it at PM finalize)" ;;
    *) fail "Git scope — changes outside $MODULE_NAME's scope:"
       printf '%s\n' "$SCOPE_OUT" | sed 's/^/  /' ;;
  esac
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo " SELF-CHECK SUMMARY"
echo "========================================"
echo " Module : $MODULE_NAME"
echo " Passed : $PASS_COUNT"
echo " Failed : $FAIL_COUNT"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo ""
  echo " Failures:"
  for f in "${FAILURES[@]}"; do
    echo "   - $f"
  done
fi

echo "========================================"

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo " RESULT: FAIL — fix the issues above before handing off to QA"
  exit 1
else
  echo " RESULT: PASS — automated checks complete, proceed to judgment items"
  exit 0
fi
