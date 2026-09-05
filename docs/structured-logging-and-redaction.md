# Structured Logging And Redaction Contract

This contract defines the portable logging boundary for Digital Bank Java
services. It applies to the `sit`, `uat`, and `prod` environments and is
intended to be implemented consistently by every Spring Boot service.

## Contract Goals

- Emit machine-readable operational events that can be collected without
  service-specific parsing.
- Keep sensitive data out of process output and downstream log stores.
- Preserve enough context to correlate a request, message, exception, and
  distributed trace.
- Keep operational diagnostics separate from immutable business and security
  audit records.

## Required Event Shape

Every operational log event MUST be one valid JSON object encoded as UTF-8 and
terminated by exactly one newline. The following fields are required:

| Field | Type | Requirement |
| --- | --- | --- |
| `timestamp` | string | UTC time in RFC 3339 format with milliseconds, for example `2026-08-30T10:15:30.123Z`. The event time is when the service emitted the event. |
| `level` | string | One of the configured levels, normally `TRACE`, `DEBUG`, `INFO`, `WARN`, or `ERROR`. |
| `service` | string | Canonical lowercase service name, such as `account-service` or `ledger-service`. |
| `environment` | string | One of `sit`, `uat`, or `prod`. The value MUST be supplied by runtime configuration. |
| `correlation_id` | string | End-to-end request or workflow identifier. The service preserves an accepted inbound value or creates one at the first trusted boundary. |
| `trace_id` | string | Distributed-trace identifier. For W3C Trace Context, this is the 32-lowercase-hexadecimal trace ID. Use `unknown` only when no trace context exists, such as an early startup failure. |
| `logger` | string | Fully qualified logger name or stable application logger category. |
| `message` | string | Short human-readable event summary. It MUST NOT contain unredacted sensitive values. |

Services SHOULD also emit these fields when available:

| Field | Purpose |
| --- | --- |
| `span_id` | Identifies the current trace span. |
| `event_name` | Stable machine-readable event name, for example `transfer.authorized`. |
| `request_id` | Transport-specific request identifier when different from `correlation_id`. |
| `http_method`, `route`, `status_code` | Sanitized HTTP operation context. Use route templates, not raw URLs containing identifiers. |
| `duration_ms` | Elapsed processing time as a non-negative number. |
| `exception` | Nested `type`, `message`, and `stacktrace` failure details, subject to the redaction rules below. |
| `audit_id` | Link to a separately stored audit record when an operation also creates one. |

Additional fields MUST use stable snake_case names, must have scalar or nested
JSON values that remain valid after serialization, and must not replace or
rename required fields. High-cardinality or sensitive values belong in neither
the field name nor the field value.

Example operational event:

```json
{"timestamp":"2026-08-30T10:15:30.123Z","level":"INFO","service":"account-service","environment":"sit","correlation_id":"corr-7f4b","trace_id":"4bf92f3577b34da6a3ce929d0e0e4736","span_id":"00f067aa0ba902b7","logger":"com.digitalbank.accountservice.AccountApplication","message":"Account lookup completed","event_name":"account.lookup.completed","status_code":200,"duration_ms":18}
```

## Service Emission Boundary

Spring Boot services own the event schema, context propagation, and redaction.
They MUST:

1. Configure the logging framework to serialize each event as one JSON object
   on one physical line.
2. Write normal operational events to `stdout` and error events, including
   uncaught exception events, to `stderr`.
3. Flush output through the normal container process streams; services MUST
   not write application logs directly to files inside the container.
4. Redact or omit prohibited values before serialization. A downstream
   collector is an additional control, not the primary protection.
5. Avoid logging an exception twice merely because it was written to both
   application logging and an error handler.

The `stdout`/`stderr` distinction is a routing signal, not a different event
schema. Both streams contain JSON Lines and are collected with their source
stream metadata preserved. A log event MUST NOT contain terminal color codes,
plain-text prefixes, banners, or a pretty-printed multi-line JSON object.

