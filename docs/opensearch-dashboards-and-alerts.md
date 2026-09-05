# OpenSearch Dashboards And Operational Alerts

## Design Status

| Field | Decision |
| --- | --- |
| Status | Proposed design; deployment is follow-on infrastructure work |
| Scope | Operational dashboards and alert definitions for `sit`, `uat`, and `prod` |
| Parent story | [#91 - Implement centralized logging with OpenSearch](https://github.com/digital-bank-java/.github/issues/91) |
| Task | [#95 - Create OpenSearch dashboards and operational alerts](https://github.com/digital-bank-java/.github/issues/95) |
| Related contracts | [#92 - Structured logging and redaction](https://github.com/digital-bank-java/.github/issues/92), [#96 - OpenSearch security and lifecycle](https://github.com/digital-bank-java/.github/issues/96), [#97 - Amazon OpenSearch UAT/PROD architecture](https://github.com/digital-bank-java/.github/issues/97) |

This document defines what operators should be able to see and which conditions
should create an operational response. It does not claim that the dashboards,
monitors, notification destinations, or runbooks are deployed. Those artifacts
will be provisioned and verified by the infrastructure work for each environment.

## Purpose And Boundaries

OpenSearch Dashboards is an internal operations tool for investigating service
availability, errors, latency, deployments, asynchronous workflows, and log
pipeline health. It is not a customer-facing product and it is not an
authoritative store for:

- ledger entries, balances, reservations, or transaction state;
- customer, account, payment, or identity records;
- authentication evidence or immutable security audit records; or
- service-level metrics that require a dedicated metrics system.

Dashboards may show counts and masked correlation references that help an
operator locate a workflow. They must not display raw financial or customer
data. A dashboard outage must not block an HTTP request, message consumer,
ledger posting, or transfer workflow.

## Common Data Sources

Every saved search, visualization, and monitor must identify its environment
and use the approved data source for that signal.

| Data source | Examples | Use | Owner |
| --- | --- | --- | --- |
| Application operational indexes | `logs-application-{environment}-*` | Service errors, request outcomes, latency fields, workflow correlation | Service teams and platform/observability |
| Quarantine indexes | `logs-quarantine-{environment}-*` | Malformed, rejected, or redaction-failed events | Platform/observability with security approval |
| Collector metrics | Fluent Bit health, output failures, retries, queue depth, buffer utilization | Collection and delivery health | Platform/observability |
| OpenSearch and AWS metrics | Cluster status, storage, JVM pressure, indexing/search latency, throttling | Search platform capacity and availability | Platform/observability |
| Separate security audit sink | Authentication, authorization, role, export, and policy-change evidence | Security investigation and access review | Security and audit |

Application indexes use the stable fields in the structured logging contract:
`timestamp`, `level`, `service`, `environment`, `correlation_id`, `trace_id`,
`span_id`, `event_name`, `route`, `status_code`, and `duration_ms`. A dashboard
must not depend on an unreviewed parser-specific field or an arbitrary request
payload.

Use an environment-specific data view or index pattern. The saved object may
use a placeholder such as `${environment}`, but the deployed object must bind
it to exactly one environment. A SIT operator must not be able to select PROD
indexes with the same role or saved object.

## Dashboard Catalog

These are the initial dashboard products. They are intentionally small enough
to support a useful SIT deployment and can be promoted to UAT and PROD without
changing the application logging contract.

### 1. Service Health And Traffic

**Audience:** service owners and SRE/on-call.

**Data:** application operational indexes and the approved metrics source.

**Panels:**

- request outcome count by `service` and `status_code` over time;
- error-rate percentage by service, with a minimum-event-count indicator;
- request duration percentiles by service and `route`;
- active service freshness, showing time since the last accepted event;
- top route templates by request count, without query strings;
- deployment and pod restart events from Kubernetes metadata when available.

The dashboard must show the selected `environment` prominently and default to
the last 30 minutes. It must provide links to a correlation/trace view without
putting raw request or response bodies into the panel.

### 2. Error Investigation

**Audience:** service owners, SRE/on-call, and approved support staff.

**Data:** application operational indexes.

**Panels:**

- `WARN` and `ERROR` count by service and `event_name`;
- status-code distribution for `4xx` and `5xx` responses;
- exception type count with bounded, redacted messages;
- error trend by route template and deployment version;
- a saved search ordered by `timestamp` for a selected `trace_id` or
  `correlation_id`.

Free-text exception messages are displayed only when the emitting service and
collector have applied the redaction contract. Saved searches must not export
unrestricted results by default.

### 3. Workflow Correlation

**Audience:** SRE/on-call and service teams troubleshooting a business flow.

**Data:** application operational indexes, filtered by an operator-provided
synthetic or approved correlation identifier.

**Panels:**

- chronological events across services for one `correlation_id`;
- trace span timing by `trace_id` and `span_id` when tracing is available;
- workflow outcome counts by `event_name`;
- missing-event or stale-workflow counts emitted by the reconciliation and
  workflow components.

This dashboard shows workflow metadata and outcome counts, not ledger amounts,
account balances, customer attributes, or complete transaction payloads.

### 4. Collection And Delivery Health

**Audience:** platform/observability owner.

**Data:** Fluent Bit or managed collector metrics, quarantine indexes, and
  destination health metrics.

**Panels:**

- collector instances available versus expected;
- parse failures, rejected events, quarantined events, and dropped events;
- output errors, retry count, delivery lag, and queue depth;
- memory and filesystem buffer utilization;
- accepted events by service and environment;
- oldest buffered event age.

The dashboard distinguishes an application emitting no events from a collector
that cannot deliver events. Maintenance windows and intentionally idle services
must be represented as explicit suppressions, not hidden by broad filters.

### 5. OpenSearch Platform Health

**Audience:** platform/observability owner and SRE/on-call.

**Data:** OpenSearch cluster metrics and AWS CloudWatch metrics in UAT/PROD.

**Panels:**

- cluster health and node reachability;
- JVM memory pressure, CPU, free storage, and EBS capacity signals;
- shard allocation, relocation, and unassigned shard count;
- indexing and search latency, rejected requests, and HTTP `4xx`/`5xx`;
- index growth, rollover age, and lifecycle-policy failures;
- snapshot age and last successful snapshot where snapshots are enabled.

The panel must link to the platform recovery runbook. It must not encourage an
operator to delete indexes manually or change retention outside change control.

### 6. Privacy And Security Control Health

**Audience:** security, audit, and platform/observability owner.

**Data:** quarantine metrics and the separate security audit sink. Operational
indexes may provide aggregate redaction counters but are not the audit source.

**Panels:**

- redaction and quarantine failures by service and reason code;
- attempted access outside the assigned environment;
- unauthorized dashboard, export, role, policy, or index actions;
- age of the last access-review and alert-destination verification evidence;
- alert delivery failures.

This dashboard contains safe metadata and counts. Detailed access evidence is
read from the restricted audit sink by the security/audit role.

## Alert Policy

The following are starting operational thresholds, not customer or financial
SLOs. Before UAT and PROD, the platform owner must tune them against measured
traffic, baseline noise, maintenance windows, and the approved paging policy.
Every monitor includes a time window, minimum sample count where relevant,
environment, owner, severity, and suppression rule.

| Signal and condition | Severity | Initial response | Owner |
| --- | --- | --- | --- |
| Any hosted environment has red cluster health, unreachable required nodes, or an unavailable OpenSearch endpoint for 5 minutes | Page | Start the OpenSearch recovery runbook; confirm application transactions remain independent | Platform/observability and SRE |
| PROD free storage is below 20%, JVM memory pressure is above 85% for 10 minutes, or unassigned shards persist for 5 minutes | Page | Protect capacity, investigate shard allocation and ingestion volume, and use the approved change path | Platform/observability and SRE |
| Collector output failures or authentication/TLS failures occur for 5 minutes, or the oldest buffer exceeds the bounded recovery window | Page | Check destination, identity, certificates, and buffer/backpressure; do not add application retries | Platform/observability |
| Collector buffer utilization exceeds 80% for 10 minutes or dropped events are non-zero | Page in PROD; ticket in SIT/UAT | Reduce delivery pressure, investigate loss, and record the visibility incident | Platform/observability |
| Malformed or redaction-rejected events exceed the agreed service baseline for 5 minutes | Page for security-sensitive redaction failures; ticket otherwise | Quarantine events, identify the emitting release, and block promotion if sensitive data may be exposed | Service owner, security, and platform |
| A required active service emits no accepted event for 10 minutes outside an approved maintenance window | Ticket; page when it coincides with service health failure | Check pod health, collector routing, deployment version, and service log level | Service owner and platform |
| A service `5xx` rate exceeds 5% for 5 minutes with at least 50 requests, or its latency p95 exceeds the approved baseline for 10 minutes | Page in PROD; ticket in SIT/UAT | Inspect the service and gateway correlation view; use the service rollback/runbook decision | Service owner and SRE |
| Unauthorized access, export, role, retention, or policy-change evidence is recorded | Page security | Preserve audit evidence and follow the security incident process | Security and audit |
| Indexing rejection, lifecycle failure, snapshot failure, or alert delivery failure persists for 10 minutes | Ticket; page for PROD data-loss risk | Repair the platform configuration through reviewed change control and verify recovery | Platform/observability |

An alert must not be based on a single transient log line when a rate,
duration, or persistence condition is available. Alerts derived from logs must
include a minimum event count or an explicit low-volume rule to avoid paging on
one synthetic request. The same condition must not page once per service and
again once per pod unless the notifications are intentionally deduplicated.

## Notification And Ownership Model

| Destination | Use | Required content | Not allowed |
| --- | --- | --- | --- |
| PROD on-call pager | Immediate availability, data-loss risk, security, or capacity response | Environment, service/platform component, condition, window, severity, runbook link, and correlation/trace reference when safe | Customer data, credentials, raw payloads, or an instruction to bypass change control |
| Platform operations queue | Non-paging collector, index, lifecycle, dashboard, or UAT/SIT issue | Query/monitor name, environment, owner, first/last observed time, and safe counters | Unrestricted search exports |
| Service team queue | Service-specific error-rate, latency, schema, or redaction issue | Service, route template, release identifier, safe event name, and trace/correlation reference | Request bodies, response bodies, or PII |
| Security/audit workflow | Access, export, redaction, IAM, or retention-control event | Audit event identifier, actor role, environment, action, and evidence location | Operational logs treated as the authoritative audit record |

Every alert has one accountable owner and one backup owner. Platform operations
owns collector, OpenSearch, dashboard, lifecycle, and alert-delivery failures.
Service teams own application fields, redaction, service health, and release
regressions. Security and audit own access violations, redaction policy, and
retention approvals. SRE/on-call owns incident coordination and escalation.

## Privacy, Redaction, And Access Controls

- Redaction happens in the emitting service before `stdout`/`stderr`; collector
  filtering is defense in depth, as defined by the structured logging contract.
- Dashboard objects never include passwords, tokens, OTPs, PINs, payment-card
  values, full account or IBAN numbers, identity documents, customer PII,
  balances, or raw transaction records.
- Use masked or non-reversible references only when a workflow investigation
  needs correlation. Correlation and trace identifiers must not encode business
  data.
- Dashboard roles are environment-scoped. `log-reader` can query assigned
  operational indexes; only `observability-admin` can change saved objects,
  monitors, or destinations. No application identity receives query or admin
  access.
- Exports, searches, dashboard changes, alert changes, and failed
  authorization attempts are recorded in the separate security audit sink.
- SIT and UAT dashboards use synthetic data. Screenshots, saved searches, and
  issue comments must not contain production records or unmasked identifiers.

These rules apply equally to OpenSearch Dashboards, its API, exported saved
objects, alert notifications, and runbook examples.

## Environment Portability

| Concern | SIT | UAT | PROD |
| --- | --- | --- | --- |
| Workloads | Docker Desktop Kubernetes, `digital-bank-sit` | AWS EKS | AWS EKS |
| Collection | `infra-sit` Fluent Bit or approved local collector | Platform-owned EKS collector | Highly available platform-owned EKS collector |
| Destination | Local OpenSearch deployment in the tooling boundary | Dedicated private Amazon OpenSearch Service domain | Dedicated private Amazon OpenSearch Service domain, isolated from UAT |
| Metrics | Local collector/OpenSearch metrics | CloudWatch and platform metrics | CloudWatch and platform metrics |
| Access | Temporary local operator access | Private operator path and UAT groups | Private operator path, named on-call, security, and approved support groups |
| Data | Synthetic only | Synthetic or approved masked acceptance data | Redacted production operational data |

The dashboard field names, panel meanings, alert conditions, severity model,
and runbook intent remain the same across environments. Only the data-view
binding, metric source, notification destination, thresholds, retention, and
access groups vary by environment. Saved objects and monitors are versioned
and promoted through reviewed infrastructure changes; they are not edited
manually in PROD.

SIT is the first validation target. UAT must prove that the same objects work
with Amazon OpenSearch and CloudWatch metrics before PROD promotion. AWS
networking, KMS, IAM, domain isolation, retention, and backup requirements
remain governed by the existing Amazon OpenSearch architecture and security
contracts.

## Rollout And Verification

This task is complete only when the implementation work provides evidence for
the following sequence:

1. Provision the SIT data views, role mappings, dashboards, monitors, and a
   safe local notification destination through `infra-sit`.
2. Submit synthetic success, `4xx`, `5xx`, exception, malformed, and
   redaction-rejected events. Confirm the expected panels and quarantine
   counters without exposing prohibited values.
3. Trigger one non-paging threshold and one paging threshold in SIT. Confirm
   deduplication, suppression, notification content, owner routing, and the
   recovery runbook.
4. Simulate collector and OpenSearch degradation. Confirm the alert fires,
   application requests remain independent, bounded buffers are visible, and
   recovery clears the alert.
5. Verify that `log-reader`, `observability-admin`, and security/audit roles
   can access only their intended data and actions.
6. Promote the versioned saved objects and monitor definitions to UAT, then
   repeat the checks with Amazon OpenSearch and CloudWatch data sources.
7. Complete PROD approval for thresholds, paging, privacy, retention, IAM,
   and recovery evidence before enabling production notifications.

## References

- [Task #91 - Implement centralized logging with OpenSearch](https://github.com/digital-bank-java/.github/issues/91)
- [Task #92 - Define structured logging and redaction contract](https://github.com/digital-bank-java/.github/issues/92)
- [Task #96 - Define OpenSearch security and lifecycle contract](https://github.com/digital-bank-java/.github/issues/96)
- [Task #97 - Define Amazon OpenSearch UAT and PROD architecture](https://github.com/digital-bank-java/.github/issues/97)
- [Platform conventions](platform-conventions.md)
