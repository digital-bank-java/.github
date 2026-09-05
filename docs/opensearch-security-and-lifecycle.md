# OpenSearch Logging Security And Lifecycle Contract

This contract defines the security, access, retention, and audit boundaries for
centralized operational logs in `sit`, `uat`, and `prod`. It applies to service
logs collected from container `stdout` and `stderr`, Fluent Bit or an approved
managed collector, OpenSearch, and OpenSearch Dashboards.

The contract is a minimum control set. A service, environment, legal
requirement, or incident hold may impose stricter controls, but no implementation
may weaken these controls without a reviewed change to this document and its
supporting issue.

## Boundary And Non-Goals

OpenSearch is an operational diagnostics system. It is used to investigate
availability, errors, latency, deployments, and workflow correlation. It is not
the authoritative source for:

- Financial postings, balances, or ledger history.
- Customer identity or account records.
- Authentication, authorization, or security audit history.
- Retention obligations that belong to an immutable business or audit store.

The owning service writes financial and security audit records through their
separate append-only audit boundaries. An operational event may carry an
`audit_id`, `correlation_id`, or `trace_id` as a link, but an audit record must
never be reconstructed from OpenSearch. If OpenSearch is unavailable, a
required audit write follows the audit store's own durability and failure
policy; it is not replaced by an operational log.

## Data Handling Rules

### Redaction Before Ingestion

Redaction is owned by the emitting service and occurs before a value reaches
`stdout`, `stderr`, a collector buffer, or an OpenSearch client. The service
must omit a value when its sensitivity is unknown. Collector-side filtering is
defense in depth and must not be treated as permission for application code to
emit raw data.

The service logging tests must cover structured fields, nested objects,
exception messages and stack traces, request metadata, and free-form message
text. A log event is rejected by the collector when it cannot be parsed or
redacted with confidence; it must not be forwarded in raw form.

### Prohibited Indexed Values

The following values must never appear in an indexed event, including in a
message, exception, URL, header, request/response dump, tag, or field name:

- Passwords, passphrases, client secrets, private keys, database credentials,
  connection strings with credentials, signing material, and API keys.
- Access tokens, refresh tokens, session identifiers, cookies, authorization
  headers, bearer values, and one-time links.
- OTP values, PINs, CVV/CVC values, recovery codes, and challenge responses.
- Full card numbers, full bank account numbers, full IBANs, and raw identity
  documents.
- Customer PII such as national identifiers, dates of birth, names, addresses,
  email addresses, phone numbers, and free-form customer-provided text.
- Raw account balances, transaction details, or customer/account records.

Key names alone are not sufficient protection. Token-shaped and credential-
shaped values embedded in free-form strings must also be detected. Logging a
whole request or response object is prohibited unless its schema is explicitly
allow-listed and its redaction test is maintained by the service team.

### Approved References

Operational logs should omit sensitive values. When support or fraud
investigation requires correlation to an account or customer, the service may
emit an approved non-reversible reference or a masked value showing at most the
last four characters, such as `****1234`. The source value must not occur in
another field or attached exception. Passwords, secrets, tokens, OTPs, PINs,
and CVV/CVC values are always omitted and are never partially masked.

Stable operational fields may include service, environment, level, event name,
route template, status, duration, correlation ID, trace ID, and a separately
issued audit ID. Correlation and trace identifiers must not encode customer or
account data.

## Collection And Indexing Boundary

The application emits one structured JSON object per physical line. The
collector:

1. Reads both container streams and preserves the source stream as metadata.
2. Parses JSON and attaches non-sensitive Kubernetes metadata such as service,
   namespace, pod, container, and node where available.
3. Applies the denylist and value-pattern checks again before transport.
4. Routes only approved operational events to the environment's operational
   indexes and counts malformed, rejected, quarantined, and dropped events.
5. Uses environment-specific index templates and lifecycle policies so an
   operator cannot accidentally apply a production policy to SIT data.

Use environment-separated OpenSearch domains or an equivalent isolation
boundary in UAT and PROD. A shared domain is acceptable only when tenant,
index, network, and IAM controls prevent cross-environment reads and writes and
the security owner has approved the design. PROD must not share an index,
collector credential, or dashboard role with SIT.

## Access Control

Access is through the approved identity provider and role-based groups. Shared
accounts, embedded dashboard credentials, direct public endpoints, and
long-lived personal access keys are prohibited.

