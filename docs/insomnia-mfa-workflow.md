# Insomnia MFA Workflow

This document defines the Insomnia workflow for the internal MFA HTTP contract.
It is a verification guide for the Digital Bank Java platform, not a customer
authentication guide. Use synthetic SIT identities only.

## Preconditions

The following dependencies must be available before the workflow can be run
through the normal platform entry point:

- The API Gateway port-forward is running and `apiGatewayUrl` points to it.
- The MFA Service SIT configuration and gateway route are deployed from
  [config-repo PR #32](https://github.com/digital-bank-java/config-repo/pull/32).
- The caller has an internal JWT with the `mfa.internal` scope. The login and
  token-handling procedure is documented by the pending
  [auth session workflow PR #178](https://github.com/digital-bank-java/.github/pull/178).
- The MFA Service deployment is healthy.

Use the shared Insomnia **Base Environment** and select **SIT**. Do not add a
direct MFA service URL to a shared environment. Normal requests use:

```text
{{ apiGatewayUrl }}
```

The SIT value is normally `http://localhost:8080` while the gateway is
forwarded. Use the actual forwarded port if `8080` is occupied.

## Variables

Keep these values in the private SIT child environment or request-local
variables. Do not commit tokens, TOTP secrets, or real customer identifiers.

| Variable | Example | Purpose |
| --- | --- | --- |
| `apiGatewayUrl` | `http://localhost:8080` | API Gateway port-forward |
| `authAccessToken` | private value | Internal JWT with `mfa.internal` |
| `mfaSubjectId` | `sit-subject-001` | Synthetic subject identifier |
| `mfaEnrollmentId` | response value | Enrollment id captured after creation |
| `mfaChallengeId` | response value | Challenge id captured after creation |
| `mfaCode` | private value | Six-digit code from the approved authenticator |

Apply this header to every authenticated request:

```http
Authorization: Bearer {{ authAccessToken }}
```

## 1. Create Enrollment

Create a pending enrollment for a synthetic subject:

```http
POST {{ apiGatewayUrl }}/api/v1/mfa/enrollments
Authorization: Bearer {{ authAccessToken }}
Content-Type: application/json

{
  "subjectId": "{{ mfaSubjectId }}"
}
```

Expected result: `201 Created`, an opaque `enrollmentId`, and
`enrollmentStatus: PENDING`. Capture `enrollmentId` as
`mfaEnrollmentId`. The response must not contain `secret` or
`provisioningUri`.

The `Location` header points to the enrollment resource. The current contract
does not expose a GET operation for that resource.

## 2. Verify Enrollment

After the platform-owned authenticator provisioning path has supplied a valid
code, activate the enrollment:

```http
POST {{ apiGatewayUrl }}/api/v1/mfa/enrollments/{{ mfaEnrollmentId }}/verifications
Authorization: Bearer {{ authAccessToken }}
Content-Type: application/json

{
  "code": "{{ mfaCode }}"
}
```

Expected result: `200 OK`, `status: ACTIVATED`, and
`enrollmentStatus: ACTIVE`.

The current SIT foundation deliberately does not return the generated TOTP
secret or provisioning URI. Therefore, a fresh deployment cannot complete
this step through Insomnia until the tracked authenticator provisioning
capability exists. Do not guess a code, add a secret field to the request, or
weaken the response contract to make the test appear to pass.

## 3. Create Challenge

After enrollment is active, create a one-time challenge:

```http
POST {{ apiGatewayUrl }}/api/v1/mfa/challenges
Authorization: Bearer {{ authAccessToken }}
Content-Type: application/json

{
  "enrollmentId": "{{ mfaEnrollmentId }}"
}
```

Expected result: `201 Created`, an opaque `challengeId`,
`challengeStatus: OPEN`, an `expiresAt` timestamp, and the configured
`remainingAttempts`. Capture `challengeId` as `mfaChallengeId`.

## 4. Verify Challenge

Submit the current code from the approved authenticator:

```http
POST {{ apiGatewayUrl }}/api/v1/mfa/challenges/{{ mfaChallengeId }}/verifications
Authorization: Bearer {{ authAccessToken }}
Content-Type: application/json

{
  "code": "{{ mfaCode }}"
}
```

Expected result: `200 OK`, `status: VERIFIED`, and
`challengeStatus: CONSUMED`. Repeating the same request after consumption
returns the replay-safe terminal result and does not call the TOTP provider a
second time.

## Negative-Path Verification

These checks are executable without exposing a TOTP secret:

| Request | Expected result |
| --- | --- |
| Any MFA request without `Authorization` | `401` Problem Details |
| Any MFA request with a malformed or expired JWT | `401` Problem Details |
| Authenticated request without `mfa.internal` | `403` Problem Details |
| Verification request with a non-six-digit code | `400` Problem Details |
| Verification for an unknown enrollment or challenge id | `404` Problem Details |
| Verification with a wrong six-digit code | `401` Problem Details; attempts decrease |
| Verification after expiry | `401` Problem Details; challenge is terminal |

Problem responses use `application/problem+json`. Do not record bearer tokens,
submitted codes, TOTP secrets, or raw response dumps in GitHub issues or PR
comments.

## Completion Evidence

For a completed manual run, record only non-sensitive evidence in the parent
issue or PR:

- environment: SIT;
- gateway URL and date, without credentials;
- request names and HTTP status codes;
- opaque enrollment/challenge identifiers only when policy allows them;
- confirmation that secret-bearing fields were absent;
- failure-path status codes and terminal-state behavior.

The full positive-path workflow becomes verifiable after the authenticator
provisioning path and gateway configuration are available. Until then, report
the positive-path limitation as a dependency rather than treating an invalid
placeholder code as successful verification.

Related implementation boundaries:

- [MFA Service HTTP contract](https://github.com/digital-bank-java/mfa-service#http-api)
- [MFA provider foundation](https://github.com/digital-bank-java/mfa-service/blob/main/docs/superpowers/specs/2026-08-30-mfa-provider-foundation-design.md)
- [Platform API and security conventions](platform-conventions.md)
- [Workstation debugging against SIT](workstation-debugging-against-sit.md)

All changes to this workflow require a tracked issue, a dedicated branch, and
a pull request. Never commit credentials or production data.
