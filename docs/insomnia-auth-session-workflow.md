# Insomnia Auth And Session Workflow

This is the repeatable manual workflow for checking authentication and session behavior against the local Kubernetes SIT environment. It exercises the public client path through the API Gateway; it does not replace the automated auth-service tests or deployment checks.

The current auth-service foundation provides `POST /api/v1/auth/login` and `POST /api/v1/auth/logout`. Gateway authentication and protected-route enforcement are separate delivery work. Complete the auth-service stack and the related gateway/config/security changes before treating the protected-request checks below as available.

## Prerequisites

Confirm the local SIT cluster and gateway are healthy, then keep the port-forward running while using Insomnia:

```bash
kubectl config use-context docker-desktop
kubectl get deployment,pod,service --namespace digital-bank-sit
kubectl port-forward --namespace digital-bank-sit service/api-gateway 8080:8080
```

Use `http://localhost:8080` as the workstation URL. If port `8080` is occupied, forward an unused port such as `18080:8080` and change only the active SIT environment value. Do not bypass the gateway with a direct auth-service, customer-service, or account-service URL.

## Environment Layout

Keep one Insomnia workspace with a **Base Environment** and three named sub-environments: **SIT**, **UAT**, and **PROD**.

| Environment | Use | `apiGatewayUrl` |
| --- | --- | --- |
| Base Environment | Shared variable names and empty placeholders only | Empty; supplied by a sub-environment |
| SIT | Active local Kubernetes environment | `http://localhost:8080` or the selected forwarded port |
| UAT | Cloud acceptance environment when approved | Approved HTTPS gateway URL, supplied locally |
| PROD | Production verification when explicitly authorized | Approved HTTPS gateway URL, supplied locally |

The Base Environment should contain no usable credential or token values. Keep the same variable names in each environment:

```json
{
  "apiGatewayUrl": "",
  "authUsername": "",
  "authPassword": "",
  "authAccessToken": "",
  "authSessionId": ""
}
```

Set `authUsername`, `authPassword`, `authAccessToken`, and `authSessionId` only as private/local values or through an approved local secret source. Before exporting or syncing the workspace, confirm that those values are absent. Never create a `LOCAL-DEV` environment and never add direct customer/account service URLs as standard variables.

SIT is the active environment for this workflow. UAT and PROD use the same request definitions but require approved access, environment-specific gateway configuration, and authorized test identities. Do not copy SIT credentials, tokens, or endpoints into UAT or PROD.

## Login

Select **SIT**, then send:

```http
POST {{ apiGatewayUrl }}/api/v1/auth/login
Content-Type: application/json

{
  "username": "{{ authUsername }}",
  "password": "{{ authPassword }}"
}
```

Expected result:

- `200 OK`.
- The response contains `accessToken`, `tokenType` (`Bearer`), `sessionId`, and `expiresAt`.
- The signed JWT contains `sub`, `sid`, `iss`, `iat`, and `exp`; `sid` matches `sessionId`.

Copy the access token and session ID only into the private/local SIT values. Do not put either value in the request URL, a request body other than the login password field, a shared example, or an exported workspace.

With the default `REVOKE_PREVIOUS` session policy, logging in again for the same username revokes the earlier active session. Use this behavior to verify single-session handling when the gateway session-validation dependency is available: the newest token remains usable and the earlier token must be rejected.

## Authenticated Request And Session Verification

After login, call a protected API through the gateway using the private token value:

```http
GET {{ apiGatewayUrl }}/<protected-path-from-the-api-contract>
Authorization: Bearer {{ authAccessToken }}
```

Use the exact protected path documented by the service or gateway change under test. A successful response confirms that the gateway accepted the bearer token and the session is active. Do not infer session validity from JWT decoding alone: signature, expiry, and the server-side session state all matter.

Repeat the request with one of these controlled variations:

1. Remove the `Authorization` header. Expect `401 Unauthorized`.
2. Change one character in the token. Expect `401 Unauthorized`.
3. Log out, then repeat the request with the same token. Expect `401 Unauthorized` after server-side revocation is enforced by the gateway/service.

The current auth-service foundation does not expose a public session-introspection endpoint. The protected-request check is therefore the observable session verification path once the gateway authentication slice is merged. Do not substitute a direct auth-service URL or claim that a successful login alone verifies downstream authorization.

## Logout And Revocation

Send logout with the token returned by login:

```http
POST {{ apiGatewayUrl }}/api/v1/auth/logout
Authorization: Bearer {{ authAccessToken }}
```

Expected result is `204 No Content`. Send the same request a second time to verify idempotent logout; it should still return `204` for the valid token shape. Then repeat the protected request and confirm that server-side session validation rejects the revoked session with `401 Unauthorized`.

Clear the private/local `authAccessToken` and `authSessionId` values after the check. A token's `exp` claim limits its lifetime, but expiry is not a substitute for logout and logout is not represented by editing the token. Revocation is checked against server-side session state.

## Failure Cases

| Check | Expected result | Interpretation |
| --- | --- | --- |
| Blank or malformed login payload | `400` `application/problem+json` | Request validation failed; do not retry with real credentials in a shared workspace. |
| Unknown username or wrong password | `401` `authentication-failed` problem | These failures are intentionally indistinguishable. |
| Missing, malformed, invalid, expired, or revoked bearer token | `401` `invalid-token` problem | Token verification or active-session validation failed. |
| Repeated logout for the same valid token | `204 No Content` | Revocation is idempotent. |
| Gateway route returns `404` or cannot connect | Gateway/config or rollout issue | Check the gateway route, Config Server state, and SIT rollout; do not add a direct service URL to the workspace. |

Do not paste `Authorization` headers, passwords, raw JWTs, customer data, or response dumps containing them into issues, pull requests, screenshots, or logs. Redact tokens before sharing any failure evidence.

## Automated-Test Boundary And Dependencies

Insomnia provides a manual smoke check for the deployed SIT route, configuration, request wiring, and observable login/logout lifecycle. It does not replace auth-service unit/integration tests, gateway route tests, or Kubernetes rollout checks. Run the automated quality gates in the owning repositories as part of those changes.

This workflow depends on the auth-service PR stack for the authentication/session foundation, JWT session claims, and single-session policy (the organization stories `.github#45`, `.github#46`, and `.github#47`). Gateway route, Config Server, and authentication/authorization enforcement changes must then be merged and deployed before the gateway-routed protected-request and post-revocation checks can pass. This documentation change does not add those routes or change deployment implementation.

Related guidance: [local Kubernetes SIT](local-sit.md), [platform conventions](platform-conventions.md), and the auth-service [session request notes](https://github.com/digital-bank-java/auth-service/blob/main/docs/insomnia/auth-service.md).
