# Security Policy

## Supported Repositories

Security reports are welcome for active repositories in the `digital-bank-java` organization.

## Reporting a Vulnerability

Do not open a public GitHub issue for a suspected vulnerability.

Use GitHub's private vulnerability reporting flow for the affected repository:

1. Open the repository's **Security** tab.
2. Select **Report a vulnerability**.
3. Provide a concise description, affected component, impact, and safe reproduction steps.
4. Remove credentials, tokens, private keys, personal data, customer data, and production endpoints from the report.

If private vulnerability reporting is unavailable for the repository, contact an organization maintainer privately through their GitHub profile and request a secure reporting channel. Do not publish exploit details while the issue is being assessed.

## What to Include

- Affected repository, component, and version or commit.
- Security impact and realistic attack prerequisites.
- Safe reproduction steps or proof of concept.
- Suggested mitigation, if known.

## Response Expectations

Maintainers will acknowledge a valid report, assess impact, coordinate remediation, and decide when disclosure is safe. Timeframes depend on severity, reproducibility, and the scope of the required fix.

## Scope Notes

- Example credentials, test containers, local Kubernetes manifests, and placeholder values are not secrets by themselves.
- Exposed real credentials, private keys, customer data, or unsafe public administrative access should be reported privately.
