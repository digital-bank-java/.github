# Sprint 0 Reconciliation Design

## Purpose

Make Sprint 0 an outcome-based foundation sprint with one clear completion
criterion: a developer can reproduce, operate, and verify the Digital Bank
Java platform in the local Kubernetes SIT environment using documented
engineering conventions.

This reconciliation changes Project organization only. It does not change
application behavior, deployed infrastructure, or completed pull requests.

## Scope Boundary

Sprint 0 retains work necessary to establish and operate local SIT:

- local Kubernetes, Helm, PostgreSQL, Kafka, AKHQ, Config Server, and API
  Gateway foundations;
- repeatable service delivery conventions, CI foundations, CODEOWNERS, and
  contributor workflow assets;
- platform architecture documentation and local-SIT diagnostics;
- Insomnia requests needed to validate the local gateway and foundational
  platform services;
- completion evidence and closure of work already delivered.

Sprint 0 excludes capability work whose delivery outcome belongs to another
sprint:

| Scope | Destination |
| --- | --- |
| UAT and production environment values, validation, and AWS release work | Sprint 7 |
| Authentication, authorization, rate limiting, and step-up controls | Sprint 4 |
| SonarQube and broader observability or resilience tooling | Sprint 6 |
| Transaction workflow implementation and event consistency | Sprint 3 |

## Item Treatment

Each affected issue will receive one of these treatments:

1. **Keep in Sprint 0:** the issue directly supports the local-SIT outcome.
2. **Move to its outcome sprint:** only when the issue's primary deliverable
   is clearly security, observability, transaction/eventing, or AWS/UAT/PROD
   readiness.
3. **Split the issue:** preserve a local-SIT portion in Sprint 0 and create or
   retain a later-sprint issue for deferred environment-specific scope.
4. **Close with evidence:** when implementation and verification already
   exist, add a concise evidence comment and set the Project item to Done.

No completed work is discarded. Historical issues stay linked in the native
GitHub issue hierarchy under their appropriate Sprint root.

## Sprint 0 Completion Criteria

Sprint 0 is complete only when:

- a clean local workstation can provision the documented SIT platform and
  deploy its existing foundational services;
- platform health and routed diagnostics are verifiable through documented
  commands and Insomnia;
- organization-wide development conventions that are intentionally shared are
  published in the `.github` repository;
- `config-server` has the same governance ownership baseline as the other
  active Java services;
- stale planning items are either completed with evidence or explicitly moved
  to their outcome sprint.

## Non-Goals

- Implementing new domain capabilities.
- Deploying UAT, production, or AWS infrastructure.
- Introducing production security controls or observability platforms before
  their dedicated sprints.
- Rewriting past issue history solely for cosmetic reasons.

## Verification

After the Project updates, verify that every active Sprint 0 item directly
supports the stated outcome, every moved item has a Sprint matching its
parent root, and stale completed work is no longer reported as active.
