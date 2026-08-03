# README Standard

This standard defines the minimum human-facing documentation for active Digital Bank Java repositories. It applies to application services, platform services, configuration, and infrastructure repositories. Repository type determines which sections are applicable.

## Required Baseline

Every active repository README must state:

1. **Purpose and current state**: what the repository owns and which capabilities are implemented today. Planned work must be labelled as planned.
2. **Responsibilities and non-responsibilities**: the boundary that prevents overlapping ownership between services.
3. **Runtime or repository model**: how the component participates in the platform, including Config Server, Kubernetes, or data ownership where applicable.
4. **Prerequisites and verification**: the smallest truthful commands a contributor can use to validate the repository.
5. **SIT usage**: build, Helm validation, deployment, or the reason the repository has no deployable artifact.
6. **Security and environment posture**: secrets stay outside Git; SIT, UAT, and PROD are the formal environments; a workstation process is debugging against SIT, not a separate deployment environment.
7. **Contribution workflow**: use a dedicated branch, a tracked issue, a pull request, and the repository's documented quality checks.

## Service Repositories

An active Java service README additionally documents:

- Java version and Maven Wrapper commands.
- The Config Server dependency and service port when implemented.
- Docker image build command and non-root runtime posture.
- Helm rendering and SIT deployment commands.
- API Gateway verification for endpoints intentionally exposed through the gateway.
- CI checks actually configured in the repository.

Do not document a gateway route, API endpoint, database, Kafka topic, or AWS service until it is implemented and tracked.

## Configuration and Infrastructure Repositories

Configuration and infrastructure README files document their file or chart model, installation/verification commands, ownership boundaries, and a safe secret-handling process. They must not contain real credentials, personal tokens, or production endpoints.

## Keeping Documentation Accurate

- Update the README in the same pull request when user-visible setup, verification, deployment, or ownership changes.
- Prefer exact commands copied from the current build, Helm chart, or CI workflow.
- Link to organization standards rather than duplicating cross-repository policy.
- Keep historical decisions in issues and the project handoff, not as unsupported operational instructions in a README.
