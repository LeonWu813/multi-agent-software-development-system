#!/bin/bash
# pstack guard — PreToolUse hook for dev-team-agent projects.
# Registered under "hooks" in ~/.claude/settings.json, matcher Skill|Edit|Write|MultiEdit|NotebookEdit.
#
# 1. Skill calls from framework agents must be on that agent's allowlist. The Skill tool is
#    all-or-nothing, so this hook is what limits each agent to its own skills.
# 2. Subagents that are not framework agents (pstack reviewers run as general-purpose,
#    pstack:effort-*, pstack:thermo-*) may write only under project-planning/pstack-findings/
#    or outside the project. pstack steps deliver findings; owners make the changes.
#
# Main-session calls carry no agent_type and are not blocked here; CLAUDE.md governs them.
# Exit 2 blocks the call and shows stderr to the agent as the reason.

INPUT=$(cat)

CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -z "$CWD" ] && CWD="$(pwd)"
# Resolve the project root, so a session that ran `cd src` is still guarded
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
[ -n "$ROOT" ] && [ -f "$ROOT/project-planning/status.md" ] && CWD="$ROOT"
[ -f "$CWD/project-planning/status.md" ] || exit 0  # not a dev-team-agent project

AGENT=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null)
[ -z "$AGENT" ] && exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

case "$AGENT" in
    pm)                      ALLOWED="prd-format pstack:sharpen pstack:unslop pstack:technical-writing" ;;
    engineer|engineer-mod-*) ALLOWED="coding-conventions engineer-checklist pstack:tdd pstack:deslop pstack:typescript-best-practices" ;;
    qa|qa-mod-*)             ALLOWED="qa-checklist verify" ;;
    tech-lead|doc-sync|retrospective) ALLOWED="" ;;
    *)                       ALLOWED="*" ;;  # not a framework agent
esac

if [ "$TOOL" = "Skill" ]; then
    [ "$ALLOWED" = "*" ] && exit 0
    SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // ""' 2>/dev/null)
    for s in $ALLOWED; do
        [ "$SKILL" = "$s" ] && exit 0
    done
    echo "Blocked by pstack-guard: $AGENT may not use the skill '$SKILL'. Allowed for $AGENT: ${ALLOWED:-none}. If you need something outside your skills, record it as a blocker or note for the human instead." >&2
    exit 2
fi

# Write tools: framework agents keep their own prompt-defined write scopes
[ "$ALLOWED" != "*" ] && exit 0

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null)
[ -z "$FILE" ] && exit 0
ORIG_CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
case "$FILE" in /*) ;; *) FILE="${ORIG_CWD:-$CWD}/$FILE" ;; esac
REAL_FILE=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$FILE" 2>/dev/null || echo "$FILE")
REAL_CWD=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$CWD" 2>/dev/null || echo "$CWD")

case "$REAL_FILE" in
    "$REAL_CWD"/project-planning/pstack-findings/*) exit 0 ;;
    "$REAL_CWD"/*) ;;
    *) exit 0 ;;  # outside the project (scratch files, probe scripts)
esac

echo "Blocked by pstack-guard: $AGENT is not a framework agent and may not change files in this project ($FILE). Write findings to project-planning/pstack-findings/ instead — the owning agent makes the change." >&2
exit 2
