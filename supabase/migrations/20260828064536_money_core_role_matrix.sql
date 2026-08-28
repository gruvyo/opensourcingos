begin;

-- Modification 4B: make the approved money-core role matrix enforceable at
-- both privilege and row-policy layers. Viewer remains read-only;
-- procurement_user and admin may perform ordinary commercial writes; only
-- admin may delete money-core records. Protected lifecycle, approval,
-- decision, finance, and actor columns remain RPC/trigger-owned.

-- Remove every prior table- and column-level write grant before installing
-- the reviewed per-table manifests below. REVOKE at table scope alone does
-- not remove column grants in PostgreSQL.
do $$
declare
  v_table text;
  v_columns text;
begin
  foreach v_table in array array[
    'sourcing_events', 'event_scope_lines', 'baselines', 'baseline_lines',
    'supplier_offers', 'supplier_offer_lines', 'awards', 'award_lines',
    'savings_calculations', 'savings_calculation_lines',
    'savings_periods', 'realization_periods'
  ] loop
    select string_agg(format('%I', column_name), ', ' order by ordinal_position)
      into v_columns
    from information_schema.columns
    where table_schema = 'public' and table_name = v_table;

    execute format(
      'revoke insert (%s), update (%s) on table public.%I from authenticated',
      v_columns, v_columns, v_table
    );
    execute format(
      'revoke insert, update, delete on table public.%I from authenticated',
      v_table
    );
  end loop;
end
$$;

-- Safe direct-write manifests. IDs, workspace keys, and parent keys are
-- accepted only at creation. Timestamps and actors are server-owned.
grant insert (
  id, organization_id, event_name, event_description, event_type,
  sourcing_method, category_id, business_unit_id, cost_center_id,
  incumbent_supplier_id, procurement_owner_id, business_owner_id,
  finance_owner_id, event_status, currency_code, fx_rate_to_usd,
  event_start_date, event_close_date, contract_start_date, contract_end_date,
  recognition_start_date, recognition_end_date, official_reporting_basis,
  project_type, buyer_name, notes, project_due_date
) on public.sourcing_events to authenticated;
grant update (
  event_name, event_description, event_type, sourcing_method, category_id,
  business_unit_id, cost_center_id, incumbent_supplier_id,
  procurement_owner_id, business_owner_id, finance_owner_id, event_status,
  currency_code, fx_rate_to_usd, event_start_date, event_close_date,
  contract_start_date, contract_end_date, recognition_start_date,
  recognition_end_date, official_reporting_basis, project_type, buyer_name,
  notes, project_due_date
) on public.sourcing_events to authenticated;

grant insert (
  id, organization_id, event_id, line_number, category_id,
  item_service_name, item_description, uom, location_id,
  baseline_quantity, forecast_quantity, final_quantity,
  scope_change_flag, scope_change_description
) on public.event_scope_lines to authenticated;
grant update (
  line_number, category_id, item_service_name, item_description, uom,
  location_id, baseline_quantity, forecast_quantity, final_quantity,
  scope_change_flag, scope_change_description
) on public.event_scope_lines to authenticated;

grant insert (
  id, organization_id, event_id, baseline_name, baseline_type,
  baseline_source, baseline_period_start, baseline_period_end,
  baseline_currency_code, baseline_fx_rate_to_usd, baseline_total_amount,
  baseline_normalized_amount, normalization_notes, baseline_lock_status,
  baseline_lock_date, official_for_hard_savings,
  official_for_cost_avoidance, official_for_demand_reduction,
  baseline_term_months
) on public.baselines to authenticated;
grant update (
  baseline_name, baseline_type, baseline_source, baseline_period_start,
  baseline_period_end, baseline_currency_code, baseline_fx_rate_to_usd,
  baseline_total_amount, baseline_normalized_amount, normalization_notes,
  baseline_lock_status, baseline_lock_date, official_for_hard_savings,
  official_for_cost_avoidance, official_for_demand_reduction,
  baseline_term_months
) on public.baselines to authenticated;

