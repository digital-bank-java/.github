# Public Release Review And Organization Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Review the authoritative mainline of every Digital Bank Java repository, fix confirmed public-release blockers through focused PRs, and publish an accurate GitHub organization introduction page.

**Architecture:** Review work is split by risk boundary: Java domain/security services, gateway/configuration, and infrastructure/organization automation. The public profile is owned by `.github/profile/README.md` and links to verified repository documentation without duplicating private operational data.

**Tech Stack:** Java 21, Spring Boot, Maven Wrapper, PostgreSQL/Flyway, Kafka, Kubernetes/Helm, GitHub Actions, Markdown, GitHub CLI.

**Spec:** `docs/superpowers/specs/2026-09-12-public-release-review-design.md` and `docs/superpowers/specs/2026-09-12-public-release-review-scope.md`

## Global Constraints

- Review `origin/main` after fetching each repository.
- Never change repository visibility, branch protection, secrets, or organization settings in this work.
- AWS/UAT/PROD and SonarQube remain deferred.
- Do not add broad or redundant tests; add a test only as load-bearing proof of a confirmed defect.
- Every code or documentation change uses an isolated branch and a pull request; never merge directly to `main`.
- Public documentation must contain no credentials, tokens, customer data, private endpoints, internal hostnames, or unverifiable runtime claims.

### Task 1: Establish Review Evidence Matrix

**Files:**
- Create: `docs/review/public-release-review-2026-09.md`
- Inspect: all repository `origin/main` trees and their `AGENTS.md`, `README.md`, CI, Maven, Helm, and runtime configuration files

**Interfaces:**
- Consumes: the two approved review specifications.
- Produces: a dated evidence matrix with repository commit, commands run, findings, severity, and disposition.

- [ ] **Step 1: Fetch and record authoritative commits**

Run from each repository:

```bash
git fetch origin main
git rev-parse origin/main
```

Record the resulting commit SHA and the repository baseline files inspected. Do not use stale local branches as review evidence.

- [ ] **Step 2: Run repository hygiene scans**

Run the existing repository-scoped scans:

```bash
git grep -n -E 'TODO|FIXME|System\.out|printStackTrace' origin/main -- ':!*.md' ':!*.json' ':!*.yml' ':!*.yaml' || true
git grep -n -i -E 'password|secret|token|private key|BEGIN .* KEY' origin/main -- ':!mvnw*' ':!*.md' || true
git diff --check origin/main
```

Classify each match as expected implementation, test-only fixture, documentation example, or finding. Do not report generated wrapper code as a secret finding.

- [ ] **Step 3: Record verification commands and evidence**

For every Java repository record whether the existing Maven `verify` command was run against an isolated `origin/main` worktree, its result, and any environment limitation. For infrastructure and `.github`, record Helm/template, contract, workflow, and Markdown checks that already exist.

- [ ] **Step 4: Commit the evidence matrix**

```bash
git add docs/review/public-release-review-2026-09.md
git commit -m "docs: record public release review evidence"
```

### Task 2: Review Financial Integrity And Event Delivery

**Repositories:** `account-service`, `ledger-service`, `transaction-service`, `payment-service`, `notification-service`, `mfa-service`

**Files:**
- Inspect: `src/main/java/**`, `src/main/resources/db/migration/**`, `src/test/**`, `pom.xml`, `helm/**`
- Modify only confirmed defects in the affected repository
- Test only the specific invariant that demonstrates the defect

**Interfaces:**
- Consumes: event contracts under `.github/docs/contracts/` and service-owned persistence schemas.
- Produces: focused fix PRs or a documented no-finding result for each service.

- [ ] **Step 1: Inspect transaction boundaries and immutable data paths**

Verify that ledger postings/reversals are append-only, posting idempotency is backed by a database uniqueness constraint, account balance changes are driven by workflow events, payment idempotency is persisted, and inbox/outbox rows are written in the same transaction as their business state.

- [ ] **Step 2: Inspect replay, lease, and concurrency behavior**

Verify that identical events are safe to replay, conflicting request keys fail closed, expired outbox leases can be reclaimed, and concurrent duplicate commands cannot create two financial facts. Compare the implementation with existing tests before adding any new test.

- [ ] **Step 3: Inspect contract validation and quarantine paths**

Verify event metadata, binding fields, expiry, subject, amount, currency, and correlation validation. Confirm malformed or mismatched messages cannot create a reservation, posting, notification, or transfer state transition.

- [ ] **Step 4: Create focused fix branches only for confirmed findings**

For each finding, create one repository branch, add the smallest defect test when necessary, implement the fix, run the repository’s existing `./mvnw verify`, and open one PR linked to the review issue. Do not refactor unrelated files.

### Task 3: Review Security And Public Exposure

**Repositories:** `auth-service`, `mfa-service`, `api-gateway`, `customer-service`, `account-service`, `transaction-service`, `payment-service`, `ledger-service`

**Files:**
- Inspect: security configurations, JWT decoders, controllers, Helm values/templates, Config Server properties, and OpenAPI annotations
- Modify only confirmed exposure or secret-handling defects

**Interfaces:**
- Consumes: platform security boundaries in `docs/security-and-transfer-rail.md` and `docs/platform-conventions.md`.
- Produces: focused security fix PRs or evidence that protected routes, internal scopes, and secret injection are correct.

