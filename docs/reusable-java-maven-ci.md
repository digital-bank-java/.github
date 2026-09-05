# Reusable Java Maven CI

The organization workflow at `.github/workflows/java-maven-verify.yml` provides the common Java quality gate for Maven Wrapper-based services.

For OpenAPI contract validation, breaking-change detection, and versioned contract artifacts, use the separate [reusable OpenAPI CI workflow](reusable-openapi-ci.md). Service repositories should adopt it in a service-owned pull request; this repository does not modify service workflows automatically.

It deliberately performs only the common verification responsibility:

- checks out the calling repository
- installs Temurin Java 21 by default
- restores and saves the Maven dependency cache
- runs `./mvnw --batch-mode --no-transfer-progress verify`
- uploads Surefire and Failsafe reports for 14 days, including when Maven verification fails

The `Maven verify` job is the visible required check. The report artifact makes individual test results available after a failure without granting the workflow broader permissions.

## Caller Requirements

The caller repository must:

- contain `mvnw` and `pom.xml` in its configured working directory
- grant the reusable workflow only the permissions it needs, normally `contents: read`
- keep service-specific jobs, such as Helm validation and container smoke tests, in its own workflow

Use a full commit SHA when referencing the shared workflow. This protects callers from unexpected changes to a moving branch or tag.

## Standard Caller

Create `.github/workflows/ci.yml` in a service repository:

```yaml
name: CI

on:
  pull_request:
  push:
    branches:
      - main

permissions:
  contents: read

jobs:
  verify:
    uses: digital-bank-java/.github/.github/workflows/java-maven-verify.yml@<pinned-commit-sha>
    permissions:
      contents: read
```

Replace `<pinned-commit-sha>` with the commit that introduces, or later updates, the reusable workflow. Do not use `main` in production workflow references.

## Optional Inputs

```yaml
jobs:
  verify:
    uses: digital-bank-java/.github/.github/workflows/java-maven-verify.yml@<pinned-commit-sha>
    permissions:
      contents: read
    with:
      working_directory: service
      java_version: "21"
      test_report_artifact_name: service-maven-test-reports
```

`working_directory` defaults to the repository root, `java_version` defaults to `21`, and `test_report_artifact_name` defaults to `maven-test-reports`.

## Adoption

Adopt this workflow through a separate service pull request. Preserve the repository's service-specific jobs and establish the reusable `Maven verify` job as the required Java quality check before removing equivalent inline setup.

## Organization Workflow Template

Java service repositories can start from the **Java Maven service CI** template in the GitHub Actions workflow chooser. The template creates `.github/workflows/ci.yml` with the shared Maven verification workflow pinned to an immutable `.github` commit.

After creating the workflow, review it in a service pull request. Add service-specific jobs, such as Helm rendering or a container smoke test, in that repository's workflow rather than modifying the organization template for one service.
