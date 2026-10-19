# Optimization Proposal Criteria

**This is the safety net, not the primary mechanism.** Duplication across modules should ideally be proposed by Tech Lead at spec time — during init review or whenever a new module is added — by scanning the Module Breakdown for overlapping domains before any engineer starts writing code (see `tech-lead.md`'s init-review process). Finding duplication here, after both modules are already built, means that earlier check missed it. Log it anyway — late is better than never — but don't treat this phase-end pass as the thing that's supposed to catch it.

Not every observation is worth a row in `integration-review.md`. An optimization proposal must pass all of the following before it gets logged:

- [ ] **It's visible only from the whole-system view.** If a single module's Engineer or QA could have caught it in isolation, it's not an integration-review finding — it belongs in that module's own status.md as a bug or skill recommendation, not here.
- [ ] **It has a concrete trade-off, not just a preference.** "This could be cleaner" is not a proposal. "Modules X and Y each implement their own retry logic against the same external API; consolidating into one shared client would cut duplicated code by ~N lines and fix the inconsistent backoff between them, at the cost of a new shared dependency both modules must adopt" is.
- [ ] **It doesn't change user-facing behavior or requirements.** If it does, it's a PRD-level change — escalate to PM's change flow instead of logging it here.
- [ ] **It's actionable by a single module's engineer, or clearly says which engineers must coordinate.** A proposal with no clear owner just sits in `PROPOSED` forever.

## Good candidates

- Duplicated logic across modules that could move to a single owner module (an existing module that naturally owns it, or a new one named for what it is), with the duplication, the proposed owner and Source Path, and the extraction cost all stated
- A performance issue only visible at the integration boundary (e.g. module A calls module B's API once per item in a loop instead of batching — invisible in either module's own tests, obvious when tracing a request across both)
- Inconsistent patterns for the same problem across modules (two different pagination styles, two different error envelope shapes) where standardizing has a clear, statable benefit

## Not worth logging

- Naming or style preferences with no measurable benefit
- Anything a single module's own Engineer/QA cycle would have already caught
- Speculative "might want this later" suggestions with no current cost being paid
- Anything that changes what the product does, not how it's built
