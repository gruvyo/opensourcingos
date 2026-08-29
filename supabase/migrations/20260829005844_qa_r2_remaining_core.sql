begin;

-- Legacy clients and the application population rule both treat a missing
-- project type as Sourcing. Make that compatibility rule structural so the
-- database guards and every writer see the same population.
update public.sourcing_events
set project_type = 'Sourcing'
where project_type is null;

alter table public.sourcing_events
  alter column project_type set default 'Sourcing',
  alter column project_type set not null;

-- Add one baseline line and recompute the selected baseline amount inside the
-- same parent-row lock. The browser cannot supply workspace, project, actor, or
-- line ordering; all four come from trusted database state.
create function public.add_baseline_line(
  p_baseline_id uuid,
  p_line jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_event uuid;
  v_lock_status text;
  v_scope_line uuid;
  v_line_id uuid;
  v_line_number integer;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  if jsonb_typeof(p_line) is distinct from 'object' then
    raise exception 'baseline line must be a JSON object';
  end if;

  if exists (
    select 1 from jsonb_object_keys(p_line) as field(name)
    where field.name not in (
      'scope_line_id', 'baseline_unit_price', 'baseline_quantity',
      'baseline_extended_amount', 'baseline_recurring_amount',
      'baseline_one_time_amount', 'baseline_term_months',
      'annualized_baseline_amount', 'normalized_quantity',
      'normalized_unit_price', 'normalized_extended_amount'
    )
  ) then
    raise exception 'baseline line contains unsupported fields';
  end if;

  select organization_id, role into v_org, v_role
  from public.profiles where id = v_user;
  if v_org is null then raise exception 'workspace membership required'; end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;

  select event_id, baseline_lock_status into v_event, v_lock_status
  from public.baselines
  where id = p_baseline_id and organization_id = v_org
  for update;
  if v_event is null then raise exception 'baseline not found'; end if;
  if v_lock_status is distinct from 'Draft' then
    raise exception 'locked baselines cannot be edited';
  end if;

  v_scope_line := nullif(p_line->>'scope_line_id', '')::uuid;
  if v_scope_line is not null and not exists (
    select 1 from public.event_scope_lines
    where id = v_scope_line
      and event_id = v_event
      and organization_id = v_org
  ) then
    raise exception 'scope line not found';
  end if;

  select coalesce(max(line_number), 0) + 1 into v_line_number
  from public.baseline_lines
  where baseline_id = p_baseline_id and organization_id = v_org;

  insert into public.baseline_lines (
    organization_id, baseline_id, event_id, scope_line_id, line_number,
    baseline_unit_price, baseline_quantity, baseline_extended_amount,
    baseline_recurring_amount, baseline_one_time_amount,
    baseline_term_months, annualized_baseline_amount,
    normalized_quantity, normalized_unit_price, normalized_extended_amount,
    created_by, updated_by
  ) values (
    v_org, p_baseline_id, v_event, v_scope_line, v_line_number,
    coalesce((p_line->>'baseline_unit_price')::numeric, 0),
    coalesce((p_line->>'baseline_quantity')::numeric, 0),
    coalesce((p_line->>'baseline_extended_amount')::numeric, 0),
    coalesce((p_line->>'baseline_recurring_amount')::numeric, 0),
    coalesce((p_line->>'baseline_one_time_amount')::numeric, 0),
    coalesce((p_line->>'baseline_term_months')::numeric, 12),
    coalesce((p_line->>'annualized_baseline_amount')::numeric, 0),
    coalesce((p_line->>'normalized_quantity')::numeric, 0),
    coalesce((p_line->>'normalized_unit_price')::numeric, 0),
    coalesce((p_line->>'normalized_extended_amount')::numeric, 0),
    v_user, v_user
  ) returning id into v_line_id;

  update public.baselines
  set baseline_total_amount = (
        select coalesce(sum(baseline_extended_amount), 0)
        from public.baseline_lines
        where baseline_id = p_baseline_id and organization_id = v_org
      ),
      updated_by = v_user,
      updated_at = now()
  where id = p_baseline_id and organization_id = v_org;

  return v_line_id;
end
$$;

-- Delete a line and recompute the total under the same baseline lock. Resolve
-- the parent once for lock ordering, then recheck the child after acquiring it.
create function public.delete_baseline_line(p_baseline_line_id uuid)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_baseline uuid;
  v_lock_status text;
begin
  if v_user is null then raise exception 'authentication required'; end if;

  select organization_id, role into v_org, v_role
  from public.profiles where id = v_user;
  if v_org is null then raise exception 'workspace membership required'; end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;

  select baseline_id into v_baseline
  from public.baseline_lines
  where id = p_baseline_line_id and organization_id = v_org;
  if v_baseline is null then raise exception 'baseline line not found'; end if;

  select baseline_lock_status into v_lock_status
  from public.baselines
  where id = v_baseline and organization_id = v_org
  for update;
  if not found then raise exception 'baseline line not found'; end if;
  if v_lock_status is distinct from 'Draft' then
    raise exception 'locked baselines cannot be edited';
  end if;

  delete from public.baseline_lines
  where id = p_baseline_line_id
    and baseline_id = v_baseline
    and organization_id = v_org;
  if not found then raise exception 'baseline line not found'; end if;

  update public.baselines
  set baseline_total_amount = (
        select coalesce(sum(baseline_extended_amount), 0)
        from public.baseline_lines
        where baseline_id = v_baseline and organization_id = v_org
      ),
      updated_by = v_user,
      updated_at = now()
  where id = v_baseline and organization_id = v_org;
end
$$;

-- Direct line creation/deletion can otherwise leave the baseline total stale.
revoke insert, delete on public.baseline_lines from authenticated;

revoke all on function public.add_baseline_line(uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.delete_baseline_line(uuid)
  from public, anon, authenticated;
grant execute on function public.add_baseline_line(uuid, jsonb) to authenticated;
grant execute on function public.delete_baseline_line(uuid) to authenticated;

-- Deployments that already ran the per-leg migration may contain untouched
-- pre-migration shells that were derived as zero realization / Leaked. Return
-- only the unambiguous empty-evidence shape to Pending. Production has no rows,
-- so this is a portability repair and changes no current tenant data.
update public.realization_periods
set actual_amount = null,
    realized_reduction_amount = null,
    realized_savings = null,
    leakage_amount = null,
    realization_status = 'Pending'
where actual_amount = 0
  and realized_reduction_amount = 0
  and realized_avoidance_amount is null
  and realized_savings = 0
  and realization_status = 'Leaked'
  and not finance_validated
  and evidence_document_id is null
  and notes is null
  and leakage_reason is null;

commit;
