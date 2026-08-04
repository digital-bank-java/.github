# Ledger Reconciliation Architecture

This document defines the reconciliation boundary for the Digital Bank Java platform. It is an operational control design, not a replacement for the immutable ledger or for the financial audit record.

## Scope And Ownership

The ledger is the financial posting authority. `ledger-service` owns balanced, append-only journal entries and their immutable relationships. `account-service` owns account and available-balance projections. `transaction-service` owns transfer state and saga orchestration.

Reconciliation compares those independently owned views and reports differences. It must not silently repair, update, or delete ledger entries.

The delivery boundary is intentionally split:

- **Sprint 2:** define ledger invariants, reconciliation categories, evidence, and remediation rules.
- **Sprint 3:** implement event-driven consistency checks, outbox/inbox correlation, and transfer-state reconciliation.
- **Sprint 6:** implement scheduled reporting, alerting, dashboards, and operational runbooks.

## Invariants

Every accepted ledger entry must satisfy these invariants:

1. Debit and credit lines are both present.
2. The sum of debit amounts equals the sum of credit amounts in the entry currency.
3. Amounts are positive and represented with the platform's monetary precision.
4. The entry and its lines are append-only after acceptance.
5. A reversal is a new balanced entry linked to the original; the original is never edited or deleted.
6. A posting request is idempotent: replaying the same normalized request returns the original entry, while reusing its key for different content is a conflict.

These are ledger correctness rules. They are distinct from the eventual-consistency rules used to project balances or advance a transfer.

## Comparisons

Reconciliation performs comparisons using stable identifiers and correlation metadata:

| Comparison | Expected relationship | Owner of the source of truth |
| --- | --- | --- |
| Ledger entry versus account projection | Account projection reflects the applicable completed postings and reservations | Ledger for postings; account service for projection state |
| Reservation versus transfer | Each reservation is correlated with one transfer workflow and has a valid lifecycle outcome | Transaction service for transfer state |
| Ledger posting versus transfer | A completed posting has a matching transfer step and expected idempotency key | Ledger for the posting; transaction service for workflow state |
| Reversal versus original entry | The reversal references an existing entry and swaps the debit/credit effect | Ledger service |

Comparisons must be repeatable and must record the observation time, source identifiers, expected state, observed state, and correlation identifiers used to reach the result.

## Mismatch Categories

The first implementation should classify, rather than conceal, mismatches:

- **Missing posting:** a transfer or completed workflow has no corresponding ledger entry.
- **Duplicate posting:** more than one financial posting represents the same idempotency key or workflow step.
- **Stale projection:** the account projection has not applied a known completed ledger outcome within the agreed operational window.
- **Orphan reservation:** a reservation has no valid transfer correlation or remains open after the workflow reached a terminal state.
- **State divergence:** transaction, reservation, ledger, and projection states disagree in a way that cannot be explained by an in-flight event.
- **Invalid ledger invariant:** an entry is unbalanced, mutable, or has an invalid reversal relationship. This is a critical integrity incident.

Each finding should include severity, first-seen time, last-seen time, correlation identifiers, and whether it is safe to retry automatically.

## Remediation Paths

Reconciliation is not permission to mutate financial history. Remediation follows this order:

1. **Replay:** retry a missing or failed event through the idempotent outbox/inbox path when the original operation is known to be valid.
2. **Compensating reversal:** create a new, balanced reversal posting when an accepted financial posting must be corrected. Never update the original entry.
3. **Quarantine:** stop automatic processing for ambiguous or potentially duplicated work and preserve the evidence for investigation.
4. **Alert:** notify the operational owner when severity or age exceeds the agreed threshold.
5. **Manual review:** require an authorized review for unresolved financial divergence. The review records the decision and evidence; it does not rewrite the ledger.

Automatic remediation must be bounded by idempotency keys, retry limits, optimistic-concurrency checks, and an auditable decision record.

## Operational Findings Versus Audit Records

Operational reconciliation findings are transient control data used to detect and resolve divergence. They may be acknowledged, retried, quarantined, or closed with an evidence trail.

The ledger and its append-only history are the immutable financial audit record. A reconciliation result must reference that history, never replace it. Audit records must not be deleted merely because an operational finding has been closed.

The future implementation should therefore keep separate storage and access concerns:

- ledger entries and reversals remain in `ledger-service` persistence;
- reconciliation findings and run metadata belong to the future reconciliation capability;
- operational dashboards and alerts belong to Sprint 6 observability work;
- financial audit access remains restricted and separately authorized.

## Planned Delivery

Sprint 3 will add event-driven checks around ledger posting outcomes, account reservations, and transfer state using reliable publication and consumption. Sprint 6 will add scheduled reconciliation reports, alert thresholds, dashboards, and incident runbooks. Until then, this document is the design contract for ledger-service implementation and review.
