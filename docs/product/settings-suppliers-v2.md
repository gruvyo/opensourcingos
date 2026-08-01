# Settings and Suppliers v2

## Product intent

Settings should become the control plane for a procurement workspace. Suppliers
should become a living relationship and performance record, not merely a list
of names used by projects.

The modules should reinforce the product's governing promise: every setting
that changes reporting and every supplier result should remain explainable,
workspace-scoped, and auditable.

## Settings v2

### Outcomes

- Administrators can manage organization identity, fiscal calendar, currency,
  reporting conventions, and procurement methodology defaults.
- Users can manage their own profile and presentation preferences.
- Workspace roles and membership are visible and enforceable.
- Connections, exports, and security posture are understandable without
  exposing credentials.

### Proposed sections

1. **Organization** — name, logo, default currency, locale, fiscal-year start,
   and reporting timezone.
2. **Savings methodology** — default recognition method, baseline requirements,
   hard-reduction approval policy, forecast/contracted/realized terminology,
   and reporting thresholds.
3. **People and roles** — invite members, assign `admin`, `procurement_user`, or
   `viewer`, and show pending access.
4. **Data and integrations** — exports, API/integration status, and connection
   health. Secrets remain in the deployment platform, never in browser forms.
5. **Audit and safety** — recent administrative changes, workspace ID, RLS
   status, and clearly separated destructive actions.

### Data additions

- `organization_settings`: currency, locale, timezone, fiscal year start month,
  date format, and methodology defaults.
- `organization_memberships` or an extension of `profiles`: explicit status,
  invitation state, and role-change timestamps.
- `audit_log`: actor, workspace, action, entity, before/after summary, and time.

All new tables require forced Row Level Security, organization-scoped policies,
indexes on `organization_id`, and tests proving cross-workspace isolation.

## Suppliers v2

### Outcomes

- Procurement can create and maintain supplier master records independently of
  a sourcing project.
- Each supplier has a profile combining relationship attributes, risk,
  sourcing history, awards, savings, and realization.
- Teams can find duplicates and understand concentration or risk before an
  award decision.

### Proposed capabilities

1. **Supplier directory** — create/edit/archive, status, preferred and diversity
   flags, risk rating, categories, owner, and normalized legal name.
2. **Supplier profile** — headline metrics, active projects, award history,
   contracted savings, realized savings, and recent activity.
3. **Contacts and classifications** — commercial contacts, diversity
   certifications, category coverage, geography, and expiration dates.
4. **Risk and performance** — overall rating plus delivery, quality, commercial,
   compliance, and concentration signals with evidence and review dates.
5. **Data quality** — duplicate suggestions based on normalized names and a safe
   merge workflow that repoints related records with a complete audit trail.

### Data additions

- Extend `suppliers` with legal name, website, country, owner, review date, and
  structured risk metadata.
- Add `supplier_contacts`, `supplier_categories`, `supplier_certifications`,
  `supplier_performance_reviews`, and `supplier_notes`.
- Add normalized-name uniqueness within each organization, supporting indexes,
  and an audited supplier-merge database function unavailable to browser users.

## Delivery sequence

### Release 1 — useful with today's schema

- Concept B application shell and shared page hierarchy.
- Supplier portfolio summary, search, filters, status, risk, preference,
  diversity, project links, and awards.
- Settings overview with correct identity, organization, reporting conventions,
  methodology controls, and platform connections.

### Release 2 — editable operating controls

- Database migration for organization settings and supplier master details.
- Authenticated, validated server actions for settings and supplier edits.
- Supplier profile route with sourcing, award, savings, and realization history.
- Role-aware controls and complete loading, success, and failure feedback.

### Release 3 — governance and intelligence

- Membership administration and audit log.
- Supplier performance reviews, certifications, risk evidence, and reminders.
- Duplicate detection and audited supplier merge.
- Portfolio concentration, diverse-spend, preferred-supplier, risk, savings, and
  realization reporting.

## Release 2 acceptance criteria

- An administrator can change workspace defaults and immediately see them used
  in the relevant UI without changing historical financial meaning.
- A procurement user can create and maintain a supplier without creating a
  project first.
- A supplier profile reconciles its project, award, savings, and realization
  totals to the existing portfolio methodology.
- Viewers cannot mutate settings or supplier records.
- Invalid or unauthorized requests fail loudly and do not partially update.
- Cross-workspace access tests pass for every new table and mutation.
- Desktop, tablet, and mobile layouts match the Concept B information hierarchy.
