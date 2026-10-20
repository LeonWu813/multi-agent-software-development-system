#!/bin/bash
# Handoff hook — fires on Stop/SubagentStop for dev-team-agent sessions.
# Reads project-planning/status.md Last Action and shows the next claude --agent suggestion.
# Registered under "hooks" in ~/.claude/settings.json on Stop and SubagentStop events.
# Output is a JSON systemMessage: plain stdout from Stop hooks goes to the debug log, not the user.

INPUT=$(cat)

# Prevent infinite loops (required for Stop hooks)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_HOOK_ACTIVE" = "true" ] && exit 0

# Get working directory from hook input, fall back to pwd
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -z "$CWD" ] && CWD="$(pwd)"

# Resolve the project root, so a session that ran `cd src` still finds status.md
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$ROOT" ] || [ ! -f "$ROOT/project-planning/status.md" ]; then
    ROOT=""; d="$CWD"
    while [ -n "$d" ] && [ "$d" != "/" ]; do
        [ -f "$d/project-planning/status.md" ] && { ROOT="$d"; break; }
        d=$(dirname "$d")
    done
fi
[ -n "$ROOT" ] && CWD="$ROOT"

STATUS_FILE="$CWD/project-planning/status.md"
[ ! -f "$STATUS_FILE" ] && exit 0  # not a dev-team-agent project — exit silently

# Extract Last Action block (between ## Last Action and the next ## heading)
LAST_ACTION=$(awk '/^## Last Action/{found=1; next} found && /^## /{exit} found{print}' "$STATUS_FILE")

AGENT=$(echo "$LAST_ACTION"  | grep -m1 "^agent:"  | sed 's/agent:[[:space:]]*//')
MODE=$(echo "$LAST_ACTION"   | grep -m1 "^mode:"   | sed 's/mode:[[:space:]]*//')
RESULT=$(echo "$LAST_ACTION" | grep -m1 "^result:" | sed 's/result:[[:space:]]*//')
MODULE=$(echo "$LAST_ACTION" | grep -m1 "^module:" | sed 's/module:[[:space:]]*//')

[ -z "$AGENT" ] && exit 0

# Show each handoff once. Stop and SubagentStop both fire, and Stop fires after every
# main-session turn; only a new Last Action block produces a new message.
GIT_DIR=$(git -C "$CWD" rev-parse --absolute-git-dir 2>/dev/null)
STATE_FILE="${GIT_DIR:-$CWD/project-planning}/handoff-last-shown"
FINGERPRINT=$(printf '%s' "$LAST_ACTION" | cksum | cut -d' ' -f1)
[ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "$FINGERPRINT" ] && exit 0

# First non-comment line of Current Phase (comments may span several lines)
CURRENT_PHASE=$(awk '/^## Current Phase/{found=1; next} found && /^## /{exit} found && /<!--/{c=1} found && c {if (/-->/) c=0; next} found && NF{print; exit}' "$STATUS_FILE")
INIT_TAGGED=0
grep -q '\[INIT\]' "$STATUS_FILE" && INIT_TAGGED=1
AC=$(echo "$LAST_ACTION" | grep -m1 "^ac:" | sed 's/ac:[[:space:]]*//')

# Offer the verify skill only during phase 1 (no checkpoint recorded yet) and only while it doesn't exist
CHECKPOINTS=$(awk '/^## Checkpoint History/{found=1; next} found && /^## /{exit} found && /approved/' "$STATUS_FILE")
VERIFY_HINT=""
[ ! -f "$CWD/.claude/skills/verify/SKILL.md" ] && [ -z "$CHECKPOINTS" ] && VERIFY_HINT=" Optional, phase 1 only: once the app runs, have the coordinator run /pstack:create-verification-skill (with your OK)."

# Every command below is written as `claude --agent <name> "<what to say>"`, so it pastes into any shell.
if [ "$RESULT" = "needs-human" ]; then
    NEXT="$AGENT is waiting on you — read its last message (and its status.md entry), do what it asks, then run \`claude --agent $AGENT\` and give it your answer"
    case "$AGENT" in
        qa-*) NEXT="QA needs your sign-off — run its test script (in QA Results), then: \`claude --agent $AGENT \"ui-results: <which ACs passed, which failed and how>\"\`" ;;
    esac
fi

