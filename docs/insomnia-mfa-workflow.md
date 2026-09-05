# Insomnia MFA Workflow

This guide verifies the generic MFA enrollment and challenge lifecycle through
the API Gateway. Use synthetic SIT identities only. The transfer-bound
step-up flow is documented separately in
[the step-up transfer guide](insomnia-step-up-transfer-workflow.md).

## Preconditions And Environment

The API Gateway port-forward, MFA Service, Auth Service, and the gateway MFA
route must be healthy. The route/configuration dependency is [Config Repo PR #39](https://github.com/digital-bank-java/config-repo/pull/39).

Use the shared Insomnia Base Environment and select `SIT`:

| Variable | Purpose |
| --- | --- |
| `apiGatewayUrl` | API Gateway port-forward, normally `http://localhost:8080` |
| `authAccessToken` | Private internal JWT with the configured MFA scope |
| `mfaEnrollmentId` | Opaque enrollment ID captured from creation |
| `mfaChallengeId` | Opaque challenge ID captured from creation |
| `mfaCode` | Private six-digit code from the approved authenticator |

Keep all credentials, tokens, codes, and identifiers in private/local values.
Do not add a direct MFA Service URL to a shared environment.

Every authenticated request uses:

```http
Authorization: Bearer {{ authAccessToken }}
```

## 1. Create Enrollment

Enrollment ownership is derived from the authenticated JWT `sub` claim. The
legacy `subjectId` field is accepted for compatibility but ignored, so do not
add it to a new request:

```http
POST {{ apiGatewayUrl }}/api/v1/mfa/enrollments
Authorization: Bearer {{ authAccessToken }}
Content-Type: application/json

{}
```

Expect `201 Created` with an opaque `enrollmentId`, `status: "ENROLLED"`, and
`enrollmentStatus: "PENDING"`. Capture the ID as `mfaEnrollmentId`. The
response must not contain a TOTP secret or provisioning URI.

The current service contract does not expose a secret/provisioning response.
An approved platform authenticator path must provision the enrollment before
the next request can succeed. Do not guess a code or add a secret field.

## 2. Verify Enrollment

After the approved authenticator path supplies a valid code, send:

```http
POST {{ apiGatewayUrl }}/api/v1/mfa/enrollments/{{ mfaEnrollmentId }}/verifications
Authorization: Bearer {{ authAccessToken }}
Content-Type: application/json

{
  "code": "{{ mfaCode }}"
}
```

Expect `200 OK` with `status: "ACTIVATED"` and
`enrollmentStatus: "ACTIVE"`. A wrong six-digit code returns `401` Problem
Details; an unknown or foreign enrollment returns `404`; an already active
enrollment returns `409`.

## 3. Create Challenge

Once the enrollment is active, send:

```http
POST {{ apiGatewayUrl }}/api/v1/mfa/challenges
Authorization: Bearer {{ authAccessToken }}
Content-Type: application/json

{
  "enrollmentId": "{{ mfaEnrollmentId }}"
}
```

Expect `201 Created` with an opaque `challengeId`,
`challengeStatus: "OPEN"`, `expiresAt`, and `remainingAttempts`. Capture the
ID as `mfaChallengeId`.

## 4. Verify Challenge

Submit the current code:

```http
POST {{ apiGatewayUrl }}/api/v1/mfa/challenges/{{ mfaChallengeId }}/verifications
Authorization: Bearer {{ authAccessToken }}
Content-Type: application/json

{
  "code": "{{ mfaCode }}"
}
```

Expect `200 OK` with `status: "VERIFIED"` and
`challengeStatus: "CONSUMED"`. The challenge is single-use.

## Negative Checks

| Check | Expected result |
| --- | --- |
| Missing, malformed, expired, or revoked bearer | `401` `application/problem+json` |
| Authenticated principal without the MFA scope | `403` `application/problem+json` |
| Non-six-digit verification code | `400` validation Problem Details |
| Unknown or foreign enrollment/challenge | `404` resource-not-found Problem Details |
| Wrong six-digit code | `401` invalid-code Problem Details; attempts decrease |
| Expired challenge | `401` challenge-expired Problem Details |
| Exhausted challenge | `401` challenge-exhausted Problem Details |
| Replayed consumed challenge | `401` challenge-replayed Problem Details |
| Challenge created before enrollment is active | `409` enrollment-not-active Problem Details |

The MFA Service also enforces authenticated-principal ownership. Do not use a
different JWT subject to access an existing enrollment or challenge.

## Evidence And Boundaries

Record only the environment, date, request names, status codes, redacted
problem types, and opaque IDs where policy permits. Never record bearer
tokens, submitted codes, TOTP secrets, provisioning material, or raw response
dumps.

This generic workflow does not authorize a transfer, mutate account balances,
or publish transfer assurance. Successful transfer-bound verification and its
event handoff are covered by the separate step-up guide. The MFA Service has
no customer login, session management, recovery-code, or direct account API.