grant insert (
  id, organization_id, baseline_id, event_id, scope_line_id, line_number,
  baseline_unit_price, baseline_quantity, baseline_extended_amount,
  baseline_recurring_amount, baseline_one_time_amount, baseline_term_months,
  annualized_baseline_amount, normalized_quantity, normalized_unit_price,
  normalized_extended_amount, tax_amount_included, freight_amount_included,
  source_document_id, notes
) on public.baseline_lines to authenticated;
grant update (
  scope_line_id, line_number, baseline_unit_price, baseline_quantity,
  baseline_extended_amount, baseline_recurring_amount,
  baseline_one_time_amount, baseline_term_months,
  annualized_baseline_amount, normalized_quantity, normalized_unit_price,
  normalized_extended_amount, tax_amount_included, freight_amount_included,
  source_document_id, notes
) on public.baseline_lines to authenticated;

grant insert (
  id, organization_id, event_id, supplier_id, offer_type, offer_round,
  offer_date, offer_currency_code, fx_rate_to_usd, offer_total_amount,
  offer_valid_until, compliant_bid_flag, selected_for_award_flag,
  source_document_id, notes, offer_term_months
) on public.supplier_offers to authenticated;
grant update (
  supplier_id, offer_type, offer_round, offer_date, offer_currency_code,
  fx_rate_to_usd, offer_total_amount, offer_valid_until, compliant_bid_flag,
  selected_for_award_flag, source_document_id, notes, offer_term_months
) on public.supplier_offers to authenticated;

grant insert (
  id, organization_id, offer_id, event_id, scope_line_id, line_number,
  offer_unit_price, offer_quantity, offer_extended_amount,
  offer_recurring_amount, offer_one_time_amount, offer_term_months,
  annualized_offer_amount, compliance_status, exclusion_notes
) on public.supplier_offer_lines to authenticated;
grant update (
  scope_line_id, line_number, offer_unit_price, offer_quantity,
  offer_extended_amount, offer_recurring_amount, offer_one_time_amount,
  offer_term_months, annualized_offer_amount, compliance_status,
  exclusion_notes
) on public.supplier_offer_lines to authenticated;

grant insert (
  id, organization_id, event_id, supplier_id, offer_id, award_name,
  award_date, award_total_amount, award_status, award_notes
) on public.awards to authenticated;
grant update (
  supplier_id, offer_id, award_name, award_date, award_total_amount,
  award_status, award_notes
) on public.awards to authenticated;

grant insert (
  id, organization_id, award_id, event_id, scope_line_id, line_number,
  awarded_unit_price, awarded_quantity, awarded_extended_amount,
  awarded_recurring_amount, awarded_one_time_amount, awarded_term_months,
  annualized_award_amount
) on public.award_lines to authenticated;
grant update (
  scope_line_id, line_number, awarded_unit_price, awarded_quantity,
  awarded_extended_amount, awarded_recurring_amount,
  awarded_one_time_amount, awarded_term_months, annualized_award_amount
) on public.award_lines to authenticated;

grant insert (
  id, organization_id, event_id, baseline_id, award_id,
  calculation_name, savings_type, baseline_total_amount, award_total_amount,
  gross_savings_amount, savings_percentage, net_savings_amount,
  recognition_notes, savings_start_date, savings_end_date,
  cost_reduction_amount, cost_avoidance_amount, opening_proposal_amount,
  schedule_start_month, schedule_start_year, schedule_period_type,
  schedule_period_count
) on public.savings_calculations to authenticated;
grant update (
  baseline_id, award_id, calculation_name, savings_type,
  baseline_total_amount, award_total_amount, gross_savings_amount,
  savings_percentage, net_savings_amount, recognition_notes,
  savings_start_date, savings_end_date, cost_reduction_amount,
  cost_avoidance_amount, opening_proposal_amount, schedule_start_month,
  schedule_start_year, schedule_period_type, schedule_period_count
) on public.savings_calculations to authenticated;

grant insert (
  id, organization_id, savings_calculation_id, event_id, scope_line_id,
  line_number, baseline_unit_price, baseline_quantity,
  baseline_extended_amount, awarded_unit_price, awarded_quantity,
  awarded_extended_amount, savings_amount, savings_percentage, savings_type
) on public.savings_calculation_lines to authenticated;
grant update (
  scope_line_id, line_number, baseline_unit_price, baseline_quantity,
  baseline_extended_amount, awarded_unit_price, awarded_quantity,
  awarded_extended_amount, savings_amount, savings_percentage, savings_type
) on public.savings_calculation_lines to authenticated;

