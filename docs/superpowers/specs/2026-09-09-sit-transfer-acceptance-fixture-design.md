# SIT Transfer Acceptance Fixture Design

## Context

Sprint 3 implements the reservation-ledger transfer saga. Existing SIT service
workloads are healthy, but all existing accounts have a zero available balance
and the Auth fixture has no known usable password. This prevents an end-to-end
acceptance run without adding a public balance mutation endpoint or reading an
existing Kubernetes Secret.

This design provides a temporary, local-SIT-only acceptance fixture. It is not
a financial product capability, not an UAT or PROD deployment mechanism, and
not a replacement for a future cash-in or funding domain.

## Goals

- Provision deterministic synthetic customer and account records for local SIT.
- Establish one reconciled 1,000.0000 AED source balance through a balanced,
  immutable opening ledger entry.
- Provide a temporary Auth fixture without reading or modifying the shared
  signing-secret value.
- Exercise successful transfer completion, insufficient funds, ledger failure
  compensation, and duplicate terminal-event handling through the real Kafka
  flow.
- Leave no public direct-balance API, permanent credential, or enabled fault
  injection behind.

## Non-Goals

- UAT, PROD, AWS, customer-facing funding, cash-in, or payment functionality.
- Editing a live database manually from a workstation.
- Replaying DLQ records or fabricating event payloads.
- Retaining a fixture password or JWT in a repository, issue, PR, or log.

## Architecture

### Synthetic financial fixture

`infra-sit` will own a disabled-by-default Helm chart named
`transfer-acceptance-fixture`. When explicitly enabled, it creates a single
Kubernetes Job using the already deployed PostgreSQL image and existing
`postgres` Secret only by reference. The Job runs idempotent SQL against the
three service-owned logical databases:

- `customer_service`: a deterministic synthetic source customer and destination
  customer.
- `account_service`: active AED source and destination accounts. The source
  has `current_balance` and `available_balance` of `1000.0000`; destination
  starts at zero.
- `ledger_service`: one immutable, balanced opening ledger entry that debits a
  deterministic external SIT clearing account and credits the source account
  for `1000.0000` AED.

The SQL uses stable identifiers, unique request markers, and `ON CONFLICT`
semantics. A repeated execution converges to the same fixture state and never
updates or deletes an existing ledger record. The chart renders no Kubernetes
objects unless `fixtures.enabled=true` is explicitly supplied.

The opening entry is labeled as a SIT acceptance fixture in its description and
uses only synthetic identifiers. It is a controlled environment seed, not a
ledger posting flow exposed to customers.

### Temporary Auth fixture

The acceptance runner creates a short-lived Kubernetes Secret containing only:

- `fixture-username=transfer-orchestrator`
- a BCrypt hash of a generated random password

It temporarily changes only the two Auth fixture environment-variable Secret
references in the `auth-service` Deployment. It does not read, print, replace,
or rotate `AUTH_JWT_SECRET`. The runner waits for rollout, obtains a short-lived
JWT through the normal gateway login endpoint, and restores the original
references and deployment before it exits. A shell `trap` performs restoration
on success, failure, or interruption and removes the temporary Secret and local
token file.

### Deterministic ledger-failure acceptance case

Natural healthy transfers do not create a ledger posting failure after an
accepted reservation. `ledger-service` will therefore expose no new HTTP API
but will support a narrowly scoped, disabled-by-default acceptance fault switch
in its Kafka consumer:

- active only when the `sit` profile is active;
- enabled only by a temporary deployment environment override;
- matches exactly one supplied `postingRequestId`;
- records the existing governed `LedgerPostingFailed.v1` fact using the normal
  failure-decision and outbox path;
- rejects activation outside SIT.

The acceptance runner applies the override only for the one compensation case,
then restores the deployment and waits for rollout. This tests the real
reservation-release flow without fabricated Kafka events or a public test API.

### Duplicate terminal-event handling

The acceptance runner captures the Kafka partition and offset of a real
terminal fact, stops only the Transaction Service consumer deployment, resets
that consumer group to the one original offset, and restores the deployment.
Kafka then redelivers the original authoritative record. This proves consumer
idempotency without producing a forged event or replaying a DLQ record.

## Safety Boundaries

- The chart, runner, and fault switch are SIT-only and disabled by default.
- All credentials are generated at runtime and redacted from output.
- The runner validates the Kubernetes context is `docker-desktop` and namespace
  is `digital-bank-sit` before any mutation.
- It records non-sensitive evidence: correlation IDs, transfer IDs, HTTP
  statuses, final transfer status, reservation status, and ledger entry IDs.
- It restores temporary deployment overrides even if a scenario fails.
- The fixture remains a controlled development data seed. It must be removed or
  replaced by a real funding/cash-in workflow before UAT readiness.

## Acceptance Evidence

The runner must prove:

1. A valid transfer completes through reservation, ledger posting, and account
   projection.
2. An amount above the seeded balance fails through the normal reservation
   rejection path.
3. The temporary Ledger fault produces `LedgerPostingFailed.v1`, releases the
   reservation, and moves the transfer to its terminal failure state.
4. A Kafka redelivery of a real terminal event does not create another transfer
   effect or change the terminal status.

Evidence is written to a local, gitignored directory and summarized without
secrets in the supporting GitHub issue after successful SIT execution.
