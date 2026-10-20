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
Step 0 (first module of the project only): Run the infrastructure pre-flight check before writing any code:
  - `.env` file exists at repo root if `setup.md` requires one (presence check only — do not read or log its contents)
  - Every service `setup.md` lists (database, cache, storage, external API sandbox) is reachable, using the check `setup.md` gives for it
  If any check fails: stop, report the specific failure to the user (Last Action `result: needs-human`), and do not proceed to implementation.

Step 1: Run `scripts/self-check.sh <module-name> <project-root>`
Step 2: Review automated check output — note which items passed and failed
Step 3: Run the project's integration tests, if `production.md` Shared Conventions or `setup.md` names an integration-test command — they must pass before handoff. Use the test database or test environment the project defines, never the development or production one.
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
- No files changed outside the module's Source Path (status.md Module Map) and its own planning files — tracked and untracked changes both count
</automated_items>

<judgment_items>
Manually verified by Engineer:
**Always:**
- Every requirement in `project-planning/modules/<dir>/spec.md` is implemented
- If the spec's "Integration Points" section names a cross-module wiring task: verify the wiring is implemented before handing off to QA. If the wiring requires changes in another module's files and you are not that module's assigned engineer, write a blocker to status.md and stop — do not implement cross-boundary changes without explicit assignment.
- If the spec's "Integration Points" section names a conditional-mounting condition (Case 2): verify your implementation is reached through that exact condition, checked entirely within your own module's code — do not open another module's files to confirm this; the condition is already named in your spec for exactly this reason. If your spec names no conditional-mounting entry but your AC depends on a UI entry point, implement normally — do not go looking for a hidden alternate path.
- Integration tests for any AC with a UI entry point must mount your module's real production configuration (the actual parent/props/mode your spec's Integration Points describes), not an isolated leaf component rendered in test-only isolation. A test that never reaches the production entry point is not evidence the feature works.
- If a test mocks an entire framework module that provides hooks or context (navigation, state store, dependency injection, theming, i18n, data-fetching client): confirm the mock reflects whether your component is actually rendered with that provider/ancestor in production. If your component is ever mounted without that ancestor (e.g. a keep-alive or background-rendered screen), the test must not mock the hook into silently working — it must exercise the real degraded behavior your component needs in that context.
- Before implementing a fix for a runtime bug (not a straightforward logic bug with an obvious single-location cause): state the layer where you observed the bad output, with the specific evidence. If you cannot confirm a single layer — because the diagnosis spans a multi-step call path (e.g. picker → upload → storage → player) or depends on OS/third-party runtime behavior you can't fully observe from code — do not guess and do not implement. Write a blocker listing each plausible layer as a numbered hypothesis, with the specific evidence that would confirm or rule out each one, and stop. This requires human (or device-level) investigation to pick the correct hypothesis before any fix is implemented.
- Before implementing a fix (especially a second attempt at the same symptom): write a one-line impact note — what else in your module reads or depends on the code you're about to change — and confirm your fix doesn't break those dependents.
- If writing a Jest mock for an external API function whose return value depends on options or arguments: the mock must inspect call arguments and return a shape that reflects what the real API returns for those exact arguments — not a flat object with all fields populated unconditionally. Check the installed library's `.d.ts` file (not public documentation, which may describe a different version) to confirm which fields are unconditional and which are option-gated.
- If adding or modifying a query built via a string or DSL whose validity is determined by the backend at runtime, and which neither TypeScript nor your test's mock can validate (e.g. a raw embed/join string, a dynamically-assembled ORM query, a hand-built GraphQL document): exercise the exact query against a real or local backend instance before marking the AC done, and record the verification (the query run, or the URL hit) in this module's `status.md` Engineering Progress — a verification that exists only in memory is indistinguishable from one that was skipped.
- Every acceptance criterion in the module spec is addressed with observable behavior
- Edge cases handled: empty inputs, boundary values, error states, invalid data
- No hardcoded values that should be configurable (URLs, timeouts, limits, environment identifiers)
- Code follows conventions in coding-conventions skill and production.md Shared Conventions
- No new dependencies introduced that aren't listed in production.md Tech Stack
- Code is readable: another engineer could understand it without asking questions or reading internal comments
- Before querying or joining a table, collection, or API owned by another module: read its migration, schema, or contract for the real field names. Never infer them from naming. Record any non-obvious schema fact in Engineering Progress so Tech Lead can propose it as a convention.
- No TRACE or DEBUG log levels for framework or third-party loggers in committed production configuration. Remove any verbose logging you added for debugging before handoff.

