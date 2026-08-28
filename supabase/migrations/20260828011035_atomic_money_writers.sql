begin;

-- The three decisions below each span more than one row (and, for offers and
-- schedules, more than one table). Keep them inside one database transaction
-- and derive workspace/actor identity from the authenticated session.

create function public.select_baseline(p_baseline_id uuid)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_event uuid;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;

  select organization_id, role into v_org, v_role
  from public.profiles
  where id = v_user;

  if v_org is null then
    raise exception 'workspace membership required';
  end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;

  select event_id into v_event
  from public.baselines
  where id = p_baseline_id
    and organization_id = v_org;

  if v_event is null then
    raise exception 'baseline not found';
  end if;

  -- The parent lock serializes two callers selecting different baselines for
  -- the same project. Lock every tuple before applying the invariant.
  perform 1
  from public.sourcing_events
  where id = v_event and organization_id = v_org
  for update;

  perform 1
  from public.baselines
  where event_id = v_event and organization_id = v_org
  order by id
  for update;

  if not exists (
    select 1 from public.baselines
    where id = p_baseline_id
      and event_id = v_event
      and organization_id = v_org
  ) then
    raise exception 'baseline not found';
  end if;

  update public.baselines
  set is_selected = false, updated_by = v_user, updated_at = now()
  where event_id = v_event
    and organization_id = v_org
    and id <> p_baseline_id
    and is_selected;

  update public.baselines
  set is_selected = true, updated_by = v_user, updated_at = now()
  where id = p_baseline_id
    and event_id = v_event
    and organization_id = v_org
    and not is_selected;
end
$$;