-- Schedule creation/deletion remains atomic-RPC-only. Direct edits are
-- limited to estimated-side values and are further gated by RLS below.
grant update (
  baseline_amount, opening_amount, final_amount, cost_reduction_amount,
  cost_avoidance_amount, total_savings_amount, is_edited, notes
) on public.savings_periods to authenticated;

-- Realization shells are sync-RPC-only. Direct P/A edits are actual-result
-- inputs and derived realization fields; finance attestation is RPC-only.
grant update (
  actual_amount, realized_savings, leakage_amount, leakage_reason,
  realization_status, evidence_document_id, notes
) on public.realization_periods to authenticated;

grant delete on table
  public.sourcing_events, public.event_scope_lines,
  public.baselines, public.baseline_lines,
  public.supplier_offers, public.supplier_offer_lines,
  public.awards, public.award_lines,
  public.savings_calculations, public.savings_calculation_lines,
  public.realization_periods
to authenticated;

-- Standard money-core rows: org-scoped P/A insert and update, admin delete.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'sourcing_events', 'event_scope_lines', 'baselines', 'baseline_lines',
    'supplier_offers', 'supplier_offer_lines', 'awards', 'award_lines',
    'savings_calculation_lines'
  ] loop
    execute format('drop policy if exists org_insert on public.%I', v_table);
    execute format($policy$
      create policy org_insert on public.%I for insert to authenticated
      with check (
        organization_id = public.current_org_id()
        and exists (
          select 1 from public.profiles profile
          where profile.id = auth.uid()
            and profile.organization_id = public.current_org_id()
            and profile.role in ('admin', 'procurement_user')
        )
      )$policy$, v_table);

    execute format('drop policy if exists org_update on public.%I', v_table);
    execute format($policy$
      create policy org_update on public.%I for update to authenticated
      using (
        organization_id = public.current_org_id()
        and exists (
          select 1 from public.profiles profile
          where profile.id = auth.uid()
            and profile.organization_id = public.current_org_id()
            and profile.role in ('admin', 'procurement_user')
        )
      )
      with check (
        organization_id = public.current_org_id()
        and exists (
          select 1 from public.profiles profile
          where profile.id = auth.uid()
            and profile.organization_id = public.current_org_id()
            and profile.role in ('admin', 'procurement_user')
        )
      )$policy$, v_table);

    execute format('drop policy if exists org_delete on public.%I', v_table);
    execute format($policy$
      create policy org_delete on public.%I for delete to authenticated
      using (
        organization_id = public.current_org_id()
        and exists (
          select 1 from public.profiles profile
          where profile.id = auth.uid()
            and profile.organization_id = public.current_org_id()
            and profile.role = 'admin'
        )
      )$policy$, v_table);
  end loop;
end
$$;

-- Estimated calculations retain the lifecycle gate from Modification 3B.
drop policy if exists org_insert on public.savings_calculations;
create policy org_insert on public.savings_calculations
for insert to authenticated
with check (
  organization_id = public.current_org_id()
  and calculation_status = 'estimated'
  and exists (
    select 1 from public.profiles profile
    where profile.id = auth.uid()
      and profile.organization_id = public.current_org_id()
      and profile.role in ('admin', 'procurement_user')
  )
);

drop policy if exists org_update on public.savings_calculations;
create policy org_update on public.savings_calculations
for update to authenticated
using (
  organization_id = public.current_org_id()
  and calculation_status = 'estimated'
  and exists (
    select 1 from public.profiles profile
    where profile.id = auth.uid()
      and profile.organization_id = public.current_org_id()
      and profile.role in ('admin', 'procurement_user')
  )
)
with check (
  organization_id = public.current_org_id()
  and calculation_status = 'estimated'
  and exists (
    select 1 from public.profiles profile
    where profile.id = auth.uid()
      and profile.organization_id = public.current_org_id()
      and profile.role in ('admin', 'procurement_user')
  )
);

drop policy if exists org_delete on public.savings_calculations;
create policy org_delete on public.savings_calculations
for delete to authenticated
using (
  organization_id = public.current_org_id()
  and calculation_status = 'estimated'
  and exists (
    select 1 from public.profiles profile
    where profile.id = auth.uid()
      and profile.organization_id = public.current_org_id()
      and profile.role = 'admin'
  )
);

