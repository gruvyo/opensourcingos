# QA regression map

This map ties each accepted remediation unit to the automated evidence that
must remain green. `npm run check` runs every Node test plus the methodology,
lint, type, and build gates. The Supabase workflow rebuilds every migration and
runs every pgTAP file below against a disposable database.

| Unit | Protected behavior | Automated evidence |
| --- | --- | --- |
| U-CALC | One calculation per sourcing project; duplicate data fails closed | `scripts/supplier-portfolio.test.mts`; `supabase/tests/database/sourcing_only_savings.test.sql` |
| U-TXN | Baseline, offer-role, and schedule writes are atomic and guarded | `scripts/atomic-money-writers.test.mts`; `supabase/tests/database/atomic_money_writers.test.sql` |
| U-EXEC | Executed savings follow a guarded lifecycle and retain evidence | `supabase/tests/database/executed_savings_lifecycle.test.sql` |
| U-STAMP / U-RLS / U-PRIV | Actor fields, role permissions, column grants, anonymous denial, and workspace isolation | `scripts/money-core-role-ui.test.mts`; `supabase/tests/database/money_core_role_enforcement.test.sql`; `supabase/tests/database/money_core_role_matrix.test.sql`; `supabase/tests/database/bootstrap.test.sql` |
| U-DEL | Destructive money-core deletion is unavailable outside the reviewed administrative lifecycle | `supabase/tests/database/money_core_role_enforcement.test.sql`; `supabase/tests/database/executed_savings_lifecycle.test.sql` |
| U-DEMO | Demo cloning preserves isolation and stamps the new workspace's actors | `supabase/tests/database/demo_clone_integrity.test.sql`; `supabase/tests/database/bootstrap.test.sql` |
| U-FINAL | Blank, invalid, negative, sub-cent, and unconfirmed zero Final anchors cannot publish | `scripts/final-anchor.test.mts` |
| U-LOAD | Failed reads remain errors and cannot masquerade as empty data | `scripts/load-state.test.mts`; `scripts/portfolio-query-pagination.test.mts`; `scripts/supplier-portfolio.test.mts` |
| U-TERM | Terminal project status is managed metadata and survives label renames | `scripts/terminal-status.test.mts`; `supabase/tests/database/terminal_status_metadata.test.sql` |
| U-ATTR | Supplier savings belong to award winners, not losing incumbents | `scripts/supplier-portfolio.test.mts` |
| U-NULL | Reports preserve not-applicable reduction rather than coercing it to zero | `scripts/report-savings.test.mts` |
| U-POP | Savings include Sourcing Projects only, with legacy-null compatibility | `scripts/savings-population.test.mts`; `supabase/tests/database/sourcing_only_savings.test.sql` |
| U-ROUND | Stored monetary values use exact cents and schedules reconcile without silent rounding | `scripts/money-precision.test.mts`; `scripts/final-anchor.test.mts`; `supabase/tests/database/two_decimal_money.test.sql` |
| U-REAL | Realization tracks reduction and avoidance legs independently; avoidance shortfall is not leakage | `scripts/realization.test.mts`; `supabase/tests/database/per_leg_realization.test.sql` |
| U-HDR | Realization rows have a matching Period column header | `scripts/realization.test.mts` |
| U-DEPS | Production and development dependency advisories are cleared | `npm run audit:production`; `scripts/dependency-audit.test.mjs`; non-blocking full-tree audit in CI |
| U-CI | Pull requests cannot bypass tests, verification, lint, types, build, database rebuild, generated types, or schema drift | `.github/workflows/application-quality.yml`; `.github/workflows/supabase-database.yml` |
| U-GITIGNORE | Bare and environment-specific Next.js secret files cannot be accidentally committed; the public template remains available | `scripts/env-gitignore.test.mjs` |
| U-HEADERS | Every route is protected against framing and receives CSP, MIME, referrer, permissions, and transport headers | `scripts/security-headers.test.mts`; production response-header check after deployment |
| U-URLSCHEME | Supplier and evidence links render only absolute HTTP(S) URLs; direct writes cannot store an unsafe supplier website | `scripts/safe-external-url.test.mts`; `supabase/tests/database/url_scheme_checks.test.sql` |
| U-CSV | User-controlled CSV cells cannot execute spreadsheet formulas; exact negative monetary exports remain numeric text | `scripts/csv.test.mts` |

Hardening units not yet merged must add their evidence to this map in the same
pull request. A test name alone is not sufficient: the test must exercise the
specific failure mode recorded in the assessment.
