# Insomnia Internal Transfer Workflow

This is a repeatable manual workflow for exercising the internal transfer API
through the API Gateway in local Kubernetes SIT. It is a client-side smoke
check for request validation, workflow identity, authorization, and observable
transfer state. It does not deploy services, publish Kafka messages, mutate an
account directly, or replace automated service and contract tests.

## Current Contract And Boundary

The Transaction Service HTTP contract currently defines these internal routes:

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/internal/v1/transfer-workflows` | Create or idempotently replay a transfer workflow. |
| `GET` | `/internal/v1/transfer-workflows/{transferId}` | Inspect workflow state by transfer ID. |

The request uses `transferId` as the workflow identifier. The event contracts
refer to the same business identifier as `transactionId`. Keep
`correlationId`, `transferRequestId`, `reservationRequestId`, and
`postingRequestId` stable for one workflow.

The current Transaction Service implementation is an internal workflow
foundation, not a public customer transfer API. The API Gateway route,
account-reservation transport, ledger transport, and event-driven service
deployments are present in local SIT. The requests below still require the
SIT fixtures and credentials described by the acceptance task; an unavailable
downstream response is an environment result, not a transfer business result.

## Prerequisites

Use the [local Kubernetes SIT guide](local-sit.md) to confirm the
`docker-desktop` context, `digital-bank-sit` namespace, service rollouts, and
gateway health. Keep the gateway port-forward running while using Insomnia:

```bash
kubectl config use-context docker-desktop
kubectl get deployments,pods,services --namespace digital-bank-sit
kubectl port-forward --namespace digital-bank-sit service/api-gateway 8080:8080
```

Use `http://localhost:8080` as the workstation gateway URL. If port `8080` is
occupied, forward an unused workstation port such as `18080:8080` and change
only the active SIT `apiGatewayUrl` value. Do not port-forward or call
Transaction, Account, Ledger, or any other downstream service directly.

Before testing a protected route, use the approved private SIT fixture token.
The current Auth Service is still a deployable boundary and does not issue
login tokens through a customer-facing login route; absence of the fixture is
an acceptance prerequisite, not permission to bypass authorization. Do not
put an identity claim, MFA code, or substitute header in the transfer request
body.

## Environment Model

Keep one Insomnia workspace with a **Base Environment** and three named
sub-environments: **SIT**, **UAT**, and **PROD**.

| Environment | Use | `apiGatewayUrl` |
| --- | --- | --- |
| Base Environment | Variable names and empty placeholders only. | Empty; supplied by a sub-environment. |
| SIT | Active local Kubernetes integration testing. | `http://localhost:8080` or the selected forwarded port. |
| UAT | Cloud acceptance testing after that environment is approved and deployed. | Approved HTTPS gateway URL, supplied locally. |
| PROD | Explicitly authorized production verification only. | Approved HTTPS gateway URL, supplied locally. |

Use the same variable names in every environment. The Base Environment must
not contain usable credentials, tokens, or production endpoints:

```json
{
  "apiGatewayUrl": "",
  "authUsername": "",
  "authPassword": "",
  "authAccessToken": "",
  "transferId": "",
  "sourceAccountId": "",
  "destinationAccountId": "",
  "amount": "125.5000",
  "currency": "AED",
  "correlationId": "",
  "transferRequestId": "",
  "reservationRequestId": "",
  "postingRequestId": "",
  "decisionRequestId": "",
  "destinationClass": "INTERNAL",
  "mfaEnrollmentId": "",
  "mfaChallengeId": "",
  "riskDecisionId": "",
  "riskDecisionRequestId": "",
  "riskPolicyVersion": "",
  "otpCode": ""
}
```

Set credentials, bearer tokens, and test identifiers only in private/local
environment values or through an approved secret source. Never export those
values into a shared workspace. `local` and `LOCAL-DEV` are not supported
runtime environments; a workstation client uses the `sit` environment.

## Authenticate First

When the protected auth route is available, select **SIT** and use the
approved auth workflow before selecting any transfer request:

