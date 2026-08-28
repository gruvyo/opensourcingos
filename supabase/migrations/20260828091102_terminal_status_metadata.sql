begin;

alter table public.project_choice_options
  add column is_terminal boolean not null default false,
  add column requires_savings_disposition boolean not null default false;

alter table public.project_choice_options
  add constraint project_choice_options_terminal_status_only
  check (not is_terminal or choice_type = 'event_status'),
  add constraint project_choice_options_savings_disposition_status_only
  check (
    not requires_savings_disposition
    or (choice_type = 'event_status' and project_type = 'Sourcing' and is_terminal)
  );

create unique index project_choice_options_one_savings_completion_status
  on public.project_choice_options (organization_id, project_type)
  where requires_savings_disposition;

comment on column public.project_choice_options.is_terminal is
  'True when this managed event status represents a finished project. New custom statuses default to non-terminal.';

comment on column public.project_choice_options.requires_savings_disposition is
  'True for the one Sourcing completion status that requires an executed/no-executed-savings decision. The flag survives status renames.';

update public.project_choice_options
set is_terminal = true
where choice_type = 'event_status'
  and label in ('Complete', 'Cancelled');

update public.project_choice_options
set requires_savings_disposition = true
where choice_type = 'event_status'
  and project_type = 'Sourcing'
  and label = 'Complete';

-- The completion identity is internal workflow metadata, not another
-- workspace preference. Administrators may rename the row, but ordinary API
-- writes cannot remove, archive, or transfer its financial guard.
create function public.protect_sourcing_completion_status()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
begin
  if current_user in ('postgres', 'service_role', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' and new.requires_savings_disposition then
    raise exception 'savings completion status metadata is system-managed' using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' and (
    (not old.requires_savings_disposition and new.requires_savings_disposition)
    or (
      old.requires_savings_disposition
      and (
        not new.requires_savings_disposition
        or not new.is_terminal
        or not new.active_flag
        or new.choice_type is distinct from old.choice_type
        or new.project_type is distinct from old.project_type
      )
    )
  ) then
    raise exception 'the required sourcing completion status may be renamed but not disabled' using errcode = '42501';
  end if;

  return new;
end
$$;

revoke all on function public.protect_sourcing_completion_status()
  from public, anon, authenticated;
grant execute on function public.protect_sourcing_completion_status()
  to service_role;

create trigger project_choice_options_protect_sourcing_completion
before insert or update on public.project_choice_options
for each row execute function public.protect_sourcing_completion_status();

-- Both the immediate and deferred lifecycle guards must follow the managed
-- option row. Otherwise renaming Complete would silently disable the guard.
create or replace function public.enforce_completed_project_savings_disposition()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
begin
  if new.project_type = 'Sourcing' and exists (
    select 1
    from public.project_choice_options choice
    where choice.organization_id = new.organization_id
      and choice.choice_type = 'event_status'
      and choice.project_type = new.project_type
      and choice.requires_savings_disposition
      and lower(btrim(choice.label)) = lower(btrim(new.event_status))
  ) then
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

create or replace function public.enforce_savings_completion_invariant()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_event_id uuid;
  v_organization_id uuid;
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

  select organization_id, project_type, event_status, savings_disposition, savings_disposition_reason
  into v_organization_id, v_project_type, v_event_status, v_disposition, v_reason
  from public.sourcing_events
  where id = v_event_id;

  if not found then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if v_project_type = 'Sourcing' and exists (
    select 1
    from public.project_choice_options choice
    where choice.organization_id = v_organization_id
      and choice.choice_type = 'event_status'
      and choice.project_type = v_project_type
      and choice.requires_savings_disposition
      and lower(btrim(choice.label)) = lower(btrim(v_event_status))
  ) then
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

