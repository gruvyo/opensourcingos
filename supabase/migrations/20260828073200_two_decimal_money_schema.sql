begin;

-- Modification 6C: after the cent backfill commits and its audit-trigger
-- events are complete, make exact currency precision a permanent schema rule.
set local lock_timeout = '10s';
set local statement_timeout = '120s';

lock table public.savings_calculations, public.savings_periods
  in share row exclusive mode;

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
  governed_column_count integer;
begin
  select * into strict manifest
  from private.two_decimal_money_backup_manifest_20260828;

  if (select count(*) from public.savings_calculations) <> manifest.calculation_count
    or (select count(*) from public.savings_periods) <> manifest.period_count
    or (select count(*) from public.savings_periods where executed_total_savings_amount is not null) <> manifest.executed_period_count
    or (select count(*) from public.realization_periods) <> manifest.realization_period_count then
    raise exception 'Two-decimal schema boundary changed a protected row count';
  end if;

  select count(*) into governed_column_count
  from information_schema.columns
  where table_schema = 'public'
    and (
      (table_name = 'savings_calculations' and column_name in (
        'cost_reduction_amount', 'cost_avoidance_amount', 'opening_proposal_amount'
      ))
      or (table_name = 'savings_periods' and column_name in (
        'baseline_amount', 'opening_amount', 'final_amount',
        'cost_reduction_amount', 'cost_avoidance_amount', 'total_savings_amount',
        'executed_baseline_amount', 'executed_opening_amount', 'executed_final_amount',
        'executed_cost_reduction_amount', 'executed_cost_avoidance_amount',
        'executed_total_savings_amount'
      ))
    )
    and numeric_precision = 15
    and numeric_scale = 2;

  if governed_column_count <> 15 then
    raise exception 'Not all governed money columns are numeric(15,2)';
  end if;
end
$$;

comment on constraint chk_savings_periods_estimated_chain on public.savings_periods is
  'Cent-exact estimated row: anchors derive reduction/avoidance and both legs derive total.';
comment on constraint chk_savings_periods_executed_chain on public.savings_periods is
  'Cent-exact executed snapshot: anchors derive reduction/avoidance and both legs derive total.';

commit;
