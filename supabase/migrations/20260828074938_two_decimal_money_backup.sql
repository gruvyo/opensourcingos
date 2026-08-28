begin;

-- Modification 6A: the Free-plan production project has no user-accessible
-- scheduled restore point. Preserve a complete, API-inaccessible logical
-- snapshot before the first money-row backfill. A reviewed restore migration
-- can copy these rows back by primary key if the cent allocation is reversed.
create schema if not exists private authorization postgres;
revoke all on schema private from public, anon, authenticated;

create table private.two_decimal_savings_calculations_20260828
as table public.savings_calculations with no data;

create table private.two_decimal_savings_periods_20260828
as table public.savings_periods with no data;

insert into private.two_decimal_savings_calculations_20260828
select * from public.savings_calculations;

insert into private.two_decimal_savings_periods_20260828
select * from public.savings_periods;

revoke all on private.two_decimal_savings_calculations_20260828
  from public, anon, authenticated;
revoke all on private.two_decimal_savings_periods_20260828
  from public, anon, authenticated;

create table private.two_decimal_money_backup_manifest_20260828 (
  singleton boolean primary key default true check (singleton),
  backed_up_at timestamptz not null default transaction_timestamp(),
  calculation_count bigint not null,
  estimated_calculation_count bigint not null,
  executed_calculation_count bigint not null,
  period_count bigint not null,
  executed_period_count bigint not null,
  realization_period_count bigint not null,
  calculation_subcent_count bigint not null,
  estimated_period_subcent_count bigint not null,
  executed_period_subcent_count bigint not null
);

revoke all on private.two_decimal_money_backup_manifest_20260828
  from public, anon, authenticated;

insert into private.two_decimal_money_backup_manifest_20260828 (
  calculation_count,
  estimated_calculation_count,
  executed_calculation_count,
  period_count,
  executed_period_count,
  realization_period_count,
  calculation_subcent_count,
  estimated_period_subcent_count,
  executed_period_subcent_count
)
select
  (select count(*) from public.savings_calculations),
  (select count(*) from public.savings_calculations where calculation_status = 'estimated'),
  (select count(*) from public.savings_calculations where calculation_status = 'executed'),
  (select count(*) from public.savings_periods),
  (select count(*) from public.savings_periods where executed_total_savings_amount is not null),
  (select count(*) from public.realization_periods),
  (select count(*) from public.savings_calculations where
    (cost_reduction_amount is not null and cost_reduction_amount <> round(cost_reduction_amount, 2))
    or (cost_avoidance_amount is not null and cost_avoidance_amount <> round(cost_avoidance_amount, 2))
    or (opening_proposal_amount is not null and opening_proposal_amount <> round(opening_proposal_amount, 2))
  ),
  (select count(*) from public.savings_periods where
    (baseline_amount is not null and baseline_amount <> round(baseline_amount, 2))
    or (opening_amount is not null and opening_amount <> round(opening_amount, 2))
    or final_amount <> round(final_amount, 2)
    or (cost_reduction_amount is not null and cost_reduction_amount <> round(cost_reduction_amount, 2))
    or cost_avoidance_amount <> round(cost_avoidance_amount, 2)
    or total_savings_amount <> round(total_savings_amount, 2)
  ),
  (select count(*) from public.savings_periods where executed_total_savings_amount is not null and (
    (executed_baseline_amount is not null and executed_baseline_amount <> round(executed_baseline_amount, 2))
    or (executed_opening_amount is not null and executed_opening_amount <> round(executed_opening_amount, 2))
    or executed_final_amount <> round(executed_final_amount, 2)
    or (executed_cost_reduction_amount is not null and executed_cost_reduction_amount <> round(executed_cost_reduction_amount, 2))
    or executed_cost_avoidance_amount <> round(executed_cost_avoidance_amount, 2)
    or executed_total_savings_amount <> round(executed_total_savings_amount, 2)
  ));

comment on table private.two_decimal_savings_calculations_20260828 is
  'Pre-Modification-6 logical backup. Not exposed through the Data API.';
comment on table private.two_decimal_savings_periods_20260828 is
  'Pre-Modification-6 logical backup. Not exposed through the Data API.';
comment on table private.two_decimal_money_backup_manifest_20260828 is
  'Pre-Modification-6 production counts used as hard backfill assertions.';

commit;
