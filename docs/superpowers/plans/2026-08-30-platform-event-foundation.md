# Sprint 3 Event Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the first executable event contracts and service-owned delivery boundaries for transaction, account, and ledger workflows.

**Architecture:** Transaction Service remains the transfer process manager. Account Service owns reservations and their local state. Ledger Service owns immutable postings and publishes completion/failure facts through a transactional outbox. Kafka is shared SIT infrastructure, while event schemas are versioned organization contracts.

**Tech Stack:** Java 21, Spring Boot 4, Spring Data JPA, Flyway, PostgreSQL, Apache Kafka, AsyncAPI documentation, Maven, JUnit 5, Testcontainers.

**Spec:** `.github/docs/platform-conventions.md`, `.github/docs/project-handoff.md`, `account-service/docs/balance-and-events.md`, and `ledger-service/README.md`.

## Global Constraints

- Runtime environments are `sit`, `uat`, and `prod`; `local` is retired.
- Public access flows through API Gateway; ledger posting and event endpoints remain internal.
- Ledger entries are append-only and balanced; original entries are never updated or deleted.
- Final account balance effects are driven by ledger events, not direct public balance-update APIs.
- Every consumed event is idempotent; every produced event is written to an outbox in the same transaction as its business state change.
- Do not commit secrets, tokens, private endpoints, or real credentials.
- Every repository change must use a dedicated branch and a non-draft PR; never merge to `main`.
- Run `./mvnw verify` for Java changes before opening a PR.

### Task 1: Publish governed ledger event contracts

**Files:**
- Create: `docs/contracts/ledger-events-asyncapi.yml`
- Modify: `docs/platform-conventions.md`
- Modify: `docs/project-handoff.md`

**Interfaces:**
- Produces the versioned event names `LedgerPostingCompleted.v1` and `LedgerPostingFailed.v1`.
- Defines required metadata: `eventId`, `eventType`, `schemaVersion`, `producer`, `occurredAt`, `aggregateId`, `correlationId`, `causationId`, `transactionId`, and `reservationRequestId`.
- Defines payload fields for posting id, posting request id, currency, multi-line debit/credit entries, decimal amounts, failure code, and failure reason.

- [ ] **Step 1: Write the AsyncAPI contract with channels `ledger.posting.completed.v1` and `ledger.posting.failed.v1`, Kafka bindings, producer/consumer ownership, partition keys, delivery semantics, Schema Registry boundaries, JSON schemas, and required metadata.**
- [ ] **Step 2: Add conventions for topic names, event versioning, correlation, and compatibility.**
- [ ] **Step 3: Update the handoff to record the contract as the dependency for Tasks 2-4.**
- [ ] **Step 4: Validate the YAML parses and contains both channels, messages, schemas, identifiers, producer/consumer ownership, partition keys, delivery semantics, and Schema Registry subjects.**
- [ ] **Step 5: Commit with `docs: define ledger event contracts`.**

### Task 2: Add Ledger Service transactional outbox and event publication boundary

**Files:**
- Create: `src/main/resources/db/migration/V4__add_ledger_outbox_events.sql`
- Create: `src/main/java/com/digitalbank/ledgerservice/application/port/out/LedgerEventPublisher.java`
- Create: `src/main/java/com/digitalbank/ledgerservice/adapter/out/events/LedgerOutboxEventJpaEntity.java`
- Create: `src/main/java/com/digitalbank/ledgerservice/adapter/out/events/SpringDataLedgerOutboxEventRepository.java`
- Create: `src/main/java/com/digitalbank/ledgerservice/adapter/out/events/PostgresLedgerEventPublisher.java`
- Modify: `src/main/java/com/digitalbank/ledgerservice/application/service/LedgerService.java`
- Modify: `src/main/java/com/digitalbank/ledgerservice/application/port/in/PostLedgerEntryCommand.java`
- Modify: `src/main/java/com/digitalbank/ledgerservice/application/port/in/PostLedgerReversalCommand.java`
- Test: `src/test/java/com/digitalbank/ledgerservice/application/service/LedgerServiceTest.java`
- Test: `src/test/java/com/digitalbank/ledgerservice/LedgerPersistenceIT.java`

**Interfaces:**
- `LedgerEventPublisher.recordPostingCompleted(LedgerEntry entry, UUID reversalOfLedgerEntryId, String transactionId, String reservationRequestId, String correlationId, String causationId, Instant occurredAt)`; `reversalOfLedgerEntryId` is null for normal postings and contains the original entry UUID for reversals.
- `LedgerEventPublisher.recordPostingFailed(String postingRequestId, String transactionId, String reservationRequestId, String failureCode, String failureReason, String correlationId, String causationId, Instant occurredAt)`.
- The current internal HTTP ledger posting and reversal endpoints require non-blank `X-Correlation-Id` and `X-Causation-Id` headers. Their inbound adapters copy them into `PostLedgerEntryCommand` and `PostLedgerReversalCommand` respectively; `LedgerService` passes both identifiers unchanged to the publisher and transactional outbox, including on reversal completion. Missing or blank headers are rejected with `400`; Task 2 must not generate either identifier.
- The publisher records an outbox row only; Kafka transport polling/publication is a later task. It generates `eventId` once, stores the exact payload and schema version, and reuses both on delivery retry.
- Terminal business failures (`VALIDATION_ERROR`, `CONFLICT`, and `ACCOUNTING_ERROR`) record a failure fact durably with the posting request and do not publish a failure fact for transient database or broker outages. The failure record is written transactionally with the durable classification.

