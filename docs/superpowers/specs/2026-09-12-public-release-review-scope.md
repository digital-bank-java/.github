# Project-Wide Code Review Scope

## Review Areas

Review each repository's `origin/main` for:

- authentication, authorization, JWT validation, secret handling, and accidental public exposure;
- immutable ledger and balance/event ownership invariants;
- idempotency, optimistic concurrency, inbox/outbox leasing, retries, DLQ behavior, and replay safety;
- database migrations, append-only protections, transaction boundaries, and environment-specific configuration;
- Kubernetes probes, resource/configuration defaults, service routing, and unsafe local-only fallbacks;
- CI workflows, dependency/test phase separation, leaked credentials, redundant jobs, and release reproducibility;
- API/OpenAPI and AsyncAPI accuracy, README instructions, and stale environment references.

## Finding Rules

- A finding must identify a concrete failure mode, not a stylistic preference.
- A finding is release-blocking when it can expose protected functionality/data, corrupt financial state, lose or duplicate an event, prevent a clean deployment, or materially mislead a public user.
- Do not refactor stable code merely to make it look different.
- Do not add tests whose only value is duplicating existing coverage.
- Do not change AWS/Sonar scope without an explicit new decision.

## Outputs

- A concise review report in the handoff documentation with findings and evidence.
- Focused fix PRs for confirmed release blockers.
- Follow-up GitHub issues, parented under the appropriate Sprint 6 or Sprint 7 item, for valid deferred work.
- A public organization profile that describes only verified current capabilities.
