# SIT Transfer Acceptance Fixture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task by task.

**Goal:** Provide a guarded, idempotent, local-SIT-only fixture and acceptance runner that can complete the remaining Sprint 3 transfer-saga runtime evidence without public balance mutation APIs or persistent credentials.

**Architecture:** An opt-in Helm Job seeds a reconciled synthetic opening position across customer, account, and ledger databases. A short-lived Auth Secret override permits a normal JWT login. A disabled SIT-only Ledger consumer switch generates one governed failure fact so release compensation can be exercised. A runner orchestrates the fixture, real gateway traffic, controlled Kafka offset replay, evidence collection, and cleanup.

**Tech Stack:** Kubernetes, Helm, PostgreSQL 16, Bash, Spring Boot, Spring Kafka, Maven.

**Spec:** `docs/superpowers/specs/2026-09-09-sit-transfer-acceptance-fixture-design.md`

## Global Constraints

- Scope is local Docker Desktop SIT only: context `docker-desktop`, namespace `digital-bank-sit`.
- Do not add, expose, or document a public direct balance-change API.
- Do not read, print, commit, or rotate real secret values, credentials, JWTs, or passwords.
- Do not deploy the fixture or fault injection enabled by default.
- Do not manually update a database from a workstation; all synthetic data comes from the controlled, idempotent Job.
- Do not forge Kafka events or replay DLQ records. Duplicate delivery uses only Kafka consumer-group offset reset of an original fact.
- Keep Java tests focused on the new load-bearing SIT guard only; do not add redundant unit-test suites.
- Every PR references `.github#261`, and changes are submitted as PRs rather than committed to `main`.

## Task 1: Add the controlled SIT seed chart

**Repository:** `infra-sit`

**Files:**
- Create: `helm/transfer-acceptance-fixture/Chart.yaml`
- Create: `helm/transfer-acceptance-fixture/values.yaml`
- Create: `helm/transfer-acceptance-fixture/values-sit.yaml`
- Create: `helm/transfer-acceptance-fixture/templates/_helpers.tpl`
- Create: `helm/transfer-acceptance-fixture/templates/configmap.yaml`
- Create: `helm/transfer-acceptance-fixture/templates/job.yaml`
- Modify: `README.md`
- Modify: `AGENTS.md`

**Steps:**
1. Follow the repository’s existing PostgreSQL Job conventions.
2. Render nothing unless `fixtures.enabled` is explicitly true.
3. Use fixed synthetic UUIDs and marker values for two customers, source and destination AED accounts, an external clearing account, and a balanced 1,000.0000 AED opening ledger entry.
4. Use `INSERT ... ON CONFLICT DO NOTHING`; never issue an update or delete against financial tables.
5. Reference the existing `postgres` Secret without emitting its values.
6. Add a documented explicit invocation and query-only verification commands.
7. Validate with `helm lint` and both disabled and enabled `helm template` renders.

## Task 2: Add the SIT-only ledger failure switch

**Repository:** `ledger-service`

**Files:**
- Modify: `src/main/java/com/digitalbank/ledgerservice/adapter/in/kafka/LedgerPostingRequestedConsumer.java`
- Create or modify: configuration properties class under `src/main/java/com/digitalbank/ledgerservice/configuration/`
- Modify: `src/main/resources/application.yml` only if a default binding is required by established conventions
- Modify: `README.md`
- Add one focused test only if the existing test pattern supports proving that the switch is rejected outside SIT and records the normal governed failure path.

**Steps:**
1. Bind an acceptance-fixture configuration object with `enabled=false` and blank request ID defaults.
2. Reject enabled configuration unless the Spring `sit` profile is active.
3. In the Kafka consumer, after contract validation and before posting, match exactly the configured request ID and call the normal failure-decision input port with `INTERNAL_ERROR`.
4. Persist the source event through the existing inbox path so redelivery remains deduplicated.
5. Do not add any controller, REST route, or generic business fault behavior.
6. Run the narrow test(s) and `./mvnw verify`.

## Task 3: Create the guarded SIT acceptance runner and documentation

**Repository:** `infra-sit`

**Files:**
- Create: `scripts/run-transfer-saga-acceptance.sh`
- Create: `docs/transfer-saga-acceptance.md`
- Modify: `README.md`

**Steps:**
1. Validate context and namespace before mutations.
2. Install and wait for the explicit fixture Job, then verify fixture identifiers using read-only SQL.
3. Create the temporary Auth Secret with a generated BCrypt password hash, patch only the two fixture reference environment variables, and use a cleanup trap to restore/delete.
4. Execute normal gateway requests for complete and insufficient-funds flows.
5. Temporarily apply the exact Ledger environment override for the compensation case, wait for rollout, execute the case, then restore it.
6. Use a targeted inactive Transaction Service consumer-group offset reset to replay one real terminal fact; restore the deployment and verify terminal-state idempotency.
7. Store redacted, non-sensitive evidence under a gitignored local directory. Never write raw credentials or JWTs to it.
8. Add a dry-run/help mode so the script can be inspected without mutating SIT.

## Task 4: Update organization handoff and project evidence

**Repository:** `.github`

**Files:**
- Modify: `docs/project-handoff.md`
- Add: `docs/superpowers/specs/2026-09-09-sit-transfer-acceptance-fixture-design.md`
- Add: this plan

**Steps:**
1. Record the approved controlled fixture boundary and its temporary nature.
2. Cross-link the infra and ledger PRs and state their required merge order: Ledger switch before runner execution; infra chart and runner can merge independently.
3. After runtime execution, add a concise redacted evidence comment to `.github#261` and update Sprint 3 closeout status.

## Task 5: SIT execution and cleanup

**Repository:** operational only; no source changes unless a verified defect is found.

**Steps:**
1. Build and roll out the merged Ledger image plus the controlled infra chart.
2. Run the acceptance runner once against local SIT.
3. Verify all four scenarios with query-only database checks and service health checks.
4. Confirm the temporary Auth Secret is absent and Auth/Ledger deployments have their original fixture references and no acceptance override.
5. Add redacted evidence to `.github#261`, close it, then close Sprint 3 descendants only when all exit criteria are evidenced.

## Review Checklist

- Fixture chart is disabled by default and contains no password or token.
- SQL is convergent and append-only for ledger data.
- Fault switch is unavailable outside SIT and has no HTTP surface.
- Runner has reliable cleanup on failure or interruption.
- Kafka duplicate test is original-record redelivery, not manual event production.
- All new or changed issues remain native children in Sprint 3.