### Fluent Bit and OpenSearch Responsibilities

Fluent Bit owns collection and transport concerns:

- Read both container streams and preserve `stdout` or `stderr` as source
  metadata.
- Parse one JSON object per line and attach collector metadata such as pod,
  namespace, container, and node where available.
- Apply the multiline fallback described below only when the source is not
  already a complete JSON event.
- Route operational events to the environment's approved OpenSearch indexes
  or equivalent operational sink, with retention and access policies supplied
  by platform operations.
- Reject, quarantine, or visibly count malformed records instead of silently
  dropping them.

OpenSearch owns indexing, querying, lifecycle, access control, and operational
retention. OpenSearch is not the authoritative store for immutable business or
security audit history.

## Multiline Exception Ingestion

The preferred representation is a single JSON event. Newline characters in
`exception.message` or `exception.stacktrace` MUST be JSON-escaped as `\n`, so
the serialized event still occupies one physical line. The collector parses
the JSON first and exposes the decoded stack trace to query clients.

For a legacy or third-party emitter that cannot produce one-line JSON, Fluent
Bit MUST use an explicit parser with all of the following behavior:

- Start a new exception event only when a line matches the configured JSON
  event start pattern or the approved exception-start pattern.
- Append continuation lines to that event until the next matching start line.
- Preserve the original stream, timestamp, service, environment, and
  correlation context when they are available.
- Send an unterminated or ambiguous group to a quarantine/error route with a
  metric; never merge records from different streams or containers.
- Apply the same sensitive-data filtering before the record leaves the
  collector.

The multiline parser is a compatibility boundary, not permission for service
code to emit pretty-printed JSON. A rollout MUST include a sample exception in
each environment and verify that it becomes one searchable event.

## Redaction And Data Minimization

Redaction occurs at the service before a value reaches `stdout` or `stderr`.
The rule is fail closed: if a field's sensitivity is unknown, omit its value
and log only a stable field name or classification.

### Prohibited Values

The following values MUST NOT be logged, including in exception messages,
request bodies, query strings, headers, structured arguments, audit links, or
debug output:

- Passwords, passphrases, client secrets, private keys, database credentials,
  connection strings containing credentials, and signing material.
- Access tokens, refresh tokens, session identifiers, API keys, cookies,
  authorization headers, bearer values, and one-time links.
- OTP values, PINs, CVV/CVC values, recovery codes, and challenge responses.
- Full payment card numbers, full bank account numbers, full IBANs, and raw
  authentication or identity documents.
- Raw account balances, transaction details, and customer or account records
  unless an approved operational use case defines a masked or aggregated
  representation.
- Customer PII such as national identifiers, dates of birth, addresses, email
  addresses, phone numbers, names, and free-form customer-provided text unless
  an approved operational use case defines a masked representation.

Logging a whole request or response object is prohibited unless its schema is
explicitly allow-listed and tested for redaction. Do not rely on key names
alone: token-shaped and credential-shaped values in free-form strings must
also be detected.

### Allowed Masking

Operational logs should omit sensitive fields rather than mask them. When a
support or fraud workflow genuinely needs correlation to an account or
customer, it may use an approved non-reversible reference or a masked value
showing at most the final four characters, for example `****1234`. The full
source value MUST never be present in the same event, another field, or an
exception attached to that event. OTP, PIN, CVV/CVC, passwords, and secrets
are always omitted; they are never partially masked.

Redaction MUST cover both structured keys and common aliases, including
`password`, `secret`, `client_secret`, `authorization`, `cookie`, `token`,
`access_token`, `refresh_token`, `api_key`, `otp`, `one_time_password`, `pin`,
`cvv`, `cvc`, `iban`, `account_number`, `card_number`, `national_id`,
`date_of_birth`, `email`, `phone`, and `address`. Services may maintain a
stricter local denylist, but may not weaken this contract.

### Verification

Each service's logging tests MUST assert that representative values for every
prohibited category are absent from serialized events, including nested
objects and exception text. Tests SHOULD also assert that:

