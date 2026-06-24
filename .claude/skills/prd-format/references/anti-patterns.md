# PRD Anti-Patterns

Common PRD mistakes with before/after examples. Each anti-pattern follows the same structure: what it is, a bad example, a good example, and why it matters.

---

## 1. Combining What and How

**What it is**: A requirement states the implementation technique or internal mechanism rather than the observable behavior the system must produce. The PRD defines what the system must do — not how it does it. Implementation details belong in production.md or a module spec, not the PRD.

**Bad**:
```
AC-004: The UserService.createSession() method shall generate a UUID v4, sign it with HMAC-SHA256 using the AUTH_SECRET environment variable, and write it to the `sessions` table with a TTL of 3600 seconds.
```

**Good**:
```
AC-004: The system shall create an authenticated session when a user submits valid credentials. The session shall expire after 60 minutes of inactivity. Subsequent requests using the session token shall be treated as authenticated until the session expires.
```

**Why it matters**: Implementation-level requirements lock engineers into a specific technical approach before any design discussion has happened. They also create a moving target: any refactor of the internals (e.g., switching from a database-backed session to a stateless JWT) breaks the acceptance criterion, even if the user-visible behavior is unchanged. The PRD should survive a complete re-architecture of the implementation.

---

## 2. Implicit Dependencies

**What it is**: A module depends on data, state, or behavior from another module but does not declare that dependency in its Dependencies field. The dependency exists in reality but is invisible in the document, so engineers build in isolation and discover the coupling at integration time.

**Bad**:
```markdown
### MOD-005: Notification Service
Purpose: Sends email notifications to users when order status changes.
Dependencies: none
```

**Good**:
```markdown
### MOD-005: Notification Service
Purpose: Sends email notifications to users when order status changes.
Dependencies: MOD-002 (Order Management — source of status-change events), MOD-001 (User Profiles — source of recipient email addresses)
```

**Why it matters**: Undeclared dependencies cause integration failures that are discovered late in the development cycle, when they are most expensive to fix. They also make phasing impossible: if MOD-005 is scheduled for Phase 1 but MOD-002 is Phase 2, the phase plan is broken — but no one can see the conflict without the explicit dependency declaration.

---

## 3. Vague Acceptance Criteria

**What it is**: An acceptance criterion describes a desirable quality rather than a testable condition. Words like "fast," "secure," "smooth," "user-friendly," or "reasonable" are not testable — they require the reviewer to apply judgment, which means two reviewers will reach different conclusions.

**Bad**:
```
AC-009: The system should be fast and responsive so users don't get frustrated.
AC-010: The login flow must be secure.
AC-011: Error messages should be helpful and not confuse users.
```

**Good**:
```
AC-009: The system shall render the dashboard with all data populated within 1.5 seconds (measured from navigation start) when the user has fewer than 10,000 records, under a load of 500 concurrent users.
AC-010: The system shall lock an account for 15 minutes after 5 consecutive failed login attempts from the same IP address. The lockout message shall not reveal whether the account exists.
AC-011: The system shall display a field-level inline error message identifying the specific validation rule violated when a form field fails validation, without clearing the user's other inputs.
```

**Why it matters**: Vague criteria are not quality gates — they are open invitations for disagreement at review time. Engineers will ship whatever they built, call it "fast enough," and move on. QA will reject it as "too slow." The PM will ask for a decision. The acceptance criterion existed to prevent exactly that conversation — if it cannot do so, it is not an acceptance criterion.

---

## 4. Scope Bleed

**What it is**: A requirement is placed under the wrong module. The module it is written under is not responsible for that behavior, so the requirement is either ignored (because the module's owner knows it doesn't belong to them) or double-built (because both the correct and incorrect module owner implement it).

**Bad**:
```markdown
### MOD-003: Product Catalog
Purpose: Manages product listings, descriptions, and pricing.

**AC-017**: The system shall send a confirmation email to the customer after a successful order is placed.
```
(AC-017 belongs to MOD-006 Order Management or MOD-005 Notification Service — not the Product Catalog.)