**Only if your stack matches** (skip items that don't apply, and say so in Engineering Progress):
- If writing integration tests that use both a real database connection and Jest mocks: `beforeEach` must call both `jest.clearAllMocks()` (resets mock call counts and return values) AND `await testDb.delete(table)` or equivalent DB teardown — omitting either causes non-deterministic failures (`clearAllMocks()` omitted bleeds mock call counts across tests; DB teardown omitted bleeds real rows across tests; both must be in `beforeEach`, not `beforeAll`)
- If the module calls an AI/LLM API: the model identifier is not hardcoded as a string literal — read it from `process.env.MODEL_VAR ?? "default-model"` and add the env var to `.env.example` with a comment (hardcoded model names are environment-specific and block live verification when unavailable)
- If the module constructs LLM prompts from user-supplied text: a context window token budget is defined and enforced — see references/llm-prompt-context-budget.md
- If the backend uses Spring Boot and exposes a health check endpoint (required by any load balancer, container orchestration system, or deployment pipeline): `spring-boot-starter-actuator` must appear as an explicit dependency in pom.xml — never rely on transitive inclusion. Also set `management.health.redis.enabled=false` and `management.health.db.enabled=false` unless the Redis and DB health indicators are explicitly required by spec, to prevent 503 responses when those services are slow to respond.
- If the backend exposes `/actuator/health` for a load balancer or orchestration health check AND uses Spring Security: the health endpoint must be explicitly permitted without authentication. Add `.requestMatchers("/actuator/health").permitAll()` to the SecurityConfig `http.authorizeHttpRequests` chain. Without this, any JWT or session filter will return 401 to the unauthenticated health checker, causing the load balancer to mark the instance as unhealthy regardless of whether the application is actually running.
- If the module builds container images for a cloud deploy: pin the target architecture in every build script, CI job, and runbook command (e.g. `docker buildx build --platform linux/amd64`), and confirm it with `docker inspect --format '{{.Architecture}}' <image>`. Images built on Apple Silicon default to arm64 and fail on amd64 hosts.
- If the backend uses Spring and configures CORS with a wildcard or pattern origin: use `setAllowedOriginPatterns(...)`, not `setAllowedOrigins(...)` — the latter rejects wildcards when credentials are allowed.
- If the module is a React Native / Expo screen: wrap content in the safe-area insets (`SafeAreaView` or `useSafeAreaInsets`) so it clears the notch, Dynamic Island, and home indicator; check on a device or simulator with a notch, not only on web.
- If the module defines a `@RestControllerAdvice` exception handler class: it must be annotated with `@Order(Ordered.HIGHEST_PRECEDENCE)`. Any project-wide catch-all `@RestControllerAdvice` (e.g., GlobalExceptionHandler with `@ExceptionHandler(Exception.class)`) must be annotated with `@Order(Ordered.LOWEST_PRECEDENCE)`. Omitting `@Order` causes Spring to resolve ties non-deterministically, often routing specific exceptions to the catch-all and returning HTTP 500.
</judgment_items>

<quick_start>
1. `scripts/self-check.sh <module-name> <project-root>`
2. Verify each item in <judgment_items>
3. Log all results to status.md Engineering Progress
4. Commit: `git add <Source Path files> project-planning/modules/<dir>/status.md project-planning/status.md && git commit -m "engineer-<dir>(<implement|bugfix|integration-fix|spec-update|scope-fix|wip>): <summary>"`
</quick_start>

<success_criteria>
- All automated items pass (script exits 0)
- All judgment-based items verified as passing
- Results logged to status.md Engineering Progress section
- Git commit made before stopping
</success_criteria>
