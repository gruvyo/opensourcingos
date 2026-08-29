begin;

-- Baseline quality is a server-side booking invariant. Browser controls are
-- advisory: direct RPC callers must not be able to publish cost reduction
-- against a soft (or absent) baseline, and a schedule must not mix captured
-- and missing baseline anchors because its aggregate chain would be ambiguous.
create function public.assert_savings_schedule_baseline_quality(
  p_savings_calculation_id uuid,
  p_periods jsonb,
  p_use_selected_baseline boolean
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_event uuid;
  v_calculation_baseline uuid;
  v_baseline_type text;
  v_override boolean := false;
  v_override_reason text;
  v_is_hard boolean := false;
  v_any_baseline boolean := false;
  v_any_missing_baseline boolean := false;
  v_any_reduction boolean := false;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;
  if jsonb_typeof(p_periods) is distinct from 'array' then
    raise exception 'periods must be a JSON array';
  end if;

  select organization_id into v_org
  from public.profiles
  where id = v_user;
  if v_org is null then
    raise exception 'workspace membership required';
  end if;

  select event_id, baseline_id
  into v_event, v_calculation_baseline
  from public.savings_calculations
  where id = p_savings_calculation_id
    and organization_id = v_org
  for update;
  if v_event is null then
    raise exception 'savings calculation not found';
  end if;

  perform 1
  from public.sourcing_events
  where id = v_event and organization_id = v_org
  for update;

  -- Lock all project baselines in a deterministic order so selection cannot
  -- change between this assertion and the writer called by the wrapper.
  perform 1
  from public.baselines
  where event_id = v_event and organization_id = v_org
  order by id
  for update;

  if p_use_selected_baseline then
    select baseline_type, hard_reduction_override,
           hard_reduction_override_reason
    into v_baseline_type, v_override, v_override_reason
    from public.baselines
    where event_id = v_event
      and organization_id = v_org
      and is_selected
    order by id
    limit 1;
  elsif v_calculation_baseline is not null then
    select baseline_type, hard_reduction_override,
           hard_reduction_override_reason
    into v_baseline_type, v_override, v_override_reason
    from public.baselines
    where id = v_calculation_baseline
      and event_id = v_event
      and organization_id = v_org;
  end if;

  v_is_hard := v_baseline_type in (
    'Current Contract',
    'Prior 12-Month Actual',
    'Should-Cost Model'
  ) or (
    coalesce(v_override, false)
    and length(btrim(coalesce(v_override_reason, ''))) >= 10
  );

  select
    coalesce(bool_or(item.value ? 'baseline_amount'
      and item.value->'baseline_amount' <> 'null'::jsonb), false),
    coalesce(bool_or(not (item.value ? 'baseline_amount')
      or item.value->'baseline_amount' = 'null'::jsonb), false),
    coalesce(bool_or(item.value ? 'cost_reduction_amount'
      and item.value->'cost_reduction_amount' <> 'null'::jsonb), false)
  into v_any_baseline, v_any_missing_baseline, v_any_reduction
  from jsonb_array_elements(p_periods) item(value);

  if v_any_baseline and v_any_missing_baseline then
    raise exception 'A schedule cannot mix captured and missing baseline amounts. Capture every period or clear every period.'
      using errcode = '23514';
  end if;

  if (v_any_baseline or v_any_reduction) and not v_is_hard then
    raise exception 'Soft baselines cannot book hard cost reduction. Use cost avoidance or approve a documented hard-baseline override.'
      using errcode = '23514';
  end if;
end
$$;

revoke all on function public.assert_savings_schedule_baseline_quality(uuid, jsonb, boolean)
  from public, anon, authenticated;
grant execute on function public.assert_savings_schedule_baseline_quality(uuid, jsonb, boolean)
  to service_role;

create function public.assert_savings_calculation_baseline_quality(
  p_event_id uuid,
  p_calculation jsonb
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_baseline_id uuid;
  v_baseline_type text;
  v_override boolean := false;
  v_override_reason text;
  v_is_hard boolean := false;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;
  if jsonb_typeof(p_calculation) is distinct from 'object' then
    raise exception 'calculation must be a JSON object';
  end if;

  select organization_id into v_org
  from public.profiles
  where id = v_user;
  if v_org is null then
    raise exception 'workspace membership required';
  end if;

  perform 1
  from public.sourcing_events
  where id = p_event_id and organization_id = v_org
  for update;
  if not found then
    raise exception 'sourcing project not found';
  end if;

  perform 1
  from public.baselines
  where event_id = p_event_id and organization_id = v_org
  order by id
  for update;

  v_baseline_id := nullif(p_calculation->>'baseline_id', '')::uuid;
  if v_baseline_id is not null then
    select baseline_type, hard_reduction_override,
           hard_reduction_override_reason
    into v_baseline_type, v_override, v_override_reason
    from public.baselines
    where id = v_baseline_id
      and event_id = p_event_id
      and organization_id = v_org;
  end if;

  v_is_hard := v_baseline_type in (
    'Current Contract',
    'Prior 12-Month Actual',
    'Should-Cost Model'
  ) or (
    coalesce(v_override, false)
    and length(btrim(coalesce(v_override_reason, ''))) >= 10
  );

  if (
    (p_calculation ? 'baseline_total_amount'
      and p_calculation->'baseline_total_amount' <> 'null'::jsonb)
    or (p_calculation ? 'cost_reduction_amount'
      and p_calculation->'cost_reduction_amount' <> 'null'::jsonb)
  ) and not v_is_hard then
    raise exception 'Soft baselines cannot book hard cost reduction. Use cost avoidance or approve a documented hard-baseline override.'
      using errcode = '23514';
  end if;
end
$$;

revoke all on function public.assert_savings_calculation_baseline_quality(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.assert_savings_calculation_baseline_quality(uuid, jsonb)
  to service_role;

alter function public.save_estimated_savings_calculation(uuid, jsonb, uuid)
  rename to save_estimated_savings_calculation_unchecked;

revoke all on function public.save_estimated_savings_calculation_unchecked(uuid, jsonb, uuid)
  from public, anon, authenticated;

create function public.save_estimated_savings_calculation(
  p_event_id uuid,
  p_calculation jsonb,
  p_calculation_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  perform public.assert_savings_calculation_baseline_quality(
    p_event_id, p_calculation
  );
  return public.save_estimated_savings_calculation_unchecked(
    p_event_id, p_calculation, p_calculation_id
  );
end
$$;

revoke all on function public.save_estimated_savings_calculation(uuid, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.save_estimated_savings_calculation(uuid, jsonb, uuid)
  to authenticated;

create or replace function public.replace_savings_schedule(
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
begin
  perform public.assert_jsonb_money_cent_exact(
    p_periods,
    array[
      'baseline_amount', 'opening_amount', 'final_amount',
      'cost_reduction_amount', 'cost_avoidance_amount', 'total_savings_amount'
    ]
  );
  perform public.assert_savings_schedule_baseline_quality(
    p_savings_calculation_id, p_periods, true
  );
  perform public.replace_savings_schedule_unchecked(
    p_savings_calculation_id,
    p_schedule_start_month,
    p_schedule_start_year,
    p_schedule_period_type,
    p_periods
  );
end
$$;

revoke all on function public.replace_savings_schedule(uuid, integer, integer, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.replace_savings_schedule(uuid, integer, integer, text, jsonb)
  to authenticated;

create or replace function public.correct_savings_execution(
  p_calc_id uuid,
  p_note text,
  p_calculation jsonb,
  p_periods jsonb
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  perform public.assert_jsonb_money_cent_exact(
    jsonb_build_array(p_calculation),
    array[
      'baseline_total_amount', 'opening_proposal_amount', 'award_total_amount',
      'gross_savings_amount', 'net_savings_amount',
      'cost_reduction_amount', 'cost_avoidance_amount', 'savings_percentage'
    ]
  );
  perform public.assert_jsonb_money_cent_exact(
    p_periods,
    array[
      'baseline_amount', 'opening_amount', 'final_amount',
      'cost_reduction_amount', 'cost_avoidance_amount', 'total_savings_amount'
    ]
  );
  perform public.assert_savings_schedule_baseline_quality(
    p_calc_id, p_periods, false
  );
  perform public.correct_savings_execution_unchecked(
    p_calc_id, p_note, p_calculation, p_periods
  );
end
$$;

revoke all on function public.correct_savings_execution(uuid, text, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.correct_savings_execution(uuid, text, jsonb, jsonb)
  to authenticated;

commit;
