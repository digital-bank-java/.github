# Workstation Debugging Against SIT

## Purpose

SIT is the lowest Digital Bank Java runtime environment. It runs as the integrated platform in the local Docker Desktop Kubernetes cluster. A service can be started from VS Code or Eclipse for breakpoint debugging, but that is a temporary workstation process connected to SIT dependencies, not a separate `LOCAL-DEV` environment.

Use this procedure for one database-backed service at a time. It applies to Customer Service, Account Service, and Ledger Service.

## Preconditions

Confirm the relevant SIT workloads are healthy:

```bash
kubectl get deployment,pod,service --namespace digital-bank-sit
```

Use the gateway port-forward for normal integrated API testing. A local JVM does not register itself as a Kubernetes Service endpoint, so its APIs are called directly on the workstation port while debugging.

## Procedure

1. Scale the deployed copy of the selected service to zero. This prevents duplicate request handling, event consumption, or database writes while the local JVM is active.

```bash
kubectl scale deployment/customer-service \
  --namespace digital-bank-sit \
  --replicas=0
```

2. In separate terminals, forward Config Server and PostgreSQL from SIT:

```bash
kubectl port-forward service/config-server 8888:8888 \
  --namespace digital-bank-sit
```

```bash
kubectl port-forward service/postgres 15432:5432 \
  --namespace digital-bank-sit
```

3. In the service repository, supply the SIT profile and temporary local connection values. The PostgreSQL credentials below are synthetic local SIT credentials read from the Kubernetes Secret; do not use this pattern for UAT or PROD credentials.

```bash
export SPRING_PROFILES_ACTIVE=sit
export CONFIG_SERVER_URL=http://localhost:8888
export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:15432/customer_service
export SPRING_DATASOURCE_USERNAME="$(kubectl get secret postgres --namespace digital-bank-sit --output jsonpath='{.data.POSTGRES_USER}' | base64 -D)"
export SPRING_DATASOURCE_PASSWORD="$(kubectl get secret postgres --namespace digital-bank-sit --output jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -D)"
./mvnw spring-boot:run
```

For Account Service and Ledger Service, change only the database name in `SPRING_DATASOURCE_URL` to `account_service` or `ledger_service`.

4. Debug through the IDE and call the service directly on its workstation port: Customer Service `8081`, Account Service `8082`, or Ledger Service `8083`.

5. Stop the local JVM. Clear the temporary shell variables and stop both port-forwards with `Ctrl+C`.

```bash
unset SPRING_PROFILES_ACTIVE CONFIG_SERVER_URL SPRING_DATASOURCE_URL
unset SPRING_DATASOURCE_USERNAME SPRING_DATASOURCE_PASSWORD
```

6. Restore the Kubernetes deployment and verify its rollout:

```bash
kubectl scale deployment/customer-service \
  --namespace digital-bank-sit \
  --replicas=1

kubectl rollout status deployment/customer-service \
  --namespace digital-bank-sit \
  --timeout=180s
```

## Boundaries

- Full API Gateway routing is validated by deploying the service into SIT and using the API Gateway port-forward.
- Kafka consumer workflows are initially validated in Testcontainers or deployed SIT. The current broker advertises Kubernetes-only DNS, so a workstation JVM cannot consume through a simple port-forward. Cluster-aware interception such as Telepresence can be evaluated later.
- UAT and PROD are future AWS environments. Their credentials must be supplied through approved managed secret delivery, never copied into shell commands or repository files.
