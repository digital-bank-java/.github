# Project Sprint Hierarchy Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the eight Sprint epics the only root items in GitHub Project #1, with all historic work visible below its owning Sprint.

**Architecture:** Retain the Sprint field as the delivery grouping and use GitHub's native parent/sub-issue relationship for the visible hierarchy. Historic epics become children of their owning Sprint. Existing item relationships remain only when parent and child share the Sprint; unparented or cross-Sprint items attach directly to the appropriate Sprint instead of crossing Sprint boundaries.

**Tech Stack:** GitHub Issues, GitHub Projects v2 GraphQL API, GitHub CLI, jq.

## Global Constraints

- Do not delete issues, pull requests, labels, or Project items.
- Keep exactly eight root issues: Sprint epics #18 through #25.
- Preserve relationships that remain inside one Sprint.
- Never place an item below a parent assigned to another Sprint.
- Keep native issue types, Project `Item Type`, statuses, assignees, and Sprint values unchanged.
- Use `.github#17` as the supporting work item and update PR #106 rather than opening an unrelated PR.

---

### Task 1: Build and Review the Parent Migration Candidates

**Files:**
- Create: `docs/project-inventory/2026-08-02-sprint-hierarchy-mapping.csv`

**Consumes:** The pre-migration inventory, existing relationship snapshot, and `2026-08-02-sprint-mapping.csv`.

**Produces:** A recoverable record of current and desired parent relationships for every Project issue.

- [x] **Step 1: Export the current Project items and live parent links**

Run the Project item export and a GraphQL query that returns each issue ID, title, native type, current parent, Sprint, and manual historic Epic classification.

- [x] **Step 2: Calculate every desired parent**

Apply these deterministic rules:

1. Sprint epics #18 through #25 have no parent.
2. Every historic Epic becomes a child of the Sprint epic matching its Sprint value.
3. Existing child relationships remain only when parent and child have the same Sprint.
4. An unparented Story, Task, or Bug becomes a child of the matching same-Sprint historic Epic when one exists.
5. If no same-Sprint historic Epic exists, the item becomes a direct child of its Sprint epic.

- [x] **Step 3: Save the candidate mapping and verify it before mutation**

The CSV must contain issue URL, current parent URL, desired parent URL, Sprint, reason, and whether the relationship changes. Confirm that exactly eight candidate roots remain and that every other Project issue has a desired parent.

### Task 2: Apply the Sprint-Rooted Relationships

**Files:**
- Modify: live GitHub issue parent/sub-issue relationships in Project #1.

**Consumes:** The reviewed candidate mapping.

**Produces:** A Project hierarchy with only Sprint epics at the root.

- [x] **Step 1: Attach historic Epics to their Sprint parents**

Use the GitHub GraphQL parent/sub-issue mutation. Reparent only historic epics, leaving Sprint epics as roots.

- [x] **Step 2: Attach remaining unparented or cross-Sprint items**

Apply the candidate desired parent relation. Do not mutate items whose current parent already equals the desired parent.

- [x] **Step 3: Capture a post-mutation relationship snapshot**

Export the relationship tree after all changes, including parent URLs and the immediate sub-issues for each issue.

### Task 3: Verify the Tree and Update the Handoff

**Files:**
- Modify: `docs/project-handoff.md`

**Consumes:** The post-mutation relationship snapshot and hierarchy mapping.

**Produces:** Evidence that the Project is a Sprint-rooted hierarchy.

- [x] **Step 1: Verify the root set**

Confirm the only root issue titles are the eight Sprint epics #18 through #25.

- [x] **Step 2: Verify relationship safety**

Confirm every non-root issue has a parent in the same Sprint, and no cycle exists.

- [x] **Step 3: Append the hierarchy result to the handoff**

Record the hierarchy rules, root-count verification, and the link to the hierarchy mapping CSV.

- [ ] **Step 4: Commit and update PR #106**

Run `git diff main...HEAD --check`, commit the mapping, plan/spec amendment, and handoff update, then push the existing branch.

## Self-Review

- Spec coverage: root-only Sprint epics, same-Sprint parent safety, historic epic preservation, and direct-child fallback are represented.
- Placeholder scan: no unresolved execution decisions remain.
- Consistency: each desired parent is derived from the already authoritative Sprint value.
