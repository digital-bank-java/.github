# Project Status Caller Template

The `project-status.yml` workflow template is the repository-side entry point for the organization-managed GitHub Project lifecycle workflow. Add the generated caller to a service repository when pull request events should update the matching item in Digital Bank Java Project #1.

## What The Template Does

The caller listens for pull request lifecycle events and delegates the status update to the pinned reusable workflow in `digital-bank-java/.github`. It contains no checkout step, does not execute pull request code, and never merges pull requests.

| Pull request event | Project status behavior |
| --- | --- |
| `opened` or `reopened` | Set the pull request item to `In progress`. |
| `ready_for_review` | Set the pull request item to `In review`. |
| `closed` after merge | Set the pull request item to `Done`. |
| `closed` without merge | Leave the current status unchanged and emit a notice. |

The pull request must already be present in Project #1. The project must contain a single-select `Status` field with the `In progress`, `In review`, and `Done` options.

## Caller Contract

The generated workflow has this shape:

```yaml
name: GitHub Project status

on:
  pull_request_target:
    types: [opened, reopened, ready_for_review, closed]

permissions: {}

jobs:
  project-status:
    uses: digital-bank-java/.github/.github/workflows/project-status.yml@<full-commit-sha>
    permissions: {}
    with:
      project_owner: digital-bank-java
      project_number: 1
      status_field_name: Status
    secrets:
      project_token: ${{ secrets.PROJECT_STATUS_TOKEN }}
```

Replace `<full-commit-sha>` with the 40-character commit SHA that contains the reusable workflow. A mutable branch or tag must not be used for a protected delivery workflow.

## Inputs, Secret, And Permissions

| Item | Required value | Purpose |
| --- | --- | --- |
| `project_owner` | `digital-bank-java` | Organization that owns the project. |
| `project_number` | `1` | Project number to update. |
| `status_field_name` | `Status` | Single-select field to update. |
| `PROJECT_STATUS_TOKEN` | Fine-grained token or GitHub App token with Project read/write access | Authorizes the Project GraphQL lookup and status update. |
| Caller permissions | `{}` | Prevents the caller from granting unnecessary `GITHUB_TOKEN` access. |

Store `PROJECT_STATUS_TOKEN` as a repository or organization secret. Do not place the token in YAML, documentation, issue comments, pull requests, or logs. Do not replace the explicit secret mapping with `secrets: inherit`, because that would expose unrelated secrets to the reusable workflow.

The `pull_request_target` trigger makes the organization secret available for pull requests from forks. This is safe here because the caller only invokes a pinned reusable workflow and neither checks out nor executes pull request content. The reusable workflow receives the Project token as its only secret and uses no repository write permissions.

## Failure Handling

- If `PROJECT_STATUS_TOKEN` is absent, the workflow emits a warning and exits as a safe no-op. It does not make a Project request or change status.
- If the Project, status field, status option, or pull request item cannot be resolved, the workflow fails clearly. It does not merge the pull request or silently report success.
- If a closed pull request was not merged, the workflow succeeds with a notice and preserves the existing Project status.
- If a status update fails, resolve the Project configuration or permission problem and rerun the workflow. Never bypass the failure by adding repository-wide write permissions.

## Adoption Steps

1. Ensure the repository is included in Project #1 and that its pull request items are added to the project.
2. Create `PROJECT_STATUS_TOKEN` with only the required Project read/write scope, or provision an equivalent GitHub App credential.
3. Add the **GitHub Project status** workflow from the organization template chooser.
4. Review the generated file. Confirm `permissions: {}`, the explicit `project_token` mapping, and the full SHA pin.
5. Keep this caller separate from Java verification, OpenAPI validation, deployment, and release workflows.
6. Test an opened, ready-for-review, reopened, merged, and unmerged-closed pull request when practical. Confirm each expected transition and the unmerged-close no-op.
7. Update the SHA through a pull request when the reusable workflow changes. Review lifecycle changes before rolling them out to all service repositories.

The reusable implementation and its broader credential/versioning guidance are documented in [`reusable-project-status.md`](reusable-project-status.md). This caller template is part of the lifecycle work in [#145](https://github.com/digital-bank-java/.github/pull/145) and is tracked as supporting issue [#126](https://github.com/digital-bank-java/.github/issues/126).
