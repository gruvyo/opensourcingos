begin;

-- Keep the database arithmetic contract identical to lib/savings.chainSavings:
-- when Opening and Baseline both exist, avoidance is Opening - Baseline even
-- when that leg is zero or negative. The prior checks silently clamped those
-- outcomes to zero.
set local lock_timeout = '10s';
set local statement_timeout = '120s';

alter table public.savings_periods
  drop constraint chk_savings_periods_estimated_chain,
  drop constraint chk_savings_periods_executed_chain;

alter table public.savings_periods
  add constraint chk_savings_periods_estimated_chain check (
    cost_reduction_amount is not distinct from case
      when baseline_amount is null then null
      else baseline_amount - final_amount
    end
    and cost_avoidance_amount is not distinct from case
      when baseline_amount is not null and opening_amount is not null
        then opening_amount - baseline_amount
      when baseline_amount is null and opening_amount is not null
        then opening_amount - final_amount
      else 0
    end
    and total_savings_amount is not distinct from
      coalesce(cost_reduction_amount, 0) + cost_avoidance_amount
  ) not valid,
  add constraint chk_savings_periods_executed_chain check (
    executed_total_savings_amount is null
    or (
      executed_cost_reduction_amount is not distinct from case
        when executed_baseline_amount is null then null
        else executed_baseline_amount - executed_final_amount
      end
      and executed_cost_avoidance_amount is not distinct from case
        when executed_baseline_amount is not null
          and executed_opening_amount is not null
          then executed_opening_amount - executed_baseline_amount
        when executed_baseline_amount is null
          and executed_opening_amount is not null
          then executed_opening_amount - executed_final_amount
        else 0
      end
      and executed_total_savings_amount is not distinct from
        coalesce(executed_cost_reduction_amount, 0)
          + executed_cost_avoidance_amount
    )
  ) not valid;

alter table public.savings_calculations
  add constraint chk_savings_calculations_chain check (
    cost_reduction_amount is not distinct from case
      when baseline_total_amount is null then null
      else baseline_total_amount - award_total_amount
    end
    and cost_avoidance_amount is not distinct from case
      when baseline_total_amount is not null
        and opening_proposal_amount is not null
        then opening_proposal_amount - baseline_total_amount
      when baseline_total_amount is null
        and opening_proposal_amount is not null
        then opening_proposal_amount - award_total_amount
      else 0
    end
    and gross_savings_amount is not distinct from
      coalesce(cost_reduction_amount, 0) + cost_avoidance_amount
    and net_savings_amount is not distinct from gross_savings_amount
  ) not valid;

alter table public.savings_periods
  validate constraint chk_savings_periods_estimated_chain,
  validate constraint chk_savings_periods_executed_chain;

alter table public.savings_calculations
  validate constraint chk_savings_calculations_chain;

comment on constraint chk_savings_periods_estimated_chain
  on public.savings_periods is
  'Cent-exact estimated chain. Avoidance is Opening - Baseline without sign clamping.';
comment on constraint chk_savings_periods_executed_chain
  on public.savings_periods is
  'Cent-exact executed chain. Avoidance is Opening - Baseline without sign clamping.';
comment on constraint chk_savings_calculations_chain
  on public.savings_calculations is
  'Calculation anchors, signed legs, gross headline, and net headline satisfy the approved chain.';

-- Foreign-key cascades and SET NULL actions run below the parent statement and
-- can bypass the child table's RLS visibility. Use a narrowly scoped,
-- owner-executed guard so an executed financial record must be reversed before
-- its project, baseline, or award can be removed.
create function public.prevent_executed_savings_parent_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'sourcing_events' and exists (
    select 1
    from public.savings_calculations
    where event_id = old.id
      and calculation_status = 'executed'
  ) then
    raise exception 'reverse executed savings before deleting the project';
  end if;

  if tg_table_name = 'baselines' and exists (
    select 1
    from public.savings_calculations
    where baseline_id = old.id
      and calculation_status = 'executed'
  ) then
    raise exception 'reverse executed savings before deleting the baseline';
  end if;

  if tg_table_name = 'awards' and exists (
    select 1
    from public.savings_calculations
    where award_id = old.id
      and calculation_status = 'executed'
  ) then
    raise exception 'reverse executed savings before deleting the award';
  end if;

  return old;
end
$$;

create trigger sourcing_events_executed_savings_delete_guard
before delete on public.sourcing_events
for each row execute function public.prevent_executed_savings_parent_delete();

create trigger baselines_executed_savings_delete_guard
before delete on public.baselines
for each row execute function public.prevent_executed_savings_parent_delete();

create trigger awards_executed_savings_delete_guard
before delete on public.awards
for each row execute function public.prevent_executed_savings_parent_delete();

revoke all on function public.prevent_executed_savings_parent_delete()
  from public, anon, authenticated;
grant execute on function public.prevent_executed_savings_parent_delete()
  to service_role;

commit;
