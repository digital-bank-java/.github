# GitHub Project Outcome-Based Sprint Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure Digital Bank Java Platform Project #1 into outcome-based Sprint 0 through Sprint 7 while retaining all issue and delivery evidence.

**Architecture:** GitHub Project #1 remains the cross-repository delivery source of truth. A new `Sprint` single-select field assigns every Project item to one outcome-based sprint. Eight sprint epics in `digital-bank-java/.github` define cross-repository outcomes and exit criteria. Existing repository issues, pull requests, labels, and parent/sub-issue relationships are preserved.

**Tech Stack:** GitHub Projects v2, GitHub Issues, GitHub CLI (`gh`), GitHub GraphQL API.

## Global Constraints

- Do not delete existing issues, pull requests, labels, or parent/sub-issue relationships.
- Every issue, including historical Done work, must have the correct native GitHub Issue Type.
- Use `EPIC:`, `STORY:`, `TASK:`, and `BUG:` prefixes for newly created planning items.
- Assign active `In progress` tasks to `ramioooz`.
- Associate bugs with the discovery sprint and apply the `bug` label.
- Retain `Status`, `Sprint`, `Item Type`, `Service`, `Priority`, `Size`, `Repository`, `Parent issue`, `Sub-issues progress`, and `Linked pull requests` fields.
- Retire `Phase`, `Slice`, manual `Epic`, and `Delivery Priority` only after their information is represented by retained fields.

## File Structure

| File | Responsibility |
| --- | --- |
| `docs/superpowers/specs/2026-08-02-project-sprint-restructure-design.md` | Approved sprint model and migration rules. |
| `docs/superpowers/plans/2026-08-02-project-sprint-restructure.md` | Migration execution record. |
| `docs/project-inventory/2026-08-02-before-sprint-restructure.json` | Pre-migration Project backup. |
| `docs/project-inventory/2026-08-02-sprint-mapping.csv` | Reviewed item-to-sprint audit trail. |
| `docs/project-handoff.md` | Persistent record of the new planning model. |

### Task 1: Capture a Recoverable Project Inventory

**Files:**
- Create: `docs/project-inventory/2026-08-02-before-sprint-restructure.json`

**Consumes:** Project ID `PVT_kwDOEWKGsc4BaNxz`.

**Produces:** Project item IDs, URLs, repositories, field values, and relationships before mutation.

- [ ] **Step 1: Export all Project items and field values**

Run `gh project item-list 1 --owner digital-bank-java --limit 500 --format json > docs/project-inventory/2026-08-02-before-sprint-restructure.json`.

- [ ] **Step 2: Verify the inventory**

Run `jq '.items | length' docs/project-inventory/2026-08-02-before-sprint-restructure.json`. Expected: a positive count matching the Project item total.

- [ ] **Step 3: Commit the snapshot**

Run `git add docs/project-inventory/2026-08-02-before-sprint-restructure.json && git commit -m "docs: snapshot project before sprint migration"`.

### Task 2: Add the Sprint Field and Create Sprint Epics

**Files:**
- Modify: `docs/project-handoff.md`

**Consumes:** The eight sprint definitions from the approved design.

**Produces:** `Sprint` Project field and eight `.github` `EPIC:` issues.

- [ ] **Step 1: Create the Sprint field**

Run `gh project field-create 1 --owner digital-bank-java --name Sprint --data-type SINGLE_SELECT --single-select-options 'Sprint 0 - Platform Foundation and Local SIT,Sprint 1 - Customer and Account Foundation,Sprint 2 - Ledger Foundation,Sprint 3 - Internal Transfers and Event Consistency,Sprint 4 - Secure Customer Access and Step-Up Authorization,Sprint 5 - Payment Rails and Notifications,Sprint 6 - Operational Resilience and Observability,Sprint 7 - AWS UAT and Production Readiness'`.

- [ ] **Step 2: Create eight Epic-typed `.github` issues**

Create these exact titles, each with `Outcome`, `Scope`, and `Exit Criteria` copied from the approved design:

```text
EPIC: Sprint 0 - Platform Foundation and Local SIT
EPIC: Sprint 1 - Customer and Account Foundation
EPIC: Sprint 2 - Ledger Foundation
EPIC: Sprint 3 - Internal Transfers and Event Consistency
EPIC: Sprint 4 - Secure Customer Access and Step-Up Authorization
EPIC: Sprint 5 - Payment Rails and Notifications
EPIC: Sprint 6 - Operational Resilience and Observability
EPIC: Sprint 7 - AWS UAT and Production Readiness
```

