# Digital Bank Java Project Handoff

Last updated: 2026-09-05

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
| [`config-repo#33`](https://github.com/digital-bank-java/config-repo/pull/33) and [`config-repo#34`](https://github.com/digital-bank-java/config-repo/pull/34) | Notification and Payment SIT configuration |
| [`infra-sit#29`](https://github.com/digital-bank-java/infra-sit/pull/29) | Transfer-created Kafka topic and dead-letter topic provisioning |
| [`config-repo#39`](https://github.com/digital-bank-java/config-repo/pull/39) | Auth, MFA, Transaction, and Payment gateway routes and centralized OpenAPI entries |
| [`config-repo#41`](https://github.com/digital-bank-java/config-repo/pull/41) | Account, Transaction, and Ledger event transport enablement in SIT |
| [`infra-sit#31`](https://github.com/digital-bank-java/infra-sit/pull/31) | Auth Service logical database reconciliation for existing SIT PVCs |
| [`infra-sit#24`](https://github.com/digital-bank-java/infra-sit/pull/24) | OpenSearch deployment for local SIT |
| [`infra-sit#25`](https://github.com/digital-bank-java/infra-sit/pull/25) | Fluent Bit log collection for local SIT |

The application PRs report focused Maven, Helm, and container verification. The
configuration PRs report YAML parsing and diff checks. SIT rollout, end-to-end
transfer demonstration, and secret provisioning still require separate evidence.

The Auth, MFA, Payment, Gateway security, Redis, and gateway resilience/rate-limit
PRs referenced in earlier handoff entries are merged. Their runtime rollout still
requires the open Config Repo changes above and SIT verification.

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

1. Merge [`config-repo#39`](https://github.com/digital-bank-java/config-repo/pull/39), which is clean after conflict repair and contains the Gateway security, workflow, and centralized Swagger routes.
2. Merge [`config-repo#33`](https://github.com/digital-bank-java/config-repo/pull/33) and [`config-repo#34`](https://github.com/digital-bank-java/config-repo/pull/34) in either order; both are clean after rebasing onto current `main`.
3. Merge [`config-repo#41`](https://github.com/digital-bank-java/config-repo/pull/41) to enable the Account, Transaction, and Ledger event transport in local SIT. Topic provisioning from [`infra-sit#29`](https://github.com/digital-bank-java/infra-sit/pull/29) should be available before end-to-end transfer verification.
4. Merge [`infra-sit#29`](https://github.com/digital-bank-java/infra-sit/pull/29) for transfer-created notification topics, then provision the Auth Secret and remaining service prerequisites.
5. Merge [`infra-sit#31`](https://github.com/digital-bank-java/infra-sit/pull/31), upgrade PostgreSQL, and wait for its database reconciliation Job before rolling out Auth Service. No fixed delay is required after merge.
6. Roll out Config Server, API Gateway image `0.0.3` from merged commit `23c1fa8`, Account Service, Ledger Service image `0.0.4`, Transaction Service, Payment Service, and Notification Service. Wait for Config Server to serve the merged revision before restarting clients.
7. Verify service health, protected Gateway workflows, rate limiting, centralized Swagger, Kafka topics/consumer groups in AKHQ, transfer saga state, and database state. Record evidence in the supporting issues.
8. For local observability, merge [`infra-sit#24`](https://github.com/digital-bank-java/infra-sit/pull/24) and then [`infra-sit#25`](https://github.com/digital-bank-java/infra-sit/pull/25); deploy OpenSearch before Fluent Bit and verify logs, redaction, dashboards, and alerts.
9. Keep UAT/PROD cloud deployment deferred to Sprint 7.

Consult GitHub Project #1 for the authoritative Sprint hierarchy and current issue status.

## Update Log

### 2026-09-05 - Enforced Project Sprint parent hierarchy

- Audited all 245 items in Digital Bank Project #1 across its paginated item connection.
- Confirmed that the eight Sprint epics are the only intended root planning items.
- Repaired the two parentless historical tasks: [`.github#202`](https://github.com/digital-bank-java/.github/issues/202) now belongs to Sprint 3, and [`.github#203`](https://github.com/digital-bank-java/.github/issues/203) now belongs to Sprint 4.
- Created the parented governance task [`.github#223`](https://github.com/digital-bank-java/.github/issues/223) under the Sprint 6 engineering-workflow story to make the parent-before-project rule explicit for future agents and contributors.
- The native GitHub sub-issue relationship is authoritative; a `Parent:` line in an issue body alone is not sufficient. New work must be assigned a Sprint, native Issue Type, parent, assignee, and Project status before implementation begins.
- After the governance repair, the full 246-item audit reports zero parentless non-Epic issues and zero missing native Issue Types. Corrected the native types for [`.github#125`](https://github.com/digital-bank-java/.github/issues/125), [`.github#128`](https://github.com/digital-bank-java/.github/issues/128), [`.github#130`](https://github.com/digital-bank-java/.github/issues/130), [`.github#166`](https://github.com/digital-bank-java/.github/issues/166), [`.github#167`](https://github.com/digital-bank-java/.github/issues/167), [`.github#168`](https://github.com/digital-bank-java/.github/issues/168), [`.github#169`](https://github.com/digital-bank-java/.github/issues/169), [`.github#182`](https://github.com/digital-bank-java/.github/issues/182), [`.github#183`](https://github.com/digital-bank-java/.github/issues/183), and [`infra-sit#26`](https://github.com/digital-bank-java/infra-sit/issues/26).

### 2026-09-05 - PostgreSQL prerequisite and current SIT event-flow state

- Confirmed the merged PostgreSQL database-init password fix in [`infra-sit#33`](https://github.com/digital-bank-java/infra-sit/pull/33) and retried the local SIT release without changing the existing PVC or data.
- Helm release `postgres` is now `deployed` at revision 5; the post-upgrade database-init hook completed successfully and was removed by its success policy.
- Read-only verification confirmed all expected logical databases, including `auth_service`, and all 12 SIT workloads are currently Ready.
- [`config-repo#41`](https://github.com/digital-bank-java/config-repo/pull/41), [`payment-service#9`](https://github.com/digital-bank-java/payment-service/pull/9), and the related infrastructure prerequisites are merged. The Notification Kafka fix is prepared in [`notification-service#9`](https://github.com/digital-bank-java/notification-service/pull/9), which was reopened because its code was previously validated only from a feature image and not merged to `main`.
- Sprint 3 event-flow task [`.github#213`](https://github.com/digital-bank-java/.github/issues/213) remains open until the Notification fix is merged and a representative transfer is verified end to end through reservation, ledger posting, outcome handling, and transaction state. No AWS/UAT/PROD work is included in this SIT checkpoint.

### 2026-09-05 - Auth Service SIT database prerequisite

- Created parented task [`.github#214`](https://github.com/digital-bank-java/.github/issues/214) under Auth session Story #46 and moved it to In review.
- Opened [`infra-sit#31`](https://github.com/digital-bank-java/infra-sit/pull/31) to add `auth_service` and reconcile all configured PostgreSQL databases on Helm install and upgrade, including existing persistent volumes.
- Local Helm lint, rendered manifest checks, and Kubernetes client-side dry-run passed. The GitHub Helm validation check is pending.
- Auth Service rollout must wait until this PR is merged and the reconciliation Job completes; no database credentials were added.

### 2026-09-05 - Config conflict repair and SIT event-flow configuration

- Confirmed [`api-gateway#23`](https://github.com/digital-bank-java/api-gateway/pull/23), [`infra-sit#23`](https://github.com/digital-bank-java/infra-sit/pull/23), [`config-repo#35`](https://github.com/digital-bank-java/config-repo/pull/35), and [`config-repo#36`](https://github.com/digital-bank-java/config-repo/pull/36) are merged.
- Rebased [`config-repo#39`](https://github.com/digital-bank-java/config-repo/pull/39) onto current `main` in commit `a58b222`; it is clean and non-draft.
- Rebased [`config-repo#33`](https://github.com/digital-bank-java/config-repo/pull/33) in commit `915df40` and [`config-repo#34`](https://github.com/digital-bank-java/config-repo/pull/34) in commit `71a669b`; both are clean and non-draft.
- Added parented Sprint 3 Task [`.github#213`](https://github.com/digital-bank-java/.github/issues/213) and opened [`config-repo#41`](https://github.com/digital-bank-java/config-repo/pull/41) to enable the merged Account, Transaction, and Ledger Kafka adapters in SIT.
- Verified all four Config Repo PRs are reviewable. No pull request was merged directly by the implementation agent.

### 2026-09-05 - Local observability conflict repair

- Rebased [`infra-sit#24`](https://github.com/digital-bank-java/infra-sit/pull/24) onto current `main` in commit `e0f8820`; OpenSearch chart validation passed.
- Rebased [`infra-sit#25`](https://github.com/digital-bank-java/infra-sit/pull/25) onto current `main` in commit `d54702f`; Fluent Bit chart and plain-text redaction validation passed.
- Preserved the merged Redis and Kafka infrastructure in both branches and kept OpenSearch/Fluent Bit limited to local SIT. AWS observability remains deferred.
- Both PRs are normal, non-draft, and ready for review. No pull request was merged directly by the implementation agent.

### 2026-09-04 - Gateway security merged and SIT rollout checkpoint

- Verified that `api-gateway#23` merged to `main` as commit `23c1fa8` after resolving its configuration conflict and isolating Redis health from the security test context.
- Built `digital-bank-java/api-gateway:0.0.3` from the merged commit and verified its non-root image metadata (`10001:10001`, port `8080`).
- Verified all current SIT workloads are healthy, but Redis is not installed and the Gateway deployment still runs image `0.0.2`.
- Verified the remaining Gateway prerequisite PRs are open and clean: `infra-sit#23`, `config-repo#35`, `config-repo#36`, and `config-repo#39`. `config-repo#36` currently targets the #35 feature branch and must be retargeted after #35 merges.
- Ledger Service consumer and Transaction Service assurance consumer are already merged, but their complete event flow remains dependent on intentional SIT topic/configuration rollout.
- No pull request was merged directly by the implementation agent. The next boundary is user review/merge of the Redis and Config Repo changes, followed by SIT rollout evidence.

### 2026-09-04 - Mainline merge checkpoint

- Verified that the recent review wave is on the service `main` branches, including Auth #8, Account #38, Customer #34, Ledger #17, MFA #12, Transaction #18, Payment #8, Notification #8, API Gateway #20, Infra SIT #30, Config Repo #40, and Config Server #21.
- Verified that the remaining security/configuration and delivery PRs are open and reviewable: Auth #6, MFA #8, Payment #7, Config Repo #32, Ledger #18, API Gateway #22 and #23, Infra SIT #23 through #25 and #29.
- Transaction Service is running the merged assurance-consumer release in local SIT. MFA remains on its previous SIT image until the shared Auth/MFA trust contract and configuration PRs are merged and rolled out together.
- No pull request was merged directly by the implementation agent. The next boundary is user review and merge, followed by SIT rollout evidence.

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

### 2026-09-04 - MFA Assurance Integration Boundary

- Created and classified [`.github#208`](https://github.com/digital-bank-java/.github/issues/208) under the transfer step-up story [`.github#56`](https://github.com/digital-bank-java/.github/issues/56), in Sprint 4 with native type `Task`, priority P0, and the `Step-Up Security` / `event-contracts` classification.
- Defined the next implementation boundary as an event-driven `MfaAssuranceGranted.v1` handoff: MFA writes the assurance outbox record atomically with successful challenge consumption; Transaction Service consumes it through an inbox and resumes the existing reservation outbox only after binding and expiry validation.
- Explicitly excluded synchronous MFA-to-Transaction calls, direct balance mutation, and AWS/UAT/PROD dependencies. Duplicate, malformed, mismatched, expired, and exhausted-retry events must be idempotent or quarantined without creating a financial action.
- Implemented and verified the event-driven assurance handoff in the merged [mfa-service PR #11](https://github.com/digital-bank-java/mfa-service/pull/11) and [transaction-service PR #17](https://github.com/digital-bank-java/transaction-service/pull/17). Task #208 is closed; SIT transport rollout and end-to-end verification remain tracked separately.

### 2026-09-04 - Transfer Notification Verification Guide

- Added the notification verification guide in [`docs/insomnia-transfer-notification-workflow.md`](insomnia-transfer-notification-workflow.md), tracked by [`.github#62`](https://github.com/digital-bank-java/.github/issues/62).
- The guide uses Insomnia to create a transfer through API Gateway, AKHQ to verify `TransferCreated.v1`, and read-only DBeaver checks for the Notification Service durable inbox and notification work records.
- Confirmed that Notification Service has no notification HTTP endpoint in the current scope; no fabricated direct-service request or public notification API was added.
- Kept duplicate delivery, retry, DLQ/quarantine, sensitive-data handling, and event/balance ownership boundaries explicit.

### 2026-09-04 - Shared Auth JWT Secret Runbook

- Added [`docs/sit-auth-jwt-secret.md`](sit-auth-jwt-secret.md) as the controlled local SIT procedure for generating, verifying, rotating, and removing the synthetic `auth-service-secrets/jwt-secret` value without exposing secret material.
- Recorded the shared Helm contract for Auth Service and Transaction Service, including the current merge dependencies and ordered rollout checks.
- Kept AWS Secrets Manager and External Secrets Operator delivery as deferred Sprint 7 scope for UAT and PROD; the local Kubernetes procedure must not be promoted to cloud environments.
- Supporting task: [`.github#192`](https://github.com/digital-bank-java/.github/issues/192).

### 2026-09-05 - Current SIT rollout review wave

- Merged the complete local SIT event-driven rollout guide in [`.github` PR #216](https://github.com/digital-bank-java/.github/pull/216), tracked by [task #215](https://github.com/digital-bank-java/.github/issues/215).
- A PostgreSQL Helm upgrade exposed an immutable StatefulSet `volumeClaimTemplates` label regression after the chart version changed. No PVCs were deleted and no data replacement was performed. The repair is tracked by [task #217](https://github.com/digital-bank-java/.github/issues/217) and [infra-sit PR #32](https://github.com/digital-bank-java/infra-sit/pull/32).
- The four immediate SIT rollout prerequisites are now merged: [infra-sit #32](https://github.com/digital-bank-java/infra-sit/pull/32), [config-repo #34](https://github.com/digital-bank-java/config-repo/pull/34), [infra-sit #29](https://github.com/digital-bank-java/infra-sit/pull/29), and [config-repo #41](https://github.com/digital-bank-java/config-repo/pull/41).
- [config-repo #39](https://github.com/digital-bank-java/config-repo/pull/39) is already merged; any earlier conflict indication for that PR is stale.
- The PostgreSQL retry was attempted after [infra-sit #32](https://github.com/digital-bank-java/infra-sit/pull/32) merged. The StatefulSet stayed `1/1` and the existing PVC remained `Bound`, but the database-init hook failed because `psql` was not given `PGPASSWORD`; this is tracked by [`.github#220`](https://github.com/digital-bank-java/.github/issues/220) and [infra-sit #33](https://github.com/digital-bank-java/infra-sit/pull/33). No PVC was deleted or replaced.
- After [infra-sit #33](https://github.com/digital-bank-java/infra-sit/pull/33) merges, retry the PostgreSQL release first, then roll out the merged Payment configuration, Kafka topics, and ledger-driven event configuration.
- API Gateway Redis rate limiting and downstream resilience are complete for the current code scope through merged [api-gateway #21](https://github.com/digital-bank-java/api-gateway/pull/21) and [api-gateway #22](https://github.com/digital-bank-java/api-gateway/pull/22); the tracking task and parent story are closed. SIT rollout verification remains part of the pending environment wave.
- The reusable MFA implementation story is complete through merged [mfa-service #1](https://github.com/digital-bank-java/mfa-service/pull/1) through [mfa-service #12](https://github.com/digital-bank-java/mfa-service/pull/12), and the Ledger command-consumer implementation is complete through merged [ledger-service #17](https://github.com/digital-bank-java/ledger-service/pull/17). Their organization tracking items are closed; MFA/ledger runtime enablement and verification remain separate SIT work.
- Do not record the full Auth, Payment, Notification, or event-driven transfer rollout as complete until the merged configurations are served by Config Server and the workloads and representative flows are verified in `digital-bank-sit`.

### 2026-09-05 - Backlog and review cleanup

- Closed completed Sprint 4 parent stories [`.github#55`](https://github.com/digital-bank-java/.github/issues/55) and [`.github#56`](https://github.com/digital-bank-java/.github/issues/56) after confirming that every native child task is closed. Their Project items are synchronized to `Done`.
- Closed superseded duplicate documentation PRs [`.github#193`](https://github.com/digital-bank-java/.github/pull/193) and [infra-sit#28](https://github.com/digital-bank-java/infra-sit/pull/28); [`.github#201`](https://github.com/digital-bank-java/.github/pull/201) is the authoritative replacement and remains open for review.
- Confirmed [config-repo#39](https://github.com/digital-bank-java/config-repo/pull/39) is merged. Any remaining conflict banner for that PR is stale.
- Confirmed [infra-sit#24](https://github.com/digital-bank-java/infra-sit/pull/24) is a normal, clean, mergeable review PR rather than a draft.
- Opened [infra-sit#33](https://github.com/digital-bank-java/infra-sit/pull/33) for the PostgreSQL init-hook credential wiring bug; it is clean, mergeable, and non-draft. No fixed delay is required after merge before retrying Helm.

### 2026-09-03 - Mainline Integration PR Wave

- Re-audited the service repositories and confirmed that several previously merged PRs were stacked into feature branches rather than present on `main`.
- Opened non-draft integration PRs for the complete reviewed stacks: Auth Service #5, MFA Service #7, Payment Service #6, Account Service #37, Ledger Service #17, API Gateway #22, Transaction Service #13, and Notification Service #6.
- Opened `.github` PR #186 to place the governed transfer-event contract on `main`; it should be available before enabling Notification Service transfer-event consumption.
- All service integration PRs passed their existing Maven, Helm, and container checks. No PR was merged directly.
- Added `.github#67` platform architecture documentation in PR #187, covering service ownership, local SIT topology, Kafka/outbox flow, ledger-driven transfer consistency, and the future AWS hosting direction.
- The next state transition requires human review and merge of the prepared PRs, followed by local SIT rollout and cross-service verification. AWS/UAT/PROD implementation remains deferred.

### 2026-09-05 - Ledger-driven destination projection

- Added the Account Service destination projection task [`.github#231`](https://github.com/digital-bank-java/.github/issues/231) as a native child of Sprint 3 saga story [`.github#103`](https://github.com/digital-bank-java/.github/issues/103). The task is assigned to `ramioooz`, typed as `Task`, and synchronized to `In review` in Project #1.
- Opened [account-service PR #39](https://github.com/digital-bank-java/account-service/pull/39) for review. It validates the governed destination line against the persisted reservation, atomically debits the source and credits the destination, supports the opposite reversal projection, persists destination identity in the ledger outcome inbox, and adds Flyway migration V6.
- Account Service verification passed: Spotless, focused outcome/mapper unit tests, the new PostgreSQL-backed destination replay test, and the full Maven `verify` gate with Testcontainers. PR #39 remains open and must be reviewed and merged before task #231 is closed.
- Confirmed [infra-sit PR #36](https://github.com/digital-bank-java/infra-sit/pull/36) merged. Closed the related PVC-upgrade bug [`.github#230`](https://github.com/digital-bank-java/.github/issues/230) after confirming the existing OpenSearch PVC stayed Bound during the chart upgrade.
- Closed completed OpenSearch deployment task [`.github#93`](https://github.com/digital-bank-java/.github/issues/93) and Maven quality-gate task [`.github#2`](https://github.com/digital-bank-java/.github/issues/2); their Project items remain under Sprint 6 and are `Done`.
- Fluent Bit remains `In progress`: the DaemonSet is healthy and has no output errors, but Docker Desktop exposes no standard container log files to the current `/var/log/containers` input. Centralized logging task [`.github#91`](https://github.com/digital-bank-java/.github/issues/91) must not be closed until a supported local log source is verified.
- Sprint 3 transfer verification remains open. All governed topics and consumer groups are healthy, but a representative successful transfer, duplicate-delivery proof, and deterministic DLQ proof still require a controlled SIT fixture with a positive source balance. No public balance-mutation endpoint should be added for this purpose.

### 2026-09-05 - Structured logging review wave

- Created and parented [`.github#233`](https://github.com/digital-bank-java/.github/issues/233) under Sprint 6 Story #64 to standardize ECS console output, bounded HTTP `X-Correlation-ID` propagation, safe request-completion events, and service-level redaction documentation across Customer, Account, Ledger, Transaction, Auth, MFA, Payment, and Notification Services.
- Opened the non-draft implementation PRs [customer-service #35](https://github.com/digital-bank-java/customer-service/pull/35), [account-service #40](https://github.com/digital-bank-java/account-service/pull/40), [ledger-service #19](https://github.com/digital-bank-java/ledger-service/pull/19), [transaction-service #21](https://github.com/digital-bank-java/transaction-service/pull/21), [auth-service #9](https://github.com/digital-bank-java/auth-service/pull/9), [mfa-service #15](https://github.com/digital-bank-java/mfa-service/pull/15), [payment-service #10](https://github.com/digital-bank-java/payment-service/pull/10), and [notification-service #11](https://github.com/digital-bank-java/notification-service/pull/11).
- All eight PRs passed their existing Maven verification/test phase, Helm validation, and container build/smoke checks. No redundant CI workflow or broad unit-test expansion was added.
- The API Gateway correlation and structured logging boundary was already present in merged [api-gateway #24](https://github.com/digital-bank-java/api-gateway/pull/24); no duplicate gateway implementation was retained.
- `.github#233` remains `In review` until the service PRs are merged. Fluent Bit/OpenSearch collection, Zipkin, immutable audit storage, and AWS deployment remain separate work.
- Re-audited Project #1 after the logging wave: all 20 active non-Epic items have a native GitHub parent, and no active task, story, or bug is unparented. Deferred Sonar work is correctly in `Backlog`.
- Closed completed parent items [`.github#28`](https://github.com/digital-bank-java/.github/issues/28), [`.github#52`](https://github.com/digital-bank-java/.github/issues/52), and [`.github#73`](https://github.com/digital-bank-java/.github/issues/73) after verifying their children and merged deliverables; their Project items are synchronized to `Done`.
- Closed completed MFA Provider Service epic [`.github#29`](https://github.com/digital-bank-java/.github/issues/29) after verifying its three native child stories and merged implementation deliverables. Step-Up Authorization remains open because [`.github#208`](https://github.com/digital-bank-java/.github/issues/208) is still active.
- Added parented Sprint 3 task [`.github#235`](https://github.com/digital-bank-java/.github/issues/235) and review PR [`.github#236`](https://github.com/digital-bank-java/.github/pull/236) to validate all four governed AsyncAPI documents in one path-scoped CI workflow. Local validation passed; runtime Schema Registry deployment remains outside this task.
- Opened review PR [`.github#237`](https://github.com/digital-bank-java/.github/pull/237), stacked on #236, to validate every representative AsyncAPI payload example against its declared local schema using the existing dependency-free validator. The check covers the schema constructs used by the four current contracts without adding a second CI job or generated Java DTO library; PR CI passed. Issue [`.github#61`](https://github.com/digital-bank-java/.github/issues/61) now records that generated service models and live Registry compatibility checks remain explicitly deferred, while producer/consumer runtime adoption remains Sprint 3 work.

### 2026-09-05 - SIT transfer transport configuration

- Opened [config-repo PR #44](https://github.com/digital-bank-java/config-repo/pull/44) for Sprint 3 task [`.github#213`](https://github.com/digital-bank-java/.github/issues/213). It adds the missing Transaction Service reservation topics, consumer group, retry policy, and publisher lease/retry settings to the SIT profile.
- Account Service and Ledger Service SIT transport settings were already present in the configuration baseline; no duplicate properties or alternate environment stack was introduced.
- YAML parsing, required-property checks, diff hygiene, and secret scanning passed. No Java tests, generated models, or additional CI workflow were added.
- The PR must merge before refreshing Config Server and rolling out Account, Transaction, and Ledger consumers for end-to-end SIT verification. A representative successful transfer, duplicate-delivery proof, and deterministic DLQ proof remain open acceptance checks; no public balance mutation endpoint should be added.

### 2026-09-05 - Ledger outbox SIT startup repair

- During the merged SIT transport rollout, Ledger Service exposed a startup defect when outbox delivery was enabled: Spring could not select between two transport constructors, and the service did not have Spring Boot Kafka auto-configuration for `KafkaTemplate`.
- Prepared [ledger-service PR #20](https://github.com/digital-bank-java/ledger-service/pull/20), tracked by parented Bug [`.github#238`](https://github.com/digital-bank-java/.github/issues/238) under Sprint 3 task [`.github#213`](https://github.com/digital-bank-java/.github/issues/213). The fix explicitly selects the properties constructor, resolves the scheduler delay from configuration, and uses `spring-boot-starter-kafka`.
- Full `./mvnw verify` passed with 27 unit-phase tests and 30 integration tests. The corrected local image `digital-bank-java/ledger-service:0.0.4` was rolled out to `digital-bank-sit`; Helm revision 8 is `deployed`, the pod is `1/1 Running`, the Kafka consumer joined `ledger.posting.requested.v1`, and health/OpenAPI checks passed.
- PR #20 has since merged; the local SIT rollout remains validation evidence only and is not a production deployment. End-to-end transfer evidence still requires a controlled positive-balance fixture.
- AsyncAPI validation task [`.github#235`](https://github.com/digital-bank-java/.github/issues/235) and structured logging task [`.github#233`](https://github.com/digital-bank-java/.github/issues/233) were closed after their merged PRs and passing CI; their parent stories remain open for runtime Schema Registry adoption and Fluent Bit/OpenSearch collection respectively.
- Ledger Service PR #20 completed Maven, Helm, and container CI checks successfully. The PR has merged and Bug #238 is now closed after review and tracking closeout.

### 2026-09-05 - Schema adoption and transaction completion validation

- Confirmed [`.github#61`](https://github.com/digital-bank-java/.github/issues/61) is closed as completed and its Project item is `Done`. The current producer/consumer implementations and merged AsyncAPI validation provide the Sprint 3 contract baseline; generated service models, a live Schema Registry, and cloud compatibility gates remain explicitly deferred.
- Confirmed [ledger-service PR #20](https://github.com/digital-bank-java/ledger-service/pull/20) and its handoff PR [`.github#239`](https://github.com/digital-bank-java/.github/pull/239) are merged. Bug [`.github#238`](https://github.com/digital-bank-java/.github/issues/238) is closed after the Ledger outbox transport startup repair and SIT validation.
- Added parented Sprint 3 Bug [`.github#240`](https://github.com/digital-bank-java/.github/issues/240) under transfer saga story [`.github#103`](https://github.com/digital-bank-java/.github/issues/103) to require exact ledger completion-line validation before a transfer becomes complete. Review PR [transaction-service #22](https://github.com/digital-bank-java/transaction-service/pull/22) is non-draft, mergeable, and has passing Maven, Helm, and container checks; it remains open for review and merge.
- The transaction fix preserves reservation/posting correlation, currency, and the exact source debit/destination credit lines; malformed or mismatched completion events remain unprocessed for retry/DLQ handling. No public balance-mutation endpoint, schema migration, redundant CI workflow, or broad unit-test expansion was added.
- Refreshed [`docs/insomnia-transfer-workflow.md`](insomnia-transfer-workflow.md) with the deployed transfer-bound MFA challenge flow, `AWAITING_STEP_UP` expectations, gateway paths, replay behavior, and read-only AKHQ/DBeaver evidence guidance. It keeps TOTP codes and credentials outside shared workspace data and does not claim that manual SIT evidence has been completed.
- Corrected parent tracking in Project #1: Sprint 3 child Epic [`.github#30`](https://github.com/digital-bank-java/.github/issues/30) is closed and `Done` because its three native children are complete; Sprint 4 Story [`.github#56`](https://github.com/digital-bank-java/.github/issues/56) is reopened and `In progress` because child task #208 remains open for behavioral SIT acceptance.
- Sprint 3 is not complete: the remaining acceptance boundary is controlled SIT verification of a successful transfer, duplicate delivery idempotency, and deterministic malformed-event DLQ behavior. Do not close [`.github#103`](https://github.com/digital-bank-java/.github/issues/103) or the related transfer verification task until that evidence exists.

### 2026-09-05 - Local SIT Zipkin tracing baseline

- Created and parented [`.github#242`](https://github.com/digital-bank-java/.github/issues/242) under Sprint 6 Story #64. It is a Task, assigned to `ramiooz`, and marked `In progress` in Project #1.
- Opened the non-draft implementation PRs [infra-sit #37](https://github.com/digital-bank-java/infra-sit/pull/37), [config-repo #45](https://github.com/digital-bank-java/config-repo/pull/45), [api-gateway #25](https://github.com/digital-bank-java/api-gateway/pull/25), [customer-service #36](https://github.com/digital-bank-java/customer-service/pull/36), [account-service #41](https://github.com/digital-bank-java/account-service/pull/41), [transaction-service #23](https://github.com/digital-bank-java/transaction-service/pull/23), [mfa-service #16](https://github.com/digital-bank-java/mfa-service/pull/16), and [ledger-service #21](https://github.com/digital-bank-java/ledger-service/pull/21).
- The infra PR adds an internal Zipkin 3.6.1 ClusterIP deployment with in-memory storage and no public exposure. The Config Repository PR enables bounded 100% sampling only for SIT and keeps tracing disabled by default outside an explicit environment.
- The six HTTP-path service PRs add only Spring Boot's managed `spring-boot-starter-zipkin`; they do not change business payloads, correlation-ID behavior, CI workflows, or add redundant tests. Existing tests passed: Gateway 20, Customer 7, Account 64, Transaction 89, MFA 46, and Ledger 27.
- Each service also keeps the exporter disabled by default for standalone/test execution; the shared SIT profile explicitly enables it. The Zipkin Helm chart uses the official slim image because this slice needs HTTP ingestion and in-memory storage only.
- Required next verification after merge: deploy Zipkin, refresh Config Server, roll out the affected services, then correlate one API Gateway request across at least two services in the Zipkin UI. Do not close #242 until this SIT evidence exists. AWS X-Ray/OpenTelemetry Collector mapping remains deferred to Sprint 7.

### 2026-09-06 - Auth fixture readiness for MFA acceptance

- Runtime inspection found that the deployed Auth Service received the JWT secret and fixture password hash, but not the synthetic fixture username required by the controlled MFA acceptance flow.
- Created and parented Sprint 4 Task [`.github#243`](https://github.com/digital-bank-java/.github/issues/243) under [`.github#208`](https://github.com/digital-bank-java/.github/issues/208). The task is assigned to `ramioooz`, typed as `Task`, marked `In progress`, and mapped to Sprint 4, Auth Service, and Step-Up Security.
- Opened [auth-service PR #11](https://github.com/digital-bank-java/auth-service/pull/11). It adds configurable `fixture-username` Secret wiring for `AUTH_FIXTURE_USERNAME` and documents the three required Auth Secret keys without adding credentials, routes, CI jobs, or redundant tests.
- The existing SIT Secret now contains the documented synthetic `fixture-username` key; existing Secret values were not read or changed.
- After PR #11 merges, roll out Auth Service and execute the controlled `.github#208` acceptance: one successful step-up, one assurance/outbox and Transaction inbox continuation, duplicate no-op, malformed-event DLQ, and read-only AKHQ/DBeaver evidence. Keep #208 and Sprint 4 open until those checks pass.

### 2026-09-06 - Fluent Bit Docker Desktop source probe

- A read-only SIT node probe confirmed that Docker Desktop exposes Docker JSON logs under `/var/lib/docker/containers/<container-id>/*-json.log`, while the standard `/var/log/containers` and `/var/log/pods` paths contain no readable log files for the DaemonSet.
- Docker container configuration labels do contain Kubernetes pod, namespace, container, and log-path metadata, but a raw path-only Fluent Bit input would not preserve that mapping or the existing structured-log enrichment contract.
- No partial collector was added. Fluent Bit task [`.github#94`](https://github.com/digital-bank-java/.github/issues/94) remains open until the runtime exposes supported Kubernetes log symlinks or a metadata-preserving Docker-ID adapter is implemented and verified.

### 2026-09-06 - Docker Desktop Fluent Bit fallback

- Implemented the Docker Desktop SIT fallback for Fluent Bit in [infra-sit PR #38](https://github.com/digital-bank-java/infra-sit/pull/38), tracked by [`.github#94`](https://github.com/digital-bank-java/.github/issues/94). The standard CRI `/var/log/containers` input remains unchanged and the Docker input is enabled only by `values-sit.yaml`.
- The fallback mounts `/var/lib/docker/containers` read-only, derives only selected Kubernetes labels from the matching `config.v2.json`, and never emits the full Docker config or environment. Structured, unstructured, and invalid records are redacted or quarantined in the record payload before OpenSearch delivery.
- Helm lint/template, existing Fluent Bit and redaction validators, the Docker-mode Fluent Bit 3.2.10 fixture, and `git diff --check` pass. The container-ID tag matcher was corrected to handle the actual `*-json.log` tag suffix and the focused fixture was rerun successfully.
- PR #38 is open, non-draft, mergeable, and its Helm CI check is green. Do not close #94 until the PR is reviewed/merged and the Docker Desktop SIT/OpenSearch evidence is repeated against the deployed chart.
- Current reviewable implementation PRs remain listed in the GitHub project; no direct merge to `main` was performed. After the pending service/config/Zipkin PRs are merged, roll out the observability wave and verify one cross-service trace before closing [`.github#242`](https://github.com/digital-bank-java/.github/issues/242).
- The current Docker Desktop SIT release was also runtime-verified: Fluent Bit processed 372 CRI records and 397 Docker JSON records, both OpenSearch outputs reported zero errors/retries, and an authenticated OpenSearch query returned 1,749 Docker-source documents with selected Kubernetes metadata. This is pre-merge evidence only; repeat it after PR #38 merges.

### 2026-09-06 - Resilience backlog deduplication

- Closed Sprint 6 Story [`.github#65`](https://github.com/digital-bank-java/.github/issues/65) as superseded. API Gateway circuit breaking and safe retries are already delivered by [api-gateway #20](https://github.com/digital-bank-java/api-gateway/pull/20) and [#22](https://github.com/digital-bank-java/api-gateway/pull/22), with Redis-backed rate limiting in [#21](https://github.com/digital-bank-java/api-gateway/pull/21).
- The story was a native child of the Observability & Resilience Epic, so no orphaned active project item was created. A future payment-provider-specific resilience change must be a concrete child of the Sprint 5 payment story with an identified downstream dependency; no duplicate implementation is planned.

### 2026-09-06 - Deferred payment-rail scope normalized

- The Sprint 5 child Epic [`.github#31`](https://github.com/digital-bank-java/.github/issues/31) remains open as the future payment-provider architecture boundary, but its Project status is now `Backlog`. It has no native children, and the current Payment Service README explicitly keeps provider integrations, Kafka publication, and external payment-rail behavior out of the implemented scope.
- Completed Payment Service and Notification Service lifecycle work remains historical evidence under Sprint 5. No provider-specific implementation was invented to fill an undefined dependency; future payment-rail work must be split into concrete native child tasks when a rail/provider contract is selected.

### 2026-09-06 - SIT tracing and reservation-event consistency follow-up

- SIT revealed a real Account-to-Transaction event contract defect: Account Service serialized reservation-event `Instant` values as numeric timestamps, while Transaction Service validates the governed `occurredAt` field as ISO-8601 text and compares it with the Kafka header. The resulting rejection event was consumed but left the transfer `PENDING` without a workflow event.
- Opened [account-service PR #42](https://github.com/digital-bank-java/account-service/pull/42), tracked by Bug [`.github#244`](https://github.com/digital-bank-java/.github/issues/244), to disable Jackson timestamp serialization for the reservation-event mapper. The focused regression test and full Maven `verify` with Testcontainers pass; GitHub Maven, Helm, and container checks are green. The PR remains open for review.
- Installed the merged local SIT Zipkin chart and found a Kubernetes startup defect: the official image declares the symbolic user `zipkin`, which cannot satisfy `runAsNonRoot` validation without a numeric identity. Opened [infra-sit PR #39](https://github.com/digital-bank-java/infra-sit/pull/39), tracked by [`.github#242`](https://github.com/digital-bank-java/.github/issues/242), to set the pod and container UID/GID to `1000` while retaining the hardening settings.
- Deployed the candidate Zipkin chart and rebuilt the merged API Gateway and Auth Service tracing images with temporary local SIT tags. A controlled gateway login produced one trace containing spans from both `api-gateway` and `auth-service`; Zipkin health and span ingestion returned successfully. This is pre-merge runtime evidence and must be repeated after PR #39 is merged with the normal release tags.
- No direct merge to `main`, public balance-mutation API, redundant CI workflow, or broad test expansion was introduced. The next transfer acceptance remains dependent on review/merge of #42, then a controlled positive-balance SIT fixture for successful reservation, ledger completion, duplicate delivery, and DLQ verification.
