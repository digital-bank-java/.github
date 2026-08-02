# Sprint 0 Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Leave Sprint 0 with only work required to reproduce, operate, and verify the local Kubernetes SIT platform.

**Architecture:** GitHub Project #1 has eight Sprint root epics. Native GitHub parent/sub-issue relationships provide hierarchy; every child Project Sprint must match its direct parent. The `.github` repository keeps audit artifacts in the handoff and hierarchy mapping.

**Tech Stack:** GitHub CLI, GitHub GraphQL ProjectV2 API, GitHub Issues, Markdown, CSV.

## Global Constraints

- Operate on `digital-bank-java` Project #1 only.
- Preserve the eight Sprint roots and their native issue hierarchy.
- Assign `ramioooz` to every item moved to `In progress`.
- Use a native Epic, Story, Task, or Bug type for every created issue.
- Add an evidence comment before closing an issue or marking it Done.
- Do not change application code, infrastructure, or deployed resources.

---

### Task 1: Create an executable reconciliation task

**Files:**
- Modify: `docs/project-handoff.md`
- Create: `.github` native Task under Sprint 0 issue #18

**Produces:** A tracked Task for reconciliation, assigned to `ramioooz`, with native type `Task`, status `In progress`, and Sprint `Sprint 0 - Platform Foundation and Local SIT`.

- [ ] **Step 1: Create the Task**

Title:

```text
TASK: Reconcile Sprint 0 scope and local SIT completion gaps
```

Body:

```text
Objective

Align Sprint 0 with its outcome: a developer can reproduce, operate, and verify the Digital Bank Java platform in local Kubernetes SIT.

Scope

- Move UAT/PROD, SonarQube, and other later-sprint outcomes to their owning Sprint.
- Close stale planning work only with evidence.
- Create the remaining local-SIT documentation task.
- Verify all direct parent/sub-issue relationships remain within one Sprint.

Acceptance criteria

- Sprint 0 active work directly supports local SIT.
- Moved items have an evidence comment, new parent, and matching Sprint value.
- Completed items are not left active.
- Project hierarchy audit reports no cross-Sprint direct relationships.
```

Set parent to `.github#18`, then comment:

```text
Scope approved in the Sprint 0 reconciliation design. Implementation is documented by .github PR #106.
```

- [ ] **Step 2: Append task evidence to the handoff**

Add a dated entry with the created issue URL, the approved boundary, and the reference to PR #106.

- [ ] **Step 3: Commit the handoff update**

```bash
git add docs/project-handoff.md && git commit -m "docs: track Sprint 0 reconciliation"
```

### Task 2: Move deferred work to its owning Sprint

**Files:**
- Modify: `docs/project-inventory/2026-08-02-sprint-hierarchy-mapping.csv`
- Modify: `docs/project-handoff.md`
- Modify: GitHub Issues `.github#1`, `#3`, `#4`, `#40`, and `#67`

**Produces:** SonarQube work under Sprint 6 epic #34; UAT/PROD and production documentation work under Sprint 7 epic #37.

- [ ] **Step 1: Move SonarQube issues to Sprint 6**

Set Project Sprint to `Sprint 6 - Operational Resilience and Observability`, re-parent to `.github#34`, and add matching evidence comments:

| Issue | Comment |
| --- | --- |
| #1 | `Moved from Sprint 0 to Sprint 6 because SonarQube is observability and quality tooling, not a prerequisite for local SIT platform operation.` |
| #3 | `Moved from Sprint 0 to Sprint 6 with the SonarQube strategy. The platform deliberately deferred SonarQube while foundational service delivery proceeds.` |
| #4 | `Moved from Sprint 0 to Sprint 6 because the local SonarQube tooling stack is an observability/quality capability, not a local SIT platform prerequisite.` |

- [ ] **Step 2: Move environment and production documentation to Sprint 7**

Set Project Sprint to `Sprint 7 - AWS UAT and Production Readiness`, re-parent to `.github#37`, and add matching evidence comments:

| Issue | Comment |
| --- | --- |
| #40 | `Moved from Sprint 0 to Sprint 7 because its remaining definition of done is replacing and validating UAT and PROD endpoints after those environments are deployed. LOCAL-DEV and SIT requests remain covered by the gateway diagnostics story.` |
| #67 | `Moved from Sprint 0 to Sprint 7 because its existing scope is Production Documentation. Sprint 0 will retain a focused local-SIT setup and verification document.` |

- [ ] **Step 3: Update audit artifacts**

Change mapping #1, #3, #4 to parent #34 / Sprint 6, and #40, #67 to parent #37 / Sprint 7. Append the five moves to the handoff.

- [ ] **Step 4: Commit the artifacts**

