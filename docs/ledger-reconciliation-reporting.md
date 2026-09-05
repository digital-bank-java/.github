# Ledger Reconciliation Reporting

This document defines scheduled ledger reconciliation reporting for the Digital Bank Java platform. It is design and operational guidance only. It does not describe implemented runtime code, deployed jobs, database tables, alert rules, dashboards, or access-control policies that already exist.

The intent is to give Sprint 6 reporting and alerting work a clear target while preserving the Sprint 3 boundary for event-driven consistency checks.

## Scope And Boundary

Scheduled reconciliation reporting is an operational control over independently owned service views:

- `ledger-service` remains the financial posting authority for balanced, append-only journal entries and reversals.
- `account-service` owns account projections, available-balance state, and future reservation lifecycle state.
- `transaction-service` owns transfer state and saga orchestration.
- The future reconciliation capability records report runs, findings, acknowledgements, evidence, and operator decisions.

Reports must compare the views and surface exceptions. They must not silently repair financial history, update ledger entries, delete evidence, or become a second ledger.

The delivery boundary is:

- **Sprint 3 event-driven checks:** near-real-time consistency checks, outbox/inbox correlation, idempotent event consumption, replay eligibility, and transfer-state reconciliation signals.
- **Sprint 6 reporting and alerting:** scheduled reports, freshness windows, exception aging, severity thresholds, alert routing, dashboard views, manual review queues, audit exports, access-control policy, and operational runbooks.

Sprint 6 reporting consumes Sprint 3 signals when available, but it must still be able to run scheduled comparisons from durable service state.

## Scheduled Reports

### Intraday Exception Report

Purpose: identify active reconciliation findings that exceed freshness windows during the business day.

Suggested cadence: every 15 minutes in `prod`, every 30 minutes in `uat`, and on demand in `sit`.

Primary outputs:

- open findings grouped by severity, category, owner service, and age;
- newly detected findings since the previous successful run;
- findings that crossed an alert threshold;
- replay-eligible findings separated from findings requiring manual review.

### End-Of-Day Control Report

Purpose: provide a daily control record for ledger, account projection, reservation, and transfer consistency.

Suggested cadence: once after the close-of-day processing window for each supported business date and currency.

Primary outputs:

- ledger debit and credit control totals by business date, currency, and posting type;
- count and amount totals for accepted postings, reversals, failed postings, open reservations, completed transfers, failed transfers, and stale projections;
- unresolved critical and high findings at day close;
- report run identifier, source snapshots, freshness cutoffs, and operator acknowledgement status.

### Open Item Aging Report

Purpose: show unresolved reconciliation findings that remain open across reporting periods.

Suggested cadence: daily in `prod` and `uat`.

Primary outputs:

- open findings grouped by age bucket: under 1 hour, 1-4 hours, 4-24 hours, 1-3 days, over 3 days;
- findings awaiting automatic replay, operational acknowledgement, financial review, or compensating action;
- owner, last action, next review deadline, and escalation state.

### Ledger Invariant Breach Report

Purpose: isolate findings that suggest a ledger integrity problem rather than normal eventual consistency.

Suggested cadence: every scheduled run plus immediate inclusion when detected by an event-driven check.

Primary outputs:

- unbalanced entries, invalid reversals, invalid idempotency conflicts, or evidence of mutation after acceptance;
- affected entry identifiers, currencies, amounts, correlation identifiers, and detection source;
- quarantine status and critical incident reference when opened.

### Manual Review Queue Report

Purpose: give authorized reviewers a controlled worklist for findings that cannot be closed through automatic replay or routine operational acknowledgement.

Suggested cadence: continuously refreshed by dashboards in Sprint 6, with a daily export for audit review.

Primary outputs:

- findings requiring review, sorted by severity and deadline;
- required evidence checklist;
- available decisions and decision authority;
- reviewer identity, decision time, rationale, and linked incident or change record.

### Reconciliation Operations Audit Report

Purpose: provide a durable record of report execution, alerting, access, acknowledgements, and closure activity.

Suggested cadence: daily summary with monthly export.

Primary outputs:

- successful, failed, skipped, and manually rerun report executions;
- alerts emitted, suppressed, escalated, and acknowledged;
- user access to restricted reconciliation views and exports;
- finding lifecycle events from first seen through closure.

## Report Inputs

Scheduled reports should read from durable sources and record the source position used for each run. Input contracts should prefer stable identifiers over display names.

Required input groups:

| Input group | Examples | Source owner |
| --- | --- | --- |
| Ledger postings | journal entry id, line ids, debit and credit amounts, currency, business date, posting type, reversal link, idempotency key | `ledger-service` |
| Account projections | account id, projected balance, available balance, projection version, last applied ledger event, last update time | `account-service` |
| Reservations | reservation id, account id, amount, currency, transfer id, status, expiry time, terminal outcome | `account-service` |
| Transfer state | transfer id, source account, destination account, amount, currency, saga status, current step, terminal state time | `transaction-service` |
| Event state | outbox message id, inbox message id, event type, aggregate id, correlation id, publication time, consumption time, retry count | service-owned outbox/inbox stores |
| Reconciliation history | prior run id, prior findings, acknowledgements, replay attempts, manual decisions, alert state | future reconciliation capability |

