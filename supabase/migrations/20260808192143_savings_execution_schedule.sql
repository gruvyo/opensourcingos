begin;

-- Savings Realization is optional. Estimated/executed scheduling is not.
alter table public.organization_settings
  add column savings_realization_enabled boolean not null default false;

comment on column public.organization_settings.savings_realization_enabled is
  'Enables actual/realized savings entry, variance, and finance validation against executed schedule periods.';

-- The calculation retains the reportable lifecycle decision and its actor.
alter table public.savings_calculations
  add column executed_at timestamptz,
  add column executed_by uuid references public.profiles(id),
  add column execution_note text;

alter table public.savings_calculations
  drop constraint chk_calculation_status;

-- Existing schedule values become the immutable estimated side of each row.
-- The executed side is populated only by an explicit execution decision.
alter table public.savings_periods
  add column executed_baseline_amount numeric,
  add column executed_opening_amount numeric,
  add column executed_final_amount numeric,
  add column executed_cost_reduction_amount numeric,
  add column executed_cost_avoidance_amount numeric,
  add column executed_total_savings_amount numeric;

comment on column public.savings_periods.total_savings_amount is
  'Estimated savings for this period. Preserved when an executed snapshot is created.';
comment on column public.savings_periods.executed_total_savings_amount is
  'Executed savings snapshot for this period. NULL means the schedule has not been executed.';

-- Every existing beta savings record receives a real monthly schedule. The
-- source rows already carry whole-term anchors and inclusive start/end dates.
-- Existing saved schedules are preserved byte-for-byte.
with missing as (
  select
    calculation.*,
    greatest(
      1,
      (extract(year from calculation.savings_end_date)::integer
        - extract(year from calculation.savings_start_date)::integer) * 12
      + extract(month from calculation.savings_end_date)::integer
      - extract(month from calculation.savings_start_date)::integer
      + 1
    ) as month_count
  from public.savings_calculations as calculation
  where calculation.savings_start_date is not null
    and calculation.savings_end_date is not null
    and not exists (
      select 1 from public.savings_periods as period
      where period.savings_calculation_id = calculation.id
    )
), generated as (
  select
    missing.*,
    series.period_index,
    (missing.savings_start_date + (series.period_index || ' months')::interval)::date as period_date
  from missing
  cross join lateral generate_series(0, missing.month_count - 1) as series(period_index)
)
insert into public.savings_periods (
  organization_id,
  event_id,
  savings_calculation_id,
  period_number,
  period_month,
  period_year,
  period_months,
  baseline_amount,
  opening_amount,
  final_amount,
  cost_reduction_amount,
  cost_avoidance_amount,
  total_savings_amount,
  is_edited,
  notes,
  created_by,
  updated_by
)
select
  generated.organization_id,
  generated.event_id,
  generated.id,
  generated.period_index + 1,
  extract(month from generated.period_date)::integer,
  extract(year from generated.period_date)::integer,
  1,
  generated.baseline_total_amount / generated.month_count,
  generated.opening_proposal_amount / generated.month_count,
  coalesce(generated.award_total_amount, 0) / generated.month_count,
  generated.cost_reduction_amount / generated.month_count,
  coalesce(generated.cost_avoidance_amount, 0) / generated.month_count,
  coalesce(generated.gross_savings_amount, 0) / generated.month_count,
  false,
  'Monthly schedule reconstructed from the saved whole-term calculation during the beta lifecycle migration.',
  generated.created_by,
  generated.updated_by
from generated;

update public.savings_calculations as calculation
set
  schedule_start_month = coalesce(schedule_start_month, extract(month from savings_start_date)::integer),
  schedule_start_year = coalesce(schedule_start_year, extract(year from savings_start_date)::integer),
  schedule_period_type = coalesce(schedule_period_type, 'monthly'),
  schedule_period_count = coalesce(
    schedule_period_count,
    (select count(*) from public.savings_periods as period where period.savings_calculation_id = calculation.id)
  )
where exists (
  select 1 from public.savings_periods as period where period.savings_calculation_id = calculation.id
);

