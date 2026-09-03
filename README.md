# .github

Organization-wide engineering standards, architecture decisions, and reusable GitHub automation for the Digital Bank Java platform.

This repository is not a deployable application. It provides shared contributor guidance and organization-level GitHub resources; each service keeps its own build, deployment, and runtime documentation in its repository.

## Engineering Standards

- [Java test convention and CI stage guidance](docs/testing/java-test-convention.md)
- [Reproducible local Kubernetes SIT setup and verification](docs/local-sit.md)
- [Shared Auth JWT Secret for local SIT](docs/sit-auth-jwt-secret.md)
- [Platform naming, ports, configuration, API, and infrastructure conventions](docs/platform-conventions.md)
- [Workstation debugging against SIT](docs/workstation-debugging-against-sit.md)
- [README documentation baseline](docs/readme-standard.md)

## Contribution Workflow

Use a tracked GitHub issue, a dedicated branch, and a pull request for every change. Repository-specific quality commands and ownership rules remain authoritative; see the repository's `README.md`, `AGENTS.md`, and `CODEOWNERS` file.
