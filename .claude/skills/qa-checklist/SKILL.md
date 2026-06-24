---
name: qa-checklist
description: Verification checklist for the QA agent — use for first-time module verification (functional-test workflow) or re-verification after a bug fix (regression-test workflow). Every failure needs a specific reproducible description.
---

<objective>
Verify that a module's implementation matches its spec. Test observable behavior. Every failure must be described with exact input, actual output, and expected output.
</objective>

<essential_principles>
- **Verify against the spec, not assumptions**: if the behavior isn't in the spec, it's not a bug — it's a feature request (route to PM, not Engineer)
- **Test observable behavior**: test what the system does, not how it does it internally
- **Every failure needs a specific reproducible description**: exact input, actual output, expected output per spec — "it's broken" is not a failure description
- **Spec ambiguity → escalate to PM**: if the spec doesn't define the correct behavior, that's a spec problem — escalate to PM, not Engineer
- **Never edit source code**: QA only reports; Engineer fixes
- **Backend modules (MOD-001–003): real server required**: code inspection and unit tests alone are not sufficient for a PASS. QA must start the server, hit real endpoints with curl and sample fixture files, and verify actual HTTP responses and database state.
- **MOD-004 (frontend): human checkpoint**: QA cannot verify a React UI via CLI. QA produces a written test script (what to navigate, what to click, what to verify) and explicitly hands off to the user for sign-off. QA does not declare PASS on ACs it cannot exercise in a browser.
</essential_principles>

<routing>
| Task | Action |
|------|--------|
| First-time module verification | Follow workflows/functional-test.md |
| Re-verification after bug fix | Follow workflows/regression-test.md |
| Running automated tests | Run scripts/run-qa.sh <module-name> <project-root> |
| Checking known failure gotchas | Read references/common-failure-patterns.md |
</routing>

<core_checklist>

**Functional**
- [ ] Every requirement in the module spec has been verified with a specific test case
- [ ] Every acceptance criterion (AC-NNN) has been tested and result recorded

**Edge Cases**
- [ ] Error states are handled correctly and produce appropriate output
- [ ] Empty/null inputs are handled without crashes or silent corruption
- [ ] Boundary values produce correct output
- [ ] Invalid data is rejected with an appropriate error (not silently accepted)

**Integration**
- [ ] Module follows shared conventions in production.md
- [ ] Module's actual inputs/outputs match the Input/Output Contract in the spec
- [ ] The module spec contains no HTML template comments (`<!-- ... -->`) — these indicate Doc-Sync did not finish cleaning the template
- [ ] **Backend modules only**: `setup.md` is consistent with actual infrastructure config — ports in `docker-compose.yml` match `setup.md`, all env vars referenced in `setup.md` exist in `.env.example`
- [ ] **Backend modules only**: `.gitignore` exists at the project root and `.env` is listed in it — verify with `grep '^\.env$' .gitignore` before marking any backend module PASS

**Spec Compliance**
- [ ] No features implemented that aren't in the spec (gold-plating check)
- [ ] No spec requirements left unimplemented

</core_checklist>

<output_format>
Log to status.md QA Results section:
- Pass/fail per requirement and acceptance criterion (reference by ID)
- For failures: `FAIL AC-NNN: Input=[x], Actual=[y], Expected=[z per spec]`
- For spec issues: `[SPEC ISSUE: <description> — escalate to PM, not Engineer]`
</output_format>

<quick_start>
1. Read modules/module-X/spec.md completely
2. Choose workflow: first time → workflows/functional-test.md; re-verify → workflows/regression-test.md
3. Run: scripts/run-qa.sh <module-name> <project-root>
4. Manually verify each item in <core_checklist>
5. Log all results to status.md QA Results section
</quick_start>

<success_criteria>
- All checklist items verified (pass or explicitly noted)
- Results logged to status.md QA Results section with spec references
- Failures have specific reproducible descriptions (not vague labels)
- Spec issues escalated to PM (not sent back to Engineer)
- Git commit: `git add status.md && git commit -m "qa(module-X): <pass|fail> — <summary>"`
</success_criteria>