-- Contracted/realized were previously labels on the calculation. Preserve
-- those beta decisions as executed snapshots. Negotiated remains estimated.
update public.savings_periods as period
set
  executed_baseline_amount = period.baseline_amount,
  executed_opening_amount = period.opening_amount,
  executed_final_amount = period.final_amount,
  executed_cost_reduction_amount = period.cost_reduction_amount,
  executed_cost_avoidance_amount = period.cost_avoidance_amount,
  executed_total_savings_amount = period.total_savings_amount
from public.savings_calculations as calculation
where calculation.id = period.savings_calculation_id
  and calculation.calculation_status in ('contracted', 'realized');

update public.savings_calculations
set
  calculation_status = case
    when calculation_status in ('contracted', 'realized') then 'executed'
    else 'estimated'
  end,
  executed_at = case
    when calculation_status in ('contracted', 'realized') then coalesce(updated_at, created_at, now())
    else null
  end,
  executed_by = case
    when calculation_status in ('contracted', 'realized') then coalesce(updated_by, created_by)
    else null
  end,
  execution_note = case
    when calculation_status in ('contracted', 'realized')
      then 'Preserved from the legacy ' || calculation_status || ' stage during the beta lifecycle migration.'
    else null
  end;

alter table public.savings_calculations
  alter column calculation_status set default 'estimated',
  add constraint chk_calculation_status
    check (calculation_status in ('estimated', 'executed')),
  add constraint chk_savings_execution_metadata check (
    (calculation_status = 'estimated' and executed_at is null and executed_by is null)
    or
    (calculation_status = 'executed' and executed_at is not null)
  );

-- A completed sourcing project must carry an explicit savings disposition.
alter table public.sourcing_events
  add column savings_disposition text,
  add column savings_disposition_reason text,
  add column savings_disposition_at timestamptz,
  add column savings_disposition_by uuid references public.profiles(id),
  add constraint sourcing_events_savings_disposition_check check (
    savings_disposition is null
    or savings_disposition in ('executed', 'no_executed_savings')
  ),
  add constraint sourcing_events_no_execution_reason_check check (
    savings_disposition <> 'no_executed_savings'
    or length(btrim(savings_disposition_reason)) >= 10
  );

update public.sourcing_events as event
set
  savings_disposition = 'executed',
  savings_disposition_reason = 'Preserved from the existing finalized beta savings record.',
  savings_disposition_at = coalesce(calculation.executed_at, now()),
  savings_disposition_by = calculation.executed_by
from public.savings_calculations as calculation
where calculation.event_id = event.id
  and calculation.calculation_status = 'executed';

update public.sourcing_events
set
  savings_disposition = 'no_executed_savings',
  savings_disposition_reason = 'Existing completed beta project had no executed savings record.',
  savings_disposition_at = coalesce(updated_at, now()),
  savings_disposition_by = updated_by
where project_type = 'Sourcing'
  and event_status = 'Complete'
  and savings_disposition is null;

create function public.enforce_completed_project_savings_disposition()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
begin
  if new.project_type = 'Sourcing' and new.event_status = 'Complete' then
    if new.savings_disposition is null then
      raise exception 'Choose whether scheduled savings were executed before completing this project';
    end if;

    if new.savings_disposition = 'executed' and not exists (
      select 1
      from public.savings_calculations as calculation
      where calculation.event_id = new.id
        and calculation.calculation_status = 'executed'
    ) then
      raise exception 'The project cannot be completed as executed until its savings schedule is marked executed';
    end if;

    if new.savings_disposition = 'no_executed_savings'
      and length(btrim(coalesce(new.savings_disposition_reason, ''))) < 10 then
      raise exception 'Explain why the project completed without executed savings';
    end if;
  end if;
  return new;
end
$$;

create trigger sourcing_events_completion_savings_guard
before insert or update of event_status, project_type, savings_disposition, savings_disposition_reason
on public.sourcing_events
for each row execute function public.enforce_completed_project_savings_disposition();

revoke all on function public.enforce_completed_project_savings_disposition()
  from public, anon, authenticated;
grant execute on function public.enforce_completed_project_savings_disposition()
  to service_role;

-- Atomic explicit execution: copy the estimate into the executed side, stamp
-- the decision, and resolve the parent project's completion disposition.
create function public.mark_savings_schedule_executed(
  p_savings_calculation_id uuid,
  p_execution_note text default null
) returns void
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid := public.current_org_id();
  v_role text;
  v_event uuid;
  v_period_count integer;
