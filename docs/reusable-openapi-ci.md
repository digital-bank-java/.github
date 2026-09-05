# Reusable OpenAPI CI

The organization workflow at `.github/workflows/openapi-contract.yml` validates a generated or committed OpenAPI document, detects breaking changes on pull requests, and uploads the exact contract reviewed by CI as a versioned artifact. It does not require the service to be running.

## Caller Contract

Service repositories adopt the workflow in a separate pull request. The caller must provide:

- `contract_path`: the OpenAPI JSON or YAML document, relative to `working_directory`
- `generate_command`: an optional deterministic command that creates `contract_path`; omit it only when the document is committed and versioned in the service repository
- `working_directory`: the service directory containing the contract or generation command, defaulting to `.`
- `artifact_name`: an optional stable artifact prefix, defaulting to `openapi-contract`

The generation command runs once for the pull request revision and, on pull requests, once for the base revision. It must produce the same path in both checkouts. The workflow executes it without repository secrets and grants only `contents: read`.

Example caller:

```yaml
name: OpenAPI contract

on:
  pull_request:
  push:
    branches:
      - main

permissions:
  contents: read

jobs:
  openapi:
    uses: digital-bank-java/.github/.github/workflows/openapi-contract.yml@<pinned-commit-sha>
    permissions:
      contents: read
    with:
      contract_path: target/openapi/service.yaml
      generate_command: ./mvnw --batch-mode --no-transfer-progress verify -DskipTests
      artifact_name: service-openapi
```

Replace the generation command with the service's actual repeatable contract-generation command. If the build does not generate a file, commit the versioned contract and omit `generate_command`. Do not point this workflow at a runtime URL: contract checks must remain independent of service availability.

Use a full commit SHA in the `uses` reference. The artifact is named `<artifact_name>-<github.sha>` and retained for 30 days, making the reviewed contract independently downloadable from the workflow run.

## Validation And Comparison

Every invocation runs Redocly CLI `2.49.0` for syntax and semantic validation. Pull requests additionally compare the base and revision documents with oasdiff `1.29.1`; the Linux archive is checksum-verified before execution. The breaking-change report is written to the job summary and uploaded as `openapi-breaking-report-<github.sha>`.

Pushes validate and publish the contract artifact but skip comparison because there is no pull request base document. Pull requests fail when oasdiff reports `ERR` or `WARN` breaking changes.

## Intentional Breaking Changes

Breaking changes are exceptions, not a bypass. To approve one, the pull request must have the `api-breaking-change-approved` label (or the configured `breaking_change_approval_label`) and change `info.version` to a new major version. The workflow rejects a breaking change when either condition is missing. Reviewers should describe the migration impact and consumer plan in the pull request before applying the label.

The versioning policy is semantic: additive, backward-compatible changes stay on the current major version; incompatible request, response, path, or schema changes require a major `info.version` bump. A major version bump without a detected breaking change is allowed and does not need the approval label.

## Adoption Checklist

1. Generate or commit a deterministic OpenAPI document in the service repository.
2. Add a caller workflow referencing this reusable workflow by commit SHA.
3. Verify the generated path exists in both the service's pull request and `main` revisions.
4. Make the OpenAPI validation and breaking-change jobs required checks before removing an equivalent inline check.
5. Link the adoption pull request to its tracked task with a real Markdown closing keyword such as `Closes #123`.