**Good**:
```markdown
### MOD-005: Notification Service
Purpose: Sends transactional emails triggered by system events.

**AC-017**: The system shall send an order confirmation email to the customer's registered email address within 60 seconds of an order reaching the CONFIRMED status.
```

**Why it matters**: When requirements are placed in the wrong module, ownership breaks down. The engineer building MOD-003 (Product Catalog) either skips AC-017 because they know it's wrong, or implements email sending inside the catalog module — creating a dependency and a responsibility that doesn't belong there. Either outcome means the requirement is not reliably delivered.

---

## 5. Orphan Requirements

**What it is**: A user story exists in Section 3 but no module in Section 6 claims responsibility for satisfying it. The story is real and approved, but there is no module that will actually build it.

**Bad**:
```markdown
## 3. User Stories

### US-008: Export Data
As a data analyst, I want to export query results to CSV so that I can analyze them in Excel.
Acceptance Criteria: AC-028, AC-029

---

## 6. Module Breakdown

### MOD-001: Query Builder
User Stories: US-006, US-007
Dependencies: none

### MOD-002: Data Visualization
User Stories: US-009, US-010
Dependencies: MOD-001
```
(US-008 is not referenced by any module — it is an orphan.)

**Good**:
```markdown
### MOD-003: Data Export
Purpose: Generates downloadable CSV files from query results.
User Stories: US-008
Dependencies: MOD-001 (Query Builder — source of result sets)
```

**Why it matters**: Orphan requirements are requirements that will not be built. They exist in the PRD, were approved by stakeholders, and are assumed to be in scope — but no team owns them. They surface as missed features at launch. The quality checklist catches this by requiring every US-ID to appear in at least one module's User Stories field.

---

## 6. Gold-Plating Specs

**What it is**: The PRD specifies capabilities beyond what the stated user need requires, driven by engineering enthusiasm for interesting problems or anticipation of hypothetical future requirements. This inflates scope, increases build time, and often produces features users never asked for.

**Bad**:
```markdown
### US-004: View Profile
As a registered user, I want to view my profile so that I can confirm my account information.
Acceptance Criteria: AC-014, AC-015

### MOD-004: User Profile Service
Purpose: Serves user profile data with a full CQRS architecture, event-sourced history of all profile changes, a GraphQL API supporting field-level subscriptions, and a configurable plugin system for third-party profile enrichment providers.
Dependencies: MOD-001
```
(US-004 is "view my profile" — none of the CQRS, event sourcing, GraphQL subscriptions, or plugin system is required by that story.)

**Good**:
```markdown
### MOD-004: User Profile Service
Purpose: Stores and serves the user's name, email address, and display preferences.
User Stories: US-004
Dependencies: MOD-001 (Authentication)
```

**Why it matters**: Gold-plating wastes engineering time, introduces complexity that must be maintained indefinitely, and frequently pushes out launch dates for features that users never requested. The PRD should describe the minimum system that satisfies the stated user stories — not the most impressive system an engineer could imagine.

---

## 7. Missing Non-Goals

**What it is**: A feature is not mentioned in the Non-Goals section, so stakeholders assume it is in scope. The PRD is technically not wrong — it never promised the feature — but the absence of an explicit exclusion creates an invisible assumption that causes conflict during development or at launch.

**Bad**:
```markdown
## 2. Goals & Non-Goals

### Goals
- Launch a web app for the global enterprise market by Q3.

### Non-Goals
- None at this time.
```
(The product targets the "global enterprise market" — this strongly implies i18n support, SSO integration, and an admin panel. None of these are excluded. Every stakeholder will assume they are in scope.)

**Good**:
```markdown
### Non-Goals
- Internationalization and localization are out of scope for v1. The product is US English only. i18n infrastructure is not required.
- SSO / SAML / OIDC federation is out of scope for v1. Enterprise identity provider integration is planned for v2.
- A self-service admin panel for customer configuration is out of scope for v1. Admin operations are performed via direct database access by the internal ops team.
- Native iOS and Android apps are out of scope. The web UI must be responsive to 320px, but no native mobile app will be built.
- Offline support is out of scope. The product requires a live internet connection.
```

