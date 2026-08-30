# Amazon OpenSearch Architecture For UAT And PROD

## Architecture Decision Record

| Field | Decision |
| --- | --- |
| Status | Accepted for the UAT/PROD design; infrastructure rollout is follow-on work |
| Date | 2026-08-30 |
| Scope | Centralized operational logs for `uat` and `prod` |
| Parent story | [#91 - Implement centralized logging with OpenSearch](https://github.com/digital-bank-java/.github/issues/91) |
| Task | [#97 - Define Amazon OpenSearch architecture for UAT and PROD](https://github.com/digital-bank-java/.github/issues/97) |

### Context

The Digital Bank Java services already have a portable operational logging
boundary: one JSON event per physical line on `stdout` or `stderr`, with
service-side redaction and stable correlation and trace fields. Local SIT uses
the same boundary with Fluent Bit collecting Kubernetes container logs and
forwarding them to an OpenSearch sink. UAT and PROD need the same searchable
contract without making application pods depend on a logging network endpoint.

Operational logs are diagnostic data. They are not the authoritative source
for financial state, customer state, authorization evidence, or immutable
security audit history. The owning service and its approved audit store remain
responsible for those records.

### Decision

Use one Amazon OpenSearch Service domain per hosted environment, with UAT and
PROD separated by AWS account and VPC where the platform landing zone permits
it. Where separate accounts are temporarily unavailable, use separate VPCs,
domains, KMS keys, IAM roles, and access groups as a minimum boundary; a shared
domain with index prefixes is not an acceptable substitute for PROD isolation.

Run Fluent Bit as a platform-owned EKS node-level collector. It reads the
existing container `stdout` and `stderr` streams, parses JSON Lines, preserves
the logging contract, and sends records over a private HTTPS endpoint to the
matching environment's domain. Applications continue to log only to process
streams and receive no OpenSearch credentials, endpoint, or client library.

The collector uses bounded memory and filesystem buffering, retries transient
failures with a limit, and exposes dropped, malformed, quarantined, and
backlogged records as metrics. OpenSearch unavailability must reduce logging
visibility, not change the outcome or latency of a banking transaction.

The domain is private, encrypted, fine-grained, monitored through CloudWatch,
and managed as infrastructure. Daily time-based indexes use an Index State
Management (ISM) policy for rollover, tiering where justified, snapshots, and
deletion. Retention for operational logs is separate from the retention of
immutable financial and security audit records.

## Environment Mapping

The application-facing side of the topology is intentionally identical in all
environments:

```text
Spring Boot service
  -> one-line JSON event to stdout/stderr
  -> Kubernetes container log file
  -> Fluent Bit collector
  -> environment-specific OpenSearch endpoint
  -> environment-specific indexes and Dashboards
```

| Concern | SIT reference | UAT on AWS | PROD on AWS |
| --- | --- | --- | --- |
| Workloads | Local Docker Desktop Kubernetes, `digital-bank-sit` | EKS UAT cluster | EKS PROD cluster |
| Application output | `stdout`/`stderr`, JSON Lines | Same | Same |
| Collection | SIT Fluent Bit deployment/DaemonSet | Platform-owned Fluent Bit DaemonSet | Platform-owned highly available Fluent Bit DaemonSet |
| Destination | SIT OpenSearch sink from the centralized-logging story | Dedicated Amazon OpenSearch Service UAT domain | Dedicated Amazon OpenSearch Service PROD domain |
| Network path | Local cluster network | Private VPC endpoint; no public domain endpoint | Private VPC endpoint; no public domain endpoint |
| Access | SIT-only operator access | UAT operator and test support groups | Restricted production operations and security groups |
| Data | Synthetic or approved non-production data | Synthetic or approved UAT data | Production operational data, still subject to redaction |
| Retention baseline | Local policy and capacity constrained | 14 days searchable, delete after 30 days | 30 days hot, up to 90 days warm/cold, delete after 180 days |

The retention values are starting operational baselines, not financial or
regulatory retention requirements. Security, privacy, legal, and audit owners
must approve any production retention before rollout. If a longer retention is
required for an audit record, that record belongs in the owning immutable audit
store, not in this operational index.

### AWS Isolation Boundary

- Prefer one AWS account for UAT and a separate AWS account for PROD, with
  separate EKS clusters, VPCs, KMS keys, deployment roles, and operator groups.
- Create one OpenSearch Service domain in each environment. Do not place UAT
  and PROD indexes in the same domain, even with different index names or
  tenant mappings.
- Use environment-specific names and tags, for example
  `digital-bank-uat-logs` and `digital-bank-prod-logs`; keep account IDs,
  endpoints, and role ARNs as injected infrastructure values, never as service
  constants.
- Permit only the environment's collector role to write application indexes.
  Dashboards users receive read access through mapped roles, not write access.
- Keep the PROD domain and its snapshot repository inaccessible from UAT
  workloads. Any cross-account support access must be a time-bound, audited
  role assumption approved by security operations.

## Ingestion And Failure Isolation

### Fluent Bit Responsibilities

The collector configuration is owned by platform operations and is deployed
with the EKS platform layer. It must:

1. Read both container streams and preserve the source stream as metadata.
2. Parse one JSON object per line and attach Kubernetes metadata such as pod,
   namespace, container, node, and cluster without replacing application
   fields.
3. Apply the existing multiline fallback only to legacy or third-party output;
   service code remains responsible for one-line JSON events.
4. Route malformed records to a visible quarantine index or CloudWatch error
   path and increment a metric. It must never silently discard malformed data.
5. Use a bounded in-memory queue and bounded node-local filesystem buffer.
   Buffer limits must be included in node ephemeral-storage capacity planning.
6. Retry transient OpenSearch failures with exponential backoff and a maximum
   retry window. A permanently rejected record is counted and routed to the
   configured loss/quarantine path.
7. Expose collector health, output errors, retry counts, buffer utilization,
   parse failures, and dropped/quarantined record counts to CloudWatch or the
   platform metrics system.

Direct Fluent Bit to OpenSearch is the default because it retains the SIT
   collection contract, minimizes moving parts and latency, and does not
   require application changes. A managed ingestion path remains available for
   higher-volume workloads; see [Alternatives](#alternatives-and-tradeoffs).

### Transaction Independence

The following controls are mandatory:

- No Spring Boot service may use an OpenSearch client, network appender, or
  OpenSearch health check in a request, message-consumer, transaction, liveness,
  or readiness path.
- Services write only to normal container process streams. Collector retries,
  DNS failures, TLS failures, throttling, or domain outages must not be thrown
  back into a banking request or event handler.
- Apply log-level, event-size, and exception-size limits at the service and
  collector boundaries. Prefer dropping low-value `DEBUG` events when a
  bounded queue is saturated; preserve `WARN`/`ERROR` counts and alert on the
  loss.
- Configure node-level log rotation and storage quotas so a logging outage
  cannot exhaust the node filesystem needed by application pods or databases.
- Keep a short local buffer for transient outages, then fail visibly and
  boundedly. Do not create an unbounded retry queue that can consume node
  resources after recovery.
- Keep application availability and transaction SLO alarms independent from
  the OpenSearch availability alarm. An OpenSearch outage is an observability
  incident and must not page as a transaction failure unless a separate
  application symptom exists.

| Failure | Expected application behavior | Collector/platform response |
| --- | --- | --- |
| OpenSearch endpoint unavailable | Transactions and message handlers continue | Retry within bounded buffer; alert; count backlog and drops |
| TLS or IAM rejection | Transactions continue; no credential fallback | Alert on output auth/TLS errors; quarantine rejected records; rotate configuration through platform controls |
| Domain throttling or red status | Transactions continue | Backoff, rate-limit output, alert on rejection and cluster health |
| Malformed application event | Transaction behavior is unchanged | Quarantine the record, count it, alert when threshold is exceeded |
| Fluent Bit pod restart | Applications continue | DaemonSet restarts; node-local buffer recovery is best effort; monitor collector restarts |
| Node filesystem pressure | Application pods remain protected by quotas and eviction policy | Rotate/drop according to documented priority; alert before critical pressure |
| Index mapping rejection | Applications continue | Send rejected records to quarantine/error path; fix template in the platform layer |

Logging loss is acceptable only as a controlled, measurable degradation of
operational visibility. It is never a reason to block, roll back, or alter a
financial workflow automatically.

## Security And Network Controls

### Network

- Use VPC access for both domains with private subnets across multiple
  Availability Zones. Do not enable public access for UAT or PROD.
- Permit inbound traffic only from the environment's EKS collector security
  group and explicitly approved operator access paths. Keep Dashboards behind
  private access, VPN, or an approved identity-aware administrative path.
- Require HTTPS/TLS for collector-to-domain and operator-to-Dashboards traffic.
  Require TLS 1.2 or the platform-approved stronger minimum and validate the
  AWS endpoint certificate using the standard trust store.
- Enable node-to-node encryption so traffic between OpenSearch nodes is also
  protected. Amazon OpenSearch Service documents this as TLS 1.2 encryption
  for in-VPC node communication.
- Keep AWS API access, KMS, CloudWatch Logs, and S3 snapshot access on private
  paths where the landing zone supports VPC endpoints. Do not route collector
  traffic through a public NAT path solely because the domain was configured
  with a public endpoint.

### IAM And OpenSearch Access

- Use EKS Pod Identity or IRSA for the Fluent Bit service account. Its role is
  environment-scoped and can sign requests and write only to the approved
  application-log index patterns.
- Use IAM identity policies plus the domain access policy. Use OpenSearch
  fine-grained access control for index and Dashboards permissions; do not use
  the master user for routine ingestion or searches.
- Separate roles at minimum into `collector-write`, `operations-read`,
  `security-audit-read`, `platform-admin`, and `break-glass-admin`. The
  `collector-write` role cannot delete indexes, change mappings, manage users,
  or read log data.
- Store no AWS credentials, endpoint secrets, or master credentials in service
  repositories, `config-repo`, container images, Helm values, or log events.
  Runtime delivery belongs to the AWS identity and secret-management design.
- Enable OpenSearch audit logging for administrative and data-access activity
  as an operational security control, publish it to a restricted CloudWatch
  log group, and alert on unauthorized access. It does not replace the
  platform's immutable financial or security audit store.

### Encryption And Redaction

- Enable encryption at rest with a customer-managed, symmetric AWS KMS key per
  environment or approved equivalent key boundary. Protect the key policy and
  monitor key use; do not delete or disable the key while data or snapshots
  depend on it.
- Enable node-to-node encryption and HTTPS-only domain access. Fine-grained
  access control requires HTTPS, encryption at rest, and node-to-node
  encryption.
- Service-side redaction remains the primary control. The collector may add a
  second denylist or quarantine control, but it must not be treated as a
  substitute for service redaction.
- Never use operational log fields for raw passwords, tokens, OTPs, PINs,
  payment-card values, full bank or IBAN numbers, raw identity documents,
  customer PII, or raw account/transaction records. Follow the complete
  [structured logging and redaction contract task](https://github.com/digital-bank-java/.github/issues/92).

## Index, Search, Retention, And Recovery

### Stable Index Contract

Use daily indexes behind an environment-specific alias or index pattern. A
recommended naming shape is:

```text
logs-application-{environment}-{yyyy.MM.dd}
logs-quarantine-{environment}-{yyyy.MM.dd}
```

Index names are collector/platform details. They are not emitted by services
and must not be used as a substitute for the required `environment` field.
Install one versioned index template per environment before enabling writes.
The template must preserve these mappings:

| Field | Mapping | Rule |
| --- | --- | --- |
| `timestamp` | `date` | UTC RFC 3339 with milliseconds |
| `level`, `service`, `environment`, `correlation_id`, `trace_id`, `span_id`, `event_name`, `logger`, `route` | `keyword` | Exact filtering and aggregations |
| `message` | `text` with a bounded `keyword` subfield where needed | Human search without unbounded exact-value fields |
| `http_method` | `keyword` | Exact filtering |
| `status_code` | `integer` | Range and aggregation queries |
| `duration_ms` | `long` | Range and percentile aggregations |
| `exception` | Explicit object with bounded `type`, `message`, and `stacktrace` fields | No uncontrolled dynamic field expansion |
| Kubernetes metadata | Explicit keywords and bounded numeric fields | Collector metadata cannot create unlimited fields |

Additional fields must use stable `snake_case` names and a reviewed template or
dynamic-template rule. Set a field-count limit and reject/quarantine events
that would create uncontrolled mappings. Do not index arbitrary request,
response, header, query-string, or customer-object payloads.

The following operational searches must work in SIT, UAT, and PROD by changing
only the environment index pattern and the authorized endpoint:

Find a workflow across services:

```json
GET logs-application-uat-*/_search
{
  "size": 100,
  "sort": [{"timestamp": "asc"}],
  "query": {
    "bool": {
      "filter": [
        {"term": {"environment": "uat"}},
        {"term": {"correlation_id": "corr-7f4b"}},
        {"range": {"timestamp": {"gte": "now-15m"}}}
      ]
    }
  }
}
```

Find errors for one service and trace:

```json
GET logs-application-prod-*/_search
{
  "size": 100,
  "sort": [{"timestamp": "desc"}],
  "query": {
    "bool": {
      "filter": [
        {"term": {"environment": "prod"}},
        {"term": {"service": "ledger-service"}},
        {"term": {"trace_id": "4bf92f3577b34da6a3ce929d0e0e4736"}},
        {"terms": {"level": ["WARN", "ERROR"]}},
        {"range": {"timestamp": {"gte": "now-1h"}}}
      ]
    }
  }
}
```

Find a service error-rate trend:

```json
GET logs-application-prod-*/_search
{
  "size": 0,
  "query": {
    "bool": {
      "filter": [
        {"term": {"environment": "prod"}},
        {"range": {"timestamp": {"gte": "now-24h"}}}
      ]
    }
  },
  "aggs": {
    "by_service": {
      "terms": {"field": "service", "size": 20},
      "aggs": {
        "by_level": {"terms": {"field": "level", "size": 10}}
      }
    }
  }
}
```

Dashboards saved searches and alerts must use these contract fields rather
than environment-specific parser fields. Any change to a required field,
mapping, or search query is a compatibility change reviewed by the platform
and service owners.

### Retention And Tiering

Apply ISM to daily indexes:

1. Rollover on age or size to prevent large shards.
2. Keep recent UAT and PROD data in hot storage for the searchable periods in
   the environment table.
3. Move older PROD operational indexes to UltraWarm or cold storage only after
   query and recovery testing confirms the required support workflow.
4. Delete indexes at the approved operational retention limit.
5. Apply a shorter, explicit retention to the quarantine index and review it
   during every collector incident; quarantine must not become an unnoticed
   second log store.

Use shard and replica counts based on measured ingest volume, shard size, and
  recovery targets. Do not copy SIT capacity values into PROD. Avoid high
  cardinality fields, uncontrolled dynamic mappings, and unnecessary replicas
  because they increase storage and heap cost.

### Backups And Disaster Recovery

- Use Amazon OpenSearch Service automated snapshots for routine domain
  recovery, and monitor snapshot success and age.
- For retention beyond the managed automated snapshot window or for a
  cross-region recovery objective, use scheduled manual snapshots in an
  encrypted, versioned S3 repository with a restricted snapshot role. Apply
  the approved cross-region replication and lifecycle policy where required.
- Test restore of the index template, ISM policy, representative indexes, and
  Dashboards saved objects at least quarterly in UAT or a recovery account.
- Record the recovery point objective and recovery time objective as part of
  the PROD service readiness review. OpenSearch logs are operational evidence;
  restoring them does not restore financial state or audit history.

## Monitoring And Cost

### Required Signals

Create CloudWatch alarms and an operator dashboard for at least:

- Domain cluster status, master reachability, data-node health, and service
  software/configuration changes.
- Free storage, EBS burst balance/throughput where applicable, CPU, JVM memory
  pressure, heap pressure, and shard count/relocation.
- Indexing and search latency, rejected requests, HTTP 4xx/5xx responses, and
  thread-pool queue/rejection metrics.
- Fluent Bit daemon availability, restart count, parse failures, output
  failures, retry count, buffer utilization, quarantined records, and dropped
  records.
- Freshness by service: alert when an expected active service has no accepted
  event within its agreed window, with maintenance and idle-service
  suppression to avoid false positives.
- OpenSearch error, index-slow, search-slow, and restricted audit logs in
  CloudWatch. Audit-log access is separately permissioned.

Page the production on-call for data loss risk, red cluster status, sustained
storage/heap pressure, or collector backlog approaching its bounded limit.
Route lower-severity mapping and dashboard failures to the platform queue.
Keep a runbook for collector output recovery, index rollover failure, shard
allocation issues, and snapshot restore.

### Cost Controls

Track cost by environment and domain tags. The main cost drivers are data-node
and dedicated-master capacity, EBS, UltraWarm/cold storage, CloudWatch log
ingestion and retention, S3 snapshots, cross-region transfer, and operator
query volume.

Before production sizing, measure bytes per event, events per second, peak
multiplier, compression, replicas, retention, and query concurrency. Size for
the peak ingest rate plus recovery headroom, not the average. Use short UAT
retention and smaller capacity for acceptance testing; do not turn UAT into a
shared production log archive.

For PROD, use a multi-AZ topology with capacity and dedicated cluster-manager
nodes appropriate for the measured workload. Enable UltraWarm/cold only when
the storage and query-cost model is lower than retaining all data on hot EBS.
Review high-cardinality fields and noisy log levels before adding nodes.

## Version Compatibility And Ownership

### Compatibility Rules

- Keep the same OpenSearch major/minor line in SIT, UAT, and PROD where the
  AWS service supports it. Pin the service version in infrastructure code; do
  not accept an implicit latest version.
- The application contract is OpenSearch-version independent: services emit
  JSON Lines to streams and do not call the OpenSearch API. Compatibility is
  therefore tested at the Fluent Bit parser/output, index template, ISM, and
  Dashboards layers.
- Before an upgrade, test representative success, error, exception, and
  asynchronous events; required mappings; redaction; correlation/trace
  searches; quarantine behavior; saved searches; alerts; and snapshot restore.
- Validate the Fluent Bit OpenSearch output plugin, TLS configuration, IAM
  signing, bulk request behavior, and any managed ingestion alternative
  against the target OpenSearch version.
- Prefer a staged UAT upgrade followed by a controlled PROD change window.
  Treat major-version upgrades, mapping changes, and ISM changes as reviewed
  compatibility changes. Keep a tested migration or restore path; do not
  assume an in-place rollback is available after a domain upgrade.

### Ownership

| Owner | Responsibilities |
| --- | --- |
| Service teams | Required fields, correlation/trace propagation, service-side redaction, log volume, and contract tests |
| Platform operations | EKS Fluent Bit, buffers, routing, domains, templates, ISM, capacity, Dashboards, alarms, snapshots, and upgrades |
| Security and audit | IAM model, KMS policy, access reviews, audit-log review, redaction policy, and production retention approval |
| SRE/on-call | Incident response for collector/domain degradation, recovery drills, and SLO-impact assessment |
| Application release owners | Validate log compatibility in UAT before release promotion; no AWS logging credentials or endpoint logic in services |

Platform operations owns the AWS domain and collector upgrade. Service owners
must approve changes that would alter the portable event contract. Security
must approve access, encryption, and retention changes. A release is not
blocked merely because OpenSearch is unavailable, but it is blocked when
redaction, access, or recovery verification fails.

## Alternatives And Tradeoffs

### Direct Fluent Bit To Amazon OpenSearch Service (Chosen)

**Advantages:** preserves the SIT topology and application contract, adds no
application dependency, keeps search latency low, and has a small operational
surface. Fluent Bit buffering and backpressure must be configured carefully,
and platform operations owns the collector fleet.

### CloudWatch Logs Plus Managed Delivery

Send EKS logs to CloudWatch Logs, then use a subscription and Amazon Data
Firehose or an equivalent managed delivery layer to OpenSearch.

**Advantages:** a managed durable handoff, less collector output management,
and useful CloudWatch-native retention and alarms. **Tradeoffs:** additional
ingestion, storage, delivery, and cross-service costs; more latency and failure
states; duplicate log billing; and another parser/schema boundary. This is a
valid later choice if measured volume or operational staffing makes direct
delivery unsuitable, but it is not needed for the initial mapping.

### One Shared UAT/PROD Domain With Index Isolation (Rejected)

It reduces domain count and may lower idle cost, but a policy, KMS, mapping,
capacity, snapshot, or operator mistake can cross the environment boundary.
It also creates noisy-neighbor and incident-blast-radius risks. Separate
domains, accounts, and keys are required for PROD.

### Application-Direct OpenSearch Logging (Rejected)

It can provide application-level acknowledgements, but it couples every
transaction path to a logging service, spreads credentials and retry logic
across services, and makes upgrades a cross-repository compatibility event.
The existing stdout/stderr contract gives sufficient decoupling.

### Self-Managed OpenSearch On EKS (Rejected For UAT/PROD)

It maximizes configuration control and topology similarity to SIT, but shifts
cluster upgrades, storage, quorum, snapshots, and on-call burden to the team.
The managed AWS service better matches the platform direction unless a future
capacity, compliance, or feature requirement demonstrates otherwise.

## Rollout And Acceptance Checklist

1. Provision the UAT domain and collector role in private network paths; verify
   TLS, KMS, fine-grained roles, templates, ISM, snapshots, and CloudWatch
   alarms before ingesting real UAT traffic.
2. Deploy Fluent Bit with a canary route and submit synthetic success, error,
   multiline-exception, malformed, and oversized events. Confirm searchable
   fields, redaction, quarantine metrics, and saved searches.
3. Stop or isolate the UAT domain in a controlled test. Confirm a representative
   customer request and asynchronous workflow complete without an OpenSearch
   dependency, while collector backlog and alerts behave as documented.
4. Verify snapshot creation and restore, including templates, ISM, and
   Dashboards objects. Record RPO/RTO evidence.
5. Repeat the checks in PROD with production access approvals, approved
   retention, measured capacity, and a change window. Promote the same
   collector contract and version only after UAT evidence is accepted.
6. Confirm no application repository contains an OpenSearch client, endpoint,
   credential, or environment-specific logging destination.

## References

- [Task #92 - Define structured logging and redaction contract](https://github.com/digital-bank-java/.github/issues/92)
- [Local SIT Guide](local-sit.md)
- [Platform Conventions](platform-conventions.md)
- [Amazon OpenSearch Service VPC and encryption guidance](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ntn.html)
- [Fine-grained access control](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/fgac.html)
- [Encryption at rest](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/encryption-at-rest.html)
- [Index State Management and storage tiers](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ism-tutorial.html)
- [OpenSearch Service snapshots](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/managedomains-snapshots.html)
- [OpenSearch Service monitoring and log publishing](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/monitoring.html)