-- Schedule replacement owns insert/delete. Ordinary direct updates require an
-- estimated parent and a P/A caller.
drop policy if exists org_insert on public.savings_periods;
create policy org_insert on public.savings_periods
for insert to authenticated with check (false);

drop policy if exists org_update on public.savings_periods;
create policy org_update on public.savings_periods
for update to authenticated
using (
  organization_id = public.current_org_id()
  and exists (
    select 1 from public.savings_calculations calculation
    where calculation.id = savings_periods.savings_calculation_id
      and calculation.organization_id = public.current_org_id()
      and calculation.calculation_status = 'estimated'
  )
  and exists (
    select 1 from public.profiles profile
    where profile.id = auth.uid()
      and profile.organization_id = public.current_org_id()
      and profile.role in ('admin', 'procurement_user')
  )
)
with check (
  organization_id = public.current_org_id()
  and exists (
    select 1 from public.savings_calculations calculation
    where calculation.id = savings_periods.savings_calculation_id
      and calculation.organization_id = public.current_org_id()
      and calculation.calculation_status = 'estimated'
  )
  and exists (
    select 1 from public.profiles profile
    where profile.id = auth.uid()
      and profile.organization_id = public.current_org_id()
      and profile.role in ('admin', 'procurement_user')
  )
);

drop policy if exists org_delete on public.savings_periods;
create policy org_delete on public.savings_periods
for delete to authenticated using (false);

-- Realization shells are created only by sync_realization_periods. P/A may
-- edit actual results; admin may delete only an unvalidated shell/record.
drop policy if exists org_insert on public.realization_periods;
create policy org_insert on public.realization_periods
for insert to authenticated with check (false);

drop policy if exists org_update on public.realization_periods;
create policy org_update on public.realization_periods
for update to authenticated
using (
  organization_id = public.current_org_id()
  and exists (
    select 1 from public.profiles profile
    where profile.id = auth.uid()
      and profile.organization_id = public.current_org_id()
      and profile.role in ('admin', 'procurement_user')
  )
)
with check (
  organization_id = public.current_org_id()
  and exists (
    select 1 from public.profiles profile
    where profile.id = auth.uid()
      and profile.organization_id = public.current_org_id()
      and profile.role in ('admin', 'procurement_user')
  )
);

drop policy if exists org_delete on public.realization_periods;
create policy org_delete on public.realization_periods
for delete to authenticated
using (
  organization_id = public.current_org_id()
  and not coalesce(finance_validated, false)
  and exists (
    select 1 from public.profiles profile
    where profile.id = auth.uid()
      and profile.organization_id = public.current_org_id()
      and profile.role = 'admin'
  )
);

