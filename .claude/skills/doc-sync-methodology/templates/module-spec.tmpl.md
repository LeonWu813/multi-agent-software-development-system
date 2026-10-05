<!-- owner: doc-sync | to change: invoke doc-sync — never edit this file directly -->

**Last Synced from PRD Revision**: <fill in PRD revision number> | **Last Updated**: <date>

---

## Module ID & Name

<!-- e.g., MOD-001: Authentication Service -->

## Purpose

<!-- One paragraph: what this module does. Copied verbatim from PRD Module Breakdown. Do not paraphrase or add detail not present in the PRD. -->

## Context

<!-- Populated by Doc-Sync. This section gives the Engineer the full "why" without needing access to prd.md. Include all three elements:

     1. The business problem this module addresses (from PRD Goals or User Stories rationale).
        Copy the exact PRD text — do not paraphrase. If the PRD does not state a business
        problem for this module, write:
        [AMBIGUITY: PRD does not state the business problem addressed by this module]

     2. Full text of each related user story (not just US-IDs).
        Copy the complete story text for every US-ID associated with this module, so the
        Engineer does not need to open prd.md to understand the user need.
        Format each story as:
          **US-XXX**: <full story text>

     3. Any non-goals from the PRD that explicitly bound what this module must NOT do.
        Copy verbatim. If none are stated, write "No non-goals stated in PRD for this module."
-->

## Related User Stories

<!-- List of US-IDs this module satisfies. One per line. Copy IDs exactly as they appear in prd.md. -->

- US-XXX

## Requirements

<!-- Extracted from PRD Module Breakdown requirements + related user story acceptance criteria.
     Each item must be one testable statement copied from the PRD. Do not combine requirements
     or split a single PRD requirement into sub-items unless the PRD itself uses sub-items.
     Do not add requirements not present in the PRD. -->

- 

## Input / Output Contract

<!-- From PRD module definition. Copy the exact input and output specifications stated in the PRD.
     If the PRD does not specify, write:
     [AMBIGUITY: PRD does not define the input/output contract for this module — needs PM clarification] -->

**Input:**

**Output:**

## Dependencies

<!-- List MOD-IDs this module depends on, as stated in the PRD. Do not infer dependencies
     not explicitly stated. If none are stated in the PRD, write "none". -->

- 

## Acceptance Criteria

<!-- Combined from PRD module criteria and related user story criteria.
     Format each criterion as: AC-NNN: The system shall [observable behavior] when [condition]
     Copy the criterion text from the PRD — do not reword. If the PRD criterion is not in this
     format, reformat it only to the extent of using "The system shall" wording while keeping
     the original behavioral statement intact.
     Preserve the AC-NNN IDs exactly as they appear in prd.md — do not renumber locally.
     Duplicate IDs across module specs indicate an error in the source PRD. -->

- AC-NNN: 

## Integration Points

<!-- Populated by Doc-Sync FROM AN EXPLICIT PRD REQUIREMENT ONLY — never inferred from a
     Dependencies field alone. A `Dependencies: MOD-X` entry with no concrete integration
     requirement in the PRD is not enough to fill in this section (see prd-format's
     "Implicit Dependencies" anti-pattern). If a module declares a dependency but the PRD
     states no concrete integration detail, write:
     [AMBIGUITY: MOD-X dependency declared but no concrete integration requirement stated in
     the PRD — needs PM clarification before engineering starts]
     and log it to status.md Sync Reports, same as any other AMBIGUITY.

     This section covers two distinct cases — cover both if both apply, write "none" if neither applies:

     CASE 1 — Embedding: this module exposes a component designed to be rendered from
     within another module's screen.
     For each embedding integration, name:
     1. The file in the other module that must be modified
     2. The exact component or prop to add
     3. Which module's engineer owns the change (default: upstream module's engineer implements;
        downstream module's engineer confirms it is done before QA handoff)
     4. The acceptance criterion that gates QA handoff

     Example:
     ### Integration with MOD-002 (Gym Directory) — Embedding
     - **File to modify:** `src/modules/mod-gym-directory/screens/GymDetailScreen.tsx`
     - **Change required:** Render `<RouteNavigator gymId={gym.id} gymName={gym.name} session={session} onBackToGym={onBack} />` at the bottom of the screen
     - **Owner:** engineer-mod-gym-directory implements; engineer-mod-route-catalog confirms before QA handoff
     - **AC:** AC-NNN: GymDetailScreen renders RouteNavigator with gymId, gymName, session, and onBackToGym

     CASE 2 — Conditional mounting: this module's component is only reached under a specific
     prop, flag, or mode passed by another module's screen — meaning a different component or
     code path could run instead depending on that condition. Name the exact condition so the
     assigned engineer never has to discover it by reading the other module's code.
     For each conditional-mounting integration, name:
     1. The parent file (in either this module or another) that decides which component mounts
     2. The exact condition (prop name, flag, mode value) that makes THIS module's component the live path
     3. What the alternate path is, if one exists, and whether it is still expected to run
     4. The acceptance criterion that gates QA handoff — must assert the live path, not just that the component works in isolation

     Example:
     ### Integration with MOD-006 (Route Detail) — Conditional Mounting
     - **Parent file:** `src/modules/mod-route-detail/screens/RouteDetailScreen.tsx`
     - **Live condition:** `RouteDetailScreen` always passes `onRegisterUploadLauncher`, which routes
       mounting to `BetaVideoSection`, not `BetaVideoUploader`
     - **Alternate path:** `BetaVideoUploader` only mounts when `onRegisterUploadLauncher` is absent —
       not expected to run in the current flow
     - **AC:** AC-NNN: Uploading from the route detail screen exercises `BetaVideoSection`'s upload path,
       not `BetaVideoUploader`'s
-->

none