[ -n "$NEXT" ] || case "$AGENT" in
    pm)
        case "$MODE" in
            init)       NEXT="\`claude --agent tech-lead \"initial PRD review\"\`" ;;
            iterate)    NEXT="Review the revised PRD. Architectural changes: \`claude --agent tech-lead \"pre-sync re-review\"\`. Otherwise, once you approve: \`claude --agent pm \"finalize\"\`" ;;
            finalize)   NEXT="\`claude --agent doc-sync\` — initial sync" ;;
            change)     NEXT="Architectural impact: have the coordinator run /pstack:how on the affected code (saved to project-planning/pstack-findings/), then \`claude --agent tech-lead \"change review\"\`. Otherwise: \`claude --agent doc-sync\`" ;;
            checkpoint)
                if [ "$RESULT" = "project-complete" ]; then
                    NEXT="Project complete — README.md written. Optional: \`claude --agent retrospective\`"
                else
                    NEXT="Now in ${CURRENT_PHASE:-the next phase}. Next: \`claude --agent engineer-<first module of this phase> \"implement\"\` (see Phase Plan)"
                fi ;;
            *)          NEXT="Check PM Updates in project-planning/status.md" ;;
        esac ;;
    tech-lead)
        [ "$RESULT" = "setup-changed" ] && MODE="setup-changed"
        case "$MODE" in
            setup-changed)          NEXT="Setup changed (see Setup Changed in status.md Tech Lead Reviews). Redo the listed setup.md steps, then: \`claude --agent tech-lead \"Setup is complete\"\`" ;;
            pre-sync-review)        NEXT="Read the re-review in status.md Tech Lead Reviews. Changes requested: \`claude --agent pm \"iterate\"\`. You approve the PRD: \`claude --agent pm \"finalize\"\`" ;;
            init-review)            NEXT="Complete every step in project-planning/setup.md, then: \`claude --agent tech-lead \"Setup is complete\"\`" ;;
            setup-confirmation)
                if [ "$INIT_TAGGED" = "1" ]; then
                    NEXT="Setup re-confirmed. Resume the step that found the drift (usually: \`claude --agent qa-<module> \"verify\"\`)"
                else
                    NEXT="\`claude --agent pm \"iterate\"\` to apply Tech Lead's feedback, or \`claude --agent pm \"finalize\"\` if there is none and you approve the PRD"
                fi ;;
            change-review)          NEXT="Read the review in status.md Tech Lead Reviews. Accept as-is: \`claude --agent doc-sync\`. PRD needs revising: \`claude --agent pm \"change\"\`" ;;
            on-demand-review)       NEXT="Read the review in status.md Tech Lead Reviews. Minor adjustment: \`claude --agent engineer-<module> \"bugfix\"\`. PRD-level change: \`claude --agent pm \"change\"\`" ;;
            integration-review)
                if [ "$RESULT" = "clean" ]; then
                    NEXT="No integration issues this phase. Next: \`claude --agent pm \"checkpoint\"\`"
                else
                    NEXT="Review project-planning/integration-review.md and decide every row (Concerns and Recommendations), then: \`claude --agent tech-lead \"decisions: INT-001 approve, INT-002 reject, INT-003 defer\"\`"
                fi ;;
            record-decisions)       NEXT="For each APPROVED item: \`claude --agent engineer-<Assigned Module> \"integration-fix <INT-ID>\"\` (rows noted 'blast-radius first': the coordinator runs /pstack:blast-radius before that). Nothing approved and nothing PROPOSED: \`claude --agent pm \"checkpoint\"\`" ;;
            confirm-fix)            NEXT="Every row for this phase CONFIRMED CLOSED, REJECTED, DEFERRED or NO ISSUES: \`claude --agent pm \"checkpoint\"\`. Otherwise continue the next open row (see integration-review.md Status)" ;;
            repeat-failure-review)  NEXT="Tech Lead's diagnosis is in status.md Tech Lead Reviews. Next: \`claude --agent engineer-${MODULE:-<module>} \"bugfix — follow Tech Lead's repeat-failure diagnosis${AC:+ for $AC}\"\`, or \`claude --agent pm \"change\"\` if it needs a requirements change" ;;
            *)                      NEXT="Read the latest entry in status.md Tech Lead Reviews and decide the next agent" ;;
        esac ;;
    doc-sync)
        case "$RESULT" in
            needs-pm)   NEXT="Doc-Sync left unresolved PRD questions (see Sync Reports). \`claude --agent pm \"change\"\` before any engineering starts" ;;
            *)          NEXT="Review the sync report in status.md. If it generated new agents, open a new terminal so they load. Then: \`claude --agent engineer-<first module in the Phase Plan not yet built> \"implement\"\`" ;;
        esac ;;
    engineer-*)
        SLUG="${AGENT#engineer-}"
        case "$RESULT" in
            success)
                case "$MODE" in
                    bugfix*)          NEXT="\`claude --agent qa-$SLUG \"regression\"\`" ;;
                    integration-fix*) NEXT="\`claude --agent qa-$SLUG \"integration-fix-verify <INT-ID from integration-review.md>\"\`" ;;
                    *)                NEXT="\`claude --agent qa-$SLUG \"verify\"\`" ;;
                esac ;;
            blocked-dependency) NEXT="A module this one depends on has not passed QA yet — finish that module first (see Phase Plan). If the phase order itself is wrong: \`claude --agent pm \"change\"\`" ;;
            blocked-technical)  NEXT="\`claude --agent tech-lead \"engineer blocker in $SLUG\"\` — cross-module or tech-stack blocker in Engineering Progress" ;;
            *)                  NEXT="Check Engineering Progress in project-planning/modules/${MODULE:-$SLUG}/status.md" ;;
        esac ;;
    qa-*)
        SLUG="${AGENT#qa-}"
        case "$MODE" in
            integration-fix-verify*)
                case "$RESULT" in
                    success) NEXT="Verify the fix yourself, then: \`claude --agent tech-lead \"<INT-ID> verified: <what you checked>\"\`" ;;
                    *)       NEXT="The integration fix does not hold yet — \`claude --agent engineer-$SLUG \"integration-fix <INT-ID>\"\`" ;;
                esac ;;
            *)
                case "$RESULT" in
                    success)        NEXT="Next module in the Phase Plan: \`claude --agent engineer-<next module> \"implement\"\`. If this was the last module of the phase: the coordinator runs /pstack:thermos on the phase's changes (saved to project-planning/pstack-findings/), then \`claude --agent tech-lead \"phase-end integration review\"\`.$VERIFY_HINT" ;;
                    bugs-found)     NEXT="\`claude --agent engineer-$SLUG \"bugfix\"\` — failures are in QA Results" ;;
                    setup-drift)    NEXT="setup.md is out of step with the real infrastructure (see QA Results) — \`claude --agent tech-lead \"on-demand review: setup drift found by qa-$SLUG\"\`" ;;
                    spec-issue)     NEXT="\`claude --agent pm \"change: spec issue from qa-$SLUG\"\` — PRD update needed" ;;
                    repeat-failure)
                        MARKER_FILE="$CWD/project-planning/modules/${MODULE:-$SLUG}/status.md"
                        if [ -n "$AC" ] && grep -q "$AC: ESCALATED TO TECH LEAD — open" "$MARKER_FILE" 2>/dev/null; then
                            NEXT="$AC is already escalated — \`claude --agent tech-lead \"repeat-failure review $AC\"\` (Tech Lead stays the owner until it passes)"
                        elif [ -n "$AC" ]; then
                            NEXT="First escalation of $AC — the coordinator runs /pstack:how and /pstack:why on the failing path (saved to project-planning/pstack-findings/), then \`claude --agent tech-lead \"repeat-failure review $AC\"\`"
                        else
                            NEXT="Repeat failure — if this AC has no open ESCALATED marker yet, the coordinator runs /pstack:how and /pstack:why first; then \`claude --agent tech-lead \"repeat-failure review <AC-ID>\"\`"
                        fi ;;
                    *)              NEXT="Check QA Results in project-planning/modules/${MODULE:-$SLUG}/status.md" ;;
                esac ;;
        esac ;;
    *)
        exit 0 ;;
esac

MSG="Handoff — $AGENT ($MODE, $RESULT)
Next → $NEXT"

# Warn if the agent left anything uncommitted (source code and generated agents included)
UNCOMMITTED=$(git -C "$CWD" status --porcelain 2>/dev/null)
if [ -n "$UNCOMMITTED" ]; then
    MSG="$MSG

Warning: uncommitted changes — the agent may not have committed before stopping:
$UNCOMMITTED"
fi

printf '%s' "$FINGERPRINT" > "$STATE_FILE" 2>/dev/null
jq -n --arg m "$MSG" '{systemMessage: $m}'
