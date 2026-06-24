# Functional Test Workflow

First-time module verification procedure. Follow every step in order. Do not skip ahead — reading the spec fully before touching any test tooling is mandatory.

---

## Steps

### 1. Read the full spec before doing anything else

Open `modules/module-X/spec.md` and read it completely. Do not start designing tests, running scripts, or checking any code until you have finished reading the entire spec.

What to capture as you read:
- Every stated requirement (label each REQ-NNN for your own tracking)
- Every acceptance criterion (AC-NNN as written in the spec)
- The Input/Output Contract section — note exact types, shapes, and constraints
- Any error-handling behavior that is explicitly defined

If the spec is missing an AC identifier for a requirement, assign a local label (e.g. REQ-07) and note in status.md that the spec lacks a formal ID.

---

### 2. Read production.md for integration context

Open `project-planning/production.md` and read the **Shared Conventions** and **Module Index** sections. You need to know:
- Naming conventions, file structure conventions, error format conventions that all modules must follow
- What other modules this module interacts with and in what direction
- The test command configured for this project (you will use it in step 5)

---

### 2a. Backend modules only: verify setup.md matches infrastructure config

`setup.md` is written by Tech Lead before implementation. By the time QA runs, the actual infrastructure files may have diverged. QA is the last verification gate and is best positioned to catch this.

Check the following:

1. Every port number in `project-planning/setup.md` matches the host port in `docker-compose.yml`
2. Every environment variable referenced in `setup.md` exists in `.env.example`

If a mismatch is found, log it as a FAIL — this is an infrastructure documentation issue, not a spec issue. Route to Engineer (update `setup.md` to match what was actually implemented).

Example failure entry:
```
FAIL setup.md: setup.md states dev database on port 5432 but docker-compose.yml maps db_dev to host port 5434
```

Skip this step for MOD-004 (frontend) — it has no infrastructure config.

---

### 3. Build your test checklist from the spec

From what you read in step 1, create an explicit checklist — one line per requirement or acceptance criterion:

```
- [ ] AC-001: <brief description>
- [ ] AC-002: <brief description>
- [ ] REQ-07 (no AC id in spec): <brief description>
...
```

Every item that appears in the spec must appear in this list. No item in this list should come from assumptions not in the spec.

---

### 4. Design a verification approach for each requirement

For each checklist item, decide before testing how you will verify it:

- **Automated**: the test suite covers this; a passing run is sufficient evidence
- **Manual**: requires direct inspection, calling the module with specific inputs, or observing output
- **Both**: automated tests exist but the item also requires a judgment call (e.g. "output is user-readable")

Document your approach next to each item. This prevents post-hoc rationalization of results.

---

### 5. Run the automated test suite

```bash
scripts/run-qa.sh <module-name> <project-root>
```

- Capture the full output (pass count, fail count, any error messages)
- Record the exit code
- If the script warns that no test command was found in production.md, note this in status.md and proceed with manual verification only

Do not interpret a green automated run as "done" — automated tests rarely cover every AC.

---

### 5a. Backend modules only (MOD-001–003): live server verification

After the automated suite passes, verify real HTTP behavior:

1. Confirm `.env` exists and `DATABASE_URL_TEST` is set (file presence only — do not read or log contents)
2. Start the server:
   ```bash
   npm run dev &
   SERVER_PID=$!
   sleep 3
   ```
3. Run curl against each endpoint defined in the module's Input/Output Contract, using real sample fixture files (a small PDF and a `.txt` file). Capture the full response body and HTTP status code for each call.
4. Verify database state after write operations: query the test database directly to confirm records were created, updated, or deleted as expected.
5. Stop the server:
   ```bash
   kill $SERVER_PID
   ```

Record each curl call, its response, and the observed database state in status.md alongside the AC it verifies.

**If the server fails to start** (missing env vars, DB not running, migration not applied), stop and report the specific error to the user before continuing. Do not declare any AC as PASS if the server did not run.

---

### 5b. MOD-004 (frontend): human checkpoint

QA cannot verify a React UI via CLI tools alone. Instead:

1. Run the automated test suite and integration tests as usual.
2. Produce a written test script in status.md under QA Results covering every AC:
   - AC-023: navigate between each view — describe which links/buttons to click and what URL or content change confirms navigation happened without a full reload
   - AC-024: submit an AI request — describe where to look for the loading indicator appearing within 300ms, and the response replacing it
   - AC-025: trigger an API error — describe how to simulate a failure and what the non-blocking notification should say
   - AC-026: resize the browser to 375px width — describe which views and controls to check for clipping or horizontal scroll
3. End with: "**Human sign-off required.** Complete the test script above at 375px and full-width viewports and confirm each AC passes before marking MOD-004 as QA PASS."
4. Do not write a PASS verdict for MOD-004 until the user explicitly confirms.

---

### 6. Manually verify judgment-based checklist items

Work through every item in the `<core_checklist>` from SKILL.md that cannot be confirmed by the automated run alone. This includes:

- Edge cases: empty input, null input, boundary values, invalid data
- Integration: does actual I/O match the spec's Input/Output Contract?
- Spec compliance: is there anything implemented that isn't in the spec (gold-plating)?
- Error handling: do error states produce the output the spec describes?

For each manual check, record your exact test input and the exact output you observed.

---

### 7. Document results in status.md

Under the **QA Results** section of `status.md`, record:

- One line per AC/REQ: `PASS AC-001` or `FAIL AC-001: Input=[x], Actual=[y], Expected=[z per spec]`
- Any spec issues found: `[SPEC ISSUE: AC-004 does not define behavior when input is empty — escalate to PM]`
- Automated test summary: total passed, total failed, exit code
- Manual check summary: which items were manually verified and results

Use exact IDs from the spec. "Everything looks fine" is not a result entry.

---

### 8. Classify every failure

For each `FAIL` entry you logged, make an explicit routing decision:

| Failure type | Route to |
|---|---|
| Implementation does not match what the spec requires | Engineer |
| Spec is silent or ambiguous about this behavior | PM |
| Spec has an internal contradiction | PM |
| Behavior matches spec but spec is wrong | PM |

Write your routing decision next to each failure in status.md. Do not send spec problems to Engineer — Engineer cannot fix a spec.

---

## Completion

When all steps are done:

```bash
git add status.md && git commit -m "qa(module-X): <pass|fail> — <one-line summary>"
```

If any failures were found, do not mark the module as passing. The summary should reflect the actual outcome: `qa(module-X): fail — AC-003 rejects valid input, AC-007 crashes on empty string`.
