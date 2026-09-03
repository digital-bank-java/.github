# Digital Bank Java Platform Architecture

This document is the high-level architecture view for the Digital Bank Java platform. It describes the current service boundaries, the local SIT deployment shape, and the intended financial-event flow. It is a system map, not a list of customer-facing APIs.

## System Context

Normal application traffic enters through the API Gateway. Services own their business capabilities and data; they do not query another service's database. Config Server supplies externalized runtime configuration from `config-repo`.

```mermaid
flowchart LR
    Client[Client or internal operator] --> Gateway[API Gateway]

    Gateway --> Customer[Customer Service]
    Gateway --> Account[Account Service]
    Gateway --> Transaction[Transaction Service]
    Gateway --> Payment[Payment Service]
    Gateway --> Auth[Auth Service]
    Gateway --> MFA[MFA Service]
    Gateway --> Docs[Admin API documentation]

    ConfigRepo[config-repo] --> ConfigServer[Config Server]
    ConfigServer --> Customer
    ConfigServer --> Account
    ConfigServer --> Transaction
    ConfigServer --> Payment
    ConfigServer --> Auth
    ConfigServer --> MFA
    ConfigServer --> Notification[Notification Service]
    ConfigServer --> Ledger[Ledger Service]

    Customer --> CustomerDB[(customer_service)]
    Account --> AccountDB[(account_service)]
    Transaction --> TransactionDB[(transaction_service)]
    Payment --> PaymentDB[(payment_service)]
    Auth --> AuthStore[(Auth session store)]
    MFA --> MFAStore[(MFA provider state)]
    Ledger --> LedgerDB[(ledger_service)]
    Notification --> NotificationDB[(notification_service)]

    Transaction <--> Kafka[(Kafka)]
    Account <--> Kafka
    Ledger <--> Kafka
    Notification <--> Kafka
    Kafka --> Delivery[Outbox and inbox delivery]
    Kafka --> AKHQ[AKHQ developer tooling]
```

The diagram shows logical ownership. A shared PostgreSQL instance may host the logical databases in local SIT, but that does not create shared database ownership. In a hosted environment, the logical database mapping may move to managed PostgreSQL without changing the service boundaries.

## Service Responsibilities

| Service | Owns | Does not own |
| --- | --- | --- |
| API Gateway | Entry routing, resilience controls, and centralized internal API documentation | Business state or financial decisions |
| Customer Service | Customer identity and profile state | Accounts, balances, or transfers |
| Account Service | Account lifecycle, account lookup, reservations, and account projections | The immutable ledger or transfer status |
| Ledger Service | Balanced, immutable journal entries, reversals, and posting facts | Saga orchestration or account projection state |
| Transaction Service | Transfer workflow state and saga/process-manager decisions | The official financial journal |
| Payment Service | Payment instruction lifecycle and payment-specific state | Direct account balance mutation |
| Auth Service | Authentication sessions and signed access tokens | Customer profile or MFA enrollment state |
| MFA Service | MFA enrollment and challenge verification | Authentication session ownership |
| Notification Service | Notification delivery state and transfer notifications | Financial posting or transfer ownership |

## Transfer And Ledger Event Flow

The final account balance effect is driven by financial workflow events, not by a public balance-update endpoint.

```mermaid
sequenceDiagram
    participant T as Transaction Service
    participant A as Account Service
    participant K as Kafka
    participant L as Ledger Service
    participant N as Notification Service

    T->>T: Create transfer as PENDING
    T->>A: Request funds reservation
    A->>A: Validate available balance and reserve funds
    A->>K: Publish reservation outcome through outbox
    K-->>T: Reservation accepted or rejected
    T->>L: Request immutable debit and credit posting
    L->>L: Persist balanced ledger entry and outbox record
    L->>K: Publish LedgerPostingCompleted.v1 or LedgerPostingFailed.v1
    K-->>A: Settle or release reservation through inbox
    K-->>T: Advance or compensate transfer saga
    K-->>N: Deliver notification when the workflow requires it
```

Delivery is at least once. Outbox records are created with the business transaction, consumers use inbox identity and idempotency, and replay must be safe. Transaction Service owns the transfer saga; Ledger Service remains the financial posting authority and does not coordinate the saga.

The event contract and topic details are maintained in:

- [`docs/contracts/ledger-events-asyncapi.yml`](contracts/ledger-events-asyncapi.yml)
- [`docs/contracts/transfer-events-asyncapi.yml`](contracts/transfer-events-asyncapi.yml)
- [`docs/ledger-reconciliation.md`](ledger-reconciliation.md)

## Local SIT Topology

SIT is the lowest formal runtime environment and runs on Docker Desktop Kubernetes:

```mermaid
flowchart TB
    subgraph SIT[Namespace: digital-bank-sit]
        GatewaySIT[API Gateway]
        Services[Java services]
        ConfigSIT[Config Server]
        Postgres[PostgreSQL instance and logical databases]
        KafkaSIT[Kafka]
        GatewaySIT --> Services
        Services --> ConfigSIT
        Services --> Postgres
        Services --> KafkaSIT
    end

    subgraph Tooling[Namespace: digital-bank-tooling]
        AKHQTool[AKHQ]
    end

    AKHQTool --> KafkaSIT
    Workstation[Developer workstation] -->|kubectl port-forward| GatewaySIT
    Workstation -->|Headlamp Desktop| SIT
```

`digital-bank-tooling` contains developer tooling, not business services. Headlamp Desktop is the preferred local Kubernetes GUI; it is not part of the deployable banking runtime.

The standard local entry point is:

```bash
kubectl port-forward -n digital-bank-sit svc/api-gateway 8080:8080
```

Running one service from an IDE is workstation debugging against SIT with the `sit` profile and temporary port-forwarded dependency settings. It is not a separate `local` environment.

## Environment Promotion

| Environment | Runtime target | Purpose |
| --- | --- | --- |
| `sit` | Local Docker Desktop Kubernetes | Integrated development, contract checks, and repeatable demonstrations |
| `uat` | Future AWS Kubernetes and managed services | Acceptance testing and operational rehearsal |
| `prod` | Future AWS Kubernetes and managed services | Production banking workload |

The future AWS mapping is intentionally infrastructure-neutral at this layer. The current direction is EKS, managed PostgreSQL such as RDS or Aurora, managed Kafka such as MSK, AWS OpenSearch, and AWS-managed secrets. Cloud manifests and credentials remain Sprint 7 work.

## Boundary Rules

- Route normal service access through API Gateway.
- Keep administrative and aggregated documentation paths restricted and separate from customer APIs.
- Keep financial corrections append-only through compensating reversals.
- Keep secrets, tokens, OTP values, customer PII, and production endpoints out of Git.
- Add a tracked issue before changing a service boundary, port, topic contract, or deployment dependency.

