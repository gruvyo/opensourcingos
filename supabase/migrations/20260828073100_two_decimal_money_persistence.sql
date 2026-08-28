begin;

-- Modification 6B: store schedule money at exact two-decimal currency
-- precision. Regular periods round to cents; the last period absorbs each
-- anchor residual. Savings legs are then derived from the balanced anchors,
-- preserving both row equations and calculation totals.
set local lock_timeout = '10s';
set local statement_timeout = '120s';

lock table public.savings_calculations, public.savings_periods
  in share row exclusive mode;

do $$
declare
  manifest private.two_decimal_money_backup_manifest_20260828%rowtype;
begin
  select * into strict manifest
  from private.two_decimal_money_backup_manifest_20260828;

  if (select count(*) from public.savings_calculations) <> manifest.calculation_count
    or (select count(*) from public.savings_calculations where calculation_status = 'estimated') <> manifest.estimated_calculation_count
    or (select count(*) from public.savings_calculations where calculation_status = 'executed') <> manifest.executed_calculation_count
    or (select count(*) from public.savings_periods) <> manifest.period_count
    or (select count(*) from public.savings_periods where executed_total_savings_amount is not null) <> manifest.executed_period_count
    or (select count(*) from public.realization_periods) <> manifest.realization_period_count then
    raise exception 'Two-decimal backup no longer matches the live population';
  end if;

  if exists (
    select id, cost_reduction_amount, cost_avoidance_amount, opening_proposal_amount
    from public.savings_calculations
    except
    select id, cost_reduction_amount, cost_avoidance_amount, opening_proposal_amount
    from private.two_decimal_savings_calculations_20260828
  ) or exists (
    select id, cost_reduction_amount, cost_avoidance_amount, opening_proposal_amount
    from private.two_decimal_savings_calculations_20260828
    except
    select id, cost_reduction_amount, cost_avoidance_amount, opening_proposal_amount
    from public.savings_calculations
  ) then
    raise exception 'Savings calculations changed after the two-decimal backup';
  end if;

  if exists (
    select id, baseline_amount, opening_amount, final_amount,
      cost_reduction_amount, cost_avoidance_amount, total_savings_amount,
      executed_baseline_amount, executed_opening_amount, executed_final_amount,
      executed_cost_reduction_amount, executed_cost_avoidance_amount,
      executed_total_savings_amount
    from public.savings_periods
    except
    select id, baseline_amount, opening_amount, final_amount,
      cost_reduction_amount, cost_avoidance_amount, total_savings_amount,
      executed_baseline_amount, executed_opening_amount, executed_final_amount,
      executed_cost_reduction_amount, executed_cost_avoidance_amount,
      executed_total_savings_amount
    from private.two_decimal_savings_periods_20260828
  ) or exists (
    select id, baseline_amount, opening_amount, final_amount,
      cost_reduction_amount, cost_avoidance_amount, total_savings_amount,
      executed_baseline_amount, executed_opening_amount, executed_final_amount,
      executed_cost_reduction_amount, executed_cost_avoidance_amount,
      executed_total_savings_amount
    from private.two_decimal_savings_periods_20260828
    except
    select id, baseline_amount, opening_amount, final_amount,
      cost_reduction_amount, cost_avoidance_amount, total_savings_amount,
      executed_baseline_amount, executed_opening_amount, executed_final_amount,
      executed_cost_reduction_amount, executed_cost_avoidance_amount,
      executed_total_savings_amount
    from public.savings_periods
  ) then
    raise exception 'Savings periods changed after the two-decimal backup';
  end if;
end
$$;