- Every emitted record parses as one JSON object.
- Required fields are present and use the configured environment.
- Correlation and trace context survive success and failure paths.
- A multi-line stack trace is escaped inside one physical JSON line.
- Redaction does not replace a secret with an equivalent value in another
  field.

## Operational Logs Versus Audit Records

Operational logs answer "what happened in the running system?" They are
diagnostic, searchable, and subject to operational retention. They may be
sampled or deleted according to the approved environment policy and MUST NOT
be used as the source of truth for a financial, authorization, or customer
state decision.

Immutable audit records answer "what business or security action must be
provable later?" They are written through the owning service's audit boundary
to an append-only store with controlled access, integrity protection, and an
explicit retention policy. An audit record MUST include the authorized actor
or system principal, action, target reference, outcome, event time, reason or
decision context when applicable, and a link to the relevant `correlation_id`
and `trace_id`. It MUST contain only approved masked references and no secrets,
OTP values, credentials, tokens, or raw customer PII.

An audit record MUST NOT be reconstructed from OpenSearch operational logs.
When an operation creates both records, the operational event may include
`audit_id` and the audit record may include the same correlation and trace
identifiers. Updating or deleting an audit record is not an operational-log
operation; corrections use the owning audit process and an append-only
compensating record.

## Correlation And Distributed Tracing

- `correlation_id` represents the business request or workflow across service
  boundaries. HTTP clients and asynchronous producers propagate it in the
  approved context headers or message metadata. A trusted ingress creates it
  when absent; internal services preserve it.
- `trace_id` and `span_id` represent the distributed trace. Instrumentation
  propagates W3C Trace Context where supported and creates a new span for each
  service operation. A trace may end before an asynchronous workflow ends;
  `correlation_id` remains the durable workflow link.
- Consumers MUST copy validated context into the logging context before the
  handler starts and clear it after completion so identifiers cannot leak
  between requests or messages.
- Logs and traces are complementary. The log contract does not make a log
  event an audit record, and a trace backend does not replace either logging
  or audit storage.

## Environment Responsibilities

The contract is portable across `sit`, `uat`, and `prod`; only destinations,
retention values, access groups, and capacity settings vary by environment.

| Owner | `sit` | `uat` | `prod` |
| --- | --- | --- | --- |
| Service teams | Emit the same JSON shape, propagation, and redaction behavior; use synthetic data. | Verify the release candidate against the same contract and synthetic or approved test data. | Operate the approved release with the same fail-closed redaction and schema guarantees. |
| Platform/collector operations | Configure Fluent Bit for both streams, multiline compatibility, quarantine metrics, and the SIT operational sink. | Validate routing, parser behavior, dashboards, access, and retention before acceptance testing. | Operate highly available collection, alert on malformed or quarantined records, and enforce production access and retention. |
| Security and audit owners | Provide test cases and review audit classification. | Approve security/audit evidence and access before acceptance. | Own audit-store policy, integrity controls, retention, access review, and incident response. |

Environment configuration MUST supply `environment` as `sit`, `uat`, or `prod`
and MUST NOT be inferred from a log message. Credentials for collectors,
OpenSearch, and audit storage are injected at runtime and are never placed in
service configuration committed to source control.

## Acceptance Checklist

- [ ] Every service emits one JSON event per physical line to `stdout` or
      `stderr` with all required fields.
- [ ] Collector parsing preserves stream metadata and handles malformed and
      legacy multiline records visibly.
- [ ] Automated tests demonstrate that credentials, tokens, OTP values,
      account data, and customer PII are absent or in an approved masked form.
- [ ] Operational retention and OpenSearch access are documented separately
      from immutable audit retention and access.
- [ ] A success path, failure path, and asynchronous path preserve both
      `correlation_id` and `trace_id` where trace context exists.
- [ ] SIT, UAT, and PROD ownership and rollout checks are identified before
      enabling the contract for a service.
