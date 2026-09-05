# Insomnia Internal Transfer Workflow

This guide exercises the internal transfer workflow through the API Gateway in
local Kubernetes SIT. It checks request validation, authorization, risk
decision metadata, idempotent replay, and observable workflow state. It does
not call downstream services directly, mutate balances, or replace automated
service and event-contract tests.

## Current HTTP Contract

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/internal/v1/transfer-workflows` | Create or idempotently replay a transfer workflow |
| `GET` | `/internal/v1/transfer-workflows/{transferId}` | Read workflow state by transfer ID |

The request identifier is `transferId`; event contracts also refer to this
business identifier as `transactionId`. Keep all correlation and request IDs
stable for one workflow.

The transfer risk gate runs before a reservation action is recorded. It
returns `ALLOW`, `REQUIRE_STEP_UP`, or `DECLINE`. The step-up continuation is
documented in [the step-up transfer guide](insomnia-step-up-transfer-workflow.md).

## Preconditions And Environment

Confirm the local SIT gateway and workloads, then keep the gateway
port-forward running:

```bash
kubectl config use-context docker-desktop
kubectl get deployments,pods,services --namespace digital-bank-sit
kubectl port-forward --namespace digital-bank-sit service/api-gateway 8080:8080
```

Use `http://localhost:8080` or the selected forwarded port. Do not port-forward
Transaction, Account, Ledger, or MFA Service directly for this workflow.

Use a Base Environment plus `SIT`, `UAT`, and `PROD` child environments. The
Base Environment has empty placeholders only:

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
  "channel": "INTERNAL",
  "destinationClass": "INTERNAL"
}
```

Set credentials, tokens, synthetic IDs, and request IDs only in private/local
values. `SIT` is the active local environment. `UAT` and `PROD` require
approved HTTPS gateway values and explicit authorization. `local` and
`LOCAL-DEV` are not supported runtime environments.

Authenticate through the gateway using the auth/session workflow before
calling the protected transfer route. The token must have `transfer.internal`
and its `sub` must be in the configured transfer allowlist.

## 1. Create A Transfer

Generate fresh synthetic UUIDs and request IDs. Optional risk fields are
included below so the request matches the current risk-aware contract:

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
  "destinationClass": "INTERNAL"
}
```

`decisionRequestId`, `channel`, and `destinationClass` are optional. When
omitted, the service uses `transferRequestId`, `INTERNAL`, and `INTERNAL` as
the defaults. No `customerId`, identity claim, MFA code, or substitute
authorization header belongs in this request; the authenticated JWT subject
is the workflow customer/principal binding.

For a normal low-risk request, expect `201 Created`, `status: "PENDING"`, a
risk decision with `riskOutcome: "ALLOW"`, and a
`REQUEST_ACCOUNT_RESERVATION` action when the event transport is enabled.
The HTTP workflow foundation may return the accepted state before downstream
reservation processing is deployed.

The response may include `riskDecisionId`, `riskDecisionRequestId`,
`riskOutcome`, `riskReasonCodes`, `riskRequiredAssurance`,
`riskChallengeType`, `riskPolicyVersion`, `riskIssuedAt`, and `riskExpiresAt`.
Treat these as read-only decision evidence.

## 2. Inspect The Workflow

```http
GET {{ apiGatewayUrl }}/internal/v1/transfer-workflows/{{ transferId }}
Authorization: Bearer {{ authAccessToken }}
```

Expect `200 OK` for an existing workflow. Confirm the transfer IDs, request
identifiers, risk metadata, status, and actions match the test. An invalid
UUID returns `400` Problem Details; an unknown transfer returns `404`.

## 3. Idempotent Retry And Conflict

Resend the exact same `POST` request with the same transfer, correlation,
decision, and request identifiers. Expect `200 OK` with
`Idempotent-Replay: true`; no second workflow or reservation action is
created.

Then change one business value, such as `amount`, while retaining the same
transfer identity. Expect `409 Conflict` with `application/problem+json`.
There is no documented `Idempotency-Key` header for this endpoint.

## Risk Outcomes

The default Transaction Service risk configuration requires step-up for an
amount at or above `10000` in AED or USD and for `destinationClass:
"INTERNATIONAL"`. Use the deployed SIT configuration as the authority:

| Outcome | Expected workflow state | Reservation action |
| --- | --- | --- |
| `ALLOW` | `PENDING` | Normal reservation action may be recorded |
| `REQUIRE_STEP_UP` | `AWAITING_STEP_UP` or `PENDING` on older rollout | No reservation action until assurance |
| `DECLINE` | `FAILED` | No reservation action |

For `REQUIRE_STEP_UP`, capture the returned risk decision fields and continue
with the step-up guide. Do not add an `mfaCode` field to this transfer request.
For `DECLINE`, verify only the HTTP state and redacted problem/evidence; do
not alter database rows to manufacture an outcome.

## Authorization And Validation Checks

| Check | Expected result |
| --- | --- |
| Missing, malformed, invalid, expired, or revoked bearer | `401` Problem Details |
| Valid token without `transfer.internal` or allowlisted `sub` | `403` Problem Details |
| Missing/invalid UUID or field validation failure | `400` Problem Details with `errors` |
| Source and destination account IDs equal | `400` Problem Details |
| Exact duplicate request | `200` with `Idempotent-Replay: true` |
| Same identity with changed payload | `409` Problem Details |

## Evidence And Boundaries

Poll only through the gateway. A transfer HTTP response or `TransferCreated.v1`
event confirms workflow acceptance, not account balance mutation. Reservation,
ledger posting, account projection, and notification evidence require their
own deployed event contracts and read-only verification procedures.

Record only environment, date, request name, status, problem type, and opaque
IDs. Never share passwords, bearer tokens, Authorization headers, real
customer/account data, or unredacted event payloads.

Related contracts: [transfer events](contracts/transfer-events-asyncapi.yml),
[transfer risk and step-up](contracts/transfer-risk-step-up.md), and the
[local SIT guide](local-sit.md). Gateway routing and security are in [Config
Repo PR #39](https://github.com/digital-bank-java/config-repo/pull/39) and [API
Gateway PR #23](https://github.com/digital-bank-java/api-gateway/pull/23).
