begin;

select plan(17);

select has_schema('private', 'the private recovery schema exists');
select has_table('private', 'two_decimal_savings_calculations_20260828', 'the calculation backup exists');
select has_table('private', 'two_decimal_savings_periods_20260828', 'the period backup exists');
select has_table('private', 'two_decimal_money_backup_manifest_20260828', 'the count manifest exists');

select ok(
  not has_schema_privilege('authenticated', 'private', 'USAGE')
  and not has_schema_privilege('anon', 'private', 'USAGE'),
  'browser roles cannot access the recovery schema'
);

select is(
  (select count(*)::integer
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
     and numeric_scale = 2),
  15,
  'all newly governed calculation and schedule money columns are numeric(15,2)'
);

select has_check(
  'public', 'savings_calculations', 'chk_savings_calculations_total_chain',
  'calculation totals have a database equation'
);
select has_check(
  'public', 'savings_periods', 'chk_savings_periods_estimated_chain',
  'estimated schedule rows have a database equation'
);
select has_check(
  'public', 'savings_periods', 'chk_savings_periods_executed_chain',
  'executed schedule rows have a database equation'
);

select ok(
  not exists (
    select 1 from public.savings_calculations
    where gross_savings_amount <> coalesce(cost_reduction_amount, 0) + coalesce(cost_avoidance_amount, 0)
  ),
  'seeded calculation totals reconcile at cent precision'
);

select ok(
  not exists (
    select 1 from public.savings_periods
    where cost_reduction_amount is distinct from case
        when baseline_amount is null then null else baseline_amount - final_amount end
      or cost_avoidance_amount <> case
        when baseline_amount is not null and opening_amount > baseline_amount
          then opening_amount - baseline_amount
        when baseline_amount is null and opening_amount is not null
          then opening_amount - final_amount
        else 0 end
      or total_savings_amount <> coalesce(cost_reduction_amount, 0) + cost_avoidance_amount
  ),
  'seeded estimated rows retain the anchor and leg equations'
);

select ok(
  not exists (
    select 1 from public.savings_periods
    where executed_total_savings_amount is not null
      and (
        executed_cost_reduction_amount is distinct from case
          when executed_baseline_amount is null then null
          else executed_baseline_amount - executed_final_amount end
        or executed_cost_avoidance_amount <> case
          when executed_baseline_amount is not null and executed_opening_amount > executed_baseline_amount
            then executed_opening_amount - executed_baseline_amount
          when executed_baseline_amount is null and executed_opening_amount is not null
            then executed_opening_amount - executed_final_amount
          else 0 end
        or executed_total_savings_amount
          <> coalesce(executed_cost_reduction_amount, 0) + executed_cost_avoidance_amount
      )
  ),
  'seeded executed snapshots retain the anchor and leg equations'
);

select ok(
  not exists (
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
  ),
  'schedule detail sums exactly to every calculation headline'
);

select is(
  (select calculation_count from private.two_decimal_money_backup_manifest_20260828),
  (select count(*) from private.two_decimal_savings_calculations_20260828),
  'the calculation backup count matches its immutable manifest'
);

select is(
  (select period_count from private.two_decimal_money_backup_manifest_20260828),
  (select count(*) from private.two_decimal_savings_periods_20260828),
  'the period backup count matches its immutable manifest'
);

select throws_ok(
  $$ update public.savings_calculations
     set gross_savings_amount = gross_savings_amount + 0.01
     where id = '00000000-0000-4000-8000-000000000051' $$,
  '23514', null,
  'an inconsistent calculation total is rejected'
);

select throws_ok(
  $$ update public.savings_periods
     set baseline_amount = baseline_amount + 0.01
     where id = '00000000-0000-4000-8000-000000000061' $$,
  '23514', null,
  'an independently changed period anchor is rejected'
);

select * from finish();
rollback;
