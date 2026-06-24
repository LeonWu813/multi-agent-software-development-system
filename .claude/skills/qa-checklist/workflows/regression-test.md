# Regression Test Workflow

Re-verification after a bug fix. Use this workflow — not the functional-test workflow — when an Engineer has returned a module after fixing a reported bug.

The goal is two-fold: confirm the original bug is gone, and confirm nothing else broke in the process.

---

## Steps

### 1. Read the original bug description from status.md

Open `status.md` and find the **QA Results** section from the previous QA run. Locate the specific failure entry that triggered this fix. Extract:

- The exact `FAIL AC-NNN` line that was reported
- The exact `Input=`, `Actual=`, and `Expected=` values recorded
- Any adjacent failures from the same run that may be related

You must reproduce the original failure scenario precisely. If you cannot reconstruct the exact scenario from the status.md entry, that is a documentation gap — note it, then use the closest approximation you can.

---

### 2. Verify the specific reported bug is fixed

Reproduce the original failure scenario exactly:
- Use the same input that was recorded in the failure entry
- Observe the actual output
- Compare against the expected output from the spec

If the original scenario now produces the expected output: the bug is fixed. Record: `REGRESSION PASS AC-NNN: original failure scenario resolved`.

If the original scenario still fails: the fix did not work. Record the new `FAIL` entry with updated `Input=`, `Actual=`, `Expected=` and route back to Engineer.

Do not assume the fix worked because the Engineer says it did. Verify independently.

---

### 3. Re-run all previously passing tests

Fixes frequently break adjacent behavior. Run through every item that passed in the previous QA run:

- Review the previous passing entries in status.md
- Re-verify each one — either by re-running the automated suite or by repeating the manual check
- A test that passed before must still pass now

Do not only test the fixed item. A fix that resolves AC-003 by breaking AC-001 is not a fix — it is a regression.

---

### 4. Run the automated test suite

```bash
scripts/run-qa.sh <module-name> <project-root>
```

- Compare pass/fail counts against the previous run
- Any test that newly fails is a regression introduced by the fix
- Record the full output and exit code in status.md

---

### 5. Pay extra attention to code adjacent to the fix

Regressions most commonly appear in logic that is near — not identical to — the changed code. When reviewing results, pay extra attention to:

- Requirements that share data with the fixed requirement (same inputs, same outputs, same data structure)
- Error handling paths near the fix — fixes often add early returns or conditionals that affect other error paths
- Any AC that the Engineer's fix description mentions as "related" or "affected"

If you find a new failure in adjacent logic, log it as a new `FAIL` entry distinct from the original failure. Label it clearly: `NEW REGRESSION AC-NNN: introduced by fix for AC-MMM`.

---

### 6. Update status.md QA Results section

Append a new dated block to the QA Results section — do not overwrite the original run. The new block must:

- Be clearly labeled as a regression test run (e.g. `## QA Run 2 — Regression — 2026-05-13`)
- State which bug was being re-verified (reference the original AC-NNN)
- Record `REGRESSION PASS` or `REGRESSION FAIL` for the original bug
- Record pass/fail for every other item that was re-tested
- Call out any new regressions with `NEW REGRESSION` prefix
- Include automated test summary (counts, exit code)

Distinguishing runs matters. If a second Engineer fix is needed, they need to see the history clearly.

---

## Completion

When all steps are done:

```bash
git add status.md && git commit -m "qa(module-X): <pass|fail> — regression test, <one-line summary>"
```

Examples:
- `qa(module-X): pass — regression test, AC-003 fix verified, no new regressions`
- `qa(module-X): fail — regression test, AC-003 still failing + new regression AC-001`
