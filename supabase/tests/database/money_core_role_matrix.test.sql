begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(48);

select is(
  (select count(*)::integer
   from pg_catalog.pg_policies
   where schemaname = 'public'
     and tablename in (
       'sourcing_events', 'event_scope_lines', 'baselines', 'baseline_lines',
       'supplier_offers', 'supplier_offer_lines', 'awards', 'award_lines',
       'savings_calculations', 'savings_calculation_lines',
       'savings_periods', 'realization_periods'
     )
     and policyname in ('org_select', 'org_insert', 'org_update', 'org_delete')),
  48,
  'all twelve money-core tables expose the four-operation RLS matrix'
);

select is(
  (select count(*)::integer
   from pg_catalog.pg_policies
   where schemaname = 'public'
     and tablename in (
       'sourcing_events', 'event_scope_lines', 'baselines', 'baseline_lines',
       'supplier_offers', 'supplier_offer_lines', 'awards', 'award_lines',
       'savings_calculations', 'savings_calculation_lines',
       'savings_periods', 'realization_periods'
     )
     and policyname in ('org_insert', 'org_update')
     and coalesce(with_check, '') ilike '%procurement_user%'
     and coalesce(with_check, '') ilike '%admin%'),
  22,
  'every directly writable insert/update policy is limited to procurement and admin'
);

select ok(
  (select with_check = 'false'
   from pg_catalog.pg_policies
   where schemaname = 'public' and tablename = 'savings_periods'
     and policyname = 'org_insert')
  and (select qual = 'false'
       from pg_catalog.pg_policies
       where schemaname = 'public' and tablename = 'savings_periods'
         and policyname = 'org_delete')
  and (select with_check = 'false'
       from pg_catalog.pg_policies
       where schemaname = 'public' and tablename = 'realization_periods'
         and policyname = 'org_insert'),
  'schedule replacement and realization sync remain RPC-only operations'
);

select ok(
  (select qual ilike '%role = ''admin''%'
          and qual ilike '%finance_validated%'
   from pg_catalog.pg_policies
   where schemaname = 'public' and tablename = 'realization_periods'
     and policyname = 'org_delete'),
  'realization deletion is admin-only and excludes finance-validated rows'
);

select is(
  (select count(*)::integer
   from (values
     ('sourcing_events'), ('event_scope_lines'), ('baselines'),
     ('baseline_lines'), ('supplier_offers'), ('supplier_offer_lines'),
     ('awards'), ('award_lines'), ('savings_calculations'),
     ('savings_calculation_lines'), ('savings_periods'),
     ('realization_periods')
   ) money(table_name)
   where has_table_privilege(
     'authenticated', format('public.%I', table_name), 'SELECT'
   )),
  12,
  'authenticated users retain read access to every money-core table'
);

select is(
  (select count(*)::integer
   from (values
     ('sourcing_events'), ('event_scope_lines'), ('baselines'),
     ('baseline_lines'), ('supplier_offers'), ('supplier_offer_lines'),
     ('awards'), ('award_lines'), ('savings_calculations'),
     ('savings_calculation_lines'), ('realization_periods')
   ) money(table_name)
   where has_table_privilege(
     'authenticated', format('public.%I', table_name), 'DELETE'
   )),
  11,
  'all direct money-core deletes except schedule replacement have an RLS-gated grant'
);

select ok(
  not has_table_privilege('authenticated', 'public.savings_periods', 'INSERT,DELETE')
  and not has_table_privilege('authenticated', 'public.realization_periods', 'INSERT')
  and has_column_privilege('authenticated', 'public.savings_periods', 'final_amount', 'UPDATE')
  and has_column_privilege('authenticated', 'public.realization_periods', 'actual_amount', 'UPDATE'),
  'RPC-owned creation/deletion and ordinary estimated/actual edits have exact privileges'
);

