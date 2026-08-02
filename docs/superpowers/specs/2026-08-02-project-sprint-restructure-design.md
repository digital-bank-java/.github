# Digital Bank Java Platform Sprint Restructure

## Objective

Restructure GitHub Project #1 around outcome-based delivery sprints. A sprint completes when its defined outcome and exit criteria are met, rather than on a calendar date.

The migration preserves existing issues, pull requests, labels, native issue types, parent and sub-issue relationships, and completed-work history.

## Sprint Model

| Sprint | Outcome | Exit Criteria |
| --- | --- | --- |
| Sprint 0 - Platform Foundation and Local SIT | A reproducible local Kubernetes SIT platform exists. | Core services, shared PostgreSQL, Kafka, AKHQ, Config Server, API Gateway, Helm charts, CI, and operating documentation are demonstrably usable. |
| Sprint 1 - Customer and Account Foundation | Customer and account lifecycle foundations are usable through the gateway. | Customer and account APIs, persistence, validation, OpenAPI documentation, admin queries, and SIT deployment evidence are complete. |
| Sprint 2 - Ledger Foundation | A protected accounting-ledger foundation is established. | Ledger service bootstrap, persistence model, controlled posting interfaces, auditability design, and contract documentation are complete. |
| Sprint 3 - Internal Transfers and Event Consistency | Internal transfers execute through a reliable event-driven workflow. | Transaction orchestration, account reservations, ledger posting, Kafka contracts, idempotency, outbox/inbox handling, compensations, and end-to-end SIT evidence are complete. |
| Sprint 4 - Secure Customer Access and Step-Up Authorization | Customers can access protected banking capabilities safely. | Identity, authorization, gateway enforcement, service-to-service security, replay protection, and high-risk action controls are complete. |
| Sprint 5 - Payment Rails and Notifications | External payment workflows and customer notifications are operational. | Payment orchestration, payment-state events, notification delivery, retry and failure handling, and SIT evidence are complete. |
| Sprint 6 - Operational Resilience and Observability | The platform can be observed and operated safely. | Centralized logging, metrics, tracing, alerts, resilience policies, rate limits, backup/restore validation, and operational runbooks are complete. |
| Sprint 7 - AWS UAT and Production Readiness | The platform has a clear, validated route to AWS UAT and production. | EKS/RDS/MSK or equivalent managed-service mapping, secrets management, environment promotion, security hardening, deployment automation, and recovery procedures are complete. |

## Project Structure

### Project Fields

The GitHub Project is the cross-repository planning and delivery source of truth.

Required retained fields:

- `Status`: Backlog, Ready, In progress, In review, Done.
- `Sprint`: the authoritative cross-repository outcome-based sprint assignment.
- `Item Type`: native GitHub issue type mirrored into the project display.
- `Service`: owning service or platform component.
- `Priority`: delivery urgency.
- `Size`: implementation effort.
- `Parent issue`, `Sub-issues progress`, `Linked pull requests`, and `Repository`: GitHub-managed relationship evidence.

The migration will retire manual fields that duplicate this model, including `Phase`, `Slice`, and manual `Epic`, after verifying they are no longer required for filtering or reporting. `Delivery Priority` will be retired if it duplicates `Priority`.

### Issue Hierarchy

- Each sprint is represented by one cross-repository `EPIC:` issue in `digital-bank-java/.github`.
- Sprint epics contain `STORY:` issues that deliver a coherent user, business, or platform outcome.
- Stories contain small, independently reviewable `TASK:` issues in the owning repository.
- Defects are `BUG:` issues, labeled `bug`, assigned to the sprint in which they were discovered, and linked to the affected story where applicable.

### Sprint Completion

A sprint remains active until all mandatory stories meet their acceptance criteria. Completion requires:

1. Relevant implementation pull requests merged.
2. Required automated checks passing.
3. Updated developer and operational documentation.
4. A runnable SIT demonstration or evidence appropriate to the sprint.
5. Open defects either fixed or explicitly moved to a later sprint with documented risk acceptance.

## Migration Rules

1. Do not delete existing issues or pull requests merely because their title or current grouping is outdated.
2. Preserve native Issue Type for every issue, including closed work.
3. Preserve `Parent issue` and `Sub-issues progress`; do not replace GitHub relationships with duplicate text fields.
4. Convert Project draft issues to issues in `digital-bank-java/.github` before assigning a native Issue Type. Preserve their title, body, Project item identity, and field values during conversion.
5. Assign every item in Backlog, Ready, In progress, In review, and Done to exactly one sprint where it has a meaningful delivery role.
6. Assign exploratory or platform-wide governance work to Sprint 0 unless it is explicitly required by a later sprint.
7. Assign existing completed work retrospectively; its original completion date remains historical evidence.
8. Put all active work in `In progress` only when there is a real owner and active implementation. Assign active tasks to `ramioooz`.
9. Cross-repository PR descriptions must link related PRs and state merge order or lack of ordering dependency.

## Migration Sequence

1. Add the `Sprint` single-select Project field with Sprint 0 through Sprint 7 values.
2. Create the eight sprint epic issues in `digital-bank-java/.github` with objective and exit criteria.
3. Convert existing draft items to issues in `digital-bank-java/.github` and correct native Issue Type where missing.
4. Map existing work to the appropriate sprint while retaining parent/sub-issue relationships.
5. Move items to Backlog, Ready, In progress, In review, or Done based on real delivery state.
6. Verify filters by Sprint, Status, Item Type, Service, and Priority.
7. Retire duplicate Project fields only after the verified mapping is complete.

## Non-Goals

- Rewriting merged pull request history.
- Renaming every historic issue only for cosmetic consistency.
- Treating the sprint structure as a calendar commitment.
- Starting new domain implementation as part of the Project migration.