- [ ] **Step 1: Add failing service tests proving successful posting records one completion event intent and a terminal business rejection records one failure event intent.**
- [ ] **Step 2: Add failing persistence tests proving the outbox table stores the event type, schema version, aggregate id, transfer/reservation identifiers, payload, correlation id, and unpublished state.**
- [ ] **Step 3: Add the Flyway migration with unique event id, one terminal outcome per posting request, aggregate/transfer/reservation indexes, status, attempts, and timestamps.**
- [ ] **Step 4: Implement the port and JPA adapter with JSON payload serialization using the existing service conventions; schema registration and compatibility validation remain a build/platform concern, not runtime credentials in the service.**
- [ ] **Step 5: Invoke the publisher from the posting transaction after the immutable ledger entry is persisted, or after a terminal business failure is durably classified; never publish from the HTTP handler.**
- [ ] **Step 6: Run `./mvnw verify` and confirm the existing idempotency/reversal tests still pass.**
- [ ] **Step 7: Commit with `feat: record ledger posting events in an outbox`.**

### Task 3: Add Account Service reservation persistence boundary

**Files:**
- Create: `src/main/resources/db/migration/V2__add_account_reservations.sql`
- Create: `src/main/java/com/digitalbank/accountservice/application/port/out/AccountReservationRepository.java`
- Create: `src/main/java/com/digitalbank/accountservice/application/port/in/ReserveFundsInputPort.java`
- Create: `src/main/java/com/digitalbank/accountservice/application/port/in/ReserveFundsCommand.java`
- Create: `src/main/java/com/digitalbank/accountservice/application/port/in/ReservationView.java`
- Create: `src/main/java/com/digitalbank/accountservice/application/service/AccountReservationService.java`
- Create: `src/main/java/com/digitalbank/accountservice/adapter/out/persistence/AccountReservationJpaEntity.java`
- Create: `src/main/java/com/digitalbank/accountservice/adapter/out/persistence/AccountReservationJpaMapper.java`
- Create: `src/main/java/com/digitalbank/accountservice/adapter/out/persistence/PostgresAccountReservationRepository.java`
- Create: `src/main/java/com/digitalbank/accountservice/adapter/out/persistence/SpringDataAccountReservationRepository.java`
- Test: `src/test/java/com/digitalbank/accountservice/application/service/AccountReservationServiceTest.java`
- Test: `src/test/java/com/digitalbank/accountservice/AccountPersistenceIT.java`

**Interfaces:**
- `ReserveFundsInputPort.reserve(ReserveFundsCommand command)` returns `ReservationView`.
- The command requires reservation request id, account id, currency, amount, correlation id, and expiry time.
- Reservation creation must atomically validate available balance, increment the account version, and enforce uniqueness of reservation request id.

- [ ] **Step 1: Add failing unit tests for sufficient funds, insufficient funds, duplicate request replay, and optimistic-lock conflict.**
- [ ] **Step 2: Add failing persistence tests for the reservation table and uniqueness constraints.**
- [ ] **Step 3: Add the migration with account foreign key, amount/currency checks, status, version, request id uniqueness, and timestamps.**
- [ ] **Step 4: Implement the repository port and PostgreSQL adapter using the existing account mapper and transaction conventions.**
- [ ] **Step 5: Implement the application service without adding a REST adapter or direct final-balance mutation endpoint.**
- [ ] **Step 6: Run `./mvnw verify` and document the internal port boundary.**
- [ ] **Step 7: Commit with `feat: add account reservation persistence boundary`.**

### Task 4: Add Transaction Service process-manager foundation

**Files:**
- Create: `src/main/java/com/digitalbank/transactionservice/TransactionServiceApplication.java`
- Create: `pom.xml`
- Create: `src/main/resources/application.properties`
- Create: `src/test/java/com/digitalbank/transactionservice/TransactionServiceApplicationTests.java`
- Create: `README.md`
- Create: `.github/CODEOWNERS`

**Interfaces:**
- The service starts as a Spring Boot process-manager shell only.
- It must not expose transfer endpoints, publish Kafka events, or mutate accounts/ledger in this task.

- [ ] **Step 1: Add a failing context test for the service bootstrap.**
- [ ] **Step 2: Add the minimal Spring Boot build with Actuator, Config Client, Web, Validation, OpenAPI, and test dependencies matching the organization baseline.**
- [ ] **Step 3: Configure SIT profile loading through Config Server without hardcoded credentials.**
- [ ] **Step 4: Implement the application bootstrap and health endpoint.**
- [ ] **Step 5: Document that transaction orchestration is the future process-manager owner and that Kafka/DB behavior is not yet implemented.**
- [ ] **Step 6: Run `./mvnw verify` and commit with `feat: bootstrap transaction service process manager`.**

## Integration Verification

- Validate Task 1 contract syntax and required fields.
- Validate Schema Registry subject names, compatibility policy, producer/consumer ownership, partition keys, at-least-once delivery, retry/DLQ behavior, security classification, and absence of PII/secrets.
- Run `./mvnw verify` in ledger, account, and transaction services.
- Run Helm lint/template validation for affected charts before rollout.
- Do not claim Kafka behavior until a publisher/consumer integration test proves it.
- Open separate non-draft PRs with explicit cross-repository links and preferred merge order: Task 1, then Tasks 2 and 3, then Task 4.

## Self-Review Checklist

- [ ] No task adds a public ledger balance mutation API.
- [ ] No task treats the ledger as a saga orchestrator.
- [ ] Event contracts are versioned before service implementation consumes them.
- [ ] Outbox writes are transactional and publication is not performed inside HTTP request code.
- [ ] Account reservations use idempotency and optimistic locking.
- [ ] Transaction Service remains a shell until its dependencies are available.
