# Ledger Reconciliation Event Checks

This document defines Sprint 3 design and implementation guidance for event-driven ledger reconciliation checks in the Digital Bank Java platform. It is documentation only. It does not implement runtime code, create topics, change schemas, or introduce a deployed reconciliation service.

Use this guidance with [`ledger-reconciliation.md`](ledger-reconciliation.md). That document defines the ledger reconciliation boundary, invariants, mismatch categories, and remediation order. This document narrows the Sprint 3 implementation target to event-driven checks across ledger posting outcomes, account reservations and projections, and transaction state.

## Scope

Sprint 3 reconciliation checks should observe events and persisted processing evidence from independently owned services:

| Area | Owning service | Expected Sprint 3 evidence |
| --- | --- | --- |
| Ledger posting outcomes | `ledger-service` | Posting request idempotency key, journal entry identifier, posting outcome, reversal reference when applicable |
| Account reservations and projections | `account-service` | Reservation identifier, account identifier, projected balance version, reservation lifecycle state, consumed ledger outcome |
| Transaction state | `transaction-service` | Transfer identifier, saga step, terminal or in-flight transfer state, correlated reservation and posting references |
| Event transport | Shared Kafka infrastructure | Topic, partition, offset, event identifier, correlation identifier, causation identifier, producer timestamp, consumer timestamp |
| Reliable processing | Service-local outbox and inbox storage | Publication status, consumption status, retry count, deduplication decision, quarantine reason |

These checks are operational controls. They classify consistency findings and provide evidence for replay, quarantine, or manual review. They must not rewrite ledger entries, mutate another service's database, or treat derived account projections as the financial source of truth.

## Correlation Model

Every event used by reconciliation should carry stable identifiers that let a checker connect the same business workflow across service boundaries:

- `eventId` uniquely identifies one published event.
- `eventType` identifies the contract, such as `LedgerPostingCompleted`.
- `eventVersion` identifies the schema version.
- `correlationId` follows the customer-visible transfer or command across services.
- `causationId` points to the command or event that caused the current event.
- `idempotencyKey` identifies the normalized business operation for replay protection.
- `transferId`, `reservationId`, `ledgerEntryId`, and account identifiers connect the event to owned service state.
- `occurredAt` records the producer's event time; consumer-side evidence records the observed processing time.

The future implementation should validate the presence and format of these fields before using an event as reconciliation evidence. Events missing mandatory correlation data should be quarantined because they cannot be safely matched or replayed.

## Ledger Posting Outcome Checks

Ledger posting outcome events should confirm that immutable posting behavior is visible to the rest of the platform.

Expected checks:

| Check | Valid condition | Finding when invalid |
| --- | --- | --- |
| Posting outcome has ledger evidence | `LedgerPostingCompleted` references one accepted balanced journal entry | Missing posting evidence |
| Posting failure does not imply balance mutation | `LedgerPostingFailed` has no accepted journal entry for the same posting attempt | State divergence |
| Idempotency key maps to one normalized posting | Replayed posting requests return the same ledger entry and outcome | Duplicate posting or idempotency conflict |
| Reversal references original entry | Reversal outcome points to an existing accepted entry and does not edit it | Invalid ledger invariant |
| Posting outcome references transfer context | Outcome includes the transfer or saga correlation expected by `transaction-service` | State divergence |

A completed posting event is not sufficient by itself. The checker should compare the event to durable `ledger-service` evidence, including the journal entry identifier and idempotency record. If an event was published but the ledger has no matching accepted posting, quarantine the event until the ledger evidence is understood.

## Account Projection And Reservation Checks

Account projections are derived operational views. Reconciliation should verify that they reflect accepted ledger outcomes within an agreed event-processing window.

Expected checks:

| Check | Valid condition | Finding when invalid |
| --- | --- | --- |
| Reservation correlates with transfer | Each reservation has one transfer correlation and expected account identifiers | Orphan reservation |
| Reservation reaches a valid lifecycle outcome | A terminal transfer leaves no stale open reservation | Orphan reservation or state divergence |
| Completed debit posting commits reservation | Account reservation is consumed exactly once after the matching ledger completion | Stale projection or duplicate consumption |
| Failed posting releases reservation | Account reservation is released after a correlated posting failure | State divergence |
| Credit account projection is updated | Credit-side account projection reflects the completed ledger posting | Stale projection |
| Projection update is versioned | Balance projection changes carry an optimistic version or equivalent monotonic evidence | State divergence |

The checker should compare account evidence against ledger outcomes by `correlationId`, `reservationId`, `ledgerEntryId`, and idempotency key. It should tolerate short in-flight windows, but it should classify stale projections when a completed ledger outcome remains unapplied beyond the Sprint 3 operational threshold.

## Transaction State Checks

`transaction-service` owns the transfer saga and terminal transfer state. Event-driven reconciliation should verify that transaction state agrees with account reservation and ledger outcome evidence.

Expected checks:

| Check | Valid condition | Finding when invalid |
| --- | --- | --- |
| Pending transfer has active or attempted reservation | A non-terminal transfer can be explained by an in-flight reservation or posting step | State divergence |
| Completed transfer has completed posting | Terminal `COMPLETED` state references a completed ledger posting | Missing posting |
| Failed transfer has no accepted final posting | Terminal `FAILED` state either has no accepted posting or has a documented reversal path | State divergence |
| Transfer state consumes ledger outcome once | The saga records one terminal decision for each correlated posting outcome | Duplicate consumption |
| Terminal state is monotonic | A terminal transfer does not return to an in-flight state after later events | State divergence |

The checker should not make `ledger-service` the saga owner. Its role is to report disagreement between transaction state and ledger evidence so `transaction-service` can replay a safe step, quarantine the workflow, or route it to manual review.

