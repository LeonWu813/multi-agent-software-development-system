# PRD Writing Standards

This document defines the authoring standards the PM agent enforces when creating or reviewing a PRD. Every section includes actionable rules and concrete good/bad examples.

---

## 1. Writing Measurable Requirements

**Rule**: If you cannot write a pass/fail test for a requirement, the requirement is not ready. Rewrite it until it is.

The test is simple: hand the requirement to an engineer and ask, "how would you know when this is done?" If the answer involves judgment calls or interpretation, the requirement needs more precision.

### Performance Targets

| Bad | Good |
|-----|------|
| "The system must be fast." | "The API shall respond to 95% of requests within 200ms under a load of 1,000 concurrent users, measured at the load balancer." |
| "Pages should load quickly." | "The home page shall achieve a Largest Contentful Paint (LCP) of ≤ 2.5 seconds on a simulated 4G connection in Lighthouse." |
| "The system must handle high traffic." | "The ingestion pipeline shall process 10,000 events per second sustained over 5 minutes without message loss, as measured by comparing input and output event counts." |

### Functional Requirements

| Bad | Good |
|-----|------|
| "Users can log in." | "The system shall authenticate a user with valid credentials and return a session token within 500ms. Invalid credentials shall return HTTP 401 with a generic error message (no credential detail shall be leaked)." |
| "Admins can manage users." | "An authenticated user with the ADMIN role shall be able to deactivate any non-ADMIN account. Deactivation shall revoke all active sessions for the target account within 60 seconds." |
| "The form should have good validation." | "The registration form shall display an inline error message per field when a required field is submitted empty, when an email address does not match RFC 5322 format, or when a password is fewer than 12 characters." |

### Data Constraints

| Bad | Good |
|-----|------|
| "Store user data securely." | "Passwords shall be stored as bcrypt hashes with a cost factor of ≥ 12. Plaintext passwords shall never be written to logs, database columns, or error messages." |
| "The system should handle large files." | "File uploads shall support files up to 500 MB. Uploads exceeding 500 MB shall be rejected with HTTP 413 before any bytes are written to storage." |
| "Keep reasonable audit logs." | "Every write operation on the `orders` table shall produce an audit log entry recording: timestamp (UTC, millisecond precision), actor user ID, operation type (INSERT/UPDATE/DELETE), and a JSON diff of the changed fields." |

---

## 2. User Stories

**Format**: `As a [role], I want [capability] so that [benefit].`

Every user story must have:
- A unique `US-XXX` ID (assigned sequentially, never reused)
- A **role** — a specific actor (e.g., "warehouse operator", "billing admin"), not a generic one (e.g., "user", "person")
- A **capability** — a concrete action the actor wants to perform
- A **benefit** — the outcome the actor achieves (not an implementation outcome — a user value)
- At least one `AC-NNN` acceptance criterion

### Good/Bad Examples

**Bad story — missing ID, vague role, no benefit**:
> As a user, I want to reset my password.

Problems: no US-ID; "user" is too generic; the benefit is omitted; no AC reference.

**Good story**:
> **US-007**: As a **registered customer**, I want to reset my password via a time-limited email link so that I can regain access to my account without contacting support.
> **Acceptance Criteria**: AC-021, AC-022, AC-023

---

**Bad story — capability describes implementation, not user need**:
> US-012: As an admin, I want the system to send a POST request to /api/notifications so that emails are sent.

Problems: the capability is an implementation detail (POST to an endpoint), not a user need.

**Good story**:
> **US-012**: As a **billing admin**, I want to receive an email notification when an invoice payment fails so that I can follow up with the customer before their account is suspended.
> **Acceptance Criteria**: AC-031, AC-032

---

**Bad story — benefit restates the capability**:
> US-003: As an analyst, I want to export data to CSV so that I can have a CSV export.

Problems: the benefit is circular — it restates the capability, not the user value.

**Good story**:
> **US-003**: As a **data analyst**, I want to export filtered query results to CSV so that I can import them into Excel for ad-hoc analysis without requesting engineering support.
> **Acceptance Criteria**: AC-007, AC-008

---

## 3. Acceptance Criteria

**Format**: `AC-NNN: The system shall [observable behavior] when [condition].`

Every acceptance criterion must be:
- **Observable**: testable from outside the system without access to source code or internal state
- **Binary**: it either passes or fails — there is no "partial" or "mostly"
- **Independent**: it describes a single condition, not a bundle of behaviors
- **Assigned a unique ID**: `AC-NNN` (sequential, never reused)