create function public.set_offer_role(
  p_offer_id uuid,
  p_role text default null
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
  v_event uuid;
  v_final_supplier uuid;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;
  if p_role is not null and p_role not in ('opening', 'final') then
    raise exception 'offer role must be opening, final, or null';
  end if;

  select organization_id, role into v_org, v_role
  from public.profiles
  where id = v_user;

  if v_org is null then
    raise exception 'workspace membership required';
  end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;

  select event_id into v_event
  from public.supplier_offers
  where id = p_offer_id
    and organization_id = v_org;

  if v_event is null then
    raise exception 'offer not found';
  end if;

  -- The event row is the shared mutex for role changes and the award pointer.
  perform 1
  from public.sourcing_events
  where id = v_event and organization_id = v_org
  for update;

  perform 1
  from public.supplier_offers
  where event_id = v_event and organization_id = v_org
  order by id
  for update;

  if not exists (
    select 1 from public.supplier_offers
    where id = p_offer_id
      and event_id = v_event
      and organization_id = v_org
  ) then
    raise exception 'offer not found';
  end if;

  if p_role is not null then
    update public.supplier_offers
    set offer_role = null, updated_by = v_user, updated_at = now()
    where event_id = v_event
      and organization_id = v_org
      and id <> p_offer_id
      and offer_role = p_role;
  end if;

  update public.supplier_offers
  set offer_role = p_role, updated_by = v_user, updated_at = now()
  where id = p_offer_id
    and event_id = v_event
    and organization_id = v_org
    and offer_role is distinct from p_role;

  -- Resolve the winner from the locked database rows, never from browser state.
  select supplier_id into v_final_supplier
  from public.supplier_offers
  where event_id = v_event
    and organization_id = v_org
    and offer_role = 'final';

  if exists (
    select 1 from public.supplier_offers
    where event_id = v_event
      and organization_id = v_org
      and offer_role = 'final'
      and supplier_id is null
  ) then
    raise exception 'a final offer must name a supplier';
  end if;

  update public.sourcing_events
  set awarded_supplier_id = v_final_supplier,
      updated_by = v_user,
      updated_at = now()
  where id = v_event
    and organization_id = v_org
    and awarded_supplier_id is distinct from v_final_supplier;
end
$$;

create function public.replace_savings_schedule(
  p_savings_calculation_id uuid,
  p_schedule_start_month integer,
  p_schedule_start_year integer,
  p_schedule_period_type text,
  p_periods jsonb
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
  v_event uuid;
  v_status text;
  v_count integer;
  v_months numeric;
  v_baseline numeric;
  v_opening numeric;
  v_final numeric;
  v_reduction numeric;
  v_avoidance numeric;
  v_total numeric;
  v_end_date date;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;

  select organization_id, role into v_org, v_role
  from public.profiles
  where id = v_user;

  if v_org is null then
    raise exception 'workspace membership required';
  end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;
  if p_schedule_start_month not between 1 and 12 then
    raise exception 'schedule start month must be between 1 and 12';
  end if;
  if p_schedule_start_year not between 2000 and 2100 then
    raise exception 'schedule start year must be between 2000 and 2100';
  end if;
  if p_schedule_period_type not in ('monthly', 'annual', 'one_time') then
    raise exception 'unsupported schedule period type';
  end if;
  if jsonb_typeof(p_periods) is distinct from 'array' then
    raise exception 'periods must be a JSON array';
  end if;

  v_count := jsonb_array_length(p_periods);
  if v_count not between 1 and 600 then
    raise exception 'schedule must contain between 1 and 600 periods';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_periods) as period_item(value)
    cross join lateral jsonb_object_keys(period_item.value) as period_key(field_name)
    where period_key.field_name not in (
      'period_number', 'period_month', 'period_year', 'period_months',
      'baseline_amount', 'opening_amount', 'final_amount',
      'cost_reduction_amount', 'cost_avoidance_amount',
      'total_savings_amount', 'is_edited', 'notes'
    )
  ) then
    raise exception 'period payload contains unsupported fields';
  end if;

  select event_id, calculation_status into v_event, v_status
  from public.savings_calculations
  where id = p_savings_calculation_id
    and organization_id = v_org
  for update;

  if v_event is null then
    raise exception 'savings calculation not found';
  end if;
  if v_status <> 'estimated' then
    raise exception 'executed schedules are preserved and cannot be regenerated';
  end if;

  perform 1
  from public.sourcing_events
  where id = v_event and organization_id = v_org
  for update;

  perform 1
  from public.savings_periods
  where savings_calculation_id = p_savings_calculation_id
    and organization_id = v_org
  order by id
  for update;

  -- Intentionally replace before parsing/inserting the rows. Any malformed row
  -- or constraint failure aborts the RPC transaction and restores the prior
  -- schedule and published header automatically.
  delete from public.savings_periods
  where savings_calculation_id = p_savings_calculation_id
    and organization_id = v_org;

  insert into public.savings_periods (
    organization_id, event_id, savings_calculation_id,
    period_number, period_month, period_year, period_months,
    baseline_amount, opening_amount, final_amount,
    cost_reduction_amount, cost_avoidance_amount, total_savings_amount,
    is_edited, notes, created_by, updated_by
  )
  select
    v_org, v_event, p_savings_calculation_id,
    row.period_number, row.period_month, row.period_year, row.period_months,
    row.baseline_amount, row.opening_amount, row.final_amount,
    row.cost_reduction_amount, row.cost_avoidance_amount,
    row.total_savings_amount, coalesce(row.is_edited, false), row.notes,
    v_user, v_user
  from jsonb_to_recordset(p_periods) as row(
    period_number integer,
    period_month integer,
    period_year integer,
    period_months numeric,
    baseline_amount numeric,
    opening_amount numeric,
    final_amount numeric,
    cost_reduction_amount numeric,
    cost_avoidance_amount numeric,
    total_savings_amount numeric,
    is_edited boolean,
    notes text
  );

  if (
    select count(*) <> v_count
      or count(distinct period_number) <> v_count
      or min(period_number) <> 1
      or max(period_number) <> v_count
    from public.savings_periods
    where savings_calculation_id = p_savings_calculation_id
      and organization_id = v_org
  ) then
    raise exception 'period numbers must be unique and contiguous from 1';
  end if;

  select
    coalesce(sum(period_months), 0),
    coalesce(sum(baseline_amount), 0),
    coalesce(sum(opening_amount), 0),
    coalesce(sum(final_amount), 0),
    case when count(cost_reduction_amount) = 0 then null
         else sum(cost_reduction_amount) end,
    coalesce(sum(cost_avoidance_amount), 0),
    coalesce(sum(total_savings_amount), 0)
  into v_months, v_baseline, v_opening, v_final,
       v_reduction, v_avoidance, v_total
  from public.savings_periods
  where savings_calculation_id = p_savings_calculation_id
    and organization_id = v_org;

  v_end_date := (
    make_date(p_schedule_start_year, p_schedule_start_month, 1)
    + (greatest(1, round(v_months))::text || ' months')::interval
    - interval '1 day'
  )::date;

  update public.savings_calculations
  set schedule_start_month = p_schedule_start_month,
      schedule_start_year = p_schedule_start_year,
      schedule_period_type = p_schedule_period_type,
      schedule_period_count = v_count,
      baseline_total_amount = v_baseline,
      opening_proposal_amount = v_opening,
      award_total_amount = v_final,
      gross_savings_amount = v_total,
      net_savings_amount = v_total,
      cost_reduction_amount = v_reduction,
      cost_avoidance_amount = v_avoidance,
      savings_type = case when coalesce(v_reduction, 0) >= v_avoidance
                          then 'Cost Reduction' else 'Cost Avoidance' end,
      savings_percentage = case when v_baseline > 0
                                then round((v_total / v_baseline) * 100, 2)
                                else null end,
      savings_start_date = make_date(p_schedule_start_year, p_schedule_start_month, 1),
      savings_end_date = v_end_date,
      calculation_name = v_count || '-period savings schedule',
      recognition_notes = 'Published from the savings schedule: ' || v_count
        || ' periods covering ' || round(v_months) || ' of ' || round(v_months)
        || ' deal months.',
      updated_by = v_user,
      updated_at = now()
  where id = p_savings_calculation_id
    and organization_id = v_org;
