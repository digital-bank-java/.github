# Centralized API Catalog Evaluation

This document evaluates whether the Digital Bank Java platform needs a dedicated internal API and service catalog in addition to its current service-owned OpenAPI contracts and API Gateway aggregation.

## Current Baseline

Each service owns and publishes its own API contract. The API Gateway provides the central internal entry point for the aggregated Swagger UI and named contract endpoints:

```text
/admin/docs/swagger-ui.html
/admin/docs/{service}/v3/api-docs
```

This arrangement is intentionally small. It gives developers one place to discover and try the HTTP contracts without creating a second catalog product. Contract ownership remains close to the implementation repository, which keeps API changes reviewable with the code that implements them.

The current baseline does not attempt to be a complete software catalog. It does not yet provide a searchable inventory of service owners, repositories, dependencies, runtime components, lifecycle states, event channels, or consumer onboarding workflows.

## Evaluation Criteria

Any additional catalog should be evaluated against these criteria:

- **Ownership:** Can the service team maintain its API metadata and lifecycle state without a central bottleneck?
- **Discovery:** Can a developer find the contract, service owner, repository, dependencies, and supported lifecycle state?
- **Access and security:** Can internal documentation be protected by environment, identity, role, and audit policy?
- **Operational cost:** What infrastructure, upgrades, plugins, support, and on-call responsibility does the option add?
- **Contract integration:** Can it ingest service-owned OpenAPI contracts and future AsyncAPI contracts without making a second copy authoritative?
- **AWS portability:** Can the approach move from local SIT to AWS-hosted UAT and PROD without exposing internal contracts publicly?

## Options

### Option 1: Keep Gateway Aggregation as the Catalog Surface

The platform keeps service-owned OpenAPI contracts and the gateway's centralized Swagger UI as the primary API discovery experience.

| Criterion | Assessment |
| --- | --- |
| Ownership | Strong. Each service owns its contract and its API metadata. |
| Discovery | Adequate for endpoint and schema discovery; weak for broader service ownership and dependency discovery. |
| Access and security | Strong foundation. The gateway path can remain internal and can later be protected by the platform's admin authorization policy. |
| Operational cost | Lowest. No additional catalog runtime or plugin ecosystem. |
| Contract integration | Strong for OpenAPI; gateway configuration can later include AsyncAPI links or event catalog references. |
| AWS portability | Strong. The same ownership model works with an AWS-hosted gateway and private documentation access. |

### Option 2: Backstage Software Catalog

Backstage is an open-source developer portal and software catalog. It can model services, APIs, teams, repositories, dependencies, documentation, and lifecycle metadata. OpenAPI and AsyncAPI contracts can remain in the owning repositories while Backstage indexes links and metadata.

| Criterion | Assessment |
| --- | --- |
| Ownership | Strong when catalog metadata is maintained by service teams through repository descriptors and ownership rules. |
| Discovery | Strong. It provides a broader service and API catalog than Swagger UI alone. |
| Access and security | Flexible but must be configured and operated: identity integration, authorization, plugin permissions, secret handling, and network boundaries are platform responsibilities. |
| Operational cost | Medium to high. The software is open source, but hosting, upgrades, plugins, database, authentication, backups, and support are not free operationally. |
| Contract integration | Strong, provided repository contracts remain authoritative and the catalog stores references or generated views rather than unmanaged copies. |
| AWS portability | Good. It can run on AWS, but the organization must operate the portal and its dependencies. |

Backstage becomes attractive when the platform needs a complete internal developer portal rather than only API documentation.

### Option 3: Managed API Portal or API Management Product

A vendor-managed portal can provide API documentation, consumer onboarding, access plans, subscriptions, analytics, publication workflows, and sometimes a developer portal. Examples include a SaaS API documentation or portal product, a managed API-management offering, or an AWS-aligned API Gateway developer portal solution.

| Criterion | Assessment |
| --- | --- |
| Ownership | Usually good for contract publication, but ownership and lifecycle metadata may follow the vendor's workflow. |
| Discovery | Strong for published APIs and consumers; broader service topology discovery varies by product. |
| Access and security | Potentially strong, but identity integration, private-network access, tenant boundaries, audit export, and data residency must be verified for banking use. |
| Operational cost | Low platform-operations burden but recurring subscription, usage, support, and possible migration costs. |
| Contract integration | Usually good through OpenAPI import or CI publication. AsyncAPI and internal-only contracts must be verified rather than assumed. |
| AWS portability | Product-dependent. A vendor-neutral portal may reduce AWS coupling; an AWS-aligned option may simplify AWS integration but increase platform coupling. |

This option is most useful when external or internal API consumers need controlled onboarding, subscriptions, usage analytics, rate plans, or a supported developer-facing product portal.

## Comparison Summary

| Option | Best fit | Main cost or risk | Decision for current platform |
| --- | --- | --- | --- |
| Gateway aggregation | Small to medium platform focused on contract discovery | Limited service ownership and dependency metadata | Keep as the current standard |
| Backstage | Internal developer portal and complete service catalog | Operating another platform and plugin ecosystem | Reconsider when broader catalog needs are proven |
| Managed API portal | Consumer onboarding, subscriptions, analytics, and API product management | Subscription cost, vendor fit, and portability | Reconsider for UAT/PROD consumer needs |

## Decision

**Status:** Accepted

**Date:** 2026-08-30

**Decision:** Do not introduce a dedicated API catalog or portal at this stage. Keep the current service-owned OpenAPI contracts and API Gateway aggregation as the platform's API documentation surface.

The gateway remains the central place for internal HTTP contract discovery. The service repository remains the source of truth for its OpenAPI contract. A catalog, if adopted later, must index those contracts and repository-owned metadata rather than create an independently maintained copy.

This decision does not prohibit a future portal. It defers that operational commitment until the platform has evidence that gateway aggregation no longer meets its needs.

## Security And Banking Boundaries

- Aggregated documentation is an internal developer/admin capability, not a public customer API.
- SIT documentation may be reached through the local API Gateway port-forward.
- UAT and PROD documentation must use private network access, identity-based authorization, least privilege, and audit logging.
- Production contracts must not expose credentials, tokens, private infrastructure details, or sensitive examples.
- Publishing an OpenAPI contract must not automatically publish the underlying business API to the public internet.
- Any future portal must preserve repository-level review, contract versioning, access control, and auditability.

## Reconsideration Triggers

Re-evaluate this decision when one or more of the following becomes a real delivery problem:

- Developers cannot find service ownership, repository, dependency, or lifecycle information from the gateway and repository metadata.
- Multiple teams need a searchable inventory of REST APIs, events, databases, and platform dependencies.
- API consumers need subscriptions, access plans, SDK discovery, usage analytics, or onboarding workflows.
- The organization needs a single internal portal for runbooks, service health links, ownership, APIs, and event contracts.
- Contract publication, compatibility reporting, or API lifecycle reporting cannot be managed reliably through repository CI and gateway aggregation.
- AWS UAT/PROD governance requires a centrally managed private developer portal.

At reconsideration time, compare Backstage and managed products using the criteria above, with a proof of concept based on real service contracts rather than a standalone demo.

## Consequences

### Benefits

- No additional portal is introduced before its operational value is demonstrated.
- API ownership stays with the service teams and their pull requests.
- The current SIT workflow and future AWS deployment model remain simple and portable.
- The platform avoids maintaining a second authoritative copy of an API contract.

### Trade-offs

- Developers must use repository metadata and gateway documentation rather than a full service catalog.
- Service ownership, dependency, and lifecycle discovery will remain less rich until catalog metadata is added.
- Consumer onboarding and API product-management capabilities are deferred.