begin
  if v_user is null or v_org is null then
    raise exception 'authentication required';
  end if;

  select role into v_role
  from public.profiles
  where id = v_user and organization_id = v_org;

  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;

  select event_id into v_event
  from public.savings_calculations
  where id = p_savings_calculation_id
    and organization_id = v_org
  for update;

  if v_event is null then
    raise exception 'savings calculation not found';
  end if;

  select count(*) into v_period_count
  from public.savings_periods
  where savings_calculation_id = p_savings_calculation_id
    and organization_id = v_org;

  if v_period_count = 0 then
    raise exception 'generate the savings schedule before marking it executed';
  end if;

  update public.savings_periods
  set
    executed_baseline_amount = baseline_amount,
    executed_opening_amount = opening_amount,
    executed_final_amount = final_amount,
    executed_cost_reduction_amount = cost_reduction_amount,
    executed_cost_avoidance_amount = cost_avoidance_amount,
    executed_total_savings_amount = total_savings_amount,
    updated_by = v_user,
    updated_at = now()
  where savings_calculation_id = p_savings_calculation_id
    and organization_id = v_org;

  update public.savings_calculations
  set
    calculation_status = 'executed',
    executed_at = now(),
    executed_by = v_user,
    execution_note = nullif(btrim(p_execution_note), ''),
    updated_by = v_user,
    updated_at = now()
  where id = p_savings_calculation_id
    and organization_id = v_org;

  update public.sourcing_events
  set
    savings_disposition = 'executed',
    savings_disposition_reason = coalesce(nullif(btrim(p_execution_note), ''), 'Savings schedule explicitly marked executed.'),
    savings_disposition_at = now(),
    savings_disposition_by = v_user,
    updated_by = v_user,
    updated_at = now()
  where id = v_event and organization_id = v_org;
end
$$;

revoke all on function public.mark_savings_schedule_executed(uuid, text)
  from public, anon;
grant execute on function public.mark_savings_schedule_executed(uuid, text)
  to authenticated;

-- Actual entries belong to a schedule period and are available only when the
-- workspace enables Savings Realization.
alter table public.realization_periods
  add column savings_period_id uuid references public.savings_periods(id) on delete cascade;

create unique index uq_realization_periods_savings_period
  on public.realization_periods (savings_period_id)
  where savings_period_id is not null;

create function public.enforce_savings_realization_setting()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_org uuid := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
begin
  if not coalesce((
    select settings.savings_realization_enabled
    from public.organization_settings as settings
    where settings.organization_id = v_org
  ), false) then
    raise exception 'Savings Realization is disabled for this workspace';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end
$$;

create trigger realization_periods_setting_guard
before insert or update or delete on public.realization_periods
for each row execute function public.enforce_savings_realization_setting();

revoke all on function public.enforce_savings_realization_setting()
  from public, anon, authenticated;
grant execute on function public.enforce_savings_realization_setting()
  to service_role;

-- Extend the immutable workspace audit to the lifecycle decision.
alter table public.audit_log
  drop constraint audit_log_entity_type_check;
alter table public.audit_log
  add constraint audit_log_entity_type_check check (
    entity_type in (
      'organization', 'organization_settings', 'supplier',
      'project_choice_option', 'category', 'business_unit', 'cost_center',
      'project_classification_reset', 'savings_calculation'
    )
  );

create or replace function public.capture_workspace_audit()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_org uuid;
  v_entity_id uuid;
  v_entity_type text;
begin
  if tg_table_name = 'organizations' then
    v_org := case when tg_op = 'DELETE' then old.id else new.id end;
    v_entity_id := v_org;
    v_entity_type := 'organization';
  elsif tg_table_name = 'organization_settings' then
    v_org := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
    v_entity_id := v_org;
    v_entity_type := 'organization_settings';
  else
    v_org := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
    v_entity_id := case when tg_op = 'DELETE' then old.id else new.id end;
    v_entity_type := case tg_table_name
      when 'suppliers' then 'supplier'
      when 'project_choice_options' then 'project_choice_option'
      when 'categories' then 'category'
      when 'business_units' then 'business_unit'
      when 'cost_centers' then 'cost_center'
      when 'savings_calculations' then 'savings_calculation'
      else 'supplier'
    end;
  end if;

  insert into public.audit_log (
    organization_id, actor_id, entity_type, entity_id, action, before_data, after_data
  ) values (
    v_org,
    auth.uid(),
    v_entity_type,
    v_entity_id,
    lower(tg_op),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end
  );

  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