```http
POST {{ apiGatewayUrl }}/api/v1/auth/login
Content-Type: application/json

{
  "username": "{{ authUsername }}",
  "password": "{{ authPassword }}"
}
```

Store the returned access token only in the private/local `authAccessToken`
value. Use it on every protected transfer request:

```http
Authorization: Bearer {{ authAccessToken }}
```

For the implemented Transaction Service authorization contract, the token
must authenticate a subject that has the `transfer.internal` scope and whose
`sub` claim is in the configured transfer allowlist. The observable security
checks are:

| Check | Expected result |
| --- | --- |
| Missing, malformed, invalid, expired, or revoked bearer token | `401` `application/problem+json` |
| Valid token without `transfer.internal` or without an allowlisted `sub` | `403` `application/problem+json` |
| Valid token with the required scope and allowlisted subject | Continue to the transfer contract check. |

MFA is a separate, transfer-bound precondition. Do not add an `mfaCode` field
to the transfer request. The transfer response carries the risk decision
metadata needed to start the MFA challenge, and the MFA Service publishes
`MfaAssuranceGranted.v1` after successful verification. Transaction Service
then resumes the existing reservation outbox; MFA does not mutate balances.

The gateway exposes these MFA routes under the same protected API surface:

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/v1/mfa/transfer-challenges` | Create or replay a challenge bound to one transfer and risk decision. |
| `POST` | `/api/v1/mfa/transfer-challenges/{challengeId}/verifications` | Verify the bound challenge with the authenticator code. |

The challenge must use the same authenticated subject, transfer ID, decision
ID, reservation request ID, accounts, amount, currency, policy version, and
correlation ID returned by the transfer workflow. Keep the TOTP code only as a
short-lived private value; never export it or place it in a shared collection.

## Create A Transfer

Generate fresh synthetic UUIDs and request identifiers for a new test. Do not
reuse identifiers from a prior transfer except when deliberately testing the
idempotent retry below. Set the values in the private/local SIT environment,
then send:

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
  "postingRequestId": "{{ postingRequestId }}",
  "decisionRequestId": "{{ decisionRequestId }}",
  "channel": "INTERNAL",
  "destinationClass": "{{ destinationClass }}"
}
```

For a newly accepted workflow, expect `201 Created` and a JSON response with
the transfer identifiers, amount, currency, `status: "PENDING"`, a starting
`version`, and an action such as `REQUEST_ACCOUNT_RESERVATION`. The action is
an orchestration result; Insomnia must not call a downstream service with it.

The request validation contract supports these checks:

- `transferId`, account IDs, and all request identifiers are required.
- Source and destination account IDs must differ.
- `amount` must be positive, with up to 15 integer digits and 4 fraction
  digits.
- `currency` must contain exactly three letters; use an uppercase ISO 4217
  code in examples.
- `correlationId`, `transferRequestId`, `reservationRequestId`, and
  `postingRequestId` must be non-blank and at most 100 characters.

Malformed JSON, invalid UUIDs, or failed field/cross-field validation return
`400` `application/problem+json` with a validation problem and an `errors`
array. This is a request failure, not a `FAILED` transfer state.

## Complete A Step-Up Transfer

To exercise the step-up path, set `destinationClass` to `INTERNATIONAL` or use
an amount that exceeds the configured SIT high-value threshold. The current
SIT defaults require step-up for `INTERNATIONAL` transfers and for amounts at
or above the configured AED/USD threshold. Do not assume a `PENDING` response
means step-up was requested; inspect the response fields.

Expected risk-gated response:

- HTTP `201 Created` for the first workflow request;
- `status: "AWAITING_STEP_UP"`;
- `riskOutcome: "REQUIRE_STEP_UP"`;
- `riskDecisionId`, `riskDecisionRequestId`, `riskRequiredAssurance: "MFA"`,
  `riskChallengeType`, `riskPolicyVersion`, and `riskExpiresAt` populated;
- no reservation command action yet.

Copy the response values into private/local variables, then create the bound
challenge through API Gateway:

