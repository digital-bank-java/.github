# Insomnia Step-Up Transfer Workflow

This guide exercises the existing risk-gated internal transfer and
transfer-bound MFA workflow through the API Gateway. It covers the
`REQUIRE_STEP_UP` decision, challenge binding, one-time verification, and
event-driven continuation. It does not add a transfer approval endpoint,
change risk thresholds, or call a downstream service directly.

## Implemented Boundary

The workflow is owned by existing service contracts:

1. Transaction Service evaluates the transfer intent and persists a risk
   decision.
2. `REQUIRE_STEP_UP` leaves the transfer non-postable with no reservation
   action and exposes the risk decision identifiers.
3. MFA Service creates and verifies a challenge bound to that exact transfer
   and decision.
4. Successful verification publishes `MfaAssuranceGranted.v1` through the
   MFA outbox.
5. Transaction Service consumes the assurance, revalidates the binding and
   expiry, and resumes its reservation action.

The synchronous HTTP calls stop after MFA verification. Assurance publication
and transfer continuation are verified through the event and transfer read
contracts, not by inventing a `POST /approve` or `POST /resume` route.

## Preconditions And Variables

Use the local Kubernetes SIT gateway port-forward from the
[local SIT guide](local-sit.md). The Auth, MFA, Transaction, and gateway
rollouts must be healthy. Gateway routing/security and SIT configuration are
provided by [Config Repo PR #39](https://github.com/digital-bank-java/config-repo/pull/39), [API Gateway PR #23](https://github.com/digital-bank-java/api-gateway/pull/23), and the related service releases.

Use private/local values for:

| Variable | Purpose |
| --- | --- |
| `apiGatewayUrl` | Gateway port-forward, normally `http://localhost:8080` |
| `authAccessToken` | Authenticated JWT with `transfer.internal` and MFA access |
| `transferId` | Fresh transfer UUID |
| `sourceAccountId` | Synthetic source account UUID |
| `destinationAccountId` | Synthetic destination account UUID |
| `amount` | Synthetic risk-test amount, normally `12500.0000` AED |
| `currency` | `AED` or another configured risk currency |
| `correlationId` | Stable transfer correlation identifier |
| `transferRequestId` | Stable transfer request identifier |
| `reservationRequestId` | Stable reservation identifier |
| `postingRequestId` | Stable posting identifier |
| `decisionRequestId` | Stable risk decision request identifier |
| `mfaEnrollmentId` | Active enrollment ID for the authenticated subject |
| `riskDecisionId` | Returned `riskDecisionId` from the transfer response |
| `riskDecisionRequestId` | Returned decision request ID |
| `riskPolicyVersion` | Returned risk policy version |
| `mfaChallengeId` | Returned transfer-bound challenge ID |
| `mfaCode` | Private current TOTP code |

The default SIT risk policy requires step-up for `INTERNATIONAL` destination
class or an AED/USD amount at or above `10000`. Confirm the deployed policy
before running the test; configuration is authoritative.

## 1. Create A Step-Up Transfer

Authenticate using the auth/session workflow, then send a fresh transfer with
a configured step-up condition. The example uses the default high-value
condition:

```http
POST {{ apiGatewayUrl }}/internal/v1/transfer-workflows
Authorization: Bearer {{ authAccessToken }}
Content-Type: application/json

{
  "transferId": "{{ transferId }}",
  "sourceAccountId": "{{ sourceAccountId }}",
  "destinationAccountId": "{{ destinationAccountId }}",
  "amount": 12500.0000,
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

Expect `201 Created`, `riskOutcome: "REQUIRE_STEP_UP"`,
`riskRequiredAssurance: "MFA"`, `riskChallengeType: "TOTP"`, a non-expired
`riskDecisionId`, and no reservation action. The risk-gated workflow should
remain in `AWAITING_STEP_UP` on the current Transaction Service release. Keep
the following response values unchanged: transfer ID, reservation request ID,
decision ID, decision request ID, account IDs, amount, currency, policy
version, and correlation ID.

If the response is `ALLOW`, the deployed risk configuration did not classify
the request as step-up. Stop and use the configured test condition; do not
pretend that an ALLOW response is a step-up result.

## 2. Create The Transfer-Bound MFA Challenge

The authenticated subject must have an active enrollment. The request binds
the challenge to the exact transfer and risk decision:

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
  "amount": 12500.0000,
  "currency": "AED",
  "policyVersion": "{{ riskPolicyVersion }}",
  "correlationId": "{{ correlationId }}"
}
```

Expect `201 Created` with `status: "CREATED"`, an opaque `challengeId`,
`challengeStatus: "OPEN"`, `expiresAt`, `remainingAttempts`, and the bound
transfer/decision metadata. Capture `challengeId` as `mfaChallengeId`. An
exact repeated create returns `200 OK` with `Idempotent-Replay: true` and the
existing challenge; it must not create a second challenge.

Do not change any bound field between the transfer and challenge requests.
The challenge request does not accept a customer ID override; the
authenticated JWT `sub` is bound by MFA Service.

## 3. Verify The Transfer-Bound Challenge

Submit the current code from the approved authenticator:

```http
POST {{ apiGatewayUrl }}/api/v1/mfa/transfer-challenges/{{ mfaChallengeId }}/verifications
Authorization: Bearer {{ authAccessToken }}
Content-Type: application/json

{
  "transferId": "{{ transferId }}",
  "decisionId": "{{ riskDecisionId }}",
  "code": "{{ mfaCode }}"
}
```

Expect `200 OK` with `status: "VERIFIED"`,
`challengeStatus: "CONSUMED"`, and the same transfer/decision binding. The
challenge is single-use. Do not send the code again after success.

## 4. Verify Assurance And Continuation

After the successful verification, the MFA Service writes and publishes one
`MfaAssuranceGranted.v1` fact to `mfa.assurance.granted.v1`. Inspect the
approved SIT Kafka tooling and confirm the event retains the same transfer,
reservation, decision, policy, account, amount, currency, correlation, and
challenge identifiers. The event must contain `assuranceType: "MFA"`,
`challengeType: "TOTP"`, and a future `expiresAt`.

Then poll the existing transfer read request:

```http
GET {{ apiGatewayUrl }}/internal/v1/transfer-workflows/{{ transferId }}
Authorization: Bearer {{ authAccessToken }}
```

Transaction Service must accept only a matching, unexpired assurance event.
The workflow should leave `AWAITING_STEP_UP`, return to `PENDING`, and expose
the deterministic reservation action once the assurance consumer and
reservation transport are enabled in SIT. If those event consumers are not
deployed, report the HTTP challenge verification as successful but the
continuation as unavailable; do not claim that funds were reserved.

## Negative And Replay Checks

| Check | Expected result |
| --- | --- |
| Missing/invalid bearer | `401` Problem Details |
| Missing MFA authorization scope | `403` Problem Details |
| Inactive or unknown enrollment | `404` or `409` Problem Details according to enrollment state |
| Transfer challenge with changed binding | `409` binding-mismatch Problem Details |
| Verification with wrong transfer or decision ID | `401` binding-mismatch or controlled verification failure |
| Wrong six-digit code | `401` invalid-code; attempts decrease |
| Expired challenge or assurance | `401` expired Problem Details; no assurance continuation |
| Replayed consumed challenge | `401` replayed Problem Details; no second assurance |
| Duplicate assurance event ID | One durable inbox/business action only |
| Malformed, mismatched, or exhausted assurance event | Quarantine/DLQ path; no reservation action |

Never edit workflow, MFA, inbox, or outbox rows to force a result. Preserve
event IDs for retry analysis and use only the approved SIT replay procedure.

## Evidence And Boundaries

Record environment/date, request names, status codes, opaque identifiers,
topic/consumer observations, and redacted binding checks. Never record
passwords, bearer tokens, TOTP codes, TOTP secrets, Authorization headers, or
unredacted Kafka payloads.

The authoritative contracts are [transfer risk and step-up](contracts/transfer-risk-step-up.md) and [MFA assurance events](contracts/mfa-assurance-events-asyncapi.yml). Implementation references are [Transaction Service PR #16](https://github.com/digital-bank-java/transaction-service/pull/16), [MFA Service PR #10](https://github.com/digital-bank-java/mfa-service/pull/10), [MFA assurance publisher PR #11](https://github.com/digital-bank-java/mfa-service/pull/11), and [Transaction assurance consumer PR #17](https://github.com/digital-bank-java/transaction-service/pull/17). This guide adds no new API or infrastructure behavior.