Reports must capture the query cutoff time, source freshness time, run start time, run end time, environment, and business date scope. When a source is unavailable or stale, the report should emit a run-level warning or failure rather than presenting incomplete results as clean.

## Report Outputs

Each scheduled report run should produce:

- a stable report run id;
- report type, environment, schedule trigger, and operator trigger when manually run;
- source systems queried and their observed freshness;
- business date, currency, and account or transfer scope when applicable;
- total records examined and totals compared;
- findings created, updated, reopened, suppressed, or closed;
- severity distribution and alert actions;
- links to evidence snapshots or immutable source references;
- machine-readable output for dashboards and alerts;
- human-readable output for operations and audit review.

Finding records should include:

- category from `docs/ledger-reconciliation.md`;
- severity;
- first-seen time and last-seen time;
- owner service and current operational owner;
- correlation identifiers, idempotency keys, account ids, transfer ids, entry ids, and event ids;
- expected state, observed state, and freshness window used;
- replay eligibility and retry limit state;
- manual review requirement and reviewer decision when applicable.

## Freshness Windows

Freshness windows define how long normal eventual consistency may explain a difference before the scheduled report classifies it as an exception. The initial windows below are guidance for Sprint 6 design and must be tuned with production evidence.

| Condition | Freshness window | Initial handling |
| --- | --- | --- |
| Ledger posting event not consumed by `account-service` | 5 minutes | Track as pending until the window expires, then classify as stale projection. |
| Ledger posting event not consumed by `transaction-service` | 5 minutes | Track as pending until the window expires, then classify as state divergence. |
| Reservation remains open after transfer terminal state | 10 minutes | Alert if not released, committed, or explicitly extended. |
| Outbox event unpublished after local transaction commit | 2 minutes | Treat as event-pipeline operational risk. |
| Inbox retry backlog for financial events | 15 minutes | Alert operations before business state divergence ages further. |
| Missing posting for completed transfer | 0 minutes after terminal completion unless a known posting request is in flight | Classify as high or critical depending on financial exposure. |
| Invalid ledger invariant | 0 minutes | Classify as critical immediately. |
| Source system unavailable during scheduled run | one missed run | Mark the run degraded; alert if repeated or if critical reports cannot complete. |

Event-driven checks may detect these conditions earlier. Scheduled reports are the durable control that proves whether the condition still exists after the freshness window.

## Severity Classification

Severity must reflect financial integrity, customer impact, operational recoverability, and evidence confidence.

| Severity | Definition | Examples | Required response |
| --- | --- | --- | --- |
| Critical | Potential ledger integrity breach, duplicated financial effect, unreconciled customer-impacting amount, or control failure that blocks trustworthy reporting | invalid ledger invariant, duplicate posting, missing posting for completed transfer with funds movement, unauthorized manual closure | Immediate alert to on-call engineering and finance operations; open incident; quarantine affected workflow when possible. |
| High | Financial workflow divergence outside freshness windows with clear customer or accounting risk, but ledger integrity is not known to be broken | stale account projection over threshold, orphan reservation after terminal transfer, failed replay for a valid event | Alert service owner and finance operations; review within the same business day. |
| Medium | Reconciliation difference outside freshness windows with bounded exposure or likely operational retry path | delayed inbox consumption, unpublished outbox event, retryable missing projection update | Route to operations queue; resolve or escalate before the next end-of-day report. |
| Low | Informational or early warning condition that does not yet exceed a materiality or customer-impact threshold | one degraded non-production report run, short-lived backlog below alert threshold | Track in dashboard; no page unless repeated. |

Severity may only be lowered through an auditable review decision. Suppression rules must be time-bounded, scoped to known causes, and visible in the audit report.

## Alert Routing

Alert routing should be explicit and based on severity, category, environment, and ownership.

| Alert target | Receives |
| --- | --- |
| Ledger service owner | invalid ledger invariants, duplicate postings, reversal errors, ledger source unavailability |
| Account service owner | stale projections, reservation lifecycle exceptions, account projection source unavailability |
| Transaction service owner | transfer-state divergence, missing posting request correlation, saga terminal-state mismatch |
| Platform operations | scheduler failures, report execution failures, event-pipeline backlog, degraded source freshness |
| Finance operations | high or critical financial exposure, end-of-day unresolved items, manual review queue deadlines |
| Security or compliance reviewer | unauthorized access attempts, privileged export activity, manual closure policy violations |

Expected routing behavior:

- critical findings page the active engineering on-call and notify finance operations immediately;
- high findings notify the owner channel and finance operations during business hours, with paging when unresolved near end-of-day;
- medium findings create or update operations queue items and appear on dashboards;
- low findings remain dashboard-visible and are included in daily audit summaries.