### Good/Bad Examples

**Bad — not observable, not binary**:
> AC-005: The login flow should be smooth and not confuse users.

Problems: "smooth" and "confuse" are subjective; no observable condition; cannot be tested pass/fail.

**Good**:
> **AC-005**: The system shall display the dashboard page within 1 second of a successful login, measured from the moment the user submits valid credentials, when the server is under ≤ 500 concurrent sessions.

---

**Bad — bundles multiple behaviors**:
> AC-011: The system shall validate the form, show errors, and not submit if fields are missing or invalid.

Problems: this is three separate criteria bundled into one; if one part fails, you cannot tell which behavior is broken.

**Good** (split into three):
> **AC-011**: The system shall display an inline error message below each field that is submitted empty when the registration form is submitted with one or more required fields blank.
> **AC-012**: The system shall display an inline error message below the email field when the submitted email address does not match RFC 5322 format.
> **AC-013**: The system shall not submit the registration form to the server when any field-level validation error is present; the form shall remain on the current page.

---

**Bad — implementation-dependent**:
> AC-019: The UserService.authenticate() method shall return a JWT signed with RS256.

Problems: this describes an internal implementation detail, not an observable system behavior.

**Good**:
> **AC-019**: The system shall return an authentication token in the response body within 500ms when a user submits valid credentials. Subsequent requests that include this token in the `Authorization: Bearer` header shall be treated as authenticated.

---

## 4. Module Boundaries and Dependencies

**Rule**: Each module has a single, clearly stated responsibility. Dependencies between modules must be declared explicitly using MOD-IDs — never described in prose that a reader must interpret.

### Single Responsibility

A module has a clear boundary when you can answer "what does this module NOT do?" as precisely as "what does this module do?" If the module's purpose leaks into another domain, split it.

### Declaring Dependencies

Every module's **Dependencies** field must list the MOD-IDs it depends on, or state "none". A dependency means: this module reads data from, calls into, or cannot function without the listed module.

### Good/Bad Examples

**Bad — blurry boundary**:
> **MOD-003**: User Management
> Purpose: Handles everything related to users including auth, profile data, permissions, audit logs, and notifications.
> Dependencies: none

Problems: five distinct responsibilities in one module; "none" is almost certainly wrong; impossible to assign to a single engineer without cross-cutting concerns.

**Good** (split into focused modules):
> **MOD-003**: Authentication
> Purpose: Validates user credentials and issues session tokens. Does not manage profile data or permissions.
> Dependencies: none
>
> **MOD-004**: User Profiles
> Purpose: Stores and serves user profile data (name, email, preferences). Does not handle authentication or access control.
> Dependencies: MOD-003
>
> **MOD-005**: Authorization
> Purpose: Evaluates whether an authenticated user has permission to perform a given action. Does not authenticate users or store profile data.
> Dependencies: MOD-003

---

**Bad — implicit dependency**:
> **MOD-008**: Order Fulfillment
> Purpose: Processes confirmed orders and schedules shipping.
> Dependencies: none

Problems: fulfillment clearly depends on orders existing (MOD-006, say) and inventory (MOD-007), but those are not declared. An engineer reading this could build MOD-008 without knowing it will break at runtime.

**Good**:
> **MOD-008**: Order Fulfillment
> Purpose: Processes confirmed orders by reserving inventory and scheduling a shipment record.
> Dependencies: MOD-006 (Order Management), MOD-007 (Inventory)

---

**Bad — dependency described in prose, not IDs**:
> **MOD-010**: Reporting
> Purpose: Generates monthly revenue reports.
> Dependencies: Depends on the data from the billing system and the order history somewhere.

Problems: "the billing system" and "order history somewhere" are not resolvable references; an engineer cannot act on this.

**Good**:
> **MOD-010**: Reporting
> Purpose: Generates monthly revenue reports by aggregating confirmed order and payment data.
> Dependencies: MOD-006 (Order Management), MOD-009 (Billing)

---

## 5. Non-Goals (Critical)

**Rule**: Every non-goal must be a specific named exclusion. Vague disclaimers are not non-goals.

### Why This Matters

Implied exclusions are invisible exclusions. If a feature is not explicitly ruled out, stakeholders will assume it is in scope. This is how projects accumulate undiscussed scope: each stakeholder fills ambiguity with their own assumptions. By the time implementation begins, the team is building four different products.

