# Transfer Risk And Step-Up Decision Contract

Status: design contract for Sprint 4
Contract version: `1.0.0`
Owner: Transaction Service workflow, with Auth Service and MFA Service security boundaries

This document defines the decision boundary for a transfer that may require
step-up authentication. It does not define business risk thresholds and does
not implement a risk engine, MFA challenge, or transfer execution.

## Purpose

Before a transfer reserves funds or creates a ledger posting, the workflow must
know whether the request can proceed, must obtain stronger authentication, or
must be declined. The decision is a versioned, auditable result bound to the
specific transfer intent.

The initial implementation may evaluate this contract inside Transaction
Service. A later policy evaluator may be a separate service, but moving the
evaluator must not change the contract or the ownership boundaries below.

## Decision Boundary

The sequence is:

1. Transaction Service accepts a transfer request and creates a transfer
   correlation identifier.
2. Transaction Service requests a risk decision for the transfer intent.
3. An `ALLOW` decision lets the transfer workflow continue to reservation.
4. A `REQUIRE_STEP_UP` decision starts an MFA challenge bound to the transfer.
5. A successful MFA result provides assurance evidence for the same transfer
   intent; it does not change the amount, accounts, beneficiary, or currency.
6. A `DECLINE` decision terminates the request without reservation or posting.

Transaction Service owns transfer state and orchestration. Auth Service owns
identity and session authentication. MFA Service owns challenge creation and
verification. Ledger Service owns balanced immutable postings only; it does
not decide customer risk or MFA requirements.

## Request Contract

The evaluator receives a normalized transfer intent. Thresholds and policy
rules are configuration owned by the authorized security and business policy
process, not values embedded in clients.

```json
{
  "contractVersion": "1.0.0",
  "decisionRequestId": "risk-req-001",
  "transferId": "transfer-001",
  "customerId": "customer-001",
  "sourceAccountId": "account-001",
  "destinationAccountId": "account-002",
  "amount": "1250.75",
  "currency": "USD",
  "channel": "WEB",
  "destinationClass": "INTERNAL",
  "requestedAt": "2026-09-04T10:15:00Z",
  "sessionContext": {
    "sessionId": "session-001",
    "authenticationAssurance": "STANDARD",
    "deviceTrust": "KNOWN"
  },
  "policyVersion": "transfer-risk-policy-2026-09"
}
```

Required rules:

- `amount` is a decimal string and is normalized with the platform currency
  precision before evaluation.
- Account, customer, beneficiary, currency, amount, and channel are part of
  the transfer binding and cannot be changed after a decision is issued.
- `decisionRequestId` is idempotent for the normalized request. Reusing it for
  different content is a conflict.
- Raw passwords, access tokens, OTP values, and full payment credentials are
  never sent to or stored by the evaluator.
- The evaluator receives only the identity, session, device, velocity, and
  transaction context needed by the active policy.

## Response Contract

Every response has one explicit outcome:

```json
{
  "contractVersion": "1.0.0",
  "decisionId": "risk-decision-001",
  "decisionRequestId": "risk-req-001",
  "transferId": "transfer-001",
  "outcome": "REQUIRE_STEP_UP",
  "reasonCodes": ["NEW_DEVICE", "POLICY_REQUIRES_STEP_UP"],
  "requiredAssurance": "MFA",
  "challengeType": "TOTP",
  "policyVersion": "transfer-risk-policy-2026-09",
  "issuedAt": "2026-09-04T10:15:01Z",
  "expiresAt": "2026-09-04T10:20:01Z",
  "correlationId": "transfer-001"
}
```

Outcome semantics:

| Outcome | Meaning | Next workflow action |
| --- | --- | --- |
| `ALLOW` | Current authentication and policy checks permit the transfer | Continue to account reservation |
| `REQUIRE_STEP_UP` | Stronger authentication is required before continuation | Create a transfer-bound MFA challenge |
| `DECLINE` | The request is not permitted by the active policy | Record a terminal transfer failure; do not reserve or post |

Reason codes are stable machine-readable identifiers. User-facing messages
must be mapped outside the evaluator and must not disclose sensitive risk
signals. The initial code set is intentionally small and extensible:

- `POLICY_REQUIRES_STEP_UP`
- `NEW_DEVICE`
- `UNTRUSTED_SESSION`
- `VELOCITY_LIMIT`
- `BENEFICIARY_RISK`
- `POLICY_DECLINED`
- `RISK_EVALUATOR_UNAVAILABLE`

The policy version and decision identifiers must be retained with the transfer
audit record. A decision must be single-use and valid only until `expiresAt`.

## Step-Up Binding Rules

An MFA challenge created from `REQUIRE_STEP_UP` must bind to:

- `transferId` and `decisionId`;
- customer or authenticated principal identity;
- source and destination account references;
- normalized amount and currency;
- the active policy version;
- a short, policy-defined expiry time.

MFA success is assurance evidence, not permission to alter the transfer. Any
change to the bound transfer intent requires a new risk decision and, when
required, a new challenge. A challenge response must be single-use and replay
protected.

## Failure And Availability Rules

- A duplicate normalized decision request returns the original decision.
- A reused request identifier with changed content is a conflict.
- An expired decision cannot authorize reservation or posting.
- An unavailable evaluator fails closed for flows whose policy requires an
  explicit risk decision. The transfer remains non-postable and receives a
  retryable operational outcome where appropriate.
- A timeout, retry, and duplicate event must preserve the same transfer and
  decision correlation identifiers.
- No service may infer `ALLOW` from a missing, malformed, or ambiguous result.

These rules prevent the security decision from becoming an accidental bypass
when the evaluator or an asynchronous dependency is unavailable.

## Audit And Observability

The security audit record should include decision ID, request ID, transfer ID,
policy version, outcome, reason codes, assurance level, issued/expiry times,
correlation ID, and actor or service identity. It must not include raw secrets,
OTP values, or unnecessary device fingerprints.

Operational telemetry should distinguish:

- decision latency and evaluator failures;
- counts by outcome and stable reason code;
- expired or replayed decisions;
- MFA challenge success, failure, and timeout;
- transfer requests rejected because the binding changed.

Logs and metrics must use correlation identifiers and must apply the platform's
sensitive-data redaction rules.

## Future Implementation Slices

The following work remains outside this documentation Task:

- Transaction Service risk-decision state and idempotent decision handling.
- MFA Service transfer-bound challenge lifecycle and assurance evidence.
- Auth Service session/authentication-assurance integration.
- Policy storage, approval, version promotion, and threshold governance.
- Gateway authorization for customer and admin routes.
- Event publication and saga coordination for reservation, ledger posting, and
  compensation in Sprint 3.

The contract is deliberately independent of whether the first evaluator is an
application module or a separately deployed service.
