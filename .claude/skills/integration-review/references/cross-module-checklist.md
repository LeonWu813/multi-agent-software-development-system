# Cross-Module Conflict & Leak Checklist

Living document — add project-specific patterns here as they're discovered, the same way `qa-checklist/references/common-failure-patterns.md` grows over time.

## Conflicts

- [ ] No two modules define the same route, endpoint, exported symbol, or shared config key with different meanings
- [ ] No two modules' migrations touch the same table in an order-dependent or incompatible way (check filename ordering, not just table names — a shared numeric prefix with undefined apply order is itself a conflict)
- [ ] Modules that both depend on the same shared library/service use it the same way (same auth pattern, same error handling shape, same retry/timeout policy) — divergence here is a conflict even if each module works in isolation
- [ ] Shared Conventions in `production.md` are actually followed identically across modules — engineers implementing in isolation commonly drift on naming, error formats, or logging shape
- [ ] Integration Points declared in any module's spec (cross-module UI wiring, shared components) are implemented on both sides — check the spec's Integration Points section against the actual code in both modules, not just the owning module

## Information Leakage

Leakage is not only a database problem — check every place data can cross a boundary it shouldn't:

- [ ] **Data access**: does any code path let module A read or act on module B's data without going through module B's intended authorization boundary? (e.g. a direct cross-module DB join or shared table query that bypasses an ownership check)
- [ ] **Caches**: do cache keys include the correct module/tenant/user scope, or could two different owners collide on the same key?
- [ ] **Logs**: do log lines from one module ever include another module's sensitive fields (tokens, PII, other users' data) because of a shared logging utility or overly broad object dump?
- [ ] **Exports/reports**: do any export or reporting features that aggregate across modules correctly filter to what the requesting user/tenant is authorized to see?
- [ ] **Background jobs/queues**: do jobs that process work across modules explicitly re-validate the authorization context, rather than trusting the context of whichever module enqueued them?
- [ ] **Shared config/secrets**: are module-specific secrets or config values scoped so one module can't read another's (e.g. a single flat `.env` namespace where naming collisions silently point one module at another's key)?

## How to log a finding

Every finding needs: category (`Conflict` or `Leak`), the specific file/line or component, and a concrete failure scenario — what input or sequence of actions actually triggers the problem. "Modules might conflict" is not a finding; "engineer-mod-a and engineer-mod-b both wrote a migration touching `users.email` with no ordering guarantee — see `supabase/migrations/003_*.sql` (both modules)" is.
