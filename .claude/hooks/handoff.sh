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

# Base log for the scope check: whenever HEAD has moved since the last entry, record who stopped.
# An Engineer's changes are everything since the last entry written by anyone else, so the check
# never relies on commit messages (module_scope.py reads this log).
GIT_DIR=$(git -C "$CWD" rev-parse --absolute-git-dir 2>/dev/null)
STOPPED_BY=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null)
if [ -n "$GIT_DIR" ]; then
    HEAD_SHA=$(git -C "$CWD" rev-parse -q --verify HEAD 2>/dev/null)
    BASE_LOG="$GIT_DIR/framework-handoff-log"
    if [ -n "$HEAD_SHA" ] && [ "$(tail -1 "$BASE_LOG" 2>/dev/null | cut -d' ' -f1)" != "$HEAD_SHA" ]; then
        echo "$HEAD_SHA $(date +%s) ${STOPPED_BY:-coordinator}" >> "$BASE_LOG"
    fi
fi

# Extract Last Action block (between ## Last Action and the next ## heading)
LAST_ACTION=$(awk '/^## Last Action/{found=1; next} found && /^## /{exit} found{print}' "$STATUS_FILE")

AGENT=$(echo "$LAST_ACTION"  | grep -m1 "^agent:"  | sed 's/agent:[[:space:]]*//')
MODE=$(echo "$LAST_ACTION"   | grep -m1 "^mode:"   | sed 's/mode:[[:space:]]*//')
RESULT=$(echo "$LAST_ACTION" | grep -m1 "^result:" | sed 's/result:[[:space:]]*//')
MODULE=$(echo "$LAST_ACTION" | grep -m1 "^module:" | sed 's/module:[[:space:]]*//')

[ -z "$AGENT" ] && exit 0

# Show each handoff once. Stop and SubagentStop both fire, and Stop fires after every
# main-session turn; only a new Last Action block produces a new message.
STATE_FILE="${GIT_DIR:-$CWD/project-planning}/handoff-last-shown"
FINGERPRINT=$(printf '%s' "$LAST_ACTION" | cksum | cut -d' ' -f1)
[ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "$FINGERPRINT" ] && exit 0

# First non-comment line of Current Phase (comments may span several lines)
CURRENT_PHASE=$(awk '/^## Current Phase/{found=1; next} found && /^## /{exit} found && /<!--/{c=1} found && c {if (/-->/) c=0; next} found && NF{print; exit}' "$STATUS_FILE")
# [INIT] counts only when PM tagged it in PM Updates (Setup Confirmation text mentions it too)
INIT_TAGGED=0
awk '/^## PM Updates/{f=1; next} f && /^## /{exit} f' "$STATUS_FILE" | grep -q '\[INIT\]' && INIT_TAGGED=1
AC=$(echo "$LAST_ACTION" | grep -m1 "^ac:" | sed 's/ac:[[:space:]]*//; s/,/ /g')
# An agent may name the exact next command itself (Tech Lead reviews do), which wins over the defaults below
NEXT_FIELD=$(echo "$LAST_ACTION" | grep -m1 "^next:" | sed 's/next:[[:space:]]*//')

