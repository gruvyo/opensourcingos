begin;

alter table public.realization_periods
  add column projected_reduction_amount numeric(15,2),
  add column projected_avoidance_amount numeric(15,2),
  add column realized_reduction_amount numeric(15,2),
  add column realized_avoidance_amount numeric(15,2),
  alter column actual_amount drop default,
  alter column realized_savings drop default,
  alter column leakage_amount drop default;

comment on column public.realization_periods.projected_reduction_amount is
  'Executed cost-reduction comparator for this period.';
comment on column public.realization_periods.projected_avoidance_amount is
  'Executed cost-avoidance comparator for this period.';
comment on column public.realization_periods.realized_reduction_amount is
  'Realized cost reduction, derived from actual spend when defensible or entered directly.';
comment on column public.realization_periods.realized_avoidance_amount is
  'Realized cost avoidance entered directly because it is counterfactual and not derivable from spend.';
comment on column public.realization_periods.leakage_amount is
  'Reduction leakage only: positive executed reduction less realized reduction. Avoidance shortfall is never leakage.';

update public.realization_periods realization
set
  projected_reduction_amount = period.executed_cost_reduction_amount,
  projected_avoidance_amount = period.executed_cost_avoidance_amount
from public.savings_periods period
where realization.savings_period_id = period.id;

-- A historical direct total cannot be split between reduction and avoidance
-- without human evidence. Refuse silent allocation. The production audit for
-- this release found zero realization rows, so no manual classification is
-- needed there; other deployments receive a loud, recoverable migration stop.
do $$
begin
  if exists (
    select 1
    from public.realization_periods realization
    left join public.savings_periods period on period.id = realization.savings_period_id
    where period.id is null
  ) then
    raise exception 'manual linkage required for realization rows without an executed schedule period';
  end if;

  if exists (
    select 1
    from public.realization_periods
    where actual_amount is null
      and realized_savings is not null
  ) then
    raise exception 'manual classification required for direct-entry realization totals before per-leg migration';
  end if;
end
$$;

-- The old actual-spend writer stored baseline minus actual in the single
-- realized column. That value is mechanically the reduction leg.
update public.realization_periods
set realized_reduction_amount = realized_savings
where actual_amount is not null
  and realized_savings is not null;

create function public.derive_realization_status(
  p_projected_reduction numeric,
  p_projected_avoidance numeric,
  p_realized_reduction numeric,
  p_realized_avoidance numeric
) returns text
language plpgsql
immutable
security invoker
set search_path to 'pg_catalog'
as $$
declare
  v_reduction_expected boolean := p_projected_reduction is not null and p_projected_reduction <> 0;
  v_avoidance_expected boolean := p_projected_avoidance is not null and p_projected_avoidance <> 0;
  v_realized_total numeric := coalesce(p_realized_reduction, 0) + coalesce(p_realized_avoidance, 0);
  v_reduction_leakage numeric := case
    when p_projected_reduction is null or p_realized_reduction is null then null
    else greatest(p_projected_reduction - p_realized_reduction, 0)
  end;
begin
  if p_realized_reduction is null and p_realized_avoidance is null then
    return 'Pending';
  end if;

  if (v_reduction_expected and p_realized_reduction is null)
    or (v_avoidance_expected and p_realized_avoidance is null) then
    return 'In Progress';
  end if;

  if v_realized_total <= 0 then
    return case when coalesce(v_reduction_leakage, 0) > 0 then 'Leaked' else 'Not Realized' end;
  end if;

  if (not v_reduction_expected or p_realized_reduction >= p_projected_reduction)
    and (not v_avoidance_expected or p_realized_avoidance >= p_projected_avoidance) then
    return 'Realized';
  end if;

  return 'Partially Realized';
end
$$;

revoke all on function public.derive_realization_status(numeric, numeric, numeric, numeric)
  from public, anon, authenticated;
grant execute on function public.derive_realization_status(numeric, numeric, numeric, numeric)
  to authenticated, service_role;

