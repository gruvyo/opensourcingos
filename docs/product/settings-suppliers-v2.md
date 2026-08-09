# Settings and Suppliers v2

## Implementation status

Release 2 is live on `main`: workspace settings are editable and atomic,
administrators can govern Support projects and the optional project description,
owner, Cost Center, Category, Business Unit, Project Updates, and Incumbent
Supplier features,
supplier records can be created independently, and supplier profiles reconcile
projects, awards, negotiated savings, realized savings, and audit history.
Database policies make viewers read-only while administrators and procurement
users receive the intended editing rights.

Workspace Classification Management extends Settings with administrator-managed
Event Type, Status, Owner, Category, Business Unit, and Cost Center choices.
Archived choices remain visible on historical projects but cannot be selected
for new or changed values. Renaming a text-backed choice updates projects and
reporting consistently; no project record is deleted or silently cleared.

The beta template keeps these concepts separate. Categories describe what is
being bought, using eight broad product/service markets. Business Units describe
the internal organization that owns demand, using four editable sample units.
Cost Centers receive no generic defaults because they are organization-specific
accounting values; administrators add the values that match their own chart of
accounts. Existing Cost Center relationships remain protected and auditable.

Workspace Governance Visibility adds a dedicated, read-only Governance page.
Every signed-in workspace member can see the current member roster and the same
organization-scoped audit records already protected by Row Level Security. The
history is newest-first, filterable, and paginated in groups of 50. It translates
database actions into business language and shows a small allowlisted change
summary rather than dumping raw records, notes, identifiers, or internal metadata.
System migrations and former members remain distinguishable from current actors.

Supplier Relationship Readiness extends Reports using the supplier fields already
shipped in Release 2. The report makes relationship owner, next review, risk,
preferred/diverse attributes, and project/award linkage visible in one exportable
view. Separate Attention and Setup Gaps columns keep high risk and overdue
reviews visible alongside a missing owner, review date, or risk rating. Filters cover supplier status,
risk, attributes, and readiness without changing supplier records.

Normalized supplier names are unique within each workspace. Membership
invitations and role changes, scored performance reviews, certifications,
duplicate merge, and portfolio concentration remain Release 3 work.

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
3. **People and roles** — the current roster is visible; inviting members,
   assigning `admin`, `procurement_user`, or `viewer`, and showing pending access
   remain planned.
4. **Data and integrations** — exports, API/integration status, and connection
   health. Secrets remain in the deployment platform, never in browser forms.
5. **Audit and safety** — a read-only audit history is now available; workspace
   ID, detailed RLS status, and clearly separated destructive actions remain planned.
6. **Workspace choices** — active and archived Event Types, Statuses, Owners,
   Categories, Business Units, and Cost Centers used by project forms and
   portfolio reporting.

### Data additions

- `organization_settings`: currency, locale, timezone, fiscal year start month,
  date format, and methodology defaults.
- `organization_memberships` or an extension of `profiles`: explicit status,
  invitation state, and role-change timestamps.
- `audit_log`: actor, workspace, action, entity, before/after summary, and time.
- `project_choice_options`: organization-scoped Event Type, Status, and Owner
  choices. Existing Category, Business Unit, and Cost Center tables use the
  same active/archive behavior.

### Workspace-choice behavior

- Adding a choice makes it available to new and edited projects immediately.
- Renaming an Event Type, Status, or Owner updates projects using that choice;
  relational Category, Business Unit, and Cost Center names update through
  their existing references.
- Archiving removes a choice from new selections. Existing projects keep and
  display it, and unrelated edits remain possible.
- Restoring makes an archived choice selectable again.
- Choice names are unique within their workspace and classification scope,
  without regard to capitalization or surrounding spaces.
- Only workspace administrators can add, rename, archive, or restore choices.
  Database policies and project-write triggers enforce these rules even when a
  client bypasses the application form.
- The built-in Type and Status taxonomy is defined in
  [`project-classification-defaults.md`](./project-classification-defaults.md).
  Sourcing Type explains why the project exists; commercial value levers remain
  in the savings evidence chain rather than being duplicated as project types.

All new tables require forced Row Level Security, organization-scoped policies,
indexes on `organization_id`, and tests proving cross-workspace isolation.

### Project Updates behavior

- The Project Updates setting defaults on for existing and new workspaces.
- Turning it off removes the initial-update field from project creation and the
  update composer from project details.
- The Updates tab and all existing dated history remain readable.
- Database enforcement rejects direct inserts while the setting is off, and
  re-enabling the setting restores new updates without changing history.

### Project Incumbent Supplier behavior

- The Incumbent Supplier setting defaults on for existing and new workspaces.
- Turning it off removes the field from project creation and editing.
- Existing incumbent assignments remain visible in project details, project
  lists, supplier profiles, and reports.
- Database enforcement rejects additions, replacements, and clearing while the
  setting is off, while unrelated project edits remain available.
- Re-enabling restores the field without changing existing assignments.

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
- Normalized-name uniqueness within each organization and its supporting indexes
  are implemented. An audited supplier-merge database function unavailable to
  browser users remains planned.

## Delivery sequence

### Release 1 — shipped foundation

- Concept B application shell and shared page hierarchy.
- Supplier portfolio summary, search, filters, status, risk, preference,
  diversity, project links, and awards.
- Settings overview with correct identity, organization, reporting conventions,
  methodology controls, and platform connections.

### Release 2 — shipped operating controls

- Database migration for organization settings and supplier master details.
- Authenticated, validated server actions for settings and supplier edits.
- Supplier profile route with sourcing, award, savings, and realization history.
- Role-aware controls and complete loading, success, and failure feedback.

### Release 3 — planned governance and intelligence

- Read-only membership roster and audit history are shipped; invitations and
  role administration remain planned.
- Supplier Relationship Readiness reporting is shipped; it exposes owner,
  review-date, risk, attribute, and linkage gaps from the current supplier model.
- The dashboard attention queue is shipped for urgent supplier risk and overdue
  review items, alongside overdue and upcoming project deadlines. Automated
  reminders remain planned.
- Supplier Portfolio Value reporting is shipped for awarded spend, spend and
  savings concentration, preferred/diverse attributes, risk, estimated and
  executed savings, and optional realized savings.
- Named supplier contacts are shipped with role/title, email, phone, one
  primary-contact designation, role-aware maintenance, tenant isolation, and
  workspace audit history.
- Dated supplier relationship notes are shipped as an append-only timeline for
  review context, risk evidence, and follow-up. Workspace members can read the
  timeline; administrators and procurement users can add entries.
- Supplier performance reviews, certifications, and risk evidence.
- Duplicate detection and audited supplier merge.
- Broader diverse-spend and preferred-supplier target reporting remains planned.

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