```http
POST {{ apiGatewayUrl }}/api/v1/mfa/transfer-challenges
Authorization: Bearer {{ authAccessToken }}
Content-Type: application/json

{
  "enrollmentId": "{{ mfaEnrollmentId }}",
  "transferId": "{{ transferId }}",
  "reservationRequestId": "{{ reservationRequestId }}",
  "decisionId": "{{ riskDecisionId }}",
  "decisionRequestId": "{{ riskDecisionRequestId }}",
  "sourceAccountId": "{{ sourceAccountId }}",
  "destinationAccountId": "{{ destinationAccountId }}",
  "amount": 125.5000,
  "currency": "AED",
  "policyVersion": "{{ riskPolicyVersion }}",
  "correlationId": "{{ correlationId }}"
}
```

The first request returns `201 Created`; an identical request returns `200 OK`
with `Idempotent-Replay: true`. Save only the opaque `challengeId` in the
private SIT environment. Verify it with a current authenticator code:

```http
POST {{ apiGatewayUrl }}/api/v1/mfa/transfer-challenges/{{ mfaChallengeId }}/verifications
Authorization: Bearer {{ authAccessToken }}
Content-Type: application/json

{
  "transferId": "{{ transferId }}",
  "decisionId": "{{ riskDecisionId }}",
  "code": "{{ otpCode }}"
}
```

Poll the transfer workflow using the existing GET request. A valid first
verification should publish the assurance event and advance the workflow into
reservation processing. Repeating the same verification must not publish a
second assurance event or create a second reservation command. A mismatched,
expired, exhausted, or replayed challenge must return a Problem Details error
and must not resume the transfer.

For event evidence, use AKHQ to inspect the governed assurance topic and its
consumer group. Use read-only DBeaver queries against the MFA and Transaction
databases to compare the challenge, assurance outbox, workflow inbox, and
workflow action rows. Do not publish a forged Kafka payload or update these
tables manually. The malformed-event and DLQ acceptance check is separate from
this happy-path workflow and must be recorded only after the controlled SIT
fixture has been executed.

## Inspect The Workflow

Use the `transferId` from the create request without changing it:

```http
GET {{ apiGatewayUrl }}/internal/v1/transfer-workflows/{{ transferId }}
Authorization: Bearer {{ authAccessToken }}
```

Expect `200 OK` when the workflow exists. Confirm the returned identifiers and
status match the create request. An unknown transfer ID returns `404`
`application/problem+json`; an invalid transfer ID returns `400`.

The current read response exposes `actions` for deterministic orchestration
work. It does not expose an account balance mutation operation and it does not
prove that a reservation or ledger posting has happened.

## Idempotent Retry And Duplicate Checks

To simulate a client timeout or safe retry, resend the exact same `POST`
request with the same `transferId`, `correlationId`,
`transferRequestId`, `reservationRequestId`, and `postingRequestId`:

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

The implemented HTTP behavior is `200 OK` with
`Idempotent-Replay: true`. The response represents the existing workflow; it
does not create another reservation request or another transfer.

Then change one business value, such as `amount`, while retaining the same
`transferId`, and send the request again. Expect `409 Conflict` with
`application/problem+json` because the request conflicts with existing
workflow data. Reusing a request identifier for a different workflow is also
a conflict. There is no documented `Idempotency-Key` header for this
endpoint; the transfer and request identifiers are the contract keys.

## Workflow Outcomes

Use `GET` through the gateway to observe state. Do not try to force an event
outcome by changing the response body or by calling an account or ledger
balance API.

