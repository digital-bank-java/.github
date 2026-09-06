# Local SIT Centralized Logging Verification

This runbook verifies the local Docker Desktop SIT logging path delivered by
`infra-sit`: Kubernetes container output, Fluent Bit, OpenSearch, and
OpenSearch Dashboards. It is an operational-log check for synthetic SIT data;
it is not an audit, financial-record, UAT, or PROD procedure.

## Scope and contract

Run this procedure only against the `docker-desktop` Kubernetes context and the
`digital-bank-sit` namespace. The current merged `infra-sit` charts provide:

- OpenSearch at the internal `opensearch:9200` Service and Dashboards at the
  internal `opensearch-dashboards:5601` Service.
- Fluent Bit output indices named `digital-bank-sit-YYYY.MM.DD`.
- Application JSON under the `structured` object because the collector uses
  `Merge_Log_Key structured`.
- Collector fields such as `logging_agent`, `logging_parse_status`,
  `logging_invalid_event`, and Kubernetes metadata alongside the application
  event.

For a valid structured event, the searchable application fields are:

| Acceptance field | OpenSearch field | Meaning |
| --- | --- | --- |
| service | `structured.service` | Canonical service name. |
| environment | `structured.environment` | Must be `sit` for this runbook. |
| correlation_id | `structured.correlation_id` | Durable request/workflow identifier. |
| trace_id | `structured.trace_id` | Distributed-trace identifier. |
| level | `structured.level` | `TRACE`, `DEBUG`, `INFO`, `WARN`, or `ERROR`. |
| timestamp | `structured.timestamp` | Service-emitted RFC 3339 event time. |
| ingestion time | `@timestamp` | Collector/OpenSearch time used by the Dashboards time picker. |

OpenSearch normally creates `.keyword` subfields for these string values. Use
the field-capabilities check below before copying a query into Dashboards; if a
mapping does not expose `.keyword`, use the exact field name reported by that
check and do not change the event contract.

## Preconditions

Confirm the context, releases, and workload readiness without printing Secret
data:

```bash
test "$(kubectl config current-context)" = docker-desktop
kubectl get pods,services -n digital-bank-sit \
  -l 'app.kubernetes.io/name in (opensearch,opensearch-dashboards,fluent-bit)'
helm status opensearch --namespace digital-bank-sit
helm status fluent-bit --namespace digital-bank-sit
```

If a required release is not deployed or ready, stop here and follow the
`infra-sit` README. Do not treat an empty search as proof that the logging path
works when the collector or destination is unavailable.

## Temporary local access

Both Services are `ClusterIP`. Keep these forwards in separate terminals and
stop them with `Ctrl+C` when finished:

```bash
kubectl port-forward -n digital-bank-sit service/opensearch 19200:9200
kubectl port-forward -n digital-bank-sit service/opensearch-dashboards 15601:5601
```

The OpenSearch certificate is the local chart's internal certificate, so the
examples use `--insecure` only on the loopback port-forward. This is not a
production TLS or public-exposure pattern. Retrieve the existing local
credential without echoing or recording its value:

```bash
export OPENSEARCH_PASSWORD="$(kubectl get secret opensearch-admin \
  -n digital-bank-sit \
  -o jsonpath='{.data.OPENSEARCH_INITIAL_ADMIN_PASSWORD}' | base64 --decode)"
export OPENSEARCH_URL=https://127.0.0.1:19200
```

Do not paste the password into a command, issue, screenshot, saved search, or
Dashboard object. Unset it after the checks:

```bash
unset OPENSEARCH_PASSWORD OPENSEARCH_URL
```

## Read-only OpenSearch checks

Check cluster health and the daily index projection first. These commands return
metadata and counts, not log messages:

```bash
curl --silent --show-error --fail --insecure \
  --user "admin:${OPENSEARCH_PASSWORD}" \
  "${OPENSEARCH_URL}/_cluster/health?wait_for_status=yellow&timeout=5s" \
  | jq '{status,number_of_nodes,active_shards,unassigned_shards}'

curl --silent --show-error --fail --insecure \
  --user "admin:${OPENSEARCH_PASSWORD}" \
  "${OPENSEARCH_URL}/_cat/indices/digital-bank-sit-*?format=json&h=index,docs.count,store.size"
```