| Role | Allowed actions | Explicitly not allowed |
| --- | --- | --- |
| `log-ingest` | Write to the assigned environment's log alias; use the approved index template. | Search, delete, change mappings, change retention, or access another environment. |
| `log-reader` | Read and query assigned operational indexes in the assigned environment through Dashboards or the approved API. | Export unrestricted results, alter policies, administer users, or query another environment. |
| `security-audit-reader` | Read access-control, retention-change, and security-event evidence from the separate audit sink; read operational logs only when approved for an investigation. | Modify operational indexes or treat them as the authoritative audit ledger. |
| `observability-admin` | Manage collectors, templates, lifecycle policies, dashboards, alerts, and capacity for assigned environments. | Grant their own access, bypass redaction, or make unreviewed PROD retention changes. |
| `break-glass-admin` | Time-limited incident response actions approved by the security owner. | Normal operations, standing access, or unrecorded changes. |

Role grants use least privilege, environment-specific groups, and the smallest
index and action scope needed. PROD query access is limited to named on-call,
security, and approved support personnel. Customer-facing services and
application identities do not receive OpenSearch query or administrative
permissions.

All searches, exports, authentication events, role changes, index deletions,
policy changes, dashboard changes, and failed authorization attempts must be
sent to a separate security audit sink. That sink is controlled independently
of OpenSearch operational indexes. Query results containing masked references
must not be copied into tickets, chat, screenshots, or local files unless the
approved incident process requires it.

## Transport, Storage, Network, And Secrets

- **TLS in transit:** Collector-to-OpenSearch, Dashboard-to-OpenSearch, and
  administrative connections use TLS with certificate validation. Plain HTTP
  is not allowed in UAT or PROD. SIT may use local-only generated certificates
  when the local deployment supports them; it must not establish a public
  endpoint.
- **Encryption at rest:** UAT and PROD use the managed service encryption
  capability with an organization-controlled KMS key or its approved
  equivalent. Backups and any PROD operational-log archive use encryption and
  a separate access policy. SIT uses encrypted local storage where available
  and contains synthetic data only.
- **Network isolation:** SIT services are reachable only inside the local
  Kubernetes cluster and through temporary workstation port-forwarding. UAT
  and PROD endpoints are private to their VPC or equivalent network boundary,
  with security groups, network policies, and routing rules limited to approved
  collectors, dashboards, and operator paths. Do not expose OpenSearch or
  Dashboards directly to the public internet.
- **Secret management:** SIT credentials are generated for the local
  deployment and injected through Kubernetes Secrets or an equivalent local
  mechanism. UAT and PROD credentials, certificates, and KMS references are
  supplied at runtime through AWS Secrets Manager, Parameter Store, workload
  identity, or an approved equivalent. No secret, token, private endpoint, or
  certificate private key is committed to source, Helm values, examples, or
  dashboards. Prefer short-lived workload identity over static credentials and
  rotate any remaining credentials on a documented schedule and after
  suspected exposure.

## Environment Retention And Lifecycle

The following are default operational-log retention values. They do not define
financial or security audit retention and must be implemented by versioned
index lifecycle policies, rollover settings, and deletion/archive checks.

| Environment | Searchable retention | Archive / deletion behavior | Data rule |
| --- | --- | --- | --- |
| `sit` | 7 days | Delete automatically after 7 days; no backup is required for local troubleshooting. | Synthetic data only. |
| `uat` | 30 days | Delete automatically after 30 days unless an approved test incident hold exists; do not copy data to PROD. | Synthetic acceptance data unless a documented, approved masked test dataset is required. |
| `prod` | 90 days | Move expired operational events to an encrypted, access-controlled archive for up to 365 days, then delete; apply an approved incident or legal hold explicitly. | Production operational data is minimized and remains separate from audit records. |

The platform/observability owner owns the lifecycle policy and verifies that
rollover, archive, delete, and failed-action metrics work in each environment.
Retention must be the shortest period that meets operational, incident, legal,
and contractual needs. A hold suspends deletion only for the documented scope
and duration; it must name the approving owner and release condition. Extending
or shortening retention requires the change process below and a recorded
impact assessment.

## Ownership And Operating Responsibilities

| Responsibility | Accountable owner | Required evidence |
| --- | --- | --- |
| Event schema, field allow-list, and pre-ingestion redaction | Owning service team | Automated redaction tests for prohibited values, nested data, and exception paths; release evidence. |
| Fluent Bit or managed collector, buffering, filters, quarantine, and delivery metrics | Platform/observability owner | Versioned configuration, parser tests, dashboards for rejects/drops/backpressure, and environment rollout evidence. |
| OpenSearch domains, private networking, TLS, encryption, capacity, index templates, and lifecycle policies | Platform/observability owner with security approval | Infrastructure/configuration review, health checks, policy test, and recovery evidence. |
| IAM roles, identity groups, key policy, secret rotation, access review, and incident response | Security owner | Access approvals, quarterly entitlement review, key/credential rotation record, and security audit events. |
| Financial and security audit records | Owning service, ledger, and audit owners | Append-only audit-store schema, integrity controls, retention policy, and reconciliation or export evidence. |
| Synthetic-data approval and privacy classification | Data protection/security owner | Test-data approval, masking decision, and evidence that no production extract entered SIT or UAT. |