```bash
git add docs/project-inventory/2026-08-02-sprint-hierarchy-mapping.csv docs/project-handoff.md && git commit -m "docs: align deferred work to outcome sprints"
```

### Task 3: Close completed planning work and create the local-SIT guide task

**Files:**
- Modify: `docs/project-handoff.md`
- Modify: GitHub Issues `.github#71` and `.github#72`
- Create: `.github` native Task under Local Deployment epic #35

**Produces:** Delivered draft-promotion work is closed; Sprint 0 receives its missing reproducible local-SIT guide task.

- [ ] **Step 1: Close #71 with evidence**

Post this comment, close #71, and set Project status Done:

```text
Completed. All Project draft items were converted to native repository issues during the outcome-based Sprint migration. Project #1 now has eight Sprint roots, and every tracked issue is reachable through the native parent/sub-issue hierarchy.
```

- [ ] **Step 2: Create the local-SIT documentation Task**

Title:

```text
TASK: Document reproducible local SIT platform setup and verification
```

Body:

```text
Objective

Provide one accurate local-SIT guide for bringing up the platform and proving that deployed foundations are healthy.

Scope

- State local prerequisites: Docker Desktop Kubernetes, kubectl, Helm, Java 21, and GitHub authentication where private configuration access is required.
- Document install or upgrade order for infrastructure, Config Server, API Gateway, and deployed services.
- Document port-forward commands and gateway health, routed service health, Swagger, and AKHQ verification points.
- Link service README files instead of duplicating detailed service commands.
- State that UAT and PROD deployment instructions belong to Sprint 7.

Acceptance criteria

- A new developer can execute the documented local-SIT verification path.
- The guide contains no credentials, tokens, or copied secrets.
- The guide identifies the local tooling boundary and AWS migration boundary.
```

Set parent `.github#35`, native type `Task`, Sprint `Sprint 0 - Platform Foundation and Local SIT`, and status `Backlog`.

- [ ] **Step 3: Clarify README scope**

Post on #72:

```text
Sprint 0 scope is limited to the README baseline and local-SIT guide. Service-specific API and production deployment details remain with their service and Sprint 7 work items.
```

- [ ] **Step 4: Record and commit**

Append #71 closure and local-SIT guide link to the handoff, then commit:

```bash
git add docs/project-handoff.md && git commit -m "docs: record Sprint 0 completion evidence"
```

### Task 4: Verify Project integrity and Sprint 0 scope

**Files:**
- Modify: `docs/project-handoff.md`
- Modify: `docs/project-inventory/2026-08-02-sprint-hierarchy-mapping.csv`

**Produces:** Evidence that active Sprint 0 backlog has no later-sprint outcome or cross-Sprint direct relationship.

- [ ] **Step 1: Export Project state**

```bash
gh project item-list 1 --owner digital-bank-java --limit 500 --format json > /tmp/digital-bank-project-after-sprint-0-reconciliation.json
```

- [ ] **Step 2: Verify moved Sprint values**

```bash
jq -r '.items[] | select(.content.repository == "digital-bank-java/.github" and (.content.number == 1 or .content.number == 3 or .content.number == 4 or .content.number == 40 or .content.number == 67)) | [.content.number, .status, .sprint] | @tsv' /tmp/digital-bank-project-after-sprint-0-reconciliation.json
```

Expected: #1/#3/#4 use Sprint 6; #40/#67 use Sprint 7.

- [ ] **Step 3: Verify active Sprint 0 scope**

```bash
jq -r '.items[] | select(.sprint == "Sprint 0 - Platform Foundation and Local SIT" and .status != "Done") | [.content.repository, .content.number, .content.title, .status] | @tsv' /tmp/digital-bank-project-after-sprint-0-reconciliation.json | sort
```

Require no active Sprint 0 item has UAT, PROD, AWS, SonarQube, rate limiting, circuit breaker, transaction, ledger, or payment as its primary outcome.

- [ ] **Step 4: Run native hierarchy audit**

Require exactly eight roots, every issue reachable from a root, zero missing parents, zero cycles, and zero direct parent relationships crossing Project Sprint values.

- [ ] **Step 5: Record verification, commit, and push**

```bash
git diff --check && git add docs/project-inventory/2026-08-02-sprint-hierarchy-mapping.csv docs/project-handoff.md && git commit -m "docs: verify Sprint 0 project reconciliation" && git push
```

## Plan Self-Review

- **Spec coverage:** The plan implements the approved boundary, five outcome moves, evidence-based closure, local-SIT documentation gap, and integrity checks.
- **Placeholder scan:** The only generated value is the task URL, created in Task 1 before it is written to the handoff.
- **Consistency:** SonarQube work parents to Sprint 6 epic #34; UAT/PROD and production documentation parent to Sprint 7 epic #37; retained Sprint 0 work has same-Sprint ancestry.
