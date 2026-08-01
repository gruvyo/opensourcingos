# Security Policy

## Supported version

Security fixes are made against the latest commit on `main`. Older commits,
forks, and third-party deployments are not maintained by this project.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability.

Use GitHub's private vulnerability reporting for this repository:

1. Open the repository's **Security** tab.
2. Choose **Advisories**.
3. Select **Report a vulnerability**.

Include the affected page, component, or database object; the impact; steps to
reproduce; and any suggested remediation. Do not access another person's data,
degrade the hosted demo, or retain data beyond what is necessary to demonstrate
the issue.

The maintainer will acknowledge a credible report, investigate it, and
coordinate disclosure after a fix is available. Exact response times are not
guaranteed while the project remains a public beta.

## Security boundaries

- The hosted demo is intended for evaluation, not confidential procurement
  records.
- Supabase publishable keys are expected to appear in browser code; database
  access is protected by Row Level Security.
- Supabase secret and service-role keys must never appear in browser code,
  source control, issues, or logs.
- Each demo user should see only their own workspace. Any cross-workspace read
  or write is a high-priority vulnerability.

## Current safeguards

- Row Level Security is enabled on business tables exposed through the Data API.
- Organization-scoped policies isolate each demo workspace.
- Privileged workspace-cloning functions are not callable by browser users.
- The frontend uses a publishable Supabase key; secret and service-role keys
  remain server-side and outside source control.
- GitHub secret scanning and push protection are enabled.