create or replace function public.complete_sourcing_project(
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
  v_completion_status text;
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

  select label into v_completion_status
  from public.project_choice_options
  where organization_id = v_org
    and choice_type = 'event_status'
    and project_type = 'Sourcing'
    and requires_savings_disposition
    and active_flag;
  if not found then raise exception 'active sourcing completion status not found'; end if;
  if lower(btrim(v_status)) = lower(btrim(v_completion_status)) then
    raise exception 'project already complete';
  end if;

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
  set event_status = v_completion_status,
      savings_disposition = p_disposition,
      savings_disposition_reason = v_reason,
      savings_disposition_at = now(),
      savings_disposition_by = v_user,
      updated_by = v_user,
      updated_at = now()
  where id = p_event_id and organization_id = v_org;
end
$$;

create or replace function public.reverse_savings_execution(
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
  v_requires_disposition boolean;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'a reversal note is required'; end if;

  select organization_id, role into v_org, v_role
  from public.profiles where id = v_user;
  if v_org is null then raise exception 'workspace membership required'; end if;
  if v_role <> 'admin' then raise exception 'administrator role required'; end if;

  select event_id, calculation_status, execution_note
  into v_event, v_status, v_existing_note
  from public.savings_calculations
  where id = p_calc_id and organization_id = v_org
  for update;
  if v_event is null then raise exception 'savings calculation not found'; end if;
  if v_status <> 'executed' then raise exception 'savings schedule is not executed'; end if;

  select project_type, event_status into v_project_type, v_event_status
  from public.sourcing_events
  where id = v_event and organization_id = v_org
  for update;

  select exists (
    select 1 from public.project_choice_options choice
    where choice.organization_id = v_org
      and choice.choice_type = 'event_status'
      and choice.project_type = v_project_type
      and choice.requires_savings_disposition
      and lower(btrim(choice.label)) = lower(btrim(v_event_status))
  ) into v_requires_disposition;

  perform 1 from public.savings_periods
  where savings_calculation_id = p_calc_id and organization_id = v_org
  order by id for update;

  perform 1 from public.realization_periods
  where savings_calculation_id = p_calc_id and organization_id = v_org
  order by id for update;

  if exists (
    select 1 from public.realization_periods
    where savings_calculation_id = p_calc_id
      and organization_id = v_org
      and (actual_amount is not null or realized_savings is not null or coalesce(finance_validated, false))
  ) then
    raise exception 'execution cannot be reversed after realization evidence exists; use a correction';
  end if;

  if v_project_type = 'Sourcing' and v_requires_disposition then
    if p_disposition_action <> 'no_executed_savings' then
      raise exception 'reopen the completed project or choose no_executed_savings';
    end if;
    if length(btrim(p_note)) < 10 then
      raise exception 'completed projects without executed savings require a reason of at least 10 characters';
    end if;

    update public.sourcing_events
    set savings_disposition = 'no_executed_savings',
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
    set savings_disposition = null,
        savings_disposition_reason = null,
        savings_disposition_at = null,
        savings_disposition_by = null,
        updated_by = v_user,
        updated_at = now()
    where id = v_event and organization_id = v_org;
  end if;

  delete from public.realization_periods
  where savings_calculation_id = p_calc_id and organization_id = v_org;

  update public.savings_calculations
  set execution_note = concat_ws(
        E'\n', nullif(v_existing_note, ''),
        '[' || to_char(now(), 'YYYY-MM-DD HH24:MI:SSOF') || '] Reversal: ' || btrim(p_note)
      ),
      updated_by = v_user,
      updated_at = now()
  where id = p_calc_id and organization_id = v_org;

  update public.savings_periods
  set executed_baseline_amount = null,
      executed_opening_amount = null,
      executed_final_amount = null,
      executed_cost_reduction_amount = null,
      executed_cost_avoidance_amount = null,
      executed_total_savings_amount = null,
      updated_by = v_user,
      updated_at = now()
  where savings_calculation_id = p_calc_id and organization_id = v_org;

  update public.savings_calculations
  set calculation_status = 'estimated',
      executed_at = null,
      executed_by = null,
      execution_note = null,
      legacy_execution_actor_missing = false,
      updated_by = v_user,
      updated_at = now()
  where id = p_calc_id and organization_id = v_org;
end
$$;

commit;