Non-goals are not a sign of weakness — they are a sign of a PM who has thought through the product and made deliberate decisions.

### Good/Bad Pairs

| Bad | Good |
|-----|------|
| "We won't do everything." | "Multi-tenancy is out of scope for v1. The system serves a single organization. Multi-tenant support is planned for v2." |
| "Performance optimization is not a focus." | "Sub-100ms p99 latency is not a goal for v1. The target SLA is p99 < 500ms. Latency optimization is deferred to v2." |
| "Mobile app" (listed as a non-goal with no elaboration) | "Native iOS and Android apps are out of scope. The web UI must be responsive down to 320px viewport width, but no native mobile application will be built for this release." |
| "Internationalization" (listed with no elaboration) | "Localization and internationalization are out of scope for v1. The product is English-only. All user-visible strings shall be in US English. i18n infrastructure (e.g., message catalogs) is not required." |
| "We'll keep it simple." | "An admin dashboard for managing configuration at runtime is out of scope for v1. Configuration is managed via environment variables and a deploy-time config file." |

### Scope Assumption Checklist

Review this list with stakeholders before finalizing the non-goals section. If an item is not in scope, add an explicit named exclusion. Do not leave it blank and hope no one asks.

- [ ] **Internationalization / Localization (i18n/l10n)**: Is the product English-only? Explicitly exclude other languages if so.
- [ ] **Offline support**: Does the app require an internet connection? If offline mode is not planned, say so explicitly.
- [ ] **Admin panel / back-office UI**: Is there a self-service admin interface? If not built in this release, name it as excluded.
- [ ] **API versioning**: Does the API need backward compatibility guarantees across versions? If no versioning strategy is in scope, state that.
- [ ] **SSO / SAML / OIDC federation**: Is enterprise identity federation required? If only username/password auth is in scope, name SSO as excluded.
- [ ] **Analytics / usage tracking**: Is product analytics (Mixpanel, Segment, Amplitude, etc.) in scope? If not, exclude it by name.
- [ ] **Native mobile apps (iOS / Android)**: Is mobile access via a responsive web UI sufficient? Explicitly exclude native apps if so.
- [ ] **Real-time features (WebSockets, push notifications)**: If the product is request/response only, explicitly exclude real-time push.
- [ ] **Multi-tenancy**: Does the product serve a single organization or multiple? Exclude multi-tenancy explicitly if out of scope.
- [ ] **Data export / import**: Are bulk export (CSV, JSON) or import workflows in scope? If not, name them as excluded.

---

## 6. User Approval Gates

**Rule**: PM must obtain explicit user approval before writing any change to `prd.md`. Never interpret silence, ambiguity, or a follow-up question as approval.

**What counts as explicit approval**: The user says yes, approves, confirms, looks good, go ahead, or an equivalent affirmative in context of the specific change proposed.

**What does NOT count**:
- Silence after presenting a change
- "Maybe" or "that could work" — these are not approvals
- A follow-up question — clarify first, then get approval
- Paraphrasing back the change ("so you want X?") — that is confirmation of understanding, not approval of the change

**Process**:
1. Describe the proposed change clearly before writing anything
2. Wait for an explicit affirmative response
3. Write only what was approved — not interpretations or expansions of it
4. If the user approves part of a change but is silent on another part, treat the silent part as unapproved — ask separately

---

## 7. [DECISION NEEDED] Markers

**Rule**: Use `[DECISION NEEDED: <description>]` when a requirement cannot be made concrete without stakeholder input. The marker text must name the specific decision needed — not just flag that something is unclear.

**Bad** (vague):
```
[DECISION NEEDED: authentication]
```

**Good** (specific, actionable):
```
[DECISION NEEDED: Should login tokens expire after 24 hours of inactivity or remain valid until the user explicitly logs out?]
```

**When to apply**: Inline at the point of ambiguity — do not move it to a separate "open issues" section. The quality checklist blocks handoff until all markers are resolved.

**How to resolve**: PM asks the question, gets an explicit user answer, then replaces the marker with the concrete requirement. Never remove a marker by making an assumption — only by getting an answer.

**Format rules**:
- The description after the colon must be a complete question or statement of what is missing
- Include enough context that the user knows which part of the product is affected
- One decision per marker — split compound ambiguities into separate markers
