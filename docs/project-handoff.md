# Digital Bank Java Project Handoff

Last updated: 2026-09-04

This document is the durable resume point for AI agents and contributors working on the Digital Bank Java platform.

Read this after `AGENTS.md` and before starting new work.

Update this file when a story-level task finishes, a new service is added, a cross-repo capability lands, or an architecture decision changes the path forward. Append dated entries to the update log instead of rewriting history.

## Purpose

Digital Bank Java is a production-minded banking backend platform built as a set of Java/Spring microservices.

The project is intentionally educational and step-by-step, but the target architecture should stay transferable to real production environments, especially AWS-hosted UAT and production.

The working style is:

- move in small reviewed tasks
- explain design choices while implementing
- keep GitHub Issues and Projects as the executable backlog
- keep PRs as the review and audit trail
- prefer production-grade patterns where they affect correctness, security, observability, or deployability

## Repositories

| Repository | Current responsibility |
| --- | --- |
| `.github` | Organization-level standards, agent guidance, shared docs, future reusable workflows |
| `config-server` | Spring Cloud Config Server that serves externalized runtime configuration |
| `config-repo` | Git-backed configuration source consumed by Config Server |
| `api-gateway` | Gateway entry point, service routing, admin/internal docs aggregation |
| `customer-service` | Customer identity and profile management |
| `account-service` | Account lifecycle, account lookup, admin account search |
| `ledger-service` | Immutable ledger entry posting and lookup |
| `transaction-service` | Transfer orchestration and saga/process-manager foundation |
| `auth-service` | Authentication, JWT/session foundation, and login/logout workflow |
| `mfa-service` | TOTP enrollment and authenticated MFA challenge workflow |
| `payment-service` | Authenticated internal payment instruction lifecycle |
| `notification-service` | Transfer-event notification consumption and durable inbox |
| `infra-sit` | Local SIT infrastructure: shared PostgreSQL, Kafka, and AKHQ tooling |

## Environment Model

| Environment | Meaning |
| --- | --- |
| `sit` | Lowest integrated development and testing environment on Docker Desktop Kubernetes |
| `uat` | Formal cloud-hosted pre-production environment |
| `prod` | Formal production environment |

`LOCAL-DEV` is retired as a formal environment and Spring profile. Running a single service from VS Code or Eclipse remains supported for debugging, but the process uses the `sit` profile and temporary property overrides to connect to forwarded SIT dependencies. It is not a second deployment topology.

SIT should resemble production shape where practical, but production should prefer managed AWS services rather than manually operated local-style containers.

## Current Delivery Boundary

The active delivery boundary is local Docker Desktop Kubernetes SIT. AWS infrastructure, AWS-hosted UAT, AWS-hosted production, cloud networking, managed AWS data services, cloud secret integration, and production deployment runbooks remain deferred to Sprint 7. They are backlog scope, not current implementation work.

Until the local SIT domain and event-driven workflows are complete, do not add AWS-specific manifests, cloud credentials, UAT/PROD rollout steps, or cloud-only service dependencies. Local SIT should continue to prove the service contracts and operational behavior that the later AWS deployment will host.

Canonical naming, port, configuration, API-path, and infrastructure conventions are in `docs/platform-conventions.md`.

Expected AWS direction:

- EKS for Kubernetes workloads
- RDS or Aurora PostgreSQL for managed databases
- MSK or another managed Kafka-compatible platform for event streaming
- AWS OpenSearch for centralized logging/search
- AWS Secrets Manager or Parameter Store for secrets
- ACM and AWS load balancer integration for TLS/ingress

## Current Architecture State

### Configuration

Runtime configuration is externalized through:

```text
config-server -> config-repo
```

The service repositories should not become the source of environment-specific runtime configuration.

Configuration file convention:

```text
application.yml
application-{profile}.yml
{service}/{service}.yml
{service}/{service}-{profile}.yml
```

Do not commit real secrets into `config-repo`.

### Gateway and APIs

`api-gateway` is the normal access path for local SIT.

Expected local command:

```bash
kubectl port-forward -n digital-bank-sit svc/api-gateway 8080:8080
```

Service APIs, admin APIs, health routes, and centralized OpenAPI/Swagger UI should be routed through the gateway where possible.

Direct service port-forwarding is acceptable for debugging, but should not be the default developer workflow.

### OpenAPI Documentation

Each service owns its own OpenAPI contract.

The gateway aggregates documentation behind admin/internal paths. Swagger UI should be treated as a developer/admin surface, not a public customer-facing endpoint.

Kafka event contracts use AsyncAPI, not OpenAPI. The governed ledger posting outcome contract is [`docs/contracts/ledger-events-asyncapi.yml`](contracts/ledger-events-asyncapi.yml); it defines the versioned completion and failure topics, producer/consumer ownership, delivery semantics, Schema Registry boundary, and is the implementation dependency for Sprint 3 Tasks 2 through 4.

