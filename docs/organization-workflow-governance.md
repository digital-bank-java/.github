# Organization Workflow Governance

This document governs shared automation and repository standards in `digital-bank-java/.github`.

## Repository Role And Access

The `.github` repository is private and is the organization source for shared engineering standards, reusable workflows, and contribution metadata.

Reusable Actions workflows are configured with organization access. Private repositories in `digital-bank-java` may call reusable workflows from this repository. The repository itself must not contain application credentials, personal access tokens, cloud credentials, database passwords, or environment-specific secret values.

Verify reusable-workflow access:

```bash
gh api repos/digital-bank-java/.github/actions/permissions/access
```

The expected result is:

```json
{"access_level":"organization"}
```

## Ownership And Change Control

- The current platform owner, `@ramioooz`, reviews changes to shared standards and automation.
- Changes to `main` are made through a branch and pull request.
- Every pull request must reference its supporting issue and include verification evidence.
- Cross-repository changes must link related pull requests and state merge order when it matters.

GitHub branch protection is not available for this private repository on the current organization plan. Until that changes, pull-request-only changes to `main` are an operational rule rather than a GitHub-enforced rule. When the organization is on a plan that supports it, enable a `main` ruleset that requires pull requests and passing required checks.

## Reusable Workflow Versioning

- Shared workflows live below `.github/workflows/` in this repository.
- Repositories call reusable workflows by an immutable release tag or commit SHA for protected delivery paths; do not depend on an unreviewed mutable branch.
- A workflow behavior change is versioned through a pull request, documented in its release notes, and rolled out deliberately to callers.
- Caller workflows retain only repository-specific inputs and permissions. They do not copy shared implementation logic.

## Permissions And Secrets

- Reusable workflows request the least GitHub permissions required for their job.
- Caller repositories provide only the secrets or permissions explicitly required by the called workflow.
- Use GitHub Secrets, GitHub Environments, or approved external secret managers for sensitive values.
- Logs, pull requests, issue templates, examples, and test fixtures must use placeholders rather than real credentials.
- A workflow that cannot safely proceed because a required secret or permission is absent must fail clearly without exposing sensitive data.

## Current Boundaries

Organization-level workflow access is configured. The reusable Java CI workflow, Java service caller template, reusable GitHub Project status workflow, and its caller template are available. Project status lifecycle behavior and credential setup are documented in [`docs/reusable-project-status.md`](reusable-project-status.md).
