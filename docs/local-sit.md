# Local Kubernetes SIT Guide

This guide is the platform-level path for deploying and verifying the Digital Bank Java integrated local SIT environment on Docker Desktop Kubernetes. It identifies the required order and the common verification points; each repository README remains the source of detailed service-specific build, Helm, and troubleshooting instructions.

## Scope and Boundaries

Local SIT is an integrated developer environment. It runs on the local `docker-desktop` Kubernetes context and uses the `digital-bank-sit` namespace for banking workloads.

It is not a substitute for UAT or production. UAT and PROD infrastructure, managed services, deployment pipelines, access controls, and operational procedures belong to **Sprint 7 - AWS UAT and Production Readiness**. Do not use this guide to expose banking services, PostgreSQL, Kafka, AKHQ, or Swagger UI to a public network.

Local tooling is deliberately separate from banking runtime workloads:

- `digital-bank-sit`: PostgreSQL, Kafka, Config Server, API Gateway, and banking services.
- `digital-bank-tooling`: AKHQ, used only for local Kafka inspection.
- Headlamp Desktop: workstation software that uses the active kubeconfig; it is not installed in the cluster.

## Prerequisites

Clone the active platform repositories under one parent directory, including [`config-repo`](https://github.com/digital-bank-java/config-repo), [`infra-sit`](https://github.com/digital-bank-java/infra-sit), [`config-server`](https://github.com/digital-bank-java/config-server), [`api-gateway`](https://github.com/digital-bank-java/api-gateway), [`customer-service`](https://github.com/digital-bank-java/customer-service), [`account-service`](https://github.com/digital-bank-java/account-service), and [`ledger-service`](https://github.com/digital-bank-java/ledger-service).

Install and verify:

- Docker Desktop with Kubernetes enabled.
- `kubectl` configured for the `docker-desktop` context.
- Helm 3 or Helm 4.
- Java 21 for Maven-based service checks and image builds.
- A dedicated repository-scoped, read-only GitHub token for private `config-repo` access when creating the Config Server Kubernetes Secret.

```bash
docker version
kubectl config current-context
kubectl get nodes
helm version --short
java -version
```

The expected Kubernetes context is `docker-desktop`. Stop if a different context is selected.

Do not put GitHub tokens, database passwords, or other secrets in Helm values, repository files, screenshots, or this guide. This guide deliberately does not prescribe credential entry mechanics. Follow the current credential procedures in the Config Server and Infra SIT READMEs instead; the local PostgreSQL procedure is owned by [bug #114](https://github.com/digital-bank-java/.github/issues/114). GitHub CLI authentication is not required for the Config Server Secret flow: it uses the dedicated token and `kubectl`.

## Deployment Order

Run each deployment from its repository root and use its README for the complete commands. The order below prevents a service from starting before the infrastructure and configuration it requires exist.

| Order | Component | Namespace | Why it comes next | Detailed guide |
| --- | --- | --- | --- | --- |
| 1 | PostgreSQL | `digital-bank-sit` | Creates persistent shared local storage and logical service databases. | [`infra-sit` PostgreSQL](https://github.com/digital-bank-java/infra-sit#install-shared-postgresql) |
| 2 | Kafka | `digital-bank-sit` | Supplies the shared local event broker before event-driven services are introduced. | [`infra-sit` Kafka](https://github.com/digital-bank-java/infra-sit#install-shared-kafka) |
| 3 | Config Server | `digital-bank-sit` | Loads service configuration from the private Git-backed `config-repo`. | [`config-server` local SIT](https://github.com/digital-bank-java/config-server#deploy-to-local-sit) |
| 4 | Customer Service | `digital-bank-sit` | Requires Config Server and PostgreSQL. | [`customer-service` local SIT](https://github.com/digital-bank-java/customer-service#deploy-to-local-sit) |
| 5 | Account Service | `digital-bank-sit` | Requires Config Server and PostgreSQL. | [`account-service` local SIT](https://github.com/digital-bank-java/account-service#deploy-to-local-sit) |
| 6 | Ledger Service | `digital-bank-sit` | Requires Config Server and PostgreSQL; Kafka infrastructure is available for later event work. | [`ledger-service` Helm](https://github.com/digital-bank-java/ledger-service#helm) |
| 7 | API Gateway | `digital-bank-sit` | Becomes the workstation entry point after downstream routes are available. | [`api-gateway` local SIT](https://github.com/digital-bank-java/api-gateway#deploy-to-local-sit) |
| 8 | AKHQ | `digital-bank-tooling` | Optional local-only Kafka inspection tooling; it requires Kafka but is not a banking runtime dependency. | [`infra-sit` AKHQ](https://github.com/digital-bank-java/infra-sit#install-akhq-kafka-dashboard) |

For every Helm chart, run its documented `helm lint` and `helm template ... | kubectl apply --dry-run=client -f -` commands before `helm upgrade --install`. After every install or upgrade, wait for the rollout before continuing:

```bash
kubectl rollout status deployment/<service-name> \
  --namespace digital-bank-sit \
  --timeout=180s
```

For PostgreSQL and Kafka, use the StatefulSet form:

```bash
kubectl rollout status statefulset/<postgres-or-kafka> \
  --namespace digital-bank-sit \
  --timeout=180s
```

## Cluster Verification

After the ordered deployment, confirm the expected workload and storage state:

```bash
kubectl get deployments,statefulsets,pods,services,pvc \
  --namespace digital-bank-sit

kubectl get deployments,pods,services \
  --namespace digital-bank-tooling

helm list --all-namespaces
```

The active banking deployments are currently `config-server`, `api-gateway`, `customer-service`, `account-service`, and `ledger-service`. PostgreSQL and Kafka are StatefulSets. A future service is not part of the reproducible SIT baseline until it has a supporting issue, image, Helm chart, runtime configuration, and documented verification path.

## Workstation Access and Verification

Kubernetes Services are `ClusterIP` by design, so they are not directly reachable from the Mac. Use temporary port forwarding for local verification. Keep each port-forward command running in its own terminal and stop it with `Ctrl+C` when finished.

### API Gateway

Forward the normal workstation entry point:

```bash
kubectl port-forward \
  --namespace digital-bank-sit \
  service/api-gateway 8080:8080
```

Then verify gateway and routed health endpoints from another terminal:

```bash
curl --fail http://localhost:8080/actuator/health
curl --fail http://localhost:8080/config-server/actuator/health
curl --fail http://localhost:8080/customer-service/actuator/health
curl --fail http://localhost:8080/account-service/actuator/health
```

If `8080` is already used by a local application or Docker container, choose an unused workstation port such as `18080` and use that same port in every subsequent browser, `curl`, and Insomnia URL:

```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
kubectl port-forward --namespace digital-bank-sit service/api-gateway 18080:8080
```

The API Gateway is the normal local client entry point. Use `http://localhost:8080`, or the alternate forwarded port when `8080` is occupied, as the Insomnia `apiGatewayUrl` value. Do not add service-specific workstation URLs to a shared client environment unless a troubleshooting task explicitly requires a temporary direct port-forward.

### Centralized OpenAPI and Swagger UI

With the gateway port-forward still running, open the internal developer/admin documentation surface:

```text
http://localhost:8080/admin/docs/swagger-ui.html
```

Verify the currently aggregated contracts directly:

```bash
curl --fail http://localhost:8080/admin/docs/customer-service/v3/api-docs
curl --fail http://localhost:8080/admin/docs/account-service/v3/api-docs
```

Ledger Service has no business HTTP API in its bootstrap slice, so it is not yet included in the aggregated Swagger UI. Swagger is an internal developer/admin tool, not a public customer-facing endpoint.

### Ledger Service Direct Health

Ledger Service currently has no API Gateway health route. Verify its deployment with a temporary direct port-forward:

```bash
kubectl port-forward \
  --namespace digital-bank-sit \
  service/ledger-service 18083:8083
```

```bash
curl --fail http://localhost:18083/actuator/health
```

### AKHQ

Forward the local Kafka dashboard from the separate tooling namespace:

```bash
kubectl port-forward \
  --namespace digital-bank-tooling \
  service/akhq 8088:8080
```

Open `http://localhost:8088` to inspect the local SIT Kafka broker, topics, messages, and consumer groups. The ACL view reports that no authorizer is configured because the single-broker local SIT installation intentionally does not implement production Kafka authorization. Do not interpret that local limitation as an acceptable UAT or production security posture.

## Troubleshooting Boundary

Use the following commands before changing deployment state:

```bash
kubectl get pods --namespace digital-bank-sit
kubectl describe pod <pod-name> --namespace digital-bank-sit
kubectl logs deployment/<service-name> --namespace digital-bank-sit
helm status <release-name> --namespace digital-bank-sit
```

If a workstation port is already in use, identify the local process before choosing a different port:

```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
```

Use Headlamp Desktop or `kubectl` to inspect rollout state, logs, events, Services, and persistent volume claims. Restarting or scaling a local SIT workload is acceptable only when it supports a tracked task; do not use the local cluster as a substitute for UAT/PROD rollout procedures.

## Related Documentation

- [`infra-sit` README](https://github.com/digital-bank-java/infra-sit#readme): shared PostgreSQL, Kafka, AKHQ, local storage, and tooling details.
- [`config-server` README](https://github.com/digital-bank-java/config-server#readme): private Git-backed configuration and Config Server Secret setup.
- [`api-gateway` README](https://github.com/digital-bank-java/api-gateway#readme): gateway route and local deployment details.
- [`customer-service` README](https://github.com/digital-bank-java/customer-service#readme): customer API deployment and verification.
- [`account-service` README](https://github.com/digital-bank-java/account-service#readme): account API deployment and verification.
- [`ledger-service` README](https://github.com/digital-bank-java/ledger-service#readme): current Ledger Service bootstrap and Helm details.
- [`config-repo` README](https://github.com/digital-bank-java/config-repo#readme): externalized service runtime configuration.