with ranked as (
  select period.*,
    row_number() over (
      partition by savings_calculation_id
      order by period_number desc, id desc
    ) = 1 as is_residual_period
  from public.savings_periods period
),
targets as (
  select savings_calculation_id,
    round(sum(baseline_amount), 2) as baseline_target,
    round(sum(opening_amount), 2) as opening_target,
    round(sum(final_amount), 2) as final_target,
    round(sum(executed_baseline_amount), 2) as executed_baseline_target,
    round(sum(executed_opening_amount), 2) as executed_opening_target,
    round(sum(executed_final_amount), 2) as executed_final_target
  from ranked
  group by savings_calculation_id
),
regular_totals as (
  select savings_calculation_id,
    sum(round(baseline_amount, 2)) filter (where not is_residual_period) as baseline_regular,
    sum(round(opening_amount, 2)) filter (where not is_residual_period) as opening_regular,
    sum(round(final_amount, 2)) filter (where not is_residual_period) as final_regular,
    sum(round(executed_baseline_amount, 2)) filter (where not is_residual_period) as executed_baseline_regular,
    sum(round(executed_opening_amount, 2)) filter (where not is_residual_period) as executed_opening_regular,
    sum(round(executed_final_amount, 2)) filter (where not is_residual_period) as executed_final_regular
  from ranked
  group by savings_calculation_id
),
anchors as (
  select ranked.id,
    ranked.executed_total_savings_amount is not null as has_executed_snapshot,
    case when is_residual_period
      then targets.baseline_target - coalesce(regular_totals.baseline_regular, 0)
      else round(ranked.baseline_amount, 2) end as baseline_amount,
    case when is_residual_period
      then targets.opening_target - coalesce(regular_totals.opening_regular, 0)
      else round(ranked.opening_amount, 2) end as opening_amount,
    case when is_residual_period
      then targets.final_target - coalesce(regular_totals.final_regular, 0)
      else round(ranked.final_amount, 2) end as final_amount,
    case when is_residual_period
      then targets.executed_baseline_target - coalesce(regular_totals.executed_baseline_regular, 0)
      else round(ranked.executed_baseline_amount, 2) end as executed_baseline_amount,
    case when is_residual_period
      then targets.executed_opening_target - coalesce(regular_totals.executed_opening_regular, 0)
      else round(ranked.executed_opening_amount, 2) end as executed_opening_amount,
    case when is_residual_period
      then targets.executed_final_target - coalesce(regular_totals.executed_final_regular, 0)
      else round(ranked.executed_final_amount, 2) end as executed_final_amount
  from ranked
  join targets using (savings_calculation_id)
  join regular_totals using (savings_calculation_id)
),
balanced as (
  select anchors.*,
    case when baseline_amount is null then null
      else baseline_amount - final_amount end as cost_reduction_amount,
    case
      when baseline_amount is not null and opening_amount > baseline_amount
        then opening_amount - baseline_amount
      when baseline_amount is null and opening_amount is not null
        then opening_amount - final_amount
      else 0
    end as cost_avoidance_amount,
    case
      when baseline_amount is not null and opening_amount > baseline_amount
        then (baseline_amount - final_amount) + (opening_amount - baseline_amount)
      when baseline_amount is not null then baseline_amount - final_amount
      when opening_amount is not null then opening_amount - final_amount
      else 0
    end as total_savings_amount,
    case when not has_executed_snapshot then null
      when executed_baseline_amount is null then null
      else executed_baseline_amount - executed_final_amount end as executed_cost_reduction_amount,
    case when not has_executed_snapshot then null
      when executed_baseline_amount is not null and executed_opening_amount > executed_baseline_amount
        then executed_opening_amount - executed_baseline_amount
      when executed_baseline_amount is null and executed_opening_amount is not null
        then executed_opening_amount - executed_final_amount
      else 0
    end as executed_cost_avoidance_amount,
    case when not has_executed_snapshot then null
      when executed_baseline_amount is not null and executed_opening_amount > executed_baseline_amount
        then (executed_baseline_amount - executed_final_amount)
          + (executed_opening_amount - executed_baseline_amount)
      when executed_baseline_amount is not null
        then executed_baseline_amount - executed_final_amount
      when executed_opening_amount is not null
        then executed_opening_amount - executed_final_amount
      else 0
    end as executed_total_savings_amount
  from anchors
)
update public.savings_periods period
set baseline_amount = balanced.baseline_amount,
    opening_amount = balanced.opening_amount,
    final_amount = balanced.final_amount,
    cost_reduction_amount = balanced.cost_reduction_amount,
    cost_avoidance_amount = balanced.cost_avoidance_amount,
    total_savings_amount = balanced.total_savings_amount,
    executed_baseline_amount = balanced.executed_baseline_amount,
    executed_opening_amount = balanced.executed_opening_amount,
    executed_final_amount = balanced.executed_final_amount,
    executed_cost_reduction_amount = balanced.executed_cost_reduction_amount,
    executed_cost_avoidance_amount = balanced.executed_cost_avoidance_amount,
    executed_total_savings_amount = balanced.executed_total_savings_amount
