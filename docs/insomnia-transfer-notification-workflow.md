# Insomnia Transfer Notification Workflow

This guide verifies the notification flow from the supported API entry point.
It does not add or imply a notification HTTP API. Transaction Service creates
the transfer, Kafka carries the `TransferCreated.v1` fact, and Notification
Service records durable notification work for later delivery.

Use synthetic SIT data only.

## Preconditions

The following dependencies must be available:

- API Gateway is reachable through the local SIT port-forward.
- Auth, Transaction Service, and Notification Service are healthy.
- The transfer workflow route and notification SIT configuration are deployed.
- The `events.transfer.created.v1` topic and its dead-letter topic exist.
- AKHQ is reachable at the local tooling URL for Kafka inspection.

The relevant delivery changes are:

- [Transaction Service transfer workflow](https://github.com/digital-bank-java/transaction-service/pull/15)
- [Notification Service consumer](https://github.com/digital-bank-java/notification-service/pull/7)
- [Notification SIT configuration](https://github.com/digital-bank-java/config-repo/pull/33)
- [Transfer topic provisioning](https://github.com/digital-bank-java/infra-sit/pull/29)
- [Transfer event contract](https://github.com/digital-bank-java/.github/blob/main/docs/contracts/transfer-events-asyncapi.yml)

The consumer flow is tracked by [`.github#60`](https://github.com/digital-bank-java/.github/issues/60).

## Insomnia Environment

Select the private **SIT** child environment. Keep credentials and tokens out
of exported workspace data.

| Variable | Example | Purpose |
| --- | --- | --- |
| `apiGatewayUrl` | `http://localhost:8080` | API Gateway port-forward |
| `authAccessToken` | private value | JWT with `transfer.internal` |
| `transferId` | fresh UUID | Transfer aggregate identifier |
| `sourceAccountId` | synthetic UUID | Source account |
| `destinationAccountId` | synthetic UUID | Destination account |
| `correlationId` | `sit-notification-correlation-001` | End-to-end workflow correlation |
| `transferRequestId` | `sit-transfer-request-001` | Transfer idempotency identity |
| `reservationRequestId` | `sit-reservation-request-001` | Reservation correlation |
| `postingRequestId` | `sit-posting-request-001` | Ledger posting correlation |

Use the API Gateway URL. Do not add a direct Notification Service URL to the
shared environment.

## 1. Create A Transfer

Send one fresh request through the gateway:

```http
POST {{ apiGatewayUrl }}/internal/v1/transfer-workflows
Authorization: Bearer {{ authAccessToken }}
Content-Type: application/json

{
  "transferId": "{{ transferId }}",
  "sourceAccountId": "{{ sourceAccountId }}",
  "destinationAccountId": "{{ destinationAccountId }}",
  "amount": 125.5000,
  "currency": "AED",
  "correlationId": "{{ correlationId }}",
  "transferRequestId": "{{ transferRequestId }}",
  "reservationRequestId": "{{ reservationRequestId }}",
  "postingRequestId": "{{ postingRequestId }}"
}
```

Expect `201 Created` with the transfer identifiers and an initial `PENDING`
status. A successful HTTP response confirms that Transaction Service accepted
the workflow; it does not by itself prove Kafka publication or notification
processing.

Record only the status code, opaque IDs, and correlation ID. Never record the
bearer token or any real account/customer data.

## 2. Verify The Transfer Event In AKHQ

Open the local AKHQ instance and select the SIT cluster:

```text
http://localhost:8088
```

Inspect topic `events.transfer.created.v1` and locate the event using the
recorded `correlationId`, `transferId`, or `eventId`.

Verify:

- `eventType` is `TransferCreated.v1`;
- `schemaVersion` is `1.0.0`;
- `producer` is `transaction-service`;
- `aggregateId` matches the transfer identifier;
- `correlationId` matches the Insomnia request;
- `transferRequestId`, `reservationRequestId`, and `postingRequestId` match;
- the event contains workflow data only and does not claim a balance mutation;
- the Kafka record key is the transfer aggregate key;
- the original event ID remains unchanged if the record is redelivered.

The topic is at-least-once. A duplicate delivery is safe only when the
consumer inbox recognizes the existing `eventId`; it is not a second business
fact.

## 3. Verify Notification Consumer Processing

In AKHQ, inspect the Notification Service consumer group configured for
`events.transfer.created.v1`. Confirm that the record is consumed without an
unbounded retry loop.

Then inspect the Notification Service PostgreSQL database with DBeaver. Use
the local SIT PostgreSQL port-forward and credentials supplied out of band.
The exact table names are owned by Notification Service migrations; inspect
the migration or service README before writing a query. The verification must
show:

- one durable inbox record for the event ID;
- one notification work record for the transfer/event identity;
- the stored correlation and event identity match the Kafka record;
- processing the same event again does not create a second inbox/work record;
- no bearer token, TOTP secret, or raw authentication credential is persisted
  in the notification payload or logs.

This is a read-only verification. Do not edit inbox or notification tables to
force a state, and do not replay a production-like event without an explicit
authorized procedure.

## 4. Verify The Transfer HTTP State

Poll the transfer through the gateway:

```http
GET {{ apiGatewayUrl }}/internal/v1/transfer-workflows/{{ transferId }}
Authorization: Bearer {{ authAccessToken }}
```

The returned status reflects Transaction Service workflow progress. Notification
processing does not complete the transfer and must not mutate account balances.
Ledger completion and account projection effects are verified through their
own event and persistence contracts.

## Negative And Retry Checks

| Check | Expected result |
| --- | --- |
| Missing or invalid bearer token | `401` Problem Details from the gateway |
| Authenticated token without `transfer.internal` | `403` Problem Details |
| Invalid transfer request | `400` Problem Details; no notification event |
| Exact transfer request retry | `200` with `Idempotent-Replay: true`; no duplicate event fact |
| Same transfer identity with changed payload | `409` Problem Details |
| Redelivered `TransferCreated.v1` with same `eventId` | One inbox/work record |
| Exhausted consumer retries | Original event and failure metadata in the configured DLQ/quarantine path |

Do not manufacture a notification failure by changing database rows. Failure,
retry, quarantine, and replay tests must use the approved SIT procedure for the
consumer and preserve the original event identity.

## Completion Evidence

Attach evidence to `.github#62` or the related implementation PR using only:

- environment and date;
- request name and HTTP status;
- opaque transfer/event/correlation IDs, where permitted;
- AKHQ topic and consumer-group observations;
- read-only database row counts or redacted identity checks;
- confirmation that no sensitive values were exported.

Do not attach raw JWTs, Authorization headers, passwords, real customer data,
database dumps, or unredacted Kafka payloads.

## Boundary

Notification Service currently consumes `TransferCreated.v1` and records
durable notification work. Provider delivery, customer-facing notification
history APIs, and production notification infrastructure are separate tracked
capabilities. This guide intentionally changes no application API and adds no
direct service endpoint.