create function public.derive_realization_period_fields()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_period public.savings_periods%rowtype;
begin
  if new.savings_period_id is not null then
    select * into v_period
    from public.savings_periods
    where id = new.savings_period_id;

    if found then
      new.baseline_amount := v_period.executed_baseline_amount;
      new.projected_reduction_amount := v_period.executed_cost_reduction_amount;
      new.projected_avoidance_amount := v_period.executed_cost_avoidance_amount;
    end if;
  end if;

  if new.actual_amount is not null and (
    tg_op = 'INSERT'
    or new.actual_amount is distinct from old.actual_amount
  ) then
    if new.projected_reduction_amount is null or new.baseline_amount is null then
      raise exception 'actual spend requires an executed reduction comparator' using errcode = '23514';
    end if;
    new.realized_reduction_amount := new.baseline_amount - new.actual_amount;
  end if;

  new.projected_savings := case
    when new.projected_reduction_amount is null and new.projected_avoidance_amount is null then null
    else coalesce(new.projected_reduction_amount, 0) + coalesce(new.projected_avoidance_amount, 0)
  end;
  new.realized_savings := case
    when new.realized_reduction_amount is null and new.realized_avoidance_amount is null then null
    else coalesce(new.realized_reduction_amount, 0) + coalesce(new.realized_avoidance_amount, 0)
  end;
  new.leakage_amount := case
    when new.projected_reduction_amount is null or new.realized_reduction_amount is null then null
    else greatest(new.projected_reduction_amount - new.realized_reduction_amount, 0)
  end;
  new.realization_status := public.derive_realization_status(
    new.projected_reduction_amount,
    new.projected_avoidance_amount,
    new.realized_reduction_amount,
    new.realized_avoidance_amount
  );

  return new;
end
$$;

revoke all on function public.derive_realization_period_fields()
  from public, anon, authenticated;
grant execute on function public.derive_realization_period_fields()
  to service_role;

create trigger realization_periods_derive_per_leg_fields
before insert or update on public.realization_periods
for each row execute function public.derive_realization_period_fields();

-- Run every existing row through the canonical derivation before constraints
-- make the model permanent.
update public.realization_periods
set realized_reduction_amount = realized_reduction_amount;

alter table public.realization_periods
  add constraint realization_periods_actual_nonnegative check (
    actual_amount is null or actual_amount >= 0
  ),
  add constraint realization_periods_projected_total_per_leg check (
    projected_savings is not distinct from case
      when projected_reduction_amount is null and projected_avoidance_amount is null then null
      else coalesce(projected_reduction_amount, 0) + coalesce(projected_avoidance_amount, 0)
    end
  ),
  add constraint realization_periods_realized_total_per_leg check (
    realized_savings is not distinct from case
      when realized_reduction_amount is null and realized_avoidance_amount is null then null
      else coalesce(realized_reduction_amount, 0) + coalesce(realized_avoidance_amount, 0)
    end
  ),
  add constraint realization_periods_reduction_leakage check (
    leakage_amount is not distinct from case
      when projected_reduction_amount is null or realized_reduction_amount is null then null
      else greatest(projected_reduction_amount - realized_reduction_amount, 0)
    end
  ),
  add constraint realization_periods_derived_status check (
    realization_status = public.derive_realization_status(
      projected_reduction_amount,
      projected_avoidance_amount,
      realized_reduction_amount,
      realized_avoidance_amount
    )
  );

-- Inputs stay editable by procurement/admin through RLS. Totals, leakage,
-- comparators, and status are trigger-derived and no longer directly writable.
revoke update on public.realization_periods from authenticated;
revoke update (
  period_name,
  period_start_date,
  period_end_date,
  baseline_amount,
  actual_amount,
  projected_savings,
  realized_savings,
  leakage_amount,
  leakage_reason,
  realization_status,
  evidence_document_id,
  notes
) on public.realization_periods from authenticated;
grant update (
  actual_amount,
  realized_reduction_amount,
  realized_avoidance_amount,
  leakage_reason,
  evidence_document_id,
  notes
) on public.realization_periods to authenticated;

commit;
