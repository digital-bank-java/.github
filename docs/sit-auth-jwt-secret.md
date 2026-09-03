# Shared Auth JWT Secret for Local SIT

This runbook provisions the local-only HMAC signing key shared by Auth Service
and Transaction Service in the `digital-bank-sit` namespace. It is limited to
Docker Desktop SIT. Do not use this procedure for UAT or PROD.

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

The Helm charts use the same contract:

- Auth Service maps `secrets.name` and `secrets.keys.jwtSecret` to
  `AUTH_JWT_SECRET`.
- Transaction Service maps `auth.secrets.name` and
  `auth.secrets.jwtSecretKey` to `AUTH_JWT_SECRET`.

Transaction Service contains this contract on `main` through
[`transaction-service#15`](https://github.com/digital-bank-java/transaction-service/pull/15).
At the time this runbook was written, Auth Service contains the matching chart
change in review in
[`auth-service#5`](https://github.com/digital-bank-java/auth-service/pull/5).
Both deployed charts consume `auth-service-secrets/jwt-secret` after that Auth
Service PR is merged.

Auth Service may also require a separately managed `fixture-password-hash` key
for the synthetic SIT login fixture. This runbook owns only `jwt-secret`. Do not
enable Auth Service secret injection until every key required by its merged
chart has been provisioned. Never store the fixture's source password.

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
    printf '%s\n' 'auth-service-secrets already exists; use the rotation procedure.'
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

After both deployments exist, verify that their pod templates reference the
same Secret name and key. This command inspects references only and suppresses
the JSON output:

```bash
kubectl get deployments auth-service transaction-service \
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
    | ($references | length == 2)
      and ($references | all(
        .name == "auth-service-secrets" and .key == "jwt-secret"
      ))
  ' >/dev/null && printf '%s\n' 'Auth and Transaction use the shared JWT Secret contract.'
```

## Merge and Rollout Order

The runbook may merge independently and requires no waiting period. Do not roll
out the consumers until their application and configuration changes are on
their default branches and the corresponding images have been built.

1. Merge Auth Service integration
   [`auth-service#5`](https://github.com/digital-bank-java/auth-service/pull/5)
   and Auth/MFA SIT configuration
   [`config-repo#32`](https://github.com/digital-bank-java/config-repo/pull/32).
2. Confirm Transaction Service JWT integration
   [`transaction-service#15`](https://github.com/digital-bank-java/transaction-service/pull/15)
   and its SIT configuration
   [`config-repo#38`](https://github.com/digital-bank-java/config-repo/pull/38)
   are merged.
3. Build the exact merged service revisions and validate their Helm charts.
4. Generate `auth-service-secrets/jwt-secret`. Provision any additional
   Auth-only fixture key through its approved local SIT procedure without
   replacing `jwt-secret`.
5. Upgrade Auth Service and wait for its rollout to become ready.
6. Upgrade Transaction Service and wait for its rollout to become ready.
7. Run the safe reference check above, verify both health endpoints, obtain a
   new synthetic SIT token from Auth Service, and call an authorized
   Transaction Service endpoint.

Use `kubectl rollout status` for each deployment. No arbitrary sleep is needed;
the next step starts only after the preceding rollout reports success.

## Rotate the Local SIT Key

The current HMAC contract has one active key and no key identifier or overlap
window. Rotation therefore invalidates existing SIT tokens and requires a
coordinated maintenance window.

1. Stop synthetic test traffic.
2. Generate a replacement key and merge-patch only `jwt-secret`, preserving
   other keys in `auth-service-secrets`.
3. Restart Auth Service and Transaction Service; do not resume traffic until
   both rollouts are ready.
4. Discard existing tokens and obtain new ones.

```bash
(
  set -eu
  set +x
  umask 077

  secret_file="$(mktemp)"
  trap 'rm -f "$secret_file"' EXIT HUP INT TERM

  openssl rand -base64 32 | tr -d '\n' >"$secret_file"

  base64 <"$secret_file" | tr -d '\n' |
    jq -R '{data: {"jwt-secret": .}}' |
    kubectl patch secret auth-service-secrets \
      --namespace digital-bank-sit \
      --type merge \
      --patch-file /dev/stdin
)

kubectl rollout restart deployment/auth-service \
  --namespace digital-bank-sit
kubectl rollout status deployment/auth-service \
  --namespace digital-bank-sit \
  --timeout=180s

kubectl rollout restart deployment/transaction-service \
  --namespace digital-bank-sit
kubectl rollout status deployment/transaction-service \
  --namespace digital-bank-sit \
  --timeout=180s
```

Run the safe verification checks again after rotation. The temporary mismatch
between restarting consumers is why traffic must remain stopped until both are
ready.

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

## UAT and PROD Direction

UAT and PROD must use separate environment-specific secrets in AWS Secrets
Manager. External Secrets Operator, or an equivalent approved controller,
should materialize each secret into the workload namespace using the same
`auth-service-secrets/jwt-secret` Kubernetes contract expected by the charts.

The future cloud implementation must include:

- least-privilege workload identity for reading only the environment's secret;
- encryption and audit controls through AWS KMS, CloudTrail, and Kubernetes
  RBAC;
- no secret values in Git, Helm values, Config Server, CI logs, issue bodies, or
  PR text;
- a versioned rotation design with key identifiers and an overlap period so
  production tokens can transition without an outage;
- independent UAT and PROD keys, rotation schedules, and access policies.

AWS secret delivery remains deferred to Sprint 7. The local commands in this
runbook are not a production secret-management design.