Each environment has a named primary and backup owner. The environment owner
must stop a rollout when redaction, TLS, network, IAM, or lifecycle evidence is
missing; the service must remain functional without OpenSearch availability.

## Failure And Recovery Behavior

OpenSearch is not on the synchronous transaction path. A collector or
OpenSearch outage must not block account access, transfer orchestration, ledger
posting, or other banking transactions. Services emit already-redacted events
to normal container streams and do not retry directly against OpenSearch.

During an outage, the collector uses bounded retries and a bounded,
environment-appropriate buffer. It exposes delivery lag, queue depth,
backpressure, rejected records, dropped records, and destination health as
metrics/alerts. A full buffer drops operational records according to the
documented policy and emits a safe aggregate alert; it must not spill raw
payloads to an uncontrolled disk or alternate external destination.

Redaction or parsing failure is fail closed: reject or quarantine the event,
record only safe metadata and a reason code, and alert the collector owner.
Quarantine access follows the `security-audit-reader` and break-glass rules.
Recovery verifies that new events are searchable, timestamps and environment
boundaries are correct, lifecycle policies are active, and no cross-environment
data was delivered. Recovery does not backfill from application payloads unless
the data passed the same redaction and access checks.

If the separate authoritative audit store is unavailable, the audit owner
applies its own durable-write and retry policy. An operational-log success
message cannot be used as evidence that a required financial or security audit
record was committed.

## Change Control And Review

The following actions require a tracked issue, reviewed pull request or
versioned infrastructure change, and a post-change verification record:

- Adding or changing indexed fields, allow-lists, redaction rules, or parser
  behavior.
- Changing an IAM role, group mapping, dashboard permission, network rule,
  certificate, key, secret source, or collector credential.
- Changing index templates, rollover settings, archive location, retention,
  deletion, or legal-hold behavior.

Every change record must identify the requester, approvers, environment,
ticket, old and new policy, reason, effective time, verification result, and
rollback or recovery action. PROD access or retention changes require platform,
security, and audit-owner approval. Console changes are prohibited except for
approved break-glass response; they must be captured in the security audit sink
and reconciled into version control within one business day.

Access entitlements are reviewed at least quarterly and after team or role
changes. Redaction tests run for every service release that changes logging,
request handling, or exception mapping. Lifecycle policies, restore/archive
behavior, failure alerts, and environment isolation are tested at least
annually and after a material platform change. The security and audit owners
review this contract at least annually and after a security incident, retention
requirement, or architecture change.

## Synthetic-Data Guidance

- SIT and UAT test fixtures use generated values that are unmistakably fake,
  such as `acct-sit-000001`, `customer-uat-000001`, and addresses under
  `example.invalid`. Use format-shaped fake secrets and tokens in redaction
  tests so the filters are exercised without using real credentials.
- Test fixtures must assert that credentials, tokens, OTPs, full account
  identifiers, and PII are absent from serialized events and collector output.
  Tests must cover nested objects and exception text, not only top-level keys.
- Do not copy production databases, customer exports, support tickets,
  screenshots, or log archives into SIT or UAT. If a masked dataset is
  unavoidable for an approved acceptance test, record the owner, masking
  method, fields, expiry, and deletion evidence before loading it.
- Saved searches, dashboards, alert examples, runbooks, issue comments, and
  pull requests contain synthetic values only. Production queries and exports
  follow the approved incident process and are never used as test fixtures.
- Production log samples used in development are generated from the schema,
  not copied from a production index.

## Acceptance Checklist

- [ ] Services redact before stdout/stderr and tests prove prohibited values do
      not reach the collector.
- [ ] Collector filtering, quarantine, malformed-event handling, and delivery
      metrics are enabled and tested.
- [ ] OpenSearch and Dashboards use private, TLS-protected connections with
      encryption at rest and runtime-injected credentials.
- [ ] `sit`, `uat`, and `prod` use the retention defaults and lifecycle evidence
      defined in this contract.
- [ ] Role grants are environment-scoped and least-privilege; access and
      policy changes are present in the separate security audit sink.
- [ ] Logging outage recovery is tested without making a banking transaction
      depend on OpenSearch.
- [ ] Financial and security audit records are written and retained through
      their authoritative append-only boundaries, not reconstructed from logs.
- [ ] SIT/UAT dashboards, fixtures, tests, and examples contain synthetic data
      only.
