# Contributing to Digital Bank Java

Thank you for contributing to the Digital Bank Java platform. The project is public and intended to demonstrate production-oriented Java, Spring, Kubernetes, and event-driven engineering practices.

## Before You Start

- Search existing issues before creating a new one.
- Use the issue forms for stories, tasks, and bugs.
- Keep work within the issue scope and identify cross-repository dependencies early.
- Do not include credentials, tokens, private endpoints, customer data, or production data in issues, commits, pull requests, screenshots, or logs.

## Development Workflow

1. Discuss or create a tracked issue before changing code or documentation.
2. Create a dedicated branch from the current `main` branch.
3. Use the organization branch convention:
   - `feature/<issue-number>-<description>`
   - `docs/<issue-number>-<description>`
   - `fix/<issue-number>-<description>`
4. Follow the repository's `AGENTS.md`, `README.md`, and local verification guidance.
5. Keep commits focused and avoid unrelated refactoring.
6. Run the relevant tests and quality checks before opening a pull request.

For Java services, the expected baseline quality gate is normally:

```bash
./mvnw verify
```

## Pull Requests

- Complete every section of the pull request template.
- Link the issue with a closing keyword, such as `Closes #123`.
- Explain manual verification in addition to automated checks when it matters.
- Link related cross-repository pull requests and state merge order or rollout dependencies.
- Update documentation when behavior, setup, operations, API contracts, or configuration conventions change.
- Keep pull requests small enough for a reviewer to understand and validate.

Maintainers review changes for correctness, tests, documentation, security impact, and fit with platform conventions. A pull request must not be merged until required checks pass and the change has been approved.

## Architecture and Operations

- Runtime configuration belongs in `config-repo`; do not hardcode environment-specific values in services.
- SIT is the local Kubernetes integration environment. UAT and production are future cloud environments.
- Public and admin API routing should flow through `api-gateway`.
- Use placeholders and runtime-injected values for secrets.
- Treat migrations, API changes, deployment manifests, and event contracts as compatibility-sensitive changes.

Read the organization [platform conventions](docs/platform-conventions.md) and the target repository documentation before proposing structural changes.

## Code of Conduct

Communicate constructively, keep reviews focused on the work, and assume good intent. Report suspected security vulnerabilities through the process in [SECURITY.md](SECURITY.md), not through public issues.