### Persistence

Local SIT uses one shared PostgreSQL instance with separate logical databases per service.

Known logical databases include:

```text
customer_service
account_service
ledger_service
transaction_service
payment_service
notification_service
```

Each service owns its own database objects. Services must not directly query each other's databases.

Schema migrations are managed with Flyway inside each service repository.

Ledger reconciliation is an operational comparison across independently owned views, not a second ledger. The immutable ledger remains the financial posting authority; account projections and transaction state are compared against it using stable correlation identifiers. Sprint 2 defines the invariants and remediation boundaries in [`docs/ledger-reconciliation.md`](ledger-reconciliation.md). Event-driven checks remain Sprint 3 work, while scheduled reporting and alerting remain Sprint 6 work.

### Domain Boundaries

`customer-service` owns:

- customer registration
- customer profile retrieval/update
- admin customer search/listing

`account-service` owns:

- account opening
- account lookup
- account listing/search
- available-balance reservations and reservation lifecycle
- account balance projection updates driven by ledger events

`ledger-service` owns:

- immutable ledger entries
- balanced debit/credit posting rules
- ledger lookup
- governed ledger posting outcome events
- transactional outbox delivery with retry, lease, and quarantine semantics

No service should expose naive public balance mutation APIs.

`transaction-service` owns:

- internal transfer workflow state and lifecycle
- saga/process-manager decisions
- reservation and ledger command transport
- transfer outcome handling and transactional outboxes

`auth-service`, `mfa-service`, `payment-service`, and `notification-service` have
their runtime and core HTTP/event foundations merged. Their current review wave
adds the shared SIT JWT trust contract, service configuration, and local rollout
prerequisites.

`transaction-service` has its transfer lifecycle, reservation/ledger transport,
authorization, persistence, and saga/process-manager foundation merged. End-to-end
SIT execution remains operational evidence, not an assumption from merged code.

## Event-Driven Direction

The platform is moving toward eventual consistency for financial workflows.

Current target model:

```text
Transaction Service = saga/process manager
Account Service     = reservation and account projection owner
Ledger Service      = immutable financial posting owner
Kafka               = event transport
Outbox/Inbox        = reliable publication and idempotent consumption
```

The intended transfer flow is:

```text
Transaction Service
  -> create transfer PENDING
  -> request Account Service reservation

Account Service
  -> validate available balance
  -> reserve funds
  -> publish reservation outcome facts through outbox

Transaction Service
  -> request Ledger Service posting

Ledger Service
  -> create immutable debit and credit entries
  -> publish LedgerPostingCompleted or LedgerPostingFailed through outbox

Account Service
  -> consume ledger posting event through inbox
  -> commit reservation, apply credit, or release reservation

Transaction Service
  -> consume outcome events through inbox
  -> mark transfer COMPLETED or FAILED
```

Ledger Service should not orchestrate sagas. Transaction Service should own saga orchestration for the first production-grade slice.

## Current Implementation Snapshot

The following baseline is merged on the repository default branches or was already established before this update:

- `config-server` bootstrap, tests, Dockerfile, Helm chart, CI, Git-backed config
- `config-repo` externalized service configuration
- `api-gateway` bootstrap, routing, centralized admin docs routes
- `customer-service` customer registration/profile APIs, persistence, tests, Dockerfile, Helm chart, CI
- `account-service` account opening/lookup/admin query APIs, persistence, tests, Dockerfile, Helm chart, CI
- `ledger-service` initial immutable ledger entry posting/lookup, persistence, tests, Dockerfile, Helm chart, CI
- `transaction-service` process-manager bootstrap, CI, configuration, and health baseline
- `infra-sit` shared PostgreSQL, Kafka, and AKHQ deployment for local SIT
- org-level and repo-level `AGENTS.md` files
- Java test phase convention documentation
- ledger reconciliation architecture and the independent-view reconciliation model
- shared local SIT Kafka and AKHQ tooling
- ledger database credential injection for SIT
 - governed ledger event contracts and AsyncAPI documentation
 - ledger transactional outbox publication, retry, lease, and quarantine behavior
 - account reservation persistence, ledger-event consumption, and reservation transport
 - transaction transfer lifecycle, saga/process manager, HTTP workflow API, authorization, and Kafka transport
 - auth-service session/JWT foundations and configurable single-session policy
 - mfa-service provider, TOTP, challenge, authenticated HTTP API, and principal binding foundations
 - payment-service lifecycle, internal HTTP API, idempotency, authorization, and resource contract
 - notification-service delivery lifecycle, TransferCreated consumer, and durable inbox
 - SIT ledger and transfer Kafka topic provisioning

The implementation wave above is merged on the service default branches as of
2026-09-01. Its PRs report the required Maven, Helm, and PostgreSQL/Testcontainers
verification. SIT rollout and end-to-end transfer demonstration remain separate
operational evidence and are not inferred from merged PRs.