| Scenario | Observable contract behavior | Availability |
| --- | --- | --- |
| Pending | Create returns `201` with `PENDING`; the workflow awaits reservation processing. | HTTP workflow foundation is implemented. |
| Insufficient funds / reservation rejected | Account Service rejects the reservation when available-balance rules fail; Transaction Service eventually records `FAILED` and the saga releases the reservation. | Implemented in the merged event-driven services; requires a controlled SIT fixture and persisted evidence. |
| Duplicate | Exact retry returns `200` and `Idempotent-Replay: true`; changed data for an existing identity returns `409`. | Implemented in the workflow HTTP contract. |
| Awaiting ledger posting | An accepted reservation advances the workflow to `AWAITING_LEDGER_POSTING` and produces the next orchestration action. | Implemented; verify through the deployed Account, Ledger, Kafka, and Transaction consumers. |
| Completed | A governed ledger posting completion advances the workflow to `COMPLETED`. | Implemented; verify the ledger posting, account projection, and transaction inbox evidence together. |
| Failed | A reservation rejection or ledger posting failure produces terminal `FAILED` state; compensation follows the event contract. | Implemented; verify release/reversal behavior and the terminal state in SIT. |
| Authorization denied | Missing/invalid credentials return `401`; an authenticated subject without the required scope or allowlist entry returns `403`. | Implemented in the merged gateway and Transaction Service security path; requires the SIT secret and fixture. |
| MFA / step-up | A transfer-bound challenge can be created and verified; the resulting assurance fact resumes only the matching `AWAITING_STEP_UP` workflow. | Implemented in the merged Auth, MFA, and Transaction services; requires the controlled SIT TOTP fixture. |

`REVERSED` is a domain state in the workflow foundation, but the current HTTP
surface does not provide a reverse operation. Do not document or test reversal
as an Insomnia request until a tracked contract adds it.

## Balance And Event Evidence

The create request and `TransferCreated.v1` fact announce workflow processing;
they do not move money. A reservation accepted by Account Service holds the
source amount against available balance. Final account effects are driven by
the reservation and ledger workflow events, with Ledger Service remaining the
owner of immutable postings. There is deliberately no direct public balance
mutation API for this test.

For the current merged event-driven stack, collect evidence in this order:

1. Record the create response and its `transferId`/`transactionId`,
   `correlationId`, and request identifiers.
2. Poll the transfer `GET` request through the gateway until it reaches the
   expected state or the agreed SIT timeout.
3. If account lookup is part of the deployed SIT contract, read the source and
   destination accounts through their gateway routes and compare the observed
   projection with the reservation and ledger evidence.
4. If Kafka inspection is enabled, use the approved local AKHQ tooling to
   correlate event IDs and topics. Preserve the original event identity when
   discussing retries; an at-least-once redelivery is not a new business fact.

The account-reservation and transfer-event contracts are the source of truth
for event ownership, correlation, idempotency, and terminal outcomes. The
implementation is merged, but the Sprint 3 acceptance remains incomplete until
the controlled SIT scenarios and their Account, Ledger, Transaction, Kafka, and
AKHQ/DBeaver evidence are recorded. Report only the state and event identities
that were actually observed.

## Safe Evidence And Export Rules

- Never export or sync passwords, bearer tokens, cookies, session IDs, or
  private environment values.
- Never paste an `Authorization` header or raw JWT into an issue, pull
  request, screenshot, log, or test artifact.
- Use synthetic account IDs and request IDs. Redact any real customer or
  account identifiers before sharing evidence.
- Preserve status codes, problem `type`, `title`, `detail`, and field names;
  replace sensitive values with deterministic placeholders so the request can
  still be correlated without revealing data.
- Check the rendered request, response, console, and environment export before
  attaching evidence. Clear private/local token values after the test.

## Related Work

- [Local Kubernetes SIT guide](local-sit.md)
- [Platform conventions](platform-conventions.md)
- [Transfer contract PR #173](https://github.com/digital-bank-java/.github/pull/173)
- [Transfer event contract PR #176](https://github.com/digital-bank-java/.github/pull/176)
- [Transaction Service repository](https://github.com/digital-bank-java/transaction-service)
- [Sprint 3 transfer verification task](https://github.com/digital-bank-java/.github/issues/213)

The contract PRs and the relevant Transaction Service HTTP, authorization,
outbox, Account, and Ledger work are merged and deployed in local SIT. A
passing workflow still requires a fresh authorized synthetic fixture and
end-to-end evidence. This document intentionally changes no application,
gateway, account, ledger, AWS, or cloud implementation.
