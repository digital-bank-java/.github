# Insomnia Auth And Session Workflow

This guide is a repeatable manual check of authentication and server-side
session behavior through the API Gateway in local Kubernetes SIT. It does not
replace Auth Service tests, gateway tests, or deployment checks.

## Preconditions

Confirm the local SIT cluster, Auth Service, and API Gateway are healthy:

```bash
kubectl config use-context docker-desktop
kubectl get deployments,pods,services --namespace digital-bank-sit
kubectl port-forward --namespace digital-bank-sit service/api-gateway 8080:8080
```

Use `http://localhost:8080` as the workstation gateway URL, or the selected
forwarded port if `8080` is occupied. Use the gateway for every request in
this guide; do not add a direct Auth Service URL to the shared environment.

## Environment

Use one Insomnia workspace with a Base Environment and named `SIT`, `UAT`,
and `PROD` child environments. The Base Environment contains names and empty
placeholders only:

```json
{
  "apiGatewayUrl": "",
  "authUsername": "",
  "authPassword": "",
  "authAccessToken": "",
  "authSessionId": ""
}
```

Keep usernames, passwords, bearer tokens, and session IDs in private/local
values. Do not export or sync those values. `SIT` is the active local
environment; `UAT` and `PROD` require approved gateway URLs and test
identities. `local` and `LOCAL-DEV` are not supported environments.

## Login

Select `SIT` and send:

```http
POST {{ apiGatewayUrl }}/api/v1/auth/login
Content-Type: application/json

{
  "username": "{{ authUsername }}",
  "password": "{{ authPassword }}"
}
```

Expect `200 OK` with `accessToken`, `tokenType: "Bearer"`, `sessionId`, and
`expiresAt`. The signed JWT contains `sub`, `sid`, `active`, `iss`, `iat`, and
`exp`, plus the configured space-delimited `scope` claim. The JWT `sid` must
match the response `sessionId`. Store only the token and session ID in private
local values.

With the default `REVOKE_PREVIOUS` session policy, a second successful login
for the same username revokes the earlier active session. The newest token
remains usable and the earlier token must fail once server-side session
validation is enforced.

## Protected Session Check

Use an already-defined protected request from the service workflow under test,
for example the transfer read request in
[the internal transfer guide](insomnia-transfer-workflow.md):

```http
GET {{ apiGatewayUrl }}/internal/v1/transfer-workflows/{{ transferId }}
Authorization: Bearer {{ authAccessToken }}
```

Do not invent a placeholder endpoint merely to test authentication. A
successful protected response confirms the gateway accepted the bearer token
and the server-side session is active for that route. Then repeat the same
request with these controlled variations:

1. Remove the `Authorization` header. Expect `401 Unauthorized`.
2. Change one character in the token. Expect `401 Unauthorized`.
3. Log out, then repeat the request with the same token. Expect `401
   Unauthorized` after revocation enforcement is deployed.

## Logout And Revocation

Send:

```http
POST {{ apiGatewayUrl }}/api/v1/auth/logout
Authorization: Bearer {{ authAccessToken }}
```

Expect `204 No Content`. Repeat the request with the same valid token shape;
logout is idempotent and should return `204` again. Repeat the protected
request and confirm that the revoked session is rejected. Clear the private
token and session values after the check.

## Failure Checks

| Check | Expected result |
| --- | --- |
| Blank or malformed login payload | `400` `application/problem+json` with validation errors |
| Unknown username or wrong password | `401` authentication-failed Problem Details |
| Missing, malformed, invalid, expired, or revoked bearer | `401` invalid-token Problem Details |
| Repeated logout with a valid token | `204 No Content` |
| Gateway route unavailable or returns `404` | Check gateway/configuration rollout; do not bypass the gateway |

Never record passwords, raw JWTs, Authorization headers, customer data, or
private environment values in issues, PRs, screenshots, or logs. Share only
redacted status codes, problem types, and opaque identifiers.

## Dependencies And Boundaries

The auth/session implementation is in [Auth Service PR #7](https://github.com/digital-bank-java/auth-service/pull/7), with the JWT/session foundation in [PRs #2-#6](https://github.com/digital-bank-java/auth-service/pulls?q=is%3Apr+is%3Amerged). Gateway route and scope enforcement are in [API Gateway PR #23](https://github.com/digital-bank-java/api-gateway/pull/23) and [Config Repo PR #39](https://github.com/digital-bank-java/config-repo/pull/39). Use the workflow only after the relevant service, configuration, and gateway revisions are deployed in SIT.

The current Auth Service API intentionally provides login and logout only. It
does not expose a public session-introspection or refresh endpoint, so no such
request is included here.
