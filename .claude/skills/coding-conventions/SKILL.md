---
name: coding-conventions
description: Shared coding standards for Engineer and Tech Lead agents — use when writing or reviewing code. These are defaults; always also read production.md Shared Conventions for project-specific overrides.
---

<objective>
Define default coding conventions that all engineers follow. Defaults apply when production.md doesn't specify otherwise.
</objective>

<essential_principles>
- **Consistency over personal preference**: follow these conventions even when you disagree — inconsistent code is harder to read than imperfect code
- **production.md overrides**: always read production.md Shared Conventions first; project-specific entries there take precedence over these defaults
- **These are defaults, not absolute rules**: apply them wherever production.md is silent
</essential_principles>

<conventions>

<naming>
- Variables and functions: camelCase
- Classes and components: PascalCase
- Constants: UPPER_SNAKE_CASE
- Files: kebab-case for most; PascalCase for React components and class files
- Names: descriptive over abbreviations (userId not uid, isAuthenticated not isAuth, requestTimeout not rt)
</naming>

<files>
- Group by feature/module, not by type (don't put all controllers in /controllers and all models in /models)
- One component or class per file
- Index files for public API only — don't re-export internal implementation details through index.ts
</files>

<error_handling>
- Fail fast: detect errors early and surface them immediately rather than propagating bad state
- No silent catches: every catch block must either handle the error meaningfully or rethrow it with added context
- Propagate with context: wrap low-level errors with higher-level meaning ("failed to load user" not "ENOENT")
- Use typed errors where the language supports it
</error_handling>

<logging>
- Structured logging: key-value pairs, not string interpolation ("userId", userId not `user ${userId} logged in`)
- Log levels: debug for dev-only detail, info for operational milestones, warn for recoverable issues, error for failures requiring attention
- Never log sensitive data: no passwords, tokens, full credit card numbers, or PII
</logging>

<testing>
- One test file per source file
- Test behavior, not implementation: test what the function does, not how it does it internally
- Descriptive test names: "returns 401 when token is expired" not "auth test 3"
- Arrange-Act-Assert structure
</testing>

<commit_messages>
- Format: type(scope): description
- Types: feat (new feature), fix (bug fix), docs, refactor, test, chore
- Examples: feat(auth): add OAuth2 login, fix(api): handle null user in profile endpoint

**Orchestration commits** (agent handoff commits made before stopping) use agent-role types defined by the system architecture — these are a parallel convention, not conventional commit types:
- Format: agent-name(module-or-mode): description
- Examples: `engineer(mod-login): implement session token validation`, `qa(mod-login): pass — all 8 ACs verified`, `pm(init): initial PRD for payment service`
- Use conventional commits for code-level changes within a module; use agent-role types for the handoff commit that signals a workflow transition
</commit_messages>

</conventions>

<routing>
| Task | Action |
|------|--------|
| Need concrete code examples | Read references/style-examples.md |
| Project-specific conventions | Read production.md Shared Conventions section (overrides these defaults) |
</routing>

<success_criteria>
- Code passes linter configured in production.md
- All naming, error handling, logging, and testing conventions followed
- Commit message follows conventional commits format
- engineer-checklist self-check passes
</success_criteria>
