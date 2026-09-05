# .github

Organization-wide engineering standards, architecture decisions, and reusable GitHub automation for the Digital Bank Java platform.

This repository is not a deployable application. It provides shared contributor guidance and organization-level GitHub resources; each service keeps its own build, deployment, and runtime documentation in its repository.

## Engineering Standards

- [Java test convention and CI stage guidance](docs/testing/java-test-convention.md)
- [Reproducible local Kubernetes SIT setup and verification](docs/local-sit.md)
- [Shared Auth JWT Secret for local SIT](docs/sit-auth-jwt-secret.md)
- [Platform naming, ports, configuration, API, and infrastructure conventions](docs/platform-conventions.md)
- [Platform architecture, service boundaries, and event flow](docs/platform-architecture.md)
- [Workstation debugging against SIT](docs/workstation-debugging-against-sit.md)
- [Insomnia step-up transfer workflow](docs/insomnia-step-up-transfer-workflow.md)
- [Insomnia MFA workflow](docs/insomnia-mfa-workflow.md)
- [README documentation baseline](docs/readme-standard.md)
- [Reusable GitHub Project status workflow](docs/reusable-project-status.md)

## Contribution Workflow

Use a tracked GitHub issue, a dedicated branch, and a pull request for every change. Repository-specific quality commands and ownership rules remain authoritative; see the repository's `README.md`, `AGENTS.md`, and `CODEOWNERS` file.

## Event Contract Validation

The versioned Kafka contracts under `docs/contracts/` are checked by the
path-scoped `Validate AsyncAPI contracts` workflow. The dependency-free Ruby
validator checks AsyncAPI metadata, Kafka channel and operation wiring, local
references, required event/header metadata, representative payload examples,
and the declared `BACKWARD_TRANSITIVE` Schema Registry compatibility policy.
Schema Registry deployment and credentials remain platform responsibilities.
