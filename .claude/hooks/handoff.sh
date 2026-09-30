#!/bin/bash
# Handoff hook — fires on Stop/SubagentStop for dev-team-agent sessions.
# Reads project-planning/status.md Last Action and prints the next claude --agent suggestion.
# Registered in ~/.claude/hooks.json on Stop and SubagentStop events.

INPUT=$(cat)

# Prevent infinite loops (required for Stop hooks)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_HOOK_ACTIVE" = "true" ] && exit 0

# Get working directory from hook input, fall back to pwd
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -z "$CWD" ] && CWD="$(pwd)"

STATUS_FILE="$CWD/project-planning/status.md"
[ ! -f "$STATUS_FILE" ] && exit 0  # not a dev-team-agent project — exit silently

# Warn if agent left uncommitted changes in project-planning/
UNCOMMITTED=$(git -C "$CWD" status --porcelain -- project-planning/ 2>/dev/null)
if [ -n "$UNCOMMITTED" ]; then
    echo ""
    echo "Warning: uncommitted changes in project-planning/ — agent may not have committed before stopping:"
    echo "$UNCOMMITTED"
fi

# Extract Last Action block (between ## Last Action and the next ## heading)
LAST_ACTION=$(awk '/^## Last Action/{found=1; next} found && /^## /{exit} found{print}' "$STATUS_FILE")

AGENT=$(echo "$LAST_ACTION"  | grep -m1 "^agent:"  | sed 's/agent:[[:space:]]*//')
MODE=$(echo "$LAST_ACTION"   | grep -m1 "^mode:"   | sed 's/mode:[[:space:]]*//')
RESULT=$(echo "$LAST_ACTION" | grep -m1 "^result:" | sed 's/result:[[:space:]]*//')

[ -z "$AGENT" ] && exit 0

case "$AGENT" in
    pm)
        case "$MODE" in
            init)       NEXT="claude --agent tech-lead" ;;
            change)     NEXT="claude --agent doc-sync" ;;
            checkpoint) NEXT="claude --agent doc-sync  # next phase — or project complete" ;;
            *)          NEXT="claude --agent doc-sync" ;;
        esac ;;
    tech-lead)
        case "$MODE" in
            integration-review) NEXT="Review project-planning/integration-review.md — approve/reject/defer each finding, route approved items to their engineer-mod-<name>. Once no PROPOSED rows remain for this phase: claude --agent pm  (checkpoint)" ;;
            *)                  NEXT="Complete setup.md steps, confirm with user → claude --agent pm → claude --agent doc-sync" ;;
        esac ;;
    doc-sync)
        NEXT="See Phase Plan in project-planning/status.md → claude --agent engineer-mod-<name>" ;;
    engineer-mod-*)
        SLUG="${AGENT#engineer-mod-}"
        case "$RESULT" in
            success)    NEXT="claude --agent qa-mod-$SLUG" ;;
            blocked)    NEXT="claude --agent pm  # dependency not QA-passed yet" ;;
            *)          NEXT="Check Engineering Progress in project-planning/modules/mod-*/status.md" ;;
        esac ;;
    qa-mod-*)
        SLUG="${AGENT#qa-mod-}"
        if [ "$MODE" = "integration-fix-verify" ]; then
            case "$RESULT" in
                success) NEXT="Human verifies the fix, then: claude --agent tech-lead  # confirm and close the integration-review item" ;;
                *)       NEXT="claude --agent engineer-mod-$SLUG  # integration-review item still not resolved" ;;
            esac
        else
            case "$RESULT" in
                success)    NEXT="See Phase Plan for next module — or, if this was the last module in the phase: claude --agent tech-lead  (integration & optimization review)" ;;
                bugs-found) NEXT="claude --agent engineer-mod-$SLUG  # fix bugs in QA Results" ;;
                spec-issue) NEXT="claude --agent pm  # spec issue — PRD update needed" ;;
                *)          NEXT="Check QA Results in project-planning/modules/mod-*/status.md" ;;
            esac
        fi ;;
    retrospective)
        NEXT="Review project-planning/retrospective/proposed-changes.md" ;;
    *)
        exit 0 ;;
esac

echo ""
echo "━━━  Handoff  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Agent:  $AGENT  ($RESULT)"
echo "  Next →  $NEXT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
