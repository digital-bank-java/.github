# Public Release Review: 2026-09-12

## Scope

This review evaluates the authoritative `origin/main` of every Digital Bank Java repository before public release. It covers financial and event integrity, authentication and authorization, configuration and secrets, Kubernetes/Helm deployment, CI workflows, API contracts, and public documentation.

AWS/UAT/PROD rollout and SonarQube remain deferred by project decision. The review therefore treats local SIT as the current runtime boundary and does not claim production readiness.

## Release-Blocking Findings

The platform is not ready for public release until these findings are fixed and verified through focused pull requests:

| Priority | Area | Finding | Affected repositories |
| --- | --- | --- | --- |
| P1 | Authorization | Gateway security and chart defaults fail open when the security flag is omitted. | `api-gateway` |
| P1 | Authorization | Customer and account resources are authorized from caller-supplied IDs without binding ownership to the authenticated subject or an explicit admin/service scope. | `api-gateway`, `customer-service`, `account-service` |
| P1 | Financial integrity | Ledger mutation endpoints have no service-level authentication/authorization if reached inside the cluster. | `ledger-service`, `infra-sit` |
| P1 | Transfer consistency | A ledger failure moves a transfer toward reservation release without emitting the release action. | `transaction-service` |
| P1 | Financial integrity | Ledger outcome consumers do not fully validate event identity against stored reservation metadata, and source-only outcomes can contain unrelated lines. | `account-service` |
| P1 | Event integrity | Transfer-created notification events are accepted without parsing and validating payload identifiers against trusted headers. | `notification-service` |
| P1 | Credential safety | Fixture credentials are not explicitly gated to approved SIT/test usage. | `auth-service` |
| P1 | Token isolation | Shared-key JWT consumers do not enforce service audience/token-purpose isolation. | `auth-service`, `payment-service`, `transaction-service`, `mfa-service` |
| P1 | Infrastructure | SIT Redis has no authentication, TLS, or workload network restriction. | `infra-sit` |

These are confirmed findings, not assumptions. Each must be addressed with the smallest compatible change and a focused regression or configuration check where it materially proves the failure mode.

## Correctness And Documentation Findings

The following should be fixed before or alongside the release-blocking work:

- Remove the duplicate `transaction.events.mfa-assurance` YAML mapping in SIT configuration and add duplicate-key validation to configuration checks.
- Correct the API Gateway README scope name from `transaction.internal` to the implemented `transfer.internal` contract.
- Reconcile the `infra-sit` README Kafka topic inventory with the topics actually provisioned by Helm.
- Strengthen AsyncAPI validation to invoke the existing contract checks and validate schema/examples and compatibility-relevant bindings without creating a redundant CI job.
- Pin mutable third-party action tags found in `api-gateway` and `infra-sit` to immutable SHAs.
- Remove the duplicate OpenSearch render/lint work in the `infra-sit` workflow while preserving its assertions.

## Reviewed Without Actionable Findings

- Ledger append-only triggers, balanced-entry validation, posting idempotency, reversals, command inbox, and outbox leasing.
- Payment idempotency, serialized state transitions, outbox creation, and publisher retry behavior.
- MFA challenge locking, expiry, attempts, transfer binding, encrypted TOTP persistence, and assurance outbox behavior.
- Authentication signature, issuer, expiry, server-side session state, revocation, and single-session checks.
- Reviewed actuator exposure and logging paths; no committed production credentials, bearer tokens, TOTP secrets, or private keys were found.
- Reviewed service ports, probes, Config Server wiring, existing Kubernetes Secret references, and non-root container configuration.

## Corrective PR Status

The first corrective wave and the follow-up hardening wave are merged. The hardening wave includes Ledger Service #26, Customer Service #38, Account Service #47, Auth Service #15, Config Repo #53 and #54, Infra SIT #46, API Gateway #32, Payment Service #15, Transaction Service #34, and MFA Service #23. Their focused checks passed; Testcontainers-dependent verification was limited locally by unavailable Docker.

## Completion Gate

All findings from this review are now addressed in merged code. The remaining release gate is operational: roll out the merged images/configuration to local SIT and verify authentication, ownership, audience validation, Ledger authorization, Redis authentication, and network policy. Public visibility and branch protection are separate repository-settings changes and remain pending the owner's instruction.