The current reviewable implementation wave is non-draft and is not merged or
deployed until accepted and verified:

| Repository / PR | Reviewable scope |
| --- | --- |
| [`.github#201`](https://github.com/digital-bank-java/.github/pull/201) | Shared SIT Auth JWT secret runbook |
| [`config-repo#32`](https://github.com/digital-bank-java/config-repo/pull/32) | Auth/MFA SIT configuration, shared issuer, and Auth scopes |
| [`auth-service#6`](https://github.com/digital-bank-java/auth-service/pull/6) | Shared SIT JWT scope contract |
| [`mfa-service#8`](https://github.com/digital-bank-java/mfa-service/pull/8) | HMAC/JWK JWT validation for SIT and cloud modes |
| [`auth-service#7`](https://github.com/digital-bank-java/auth-service/pull/7) | PostgreSQL-backed Auth session persistence and replica-safe revocation |
| [`mfa-service#9`](https://github.com/digital-bank-java/mfa-service/pull/9) | PostgreSQL-backed MFA enrollment/challenge persistence with encrypted TOTP secrets |
| [`payment-service#7`](https://github.com/digital-bank-java/payment-service/pull/7) | HMAC/JWK JWT validation and SIT deployment contract |
| [`config-repo#33`](https://github.com/digital-bank-java/config-repo/pull/33) and [`config-repo#34`](https://github.com/digital-bank-java/config-repo/pull/34) | Notification and Payment SIT configuration |
| [`infra-sit#29`](https://github.com/digital-bank-java/infra-sit/pull/29) | Transfer-created Kafka topic and dead-letter topic provisioning |
| [`config-repo#39`](https://github.com/digital-bank-java/config-repo/pull/39) | Auth, MFA, Transaction, and Payment gateway routes and centralized OpenAPI entries |
| [`api-gateway#23`](https://github.com/digital-bank-java/api-gateway/pull/23) | Feature-flagged JWT validation and scope authorization at the gateway |

The application PRs report focused Maven, Helm, and container verification. The
configuration PRs report YAML parsing and diff checks. SIT rollout, end-to-end
transfer demonstration, and secret provisioning still require separate evidence.

Other local-SIT operational PRs remain independently reviewable: `infra-sit#23`
(Redis), `infra-sit#24` (OpenSearch), `infra-sit#25` (Fluent Bit),
`config-repo#35` (gateway resilience), and `config-repo#36` (gateway rate limits).

## Known Missing Work

High-priority missing capabilities:

- complete governed account/transfer event-contract documentation and compatibility checks
- integrated SIT rollout and end-to-end transfer verification across Transaction, Account, and Ledger services
- rollout of the newly added gateway routes and SIT configuration for Auth, MFA, Transaction, and Payment
- gateway security rollout after the shared SIT secret is provisioned and the dependent configuration PRs are merged
- service-to-service security and admin API authentication/authorization
- API Gateway rate limiting and resilience rollout
- centralized logging with OpenSearch, Fluent Bit, dashboards, and alerts
- distributed tracing and correlation IDs
- event-driven reconciliation checks and scheduled reconciliation reporting
- production documentation and the later AWS UAT/PROD delivery path

Deferred or intentionally not first:

- SonarQube/SonarCloud quality gate
- in-cluster Headlamp, because Headlamp Desktop is preferred for local GUI access
- Eureka/discovery service, because Kubernetes-native service discovery is preferred

## GitHub Project Workflow

Use GitHub Issues and Projects as the source of executable work.

### Outcome-Based Sprints

GitHub Project #1 is organized around outcome-based, rather than calendar-based, sprints. A sprint closes only when its required implementation, verification, documentation, and SIT demonstration evidence are complete.

The current delivery sequence is:

1. [Sprint 0 - Platform Foundation and Local SIT](https://github.com/digital-bank-java/.github/issues/18)
2. [Sprint 1 - Customer and Account Foundation](https://github.com/digital-bank-java/.github/issues/19)
3. [Sprint 2 - Ledger Foundation](https://github.com/digital-bank-java/.github/issues/20)
4. [Sprint 3 - Internal Transfers and Event Consistency](https://github.com/digital-bank-java/.github/issues/21)
5. [Sprint 4 - Secure Customer Access and Step-Up Authorization](https://github.com/digital-bank-java/.github/issues/22)
6. [Sprint 5 - Payment Rails and Notifications](https://github.com/digital-bank-java/.github/issues/23)
7. [Sprint 6 - Operational Resilience and Observability](https://github.com/digital-bank-java/.github/issues/24)
8. [Sprint 7 - AWS UAT and Production Readiness](https://github.com/digital-bank-java/.github/issues/25)

The Project `Sprint` field is the authoritative cross-repository delivery grouping. The eight Sprint epics are the only root planning items. Historic epics are children of their owning Sprint, and every other item is below a parent in the same Sprint. This makes the GitHub issue hierarchy the visible delivery structure while the Sprint field remains the cross-repository filter and audit key. The full parent mapping is recorded in `docs/project-inventory/2026-08-02-sprint-hierarchy-mapping.csv`.

Keep the native `Item Type`, `Status`, `Service`, `Priority`, `Size`, and linked pull requests intact. Historic DraftIssues are converted into `.github` issues before native type assignment so every planning item has a colored GitHub type.

The historic `Phase`, `Slice`, `Epic`, and `Delivery Priority` fields are intentionally retained. They contain prior planning classifications that are not duplicated by the new Sprint model. The native GitHub type remains the source of truth for issue classification; the Project `Item Type` field is synchronized to provide a board-friendly colored display.

Issue title prefixes:

- `EPIC:`
- `STORY:`
- `TASK:`
- `BUG:`

Use the native GitHub issue type field when possible:

- Epic
- Story
- Task
- Bug

Rules:

- create or update a supporting issue before code changes
- assign in-progress work to `ramioooz`
- attach tasks/stories to a related epic when available
- use dedicated branches
- open PRs for review
- link related cross-repo PRs
- state merge order when sequencing matters
- clean local and remote branches after merge

## Resume Instructions For AI Agents

Before doing work:

1. Run `git status -sb` in each active repository.
2. Read `.github/AGENTS.md`.
3. Read the target repository `AGENTS.md`.
4. Check open GitHub issues in the relevant repository.
5. Confirm the work has a supporting issue.
6. Work on a dedicated branch.
7. Run the narrow verification first, then the repo quality gate where practical.
8. Commit, push, and open a PR.

Useful local command:

```bash
for repo in .github config-server config-repo api-gateway customer-service account-service ledger-service transaction-service infra-sit; do
  printf "\n== %s ==\n" "$repo"
  git -C "$repo" status -sb
done
```

## Next Dependency-Aware Work

The current implementation wave is ready for review and rollout, in this order:

1. Merge [`.github#201`](https://github.com/digital-bank-java/.github/pull/201), the shared SIT Auth Secret runbook.
2. Merge [`config-repo#32`](https://github.com/digital-bank-java/config-repo/pull/32), then [`auth-service#6`](https://github.com/digital-bank-java/auth-service/pull/6).
3. Merge [`auth-service#7`](https://github.com/digital-bank-java/auth-service/pull/7) for durable sessions, then [`mfa-service#8`](https://github.com/digital-bank-java/mfa-service/pull/8), [`mfa-service#9`](https://github.com/digital-bank-java/mfa-service/pull/9), and [`payment-service#7`](https://github.com/digital-bank-java/payment-service/pull/7) in parallel.
4. Merge [`config-repo#33`](https://github.com/digital-bank-java/config-repo/pull/33), [`config-repo#34`](https://github.com/digital-bank-java/config-repo/pull/34), and [`infra-sit#29`](https://github.com/digital-bank-java/infra-sit/pull/29). The first two depend on config-repo#32; the Kafka topic PR can merge independently.
5. Merge [`config-repo#39`](https://github.com/digital-bank-java/config-repo/pull/39) after the corresponding service/configuration contracts are available.
6. Provision the local SIT Auth Secret, MFA TOTP encryption Secret, and service databases; roll out the services and verify health, protected workflows, Kafka delivery, centralized Swagger, and database state.
7. Record runtime evidence in the supporting issues and synchronize Sprint 3, 4, and 5 statuses. Keep UAT/PROD cloud deployment deferred to Sprint 7.

Consult GitHub Project #1 for the authoritative Sprint hierarchy and current issue status.

## Update Log

### 2026-09-04 - SIT security and gateway review wave

- Added the shared SIT Auth JWT secret delivery runbook in [`.github#201`](https://github.com/digital-bank-java/.github/pull/201).
- Aligned Auth, MFA, and Payment JWT trust behavior for local HMAC SIT validation while preserving OIDC/JWK support for future cloud environments.
- Completed the Auth/MFA/Notification/Payment SIT configuration review wave in `config-repo#32`, `#33`, and `#34`, including shared issuer/scopes and README structure corrections.
- Provisioned the transfer-created Kafka topic and dead-letter topic in [infra-sit#29](https://github.com/digital-bank-java/infra-sit/pull/29).
- Added the missing Auth, MFA, Transaction, and Payment gateway routes and centralized OpenAPI entries in [config-repo#39](https://github.com/digital-bank-java/config-repo/pull/39), tracked by [`.github#202`](https://github.com/digital-bank-java/.github/issues/202).
- Added feature-flagged gateway JWT validation and scope authorization in [api-gateway#23](https://github.com/digital-bank-java/api-gateway/pull/23), tracked by [`.github#203`](https://github.com/digital-bank-java/.github/issues/203); updated config-repo#32 with `admin.internal` and config-repo#39 with the SIT enablement flag.
- No pull request was merged directly by the implementation agent. The remaining boundary is user review/merge followed by local SIT rollout evidence.

### 2026-09-04 - Durable Auth and MFA persistence review wave

- Added PostgreSQL/Flyway Auth session persistence with transaction-safe same-user revocation in [auth-service#7](https://github.com/digital-bank-java/auth-service/pull/7), linked to `.github#28` and `.github#45`.
- Added PostgreSQL/Flyway MFA enrollment and challenge persistence with AES-256-GCM protected TOTP secrets in [mfa-service#9](https://github.com/digital-bank-java/mfa-service/pull/9), linked to `.github#29` and `.github#49`.
- Created the parented SIT rollout task [`.github#204`](https://github.com/digital-bank-java/.github/issues/204) for the `mfa_service` database and externally supplied `mfa-service-secrets` / `MFA_TOTP_ENCRYPTION_KEY` prerequisite.
- No secret material is stored in Git, Helm values, Config Server, or issue comments. UAT/PROD secret delivery remains deferred to Sprint 7.
- Updated both container smoke workflows to start disposable PostgreSQL instances and pass only CI-local credentials; all Auth and MFA Maven, Helm, and container checks passed.
- SIT rollout requires the existing PostgreSQL Secret, separate `auth_service` and `mfa_service` databases, and an externally managed `mfa-service-secrets` key containing a base64-encoded 32-byte AES key. No secret material was committed.
- These PRs are open, non-draft, and awaiting user review. No pull request was merged directly by the implementation agent.

### 2026-09-01

- Merged the event-driven implementation wave: Ledger Service PRs #14-#16, Account Service PRs #33-#36, Transaction Service PRs #6-#12, Auth Service PRs #1-#4, MFA Service PRs #1-#6, Payment Service PRs #1-#5, Notification Service PRs #1-#5, organization event contracts PR #137, and SIT Kafka topics PR #27.
- Closed and recorded evidence for the completed Sprint 3 implementation issues #101, #102, #103, #170, #171, #182, and #183, plus the completed auth, MFA, payment, notification, and transfer implementation tasks.
- Corrected the native parent hierarchy: payment resource contract task #167 is now under payment lifecycle task #161; transfer authorization task #169 is now under transfer HTTP task #165.
- Audited GitHub Project #1 after authentication refresh: 223 tracked issues, exactly eight root Sprint epics, and no unparented non-Epic issue. Closed issue state and Project status are synchronized for the completed implementation items.
- AWS/UAT/PROD deployment remains deferred; the current focus is local SIT rollout and verification.

### 2026-08-30 - Sprint 3 ledger event contract

- Published [`docs/contracts/ledger-events-asyncapi.yml`](contracts/ledger-events-asyncapi.yml) as the governed AsyncAPI contract for `LedgerPostingCompleted.v1` and `LedgerPostingFailed.v1`.
- Established versioned topic naming, required transfer/reservation identifiers, producer/consumer ownership, correlation and causation metadata, idempotency expectations, Schema Registry compatibility, delivery/DLQ semantics, and additive-only compatibility rules for a major event version.
- Made the contract the prerequisite for Sprint 3 Tasks 2 through 4: ledger outbox, account reservation/event consumption, and the Transaction Service process-manager foundation.

### 2026-08-03

- Adopted the formal three-environment model: `sit`, `uat`, and `prod`.
- Retired `LOCAL-DEV` as a platform environment and supported Spring profile. IDE execution is now explicitly a workstation debugging technique connected to SIT through temporary port-forwards and property overrides.
- Closed the Docker Compose LOCAL-DEV story as superseded. Docker remains the image packaging mechanism; Kubernetes SIT remains the only local integrated deployment topology.
- Created [story #115](https://github.com/digital-bank-java/.github/issues/115) and its child tasks for configuration migration, workstation debugging guidance, and Insomnia environment alignment.
- Added `docs/workstation-debugging-against-sit.md` as the repeatable procedure for debugging one database-backed service without duplicate Kubernetes processing.

### 2026-09-01 - AWS delivery deferred

- Confirmed that AWS infrastructure, AWS-hosted UAT/PROD deployment, cloud networking, managed AWS services, and cloud-specific operational runbooks remain deferred to Sprint 7.
- Kept local Docker Desktop Kubernetes SIT as the active development and integrated-verification environment.
- Added an explicit delivery boundary so current event-driven domain work does not introduce AWS-specific manifests, credentials, or deployment dependencies prematurely.

### 2026-09-01 - Local SIT event transport wave

- Reviewed the prepared Account Service reservation transport, Ledger Service outbox delivery, and Transaction Service Kafka transport work.
- Pushed Account Service transport hardening on `feature/177-account-reservation-transport`; it preserves stored outbox JSON, uses the event aggregate ID as the Kafka key, and keeps reservation and ledger Kafka client configuration isolated.
- Pushed Ledger Service outbox hardening on `fix/176-ledger-outbox-safety`; it rejects incomplete governed metadata, quarantines exhausted post-crash claims, and covers the recovery rules with focused tests.
- Pushed Transaction Service Kafka consumer hardening on `feature/103-transaction-ledger-transport`; it selects explicit Spring constructors and validates reservation topic/event-type alignment before dispatch.
- These branches are review-ready but GitHub Project status and PR creation are pending restoration of the organization GitHub CLI authentication. No AWS implementation was added.

### 2026-07-28

- Added this project handoff document as the durable resume point for AI agents and contributors.
- Confirmed that `AGENTS.md` remains the working-rules source of truth, while this document tracks current project state and next work.
- Established that future updates should append dated entries here after major architecture decisions, cross-repo changes, new service creation, or completed story-level work.

### 2026-08-02

- Started [task #108](https://github.com/digital-bank-java/.github/issues/108) to publish the authoritative local Kubernetes SIT deployment and verification guide. It covers local infrastructure, configuration, service rollout order, Gateway-routed verification, Swagger, AKHQ, and the explicit Sprint 7 UAT/PROD boundary without duplicating service READMEs or secrets.
- Reconciled deferred work from Sprint 0 under [task #107](https://github.com/digital-bank-java/.github/issues/107): quality-gate and SonarQube work [#1](https://github.com/digital-bank-java/.github/issues/1), [#3](https://github.com/digital-bank-java/.github/issues/3), and [#4](https://github.com/digital-bank-java/.github/issues/4) now belong to Sprint 6 under Observability & Resilience #34.
- Moved UAT/PROD environment validation [#40](https://github.com/digital-bank-java/.github/issues/40) and production documentation [#67](https://github.com/digital-bank-java/.github/issues/67) to Sprint 7 under Production Documentation #37.
- Created [Sprint 0 reconciliation task #107](https://github.com/digital-bank-java/.github/issues/107) under the Sprint 0 epic.
- Closed delivered draft-promotion story [#71](https://github.com/digital-bank-java/.github/issues/71) with evidence that all Project drafts are now native issues beneath the eight Sprint roots.
- Created the Sprint 0 local-SIT guide task [#108](https://github.com/digital-bank-java/.github/issues/108) beneath the Local Deployment epic; UAT and production instructions remain Sprint 7 work.
- Approved the strict Sprint 0 boundary: reproducible, operable, and verifiable local Kubernetes SIT only. UAT/production readiness, security, and observability outcomes must be owned by their later Sprints.
- Completed [Sprint 0 reconciliation task #107](https://github.com/digital-bank-java/.github/issues/107) after auditing 173 Project issues: exactly eight Sprint roots, all 173 issues reachable, and zero missing parents, cycles, missing Sprint values, or cross-Sprint direct relationships. The final active Sprint 0 scope contains 23 platform-foundation and local-SIT outcomes.
- Implementation and audit trail: [`.github` PR #106](https://github.com/digital-bank-java/.github/pull/106).
- Adopted outcome-based Sprint 0 through Sprint 7 delivery structure for GitHub Project #1.
- Created the eight sprint epics in `.github` and added the Project `Sprint` field.
- Captured pre-migration Project and relationship inventories before the migration.
- Converted Project DraftIssues to `.github` issues so native Issue Types can be applied consistently.
- Mapped historic and active work to a single Sprint without changing existing structured parent/sub-issue relationships.
- Verified 171 Project items, zero remaining DraftIssues, zero missing Sprint values, correct native and display issue types, and unchanged pre-existing parent/sub-issue relationships.
- Added a red `Bug` option to the Project `Item Type` display field and synchronized it with native GitHub issue types.
- Retained the historic `Phase`, `Slice`, `Epic`, and `Delivery Priority` fields because they hold unique historical classification data.
- Rebuilt the parent/sub-issue hierarchy so Sprint epics #18 through #25 are the only roots. Verified all 171 Project issues have the recorded intended parent, with no cross-Sprint parent relationship.
- Supporting migration task: [`.github#17`](https://github.com/digital-bank-java/.github/issues/17).

### 2026-08-04

- Sprint 1 closeout work started: customer/account OpenAPI metadata, gateway documentation resilience verification, and removal of active `local`/direct-service documentation references are being aligned before the Sprint 1 epic is closed.
- Consolidated formal runtime environments to `sit`, `uat`, and `prod`. `LOCAL-DEV` and the `local` Spring profile are retired; workstation runs are debugging against SIT.
- Removed local-profile configuration from `config-repo`, added SIT profile configuration, and verified Config Server precedence for `customer-service/sit`.
- Rolled out and verified Config Server, API Gateway, Customer Service, Account Service, and Ledger Service in `digital-bank-sit`.
- Verified gateway health, routed service health, central Swagger UI, representative customer/account APIs, and a workstation debugging session against port-forwarded SIT dependencies.
- Completed and closed the SIT Deployment and Developer Workflow epic, API Testing With Insomnia epic, and Gateway/service-routing health story.
- Began `.github#39` to establish this platform-conventions document and correct organization documentation drift.

### 2026-08-04 - Sprint 2 ledger reconciliation boundary

- Defined the Sprint 2 reconciliation architecture in [`docs/ledger-reconciliation.md`](ledger-reconciliation.md).
- Confirmed that `ledger-service` remains responsible for immutable balanced postings, idempotent replay, and append-only reversals.
- Kept event-driven consistency checks, account reservation consumption, and transfer saga correlation in Sprint 3.
- Kept scheduled reconciliation reporting, alerting, dashboards, and operational runbooks in Sprint 6.
- Separated operational reconciliation findings from immutable financial audit records; reconciliation may replay or create a compensating reversal but must never rewrite ledger history.

### 2026-07-09

- Added organization-level `AGENTS.md` in `.github`.
- Added repo-level `AGENTS.md` files to active repositories.
- Cleaned up merged AGENTS documentation branches.

### Earlier Project State

- Bootstrapped Config Server, API Gateway, Customer Service, Account Service, Ledger Service, Config Repo, and local SIT infrastructure.
- Established local SIT on Docker Desktop Kubernetes.
- Chose Kubernetes-native service discovery instead of Eureka.
- Chose `config-repo` as the Git-backed runtime configuration repository.
- Chose ledger-driven balance posting and rejected direct public balance mutation APIs.
- Chose Transaction Service as the future saga/process manager.

### 2026-08-31 - Deferred AWS and Cloud Deployment

- Deferred AWS/UAT/PROD deployment implementation until the remaining local SIT and core-domain work is complete.
- Kept `Sprint 7 - AWS UAT and Production Readiness` and its related production documentation, AWS migration, managed-service, and SonarQube Cloud items in the Backlog.
- Closed the unmerged Amazon OpenSearch UAT/PROD architecture PR as deferred; its issue and discussion remain available as future planning history.
- No AWS infrastructure, cloud deployment, or UAT/PROD rollout work should start in the current delivery wave.
- Continue local SIT implementation and verification for transaction, ledger, account, payment, notification, auth, MFA, gateway, and observability capabilities.
- Revisit the AWS target architecture after the local SIT/core-domain wave, with EKS, RDS/Aurora, MSK, AWS OpenSearch, and AWS Secrets Manager or Parameter Store remaining the planned direction.

### 2026-09-04 - Sprint 4 transfer-risk contract

- Created Task [`.github#194`](https://github.com/digital-bank-java/.github/issues/194) under Sprint 4 Story [`.github#55`](https://github.com/digital-bank-java/.github/issues/55) to define the versioned transfer-risk and step-up decision boundary.
- Documented the `ALLOW`, `REQUIRE_STEP_UP`, and `DECLINE` outcomes, transfer binding, policy versioning, replay protection, expiry, failure handling, audit requirements, and stable reason codes in [`docs/contracts/transfer-risk-step-up.md`](contracts/transfer-risk-step-up.md).
- Confirmed ownership boundaries: Transaction Service orchestrates transfer state, Auth Service owns identity/session assurance, MFA Service verifies challenges, and Ledger Service remains limited to immutable financial postings.
- Kept risk thresholds, MFA implementation, and transfer execution as follow-up implementation work; no business policy threshold was introduced by this contract.

### 2026-09-01 - Local SIT Delivery Priority

- Confirmed that AWS/UAT/PROD deployment implementation remains deferred until the local SIT and core-domain delivery wave is complete.
- Implemented and verified the local SIT transport configuration needed for the current Kafka workflow:
  - Account Service reservation transport: `71cfe80` on `feature/177-account-reservation-transport`.
  - Transaction Service reservation transport: `8922c06` on `feature/178-transfer-kafka-transport`.
  - Transaction Service SIT configuration: `8152613` on `fix/transaction-service-sit-config`.
  - Ledger Service outbox SIT configuration: `dbea1c2` on `feature/23-ledger-service-sit-config`.
- Full Maven `verify` and strict Helm lint/render checks passed for Account Service and Transaction Service with the local Docker runtime available.
- Ledger outbox delivery remains on the local/SIT track; its current review branch is `fix/176-ledger-outbox-safety` at `1dc0f81`.
- The next implementation wave should finish local/SIT Kafka integration, real-broker verification, topic governance, and event-contract work before AWS infrastructure is started.

### 2026-09-01 - Handoff State Correction

- Updated the implementation snapshot to distinguish merged platform capabilities from verified local/SIT event-delivery branches awaiting PR publication.
- Recorded the transaction-service bootstrap as implemented and removed it from the missing-work list.
- Replaced the stale Sprint 0 recommendation with the current local/SIT Kafka event-foundation sequence.
- Project status, parent, assignee, and native issue-type updates remain pending until GitHub API authentication is restored.

### 2026-09-01 - Local SIT Kafka Transport Wave

- Provisioned the `ledger.posting.requested.v1` command topic and dead-letter topic in the local SIT Kafka chart, with topic auto-creation disabled for SIT.
- Added the Ledger Service inbound posting consumer with durable inbox protection and mapping to the existing immutable posting port.
- Added the Transaction Service Ledger command outbox, Kafka publisher, and Ledger outcome consumer.
- Aligned the Transaction-to-Ledger command payload with the approved contract: envelope metadata, transaction and reservation identifiers, description, effective time, currency, and explicit debit/credit lines.
- Verified the Ledger consumer branch with `./mvnw verify` (28 tests, zero failures) and the Transaction transport branch with `./mvnw -q verify` (zero exit status).
- Pushed the four local/SIT branches; non-draft PR creation and Project item updates remain pending until GitHub authentication is restored.

### 2026-09-01 - Local SIT Domain Wave Audit

- Confirmed that the next local/SIT delivery wave is already prepared in task-backed branches; no AWS implementation is included.
- Auth Service is ready in dependency order: bootstrap, JWT/session foundation, then later durable session and gateway security work.
- MFA is prepared in dependency order: HTTP API, principal binding, TOTP enrollment, then challenge lifecycle. Its current stores are intentionally in-memory and remain a later durability/security concern.
- Payment Service is prepared in dependency order: HTTP lifecycle, PostgreSQL/idempotency/authorization, then resource-contract documentation. SIT configuration is available in `config-repo` on `feature/162-payment-service-sit-config`, but the service is not yet deployed in the SIT baseline.
- Notification transfer-consumer verification reports 15 passing tests; the transfer-saga branch reports passing domain, persistence, and Spring integration suites. Their PR publication and Project updates remain blocked by expired GitHub CLI authentication.
- GitHub Project status, parent, assignee, and native issue-type changes must be applied after authentication is restored; no item is to be treated as updated based only on local branch state.

### 2026-09-04 - Transfer Risk Decision Gate

- Started and implemented [.github#205](https://github.com/digital-bank-java/.github/issues/205) under Sprint 4 Story #55, with the project item moved to `In review`.
- Opened [transaction-service PR #16](https://github.com/digital-bank-java/transaction-service/pull/16) for review; it is intentionally not merged by the agent.
- Added a deterministic, configuration-driven transfer-risk gate with outcomes `ALLOW`, `REQUIRE_STEP_UP`, and `DECLINE` before account reservation is recorded.
- Persisted normalized transfer intent and the bound risk decision snapshot with Flyway migration 7, unique decision request/decision identifiers, expiry, and additive API response fields.
- `REQUIRE_STEP_UP` remains `PENDING` without a reservation action; `DECLINE` becomes `FAILED` without reservation or ledger actions. MFA challenge execution remains the follow-up under Story #56.
- Added focused risk-boundary tests, SIT verification documentation, runtime properties, and Helm values. Full Maven verify passed with 85 unit-phase tests and 15 integration tests; PostgreSQL Testcontainers, H2 migration validation, and Helm lint/render passed.
- No AWS/UAT/PROD work was started; this remains local SIT implementation.

### 2026-09-04 - Transfer-Bound MFA Challenge

- Created and parented [.github#206](https://github.com/digital-bank-java/.github/issues/206) under Sprint 4 Story #56, assigned it to `ramioooz`, and placed it in `In review`.
- Opened [mfa-service PR #10](https://github.com/digital-bank-java/mfa-service/pull/10) as a non-draft dependent PR; durable persistence [mfa-service PR #9](https://github.com/digital-bank-java/mfa-service/pull/9) must merge first, with no delay required.
- Added transfer-bound challenge creation and verification APIs that retain the risk decision, authenticated subject, account references, normalized amount/currency, policy version, and correlation ID.
- Added PostgreSQL Flyway migration 2 and persistence rehydration for the immutable binding; mismatched transfer/decision/subject verification returns a controlled conflict.
- Verified focused controller coverage, persistence migration/rehydration, full Maven `verify` (42 unit-phase and 19 integration tests), Helm lint/render, and `git diff --check`.
- API Gateway routing and Transaction Service continuation after MFA assurance remain follow-up integration work; no AWS/UAT/PROD work was started.

### 2026-09-04 - Transfer Notification Verification Guide

- Added the notification verification guide in [`docs/insomnia-transfer-notification-workflow.md`](insomnia-transfer-notification-workflow.md), tracked by [`.github#62`](https://github.com/digital-bank-java/.github/issues/62).
- The guide uses Insomnia to create a transfer through API Gateway, AKHQ to verify `TransferCreated.v1`, and read-only DBeaver checks for the Notification Service durable inbox and notification work records.
- Confirmed that Notification Service has no notification HTTP endpoint in the current scope; no fabricated direct-service request or public notification API was added.
- Kept duplicate delivery, retry, DLQ/quarantine, sensitive-data handling, and event/balance ownership boundaries explicit.
