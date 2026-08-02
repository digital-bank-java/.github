# Digital Bank Java Project Handoff

Last updated: 2026-08-02

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
| `infra-sit` | Local SIT infrastructure, currently shared PostgreSQL |

## Environment Model

| Environment | Meaning |
| --- | --- |
| `local` | Individual service execution from IDE or terminal |
| `sit` | Integrated local Kubernetes environment on Docker Desktop |
| `uat` | Future AWS-hosted pre-production environment |
| `prod` | Future AWS production environment |

Local SIT should resemble production shape where practical, but production should prefer managed AWS services rather than manually operated local-style containers.

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

Future Kafka event contracts should use AsyncAPI, not OpenAPI.

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

### Domain Boundaries

`customer-service` owns:

- customer registration
- customer profile retrieval/update
- admin customer search/listing

`account-service` owns:

- account opening
- account lookup
- account listing/search
- future available-balance reservations
- future account balance projection updates driven by ledger events

`ledger-service` owns:

- immutable ledger entries
- balanced debit/credit posting rules
- ledger lookup
- future ledger posting outcome events

No service should expose naive public balance mutation APIs.

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
  -> publish AccountReservationCreated through outbox

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

Implemented or substantially started:

- `config-server` bootstrap, tests, Dockerfile, Helm chart, CI, Git-backed config
- `config-repo` externalized service configuration
- `api-gateway` bootstrap, routing, centralized admin docs routes
- `customer-service` customer registration/profile APIs, persistence, tests, Dockerfile, Helm chart, CI
- `account-service` account opening/lookup/admin query APIs, persistence, tests, Dockerfile, Helm chart, CI
- `ledger-service` initial immutable ledger entry posting/lookup, persistence, tests, Dockerfile, Helm chart, CI
- `infra-sit` shared PostgreSQL Helm chart for local SIT
- org-level and repo-level `AGENTS.md` files
- Java test phase convention documentation

## Known Missing Work

High-priority missing capabilities:

- project handoff maintenance discipline after major changes
- Kafka infrastructure in local SIT
- AsyncAPI event contracts
- Transaction Service repository and bootstrap
- saga/process-manager implementation in Transaction Service
- account reservation tables and APIs
- account outbox/inbox tables and publishers/consumers
- ledger outbox and posting outcome event publication
- service-to-service security
- API Gateway rate limiting and resilience
- admin API authentication/authorization
- centralized logging with OpenSearch direction
- distributed tracing and correlation IDs
- AWS infrastructure path for UAT and production

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
for repo in .github config-server config-repo api-gateway customer-service account-service ledger-service infra-sit; do
  printf "\n== %s ==\n" "$repo"
  git -C "$repo" status -sb
done
```

## Recommended Next Work

Recommended immediate sequence:

1. Add Kafka to `infra-sit` as shared local SIT infrastructure.
2. Define event contract conventions and initial AsyncAPI layout.
3. Create and bootstrap `transaction-service`.
4. Implement account reservation model in `account-service`.
5. Add ledger posting outcome events in `ledger-service`.
6. Implement Transaction Service saga orchestration.

This sequence keeps infrastructure and contracts ahead of event-driven financial behavior.

## Update Log

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
