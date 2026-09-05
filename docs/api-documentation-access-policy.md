# API Documentation Access Policy

## Purpose

This policy defines how OpenAPI contracts and interactive documentation are exposed for the
Digital Bank Java platform. API documentation is an internal developer and operator surface,
not a public customer-facing product surface.

The policy applies to service-owned OpenAPI contracts, the API Gateway's aggregated
documentation, and any Swagger UI or equivalent interactive client backed by those contracts.

## Environment Policy

| Environment | Documentation access | Interactive execution | Required exposure boundary |
| --- | --- | --- | --- |
| `sit` | Internal engineering and test users with authenticated access | Allowed for synthetic test data and non-destructive checks; mutations require an approved test case and scoped test accounts | Reachable through the internal SIT network or an approved workstation port-forward; never publicly exposed |
| `uat` | Authenticated internal users through an allowlisted network or internal portal | Limited to approved acceptance scenarios using synthetic or approved test fixtures; sensitive operations remain non-executable | Keep the documentation surface behind the UAT allowlist or internal portal and the normal gateway controls |
| `prod` | Authenticated internal users through an allowlisted network or internal portal | Disabled by default; if specifically enabled, permit only explicitly approved, low-risk operations under least-privilege authorization and audit | No public exposure; require both the production allowlist or internal portal and authentication |

Authentication and network controls are complementary. A network allowlist or internal portal
does not replace authentication, authorization, or audit logging.

## Gateway Aggregation

- Service teams own their OpenAPI contracts and keep the contract version, title, descriptions,
  schemas, and examples current.
- Consumers discover business API contracts through the API Gateway rather than service-specific public URLs.
- The canonical aggregated contract route is `/admin/docs/{service}/v3/api-docs`.
- The canonical central UI route is `/admin/docs/swagger-ui.html`.
- Direct service routes such as `/v3/api-docs` are cluster-internal implementation surfaces and
  must not be published as public documentation endpoints.
- Gateway routes for documentation must inherit the environment's authentication,
  authorization, network boundary, rate limits, and audit controls.

## Safe Interactive Execution

Interactive execution means using Swagger UI's `Try it out`, an equivalent API explorer, or a
generated request that sends traffic to an environment.

- Require an authenticated internal identity and the minimum authorization needed for the selected operation.
- Keep execution disabled by default in `prod`; documentation availability does not imply
  permission to execute an operation.
- Mark read-only and non-destructive operations separately from state-changing operations.
- In `sit` and `uat`, use synthetic data, approved test fixtures, and dedicated test accounts.
  Do not use real customer identifiers or production-like personal data in examples or requests.
- In `prod`, allow interactive execution only through an explicitly approved operational workflow
  with a named owner, least-privilege credentials, audit logging, and a clear rollback or
  compensating action where applicable.
- Do not expose credentials, bearer tokens, cookies, signing material, or reusable authorization
  headers in generated examples, URLs, request bodies, or UI defaults.
- Do not make sensitive production mutations, bulk operations, credential changes, or
  administrative actions executable from the documentation UI.
- Treat example payloads as documentation fixtures. They must not be copied from live requests or responses.

## Exclusions

The public business API documentation must exclude:

- Actuator and platform health endpoints, including `/actuator/**`.
- Administrative and operator endpoints, including `/admin/v1/**`, unless they are published in
  a separate authenticated internal administration reference with its own access policy.
- Internal configuration, diagnostics, metrics, tracing, deployment, or infrastructure endpoints.
- Debug routes, test-only routes, and implementation details that are not part of a supported business API.

Exclusion from the business contract does not make an endpoint public. Any separate internal
reference remains subject to authentication, authorization, network restrictions, audit
requirements, and the environment policy above.

## Content Safety

Every contract, schema, example, screenshot, and generated request must be reviewed before publication:

- Use placeholders or clearly synthetic values for names, identifiers, addresses, account
  numbers, tokens, and timestamps.
- Never include secrets, credentials, private keys, access tokens, session cookies, or private endpoints.
- Never include customer data, production responses, or copied live headers and payloads.
- Keep examples minimal and sufficient to explain the contract; omit fields that are not needed for the example.
- Recheck generated documentation after contract changes so newly added fields do not disclose sensitive data.

## Ownership and Review

The service owner maintains the service contract. The API Gateway owner maintains aggregation
and route protection. Security or platform reviewers must approve changes that alter `uat` or
`prod` exposure, enable interactive production execution, or add an administrative reference.
