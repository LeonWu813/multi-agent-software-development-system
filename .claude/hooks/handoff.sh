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

STATUS_FILE="$CWD/project-planning/status.md"
[ ! -f "$STATUS_FILE" ] && exit 0  # not a dev-team-agent project — exit silently

# Extract Last Action block (between ## Last Action and the next ## heading)
LAST_ACTION=$(awk '/^## Last Action/{found=1; next} found && /^## /{exit} found{print}' "$STATUS_FILE")

AGENT=$(echo "$LAST_ACTION"  | grep -m1 "^agent:"  | sed 's/agent:[[:space:]]*//')
MODE=$(echo "$LAST_ACTION"   | grep -m1 "^mode:"   | sed 's/mode:[[:space:]]*//')
RESULT=$(echo "$LAST_ACTION" | grep -m1 "^result:" | sed 's/result:[[:space:]]*//')

[ -z "$AGENT" ] && exit 0

# Show each handoff once. Stop and SubagentStop both fire, and Stop fires after every
# main-session turn; only a new Last Action block produces a new message.
GIT_DIR=$(git -C "$CWD" rev-parse --absolute-git-dir 2>/dev/null)
STATE_FILE="${GIT_DIR:-$CWD/project-planning}/handoff-last-shown"
FINGERPRINT=$(printf '%s' "$LAST_ACTION" | cksum | cut -d' ' -f1)
[ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "$FINGERPRINT" ] && exit 0

CURRENT_PHASE=$(awk '/^## Current Phase/{found=1; next} found && /^## /{exit} found && NF{print; exit}' "$STATUS_FILE")

case "$AGENT" in
    pm)
        case "$MODE" in
            init)       NEXT="claude --agent tech-lead  # initial PRD review" ;;
            iterate)    NEXT="Review the revised PRD. If the changes are architectural: claude --agent tech-lead. When you give final approval: claude --agent pm  (finalize)" ;;
            finalize)   NEXT="claude --agent doc-sync  # initial sync" ;;
            change)     NEXT="If this change has architectural impact: claude --agent tech-lead first. Otherwise: claude --agent doc-sync" ;;
            checkpoint)
                if [ "$RESULT" = "project-complete" ]; then
                    NEXT="Project complete — README.md written. Optional: claude --agent retrospective"
                else
                    NEXT="Now in ${CURRENT_PHASE:-the next phase}. Next: claude --agent engineer-mod-<first module of this phase>  (see Phase Plan)"
                fi ;;
            *)          NEXT="Check PM Updates in project-planning/status.md" ;;
        esac ;;
    tech-lead)
        case "$MODE" in
            init-review)            NEXT="Complete every step in project-planning/setup.md, then: claude --agent tech-lead  (say \"Setup is complete\")" ;;
            setup-confirmation)     NEXT="claude --agent pm  # incorporate Tech Lead feedback, then finalize the PRD" ;;
            change-review)          NEXT="Read the review in status.md Tech Lead Reviews. Accept as-is: claude --agent doc-sync. PRD needs revising: claude --agent pm  (change mode)" ;;
            on-demand-review)       NEXT="Read the review in status.md Tech Lead Reviews. Minor adjustment: claude --agent engineer-mod-<name>. PRD-level change: claude --agent pm  (change mode)" ;;
            integration-review)
                if [ "$RESULT" = "clean" ]; then
                    NEXT="No integration issues this phase. Next: claude --agent pm  (checkpoint)"
                else
                    NEXT="Review project-planning/integration-review.md — approve/reject/defer each finding, route approved items to their engineer-mod-<name>. Once no PROPOSED rows remain for this phase: claude --agent pm  (checkpoint)"
                fi ;;
            confirm-fix)            NEXT="If no PROPOSED or open items remain for this phase: claude --agent pm  (checkpoint). Otherwise route the next approved item to its engineer-mod-<name>" ;;
            repeat-failure-review)  NEXT="Review Tech Lead's diagnosis in status.md Tech Lead Reviews — route to claude --agent engineer-mod-<name> with the diagnosis in hand, or claude --agent pm if it requires a requirements change" ;;
            *)                      NEXT="Read the latest entry in status.md Tech Lead Reviews and decide the next agent" ;;
        esac ;;
    doc-sync)
        case "$RESULT" in
            needs-pm)   NEXT="Doc-Sync left unresolved PRD questions (see Sync Reports). claude --agent pm  before any engineering starts" ;;
            *)          NEXT="Review the sync report in status.md, then: claude --agent engineer-mod-<name>  (see Phase Plan)" ;;
        esac ;;
    engineer-mod-*)
        SLUG="${AGENT#engineer-mod-}"
        case "$RESULT" in
            success)            NEXT="claude --agent qa-mod-$SLUG" ;;
            blocked-dependency) NEXT="A module this one depends on has not passed QA yet — finish that module first (see Phase Plan). If the phase order itself is wrong: claude --agent pm" ;;
            blocked-technical)  NEXT="claude --agent tech-lead  # cross-module or tech-stack blocker in Engineering Progress" ;;
            *)                  NEXT="Check Engineering Progress in project-planning/modules/mod-$SLUG/status.md" ;;
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
                success)        NEXT="See Phase Plan for next module — or, if this was the last module in the phase: claude --agent tech-lead  (integration & optimization review)" ;;
                bugs-found)     NEXT="claude --agent engineer-mod-$SLUG  # fix bugs in QA Results" ;;
                spec-issue)     NEXT="claude --agent pm  # spec issue — PRD update needed" ;;
                repeat-failure) NEXT="claude --agent tech-lead  # same AC failed again — repeat-failure review, not another Engineer round" ;;
                *)              NEXT="Check QA Results in project-planning/modules/mod-$SLUG/status.md" ;;
            esac
        fi ;;
    retrospective)
        NEXT="Review project-planning/retrospective/proposed-changes.md" ;;
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