revoke all on function public.capture_workspace_audit()
  from public, anon, authenticated;
grant execute on function public.capture_workspace_audit()
  to service_role;

create trigger savings_calculations_audit
after insert or update or delete on public.savings_calculations
for each row execute function public.capture_workspace_audit();

-- Settings RPC v9 adds the organization-level Savings Realization capability.
create function public.update_workspace_settings_v9(
  p_organization_name text,
  p_full_name text,
  p_currency_code text,
  p_locale text,
  p_timezone text,
  p_fiscal_year_start_month integer,
  p_date_format text,
  p_default_recognition_method text,
  p_require_baseline boolean,
  p_hard_reduction_approval_threshold numeric,
  p_support_projects_enabled boolean,
  p_project_descriptions_enabled boolean,
  p_project_owners_enabled boolean,
  p_project_cost_centers_enabled boolean,
  p_project_categories_enabled boolean,
  p_project_business_units_enabled boolean,
  p_project_updates_enabled boolean,
  p_project_incumbent_suppliers_enabled boolean,
  p_savings_realization_enabled boolean
) returns void
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid := public.current_org_id();
  v_role text;
begin
  if v_user is null or v_org is null then raise exception 'authentication required'; end if;
  select role into v_role from public.profiles where id = v_user and organization_id = v_org;
  if v_role is distinct from 'admin' then raise exception 'administrator role required'; end if;

  update public.organizations set name = p_organization_name where id = v_org;
  update public.profiles set full_name = p_full_name where id = v_user and organization_id = v_org;

  insert into public.organization_settings (
    organization_id, currency_code, locale, timezone, fiscal_year_start_month,
    date_format, default_recognition_method, require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold, support_projects_enabled,
    project_descriptions_enabled, project_owners_enabled,
    project_cost_centers_enabled, project_categories_enabled,
    project_business_units_enabled, project_updates_enabled,
    project_incumbent_suppliers_enabled, savings_realization_enabled, updated_by
  ) values (
    v_org, p_currency_code, p_locale, p_timezone, p_fiscal_year_start_month,
    p_date_format, p_default_recognition_method, p_require_baseline,
    p_hard_reduction_approval_threshold, p_support_projects_enabled,
    p_project_descriptions_enabled, p_project_owners_enabled,
    p_project_cost_centers_enabled, p_project_categories_enabled,
    p_project_business_units_enabled, p_project_updates_enabled,
    p_project_incumbent_suppliers_enabled, p_savings_realization_enabled, v_user
  )
  on conflict (organization_id) do update set
    currency_code = excluded.currency_code,
    locale = excluded.locale,
    timezone = excluded.timezone,
    fiscal_year_start_month = excluded.fiscal_year_start_month,
    date_format = excluded.date_format,
    default_recognition_method = excluded.default_recognition_method,
    require_baseline_for_hard_reduction = excluded.require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold = excluded.hard_reduction_approval_threshold,
    support_projects_enabled = excluded.support_projects_enabled,
    project_descriptions_enabled = excluded.project_descriptions_enabled,
    project_owners_enabled = excluded.project_owners_enabled,
    project_cost_centers_enabled = excluded.project_cost_centers_enabled,
    project_categories_enabled = excluded.project_categories_enabled,
    project_business_units_enabled = excluded.project_business_units_enabled,
    project_updates_enabled = excluded.project_updates_enabled,
    project_incumbent_suppliers_enabled = excluded.project_incumbent_suppliers_enabled,
    savings_realization_enabled = excluded.savings_realization_enabled,
    updated_by = excluded.updated_by;
end
$$;

revoke all on function public.update_workspace_settings_v9(
  text, text, text, text, text, integer, text, text, boolean, numeric,
  boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean
) from public, anon;
grant execute on function public.update_workspace_settings_v9(
  text, text, text, text, text, integer, text, text, boolean, numeric,
  boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean
) to authenticated;

commit;
