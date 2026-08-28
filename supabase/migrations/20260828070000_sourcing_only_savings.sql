begin;

-- Support / Non-Commercial projects are operational records with $0 savings.
-- Enforce that boundary below the UI so direct Data API calls, future RPCs,
-- and concurrent Project Type changes cannot create a mixed population.
create function public.enforce_sourcing_project_savings()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_event_id uuid;
  v_calculation_event_id uuid;
  v_event_organization_id uuid;
  v_project_type text;
begin
  if tg_table_name = 'sourcing_events' then
    if new.project_type = 'Sourcing' or new.project_type is not distinct from old.project_type then
      return new;
    end if;

    if exists (
      select 1 from public.savings_calculations savings_row where savings_row.event_id = new.id
    ) or exists (
      select 1 from public.savings_calculation_lines savings_row where savings_row.event_id = new.id
    ) or exists (
      select 1 from public.savings_periods savings_row where savings_row.event_id = new.id
    ) or exists (
      select 1 from public.realization_periods savings_row where savings_row.event_id = new.id
    ) then
      raise exception 'Projects with savings records cannot be changed to Support / Non-Commercial'
        using errcode = '23514';
    end if;

    return new;
  end if;

  if tg_table_name = 'savings_calculations' then
    v_event_id := new.event_id;
  elsif tg_table_name = 'savings_calculation_lines' then
    if new.savings_calculation_id is null then
      raise exception 'Savings detail requires a project calculation'
        using errcode = '23514';
    end if;

    select calculation.event_id
      into v_calculation_event_id
    from public.savings_calculations calculation
    where calculation.id = new.savings_calculation_id;

    if not found or v_calculation_event_id is null then
      raise exception 'Savings detail requires a linked project calculation'
        using errcode = '23514';
    end if;

    if new.event_id is distinct from v_calculation_event_id then
      raise exception 'Savings detail must use its calculation project'
        using errcode = '23514';
    end if;

    v_event_id := v_calculation_event_id;
  elsif tg_table_name = 'savings_periods' then
    select calculation.event_id
      into v_calculation_event_id
    from public.savings_calculations calculation
    where calculation.id = new.savings_calculation_id;

    if not found or v_calculation_event_id is null then
      raise exception 'Savings schedule requires a linked project calculation'
        using errcode = '23514';
    end if;

    if new.event_id is distinct from v_calculation_event_id then
      raise exception 'Savings schedule must use its calculation project'
        using errcode = '23514';
    end if;

    v_event_id := v_calculation_event_id;
  elsif tg_table_name = 'realization_periods' then
    v_event_id := new.event_id;

    if new.savings_calculation_id is not null then
      select calculation.event_id
        into v_calculation_event_id
      from public.savings_calculations calculation
      where calculation.id = new.savings_calculation_id;

      if not found or v_calculation_event_id is distinct from v_event_id then
        raise exception 'Savings realization must use its calculation project'
          using errcode = '23514';
      end if;
    end if;
  else
    raise exception 'Unsupported savings guard table: %', tg_table_name;
  end if;

  -- event_id remains nullable for a narrow legacy/invariant-test path. Unlinked
  -- rows are excluded by every reporting population and cannot be schedules or
  -- realization evidence. Linked project savings are the boundary enforced here.
  if tg_table_name = 'savings_calculations' and v_event_id is null then
    return new;
  end if;

  if v_event_id is null then
    raise exception 'Savings records require a linked Sourcing Project'
      using errcode = '23514';
  end if;

  -- The parent lock serializes savings creation against a simultaneous attempt
  -- to convert this project to Support / Non-Commercial.
  select event.organization_id, event.project_type
    into v_event_organization_id, v_project_type
  from public.sourcing_events event
  where event.id = v_event_id
  for key share;

  if not found or v_project_type is distinct from 'Sourcing' then
    raise exception 'Savings records require a Sourcing Project'
      using errcode = '23514';
  end if;

  if new.organization_id is distinct from v_event_organization_id then
    raise exception 'Savings records must use the project workspace'
      using errcode = '23514';
  end if;

  return new;
end
$$;

revoke all on function public.enforce_sourcing_project_savings()
  from public, anon, authenticated;
grant execute on function public.enforce_sourcing_project_savings()
  to service_role;

create trigger sourcing_events_savings_population_guard
before update of project_type on public.sourcing_events
for each row execute function public.enforce_sourcing_project_savings();

create trigger savings_calculations_sourcing_only_guard
before insert or update of organization_id, event_id
on public.savings_calculations
for each row execute function public.enforce_sourcing_project_savings();

create trigger savings_calculation_lines_sourcing_only_guard
before insert or update of organization_id, event_id, savings_calculation_id
on public.savings_calculation_lines
for each row execute function public.enforce_sourcing_project_savings();

create trigger savings_periods_sourcing_only_guard
before insert or update of organization_id, event_id, savings_calculation_id
on public.savings_periods
for each row execute function public.enforce_sourcing_project_savings();

create trigger realization_periods_sourcing_only_guard
before insert or update of organization_id, event_id, savings_calculation_id
on public.realization_periods
for each row execute function public.enforce_sourcing_project_savings();

commit;