from balanced
where period.id = balanced.id
  and row(
    period.baseline_amount, period.opening_amount, period.final_amount,
    period.cost_reduction_amount, period.cost_avoidance_amount, period.total_savings_amount,
    period.executed_baseline_amount, period.executed_opening_amount, period.executed_final_amount,
    period.executed_cost_reduction_amount, period.executed_cost_avoidance_amount,
    period.executed_total_savings_amount
  ) is distinct from row(
    balanced.baseline_amount, balanced.opening_amount, balanced.final_amount,
    balanced.cost_reduction_amount, balanced.cost_avoidance_amount, balanced.total_savings_amount,
    balanced.executed_baseline_amount, balanced.executed_opening_amount, balanced.executed_final_amount,
    balanced.executed_cost_reduction_amount, balanced.executed_cost_avoidance_amount,
    balanced.executed_total_savings_amount
  );

with period_totals as (
  select savings_calculation_id,
    sum(baseline_amount) as baseline_amount,
    sum(opening_amount) as opening_amount,
    sum(final_amount) as final_amount,
    sum(cost_reduction_amount) as cost_reduction_amount,
    sum(cost_avoidance_amount) as cost_avoidance_amount,
    sum(total_savings_amount) as total_savings_amount
  from public.savings_periods
  group by savings_calculation_id
)
update public.savings_calculations calculation
set baseline_total_amount = totals.baseline_amount,
    opening_proposal_amount = totals.opening_amount,
    award_total_amount = totals.final_amount,
    cost_reduction_amount = totals.cost_reduction_amount,
    cost_avoidance_amount = totals.cost_avoidance_amount,
    gross_savings_amount = totals.total_savings_amount,
    net_savings_amount = totals.total_savings_amount
from period_totals totals
where calculation.id = totals.savings_calculation_id
  and row(
    calculation.baseline_total_amount, calculation.opening_proposal_amount,
    calculation.award_total_amount, calculation.cost_reduction_amount,
    calculation.cost_avoidance_amount, calculation.gross_savings_amount,
    calculation.net_savings_amount
  ) is distinct from row(
    totals.baseline_amount, totals.opening_amount, totals.final_amount,
    totals.cost_reduction_amount, totals.cost_avoidance_amount,
    totals.total_savings_amount, totals.total_savings_amount
  );

alter table public.savings_calculations
  alter column cost_reduction_amount type numeric(15,2) using round(cost_reduction_amount, 2),
  alter column cost_avoidance_amount type numeric(15,2) using round(cost_avoidance_amount, 2),
  alter column opening_proposal_amount type numeric(15,2) using round(opening_proposal_amount, 2);

alter table public.savings_periods
  alter column baseline_amount type numeric(15,2) using round(baseline_amount, 2),
  alter column opening_amount type numeric(15,2) using round(opening_amount, 2),
  alter column final_amount type numeric(15,2) using round(final_amount, 2),
  alter column cost_reduction_amount type numeric(15,2) using round(cost_reduction_amount, 2),
  alter column cost_avoidance_amount type numeric(15,2) using round(cost_avoidance_amount, 2),
  alter column total_savings_amount type numeric(15,2) using round(total_savings_amount, 2),
  alter column executed_baseline_amount type numeric(15,2) using round(executed_baseline_amount, 2),
  alter column executed_opening_amount type numeric(15,2) using round(executed_opening_amount, 2),
  alter column executed_final_amount type numeric(15,2) using round(executed_final_amount, 2),
  alter column executed_cost_reduction_amount type numeric(15,2) using round(executed_cost_reduction_amount, 2),
  alter column executed_cost_avoidance_amount type numeric(15,2) using round(executed_cost_avoidance_amount, 2),
  alter column executed_total_savings_amount type numeric(15,2) using round(executed_total_savings_amount, 2);

