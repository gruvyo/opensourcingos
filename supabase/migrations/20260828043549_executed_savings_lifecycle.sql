begin;

-- Modification 3B: an executed schedule is a financial record, not an
-- editable draft. Corrections and premature-execution reversals are explicit,
-- role-checked, audited transactions; ordinary Data API writes remain limited
-- to estimated records.

-- Realization rows keep a user-visible marker when a correction rebases their
-- comparison against a new executed snapshot.
alter table public.realization_periods
  add column comparison_rebased_at timestamptz,
  add column comparison_rebased_by uuid references public.profiles(id);

comment on column public.realization_periods.comparison_rebased_at is
  'Most recent time an executed-savings correction rebased this period comparator. NULL means never rebased.';

-- Empty comparator shells are not evidence. Let an authenticated commercial
-- editor remove one even after the optional Realization feature is switched
-- off, so correction/reversal can restore a consistent lifecycle state.
create or replace function public.enforce_savings_realization_setting()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_org uuid := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
begin
  if tg_op = 'DELETE'
    and old.actual_amount is null
    and old.realized_savings is null
    and not coalesce(old.finance_validated, false)
    and exists (
      select 1 from public.profiles profile
      where profile.id = auth.uid()
        and profile.organization_id = v_org
        and profile.role in ('admin', 'procurement_user')
    ) then
    return old;
  end if;

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

revoke all on function public.enforce_savings_realization_setting()
  from public, anon, authenticated;
grant execute on function public.enforce_savings_realization_setting()
  to service_role;

-- Historical actuals must never disappear because a schedule row is replaced
-- or a parent project is deleted. Empty sync shells are removed deliberately
-- by the lifecycle RPCs before a legitimate replacement or reversal.
alter table public.realization_periods
  drop constraint realization_periods_savings_period_id_fkey,
  add constraint realization_periods_savings_period_id_fkey
    foreign key (savings_period_id)
    references public.savings_periods(id)
    on delete restrict;

-- The original check permitted an executed row with no actor. It also left a
-- lifecycle note on an estimated row possible. Tighten both sides.
alter table public.savings_calculations
  drop constraint chk_savings_execution_metadata,
  add constraint chk_savings_execution_metadata check (
    (
      calculation_status = 'estimated'
      and executed_at is null
      and executed_by is null
      and execution_note is null
    )
    or
    (
      calculation_status = 'executed'
      and executed_at is not null
      and executed_by is not null
    )
  );

-- -------------------------------------------------------------------------
-- Deferred end-state invariants
-- -------------------------------------------------------------------------

create function public.enforce_savings_execution_invariant()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_calculation_id uuid;
  v_status text;
  v_executed_at timestamptz;
  v_executed_by uuid;
  v_execution_note text;
begin
  if tg_table_name = 'savings_calculations' then
    v_calculation_id := case when tg_op = 'DELETE' then old.id else new.id end;
  else
    v_calculation_id := case
      when tg_op = 'DELETE' then old.savings_calculation_id
      else new.savings_calculation_id
    end;
  end if;

  select calculation_status, executed_at, executed_by, execution_note
  into v_status, v_executed_at, v_executed_by, v_execution_note
  from public.savings_calculations
  where id = v_calculation_id;

  -- A parent delete removes the calculation, so there is no calculation state
  -- left to validate. Retention and completion have their own guards below.
  if not found then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if v_status = 'executed' then
    if v_executed_at is null or v_executed_by is null then
      raise exception 'executed savings require an execution time and actor';
    end if;

    if not exists (
      select 1 from public.savings_periods
      where savings_calculation_id = v_calculation_id
    ) then
      raise exception 'executed savings require at least one schedule period';
    end if;

    if exists (
      select 1
      from public.savings_periods
      where savings_calculation_id = v_calculation_id
        and (
          executed_total_savings_amount is null
          or executed_final_amount is null
          or executed_cost_avoidance_amount is null
        )
    ) then
      raise exception 'every executed schedule period requires a complete snapshot';
    end if;
  elsif v_status = 'estimated' then
    if v_executed_at is not null or v_executed_by is not null or v_execution_note is not null then
      raise exception 'estimated savings cannot retain execution metadata';
    end if;

    if exists (
      select 1
      from public.savings_periods
      where savings_calculation_id = v_calculation_id
        and (
          executed_baseline_amount is not null
          or executed_opening_amount is not null
          or executed_final_amount is not null
          or executed_cost_reduction_amount is not null
          or executed_cost_avoidance_amount is not null
          or executed_total_savings_amount is not null
        )
    ) then
      raise exception 'estimated savings cannot retain executed schedule snapshots';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end