Confirm the mapping exposes the fields required by the acceptance criteria:

```bash
curl --silent --show-error --fail --insecure \
  --user "admin:${OPENSEARCH_PASSWORD}" \
  "${OPENSEARCH_URL}/digital-bank-sit-*/_field_caps?fields=structured.service*,structured.environment*,structured.correlation_id*,structured.trace_id*,structured.level*,structured.timestamp,@timestamp" \
  | jq '.fields'
```

Run the aggregate acceptance search. A non-zero result for `valid_structured`
must include the five required dimensions and the application timestamp in the
returned mapping. The service and level buckets are the proof that the same
index can be searched across those dimensions.

```bash
curl --silent --show-error --fail --insecure \
  --user "admin:${OPENSEARCH_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -X POST "${OPENSEARCH_URL}/digital-bank-sit-*/_search" \
  --data-binary @- <<'JSON' | jq '{total: .hits.total, services: .aggregations.services.buckets, levels: .aggregations.levels.buckets}'
{
  "size": 0,
  "query": {
    "bool": {
      "filter": [
        {"term": {"structured.environment.keyword": "sit"}},
        {"term": {"logging_parse_status.keyword": "valid"}},
        {"exists": {"field": "structured.service"}},
        {"exists": {"field": "structured.correlation_id"}},
        {"exists": {"field": "structured.trace_id"}},
        {"exists": {"field": "structured.level"}},
        {"exists": {"field": "structured.timestamp"}},
        {"exists": {"field": "@timestamp"}}
      ]
    }
  },
  "aggs": {
    "services": {"terms": {"field": "structured.service.keyword", "size": 50}},
    "levels": {"terms": {"field": "structured.level.keyword", "size": 10}}
  }
}
JSON
```

Search each acceptance dimension with a synthetic identifier. Keep the result
projection limited to safe fields and never include `message`, exception text,
request bodies, or arbitrary `_source` in evidence:

```bash
# Service, environment, level, and recent timestamp.
curl --silent --show-error --fail --insecure \
  --user "admin:${OPENSEARCH_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -X POST "${OPENSEARCH_URL}/digital-bank-sit-*/_search" \
  --data-binary @- <<'JSON' | jq '.hits.hits[] | {index: ._index, ingest_time: ._source["@timestamp"], event: ._source.structured}'
{
  "size": 20,
  "sort": [{"@timestamp": "desc"}],
  "_source": ["@timestamp", "structured.service", "structured.environment", "structured.level", "structured.timestamp"],
  "query": {
    "bool": {
      "filter": [
        {"term": {"structured.environment.keyword": "sit"}},
        {"term": {"structured.service.keyword": "<service-name>"}},
        {"range": {"@timestamp": {"gte": "now-15m"}}}
      ]
    }
  }
}
JSON

# Correlation and trace lookup. Use synthetic IDs from the request under test.
curl --silent --show-error --fail --insecure \
  --user "admin:${OPENSEARCH_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -X POST "${OPENSEARCH_URL}/digital-bank-sit-*/_search" \
  --data-binary @- <<'JSON' | jq '.hits.hits[] | {index: ._index, ingest_time: ._source["@timestamp"], service: ._source.structured.service, environment: ._source.structured.environment, level: ._source.structured.level, correlation_id: ._source.structured.correlation_id, trace_id: ._source.structured.trace_id, event_timestamp: ._source.structured.timestamp}'
{
  "size": 50,
  "sort": [{"@timestamp": "asc"}],
  "_source": ["@timestamp", "structured.service", "structured.environment", "structured.level", "structured.correlation_id", "structured.trace_id", "structured.timestamp"],
  "query": {
    "bool": {
      "filter": [
        {"term": {"structured.environment.keyword": "sit"}},
        {"term": {"structured.correlation_id.keyword": "<synthetic-correlation-id>"}},
        {"term": {"structured.trace_id.keyword": "<synthetic-trace-id>"}}
      ]
    }
  }
}
JSON
```