alter table public.savings_periods
  add constraint chk_savings_periods_estimated_chain check (
    cost_reduction_amount is not distinct from case
      when baseline_amount is null then null
      else baseline_amount - final_amount
    end
    and cost_avoidance_amount = case
      when baseline_amount is not null and opening_amount > baseline_amount
        then opening_amount - baseline_amount
      when baseline_amount is null and opening_amount is not null
        then opening_amount - final_amount
      else 0
    end
    and total_savings_amount = coalesce(cost_reduction_amount, 0) + cost_avoidance_amount
  ),
  add constraint chk_savings_periods_executed_chain check (
    executed_total_savings_amount is null
    or (
      executed_cost_reduction_amount is not distinct from case
        when executed_baseline_amount is null then null
        else executed_baseline_amount - executed_final_amount
      end
      and executed_cost_avoidance_amount = case
        when executed_baseline_amount is not null
          and executed_opening_amount > executed_baseline_amount
          then executed_opening_amount - executed_baseline_amount
        when executed_baseline_amount is null and executed_opening_amount is not null
          then executed_opening_amount - executed_final_amount
        else 0
      end
      and executed_total_savings_amount
        = coalesce(executed_cost_reduction_amount, 0) + executed_cost_avoidance_amount
    )
  );

do $$
declare
  manifest private.two_decimal_money_backup_manifest_20260828%rowtype;
begin
  select * into strict manifest
  from private.two_decimal_money_backup_manifest_20260828;

  if (select count(*) from public.savings_calculations) <> manifest.calculation_count
    or (select count(*) from public.savings_periods) <> manifest.period_count
    or (select count(*) from public.savings_periods where executed_total_savings_amount is not null) <> manifest.executed_period_count
    or (select count(*) from public.realization_periods) <> manifest.realization_period_count then
    raise exception 'Two-decimal backfill changed a protected row count';
  end if;

  if exists (
    select 1 from public.savings_calculations
    where gross_savings_amount <> coalesce(cost_reduction_amount, 0) + coalesce(cost_avoidance_amount, 0)
  ) then
    raise exception 'Two-decimal calculation totals do not reconcile';
  end if;

  if exists (
    select 1 from public.savings_periods
    where total_savings_amount <> coalesce(cost_reduction_amount, 0) + cost_avoidance_amount
      or (executed_total_savings_amount is not null and
        executed_total_savings_amount <> coalesce(executed_cost_reduction_amount, 0) + executed_cost_avoidance_amount)
  ) then
    raise exception 'Two-decimal period totals do not reconcile';
  end if;

  if exists (
    select 1
    from public.savings_calculations calculation
    join lateral (
      select sum(baseline_amount) baseline_amount,
        sum(opening_amount) opening_amount,
        sum(final_amount) final_amount,
        sum(cost_reduction_amount) cost_reduction_amount,
        sum(cost_avoidance_amount) cost_avoidance_amount,
        sum(total_savings_amount) total_savings_amount
      from public.savings_periods period
      where period.savings_calculation_id = calculation.id
    ) totals on true
    where row(
      calculation.baseline_total_amount, calculation.opening_proposal_amount,
      calculation.award_total_amount, calculation.cost_reduction_amount,
      calculation.cost_avoidance_amount, calculation.gross_savings_amount
    ) is distinct from row(
      totals.baseline_amount, totals.opening_amount, totals.final_amount,
      totals.cost_reduction_amount, totals.cost_avoidance_amount,
      totals.total_savings_amount
    )
  ) then
    raise exception 'Two-decimal schedule detail does not match its calculation';
  end if;
end
$$;

comment on constraint chk_savings_periods_estimated_chain on public.savings_periods is
  'Cent-exact estimated row: anchors derive reduction/avoidance and both legs derive total.';
comment on constraint chk_savings_periods_executed_chain on public.savings_periods is
  'Cent-exact executed snapshot: anchors derive reduction/avoidance and both legs derive total.';

commit;
