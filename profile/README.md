# Digital Bank Java

Digital Bank Java is a modular banking platform built to explore production-minded service boundaries, financial data integrity, event-driven workflows, and repeatable delivery on Kubernetes.

The project is currently focused on a local Docker Desktop Kubernetes environment named SIT. The core customer, account, ledger, transfer, authentication, MFA, payment, and notification foundations are implemented and exercised there. AWS deployment and SonarQube integration are deliberately deferred until the platform scope is complete.

## What It Provides

- Customer and account lifecycle services.
- An immutable, balanced ledger with idempotent postings and append-only reversals.
- Transaction workflow foundations for transfers and eventual consistency.
- Authentication, session, MFA, payment-instruction, and notification capabilities.
- Centralized configuration, API Gateway routing, Kafka event infrastructure, PostgreSQL persistence, Redis, tracing, logging, and AKHQ for local SIT operations.

The platform is an engineering project and reference implementation. It is not presented as a production banking system or as financial advice.

## Architecture At A Glance

Normal HTTP traffic enters through the API Gateway. The gateway routes authenticated business requests to the owning service. Each service owns its business data and communicates with other services through explicit APIs and governed Kafka contracts; services do not query another service's database directly.

For a transfer, Transaction Service coordinates the workflow, Account Service owns account state and reservations, and Ledger Service owns the official immutable accounting entries. Kafka events, outbox delivery, idempotent consumers, and reconciliation provide the foundation for eventual consistency. Payment and Notification Services own their respective lifecycles and do not mutate ledger balances directly.

The detailed boundary and event-flow decisions are documented in [`platform-architecture.md`](../docs/platform-architecture.md). Contract conventions are in [`platform-conventions.md`](../docs/platform-conventions.md), and the event schemas are documented in [`asyncapi-contracts.md`](../docs/asyncapi-contracts.md).

## Repository Map

| Repository | Responsibility |
| --- | --- |
| [`.github`](https://github.com/digital-bank-java/.github) | Organization engineering standards, public documentation, project handoff, and shared workflow guidance. |
| [`config-server`](https://github.com/digital-bank-java/config-server) | Spring Cloud Config Server that serves environment-specific configuration. |
| [`config-repo`](https://github.com/digital-bank-java/config-repo) | Versioned, non-secret runtime configuration consumed by Config Server. |
| [`api-gateway`](https://github.com/digital-bank-java/api-gateway) | Authenticated HTTP entry point, routing, centralized API documentation, and edge resilience. |
| [`customer-service`](https://github.com/digital-bank-java/customer-service) | Customer lifecycle and customer-owned data. |
| [`account-service`](https://github.com/digital-bank-java/account-service) | Account lifecycle, balances, reservations, and account projections. |
| [`ledger-service`](https://github.com/digital-bank-java/ledger-service) | Immutable double-entry postings, idempotency, reversals, and ledger outbox facts. |
| [`transaction-service`](https://github.com/digital-bank-java/transaction-service) | Transfer workflow and saga/process coordination. |
| [`auth-service`](https://github.com/digital-bank-java/auth-service) | Authentication, sessions, and token issuance/validation. |
| [`mfa-service`](https://github.com/digital-bank-java/mfa-service) | MFA enrollment, challenges, and step-up authorization support. |
| [`payment-service`](https://github.com/digital-bank-java/payment-service) | Payment instruction lifecycle and payment workflow state. |
| [`notification-service`](https://github.com/digital-bank-java/notification-service) | Notification delivery lifecycle and event-driven notification handling. |
| [`infra-sit`](https://github.com/digital-bank-java/infra-sit) | Local SIT Kubernetes dependencies, Helm values, Kafka, PostgreSQL, Redis, tracing, logging, and operational tooling. |

## Local SIT

SIT is the lowest shared runtime environment for development and integrated testing. It runs on local Docker Desktop Kubernetes in the `digital-bank-sit` namespace. UAT and PROD are future AWS environments, not currently required to run the platform.

Start with the [local SIT guide](../docs/local-sit.md). It covers prerequisites, dependency installation, service rollout, health checks, port-forwarding, centralized Swagger, Kafka inspection through AKHQ, and controlled synthetic test fixtures. Do not commit credentials or exported secrets; use Kubernetes Secrets and local environment variables as described by the repository documentation.

The supported workstation-debugging pattern is to run one service locally with the `sit` profile while connecting to port-forwarded SIT dependencies. Full gateway and event-flow verification remains a Kubernetes SIT workflow.

## Verification

Each Java service documents its Maven verification command and container workflow. Platform changes should be checked with the relevant service `./mvnw verify`, Helm lint/template validation, and the SIT health and API checks described in the service README and [Java testing guidance](../docs/testing/java-test-convention.md).

The API Gateway is the normal path for customer-facing API calls. Internal ledger posting endpoints remain protected internal contracts and are not public business routes. Centralized OpenAPI documentation is available through the gateway in SIT when the platform is running.

## Security And Scope

Secrets, tokens, credentials, private endpoints, and production data do not belong in source control or public documentation. Authentication and authorization are enforced at the gateway and service boundaries; internal service operations require the appropriate internal scope. Synthetic SIT fixtures are for local validation only.

The project deliberately separates completed local-SIT foundations from deferred work. AWS UAT/PROD deployment, production hardening, and SonarQube quality governance remain future delivery scope and are tracked in the organization project.

## Contributing

Read the organization [engineering standards](../README.md) and each repository's `AGENTS.md` and README before changing code. Work from an issue in the [Digital Bank Java project](https://github.com/orgs/digital-bank-java/projects/1), keep new work under a sprint parent, use a focused branch, and open a pull request for review. Do not merge directly to `main`.

Project status and architectural decisions are recorded in [`docs/project-handoff.md`](../docs/project-handoff.md). The project backlog remains the executable source of delivery status; this page is the public orientation point.
