# Public Release Review And Organization Profile Design

## Goal

Prepare the Digital Bank Java organization for a future public release by reviewing the authoritative mainline of every repository, correcting only confirmed release-blocking defects, and publishing an accurate organization introduction page.

## Scope

The work has two independent deliverables:

1. A project-wide review of the twelve service/infrastructure repositories and the organization repository.
2. A public-facing organization profile at `.github/profile/README.md`.

AWS/UAT/PROD delivery and SonarQube remain deferred. Repository visibility, branch protection, secrets, and organization settings are explicitly out of scope for this change.

## Review Baseline

- Review `origin/main` after fetching each repository.
- Ignore stale local branches and untracked worktree artifacts.
- Treat security, persistence, event delivery, idempotency, migration safety, deployment configuration, CI behavior, and public documentation accuracy as release-critical.
- Do not add broad or redundant tests. Add a test only when it is the smallest load-bearing proof of a confirmed defect.
- Record findings with repository, commit, file, line, impact, and reproduction/verification evidence.
- Fix confirmed Critical and High findings in isolated branches with pull requests. Record valid Medium/Low findings as follow-up issues only when they are not already represented in the GitHub Project.

## Public Profile Content

`.github/profile/README.md` will contain:

- a concise platform purpose and current delivery status;
- a repository map covering Config Server, Config Repo, API Gateway, Auth, MFA, Customer, Account, Ledger, Transaction, Payment, Notification, and SIT infrastructure;
- the request path through API Gateway and the event-driven transfer path through Transaction, Account, Ledger, Payment, and Notification services;
- the ownership rule that ledger postings are immutable and account balances are projections of ledger/transaction outcomes;
- local SIT prerequisites and high-level verification links without private credentials or cluster-only secrets;
- links to architecture, event contracts, local SIT, security, testing, and contribution documents;
- explicit disclosure that AWS/UAT/PROD and SonarQube are planned/deferred rather than falsely presented as available;
- public-release boundaries for synthetic fixtures, internal APIs, credentials, and production data.

The profile will use relative links that remain valid in the `.github` repository and repository links for service-specific material. It will not publish localhost-only claims as production endpoints, token values, passwords, internal hostnames, or unverifiable status claims.

## Verification

- Run the existing repository CI verification appropriate to each changed repository.
- Run Markdown/link and secret-pattern checks against the new profile content.
- Run the existing Maven verification for any Java repository changed by a review fix.
- Run `git diff --check` for every PR.
- Re-scan the review baseline after fixes and confirm every finding is either fixed with evidence, intentionally deferred with a linked issue, or rejected with a documented technical reason.