Alerts must include the report run id, finding id, severity, category, owner, first-seen time, current age, correlation identifiers, and a link to the evidence view. Alerts must not include secrets or unnecessary customer personal data.

## Audit Retention

Retention must support operational troubleshooting, financial audit needs, and privacy constraints. These windows are guidance until a formal compliance policy is adopted.

| Data | Minimum retention guidance |
| --- | --- |
| Report run metadata and control totals | 7 years |
| Critical and high finding evidence | 7 years |
| Medium and low finding lifecycle history | 3 years |
| Manual review decisions and approvals | 7 years |
| Alert delivery and acknowledgement history | 3 years |
| Access logs for restricted reconciliation views and exports | 3 years |
| Non-production dry-run outputs | 90 days unless linked to a production incident or audit exercise |

Retention must preserve evidence references even when an operational finding is closed. Closing a finding must never delete ledger audit history or remove the record that the finding existed.

## Access Control

Reconciliation reporting views expose financial control data and operational evidence. Sprint 6 implementation should use least-privilege roles.

Suggested roles:

- **Viewer:** can see summary dashboards and non-sensitive finding metadata.
- **Operations responder:** can acknowledge operational findings, trigger approved reruns, and attach operational notes.
- **Finance reviewer:** can review financial exposure, approve manual closure, and request compensating action.
- **Engineering owner:** can inspect technical evidence for owned services and mark retry or quarantine decisions within policy.
- **Audit reviewer:** can access historical reports, lifecycle evidence, manual decisions, and access logs.
- **Administrator:** can manage schedules, routing policy, role membership, and suppression rules through controlled change management.

Access-control requirements:

- restrict customer-identifying data to roles with a demonstrated need;
- record access to detailed evidence, exports, and manual decision screens;
- require strong authentication for privileged roles;
- separate the ability to configure suppression rules from the ability to approve financial closure;
- prevent one user from both creating and approving a manual financial closure when dual control is required.

## Operational Workflow

Scheduled reconciliation operations should follow this lifecycle:

1. Scheduler starts a report run with a stable run id and records the source cutoff.
2. The report queries each source and records freshness, counts, and source positions.
3. The report compares source views using stable correlation identifiers.
4. Differences inside freshness windows remain pending and visible as in-flight control data.
5. Differences outside freshness windows become findings or update existing findings.
6. Severity, owner, and alert routing are calculated from policy.
7. Replay-eligible findings are marked for bounded automatic retry or operator-approved retry.
8. Findings that are ambiguous, duplicated, customer-impacting, or policy-restricted enter manual review.
9. Operators acknowledge, investigate, retry, quarantine, escalate, or close findings with evidence.
10. The report emits dashboard data, audit records, and alert events.

Manual reruns must be auditable. A rerun should state who triggered it, why it was triggered, what scope changed, and whether it replaced or supplemented the scheduled run.

## Manual Review Workflow

Manual review is required when automatic replay cannot safely resolve the finding or when financial exposure requires human decisioning.

Reviewers should verify:

- source records and correlation identifiers;
- ledger entry and reversal relationships;
- transfer and reservation lifecycle state;
- whether a retry is idempotent and still valid;
- customer or accounting exposure;
- whether quarantine, compensating reversal, or operational closure is appropriate.

Permitted outcomes:

- **Retry approved:** the original idempotent operation can be replayed through the approved event path.
- **Quarantine required:** automatic processing remains stopped for the affected workflow or account scope.
- **Compensating action required:** a new balanced reversal or corrective posting is requested through the normal ledger workflow.
- **False positive closed:** the evidence shows no remaining divergence.
- **Accepted risk closure:** an authorized finance or compliance reviewer records the reason an unresolved difference is accepted.

Manual review must not edit or delete ledger entries. Any financial correction must happen through a new auditable posting or reversal.

## Non-Production Use

In `sit`, reports may run on demand or on a reduced schedule to validate comparisons, evidence shape, and dashboard behavior. `sit` results are not audit records for production but should still avoid secrets and real customer data.

In `uat`, scheduled reports should rehearse production cadence, alert routing, access-control policy, and operational runbooks before Sprint 6 production rollout.

## Sprint 6 Acceptance Guidance

Future Sprint 6 implementation should be considered complete only when it can demonstrate:

- scheduled report execution for intraday, end-of-day, aging, invariant breach, manual review, and audit views;
- explicit report inputs, outputs, source freshness, and run metadata;
- freshness windows that distinguish in-flight eventual consistency from exceptions;
- severity classification and alert routing by owner and environment;
- audit retention behavior for report runs, findings, decisions, alerts, and access logs;
- role-based access control for summaries, evidence, exports, and manual decisions;
- manual review workflow with evidence, dual-control-ready approvals, and immutable decision history;
- a clear separation from Sprint 3 event-driven checks and from ledger financial audit records.