## Idempotent Consumption Checks

Every event consumer that changes owned state should record inbox evidence before or atomically with the owned state change. Reconciliation should use that evidence to detect replay safety and duplicate effects.

Expected checks:

- The same `eventId` is processed at most once by a consumer.
- A repeated event with the same `eventId` and payload is classified as an idempotent replay, not a new business effect.
- A repeated idempotency key with different normalized content is rejected or quarantined as a conflict.
- Consumer state changes can be traced to an inbox row, topic, partition, offset, and event contract version.
- Retry counts and failure reasons are preserved for events that cannot be consumed immediately.
- Consumers can restart and resume from durable evidence without applying a second financial effect.

The implementation should distinguish duplicate delivery from duplicate business effect. Kafka may deliver the same event more than once; the platform must not apply the same reservation, posting outcome, projection update, or transfer state transition more than once.

## Duplicate, Missing, And Out-Of-Order Event Checks

Event-driven reconciliation should classify transport and ordering problems separately from financial invariant failures.

| Event condition | Detection evidence | Expected handling |
| --- | --- | --- |
| Duplicate event | Same `eventId` or same idempotency key and normalized payload observed more than once | Deduplicate through inbox and record idempotent replay |
| Duplicate business effect | Same workflow step causes more than one reservation, posting, projection update, or terminal transfer decision | Quarantine and classify as duplicate posting or duplicate consumption |
| Missing event | Owned state exists but no corresponding outbox publication or consumed inbox evidence exists after the threshold | Replay from outbox when safe; otherwise manual review |
| Out-of-order event | Consumer observes a later lifecycle event before required predecessor evidence | Hold or quarantine until predecessor arrives or threshold expires |
| Conflicting event | Same identifier appears with incompatible payload, amount, account, currency, or terminal state | Quarantine immediately |
| Unknown event version | Event contract version is unsupported by the consumer | Quarantine and alert contract owner |

Out-of-order handling should be conservative. A later event may be valid once its predecessor arrives, but a financial side effect must not be applied without the prerequisite state and idempotency evidence.

## Quarantine, Replay, And Manual Review

Sprint 3 implementation should separate automatically retryable failures from ambiguous financial divergence.

Replay is appropriate when:

- the original command or outbox event is present and its normalized content is unchanged;
- the target consumer has no durable successful inbox record for that effect;
- the operation is protected by the same idempotency key;
- retry limits and backoff rules permit another attempt;
- the replay cannot create a second accepted posting, reservation, projection update, or terminal saga decision.

Quarantine is required when:

- correlation identifiers are missing or malformed;
- the same idempotency key is reused for different content;
- ledger, account, and transaction evidence conflict in a way that cannot be explained by an in-flight window;
- duplicate financial effects may already exist;
- an unsupported event version reaches a consumer;
- security or authorization context is missing for an event that requires it.

Manual review is required when an item remains quarantined after automated evidence collection, when a compensating reversal may be needed, or when operational staff must decide whether an external customer-visible state needs correction. Manual review records the decision, reviewer, evidence, and follow-up action. It does not edit immutable ledger history.

## Observability Boundaries

Sprint 3 should emit enough operational evidence for later Sprint 6 dashboards and alerting without implementing the full reporting layer.

Expected telemetry:

- structured logs with `correlationId`, `eventId`, `transferId`, `reservationId`, `ledgerEntryId`, topic, partition, offset, event type, and result;
- counters for consumed, deduplicated, replayed, quarantined, failed, and manually reviewed events;
- gauges or queryable counts for open quarantines and stale projections by age bucket;
- traces that connect transaction saga steps, account reservation processing, ledger posting, and event consumption;
- audit records for replay, quarantine release, manual review, and compensating reversal decisions.

Logs and metrics should be operational evidence, not a substitute for service-owned persistence. Sensitive fields, account numbers, customer identifiers, and monetary details should follow platform logging and security rules before being emitted.

## Security Boundaries

Event-driven reconciliation crosses service boundaries and must preserve ownership and least privilege.

Rules:

- A reconciliation checker may read published events, outbox/inbox metadata, and explicitly exposed service APIs intended for operational checks.
- It must not directly query or mutate another service's private database unless a future issue explicitly creates that operational access pattern.
- Replay permissions should be restricted to trusted operators or service accounts and audited separately from normal customer traffic.
- Quarantine release and manual review actions require authenticated administrative access.
- Event payloads should not carry secrets, credentials, or unnecessary personally identifiable information.
- Cross-service calls used for evidence collection should use service-to-service authentication once that platform capability exists.

These boundaries keep reconciliation as an operational control layer. They do not move ledger authority away from `ledger-service`, reservation and projection ownership away from `account-service`, or saga ownership away from `transaction-service`.

## Sprint 3 Implementation Guidance

The first implementation slice should focus on durable, queryable evidence and deterministic classification:

1. Define AsyncAPI event contracts for ledger posting outcomes, account reservation outcomes, and transfer state transitions.
2. Add outbox publication evidence in producers and inbox consumption evidence in consumers before relying on event-driven reconciliation findings.
3. Implement idempotent handlers for account projection updates and transaction state transitions.
4. Add reconciliation classifiers for missing posting, duplicate posting, stale projection, orphan reservation, state divergence, and invalid ledger invariant findings.
5. Add quarantine and replay commands only for cases that can prove replay safety through idempotency and durable evidence.
6. Leave scheduled reports, dashboards, alert thresholds, and runbooks to Sprint 6.

This document is the Sprint 3 design contract for those future implementation issues. A PR that changes only this file should be reviewed as documentation guidance, not as delivered runtime reconciliation behavior.