select ok(
  not has_column_privilege('authenticated', 'public.sourcing_events', 'savings_disposition', 'INSERT')
  and not has_column_privilege('authenticated', 'public.sourcing_events', 'savings_disposition_by', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.baselines', 'baseline_approved_by', 'INSERT')
  and not has_column_privilege('authenticated', 'public.baselines', 'baseline_approval_date', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.awards', 'award_approved_by', 'INSERT')
  and not has_column_privilege('authenticated', 'public.awards', 'award_approval_date', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.savings_calculations', 'calculation_status', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.savings_calculations', 'executed_by', 'INSERT')
  and not has_column_privilege('authenticated', 'public.realization_periods', 'finance_validated', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.realization_periods', 'created_by', 'INSERT'),
  'approval, lifecycle, finance, and actor fields are absent from direct grants'
);

select ok(
  has_function_privilege('authenticated', 'public.complete_sourcing_project(uuid,text,text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.sync_realization_periods(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.complete_sourcing_project(uuid,text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.sync_realization_periods(uuid)', 'EXECUTE')
  and (select prosecdef and array_to_string(proconfig, ',') like '%search_path=pg_catalog, public%'
       from pg_catalog.pg_proc
       where oid = 'public.complete_sourcing_project(uuid,text,text)'::regprocedure)
  and (select prosecdef and array_to_string(proconfig, ',') like '%search_path=pg_catalog, public%'
       from pg_catalog.pg_proc
       where oid = 'public.sync_realization_periods(uuid)'::regprocedure),
  'completion and realization sync are authenticated-only definer RPCs with fixed search paths'
);

select is(
  (select count(*)::integer
   from pg_catalog.pg_class index_relation
   join pg_catalog.pg_namespace namespace on namespace.oid = index_relation.relnamespace
   where namespace.nspname = 'public'
     and index_relation.relkind = 'i'
     and index_relation.relname in (
       'idx_event_scope_lines_created_by', 'idx_event_scope_lines_updated_by',
       'idx_baseline_lines_created_by', 'idx_baseline_lines_updated_by',
       'idx_supplier_offer_lines_created_by', 'idx_supplier_offer_lines_updated_by',
       'idx_award_lines_created_by', 'idx_award_lines_updated_by',
       'idx_savings_calculation_lines_created_by',
       'idx_savings_calculation_lines_updated_by'
     )),
  10,
  'every actor FK added in 4A has a supporting index'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  ('c1000000-0000-4000-8000-000000000001', 'matrix-admin@example.test', '{"full_name":"Matrix Admin"}'),
  ('c1000000-0000-4000-8000-000000000002', 'matrix-procurement@example.test', '{"full_name":"Matrix Procurement"}'),
  ('c1000000-0000-4000-8000-000000000003', 'matrix-viewer@example.test', '{"full_name":"Matrix Viewer"}');

update public.profiles set role = 'procurement_user'
where id = 'c1000000-0000-4000-8000-000000000002';
update public.profiles set role = 'viewer'
where id = 'c1000000-0000-4000-8000-000000000003';

insert into public.organization_settings (organization_id, savings_realization_enabled)
select organization_id, true
from public.profiles
where id in (
  'c1000000-0000-4000-8000-000000000001',
  'c1000000-0000-4000-8000-000000000002',
  'c1000000-0000-4000-8000-000000000003'
)
on conflict (organization_id) do update
set savings_realization_enabled = excluded.savings_realization_enabled;

insert into public.sourcing_events (
  id, organization_id, event_name, event_type, event_status, project_type
)
select event_id, profile.organization_id, event_name,
       case
         when project_type = 'Support' then 'Vendor Performance or Service Issue'
         else 'Contract Renewal'
       end,
       case
         when project_type = 'Support' then 'Not Started'
         else 'Pipeline'
       end,
       project_type
from (values
  ('c2000000-0000-4000-8000-000000000001'::uuid, 'c1000000-0000-4000-8000-000000000001'::uuid, 'Admin matrix project', 'Sourcing'),
  ('c2000000-0000-4000-8000-000000000002'::uuid, 'c1000000-0000-4000-8000-000000000002'::uuid, 'Procurement matrix project', 'Sourcing'),
  ('c2000000-0000-4000-8000-000000000003'::uuid, 'c1000000-0000-4000-8000-000000000003'::uuid, 'Viewer matrix project', 'Sourcing'),
  ('c2000000-0000-4000-8000-000000000004'::uuid, 'c1000000-0000-4000-8000-000000000002'::uuid, 'Support matrix project', 'Support'),
  ('c2000000-0000-4000-8000-000000000005'::uuid, 'c1000000-0000-4000-8000-000000000002'::uuid, 'No-savings completion project', 'Sourcing')
) seed(event_id, profile_id, event_name, project_type)
join public.profiles profile on profile.id = seed.profile_id;

insert into public.baselines (
  id, organization_id, event_id, baseline_name, baseline_type,
  baseline_total_amount
)
select baseline_id, profile.organization_id, event_id, baseline_name,
       'Prior Year Actuals', 1000
from (values
  ('c3000000-0000-4000-8000-000000000001'::uuid, 'c1000000-0000-4000-8000-000000000001'::uuid, 'c2000000-0000-4000-8000-000000000001'::uuid, 'Admin baseline'),
  ('c3000000-0000-4000-8000-000000000002'::uuid, 'c1000000-0000-4000-8000-000000000002'::uuid, 'c2000000-0000-4000-8000-000000000002'::uuid, 'Procurement baseline'),
  ('c3000000-0000-4000-8000-000000000003'::uuid, 'c1000000-0000-4000-8000-000000000003'::uuid, 'c2000000-0000-4000-8000-000000000003'::uuid, 'Viewer baseline')
) seed(baseline_id, profile_id, event_id, baseline_name)
join public.profiles profile on profile.id = seed.profile_id;

insert into public.savings_calculations (
  id, organization_id, event_id, calculation_name, savings_type,
  calculation_status, schedule_start_month, schedule_start_year,
  schedule_period_type, schedule_period_count
)
select calculation_id, profile.organization_id, event_id, calculation_name,
       'Cost Reduction', 'estimated', 8, 2026, 'monthly', 1
from (values
  ('c4000000-0000-4000-8000-000000000001'::uuid, 'c1000000-0000-4000-8000-000000000001'::uuid, 'c2000000-0000-4000-8000-000000000001'::uuid, 'Admin executed schedule'),
  ('c4000000-0000-4000-8000-000000000002'::uuid, 'c1000000-0000-4000-8000-000000000002'::uuid, 'c2000000-0000-4000-8000-000000000002'::uuid, 'Procurement executed schedule')
) seed(calculation_id, profile_id, event_id, calculation_name)
join public.profiles profile on profile.id = seed.profile_id;

insert into public.savings_periods (
  id, organization_id, event_id, savings_calculation_id,
  period_number, period_month, period_year, period_months,
  baseline_amount, opening_amount, final_amount,
  cost_reduction_amount, cost_avoidance_amount, total_savings_amount
)
select period_id, profile.organization_id, event_id, calculation_id,
       1, 8, 2026, 2, 1000, 1100, 850, 150, 100, 250
from (values
  ('c5000000-0000-4000-8000-000000000001'::uuid, 'c1000000-0000-4000-8000-000000000001'::uuid, 'c2000000-0000-4000-8000-000000000001'::uuid, 'c4000000-0000-4000-8000-000000000001'::uuid),
  ('c5000000-0000-4000-8000-000000000002'::uuid, 'c1000000-0000-4000-8000-000000000002'::uuid, 'c2000000-0000-4000-8000-000000000002'::uuid, 'c4000000-0000-4000-8000-000000000002'::uuid)
) seed(period_id, profile_id, event_id, calculation_id)
join public.profiles profile on profile.id = seed.profile_id;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000003', true);

select is(
  (select count(*)::integer from public.sourcing_events
   where id = 'c2000000-0000-4000-8000-000000000003'),
  1,
  'a viewer can read their money-core project'
);

select throws_ok(
  $$ insert into public.sourcing_events (organization_id, event_name, project_type)
     values ((select organization_id from public.profiles where id = auth.uid()), 'Viewer insert', 'Sourcing') $$,
  '42501', null,
  'a viewer cannot insert money-core records'
);

select lives_ok(
  $$ update public.sourcing_events set event_name = 'Viewer changed project'
     where id = 'c2000000-0000-4000-8000-000000000003' $$,
  'a viewer update is rejected without leaking row existence'
);
select is(
  (select event_name from public.sourcing_events
   where id = 'c2000000-0000-4000-8000-000000000003'),
  'Viewer matrix project',
  'a viewer cannot change a money-core row'
);

select lives_ok(
  $$ delete from public.baselines where id = 'c3000000-0000-4000-8000-000000000003' $$,
  'a viewer delete is rejected without leaking row existence'
);
select is(
  (select count(*)::integer from public.baselines
   where id = 'c3000000-0000-4000-8000-000000000003'),
  1,
  'a viewer cannot delete a money-core row'
);

select throws_ok(
  $$ select public.sync_realization_periods('c2000000-0000-4000-8000-000000000003') $$,
  'P0001', 'administrator or procurement role required',
  'a viewer cannot synchronize realization periods'
);

select throws_ok(
  $$ select public.complete_sourcing_project(
       'c2000000-0000-4000-8000-000000000003',
       'no_executed_savings', 'Viewer attempted project completion'
     ) $$,
  'P0001', 'administrator or procurement role required',
  'a viewer cannot complete a sourcing project'
);

select set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000002', true);

select lives_ok(
  $$ insert into public.event_scope_lines (
       id, organization_id, event_id, line_number, item_service_name
     ) values (
       'c6000000-0000-4000-8000-000000000002',
       (select organization_id from public.profiles where id = auth.uid()),
       'c2000000-0000-4000-8000-000000000002', 1, 'Procurement line'
     ) $$,
  'procurement can insert ordinary commercial rows'
);
select ok(
  (select created_by = 'c1000000-0000-4000-8000-000000000002'
       and updated_by = 'c1000000-0000-4000-8000-000000000002'
   from public.event_scope_lines
   where id = 'c6000000-0000-4000-8000-000000000002'),
  'procurement inserts are stamped by the server'
);

select lives_ok(
  $$ update public.baselines set baseline_total_amount = 1200
     where id = 'c3000000-0000-4000-8000-000000000002' $$,
  'procurement can update ordinary commercial fields'
);

select lives_ok(
  $$ delete from public.event_scope_lines
     where id = 'c6000000-0000-4000-8000-000000000002' $$,
  'a procurement delete is rejected without leaking row existence'
);
select is(
  (select count(*)::integer from public.event_scope_lines
   where id = 'c6000000-0000-4000-8000-000000000002'),
  1,
  'procurement cannot delete money-core rows'
);

select throws_ok(
  $$ insert into public.realization_periods (
       organization_id, event_id, period_name, period_start_date, period_end_date
     ) values (
       (select organization_id from public.profiles where id = auth.uid()),
       'c2000000-0000-4000-8000-000000000002', 'Forged shell',
       '2026-08-01', '2026-08-31'
     ) $$,
  '42501', null,
  'procurement cannot bypass the realization sync RPC'
);

select lives_ok(
  $$ select public.mark_savings_schedule_executed(
       'c4000000-0000-4000-8000-000000000002', 'Approved procurement execution'
     ) $$,
  'procurement can execute its reviewed schedule'
);

select is(
  public.sync_realization_periods('c2000000-0000-4000-8000-000000000002'),
  1,
  'procurement can atomically synchronize one missing realization shell'
);

select ok(
  (select period_name = 'Aug 2026'
       and period_start_date = '2026-08-01'
       and period_end_date = '2026-09-30'
       and baseline_amount = 1000
       and projected_savings = 250
       and actual_amount is null
       and realized_savings is null
       and leakage_amount is null
       and realization_status = 'Pending'
       and created_by = 'c1000000-0000-4000-8000-000000000002'
       and updated_by = 'c1000000-0000-4000-8000-000000000002'
   from public.realization_periods
   where savings_period_id = 'c5000000-0000-4000-8000-000000000002'),
  'sync derives the exact executed comparator, dates, empty actuals, and actors'
);

select is(
  public.sync_realization_periods('c2000000-0000-4000-8000-000000000002'),
  0,
  'realization sync is idempotent'
);

select throws_ok(
  $$ select public.sync_realization_periods('c2000000-0000-4000-8000-000000000001') $$,
  'P0001', 'sourcing project not found',
  'realization sync refuses cross-workspace project IDs'
);

select throws_ok(
  $$ select public.sync_realization_periods('c2000000-0000-4000-8000-000000000004') $$,
  'P0001', 'sourcing project not found',
  'realization sync refuses support/non-commercial projects'
);

select lives_ok(
  $$ select public.complete_sourcing_project(
       'c2000000-0000-4000-8000-000000000005',
       'no_executed_savings', 'No commercial savings were executed.'
     ) $$,
  'procurement can complete a sourcing project without executed savings'
);
select ok(
  (select event_status = 'Complete'
       and savings_disposition = 'no_executed_savings'
       and savings_disposition_reason = 'No commercial savings were executed.'
       and savings_disposition_by = 'c1000000-0000-4000-8000-000000000002'
       and savings_disposition_at is not null
   from public.sourcing_events
   where id = 'c2000000-0000-4000-8000-000000000005'),
  'completion atomically stamps status, disposition, reason, actor, and time'
);

select throws_ok(
  $$ select public.complete_sourcing_project(
       'c2000000-0000-4000-8000-000000000001',
       'no_executed_savings', 'Cross-workspace completion attempt'
     ) $$,
  'P0001', 'sourcing project not found',
  'project completion refuses cross-workspace IDs'
);

select lives_ok(
  $$ update public.realization_periods
     set actual_amount = 900, realized_savings = 100,
         leakage_amount = 150, realization_status = 'Partially Realized'
     where savings_period_id = 'c5000000-0000-4000-8000-000000000002' $$,
  'procurement can record actual realization results'
);

select lives_ok(
  $$ delete from public.realization_periods
     where savings_period_id = 'c5000000-0000-4000-8000-000000000002' $$,
  'a procurement realization delete is rejected without leaking row existence'
);
select is(
  (select count(*)::integer from public.realization_periods
   where savings_period_id = 'c5000000-0000-4000-8000-000000000002'),
  1,
  'procurement cannot delete realization evidence'
);

select set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ select public.mark_savings_schedule_executed(
       'c4000000-0000-4000-8000-000000000001', 'Approved administrator execution'
     ) $$,
  'an administrator can execute its reviewed schedule'
);
select lives_ok(
  $$ select public.complete_sourcing_project(
       'c2000000-0000-4000-8000-000000000001', 'executed',
       'Administrator completed the executed project.'
     ) $$,
  'an administrator can complete a project with executed savings'
);
select ok(
  (select event_status = 'Complete'
       and savings_disposition = 'executed'
       and savings_disposition_by = 'c1000000-0000-4000-8000-000000000001'
   from public.sourcing_events
   where id = 'c2000000-0000-4000-8000-000000000001'),
  'executed completion preserves the coupled lifecycle state'
);
select is(
  public.sync_realization_periods('c2000000-0000-4000-8000-000000000001'),
  1,
  'an administrator can synchronize realization shells'
);

select lives_ok(
  $$ select public.set_finance_validation(
       (select id from public.realization_periods
        where savings_period_id = 'c5000000-0000-4000-8000-000000000001'),
       true
     ) $$,
  'an administrator can finance-validate a realization row'
);

select lives_ok(
  $$ delete from public.realization_periods
     where savings_period_id = 'c5000000-0000-4000-8000-000000000001' $$,
  'validated realization deletion is refused without leaking row existence'
);
select is(
  (select count(*)::integer from public.realization_periods
   where savings_period_id = 'c5000000-0000-4000-8000-000000000001'),
  1,
  'even an administrator cannot delete finance-validated realization evidence'
);

select lives_ok(
  $$ select public.set_finance_validation(
       (select id from public.realization_periods
        where savings_period_id = 'c5000000-0000-4000-8000-000000000001'),
       false
     ) $$,
  'an administrator can explicitly remove finance validation'
);

select lives_ok(
  $$ delete from public.realization_periods
     where savings_period_id = 'c5000000-0000-4000-8000-000000000001' $$,
  'an administrator can delete an unvalidated realization row'
);
select is(
  (select count(*)::integer from public.realization_periods
   where savings_period_id = 'c5000000-0000-4000-8000-000000000001'),
  0,
  'the administrator delete removes only the unvalidated row'
);

select lives_ok(
  $$ delete from public.baselines
     where id = 'c3000000-0000-4000-8000-000000000001' $$,
  'an administrator can delete an ordinary money-core record'
);
select is(
  (select count(*)::integer from public.baselines
   where id = 'c3000000-0000-4000-8000-000000000001'),
  0,
  'the administrator money-core delete takes effect'
);

reset role;
select * from finish();
rollback;
