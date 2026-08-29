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
| U-CSV | User-controlled CSV cells cannot execute spreadsheet formulas; exact negative monetary exports remain numeric text; the formula exemption keys on the runtime value, never the column format | `scripts/csv.test.mts`; `scripts/report-currency.test.mts` |
| U-TZ-CLASSIFY | Realized-versus-accrued classification compares date-only starts with today in the workspace timezone | `scripts/realization-timezone.test.mts` |
| U-TZ-PERSIST | Schedule end dates persist the user's local calendar date without a UTC day shift | `scripts/schedule-date-persistence.test.mts` |
| U-ATTENTION | Supplier lists, readiness reports, and the dashboard share one actionable attention definition | `scripts/supplier-readiness.test.mts`; `scripts/attention-queue.test.mts` |
| U-CURRENCY | Reports use workspace currency and locale; CSV money headers identify the currency while cells retain exact numeric values | `scripts/report-currency.test.mts`; `scripts/csv.test.mts` |
| R2-V1 | TypeScript and Postgres accept the same signed Opening − Baseline − Final chain, including negative avoidance, and calculation headlines remain additive | `scripts/verify-savings.mts`; `supabase/tests/database/qa_r2_money_integrity.test.sql`; `supabase/tests/database/two_decimal_money.test.sql` |
| R2-V2 | Executed calculations cannot be removed or detached through event cascades or baseline/award `SET NULL` actions, even with zero realization rows | `supabase/tests/database/qa_r2_money_integrity.test.sql`; `supabase/tests/database/executed_savings_lifecycle.test.sql` |
| R2-V3 | Unchanged realization inputs do not issue destructive blur writes | `scripts/money-precision.test.mts`; `scripts/realization.test.mts` |
| R2-V5 | Historical null project types retain Sourcing compatibility at both application and database boundaries | `scripts/savings-population.test.mts`; `supabase/tests/database/qa_r2_remaining_core.test.sql`; `supabase/tests/database/sourcing_only_savings.test.sql` |
| R2-V6 | Baseline-line totals and every estimated schedule edit are written and republished atomically | `scripts/atomic-money-writers.test.mts`; `supabase/tests/database/atomic_money_writers.test.sql`; `supabase/tests/database/executed_savings_lifecycle.test.sql` |
| R2-V7 | Soft baselines cannot publish hard reduction through generated or hand-edited schedule rows | `scripts/verify-savings.mts`; `supabase/tests/database/qa_r2_remaining_core.test.sql` |
| R2-V8 | Portable realization backfill preserves untouched legacy rows instead of classifying them as leakage; the one-off shell repair replays against a reconstructed legacy population | `supabase/tests/database/qa_r2_remaining_core.test.sql`; `supabase/tests/database/per_leg_realization.test.sql`; `supabase/tests/database/v8_realization_repair_replay.test.sql` |
| R2-V9 | Dashboard, Savings, Realization, supplier, and project money surfaces share workspace currency/locale and cent-exact dashboard display; timezone fallbacks share one constant | `scripts/report-currency.test.mts`; `scripts/realization-timezone.test.mts`; `scripts/verify-savings.mts` |
| R2-M | Managed labels keep a case-insensitive identity and every former guarded completion label remains reserved; estimated money is cent-exact and RPC-only; finance/deferred invariants fail closed; demo clones classify every org table; legacy corrections gain attributable actors; remaining loaders, CSV numbers, roles, URLs, and refresh paths are guarded | `scripts/atomic-money-writers.test.mts`; `scripts/load-state.test.mts`; `scripts/report-currency.test.mts`; `supabase/tests/database/qa_r2_medium_integrity.test.sql`; `supabase/tests/database/money_core_role_matrix.test.sql`; `supabase/tests/database/bootstrap.test.sql` |

Future hardening units must add their evidence to this map in the same pull
request. A test name alone is not sufficient: the test must exercise the
specific failure mode recorded in the assessment.