**Why it matters**: A PRD that targets a "global product" without excluding i18n, or a "mobile-first brand" without excluding an offline mode, is a contract with invisible clauses. Stakeholders who assume those features are included will be blindsided at launch. Every unstated exclusion is a future scope-creep argument waiting to happen.

---

## 9. Dropping Human-Gate Conditions When Composing Sub-Agent Prompts

**What it is**: When an orchestrating agent (or conversation) composes an invocation prompt for a sub-agent, it may summarize or simplify the preceding agent's handoff output — and in doing so silently drop human-gate prerequisites that the preceding agent stated explicitly.

**Bad**:
```
Tech Lead output: "Before the PM tags [INIT], the user must complete setup.md and confirm the smoke check passes."
Orchestrator composes PM prompt as: "Resolve the Tech Lead conditions and tag [INIT]."
Result: PM tags [INIT] without the setup gate being satisfied — the gate was never forwarded.
```

**Good**:
```
Tech Lead output: "Before the PM tags [INIT], the user must complete setup.md and confirm the smoke check passes."
Orchestrator surfaces this to the user explicitly: "The Tech Lead requires you to complete setup.md before [INIT] can be tagged. Once done, confirm here."
User confirms setup → orchestrator invokes PM with setup confirmation included.
```

**Why it matters**: Human-gate instructions exist precisely because the system cannot verify them automatically. When an orchestrator drops them, the gate disappears entirely — the sub-agent never knew it existed and cannot enforce something it was not told about. The failure mode is silent: everything appears to proceed normally, but a required verification was skipped.

**Correct pattern**: Every human-gate condition stated by one agent must be surfaced to the user before the next agent is invoked. The user is the gate-keeper; the orchestrator is not permitted to decide the gate has been met by implication.

**Enforcement in this skill**: The setup gate is owned by the Tech Lead agent, not the PM. The Tech Lead creates `setup.md`, instructs the user to complete it and re-invoke Tech Lead, and records a Setup Confirmation entry in `status.md` when setup is verified. The PM then checks `status.md` for this confirmation entry before tagging [INIT] — checking an objective record rather than asking the user a yes/no question that can be bypassed. Neither agent can proceed without the other's gate being satisfied.

---

## 8. Ambiguous Ownership

**What it is**: Two or more modules both appear to be responsible for the same behavior, so each team assumes the other will handle it. The requirement exists in the PRD — possibly even with an AC — but is not clearly assigned to exactly one module. The result is that neither module builds it.

**Bad**:
```markdown
### MOD-002: Order Processing
Purpose: Validates and processes incoming orders. Sends status updates to customers.
User Stories: US-003, US-004
Dependencies: MOD-001

### MOD-005: Customer Communication
Purpose: Manages all outbound communication to customers including order updates and promotions.
User Stories: US-010, US-011
Dependencies: MOD-001
```
(Both MOD-002 and MOD-005 claim responsibility for sending order status updates to customers. The engineer building MOD-002 will assume MOD-005 handles it; the engineer building MOD-005 will assume MOD-002 already does it. It ships with neither doing it.)

**Good**:
```markdown
### MOD-002: Order Processing
Purpose: Validates and processes incoming orders. Emits an ORDER_STATUS_CHANGED event when an order status changes. Does not send customer notifications directly.
User Stories: US-003, US-004
Dependencies: MOD-001

### MOD-005: Customer Communication
Purpose: Listens for ORDER_STATUS_CHANGED events from MOD-002 and sends the appropriate transactional email to the customer.
User Stories: US-010, US-011
Dependencies: MOD-001, MOD-002
```

**Why it matters**: Ambiguous ownership is one of the most common sources of features that "fell through the cracks." Both teams were aware of the requirement; neither felt it was theirs to build. Explicit, non-overlapping module purpose statements eliminate this ambiguity. If a behavior could plausibly belong to two modules, the PRD must assign it to exactly one and note the boundary.
