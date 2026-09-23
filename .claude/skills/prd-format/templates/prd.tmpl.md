<!-- owner: pm | to change: invoke pm — never edit this file directly -->

**Revision**: 1 | **Last Updated**: <date>

> **Note**: Remove all HTML comments before handoff to Doc-Sync.

---

# [Project Name] — Product Requirements Document

---

## 1. Project Overview

<!-- 1-2 paragraph summary of the system and its primary purpose. Describe what problem it solves, who it is for, and what the primary value delivered to users is. Do not describe the architecture or implementation — those belong in production.md. -->

[DECISION NEEDED: Project overview not yet written]

---

## 2. Goals & Non-Goals

### Goals

<!-- Goals must be measurable. Each bullet should answer: "how will we know this goal is met?" Include a metric or observable outcome. Avoid vague statements like "improve UX" — use "reduce checkout abandonment rate from X% to Y%" instead. -->

- [Goal 1: measurable outcome with metric]
- [Goal 2: measurable outcome with metric]
- [Goal 3: measurable outcome with metric]

### Non-Goals

<!-- Non-goals must be specific named exclusions — not vague disclaimers. Every item must name the thing being excluded. The rule: if a stakeholder could reasonably assume the feature is included, it must be listed here. Use the format: "[Feature/capability] is out of scope for [version/release]." -->

- Multi-tenancy is out of scope for v1.
- [Feature X] is out of scope for v1; it is planned for v2.
- [DECISION NEEDED: Review with stakeholders — confirm which of the following are out of scope: i18n/localization, offline support, admin panel, API versioning, SSO/SAML, analytics dashboard, native mobile apps]

---

## 3. User Stories

<!-- Each user story must have: a unique US-XXX ID, a role, a capability, a benefit, and at least one acceptance criterion (referenced by AC-NNN ID). The format is: "As a [role], I want [capability] so that [benefit]." -->

### US-001: [Short title]

**As a** [role],
**I want** [capability],
**so that** [benefit].

**Acceptance Criteria**: AC-001, AC-002

---

### US-002: [Short title]

**As a** [role],
**I want** [capability],
**so that** [benefit].

**Acceptance Criteria**: AC-003, AC-004

---

<!-- Add further user stories as US-003, US-004, … incrementing the ID. -->

---

## 4. Tech Stack

<!-- Every entry must be specific: name + version. Do not write "a database" or "a frontend framework" — write "PostgreSQL 16.2" or "React 18.3". Use the Notes column for constraints or rationale. -->

| Component  | Name + Version         | Notes                              |
|------------|------------------------|------------------------------------|
| Language   | [e.g., Python 3.12]    | [e.g., required for ML libraries]  |
| Database   | [e.g., PostgreSQL 16]  | [e.g., hosted on AWS RDS]          |
| Framework  | [e.g., FastAPI 0.111]  | [e.g., async-first HTTP framework] |
| Frontend   | [e.g., React 18.3]     | [e.g., SPA, bundled with Vite 5]   |
| Cache      | [e.g., Redis 7.2]      | [e.g., session + job queue]        |

<!-- Add rows as needed. Every row must have a version number. -->

---

## 5. Architecture Overview

<!-- High-level description of how major components relate. No implementation details. Describe the data flow and the responsibilities of each major boundary (e.g., "the API layer receives requests and delegates to the service layer; the service layer reads/writes via the repository layer; no layer bypasses another"). Diagrams are welcome here as ASCII art or Mermaid. -->

[DECISION NEEDED: Architecture overview not yet written]

---

## 6. Module Breakdown

<!-- Each module has: a unique MOD-XXX ID, a purpose (single clear responsibility), the US-IDs of the user stories it satisfies, and its dependencies (list MOD-IDs or "none"). Bidirectional links are required: if MOD-002 depends on MOD-001, then MOD-001's dependents should note MOD-002 where relevant. -->

### MOD-001: [Module Name]

**Purpose**: [Single clear responsibility — one sentence. State what this module is responsible for, not how it works.]

**User Stories**: US-001, US-002

**Dependencies**: none

---

### MOD-002: [Module Name]

**Purpose**: [Single clear responsibility — one sentence.]

**User Stories**: US-002

**Dependencies**: MOD-001

---

<!-- Add further modules as MOD-003, MOD-004, … incrementing the ID. -->

---

## 7. Phases & Milestones

<!-- Each phase references module IDs (not module names) and defines a concrete completion milestone. The milestone is a testable, observable condition — not a date. Dates belong in a project plan, not the PRD. -->

### Phase 1: [Phase Name]

**Modules**: MOD-001

**Milestone**: [Observable completion condition, e.g., "MOD-001 is deployed to staging and all AC-001–AC-002 pass in the staging environment."]

---

### Phase 2: [Phase Name]

**Modules**: MOD-001, MOD-002

**Milestone**: [Observable completion condition, e.g., "All acceptance criteria for MOD-001 and MOD-002 pass in production; zero P0 bugs open."]

---

<!-- Add further phases as needed. -->

---

## 8. Acceptance Criteria

<!-- Default grouping: by MOD-ID. Every AC must have a unique AC-NNN ID and follow the format: "AC-NNN: The system shall [observable behavior] when [condition]." Criteria must be binary (pass/fail), observable (testable without access to internals), and independent of implementation. -->

<!-- Alternative grouping option: group by US-ID instead of MOD-ID when user stories span multiple modules and you need finer-grained traceability. Choose one grouping and apply it consistently throughout the entire PRD. -->

### MOD-001 Acceptance Criteria

**AC-001**: The system shall [observable behavior] when [condition].

**AC-002**: The system shall [observable behavior] when [condition].

---

### MOD-002 Acceptance Criteria

**AC-003**: The system shall [observable behavior] when [condition].

**AC-004**: The system shall [observable behavior] when [condition].

---

<!-- Add further AC entries incrementing the ID. Ensure every US-XXX listed in Section 3 maps to at least one AC here. -->