$$;

create constraint trigger savings_calculations_execution_invariant
after insert or update or delete on public.savings_calculations
deferrable initially deferred
for each row execute function public.enforce_savings_execution_invariant();

create constraint trigger savings_periods_execution_invariant
after insert or update or delete on public.savings_periods
deferrable initially deferred
for each row execute function public.enforce_savings_execution_invariant();

revoke all on function public.enforce_savings_execution_invariant()
  from public, anon, authenticated;
grant execute on function public.enforce_savings_execution_invariant()
  to service_role;

create function public.enforce_savings_completion_invariant()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_event_id uuid;
  v_project_type text;
  v_event_status text;
  v_disposition text;
  v_reason text;
begin
  if tg_table_name = 'sourcing_events' then
    v_event_id := case when tg_op = 'DELETE' then old.id else new.id end;
  else
    v_event_id := case when tg_op = 'DELETE' then old.event_id else new.event_id end;
  end if;

  select project_type, event_status, savings_disposition, savings_disposition_reason
  into v_project_type, v_event_status, v_disposition, v_reason
  from public.sourcing_events
  where id = v_event_id;

  if not found then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if v_project_type = 'Sourcing' and v_event_status = 'Complete' then
    if v_disposition is null then
      raise exception 'completed sourcing projects require a savings disposition';
    end if;

    if v_disposition = 'executed' and not exists (
      select 1
      from public.savings_calculations
      where event_id = v_event_id
        and calculation_status = 'executed'
    ) then
      raise exception 'an executed disposition requires an executed savings calculation';
    end if;

    if v_disposition = 'no_executed_savings'
      and length(btrim(coalesce(v_reason, ''))) < 10 then
      raise exception 'completed projects without executed savings require a reason';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end
$$;

create constraint trigger sourcing_events_savings_completion_invariant
after insert or update or delete on public.sourcing_events
deferrable initially deferred
for each row execute function public.enforce_savings_completion_invariant();

create constraint trigger savings_calculations_completion_invariant
after insert or update or delete on public.savings_calculations
deferrable initially deferred
for each row execute function public.enforce_savings_completion_invariant();

revoke all on function public.enforce_savings_completion_invariant()
  from public, anon, authenticated;
grant execute on function public.enforce_savings_completion_invariant()
  to service_role;

-- A project or calculation with realization history cannot use a cascading
-- delete path. Empty shells are intentionally cleared by reversal first.
create function public.prevent_realization_history_delete()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
begin
  if tg_table_name = 'sourcing_events' and exists (
    select 1 from public.realization_periods where event_id = old.id
  ) then
    raise exception 'project deletion is blocked while savings realization history exists';
  end if;

  if tg_table_name = 'savings_calculations' and exists (
    select 1 from public.realization_periods where savings_calculation_id = old.id
  ) then
    raise exception 'savings calculation deletion is blocked while realization history exists';
  end if;

  return old;
end
$$;

create trigger sourcing_events_realization_retention_guard
before delete on public.sourcing_events
for each row execute function public.prevent_realization_history_delete();

create trigger savings_calculations_realization_retention_guard
before delete on public.savings_calculations
for each row execute function public.prevent_realization_history_delete();

revoke all on function public.prevent_realization_history_delete()
  from public, anon, authenticated;
grant execute on function public.prevent_realization_history_delete()
  to service_role;

-- -------------------------------------------------------------------------
-- Audited lifecycle entities
-- -------------------------------------------------------------------------

