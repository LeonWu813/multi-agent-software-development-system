---
name: engineer-checklist
description: Pre-QA self-check items for the Engineer agent — run before handing off any module to QA. Run scripts/self-check.sh first for automated items, then verify judgment-based items manually.
---

<objective>
Self-verification process for Engineer before handing a module to QA. Automated script handles mechanical checks; manual judgment covers subjective quality.
</objective>

<essential_principles>
- **Self-check is not optional**: never hand off to QA without completing the full checklist
- **Automated first, manual second**: run scripts/self-check.sh first, then verify judgment-based items
- **Log everything to status.md**: record all results (pass/fail per item) in the Engineering Progress section — QA and Tech Lead read this
- **Stay in scope**: if a check reveals work needed outside this module's file boundary, write a blocker to status.md and stop — do not improvise
</essential_principles>

<process>
Step 0 (Phase 1 only): Run infrastructure pre-flight check before writing any code:
  - `.env` file exists at repo root (presence check only — do not read or log its contents)
  - Database connection succeeds using `DATABASE_URL` from the environment
  - `UPLOAD_DIR` exists and is writable by the server process
  If any check fails: stop, report the specific failure to the user, and do not proceed to implementation.

Step 1: Run `scripts/self-check.sh <module-name> <project-root>`
Step 2: Review automated check output — note which items passed and failed
Step 3: Run integration tests: `npm run test:integration` — must pass before handoff. Uses `DATABASE_URL_TEST`; never `DATABASE_URL`.
Step 4: Manually verify each judgment-based item in <judgment_items>
Step 5: Log all results (automated + manual + integration, pass/fail per item) to status.md Engineering Progress section
Step 6: Decision:
  - All pass → hand off to QA
  - Any fail → fix the issue and re-run from Step 1, including full re-verification of all judgment-based items in Step 4 (fixes can introduce new issues in adjacent code)
  - Blocked by out-of-scope issue → write a blocker entry to status.md and stop (do not work around it)
</process>

<automated_items>
Verified by scripts/self-check.sh:
- Build/compile succeeds without errors
- Linter passes (if a lint command is configured in production.md)
- Existing tests pass
- No files modified outside the assigned module's directory (checked via git diff)
</automated_items>

<judgment_items>
Manually verified by Engineer:
- Every requirement in modules/module-X/spec.md is implemented
- Every acceptance criterion in the module spec is addressed with observable behavior
- Edge cases handled: empty inputs, boundary values, error states, invalid data
- No hardcoded values that should be configurable (URLs, timeouts, limits, environment identifiers)
- Code follows conventions in coding-conventions skill and production.md Shared Conventions
- No new dependencies introduced that aren't listed in production.md Tech Stack
- Code is readable: another engineer could understand it without asking questions or reading internal comments
- If writing integration tests that use both a real database connection and Jest mocks: `beforeEach` must call both `jest.clearAllMocks()` (resets mock call counts and return values) AND `await testDb.delete(table)` or equivalent DB teardown — omitting either causes non-deterministic failures (`clearAllMocks()` omitted bleeds mock call counts across tests; DB teardown omitted bleeds real rows across tests; both must be in `beforeEach`, not `beforeAll`)
- If the module calls an AI/LLM API: the model identifier is not hardcoded as a string literal — read it from `process.env.MODEL_VAR ?? "default-model"` and add the env var to `.env.example` with a comment (hardcoded model names are environment-specific and block live verification when unavailable)
- If the module constructs LLM prompts from user-supplied text: a context window token budget is defined and enforced — see references/llm-prompt-context-budget.md
- If the backend uses Spring Boot and exposes a health check endpoint (required by any load balancer, container orchestration system, or deployment pipeline): `spring-boot-starter-actuator` must appear as an explicit dependency in pom.xml — never rely on transitive inclusion. Also set `management.health.redis.enabled=false` and `management.health.db.enabled=false` unless the Redis and DB health indicators are explicitly required by spec, to prevent 503 responses when those services are slow to respond.
- If the backend exposes `/actuator/health` for a load balancer or orchestration health check AND uses Spring Security: the health endpoint must be explicitly permitted without authentication. Add `.requestMatchers("/actuator/health").permitAll()` to the SecurityConfig `http.authorizeHttpRequests` chain. Without this, any JWT or session filter will return 401 to the unauthenticated health checker, causing the load balancer to mark the instance as unhealthy regardless of whether the application is actually running.
- If the module defines a `@RestControllerAdvice` exception handler class: it must be annotated with `@Order(Ordered.HIGHEST_PRECEDENCE)`. Any project-wide catch-all `@RestControllerAdvice` (e.g., GlobalExceptionHandler with `@ExceptionHandler(Exception.class)`) must be annotated with `@Order(Ordered.LOWEST_PRECEDENCE)`. Omitting `@Order` causes Spring to resolve ties non-deterministically, often routing specific exceptions to the catch-all and returning HTTP 500.
</judgment_items>

<quick_start>
1. `scripts/self-check.sh <module-name> <project-root>`
2. Verify each item in <judgment_items>
3. Log all results to status.md Engineering Progress
4. Commit: `git add <module-source-files> status.md && git commit -m "engineer(module-X): <summary>"`
</quick_start>

<success_criteria>
- All automated items pass (script exits 0)
- All judgment-based items verified as passing
- Results logged to status.md Engineering Progress section
- Git commit made before stopping
</success_criteria>
