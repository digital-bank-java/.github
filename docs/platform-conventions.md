# Platform Conventions

This document is the canonical naming and interface convention for the Digital Bank Java platform. Repository `AGENTS.md` files may add repository-specific details but must not conflict with this document.

## Runtime Environments

The formal runtime environments are:

| Environment | Purpose | Current location |
| --- | --- | --- |
| `sit` | Development and integrated testing | Docker Desktop Kubernetes on a developer workstation |
| `uat` | Acceptance testing | Future AWS environment |
| `prod` | Production banking workload | Future AWS environment |

`local` and `LOCAL-DEV` are not runtime environments or supported Spring profiles. Running a service from VS Code or Eclipse is a workstation debugging technique. The process uses the `sit` profile and temporary environment-variable overrides to access port-forwarded SIT dependencies.

## Repository And Service Names

Use lowercase kebab-case names for service repositories, Docker images, Helm charts, Kubernetes Services, and Config Server application names.

| Service | Repository | Config name | Kubernetes Service | Default HTTP port |
| --- | --- | --- | --- | --- |
| Config Server | `config-server` | `config-server` | `config-server` | `8888` |
| API Gateway | `api-gateway` | `api-gateway` | `api-gateway` | `8080` |
| Customer Service | `customer-service` | `customer-service` | `customer-service` | `8081` |
| Account Service | `account-service` | `account-service` | `account-service` | `8082` |
| Ledger Service | `ledger-service` | `ledger-service` | `ledger-service` | `8083` |
| Transaction Service | `transaction-service` | `transaction-service` | `transaction-service` | `8084` |

New service ports must be allocated here before implementation. Do not reuse a port already assigned to a platform service.

## Java Names

- Use base package `com.digitalbank.<serviceidentifier>` where `<serviceidentifier>` is lowercase without separators, for example `com.digitalbank.customerservice`.
- Name Spring Boot application classes `<ServiceName>Application`.
- Use Java records for immutable request, response, command, and value objects where appropriate.
- Keep domain naming business-oriented. Do not expose persistence names such as `JpaEntity` outside outbound persistence adapters.

## Configuration Names

Runtime configuration lives in `config-repo`, served through Config Server.

```text
application.yml
application-{profile}.yml
{service}/{service}.yml
{service}/{service}-{profile}.yml
```

The effective order for a service/profile is:

1. `{service}/{service}-{profile}.yml`
2. `application-{profile}.yml`
3. `{service}/{service}.yml`
4. `application.yml`

Use `sit`, `uat`, and `prod` only for runtime profile overrides. CI fixtures may use `default` as an isolated test mechanism; it is not another deployment environment.

## HTTP And API Paths

- Route normal service APIs through `api-gateway`.
- Service APIs use `/api/v1/...`.
- Platform-admin APIs use `/admin/v1/...` and must later be protected by authorization.
- Gateway-routed health and documentation routes are internal/developer operations, not public customer surfaces.
- OpenAPI contracts remain service-owned and are aggregated through the gateway below `/admin/docs/...`.
- Each service contract must provide an explicit product-facing title, description, and semantic contract version. The version describes the API contract, not the Docker image or Helm chart version.
- Service OpenAPI documents are available at `/v3/api-docs` inside the cluster. The gateway exposes them at `/admin/docs/{service}/v3/api-docs`; the central UI is `/admin/docs/swagger-ui.html`.
- OpenAPI examples use synthetic data and document `application/problem+json` error responses, pagination, monetary values, and existing validation behavior.
- Use RFC 9457-style `application/problem+json` responses for documented errors.

## Ledger Reconciliation

Reconciliation compares the immutable ledger with account projections, reservations, and transfer state. It classifies missing postings, duplicate postings, stale projections, orphan reservations, and state divergence; it does not rewrite ledger history. The architecture and Sprint boundary are documented in [`docs/ledger-reconciliation.md`](ledger-reconciliation.md).

- Sprint 2 owns ledger invariants, idempotent posting, append-only reversals, and the reconciliation design contract.
- Sprint 3 owns event-driven consistency checks, outbox/inbox correlation, and transfer-state reconciliation.
- Sprint 6 owns scheduled reports, alerting, dashboards, and operational runbooks.
- Replay is allowed only through an idempotent workflow. Corrections use a new compensating reversal. Ambiguous cases are quarantined for authorized review.

## Infrastructure Names

- Docker image: `digital-bank-java/<service>:<version>`.
- Helm release and Kubernetes Service: the service name, unless a documented `fullnameOverride` is needed.
- Kubernetes namespace: `digital-bank-sit` for integrated platform workloads and `digital-bank-tooling` for developer tooling.
- Each service owns one logical PostgreSQL database named with snake_case, for example `customer_service`.
- Kafka topics use lowercase dot-separated event names, for example `ledger.posting.completed`; formal topic naming will be expanded with the AsyncAPI contract work.

## Required Service Baseline

A new Java service repository must include:

- `README.md` and repository-specific `AGENTS.md`
- `.gitignore`, `.gitattributes`, and `.github/CODEOWNERS`
- Maven Wrapper and a Java 21 Maven build
- `Dockerfile` and a Helm chart
- GitHub Actions CI running the repository quality gate
- Actuator health probes
- Config Client configuration
- unit and integration-test foundations

Create the supporting GitHub issue before adding or changing any baseline element.

## Verification

When adding a service, verify that its allocated port, configuration name, Docker image, Helm release, Kubernetes Service, logical database, gateway route, and OpenAPI title all use the same canonical service name.
