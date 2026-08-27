begin;

-- The browser client never has a public-data use case. Keep the Data API
-- closed to signed-out callers even when a future migration creates an RLS
-- policy accidentally.
revoke all on all tables in schema public from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

-- Every application table is readable by signed-in workspace members. RLS
-- remains the row-level boundary and is forced on all 27 tables.
grant select on table
  public.audit_log,
  public.award_lines,
  public.awards,
  public.baseline_lines,
  public.baselines,
  public.business_units,
  public.categories,
  public.cost_centers,
  public.event_scope_lines,
  public.organization_settings,
  public.organizations,
  public.profiles,
  public.project_choice_options,
  public.project_updates,
  public.realization_periods,
  public.savings_calculation_lines,
  public.savings_calculations,
  public.savings_periods,
  public.sourcing_events,
  public.supplier_certifications,
  public.supplier_contacts,
  public.supplier_notes,
  public.supplier_offer_lines,
  public.supplier_offers,
  public.supplier_performance_reviews,
  public.supplier_risks,
  public.suppliers
to authenticated;

-- Direct inserts used by current browser/server-action workflows. Workspace
-- settings and identity rows remain RPC/trigger-only.
grant insert on table
  public.baseline_lines,
  public.baselines,
  public.business_units,
  public.categories,
  public.cost_centers,
  public.event_scope_lines,
  public.project_choice_options,
  public.project_updates,
  public.realization_periods,
  public.savings_calculations,
  public.savings_periods,
  public.sourcing_events,
  public.supplier_certifications,
  public.supplier_contacts,
  public.supplier_notes,
  public.supplier_offer_lines,
  public.supplier_offers,
  public.supplier_performance_reviews,
  public.supplier_risks,
  public.suppliers
to authenticated;

-- Append-only activity tables are intentionally absent. Organization,
-- profile, settings, audit, legacy award, and legacy calculation-line tables
-- are also absent because their current client paths are read-only or RPC-only.
grant update on table
  public.baseline_lines,
  public.baselines,
  public.business_units,
  public.categories,
  public.cost_centers,
  public.event_scope_lines,
  public.project_choice_options,
  public.realization_periods,
  public.savings_calculations,
  public.savings_periods,
  public.sourcing_events,
  public.supplier_certifications,
  public.supplier_contacts,
  public.supplier_offer_lines,
  public.supplier_offers,
  public.supplier_performance_reviews,
  public.supplier_risks,
  public.suppliers
to authenticated;

-- Deletes are limited to current operational delete flows. Cascade cleanup
-- does not require direct privileges on the child table.
grant delete on table
  public.baseline_lines,
  public.baselines,
  public.event_scope_lines,
  public.realization_periods,
  public.savings_periods,
  public.sourcing_events,
  public.supplier_certifications,
  public.supplier_contacts,
  public.supplier_offer_lines,
  public.supplier_offers,
  public.supplier_performance_reviews,
  public.supplier_risks,
  public.suppliers
to authenticated;

-- Settings are the only current multi-table tenant RPC. It already resolves
-- auth.uid(), checks the caller's workspace and admin role, and constrains all
-- writes to those resolved IDs. Definer rights let the underlying tables stay
-- read-only to authenticated clients.
alter function public.update_workspace_settings_v9(
  text, text, text, text, text, integer, text, text, boolean, numeric,
  boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean
) security definer;

-- Exact authenticated RPC allowlist. Old settings signatures remain installed
-- for migration reproducibility but are no longer exposed through the API.
grant execute on function public.current_org_id() to authenticated;
grant execute on function public.mark_savings_schedule_executed(uuid, text)
  to authenticated;
grant execute on function public.update_workspace_settings_v9(
  text, text, text, text, text, integer, text, text, boolean, numeric,
  boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean
) to authenticated;

-- Future public objects created by application migrations are private until a
-- reviewed migration opts them into the Data API. Supabase documents these
-- customer-managed defaults for `postgres`; defaults owned by
-- `supabase_admin` are platform-managed and cannot be changed by a customer
-- migration.
alter default privileges for role postgres in schema public
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

commit;