end
$$;

-- Protected tuple columns are writable only through the RPCs above. Ordinary
-- form fields keep their existing direct-write paths and remain RLS-protected.
revoke insert, update on public.baselines from authenticated;
grant insert (
  id, organization_id, event_id, baseline_name, baseline_type,
  baseline_source, baseline_period_start, baseline_period_end,
  baseline_currency_code, baseline_fx_rate_to_usd, baseline_total_amount,
  baseline_normalized_amount, normalization_notes, baseline_lock_status,
  baseline_lock_date, baseline_approved_by, baseline_approval_date,
  official_for_hard_savings, official_for_cost_avoidance,
  official_for_demand_reduction, created_at, created_by, updated_at, updated_by,
  baseline_term_months, hard_reduction_override,
  hard_reduction_override_reason, hard_reduction_override_by,
  hard_reduction_override_at
) on public.baselines to authenticated;
grant update (
  baseline_name, baseline_type, baseline_source, baseline_period_start,
  baseline_period_end, baseline_currency_code, baseline_fx_rate_to_usd,
  baseline_total_amount, baseline_normalized_amount, normalization_notes,
  baseline_lock_status, baseline_lock_date, baseline_approved_by,
  baseline_approval_date, official_for_hard_savings,
  official_for_cost_avoidance, official_for_demand_reduction, updated_at,
  updated_by, baseline_term_months, hard_reduction_override,
  hard_reduction_override_reason, hard_reduction_override_by,
  hard_reduction_override_at
) on public.baselines to authenticated;

revoke insert, update on public.supplier_offers from authenticated;
grant insert (
  id, organization_id, event_id, supplier_id, offer_type, offer_round,
  offer_date, offer_currency_code, fx_rate_to_usd, offer_total_amount,
  offer_valid_until, compliant_bid_flag, selected_for_award_flag,
  source_document_id, notes, created_at, created_by, updated_at, updated_by,
  offer_term_months
) on public.supplier_offers to authenticated;
grant update (
  supplier_id, offer_type, offer_round, offer_date, offer_currency_code,
  fx_rate_to_usd, offer_total_amount, offer_valid_until, compliant_bid_flag,
  selected_for_award_flag, source_document_id, notes, updated_at, updated_by,
  offer_term_months
) on public.supplier_offers to authenticated;

revoke insert, update on public.sourcing_events from authenticated;
grant insert (
  id, organization_id, event_name, event_description, event_type,
  sourcing_method, category_id, business_unit_id, cost_center_id,
  incumbent_supplier_id, procurement_owner_id, business_owner_id,
  finance_owner_id, event_status, currency_code, fx_rate_to_usd,
  event_start_date, event_close_date, contract_start_date, contract_end_date,
  recognition_start_date, recognition_end_date, official_reporting_basis,
  created_at, created_by, updated_at, updated_by, project_type, buyer_name,
  notes, project_due_date, savings_disposition, savings_disposition_reason,
  savings_disposition_at, savings_disposition_by
) on public.sourcing_events to authenticated;
grant update (
  event_name, event_description, event_type, sourcing_method, category_id,
  business_unit_id, cost_center_id, incumbent_supplier_id,
  procurement_owner_id, business_owner_id, finance_owner_id, event_status,
  currency_code, fx_rate_to_usd, event_start_date, event_close_date,
  contract_start_date, contract_end_date, recognition_start_date,
  recognition_end_date, official_reporting_basis, updated_at, updated_by,
  project_type, buyer_name, notes, project_due_date, savings_disposition,
  savings_disposition_reason, savings_disposition_at, savings_disposition_by
) on public.sourcing_events to authenticated;

revoke insert, update, delete on public.savings_periods from authenticated;
grant update (
  baseline_amount, opening_amount, final_amount, cost_reduction_amount,
  cost_avoidance_amount, total_savings_amount, is_edited, notes,
  updated_at, updated_by
) on public.savings_periods to authenticated;

-- Narrowing savings_periods UPDATE would otherwise break the existing
-- execution RPC. Its checks and behavior are unchanged; only its authority is
-- converted so it can continue writing the protected snapshot columns.
alter function public.mark_savings_schedule_executed(uuid, text)
  security definer;

revoke all on function public.select_baseline(uuid)
  from public, anon, authenticated;
revoke all on function public.set_offer_role(uuid, text)
  from public, anon, authenticated;
revoke all on function public.replace_savings_schedule(uuid, integer, integer, text, jsonb)
  from public, anon, authenticated;

grant execute on function public.select_baseline(uuid) to authenticated;
grant execute on function public.set_offer_role(uuid, text) to authenticated;
grant execute on function public.replace_savings_schedule(uuid, integer, integer, text, jsonb)
  to authenticated;

commit;
