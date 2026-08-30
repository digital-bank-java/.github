# Reusable GitHub Project Status

The organization workflow at `.github/workflows/project-status.yml` updates a pull request's item in GitHub Project #1 from its pull request lifecycle. It is independent of Java verification and OpenAPI contract validation; callers should keep those workflows as separate jobs and checks.

## Caller Contract

Repositories can start with the **GitHub Project status** workflow template. It creates a caller that listens to `pull_request_target` lifecycle events without checking out or executing pull request code:

```yaml
name: GitHub Project status

on:
  pull_request_target:
    types: [opened, reopened, ready_for_review, closed]

permissions: {}

jobs:
  project-status:
    uses: digital-bank-java/.github/.github/workflows/project-status.yml@<pinned-commit-sha>
    permissions: {}
    with:
      project_owner: digital-bank-java
      project_number: 1
      status_field_name: Status
    secrets:
      project_token: ${{ secrets.PROJECT_STATUS_TOKEN }}
```

Replace `<pinned-commit-sha>` with the full commit SHA that contains the reusable workflow. Do not use `main`, a branch, or a mutable tag. Keep the caller separate from Java CI and OpenAPI workflows so each workflow has one responsibility.

The Project must contain the pull request as an item, and its `Status` field must be a single-select field with these options: `In progress`, `In review`, and `Done`.

## Lifecycle Mapping

| Pull request event | Project status behavior |
| --- | --- |
| `opened` or `reopened` | Set to `In progress`. |
| `ready_for_review` | Set to `In review`. |
| `closed` with `merged == true` | Set to `Done`. |
| `closed` without a merge | Leave the current Project status unchanged and emit a notice. Reopening the pull request later sets it to `In progress`. |

The reusable workflow paginates Project items, resolves the configured field and option by name, and fails clearly if the Project, field, option, or pull request item cannot be found. It serializes updates per pull request to avoid lifecycle events overwriting one another out of order.

## Credential And Permission Model

Create an organization secret named `PROJECT_STATUS_TOKEN` in each caller repository or at the organization level. Its value must be a GitHub fine-grained personal access token scoped to the `digital-bank-java` organization with `Projects: read/write`; organization policy or SSO approval must also permit the token. A GitHub App installation token with equivalent Project access may be supplied through the same secret when the organization provisions one.

The reusable workflow accepts this value as the optional `project_token` secret. It uses the token only as `GH_TOKEN` for the two GraphQL requests needed to find and update the Project item. The workflow's `GITHUB_TOKEN` permissions are `{}` and no repository checkout occurs. The caller uses `pull_request_target` so the organization secret can be available for fork pull requests; because the workflow never checks out or executes pull request content, untrusted repository code is not run.

When `PROJECT_STATUS_TOKEN` is missing, the workflow emits a warning and exits without making a Project request or changing status. This is a safe no-op, not a credential failure that exposes secret values. Configure the secret before treating Project status as an operationally required check.

Do not put token values in workflow files, documentation, issue comments, pull requests, or logs. Rotate or revoke the token through the organization credential owner, then update the secret without changing the workflow.

## Adoption And Versioning

1. Confirm Project #1 contains the repository's pull request items and the `Status` options above.
2. Configure `PROJECT_STATUS_TOKEN` with the documented scope.
3. Add the generated caller workflow and review its permissions and pinned SHA.
4. Open, mark ready for review, reopen, merge, and close an unmerged test pull request as appropriate for the repository. Confirm the expected Project transitions and the unmerged close no-op.
5. Update the caller's SHA through a pull request whenever this reusable workflow changes.
