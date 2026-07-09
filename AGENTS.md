# Digital Bank Java Agent Playbook

This file defines the organization-wide operating contract for AI agents and human contributors working in the `digital-bank-java` organization.

## Why This Exists

- Keep repository-local agent guidance consistent.
- Reduce repeated explanation about architecture, workflow, testing, and rollout rules.
- Make public repositories easier to understand and safer to change.

## Guidance Model

Use a hybrid model:

- This file is the organization-wide source of truth.
- Each active repository should also contain its own `AGENTS.md`.

Use this file for:

- standards shared by every repository
- workflow and governance rules
- cross-repo architecture and environment conventions

Use repo-local `AGENTS.md` files for:

- repo purpose and boundaries
- local commands
- local dependencies
- rollout and verification steps specific to that repository

## Repository Map

| Repository | Role |
| --- | --- |
| `.github` | Organization-wide workflow, quality, and contributor standards |
| `config-server` | Spring Cloud Config Server |
| `config-repo` | Externalized runtime configuration served by Config Server |
| `api-gateway` | Public entry point and centralized admin/docs routing |
| `customer-service` | Customer identity and profile management |
| `account-service` | Account lifecycle and account lookup |
| `ledger-service` | Immutable journal entry posting and lookup |
| `infra-sit` | Local SIT infrastructure for Kubernetes workloads |

## Architecture Rules

- Use hexagonal architecture for Java services.
- Keep business rules in the domain and application layers.
- Keep inbound adapters responsible for transport only.
- Keep outbound adapters responsible for infrastructure only.
- Do not move business workflows into controllers, repositories, Helm files, or CI workflows.

Current service direction:

- `customer-service` owns customer identity and profile state.
- `account-service` owns account lifecycle and account retrieval.
- `ledger-service` owns immutable financial journal entries.
- Final balance mutation should be driven by ledger and transaction workflows, not by direct public balance update APIs.

## Environment Model

The platform uses these environments:

- `local`: direct developer execution from the workstation
- `sit`: integrated local Kubernetes environment
- `uat`: cloud-hosted pre-production environment
- `prod`: production environment

Rules:

- Local SIT runs on Kubernetes and should resemble production structure where practical.
- Runtime configuration belongs in `config-repo`, not in service repositories.
- Infrastructure manifests for local SIT belong in `infra-sit`.
- Do not commit real secrets into any repository.

## Configuration Rules

- `config-repo` is the source of externalized runtime configuration.
- Shared defaults belong in `application.yml`.
- Shared profile overrides belong in `application-{profile}.yml`.
- Service defaults belong in `{service}/{service}.yml`.
- Service profile overrides belong in `{service}/{service}-{profile}.yml`.

Do not rename these files to non-Spring names such as `common.yml` unless the Config Server loading model changes everywhere.

## Database Rules

- Each service owns its data logically.
- In local SIT, multiple logical PostgreSQL databases may exist inside one shared PostgreSQL instance.
- In cloud environments, production mapping may move to managed databases such as Amazon RDS.
- Use Flyway for schema migrations.
- Do not rely on Hibernate schema generation for managed environments.

## API Rules

- Public access should flow through `api-gateway`.
- Internal/admin APIs may also flow through `api-gateway`, usually under explicit admin paths.
- Service-local OpenAPI documents should be aggregated through the gateway for central discovery.
- Error responses should be explicit and documented, especially `400`, `404`, `409`, and `422` style business errors where applicable.

## Event and Consistency Rules

- Do not model final financial state changes as naive synchronous CRUD updates.
- Prefer event-driven workflows for reservations, postings, and completion/failure propagation.
- Ledger completion events should drive final account effects.
- Idempotency, optimistic locking, and replay protection should be considered when designing mutation workflows.

## Branch, Issue, and PR Rules

- Do not change repositories without supporting issue tracking.
- Use issue titles with explicit prefixes:
  - `EPIC:`
  - `STORY:`
  - `TASK:`
- Use the GitHub issue Type field correctly for every issue, including completed items.
- Keep tasks and stories attached to a relevant epic when one exists.
- Assign in-progress tasks to `ramioooz`.
- Use dedicated branches, never commit directly to `main`.

Branch naming:

- `feature/<issue-number>-<description>`
- `docs/<issue-number>-<description>`
- `fix/<issue-number>-<description>`

PR rules:

- Reference the supporting issue with a closing keyword.
- If related changes span repositories, link the related PRs explicitly.
- State preferred merge order when rollout sequencing matters.
- Mention whether any waiting period is required after merges.

## Testing and Quality Rules

- Java repositories should converge on `./mvnw verify` as the quality gate.
- Use unit tests for domain/application logic where isolation is useful.
- Use integration tests for persistence, API slices, and container-backed behaviors.
- Use Testcontainers when database-backed integration behavior must be validated.
- Keep CI green before merge.

## Deployment and Rollout Rules

- Docker images are the packaging format for Kubernetes workloads.
- Kubernetes deployments in SIT should be validated after image rebuilds and rollout restarts.
- Prefer explicit rollout checks over assumption.
- Document any required port-forward commands for local verification.

## Security Rules

- Never commit credentials, tokens, or production endpoints.
- Use placeholders and environment variables for secrets.
- Keep public internet exposure intentional and minimal.
- Developer/admin tooling such as aggregated Swagger UI should not be treated as public customer-facing surfaces.

## Documentation Rules

- `README.md` explains setup, verification, and operational use for humans.
- `AGENTS.md` explains repository working rules for agents and contributors.
- Keep both accurate.
- If behavior changes, update the matching documentation in the same workstream.

## Agent Behavior Rules

- Prefer the existing repository pattern over inventing a new one.
- Keep edits scoped to the issue being implemented.
- Validate with the narrowest relevant command first, then the broader quality gate.
- Surface cross-repo dependencies early.
- Do not silently introduce new infrastructure, new environments, or new governance rules without corresponding issue tracking.