- [ ] **Step 1: Verify protected route matrices**

Check that login and health are intentionally public, customer/account routes require authentication, internal transfer/payment/ledger routes require their specific scopes, MFA routes require the MFA scope, and administrative documentation is restricted.

- [ ] **Step 2: Verify token and session validation**

Check signature algorithm/key length, issuer, expiration, session revocation, single-session behavior, and that fixture credentials are opt-in and supplied through runtime secrets rather than committed values.

- [ ] **Step 3: Scan deployment and configuration defaults**

Check that production-sensitive features fail closed when required configuration is absent, local fixture switches are SIT-only, and no Helm values or Config Repo files contain real credentials or private endpoints.

- [ ] **Step 4: Verify public API documentation boundaries**

Confirm ledger posting, payment instruction, transfer workflow, and administrative documentation routes are not accidentally presented as public customer APIs.

### Task 4: Review Deployment, CI, And Configuration

**Repositories:** `config-repo`, `config-server`, `infra-sit`, `api-gateway`, `.github`

**Files:**
- Inspect: `helm/**`, `values*.yaml`, Kubernetes manifests, GitHub Actions workflows, reusable workflow scripts, Config Repo profiles, `Dockerfile`, and README commands
- Modify only confirmed deployment or CI defects

**Interfaces:**
- Consumes: local SIT deployment order in `docs/local-sit.md` and service-specific READMEs.
- Produces: focused infrastructure/CI PRs or evidence of no release-blocking findings.

- [ ] **Step 1: Validate manifest rendering and secret references**

Run each existing `helm lint` and `helm template` check with SIT values. Confirm probes, service ports, image tags, Config Server URLs, Kafka DNS, PostgreSQL secret references, and namespace boundaries are coherent.

- [ ] **Step 2: Review CI job scope**

Check that each repository has only the necessary quality jobs, unit and integration phases are not accidentally duplicated, secrets are scoped, fork behavior is safe, and reusable workflows do not require unrelated credentials.

- [ ] **Step 3: Validate event/API contracts**

Run the existing AsyncAPI and OpenAPI workflow tests. Confirm contract references, topics, event versions, and gateway documentation paths match the current service implementation.

- [ ] **Step 4: Open focused fix PRs only when required**

Run `git diff --check`, repository checks, and the smallest relevant verification before opening each PR. Do not add a new CI job to prove an existing workflow that already covers the behavior.

### Task 5: Create Organization Profile README

**Files:**
- Create: `.github/profile/README.md`
- Inspect: `docs/platform-architecture.md`, `docs/platform-conventions.md`, `docs/local-sit.md`, `docs/asyncapi-contracts.md`, `docs/security-and-transfer-rail.md`, and every service README

**Interfaces:**
- Consumes: verified architecture and repository documentation.
- Produces: the GitHub organization introduction page, readable without private organization context.

- [ ] **Step 1: Write the platform overview**

Include purpose, current state, architecture principles, and the distinction between customer-facing APIs, internal workflows, and event-driven financial facts.

- [ ] **Step 2: Add the repository map**

Document each repository’s responsibility and link to its README. Include `.github`, Config Server, Config Repo, API Gateway, Customer, Account, Ledger, Transaction, Auth, MFA, Payment, Notification, and Infra SIT.

- [ ] **Step 3: Add interaction and event-flow documentation**

Explain API Gateway entry, Config Server configuration, PostgreSQL ownership, Kafka delivery, reservation/ledger/transaction responsibilities, outbox/inbox delivery, idempotency, and append-only reversals. Link to the authoritative diagrams and AsyncAPI contracts.

- [ ] **Step 4: Add safe local SIT usage**

Document prerequisites, `digital-bank-sit` versus `digital-bank-tooling`, API Gateway port-forward usage, and where detailed runbooks live. Explicitly state that credentials, OTPs, private endpoints, and production data must never be committed.

- [ ] **Step 5: Add current/deferred status**

State that local SIT core delivery is complete, while AWS/UAT/PROD and SonarQube are deferred. Avoid claiming public deployment or production readiness.

- [ ] **Step 6: Verify public-readability and links**

Run `git diff --check`, scan the profile for secret-shaped values and private hostnames, and validate every relative link against the repository tree. Commit and open a dedicated PR.

### Task 6: Review Closeout And Handoff

**Files:**
- Modify: `docs/project-handoff.md`
- Modify: `docs/review/public-release-review-2026-09.md`
- Modify: relevant GitHub Project items only when a finding creates or closes tracked work

**Interfaces:**
- Consumes: all review PR links, verification output, and the final profile PR.
- Produces: a dated review closeout with no unsupported “all clear” claim.

- [ ] **Step 1: Record findings and dispositions**

For each review area, record fixed PR, accepted risk, deferred issue, or no finding with evidence. Do not record a clean review until all repositories have been inspected.

- [ ] **Step 2: Run final changed-repository verification**

Run the repository-specific Maven/Helm/contract checks for every changed PR and `git diff --check` for all documentation changes.

- [ ] **Step 3: Open the final handoff PR**

Link all review and profile PRs, list remaining deferred scope, and confirm that repository visibility and branch-protection changes were not performed.
