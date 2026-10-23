#!/bin/bash
# pstack guard — PreToolUse hook for dev-team-agent projects.
# Registered under "hooks" in ~/.claude/settings.json, matcher Skill|Edit|Write|MultiEdit|NotebookEdit.
#
# 1. Skill calls from framework agents must be on that agent's allowlist. The Skill tool is
#    all-or-nothing, so this hook is what limits each agent to its own skills.
# 2. No agent may write under ~/.claude (hooks, skills, agent definitions).
# 3. Only PM may change the status.md Module Map, so no agent can widen its own scope.
# 4. An engineer-* agent may write only its module's Source Path, the project files it owns,
#    and its own planning files (rules in engineer-checklist/scripts/module_scope.py).
# 5. Subagents that are not framework agents (pstack reviewers run as general-purpose,
#    pstack:effort-*, pstack:thermo-*) may write in the project only under
#    project-planning/pstack-findings/.
# 6. No agent may change the project's .claude/settings.json or settings.local.json:
#    permission rules are the human's decision.
#
# Main-session calls carry no agent_type and are not blocked here; CLAUDE.md governs them.
# Exit 2 blocks the call and shows stderr to the agent as the reason.

INPUT=$(cat)
SCOPE="$HOME/.claude/skills/engineer-checklist/scripts/module_scope.py"

block() { echo "Blocked by pstack-guard: $1" >&2; exit 2; }

CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -z "$CWD" ] && CWD="$(pwd)"
ORIG_CWD="$CWD"
# Resolve the project root from any subdirectory (git or not)
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$ROOT" ] || [ ! -f "$ROOT/project-planning/status.md" ]; then
    ROOT=""; d="$CWD"
    while [ -n "$d" ] && [ "$d" != "/" ]; do
        [ -f "$d/project-planning/status.md" ] && { ROOT="$d"; break; }
        d=$(dirname "$d")
    done
fi
[ -n "$ROOT" ] || exit 0  # not a dev-team-agent project
CWD="$ROOT"
STATUS="$CWD/project-planning/status.md"

AGENT=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null)
[ -z "$AGENT" ] && exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

case "$AGENT" in
    pm)              ALLOWED="prd-format pstack:sharpen pstack:unslop pstack:technical-writing"; FRAMEWORK=1 ;;
    engineer-*)      ALLOWED="coding-conventions engineer-checklist pstack:tdd pstack:deslop pstack:typescript-best-practices"; FRAMEWORK=1 ;;
    qa-*)            ALLOWED="qa-checklist verify"; FRAMEWORK=1 ;;
    tech-lead|doc-sync|retrospective) ALLOWED=""; FRAMEWORK=1 ;;
    *)               ALLOWED="*"; FRAMEWORK=0 ;;  # not a framework agent
esac

if [ "$TOOL" = "Skill" ]; then
    [ "$ALLOWED" = "*" ] && exit 0
    SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // ""' 2>/dev/null)
    for s in $ALLOWED; do
        [ "$SKILL" = "$s" ] && exit 0
    done
    # Project-level skills (the project's own .claude/skills/<name>/, e.g. verify, or one added from an
    # approved Retrospective proposal) are open to every framework agent except Doc-Sync, whose output
    # must stay a verbatim copy of the PRD.
    case "$SKILL" in
        *:*|*/*|..*) ;;
        *) [ "$AGENT" != "doc-sync" ] && [ -f "$CWD/.claude/skills/$SKILL/SKILL.md" ] && exit 0 ;;
    esac
    block "$AGENT may not use the skill '$SKILL'. Allowed for $AGENT: ${ALLOWED:-none}. If you need something outside your skills, record it as a blocker or note for the human instead."
fi

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null)
[ -z "$FILE" ] && exit 0
case "$FILE" in /*) ;; *) FILE="$ORIG_CWD/$FILE" ;; esac
realpath_of() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null || echo "$1"; }
REAL_FILE=$(realpath_of "$FILE")
REAL_CWD=$(realpath_of "$CWD")
REAL_HOME_CLAUDE=$(realpath_of "$HOME/.claude")

case "$REAL_FILE" in
    "$REAL_HOME_CLAUDE"|"$REAL_HOME_CLAUDE"/*) block "$AGENT may not write under ~/.claude ($FILE). Framework files change only on the human's explicit instruction, in the coordinator session." ;;
esac

case "$REAL_FILE" in
    "$REAL_CWD"/*) REL="${REAL_FILE#"$REAL_CWD"/}" ;;
    *) exit 0 ;;  # outside the project (scratch files, probe scripts)
esac

# Permission rules are the human's
case "$REL" in
    .claude/settings.json|.claude/settings.local.json) block "$AGENT may not change $REL — permission rules are the human's decision. If a permission check blocked you, say so in your final message with the exact action that was refused." ;;
esac

# Only PM may change the Module Map
if [ "$REL" = "project-planning/status.md" ] && [ "$AGENT" != "pm" ]; then
    CHANGED=$(printf '%s' "$INPUT" | python3 -c '
import json, re, sys
data = json.load(sys.stdin)
path, tool, ti = sys.argv[1], data.get("tool_name"), data.get("tool_input", {})
try:
    old = open(path, encoding="utf-8").read()
except OSError:
    old = ""
new = old
if tool == "Write":
    new = ti.get("content", "")
else:
    for e in (ti.get("edits") or [ti]):
        a, b = e.get("old_string", ""), e.get("new_string", "")
        new = new.replace(a, b) if e.get("replace_all") else new.replace(a, b, 1)
def module_map(t):
    m = re.search(r"^## Module Map\s*\n(.*?)(?=^## |\Z)", t, re.S | re.M)
    return m.group(1).strip() if m else ""
print("1" if module_map(old) != module_map(new) else "0")
' "$STATUS" 2>/dev/null)
    [ "$CHANGED" = "1" ] && block "$AGENT may not change the status.md Module Map — only PM changes module ownership, through a PRD change."
fi

if [ "$FRAMEWORK" = "1" ]; then
    case "$AGENT" in
        engineer-*)
            DIR="${AGENT#engineer-}"
            REASON=$(python3 "$SCOPE" check "$STATUS" "$DIR" "$REL" 2>/dev/null); RC=$?
            case "$RC" in
                0|3) exit 0 ;;  # in scope, or an older Module Map without Source Paths
                2)   [ "$REL" = "project-planning/status.md" ] && exit 0  # its Last Action, so the hook can route it to PM
                     block "$AGENT has no row in the status.md Module Map, so it has no write scope. PM must add the module (directory + Source Path) first." ;;
                *)   block "$AGENT may not write $REL — ${REASON:-outside its scope}. If the fix needs code another module owns, record a blocked-technical blocker for Tech Lead." ;;
            esac ;;
    esac
    exit 0  # other framework agents keep their prompt-defined write scopes
fi

case "$REL" in
    project-planning/pstack-findings/*) exit 0 ;;
esac
block "$AGENT is not a framework agent and may not change files in this project ($FILE). Write findings to project-planning/pstack-findings/ instead — the owning agent makes the change."