The first search proves service, environment, level, and both timestamp
representations. The second proves exact correlation and trace lookup across
the indexed event set. If either search returns zero records, record whether
the cause is no synthetic request, a service-side structured logging gap, or a
collector/destination problem; do not broaden the query until the cause is
known.

Check collector failures separately from valid application events:

```bash
curl --silent --show-error --fail --insecure \
  --user "admin:${OPENSEARCH_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -X POST "${OPENSEARCH_URL}/digital-bank-sit-*/_search" \
  --data '{"size":0,"query":{"bool":{"filter":[{"range":{"@timestamp":{"gte":"now-15m"}}},{"terms":{"logging_parse_status.keyword":["invalid","unstructured"]}}]}},"aggs":{"status":{"terms":{"field":"logging_parse_status.keyword"}},"reasons":{"terms":{"field":"invalid_event_reason.keyword"}}}}' \
  | jq '{total: .hits.total, status: .aggregations.status.buckets, reasons: .aggregations.reasons.buckets}'
```

Invalid structured JSON and unstructured fallback records are visible failure
signals. A redaction failure is not accepted as a successful logging result,
even when the collector continues forwarding other records.

### Current merged-state SIT result

The read-only verification run on 2026-09-06 reached the live Docker Desktop
cluster. OpenSearch, OpenSearch Dashboards, and Fluent Bit were each `1/1` and
their Helm releases were `deployed`. OpenSearch reported `yellow` health with
one node, 11 active shards, and 6 unassigned replica shards, which is expected
for the single-node local chart.

The collector query returned 3,410 `logging_parse_status=valid` records and
zero `invalid` or `unstructured` records in the checked 15-minute window. That
proves the collector is accepting JSON records, but it does not prove the
application contract. Field-capabilities and presence queries found:

- `@timestamp` on indexed records;
- `structured.level` on 207 records;
- zero records with `structured.service`, `structured.environment`,
  `structured.correlation_id`, `structured.trace_id`, or
  `structured.timestamp`.

Therefore the current deployed workload does **not** pass the application-level
search acceptance yet. The runbook is complete and reproducible, but the
service rollout that emits the required fields must be completed before issue
`digital-bank-java/.github#91` can be closed. Do not convert collector-valid
records into a passing structured-log result.

## Reproducible Dashboards views

Open `http://localhost:15601` through the Dashboard port-forward and use the
local operator credential supplied through the approved Secret workflow. In the
current local chart, Dashboards is a single ClusterIP pod with the `Private` and
`Global` tenants enabled; keep saved objects in the local Private tenant.

Create one data view:

1. Go to **Stack Management > Data views** and create `SIT operational logs`.
2. Set the index pattern to `digital-bank-sit-*`.
3. Select `@timestamp` as the time field. Use `structured.timestamp` when
   inspecting service-emission time; it is not the Dashboards time-picker field
   unless its mapping is explicitly a date.
4. Add these columns to Discover: `structured.service`,
   `structured.environment`, `structured.level`,
   `structured.correlation_id`, `structured.trace_id`, `structured.timestamp`,
   `logging_parse_status`, `logging_invalid_event`, and
   `kubernetes.pod_name`.

Save these searches in the same tenant:

| Saved search | DQL filter | Purpose |
| --- | --- | --- |
| `SIT - errors by service` | `structured.environment.keyword:"sit" AND structured.level.keyword:(ERROR OR WARN)` | Review warning/error volume by service over the selected time window. |
| `SIT - correlation and trace` | `structured.environment.keyword:"sit" AND structured.correlation_id.keyword:"<synthetic-correlation-id>" AND structured.trace_id.keyword:"<synthetic-trace-id>"` | Follow one synthetic request across services. |
| `SIT - collector rejects` | `logging_parse_status.keyword:(invalid OR unstructured)` | Find records that did not satisfy the structured event contract. |

Build one dashboard named `SIT logging acceptance` from those searches:

- a time histogram of valid structured events split by `structured.level.keyword`;
- a table grouped by `structured.service.keyword` and
  `structured.environment.keyword`;
- a correlation/trace table using the safe columns above; and
- a collector-reject count grouped by `logging_parse_status.keyword` and
  `invalid_event_reason.keyword`.