alter table public.audit_log drop constraint audit_log_entity_type_check;
alter table public.audit_log add constraint audit_log_entity_type_check check (
  entity_type in (
    'organization', 'organization_settings', 'supplier', 'supplier_contact',
    'supplier_certification', 'supplier_performance_review', 'supplier_risk',
    'project_choice_option', 'category', 'business_unit', 'cost_center',
    'project_classification_reset', 'savings_calculation', 'savings_period',
    'realization_period', 'sourcing_event'
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
    case tg_table_name
      when 'suppliers' then v_entity_type := 'supplier';
      when 'supplier_contacts' then v_entity_type := 'supplier_contact';
      when 'supplier_certifications' then v_entity_type := 'supplier_certification';
      when 'supplier_performance_reviews' then v_entity_type := 'supplier_performance_review';
      when 'supplier_risks' then v_entity_type := 'supplier_risk';
      when 'project_choice_options' then v_entity_type := 'project_choice_option';
      when 'categories' then v_entity_type := 'category';
      when 'business_units' then v_entity_type := 'business_unit';
      when 'cost_centers' then v_entity_type := 'cost_center';
      when 'savings_calculations' then v_entity_type := 'savings_calculation';
      when 'savings_periods' then v_entity_type := 'savings_period';
      when 'realization_periods' then v_entity_type := 'realization_period';
      when 'sourcing_events' then v_entity_type := 'sourcing_event';
      else raise exception 'unsupported workspace audit table: %', tg_table_name;
    end case;
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

create trigger savings_periods_audit
after insert or update or delete on public.savings_periods
for each row execute function public.capture_workspace_audit();

create trigger realization_periods_audit
after insert or update or delete on public.realization_periods
for each row execute function public.capture_workspace_audit();

create trigger sourcing_events_savings_disposition_audit
after update of savings_disposition, savings_disposition_reason,
  savings_disposition_at, savings_disposition_by or delete
on public.sourcing_events
for each row execute function public.capture_workspace_audit();

-- -------------------------------------------------------------------------
-- T1: execute exactly once
-- -------------------------------------------------------------------------

create or replace function public.mark_savings_schedule_executed(
  p_savings_calculation_id uuid,
  p_execution_note text default null
) returns void
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

  select event_id, calculation_status into v_event, v_status
  from public.savings_calculations
  where id = p_savings_calculation_id
    and organization_id = v_org
  for update;

  if v_event is null then
    raise exception 'savings calculation not found';
  end if;
  if v_status = 'executed' then
    raise exception 'savings schedule is already executed';
  end if;
  if v_status <> 'estimated' then
    raise exception 'only an estimated savings schedule can be executed';
  end if;

  perform 1
  from public.sourcing_events
  where id = v_event
    and organization_id = v_org
    and project_type = 'Sourcing'
  for update;

  if not found then
    raise exception 'sourcing project not found';
  end if;

  perform 1
  from public.savings_periods
  where savings_calculation_id = p_savings_calculation_id
    and organization_id = v_org
  order by id
  for update;

  if not found then
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
    savings_disposition_reason = coalesce(
      nullif(btrim(p_execution_note), ''),
      'Savings schedule explicitly marked executed.'
    ),
    savings_disposition_at = now(),
    savings_disposition_by = v_user,
    updated_by = v_user,
    updated_at = now()
  where id = v_event
    and organization_id = v_org;
end
$$;

-- -------------------------------------------------------------------------
-- T2: explicit, atomic correction
-- -------------------------------------------------------------------------

create function public.correct_savings_execution(
  p_calc_id uuid,
  p_note text,
  p_calculation jsonb,
  p_periods jsonb
) returns void
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
  v_existing_note text;
  v_existing_period_type text;
  v_count integer;
  v_existing_period_count integer;
  v_realization_count integer;
  v_has_evidence boolean;
  v_baseline numeric;
  v_opening numeric;
  v_final numeric;
  v_reduction numeric;
  v_avoidance numeric;
  v_total numeric;
  v_months numeric;
  v_first_month integer;
  v_first_year integer;
  v_period_type text;
  v_start_date date;
  v_end_date date;
  v_savings_type text;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;
  if nullif(btrim(p_note), '') is null then
    raise exception 'a correction note is required';
  end if;
  if jsonb_typeof(p_calculation) is distinct from 'object' then
    raise exception 'calculation must be a JSON object';
  end if;
  if jsonb_typeof(p_periods) is distinct from 'array' then
    raise exception 'periods must be a JSON array';
  end if;

  if exists (
    select 1
    from jsonb_object_keys(p_calculation) as calculation_key(field_name)
    where calculation_key.field_name not in (
      'calculation_name', 'savings_type', 'baseline_total_amount',
      'opening_proposal_amount', 'award_total_amount', 'gross_savings_amount',
      'net_savings_amount', 'cost_reduction_amount',
      'cost_avoidance_amount', 'savings_percentage', 'recognition_notes',
      'savings_start_date', 'savings_end_date', 'schedule_start_month',
      'schedule_start_year', 'schedule_period_type', 'schedule_period_count'
    )
  ) then
    raise exception 'calculation payload contains unsupported fields';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_periods) as period_item(value)
    cross join lateral jsonb_object_keys(period_item.value) as period_key(field_name)
    where period_key.field_name not in (
      'id', 'period_number', 'period_month', 'period_year', 'period_months',
      'baseline_amount', 'opening_amount', 'final_amount',
      'cost_reduction_amount', 'cost_avoidance_amount',
      'total_savings_amount', 'is_edited', 'notes'
    )
  ) then
    raise exception 'period payload contains unsupported fields';
  end if;

  v_count := jsonb_array_length(p_periods);
  if v_count not between 1 and 600 then
    raise exception 'correction must contain between 1 and 600 periods';
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

  select event_id, calculation_status, execution_note, schedule_period_type
  into v_event, v_status, v_existing_note, v_existing_period_type
  from public.savings_calculations
  where id = p_calc_id
    and organization_id = v_org
  for update;

  if v_event is null then
    raise exception 'savings calculation not found';
  end if;
  if v_status <> 'executed' then
    raise exception 'only executed savings can be corrected';
  end if;

  perform 1
  from public.sourcing_events
  where id = v_event and organization_id = v_org
  for update;

  perform 1
  from public.savings_periods
  where savings_calculation_id = p_calc_id
    and organization_id = v_org
  order by id
  for update;

  select count(*) into v_existing_period_count
  from public.savings_periods
  where savings_calculation_id = p_calc_id
    and organization_id = v_org;

  perform 1
  from public.realization_periods
  where savings_calculation_id = p_calc_id
    and organization_id = v_org
  order by id
  for update;

  select
    count(*),
    coalesce(bool_or(
      actual_amount is not null
      or realized_savings is not null
      or coalesce(finance_validated, false)
    ), false)
  into v_realization_count, v_has_evidence
  from public.realization_periods
  where savings_calculation_id = p_calc_id
    and organization_id = v_org;

  if v_has_evidence and v_role <> 'admin' then
    raise exception 'an administrator must correct savings after realization evidence exists';
  end if;

  -- Parsing below also performs strict scalar type validation. Required
  -- fields must be present; nullable methodology anchors may explicitly be null.
  if exists (
    select 1
    from jsonb_array_elements(p_periods) as item(value)
    where not (item.value ? 'period_number')
      or not (item.value ? 'period_month')
      or not (item.value ? 'period_year')
      or not (item.value ? 'period_months')
      or not (item.value ? 'baseline_amount')
      or not (item.value ? 'opening_amount')
      or not (item.value ? 'final_amount')
      or not (item.value ? 'cost_reduction_amount')
      or not (item.value ? 'cost_avoidance_amount')
      or not (item.value ? 'total_savings_amount')
  ) then
    raise exception 'every corrected period must include its identity and complete value chain';
  end if;

  if (
    select count(*) <> v_count
      or count(distinct row.period_number) <> v_count
      or min(row.period_number) <> 1
      or max(row.period_number) <> v_count
    from jsonb_to_recordset(p_periods) as row(period_number integer)
  ) then
    raise exception 'period numbers must be unique and contiguous from 1';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_periods) as row(
      baseline_amount numeric,
      opening_amount numeric,
      final_amount numeric,
      cost_reduction_amount numeric,
      cost_avoidance_amount numeric,
      total_savings_amount numeric
    )
    where row.final_amount is null
      or row.cost_avoidance_amount is null
      or row.total_savings_amount is null
      or row.cost_reduction_amount is distinct from case
        when row.baseline_amount is null then null
        else row.baseline_amount - row.final_amount
      end
      or row.cost_avoidance_amount is distinct from case
        when row.opening_amount is not null and row.baseline_amount is not null
          then row.opening_amount - row.baseline_amount
        when row.opening_amount is not null
          then row.opening_amount - row.final_amount
        else 0
      end
      or row.total_savings_amount is distinct from case
        when row.opening_amount is not null then row.opening_amount - row.final_amount
        when row.baseline_amount is not null then row.baseline_amount - row.final_amount
        else 0
      end
  ) then
    raise exception 'corrected periods must satisfy the approved savings equations';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_periods) as row(id uuid)
    join public.savings_periods existing on existing.id = row.id
    where existing.savings_calculation_id <> p_calc_id
      or existing.organization_id <> v_org
  ) then
    raise exception 'a supplied period ID belongs to another savings calculation';
  end if;

  if v_has_evidence then
    -- Evidence freezes schedule identity and shape. Only business values may
    -- change; historical actuals are never moved to a different period.
    if (
      select count(row.id) <> v_count
        or count(distinct row.id) <> v_count
      from jsonb_to_recordset(p_periods) as row(id uuid)
    ) then
      raise exception 'every corrected period requires its existing ID once realization evidence exists';
    end if;

    if v_count <> v_existing_period_count or exists (
      select 1
      from public.savings_periods existing
      full join jsonb_to_recordset(p_periods) as row(
        id uuid,
        period_number integer,
        period_month integer,
        period_year integer,
        period_months numeric
      ) on row.id = existing.id
      where existing.savings_calculation_id = p_calc_id
        and existing.organization_id = v_org
        and (
          row.id is null
          or row.period_number is distinct from existing.period_number
          or row.period_month is distinct from existing.period_month
          or row.period_year is distinct from existing.period_year
          or row.period_months is distinct from existing.period_months
        )
    ) then
      raise exception 'schedule identity and dates cannot change after realization evidence exists';
    end if;

    update public.savings_periods as period
    set
      baseline_amount = row.baseline_amount,
      opening_amount = row.opening_amount,
      final_amount = row.final_amount,
      cost_reduction_amount = row.cost_reduction_amount,
      cost_avoidance_amount = row.cost_avoidance_amount,
      total_savings_amount = row.total_savings_amount,
      is_edited = coalesce(row.is_edited, true),
      notes = row.notes,
      executed_baseline_amount = row.baseline_amount,
      executed_opening_amount = row.opening_amount,
      executed_final_amount = row.final_amount,
      executed_cost_reduction_amount = row.cost_reduction_amount,
      executed_cost_avoidance_amount = row.cost_avoidance_amount,
      executed_total_savings_amount = row.total_savings_amount,
      updated_by = v_user,
      updated_at = now()
    from jsonb_to_recordset(p_periods) as row(
      id uuid,
      baseline_amount numeric,
      opening_amount numeric,
      final_amount numeric,
      cost_reduction_amount numeric,
      cost_avoidance_amount numeric,
      total_savings_amount numeric,
      is_edited boolean,
      notes text
    )
    where period.id = row.id
      and period.savings_calculation_id = p_calc_id
      and period.organization_id = v_org;

    update public.realization_periods as realization
    set
      baseline_amount = period.executed_baseline_amount,
      projected_savings = period.executed_total_savings_amount,
      leakage_amount = case
        when realization.realized_savings is null then null
        else period.executed_total_savings_amount - realization.realized_savings
      end,
      realization_status = case
        when realization.actual_amount is not null then
          case
            when realization.realized_savings is null then 'In Progress'
            when period.executed_total_savings_amount - realization.realized_savings <= 0 then 'Realized'
            when period.executed_total_savings_amount - realization.realized_savings < period.executed_total_savings_amount then 'Partially Realized'
            else 'Leaked'
          end
        when realization.realized_savings is not null then
          case
            when realization.realized_savings <= 0 then 'Not Realized'
            when period.executed_total_savings_amount - realization.realized_savings <= 0 then 'Realized'
            else 'Partially Realized'
          end
        else 'Pending'
      end,
      finance_validated = false,
      finance_validated_by = null,
      finance_validation_date = null,
      comparison_rebased_at = now(),
      comparison_rebased_by = v_user,
      updated_at = now(),
      updated_by = v_user
    from public.savings_periods as period
    where realization.savings_period_id = period.id
      and period.savings_calculation_id = p_calc_id
      and realization.organization_id = v_org;
  else
    -- No entered evidence: empty sync shells are auditably replaced along with
    -- the schedule and then recreated against the new period identities.
    delete from public.realization_periods
    where savings_calculation_id = p_calc_id
      and organization_id = v_org;

    delete from public.savings_periods
    where savings_calculation_id = p_calc_id
      and organization_id = v_org;

    insert into public.savings_periods (
      id, organization_id, event_id, savings_calculation_id,
      period_number, period_month, period_year, period_months,
      baseline_amount, opening_amount, final_amount,
      cost_reduction_amount, cost_avoidance_amount, total_savings_amount,
      is_edited, notes,
      executed_baseline_amount, executed_opening_amount, executed_final_amount,
      executed_cost_reduction_amount, executed_cost_avoidance_amount,
      executed_total_savings_amount,
      created_by, updated_by
    )
    select
      coalesce(row.id, gen_random_uuid()), v_org, v_event, p_calc_id,
      row.period_number, row.period_month, row.period_year, row.period_months,
      row.baseline_amount, row.opening_amount, row.final_amount,
      row.cost_reduction_amount, row.cost_avoidance_amount,
      row.total_savings_amount, coalesce(row.is_edited, true), row.notes,
      row.baseline_amount, row.opening_amount, row.final_amount,
      row.cost_reduction_amount, row.cost_avoidance_amount,
      row.total_savings_amount,
      v_user, v_user
    from jsonb_to_recordset(p_periods) as row(
      id uuid,
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

    if v_realization_count > 0 then
      insert into public.realization_periods (
        organization_id, event_id, savings_calculation_id, savings_period_id,
        period_name, period_start_date, period_end_date,
        baseline_amount, projected_savings, actual_amount, realized_savings,
        leakage_amount, realization_status, finance_validated,
        comparison_rebased_at, comparison_rebased_by,
        created_by, updated_by
      )
      select
        v_org, v_event, p_calc_id, period.id,
        to_char(make_date(period.period_year, period.period_month, 1), 'Mon YYYY'),
        make_date(period.period_year, period.period_month, 1),
        (
          make_date(period.period_year, period.period_month, 1)
          + (greatest(1, round(period.period_months))::text || ' months')::interval
          - interval '1 day'
        )::date,
        period.executed_baseline_amount,
        period.executed_total_savings_amount,
        null, null, null, 'Pending', false,
        now(), v_user, v_user, v_user
      from public.savings_periods as period
      where period.savings_calculation_id = p_calc_id
        and period.organization_id = v_org;
    end if;
  end if;

  select
    coalesce(sum(period_months), 0),
    coalesce(sum(baseline_amount), 0),
    coalesce(sum(opening_amount), 0),
    coalesce(sum(final_amount), 0),
    case when count(cost_reduction_amount) = 0 then null
         else sum(cost_reduction_amount) end,
    coalesce(sum(cost_avoidance_amount), 0),
    coalesce(sum(total_savings_amount), 0),
    (array_agg(period_month order by period_number))[1],
    (array_agg(period_year order by period_number))[1]
  into v_months, v_baseline, v_opening, v_final, v_reduction,
       v_avoidance, v_total, v_first_month, v_first_year
  from public.savings_periods
  where savings_calculation_id = p_calc_id
    and organization_id = v_org;

  v_period_type := coalesce(nullif(p_calculation->>'schedule_period_type', ''), v_existing_period_type, 'monthly');
  if v_period_type not in ('monthly', 'annual', 'one_time') then
    raise exception 'unsupported schedule period type';
  end if;

  v_start_date := make_date(v_first_year, v_first_month, 1);
  v_end_date := (
    v_start_date
    + (greatest(1, round(v_months))::text || ' months')::interval
    - interval '1 day'
  )::date;
  v_savings_type := case when coalesce(v_reduction, 0) >= v_avoidance
    then 'Cost Reduction' else 'Cost Avoidance' end;

  if p_calculation ? 'baseline_total_amount'
    and (p_calculation->>'baseline_total_amount')::numeric is distinct from v_baseline then
    raise exception 'calculation baseline total does not match corrected periods';
  end if;
  if p_calculation ? 'opening_proposal_amount'
    and (p_calculation->>'opening_proposal_amount')::numeric is distinct from v_opening then
    raise exception 'calculation opening total does not match corrected periods';
  end if;
  if p_calculation ? 'award_total_amount'
    and (p_calculation->>'award_total_amount')::numeric is distinct from v_final then
    raise exception 'calculation final total does not match corrected periods';
  end if;
  if p_calculation ? 'cost_reduction_amount'
    and (p_calculation->>'cost_reduction_amount')::numeric is distinct from v_reduction then
    raise exception 'calculation reduction total does not match corrected periods';
  end if;
  if p_calculation ? 'cost_avoidance_amount'
    and (p_calculation->>'cost_avoidance_amount')::numeric is distinct from v_avoidance then
    raise exception 'calculation avoidance total does not match corrected periods';
  end if;
  if p_calculation ? 'gross_savings_amount'
    and (p_calculation->>'gross_savings_amount')::numeric is distinct from v_total then
    raise exception 'calculation savings total does not match corrected periods';
  end if;
  if p_calculation ? 'net_savings_amount'
    and (p_calculation->>'net_savings_amount')::numeric is distinct from v_total then
    raise exception 'calculation net savings does not match corrected periods';
  end if;
  if p_calculation ? 'savings_type'
    and p_calculation->>'savings_type' is distinct from v_savings_type then
    raise exception 'calculation savings type does not match corrected periods';
  end if;
  if p_calculation ? 'schedule_period_count'
    and (p_calculation->>'schedule_period_count')::integer is distinct from v_count then
    raise exception 'calculation period count does not match corrected periods';
  end if;
  if p_calculation ? 'schedule_start_month'
    and (p_calculation->>'schedule_start_month')::integer is distinct from v_first_month then
    raise exception 'calculation start month does not match corrected periods';
  end if;
  if p_calculation ? 'schedule_start_year'
    and (p_calculation->>'schedule_start_year')::integer is distinct from v_first_year then
    raise exception 'calculation start year does not match corrected periods';
  end if;
  if p_calculation ? 'savings_start_date'
    and (p_calculation->>'savings_start_date')::date is distinct from v_start_date then
    raise exception 'calculation start date does not match corrected periods';
  end if;
  if p_calculation ? 'savings_end_date'
    and (p_calculation->>'savings_end_date')::date is distinct from v_end_date then
    raise exception 'calculation end date does not match corrected periods';
  end if;
  if p_calculation ? 'calculation_name'
    and nullif(btrim(p_calculation->>'calculation_name'), '') is null then
    raise exception 'calculation name cannot be blank';
  end if;

  update public.savings_calculations
  set
    calculation_name = coalesce(
      nullif(btrim(p_calculation->>'calculation_name'), ''),
      v_count || '-period savings schedule'
    ),
    savings_type = v_savings_type,
    baseline_total_amount = v_baseline,
    opening_proposal_amount = v_opening,
    award_total_amount = v_final,
    gross_savings_amount = v_total,
    net_savings_amount = v_total,
    cost_reduction_amount = v_reduction,
    cost_avoidance_amount = v_avoidance,
    savings_percentage = case when v_baseline > 0
      then round((v_total / v_baseline) * 100, 2) else null end,
    recognition_notes = coalesce(
      p_calculation->>'recognition_notes',
      'Corrected executed schedule: ' || v_count || ' periods.'
    ),
    savings_start_date = v_start_date,
    savings_end_date = v_end_date,
    schedule_start_month = v_first_month,
    schedule_start_year = v_first_year,
    schedule_period_type = v_period_type,
    schedule_period_count = v_count,
    execution_note = concat_ws(
      E'\n',
      nullif(v_existing_note, ''),
      '[' || to_char(now(), 'YYYY-MM-DD HH24:MI:SSOF') || '] Correction: ' || btrim(p_note)
    ),
    updated_by = v_user,
    updated_at = now()
  where id = p_calc_id
    and organization_id = v_org;
end
$$;

-- -------------------------------------------------------------------------
-- T3: admin-only reversal before entered realization evidence exists
-- -------------------------------------------------------------------------

create function public.reverse_savings_execution(
  p_calc_id uuid,
  p_note text,
  p_disposition_action text
) returns void
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
  v_existing_note text;
  v_project_type text;
  v_event_status text;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;
  if nullif(btrim(p_note), '') is null then
    raise exception 'a reversal note is required';
  end if;

  select organization_id, role into v_org, v_role
  from public.profiles
  where id = v_user;

  if v_org is null then
    raise exception 'workspace membership required';
  end if;
  if v_role <> 'admin' then
    raise exception 'administrator role required';
  end if;

  select event_id, calculation_status, execution_note
  into v_event, v_status, v_existing_note
  from public.savings_calculations
  where id = p_calc_id
    and organization_id = v_org
  for update;

  if v_event is null then
    raise exception 'savings calculation not found';
  end if;
  if v_status <> 'executed' then
    raise exception 'savings schedule is not executed';
  end if;

  select project_type, event_status into v_project_type, v_event_status
  from public.sourcing_events
  where id = v_event
    and organization_id = v_org
  for update;

  perform 1
  from public.savings_periods
  where savings_calculation_id = p_calc_id
    and organization_id = v_org
  order by id
  for update;

  perform 1
  from public.realization_periods
  where savings_calculation_id = p_calc_id
    and organization_id = v_org
  order by id
  for update;

  if exists (
    select 1
    from public.realization_periods
    where savings_calculation_id = p_calc_id
      and organization_id = v_org
      and (
        actual_amount is not null
        or realized_savings is not null
        or coalesce(finance_validated, false)
      )
  ) then
    raise exception 'execution cannot be reversed after realization evidence exists; use a correction';
  end if;

  if v_project_type = 'Sourcing' and v_event_status = 'Complete' then
    if p_disposition_action <> 'no_executed_savings' then
      raise exception 'reopen the completed project or choose no_executed_savings';
    end if;
    if length(btrim(p_note)) < 10 then
      raise exception 'completed projects without executed savings require a reason of at least 10 characters';
    end if;

    update public.sourcing_events
    set
      savings_disposition = 'no_executed_savings',
      savings_disposition_reason = btrim(p_note),
      savings_disposition_at = now(),
      savings_disposition_by = v_user,
      updated_by = v_user,
      updated_at = now()
    where id = v_event and organization_id = v_org;
  else
    if p_disposition_action <> 'clear' then
      raise exception 'disposition action must be clear for an open project';
    end if;

    update public.sourcing_events
    set
      savings_disposition = null,
      savings_disposition_reason = null,
      savings_disposition_at = null,
      savings_disposition_by = null,
      updated_by = v_user,
      updated_at = now()
    where id = v_event and organization_id = v_org;
  end if;

  delete from public.realization_periods
  where savings_calculation_id = p_calc_id
    and organization_id = v_org;

  -- Persist the reversal reason in the immutable audit stream before clearing
  -- lifecycle metadata on the final estimated state.
  update public.savings_calculations
  set
    execution_note = concat_ws(
      E'\n',
      nullif(v_existing_note, ''),
      '[' || to_char(now(), 'YYYY-MM-DD HH24:MI:SSOF') || '] Reversal: ' || btrim(p_note)
    ),
    updated_by = v_user,
    updated_at = now()
  where id = p_calc_id and organization_id = v_org;

  update public.savings_periods
  set
    executed_baseline_amount = null,
    executed_opening_amount = null,
    executed_final_amount = null,
    executed_cost_reduction_amount = null,
    executed_cost_avoidance_amount = null,
    executed_total_savings_amount = null,
    updated_by = v_user,
    updated_at = now()
  where savings_calculation_id = p_calc_id
    and organization_id = v_org;

  update public.savings_calculations
  set
    calculation_status = 'estimated',
    executed_at = null,
    executed_by = null,
    execution_note = null,
    updated_by = v_user,
    updated_at = now()
  where id = p_calc_id
    and organization_id = v_org;
end
$$;

-- -------------------------------------------------------------------------
-- Direct-write boundary
-- -------------------------------------------------------------------------

revoke insert, update on public.savings_calculations from authenticated;

grant insert (
  id, organization_id, event_id, baseline_id, award_id,
  calculation_name, savings_type, baseline_total_amount, award_total_amount,
  gross_savings_amount, savings_percentage, net_savings_amount,
  recognition_notes, created_at, created_by, updated_at, updated_by,
  savings_start_date, savings_end_date, cost_reduction_amount,
  cost_avoidance_amount, opening_proposal_amount, schedule_start_month,
  schedule_start_year, schedule_period_type, schedule_period_count
) on public.savings_calculations to authenticated;

grant update (
  baseline_id, award_id, calculation_name, savings_type,
  baseline_total_amount, award_total_amount, gross_savings_amount,
  savings_percentage, net_savings_amount, recognition_notes,
  updated_at, updated_by, savings_start_date, savings_end_date,
  cost_reduction_amount, cost_avoidance_amount, opening_proposal_amount,
  schedule_start_month, schedule_start_year, schedule_period_type,
  schedule_period_count
) on public.savings_calculations to authenticated;

drop policy org_insert on public.savings_calculations;
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

drop policy org_update on public.savings_calculations;
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

drop policy org_delete on public.savings_calculations;
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

drop policy org_update on public.savings_periods;
create policy org_update on public.savings_periods
for update to authenticated
using (
  organization_id = public.current_org_id()
  and exists (
    select 1
    from public.savings_calculations calculation
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
    select 1
    from public.savings_calculations calculation
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

revoke all on function public.mark_savings_schedule_executed(uuid, text)
  from public, anon, authenticated;
revoke all on function public.correct_savings_execution(uuid, text, jsonb, jsonb)
  from public, anon, authenticated;
revoke all on function public.reverse_savings_execution(uuid, text, text)
  from public, anon, authenticated;

grant execute on function public.mark_savings_schedule_executed(uuid, text)
  to authenticated;
grant execute on function public.correct_savings_execution(uuid, text, jsonb, jsonb)
  to authenticated;
grant execute on function public.reverse_savings_execution(uuid, text, text)
  to authenticated;

commit;