-- Completing a sourcing project is a protected lifecycle transition because
-- status and the four disposition fields must change together. This preserves
-- the shipped "complete without executed savings" path after those columns
-- leave the browser's direct grant list.
create function public.complete_sourcing_project(
  p_event_id uuid,
  p_disposition text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_status text;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if v_user is null then raise exception 'authentication required'; end if;

  select organization_id, role into v_org, v_role
  from public.profiles where id = v_user;
  if v_org is null then raise exception 'workspace membership required'; end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;
  if p_disposition not in ('executed', 'no_executed_savings') then
    raise exception 'valid savings disposition required';
  end if;

  select event_status into v_status
  from public.sourcing_events
  where id = p_event_id
    and organization_id = v_org
    and project_type = 'Sourcing'
  for update;
  if not found then raise exception 'sourcing project not found'; end if;
  if v_status = 'Complete' then raise exception 'project already complete'; end if;

  if p_disposition = 'executed' then
    if not exists (
      select 1 from public.savings_calculations calculation
      where calculation.event_id = p_event_id
        and calculation.organization_id = v_org
        and calculation.calculation_status = 'executed'
    ) then
      raise exception 'executed savings schedule required';
    end if;
    v_reason := coalesce(v_reason, 'Savings schedule was marked executed before completion.');
  else
    if coalesce(length(v_reason), 0) < 10 then
      raise exception 'completion reason must contain at least 10 characters';
    end if;
    if exists (
      select 1 from public.savings_calculations calculation
      where calculation.event_id = p_event_id
        and calculation.organization_id = v_org
        and calculation.calculation_status = 'executed'
    ) then
      raise exception 'executed savings must use the executed disposition';
    end if;
  end if;

  update public.sourcing_events
  set event_status = 'Complete',
      savings_disposition = p_disposition,
      savings_disposition_reason = v_reason,
      savings_disposition_at = now(),
      savings_disposition_by = v_user,
      updated_by = v_user,
      updated_at = now()
  where id = p_event_id and organization_id = v_org;
end
$$;

revoke all on function public.complete_sourcing_project(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.complete_sourcing_project(uuid, text, text)
  to authenticated;

-- Atomically create the missing realization shells from an executed schedule.
-- The browser supplies only the project ID; the database resolves membership,
-- role, setting, schedule, snapshots, dates, and actors under one event lock.
create function public.sync_realization_periods(p_event_id uuid)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_inserted integer := 0;
begin
  if v_user is null then raise exception 'authentication required'; end if;

  select organization_id, role into v_org, v_role
  from public.profiles where id = v_user;
  if v_org is null then raise exception 'workspace membership required'; end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;

  perform 1
  from public.sourcing_events event
  where event.id = p_event_id
    and event.organization_id = v_org
    and event.project_type = 'Sourcing'
  for update;
  if not found then raise exception 'sourcing project not found'; end if;

  if not coalesce((
    select settings.savings_realization_enabled
    from public.organization_settings settings
    where settings.organization_id = v_org
  ), false) then
    raise exception 'Savings Realization is disabled for this workspace';
  end if;

  insert into public.realization_periods (
    organization_id, event_id, savings_calculation_id, savings_period_id,
    period_name, period_start_date, period_end_date,
    baseline_amount, actual_amount, projected_savings, realized_savings,
    leakage_amount, realization_status, created_by, updated_by
  )
  select
    period.organization_id,
    period.event_id,
    period.savings_calculation_id,
    period.id,
    to_char(make_date(period.period_year, period.period_month, 1), 'Mon YYYY'),
    make_date(period.period_year, period.period_month, 1),
    (
      make_date(period.period_year, period.period_month, 1)
      + make_interval(months => greatest(1, round(period.period_months)::integer))
      - interval '1 day'
    )::date,
    period.executed_baseline_amount,
    null,
    period.executed_total_savings_amount,
    null,
    null,
    'Pending',
    v_user,
    v_user
  from public.savings_periods period
  join public.savings_calculations calculation
    on calculation.id = period.savings_calculation_id
   and calculation.organization_id = period.organization_id
   and calculation.event_id = period.event_id
  where period.organization_id = v_org
    and period.event_id = p_event_id
    and calculation.calculation_status = 'executed'
    and period.executed_total_savings_amount is not null
    and period.executed_final_amount is not null
    and period.executed_cost_avoidance_amount is not null
    and not exists (
      select 1 from public.realization_periods existing
      where existing.savings_period_id = period.id
    )
  order by period.period_number
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end
$$;

revoke all on function public.sync_realization_periods(uuid)
  from public, anon, authenticated;
grant execute on function public.sync_realization_periods(uuid)
  to authenticated;

-- Cover the actor FKs added in 4A. These indexes also keep profile deletion
-- and advisor checks from scanning the money-detail tables.
create index idx_event_scope_lines_created_by
  on public.event_scope_lines(created_by) where created_by is not null;
create index idx_event_scope_lines_updated_by
  on public.event_scope_lines(updated_by) where updated_by is not null;
create index idx_baseline_lines_created_by
  on public.baseline_lines(created_by) where created_by is not null;
create index idx_baseline_lines_updated_by
  on public.baseline_lines(updated_by) where updated_by is not null;
create index idx_supplier_offer_lines_created_by
  on public.supplier_offer_lines(created_by) where created_by is not null;
create index idx_supplier_offer_lines_updated_by
  on public.supplier_offer_lines(updated_by) where updated_by is not null;
create index idx_award_lines_created_by
  on public.award_lines(created_by) where created_by is not null;
create index idx_award_lines_updated_by
  on public.award_lines(updated_by) where updated_by is not null;
create index idx_savings_calculation_lines_created_by
  on public.savings_calculation_lines(created_by) where created_by is not null;
create index idx_savings_calculation_lines_updated_by
  on public.savings_calculation_lines(updated_by) where updated_by is not null;

commit;
