# AsyncAPI And Schema Registry Conventions

This document defines the contract and governance conventions for internal
event-driven APIs in the Digital Bank Java platform. It is a review baseline
for AsyncAPI documents and registered payload schemas; it is not a Kafka
implementation guide.

## Scope And Status

- Kafka work starts in the local `digital-bank-sit` environment. UAT and PROD
  work remains separately tracked and is not defined here.
- AsyncAPI documents define channels, operations, messages, headers, payloads,
  ownership, and delivery expectations.
- The Schema Registry stores serialized payload schemas and enforces the
  compatibility policy. It does not replace the AsyncAPI contract.
- This document does not add producers, consumers, outbox or inbox tables,
  Kafka provisioning, registry credentials, or deployment configuration.
- Contract examples use synthetic identifiers and data.

The current workflow direction is: Transaction Service starts a transfer and
requests an Account Service reservation; Account Service publishes reservation
facts; Ledger Service publishes a terminal posting outcome; Transaction Service
advances the transfer; and Notification Service may consume transfer facts for
delivery work. A transfer-created event does not reserve funds, post to the
ledger, or mutate an account balance.

## Contract Shape

Contracts use AsyncAPI `3.0.0` with `application/json` messages. A channel
represents one business message and its version. Each message declares whether
it is a `command` or an `event`:

- A command requests an action from one owning consumer and does not claim that
  the action happened.
- An event is a durable fact published by the service that owns the fact.
- A consumer must not treat an event as a command or infer a state transition
  from an unrelated topic.

Every message uses this common payload envelope. Domain fields follow the
envelope and must be defined by the concrete schema.

| Field | Required | Meaning |
| --- | --- | --- |
| `eventId` | Yes | Immutable identifier for this message instance. |
| `eventType` | Yes | Versioned name such as `TransferCreated.v1`. |
| `schemaVersion` | Yes | Registered schema version, for example `1.0.0`. |
| `producer` | Yes | Canonical service name that owns the message. |
| `occurredAt` | Yes | UTC timestamp when the command was created or fact occurred. |
| `aggregateId` | Yes | Aggregate identity used by the topic's partitioning rule. |
| `correlationId` | Yes | End-to-end workflow identifier. |
| `causationId` | Yes | Command or immediately preceding event that caused this message. |

The following Kafka headers are required on every governed message:

| Header | Value |
| --- | --- |
| `event-id` | Stable `eventId`; it is reused across delivery retries. |
| `correlation-id` | The same workflow value as `correlationId`. |
| `causation-id` | The same causal value as `causationId`. |
| `producer` | The same canonical service value as `producer`. |
| `schema-version` | The same registered version as `schemaVersion`. |
| `occurred-at` | The same UTC timestamp as `occurredAt`. |

Header names are kebab-case on the wire. Header values must agree with the
payload values so that consumers, inbox records, logs, and authorized replay
tools retain the same identity and trace information.

## Topic Naming

Use lowercase, dot-separated topic names with a stable domain, message name,
and major version:

```text
<domain>.<noun>.<verb>.v<major>
```

The existing `events.transfer.*` namespace is valid and must remain stable.
Do not add environment suffixes to governed topic names, reuse a topic for
unrelated messages, or rename a topic to correct a non-breaking description.
Create a new major version when the message meaning or breaking schema changes.

The current contract direction includes:

| Topic | Kind | Producer | Consumer or consumers | Partition key |
| --- | --- | --- | --- | --- |
| `account.reservation.requested.v1` | Command | `transaction-service` | `account-service` | `sourceAccountId` |
| `account.reservation.accepted.v1` | Event | `account-service` | `transaction-service` | `sourceAccountId` |
| `account.reservation.released.v1` | Event | `account-service` | `transaction-service` | `sourceAccountId` |
| `events.transfer.created.v1` | Event | `transaction-service` | `notification-service` | `transactionId` |
| `events.transfer.completed.v1` | Event | `transaction-service` | `notification-service` | `transactionId` |
| `events.transfer.failed.v1` | Event | `transaction-service` | `notification-service` | `transactionId` |
| `ledger.posting.completed.v1` | Event | `ledger-service` | `account-service`, `transaction-service` | `aggregateId` |
| `ledger.posting.failed.v1` | Event | `ledger-service` | `account-service`, `transaction-service` | `aggregateId` |