Do not save full log messages, request bodies, exception text, credentials,
tokens, OTP values, customer data, or unmasked account/payment identifiers in
objects or screenshots.

## Reproducible local alerts

Create query-level monitors only in the local Private tenant. Do not configure
email, webhook, pager, or any external notification destination for this local
runbook. The conditions below are acceptance signals for a developer ticket or
console notification, not UAT/PROD paging policy.

### Invalid or unstructured event monitor

- Name: `SIT - invalid structured event`.
- Index: `digital-bank-sit-*`.
- Schedule: every 1 minute.
- Query window: `@timestamp` from `now-5m` to `now`.
- Filter: `logging_parse_status.keyword` is `invalid` or `unstructured`.
- Trigger: `hit count > 0`.
- Action: local console/test action only; include the environment, service when
  available, reason code, and time window, never the message or raw event.

### Error burst monitor

- Name: `SIT - service error burst`.
- Index: `digital-bank-sit-*`.
- Schedule: every 1 minute.
- Query window: `@timestamp` from `now-5m` to `now`.
- Filter: `structured.environment.keyword` is `sit` and
  `structured.level.keyword` is `ERROR`.
- Trigger: `hit count >= 5`.
- Action: local console/test action only; include service and count, and link to
  the saved `SIT - errors by service` search.

After creating each monitor, use the Dashboards test action with synthetic SIT
events and confirm that the trigger fires once for the window. Clear the test
data or wait for the local retention/reset procedure; do not leave a recurring
external notification active.

## Access and lifecycle boundaries

- Access is workstation-only through temporary `kubectl port-forward`; the
  Services remain `ClusterIP` and must not be changed to `LoadBalancer`,
  `NodePort`, public Ingress, or a host-published port for this task.
- Fluent Bit authenticates to OpenSearch with the local `opensearch-admin`
  Secret. Dashboards uses its internal `kibanaserver` credential from the local
  `opensearch-dashboards` Secret. The current SIT chart does not establish a
  production-style named operator/read-only role model; treat Dashboard access
  as trusted local developer/admin access and do not reuse it outside SIT.
- OpenSearch is one replica with a 5Gi local Docker Desktop PVC. This is a
  capacity and restart boundary, not a retention guarantee, backup policy,
  high-availability topology, or compliance archive. The chart does not add a
  cloud lifecycle policy or durable snapshot workflow.
- Operational logs remain separate from financial postings, balances, customer
  records, authentication history, and immutable security/business audit
  records. An `audit_id` or correlation/trace identifier may link systems, but
  OpenSearch logs must never be used to reconstruct an audit record.
- Service-side redaction is the primary control. Fluent Bit is defense in
  depth; its redaction and invalid-event markers do not authorize a service to
  emit secrets or sensitive payloads.
- Use synthetic SIT data only. Do not copy indexed values into issue comments,
  screenshots, saved objects, or chat. Teardown, PVC deletion, retention
  changes, and credential rotation are separate operator actions and require
  an explicit local reset decision.

UAT, PROD, Amazon OpenSearch Service, managed encryption, cloud IAM, external
retention, snapshots, and production notification routing are outside this
runbook and remain deferred to the Sprint 7 architecture and security work.

## Evidence record

Record only safe metadata for a completed local run:

```text
context: docker-desktop
namespace: digital-bank-sit
index pattern: digital-bank-sit-*
observed UTC window: <start>/<end>
valid structured events: <count>
services observed: <names only>
levels observed: <levels only>
correlation lookup: <matched count for synthetic ID>
trace lookup: <matched count for synthetic ID>
invalid/unstructured count: <count>
OpenSearch health: <status and node/shard counts>
Dashboards views: <data view and saved-search names>
local alerts: <monitor names and trigger result>
secrets or raw messages recorded: none
```

The existing `infra-sit` validation remains the source of chart-level evidence:

```bash
helm lint helm/opensearch --values helm/opensearch/values-sit.yaml
helm lint helm/fluent-bit --values helm/fluent-bit/values-sit.yaml
bash tests/validate.sh
bash tests/validate-fluent-bit.sh
```
