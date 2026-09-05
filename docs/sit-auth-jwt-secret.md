# Shared Auth JWT Secret for Local SIT

This runbook provisions the local-only HMAC signing key shared by Auth Service,
Transaction Service, API Gateway, MFA Service, and Payment Service in the
`digital-bank-sit` namespace. It is limited to Docker Desktop SIT. Do not use
this procedure for UAT or PROD.

Supporting task: [`.github#192`](https://github.com/digital-bank-java/.github/issues/192)

## Secret Contract

| Property | Required value |
| --- | --- |
| Namespace | `digital-bank-sit` |
| Kubernetes Secret | `auth-service-secrets` |
| Data key | `jwt-secret` |
| Application environment variable | `AUTH_JWT_SECRET` |
| Stored value | Base64 text that decodes to at least 32 random bytes |

The applications decode the stored text before using it as an HMAC-SHA signing
key. Kubernetes represents Secret data as base64 in its API object; that API
encoding is separate from the application-level base64 format and is not
encryption.

The current SIT Helm values wire every secured consumer to this same Secret
reference:

| Workload | SIT enablement | Chart secret reference | Additional secret prerequisite |
| --- | --- | --- | --- |
| API Gateway | `security.enabled=true` | `security.secretName` / `security.secretKey` | None |
| Auth Service | `secrets.enabled=true` | `secrets.name` / `secrets.keys.jwtSecret` | `fixture-password-hash` in the same Secret |
| MFA Service | `auth.enabled=true` | `auth.secretName` / `auth.secretKey` | `mfa-service-secrets/MFA_TOTP_ENCRYPTION_KEY` |
| Payment Service | `auth.enabled=true` | `auth.secretName` / `auth.secretKey` | None |
| Transaction Service | `auth.secrets.enabled=true` | `auth.secrets.name` / `auth.secrets.jwtSecretKey` | None |

In SIT, Auth Service, Transaction Service, API Gateway, MFA Service, and
Payment Service all consume `auth-service-secrets/jwt-secret` through
`AUTH_JWT_SECRET`.

Config Repo supplies the nonsecret issuer and scope configuration; it does not
contain the signing key. Auth Service's `fixture-password-hash` is a BCrypt
hash for the synthetic fixture and must not be replaced with or accompanied by
the fixture's source password. This runbook owns only `jwt-secret` and does not
provision the MFA TOTP encryption key.

## Preconditions

Confirm the local cluster and namespace before creating anything:

```bash
kubectl config current-context
kubectl get namespace digital-bank-sit
```

The context must be `docker-desktop`. Stop if another context is active. Secret
commands must not be run with shell tracing or verbose Kubernetes HTTP logging.

## Generate the Initial Secret

The following command generates a synthetic 256-bit key, stores only its base64
representation in Kubernetes, and removes the temporary file on exit. The value
does not appear in shell history, process arguments, command output, or a
rendered manifest.

Run this only when `auth-service-secrets` does not already exist. It fails
instead of silently replacing an existing key.

```bash
(
  set -eu
  set +x
  umask 077

  if kubectl get secret auth-service-secrets \
    --namespace digital-bank-sit >/dev/null 2>&1; then
    printf '%s\n' 'auth-service-secrets already exists; this runbook will not replace it.'
    exit 1
  fi

  secret_file="$(mktemp)"
  trap 'rm -f "$secret_file"' EXIT HUP INT TERM

  openssl rand -base64 32 | tr -d '\n' >"$secret_file"

  kubectl create secret generic auth-service-secrets \
    --namespace digital-bank-sit \
    --from-file=jwt-secret="$secret_file"
)
```

Do not use `--from-literal` with command substitution. That form can expose the
secret through shell history or process inspection. Do not redirect
`kubectl get secret -o yaml` or `-o json` output into logs or issue comments.

## Verify Without Printing the Value

List data key names without rendering their values:

```bash
kubectl get secret auth-service-secrets \
  --namespace digital-bank-sit \
  --output go-template='{{range $key, $value := .data}}{{printf "%s\n" $key}}{{end}}'
```

The output must include `jwt-secret`. Check the application-level decoded key
length without printing the key:

```bash
decoded_bytes="$(
  kubectl get secret auth-service-secrets \
    --namespace digital-bank-sit \
    --output jsonpath='{.data.jwt-secret}' |
    base64 -D |
    base64 -D |
    wc -c |
    tr -d ' '
)"

test "$decoded_bytes" -ge 32
printf 'jwt-secret is present and decodes to %s bytes\n' "$decoded_bytes"
unset decoded_bytes
```

The two decode operations are intentional: the first removes Kubernetes Secret
encoding and the second validates the application's base64 key format. `-D` is
the macOS `base64` decode option used by local SIT.

After the five secured workloads exist, verify that their pod templates
reference the same Secret name and key. This command inspects references only
and suppresses the JSON output:

```bash
kubectl get deployments api-gateway auth-service mfa-service payment-service transaction-service \
  --namespace digital-bank-sit \
  --output json |
  jq -e '
    [
      .items[]
      | .spec.template.spec.containers[]
      | .env[]?
      | select(.name == "AUTH_JWT_SECRET")
      | .valueFrom.secretKeyRef
    ] as $references
    | ($references | length == 5)
      and ($references | all(
        .name == "auth-service-secrets" and .key == "jwt-secret"
      ))
  ' >/dev/null && printf '%s\n' 'All five secured SIT workloads use the shared JWT Secret contract.'
```

## Rollout

Do not roll out secured consumers until the application revisions, Config Repo
revision, Helm values, database prerequisites, and required Secrets are
available. Current SIT prerequisites include the `auth_service` and
`mfa_service` PostgreSQL databases, the `postgres` Secret,
`auth-service-secrets`, and `mfa-service-secrets` when MFA is enabled.

1. Validate affected Helm charts with their repository-owned lint or render
   checks.
2. Upgrade Auth Service and wait for its rollout to become ready.
3. Upgrade MFA Service, Payment Service, Transaction Service, and API Gateway,
   waiting for each rollout to become ready.
4. Run the reference check above and the service health checks.
5. Obtain a synthetic SIT token through Auth Service and exercise the approved
   internal workflow, including the protected gateway routes.

Use `kubectl rollout status` for each deployment. No arbitrary sleep is needed;
the next step starts only after the preceding rollout reports success.

## Rotation Boundary

This runbook does not define a key-rotation procedure. The current SIT contract
has one shared active HMAC secret and no key identifier or overlap mechanism.
Changing `jwt-secret` therefore requires a separately approved, coordinated
change that updates and restarts all five consumers. Do not patch or rotate the
Secret using this runbook.

## Cleanup

Deleting the Secret does not remove the value already injected into running
containers. Existing pods keep it until replacement; newly scheduled pods fail
when the required Secret or key is absent.

Scale down or uninstall Auth Service and Transaction Service before cleanup,
then remove only the local SIT Secret:

```bash
kubectl delete secret auth-service-secrets \
  --namespace digital-bank-sit
```

Recreate it after resetting Docker Desktop Kubernetes. Never copy a local SIT
key, token, or Secret manifest into another environment.

## UAT and PROD Boundary

UAT and PROD secret delivery, identity integration, coordinated key rotation,
and production rollout are outside this local SIT runbook and require a
separately approved architecture and operational procedure. Never copy a local
SIT key, token, or Secret manifest into another environment.