- [ ] **Step 3: Add each epic to Project #1 and apply the matching Sprint value**

Verify that its colored native Epic type and Sprint field are visible in the Project table.

### Task 3: Audit and Map Existing Project Items

**Files:**
- Create: `docs/project-inventory/2026-08-02-sprint-mapping.csv`

**Consumes:** Pre-migration snapshot and sprint definitions.

**Produces:** Complete mapping audit, converted planning issues, correct native Issue Types, and Project Sprint assignments.

- [ ] **Step 1: Create the mapping table before modifying Project items**

Use exactly these CSV columns:

```text
project_item_id,issue_url,repository,title,item_type_before,item_type_after,status_before,status_after,sprint,parent_issue,reason
```

- [ ] **Step 2: Convert every Project DraftIssue to `digital-bank-java/.github`**

Use GitHub GraphQL mutation `convertProjectV2DraftIssueItemToIssue` with the Project item ID and `.github` repository ID. Preserve the title, body, Project item identity, and field values. The conversion is required because DraftIssues cannot hold a native GitHub Issue Type.

- [ ] **Step 3: Correct missing or incorrect native Issue Type**

Use this mapping: `EPIC:` to `Epic`, `STORY:` to `Story`, `TASK:` to `Task`, and `BUG:` to `Bug`. For historic unprefixed issues, preserve the title unless a correction is needed for clarity, and assign type based on its actual role.

- [ ] **Step 4: Assign a Sprint and accurate Status to every Project item**

Use `Backlog` for unselected work, `Ready` for defined startable work, `In progress` for active owned work, `In review` for open reviewable PR work, and `Done` for accepted closed deliverables.

- [ ] **Step 5: Verify parent relationships survived**

Export Project items again and compare each retained issue URL, repository, and `Parent issue` to the pre-migration snapshot.

- [ ] **Step 6: Commit the mapping**

Run `git add docs/project-inventory/2026-08-02-sprint-mapping.csv && git commit -m "docs: map project work to outcome-based sprints"`.

### Task 4: Validate the Board and Retire Only Duplicates

**Files:**
- Modify: `docs/project-handoff.md`

**Consumes:** Complete Sprint mapping.

**Produces:** A minimal Project field model and a handoff record of the migration.

- [ ] **Step 1: Verify Project filtering**

Verify filters for `Sprint = Sprint 0 - Platform Foundation and Local SIT`, `Status = In progress`, `Item Type = Task`, `Service = transaction-service`, and `Priority = P0`.

- [ ] **Step 2: Compare redundant fields to retained fields**

Confirm `Phase`, `Slice`, manual `Epic`, and `Delivery Priority` contain no unique delivery information after the migration.

- [ ] **Step 3: Delete only verified-redundant fields**

Use `gh project field-delete` only after documenting the field name, field ID, existing values, and retained replacement.

- [ ] **Step 4: Append the final result to the handoff**

Record active sprint, epic links, retained and deleted fields, and intentionally deferred items.

- [ ] **Step 5: Commit the handoff update**

Run `git add docs/project-handoff.md && git commit -m "docs: record sprint migration completion"`.

### Task 5: Review and Publish the Migration

**Files:**
- Modify: `docs/project-handoff.md`

**Consumes:** Migration evidence from Tasks 1-4.

**Produces:** PR closing `.github#17`.

- [ ] **Step 1: Verify repository hygiene**

Run `git diff main...HEAD --check` and `git status`. Expected: no whitespace errors and a clean working tree.

- [ ] **Step 2: Push and create a reviewable pull request**

Push `chore/github-project-sprint-restructure`; create a `.github` PR titled `chore: restructure project around outcome-based sprints` with `Closes #17`. The summary must include inventory coverage, all mapped Sprint values, issue-type verification, relationship verification, and any field deletions.

- [ ] **Step 3: Review before merge**

Confirm the PR contains the design, plan, inventory, mapping table, handoff update, and summary of corresponding live Project changes.

## Self-Review

- Spec coverage: inventory, Sprint field, epics, type audit, item mapping, status, field cleanup, handoff, and PR review are covered.
- Placeholder scan: no unresolved implementation placeholders remain.
- Consistency: Sprint labels, fields, and Issue Type rules match the approved design.