The account reservation contract also covers release requests, rejected
reservations, and expired reservations. The ledger outcome contract covers
immutable completion and failure facts, including reversal provenance. These
topics are governed by their concrete AsyncAPI contracts as they merge.

For a topic named `<topic>`, the default dead-letter target is
`<topic>.dlq`. A separate `<topic>.quarantine` target may be used when the
operating model distinguishes poison-message quarantine from retry exhaustion.

## Producers, Consumers, And Ownership

Each topic has one producer. The producer owns the message meaning, payload
schema, publication boundary, and compatibility review. Consumers are listed
in AsyncAPI and must be able to process the message without changing the
producer's state.

| Service | Owns | Does not own |
| --- | --- | --- |
| `account-service` | Account lifecycle, reservations, and account balance projections driven by ledger outcomes | Official ledger postings, transfer orchestration, or direct public balance mutation |
| `ledger-service` | Balanced immutable postings and posting outcome facts | Account projections or transfer saga state |
| `transaction-service` | Transfer workflow state, orchestration, and transfer facts | Official postings or direct account balance mutation |
| `notification-service` | Notification delivery work triggered by permitted events | Financial state, reservations, ledger entries, or transfer state |

One service may consume several facts, but it must validate the aggregate and
workflow identifiers and use its own state as the authority for its transition.
No consumer may publish a fact claiming another service's state changed.

## Schema Subjects And Versioning

Use `TopicNameStrategy` for value subjects:

```text
<topic>-value
```

For example, `ledger.posting.completed.v1` maps to
`ledger.posting.completed.v1-value`. A key schema is separately governed as
`<topic>-key` only when a typed key is required. The topic owner owns the
payload schema; platform infrastructure provisions the topic and registry
subject. AsyncAPI remains the source of contract meaning, while the registry
stores the serialized schema used by clients.

The default compatibility policy is `BACKWARD_TRANSITIVE`:

- Additive optional fields may be released within the same major event and
  subject after consumer review.
- Do not remove, rename, or change the type or meaning of a required field in
  a `v1` subject.
- Adding an enum value is compatibility-sensitive and requires consumer
  readiness; consumers must not fail on an unknown optional field.
- A breaking meaning or schema change creates a new event/topic major version,
  subject, and AsyncAPI message. Never overwrite `v1` to mean `v2`.
- `schema-version`, `eventType`, and the registry subject must agree.

Schema IDs, registry URLs, credentials, and environment-specific registry
configuration do not belong in the contract document.

## Partitioning And Ordering

Every channel declares a stable partition key. Producers use the same key for
all messages concerning one aggregate:

- reservation topics use `sourceAccountId`;
- transfer topics use `transactionId`;
- ledger outcome topics use the ledger posting aggregate identity.

Kafka ordering is guaranteed only for messages with the same key in the same
topic. There is no ordering guarantee across reservation request and outcome
topics, across ledger completion and failure topics, or across transfer
topics. Consumers must use persisted state, optimistic concurrency, and
correlation identifiers to handle delayed, duplicated, or out-of-order
messages. Broker order is not a substitute for a database invariant.

## Idempotency And Deduplication

Delivery is at least once. A producer must retain the same `eventId` and
correlation metadata when a publication is retried. A consumer must:

1. Check a durable inbox or equivalent deduplication record before applying a
   message.
2. Apply the state change and record successful consumption atomically.
3. Treat a repeated equivalent message as a no-op or replay of the original
   result.
4. Reject or quarantine a conflicting payload with the same business key.

