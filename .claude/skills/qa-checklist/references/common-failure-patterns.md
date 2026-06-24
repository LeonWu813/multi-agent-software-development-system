# Common Failure Patterns

> **Living document.** The Retrospective agent adds project-specific patterns to this file over time as recurring failures are identified. The 5 patterns below are universal starting points — not an exhaustive list.

---

## 1. Off-by-one errors

Loops that execute one too many or one too few times, array indexing that silently misses the last (or first) element, and range boundaries that treat inclusive and exclusive endpoints inconsistently.

**What to look for:**
- `< length` vs `<= length` in loop conditions — which one is correct for this use case?
- Pagination logic using `index + 1` or `page * size` where an off-by-one shifts an entire result set
- Date range calculations where "last 7 days" returns 6 or 8 days depending on whether today is included
- Fence-post errors: a function that processes items 1–10 but skips item 10 or processes item 11
- Slice/substring calls where the end index is exclusive but the spec says inclusive

**Test approach:** use inputs where the boundary is the data itself — a list of exactly N items, a range that starts or ends on today, a page that contains exactly the page-size limit.

---

## 2. Null/undefined handling at module boundaries

Values that are valid internally (unit tests always pass non-null) but arrive as null or undefined when flowing in from another module. The module has no null check at the top of its public functions, so the null propagates inward and produces a confusing error deep in the call stack instead of a clear boundary error.

**What to look for:**
- Public function parameters that are never null in unit tests but can be null when called from the module that produces them
- Missing null checks at the entry point of any function that is called by another module
- Optional chaining (`?.`) or null-coalescing (`??`) that silently swallows a null instead of raising an error — the output is wrong but no exception is thrown
- Functions that destructure their parameters without first checking whether the parameter exists

**Test approach:** call the module's public interface with `null`, `undefined`, and missing properties on object inputs. The spec defines what should happen — either a clear error or a documented default. Anything else is a failure.

---

## 3. Async operations without proper error handling

Promise rejections that are never caught, `async` functions called without `await` causing the operation to run but its result to be discarded, and fire-and-forget operations that silently fail while the caller assumes success.

**What to look for:**
- `.then()` chains that have no `.catch()` — a rejection will become an unhandled promise rejection
- `async` functions that are called without `await` — the function runs but the caller does not wait for it and any error is swallowed
- Event listeners or callbacks that call `async` functions but cannot `await` them, meaning errors are lost
- "Write and continue" patterns (logging, analytics, cache writes) where failure is silently ignored but the spec requires durability

**Test approach:** simulate failure in the async dependency (network error, database rejection, timeout) and observe whether the module surfaces the error or proceeds as if it succeeded.

---

## 4. Hardcoded values that should come from config

Magic numbers, hardcoded URLs, environment-specific strings, and timeout values embedded directly in code rather than drawn from configuration. These work in one environment and silently produce wrong behavior in another.

**What to look for:**
- IP addresses or hostnames written as string literals (e.g. `"192.168.1.1"`, `"localhost"`)
- Port numbers as raw integers (e.g. `3000`, `5432`) instead of `process.env.PORT`
- File paths that are absolute on the developer's machine
- Timeout or retry values as unexplained raw numbers (e.g. `setTimeout(fn, 5000)` with no constant name)
- Environment names in conditionals (e.g. `if env == "production"`) that will break when deployed to staging

**Test approach:** check the spec's configuration contract — what values is the module supposed to accept from config? Verify that those values are actually being read from config, not hardcoded. Change a config value and confirm the module reflects the change.

---

## 5. Missing input validation

The module accepts invalid data at its public boundary and passes it inward, where it causes a confusing error deep in the call stack or, worse, silently produces corrupted output. The correct behavior is a clear validation error at the boundary — before any processing begins.

**What to look for:**
- No type check on inputs coming from external sources (HTTP request body, file input, inter-module calls)
- No bounds check on numeric inputs — negative numbers, zero, or values above a maximum accepted without error
- No length check on strings — empty string accepted where non-empty is required, or arbitrarily long strings accepted without truncation or rejection
- Object inputs accepted without checking that required fields are present
- Arrays accepted without checking for empty when at least one element is required

**Test approach:** for every public input defined in the spec's Input/Output Contract, send: an empty value, a wrong type, a value below the minimum, a value above the maximum, and a missing required field. The spec defines what response each invalid input should produce — confirm the module matches it exactly.

---

## 6. Synchronous throws that escape try/catch in Express 4 middleware

Express 4.x does not automatically catch synchronous throws inside middleware or route handler functions. If a function called synchronously inside a middleware throws before any async work begins, Express 4's default error handler catches it and returns an HTML error page — not the structured JSON error body required by most API conventions. Express 5 fixes this, but Express 4 (still widely used) does not.