# Open QA items survive every handoff: QA keeps them in each module's status.md "### Open items"
OPEN_ITEMS=$(for f in "$CWD"/project-planning/modules/*/status.md; do
    [ -f "$f" ] || continue
    n=$(awk '/^### Open items/{f=1; next} /^#/{f=0} f && /^- \[ \]/' "$f" | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] && printf '%s (%s) ' "$(basename "$(dirname "$f")")" "$n"
done)
SCOPE_PY="$HOME/.claude/skills/engineer-checklist/scripts/module_scope.py"

# Offer the verify skill until it exists, unless the human declined it (PM records that in Decisions)
VERIFY_HINT=""
if [ ! -f "$CWD/.claude/skills/verify/SKILL.md" ] && ! awk '/^## Decisions/{f=1; next} f && /^## /{exit} f' "$STATUS_FILE" | grep -qiE 'verify skill.*declin'; then
    VERIFY_HINT=" Optional: once the app runs, have the coordinator run /pstack:create-verification-skill (with your OK; if you don't want one, ask PM to record \"verify skill: declined\" in Decisions)."
fi

# Latest PM Updates entry: is it marked [ARCHITECTURAL]?
# The latest entry starts at the last dated bullet ("- 2026-…" or "- **2026-…") or ### heading
LAST_ENTRY=$(awk '/^## PM Updates/{f=1; next} f && /^## /{exit} f && (/^- (\*\*)?[0-9][0-9][0-9][0-9]-/ || /^### /){e=""} f{e=e $0 "\n"} END{printf "%s", e}' "$STATUS_FILE")
ARCHITECTURAL=0
echo "$LAST_ENTRY" | sed -n 1p | grep -q '\[ARCHITECTURAL\]' && ARCHITECTURAL=1

# Modules that depend on the given module directory (module_scope.py reads the Module Map and specs)
dependents_of() { python3 "$SCOPE_PY" dependents "$CWD" "$1" 2>/dev/null; }

# Phase number of the checkpoint just recorded, and whether its Retrospective was declined
CHECKPOINT_LINES=$(awk '/^## Checkpoint History/{f=1; next} f && /^## /{exit} f' "$STATUS_FILE")
PHASE_DONE=$(echo "$CHECKPOINT_LINES" | grep -oE 'Phase [0-9]+ approved' | tail -1 | grep -oE '[0-9]+')
RETRO_SKIPPED=0
# Only lines after the latest "Phase N approved" belong to that checkpoint
echo "$CHECKPOINT_LINES" | awk '/Phase [0-9]+ approved/{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' | grep -qi 'retrospective: skipped' && RETRO_SKIPPED=1

# For a QA repeat-failure: which ACs are escalated for the first time, which already have an open marker
NEW=""; OPEN=""
case "$AGENT:$RESULT" in
    qa-*:repeat-failure)
        MARKER_FILE="$CWD/project-planning/modules/${MODULE:-${AGENT#qa-}}/status.md"
        for a in $AC; do
            if grep -E "$a[^A-Za-z0-9].*ESCALATED TO TECH LEAD — open" "$MARKER_FILE" >/dev/null 2>&1; then OPEN="$OPEN $a"; else NEW="$NEW $a"; fi
        done ;;
esac

# Every command below is written as `claude --agent <name> "<what to say>"`, so it pastes into any shell.
# The hook runs the Engineer's scope check itself: shell writes never pass through the guard,
# and the Engineer's own self-check result is not trusted for this.
case "$AGENT" in
    engineer-*)
        DIR="${AGENT#engineer-}"
        PREV_FILE="${GIT_DIR:-$CWD/project-planning}/framework-engineer-$DIR"
        # Remember what the Engineer was doing, so a later scope-fix can return to it
        [ "${MODE%% *}" != "scope-fix" ] && [ -n "$GIT_DIR" ] && echo "${MODE%% *} $RESULT" > "$PREV_FILE"
        if [ -z "$GIT_DIR" ]; then
            SCOPE_NOTES="note: not a git repository — the hook's scope check for shell writes was skipped"
            SCOPE_RC=0; SCOPE_OUT=""
        else
            SCOPE_OUT=$(python3 "$SCOPE_PY" changed "$CWD" "$DIR" 2>/dev/null); SCOPE_RC=$?
            [ $SCOPE_RC -eq 3 ] && SCOPE_OUT="note: the Module Map has no Source Path column — the hook's scope check was skipped"
        fi
        [ -z "$SCOPE_NOTES" ] && SCOPE_NOTES=$(echo "$SCOPE_OUT" | grep '^note:')
        if [ $SCOPE_RC -eq 1 ]; then
            SCOPE_VIOLATION=1
            NEXT="Scope violation — files changed outside ${AGENT#engineer-}'s Source Path:
$(echo "$SCOPE_OUT" | grep -v '^note:')
Fix first: \`claude --agent $AGENT \"scope-fix\"\` — it undoes only those changes; the hook re-checks and then returns you to the step that was interrupted (if the work belongs to another module, it records blocked-technical instead)"
        elif [ "${MODE%% *}" = "scope-fix" ] && [ "$RESULT" = "success" ]; then
            # The hook decides where a clean scope-fix returns to; the Engineer's own next: is not used
            read -r PREV_MODE PREV_RESULT < "${GIT_DIR:-$CWD/project-planning}/framework-engineer-$DIR" 2>/dev/null
            case "$PREV_RESULT:$PREV_MODE" in
                spec-issue:*)        NEXT="Scope is clean again. The interrupted run had stopped on a spec issue: \`claude --agent pm \"change: spec issue from $AGENT\"\`" ;;
                blocked-technical:*) NEXT="Scope is clean again. The interrupted run had a cross-module blocker: \`claude --agent tech-lead \"engineer blocker in $DIR\"\`" ;;
                blocked-dependency:*) NEXT="Scope is clean again. The interrupted run was waiting on a dependency — finish that module first (see Phase Plan)" ;;
                needs-human:*)       NEXT="Scope is clean again. The interrupted run was waiting on you — see Engineering Progress, then \`claude --agent $AGENT\`" ;;
                *:bugfix)            NEXT="Scope is clean again. Resume: \`claude --agent qa-$DIR \"regression\"\`"; MODE_FOR_DEPS=bugfix ;;
                *:integration-fix)   NEXT="Scope is clean again. Resume: \`claude --agent qa-$DIR \"integration-fix-verify INT-ID\"\` (the ID from integration-review.md)" ;;
                *:spec-update)       NEXT="Scope is clean again. Resume: \`claude --agent qa-$DIR \"verify\"\` (the ACs Doc-Sync changed)" ;;
                *)                   NEXT="Scope is clean again. Resume: \`claude --agent qa-$DIR \"verify\"\`" ;;
            esac
        elif [ $SCOPE_RC -eq 2 ]; then
            SCOPE_VIOLATION=1
            NEXT="${AGENT#engineer-} has no row in the status.md Module Map, so it has no Source Path. \`claude --agent pm \"change: add ${AGENT#engineer-} to the Module Map\"\` before it builds anything"
        fi ;;
esac

[ -n "$NEXT" ] || case "$RESULT" in
    needs-human)   if [ -n "$NEXT_FIELD" ]; then NEXT="$AGENT is waiting on you — $NEXT_FIELD"
                   else NEXT="$AGENT is waiting on you — read its last message (and its status.md entry), do what it asks, then run \`claude --agent $AGENT\` and give it your answer"; fi ;;
    needs-signoff) NEXT="QA needs your sign-off — run its test script (in QA Results), then: \`claude --agent $AGENT \"ui-results: WHICH ACS PASSED, WHICH FAILED AND HOW\"\`" ;;
esac
# next: never hides a setup change — the human must redo setup first
[ -z "$NEXT" ] && [ -n "$NEXT_FIELD" ] && [ "$RESULT" != "setup-changed" ] && NEXT="$NEXT_FIELD"

[ -n "$NEXT" ] || case "$AGENT" in
    pm)
        case "$MODE" in
            init)       NEXT="\`claude --agent tech-lead \"initial PRD review\"\`" ;;
            iterate)    NEXT="Review the revised PRD. Architectural changes: \`claude --agent tech-lead \"pre-sync re-review\"\`. Otherwise, once you approve: \`claude --agent pm \"finalize\"\`" ;;
            finalize)   NEXT="\`claude --agent doc-sync\` — initial sync" ;;
            change)
                if [ "$ARCHITECTURAL" = "1" ]; then
                    NEXT="[ARCHITECTURAL] change — the coordinator runs /pstack:how on the affected code (saved to project-planning/pstack-findings/), then \`claude --agent tech-lead \"change review\"\`"
                else
                    NEXT="\`claude --agent doc-sync\`"
                fi ;;
            checkpoint)
                if [ "$RESULT" = "project-complete" ]; then
                    NEXT="Project complete — README.md written. Optional: \`claude --agent retrospective\`"
                elif [ "$RESULT" != "success" ]; then
                    NEXT="The checkpoint did not complete ($RESULT) — read PM's last message for what is still open"
                else
                    NEXT="Now in ${CURRENT_PHASE:-the next phase}. Next: \`claude --agent engineer-FIRST_MODULE_OF_PHASE \"implement\"\` (see Phase Plan)"
                fi ;;
            *)          NEXT="Check PM Updates in project-planning/status.md" ;;
        esac ;;
    tech-lead)
        ROUTE="$MODE"
        [ "$RESULT" = "setup-changed" ] && ROUTE="setup-changed"
        case "$ROUTE" in
            setup-changed)          NEXT="Setup changed (see Setup Changed in status.md Tech Lead Reviews). Redo the listed setup.md steps, then: \`claude --agent tech-lead \"Setup is complete\"\`" ;;
            pre-sync-review)        NEXT="Read the re-review in status.md Tech Lead Reviews. Changes requested: \`claude --agent pm \"iterate\"\`. You approve the PRD: \`claude --agent pm \"finalize\"\`" ;;
            init-review)            NEXT="Complete every step in project-planning/setup.md, then: \`claude --agent tech-lead \"Setup is complete\"\`" ;;
            setup-confirmation)
                if [ "$INIT_TAGGED" = "1" ]; then
                    NEXT="Setup re-confirmed. Resume where the work stopped: re-run the agent that reported the drift (usually QA for that module, with the same word it had)"
                else
                    NEXT="\`claude --agent pm \"iterate\"\` to apply Tech Lead's feedback, or \`claude --agent pm \"finalize\"\` if there is none and you approve the PRD"
                fi ;;
            change-review)          NEXT="Read the review in status.md Tech Lead Reviews. Accept as-is: \`claude --agent doc-sync\`. PRD needs revising: \`claude --agent pm \"change\"\`" ;;
            on-demand-review)       NEXT="Read the review in status.md Tech Lead Reviews. Tech Lead names the next command in its review; if it didn't, PRD-level change: \`claude --agent pm \"change\"\`" ;;
            integration-review)
                if [ "$RESULT" = "clean" ]; then
                    NEXT="No integration issues this phase. Next: \`claude --agent pm \"checkpoint\"\`"
                else
                    NEXT="Review project-planning/integration-review.md and decide every row (Concerns and Recommendations), then: \`claude --agent tech-lead \"decisions: INT-001 approve, INT-002 reject, INT-003 defer\"\`"
                fi ;;
            record-decisions)       NEXT="For each APPROVED item: \`claude --agent engineer-ASSIGNED_MODULE \"integration-fix INT-ID\"\` (rows noted 'blast-radius first': the coordinator runs /pstack:blast-radius before that). Nothing approved and nothing PROPOSED: \`claude --agent pm \"checkpoint\"\`" ;;
            confirm-fix)            NEXT="No row in integration-review.md still open (all CONFIRMED CLOSED, REJECTED, DEFERRED, SPLIT, ACCEPTED (KNOWN ISSUE) or NO ISSUES — DEFERRED not at the final checkpoint): \`claude --agent pm \"checkpoint\"\`. Otherwise continue the next open row (see integration-review.md Status)" ;;
            repeat-failure-review)  NEXT="Tech Lead's diagnosis is in status.md Tech Lead Reviews. Next: \`claude --agent engineer-${MODULE:-MODULE} \"bugfix — follow Tech Lead's repeat-failure diagnosis${AC:+ for $AC}\"\`, or \`claude --agent pm \"change\"\` if it needs a requirements change" ;;
            *)                      NEXT="Read the latest entry in status.md Tech Lead Reviews and decide the next agent" ;;
        esac ;;
    doc-sync)
        case "$RESULT" in
            needs-pm)   NEXT="Doc-Sync left unresolved PRD questions (see Sync Reports). \`claude --agent pm \"change\"\` before any engineering starts" ;;
            *)
                if [ "${MODE%% *}" = "template-refresh" ]; then
                    NEXT="Module agents regenerated from the current templates. Run claude --continue so they load, then carry on with the step that was next before the refresh"
                else NEXT="Review the sync report in status.md. If it generated new agents and they can't be called yet, run claude --continue to reload them in the same conversation. Then: \`claude --agent engineer-NEXT_MODULE \"implement\"\` (the first module in the Phase Plan not yet built; if this sync created an owner module that takes over existing code, first \`claude --agent tech-lead \"log migration rows for OWNER_MODULE\"\`)"
                fi ;;
        esac ;;
    engineer-*)
        SLUG="${AGENT#engineer-}"
        case "$RESULT" in
            success)
                case "$MODE" in
                    bugfix*)          NEXT="\`claude --agent qa-$SLUG \"regression\"\`" ;;
                    spec-update*)     NEXT="\`claude --agent qa-$SLUG \"verify\"\` — check the acceptance criteria Doc-Sync changed (see the latest Sync Report) and re-run the rest for regressions" ;;
                    integration-fix*) NEXT="\`claude --agent qa-$SLUG \"integration-fix-verify INT-ID\"\` (the ID from integration-review.md)" ;;
                    *)                NEXT="\`claude --agent qa-$SLUG \"verify\"\`" ;;
                esac ;;
            spec-issue)         NEXT="\`claude --agent pm \"change: spec issue from $AGENT\"\` — the Engineer found a requirement it cannot build as written (see Engineering Progress)" ;;
            blocked-dependency) NEXT="A module this one depends on has not passed QA yet — finish that module first (see Phase Plan). If the phase order itself is wrong: \`claude --agent pm \"change\"\`" ;;
            blocked-technical)  NEXT="\`claude --agent tech-lead \"engineer blocker in $SLUG\"\` — cross-module or tech-stack blocker in Engineering Progress" ;;
            *)                  NEXT="Check Engineering Progress in project-planning/modules/${MODULE:-$SLUG}/status.md" ;;
        esac ;;
    qa-*)
        SLUG="${AGENT#qa-}"
        case "$RESULT" in
            success)
                if [ "${MODE%% *}" = "integration-fix-verify" ]; then
                    NEXT="Verify the fix yourself, then: \`claude --agent tech-lead \"INT-ID verified: WHAT YOU CHECKED\"\`"
                else
                    NEXT="Next module in the Phase Plan: \`claude --agent engineer-NEXT_MODULE \"implement\"\`. If this was the last module of the phase: the coordinator runs /pstack:thermos on the phase's changes (saved to project-planning/pstack-findings/), then \`claude --agent tech-lead \"phase-end integration review\"\`."
                fi ;;
            bugs-found)
                if [ "${MODE%% *}" = "integration-fix-verify" ]; then
                    NEXT="The integration fix does not hold yet — \`claude --agent engineer-$SLUG \"integration-fix INT-ID\"\`"
                else
                    NEXT="\`claude --agent engineer-$SLUG \"bugfix\"\` — failures are in QA Results"
                fi ;;
            setup-drift)    NEXT="setup.md is out of step with the real infrastructure (see QA Results) — \`claude --agent tech-lead \"on-demand review: setup drift found by qa-$SLUG\"\`" ;;
            spec-issue)     NEXT="\`claude --agent pm \"change: spec issue from qa-$SLUG\"\` — PRD update needed" ;;
            repeat-failure)
                if [ -z "$AC" ]; then
                    NEXT="Repeat failure — if the AC has no open ESCALATED marker yet, the coordinator runs /pstack:how and /pstack:why first; then \`claude --agent tech-lead \"repeat-failure review AC-ID\"\`"
                else
                    NEXT=""
                    [ -n "$NEW" ] && NEXT="First escalation of${NEW} — the coordinator runs /pstack:how and /pstack:why on the failing path (saved to project-planning/pstack-findings/). "
                    [ -n "$OPEN" ] && NEXT="${NEXT}Already escalated:${OPEN} (Tech Lead stays the owner). "
                    NEXT="${NEXT}Then: \`claude --agent tech-lead \"repeat-failure review ${AC}\"\`"
                fi ;;
            *)              NEXT="Check QA Results in project-planning/modules/${MODULE:-$SLUG}/status.md" ;;
        esac ;;
    *)
        exit 0 ;;
esac

# Coordinator steps the hook adds even when the agent wrote its own next: (unless next: already has them)
case "$AGENT:$RESULT:${MODE%% *}" in
    pm:success:change)
        if [ "$ARCHITECTURAL" = "1" ] && ! echo "$NEXT" | grep -q "pstack:how"; then
            NEXT="[ARCHITECTURAL] change — first the coordinator runs /pstack:how on the affected code (saved to project-planning/pstack-findings/). Then: $NEXT"
        fi ;;
    qa-*:repeat-failure:*)
        if [ -n "$NEW" ] && ! echo "$NEXT" | grep -q "pstack:how"; then
            NEXT="First escalation of${NEW} — first the coordinator runs /pstack:how and /pstack:why on the failing path (saved to project-planning/pstack-findings/). Then: $NEXT"
        fi ;;
esac

# Blast-radius after a bugfix to a module others depend on (integration fixes get it before the fix,
# via record-decisions, so they are not repeated here)
case "$AGENT:$RESULT:${MODE_FOR_DEPS:-$MODE}" in
    engineer-*:success:bugfix*)
        [ -n "$SCOPE_VIOLATION" ] && DEPS="" || DEPS=$(dependents_of "${AGENT#engineer-}")
        if [ -n "$DEPS" ] && ! echo "$NEXT" | grep -q "blast-radius"; then
            NEXT="${AGENT#engineer-} is used by $DEPS — first the coordinator runs /pstack:blast-radius on this fix's diff (saved to project-planning/pstack-findings/). Then: $NEXT"
        fi ;;
esac

# Steps the hook adds whoever wrote the next command: the verify hint after a QA pass, and the
# verify refresh at a checkpoint
case "$AGENT:$RESULT" in
    qa-*:success) echo "$NEXT" | grep -q "create-verification-skill" || NEXT="$NEXT$VERIFY_HINT" ;;
    pm:success)
        if [ "${MODE%% *}" = "checkpoint" ] && [ -f "$CWD/.claude/skills/verify/SKILL.md" ] && ! echo "$NEXT" | grep -q "maintain-verification-skill"; then
            NEXT="First the coordinator refreshes the verify skill with /pstack:maintain-verification-skill (with your OK). Then: $NEXT"
        fi
        if [ "${MODE%% *}" = "checkpoint" ] && [ "$RETRO_SKIPPED" = "0" ] && ! echo "$NEXT" | grep -q "retrospective"; then
            NEXT="$NEXT Optional: a short Retrospective on the phase just closed — \`claude --agent retrospective \"phase ${PHASE_DONE:-N}\"\`."
        fi ;;
esac

MSG="Handoff — $AGENT ($MODE, $RESULT)
Next → $NEXT"
# In one-conversation mode the agent ran as a subagent: the coordinator carries on, except at stopping points
if [ "$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)" = "SubagentStop" ]; then
    case "$RESULT:$AGENT:${MODE%% *}" in
        needs-human:*|needs-signoff:*|blocked*|setup-changed:*|issues-found:*|project-complete:*|*:pm:*|*:tech-lead:init-review|success:qa-*:integration-fix-verify) MSG="$MSG
(The coordinator will ask you before continuing.)" ;;
        *) MSG="$MSG
(The coordinator runs this next step for you unless it needs your decision.)" ;;
    esac
fi
[ -n "$SCOPE_NOTES" ] && MSG="$MSG
$SCOPE_NOTES"
[ -n "$OPEN_ITEMS" ] && MSG="$MSG
Open QA items still waiting: ${OPEN_ITEMS% } — listed under \"### Open items\" in each module's status.md. Once the step above is done: bugs-found items go to that module's Engineer (\"bugfix\"); repeat-failure and setup-drift items go to Tech Lead"

# Warn if the agent left anything uncommitted (source code and generated agents included)
UNCOMMITTED=$(git -C "$CWD" status --porcelain 2>/dev/null)
if [ -n "$UNCOMMITTED" ]; then
    MSG="$MSG

Warning: uncommitted changes — the agent may not have committed before stopping:
$UNCOMMITTED"
fi

printf '%s' "$FINGERPRINT" > "$STATE_FILE" 2>/dev/null
jq -n --arg m "$MSG" '{systemMessage: $m}'