Workflow-specific keys remain part of the domain contract. Examples include
`reservationRequestId`, `postingRequestId`, and `transactionId`. An event ID
prevents duplicate delivery effects; it does not replace a business
idempotency key. Replays must preserve the original event identity and must
not create a second financial posting, reservation, transfer outcome, or
notification request.

## Retries, DLQ, And Quarantine

Retry only transient failures such as temporary database, broker, or dependent
service unavailability. Use bounded backoff and an explicit attempt limit.
Terminal business outcomes, such as insufficient funds or a rejected ledger
posting, are facts to publish or consume; they are not consumer retry errors.

After the retry limit, write the original message and failure metadata to its
topic-specific DLQ or quarantine destination. Preserve the original topic,
partition key, headers, payload, error class, attempt count, and timestamps.
Do not publish a DLQ record as a new business event.

Replay is explicit, authorized, observable, and idempotent. A replay must
retain the original business identifiers and must not bypass schema validation,
authorization, reconciliation, or consumer state checks. Ambiguous financial
results, conflicting duplicates, malformed payloads, and suspected data
exposure go to quarantine for investigation rather than automatic replay.

## Security And PII

Governed event streams are confidential financial data unless a contract
declares a stricter classification. Payloads must use opaque identifiers such
as UUIDs; they must not contain account numbers, customer names, addresses,
phone numbers, email addresses, authentication data, credentials, tokens,
secrets, or stack traces.

Amounts and ISO currency codes may be included when required by the business
fact. Human-readable failure reasons must be sanitized and bounded. Do not
copy payloads or headers containing sensitive data into ordinary application
logs, pull requests, examples, or screenshots. Topic, subject, consumer, and
DLQ access must follow least privilege and the environment's approved Kafka
security controls. Credentials and connection details are runtime
configuration, never contract content.

## CI Validation Expectations

Every governed AsyncAPI document and referenced schema must be checked in CI
before merge. The contract check should:

1. Parse the YAML and verify a real AsyncAPI `3.0.0` document.
2. Resolve channel, operation, message, header, and payload references.
3. Require the common envelope, all six required headers, one producer,
   declared consumers, a partition key, at-least-once semantics, and a
   topic-specific DLQ or quarantine policy.
4. Verify the `TopicNameStrategy` subject mapping, schema version, and
   declared `BACKWARD_TRANSITIVE` compatibility.
5. Validate every representative example against its payload schema, including
   required fields, constants, formats, patterns, arrays, and object
   properties. The repository validator performs this deterministic local
   check without requiring a schema-validation dependency.
6. Compare changed subjects with the prior contract or registry snapshot and
   reject breaking changes under an existing major subject.
7. Run `git diff --check` and fail on malformed Markdown or accidental
   literal escape text in documentation.

The repository gate validates the checked-in contract examples. Registry
subject comparison and live compatibility checks remain release/platform
responsibilities because pull requests must not require access to a deployed
registry or production credentials.

Pull-request validation must be deterministic and must not require access to a
deployed Kafka cluster, production registry, cloud credentials, or real
customer data. A registry integration check may run with an approved
non-production fixture, but it must not make live production changes.

## Change Control

A contract change requires an issue, an owner review, an updated AsyncAPI
document, and consumer impact review. Producer or consumer implementation
pull requests should follow the governed contract rather than introduce
unreviewed topic names or payload fields. Contract changes that affect
multiple repositories must state the preferred merge order and any required
consumer migration period.

The parent API-contract standards story is
[#81](https://github.com/digital-bank-java/.github/issues/81). Related event
contract work includes
[.github PR #137](https://github.com/digital-bank-java/.github/pull/137) for
ledger outcomes,
[.github PR #173](https://github.com/digital-bank-java/.github/pull/173) for
transfer workflow events, and
[.github PR #176](https://github.com/digital-bank-java/.github/pull/176) for
account reservation and transfer workflow contracts.