**What to look for:**
- Any synchronous function call inside an Express middleware or route handler that is not wrapped in its own try/catch — especially calls that build or initialize something using environment variables, configuration, or filesystem state
- Pattern: `const middleware = buildSomething(process.env.X)` called at request time without a surrounding try/catch — if `buildSomething` throws (e.g. because `X` is unset), Express 4 renders an HTML error page
- The outer async try/catch does not protect against synchronous throws that occur before the first `await`
- Unit tests and static analysis will not catch this: the synchronous throw only surfaces at runtime with a specific bad environment condition

**Test approach:** For any endpoint that reads environment variables or performs startup-time validation at request time, verify the response with that variable deliberately unset or set to an invalid value against a running server. A green unit test suite is not sufficient evidence of compliance with the error-response convention — live server verification with the bad-env scenario is required.

**Express 4 specifics:**
- Express 4 wraps async route handlers only when they explicitly pass errors to `next(err)` — a synchronous throw that is not caught will propagate to the default error handler and produce HTML
- Fix pattern: wrap any synchronous function call that may throw in its own try/catch block, returning a structured JSON error body on catch

---

## 7. SPA + Express API route namespace collision

When a React SPA and an Express API server share a single origin (same host and port), Express route handlers can intercept browser navigation requests intended for the SPA client router, returning JSON instead of the `index.html` that the SPA needs to boot. This happens because Express processes routes top-to-bottom: if `GET /applications` is registered as a JSON API route, a browser refresh at `/applications` hits that route and receives JSON, not the HTML page.

**What to look for:**
- Express API routes registered at paths that are also valid SPA client-side routes (e.g. `/documents`, `/applications`, `/analysis`)
- SPA fallback route (`app.use('*', serveFile('index.html'))`) mounted after API routes without those API routes being namespaced
- Browser refresh at any non-root SPA route returning JSON instead of the HTML page
- API client code calling routes without a namespace prefix, making them collide with SPA paths by default

**Standard fix:** Prefix all backend API routes with a dedicated namespace (e.g. `/api/`) so the SPA fallback catch-all only receives requests that are not API calls. Mount the SPA fallback as the last route in `server.ts`. Vite proxy config (for dev) and Express static + fallback config (for production) must both reflect the `/api/` prefix.

**Test approach:** After starting the full-stack server with the built SPA, attempt a direct browser navigation (or `curl -H "Accept: text/html"`) to each SPA route path (e.g. `http://localhost:3000/applications`). The response must be `text/html` (the SPA shell), not `application/json`. Also confirm that `curl http://localhost:3000/api/applications` returns the expected JSON API response.

---

## 8. Spring Boot Actuator health endpoint absent or returning 503 unexpectedly

If the backend exposes `/actuator/health` for a load balancer or deployment health check and that endpoint returns 404 or 503, the most common causes are:

1. `spring-boot-starter-actuator` is absent from pom.xml and the endpoint was only reachable via a transitive dependency that was disrupted when other dependencies changed.
2. `spring-boot-starter-actuator` is present, but Redis or DB health indicators auto-registered and the external service is slow — causing the aggregate status to be DOWN (503) even though the application itself is running correctly.

**Fix for (1):** Add explicit `spring-boot-starter-actuator` to pom.xml.
**Fix for (2):** Set `management.health.redis.enabled=false` and `management.health.db.enabled=false` in application.properties unless those health checks are required by spec.

**Test approach:** After starting the server, curl `/actuator/health` before registering it with any load balancer. Confirm the response is HTTP 200 with `{"status":"UP"}`, not 404 or 503.

---

## 9. Spring @RestControllerAdvice tie-breaking: specific exceptions returning HTTP 500

When multiple `@RestControllerAdvice` beans exist (typically one global catch-all and several module-specific handlers), Spring may route exceptions to the wrong handler if `@Order` is not set. The most common symptom: a well-typed exception (e.g., `InvalidCredentialsException`, `NotFoundException`) returns HTTP 500 instead of the expected status code (401, 404, 429, etc.) even though a correct `@ExceptionHandler` for that type exists.

**Root cause:** all `@RestControllerAdvice` beans without an explicit `@Order` annotation default to `Ordered.LOWEST_PRECEDENCE`. When two beans share the same precedence and one is a catch-all (`@ExceptionHandler(Exception.class)`), Spring's tie-breaker is non-deterministic — the catch-all often wins.

**Fix:** Annotate every module-specific exception handler with `@Order(Ordered.HIGHEST_PRECEDENCE)`. Annotate the global catch-all with `@Order(Ordered.LOWEST_PRECEDENCE)`.

**Test approach:** For every exception type that should return a non-500 status code, trigger it against a running server and verify the exact HTTP status. Unit tests with `@WebMvcTest` slices may not reproduce this — full Spring context wiring (`spring-boot:run` or integration test with `@SpringBootTest`) is required to see the bean ordering resolution.
