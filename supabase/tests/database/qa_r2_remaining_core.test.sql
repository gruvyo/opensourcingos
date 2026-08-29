begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(20);

select ok(
  (select is_nullable = 'NO' and column_default like '%Sourcing%'
   from information_schema.columns
   where table_schema = 'public'
     and table_name = 'sourcing_events'
     and column_name = 'project_type'),
  'project type has one structural Sourcing default and cannot be null'
);

select ok(
  (select prosecdef and array_to_string(proconfig, ',') like '%search_path=pg_catalog, public%'
   from pg_catalog.pg_proc where oid = 'public.add_baseline_line(uuid,jsonb)'::regprocedure),
  'the baseline-line add writer is a fixed-search-path definer function'
);

select ok(
  (select prosecdef and array_to_string(proconfig, ',') like '%search_path=pg_catalog, public%'
   from pg_catalog.pg_proc where oid = 'public.delete_baseline_line(uuid)'::regprocedure),
  'the baseline-line delete writer is a fixed-search-path definer function'
);

select ok(
  has_function_privilege('authenticated', 'public.add_baseline_line(uuid,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.delete_baseline_line(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.add_baseline_line(uuid,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.delete_baseline_line(uuid)', 'EXECUTE'),
  'only authenticated callers receive the two narrow baseline-line APIs'
);

select ok(
  not has_table_privilege('authenticated', 'public.baseline_lines', 'INSERT')
  and not has_table_privilege('authenticated', 'public.baseline_lines', 'DELETE'),
  'direct line creation and deletion cannot bypass atomic total maintenance'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  ('e1000000-0000-4000-8000-000000000001', 'remaining-admin@example.test', '{"full_name":"Remaining Admin"}'),
  ('e1000000-0000-4000-8000-000000000002', 'remaining-viewer@example.test', '{"full_name":"Remaining Viewer"}');

update public.profiles set role = 'viewer'
where id = 'e1000000-0000-4000-8000-000000000002';

insert into public.project_choice_options (
  organization_id, choice_type, project_type, label, active_flag
)
select profile.organization_id, seed.choice_type, 'Sourcing', seed.label, true
from public.profiles profile
cross join (values
  ('event_type', 'Contract Renewal'),
  ('event_status', 'Pipeline')
) seed(choice_type, label)
where profile.id in (
  'e1000000-0000-4000-8000-000000000001',
  'e1000000-0000-4000-8000-000000000002'
)
and not exists (
  select 1 from public.project_choice_options existing
  where existing.organization_id = profile.organization_id
    and existing.choice_type = seed.choice_type
    and existing.project_type = 'Sourcing'
    and lower(btrim(existing.label)) = lower(btrim(seed.label))
);

select lives_ok(
  $$ insert into public.sourcing_events (
       id, organization_id, event_name, event_type, event_status
     ) select
       'e2000000-0000-4000-8000-000000000001', organization_id,
       'Defaulted Sourcing project', 'Contract Renewal', 'Pipeline'
     from public.profiles where id = 'e1000000-0000-4000-8000-000000000001' $$,
  'a project that omits project type uses the compatibility default'
);

select is(
  (select project_type from public.sourcing_events
   where id = 'e2000000-0000-4000-8000-000000000001'),
  'Sourcing',
  'the omitted project type is stored as Sourcing'
);

select throws_ok(
  $$ insert into public.sourcing_events (
       organization_id, event_name, event_type, project_type
     ) select organization_id, 'Invalid null project', 'Contract Renewal', null
       from public.profiles where id = 'e1000000-0000-4000-8000-000000000001' $$,
  '23514', 'Project type is not an active workspace choice',
  'an explicit null project type is rejected instead of creating a split population'
);

insert into public.sourcing_events (
  id, organization_id, event_name, event_type, event_status, project_type
)
select
  'e2000000-0000-4000-8000-000000000002', organization_id,
  'Viewer project', 'Contract Renewal', 'Pipeline', 'Sourcing'
from public.profiles where id = 'e1000000-0000-4000-8000-000000000002';

insert into public.baselines (
  id, organization_id, event_id, baseline_name, baseline_type,
  baseline_total_amount, baseline_lock_status
)
select
  'e3000000-0000-4000-8000-000000000001'::uuid, organization_id,
  'e2000000-0000-4000-8000-000000000001'::uuid, 'Atomic lines',
  'Current Contract', 999, 'Draft'
from public.profiles where id = 'e1000000-0000-4000-8000-000000000001'
union all
select
  'e3000000-0000-4000-8000-000000000002'::uuid, organization_id,
  'e2000000-0000-4000-8000-000000000002'::uuid, 'Viewer lines',
  'Current Contract', 777, 'Draft'
from public.profiles where id = 'e1000000-0000-4000-8000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000001', true);

select lives_ok(
  $$ select public.add_baseline_line(
       'e3000000-0000-4000-8000-000000000001',
       '{"baseline_unit_price":25,"baseline_quantity":5,"baseline_extended_amount":125,"baseline_recurring_amount":125,"baseline_one_time_amount":0,"baseline_term_months":12,"annualized_baseline_amount":125,"normalized_quantity":5,"normalized_unit_price":25,"normalized_extended_amount":125}'::jsonb
     ) $$,
  'an administrator can add a baseline line atomically'
);

select is(
  (select baseline_total_amount from public.baselines
   where id = 'e3000000-0000-4000-8000-000000000001'),
  125::numeric,
  'the first line and parent total commit together'
);

select ok(
  (select organization_id = (select organization_id from public.profiles where id = auth.uid())
      and event_id = 'e2000000-0000-4000-8000-000000000001'
      and line_number = 1
      and created_by = auth.uid()
      and updated_by = auth.uid()
   from public.baseline_lines
   where baseline_id = 'e3000000-0000-4000-8000-000000000001'),
  'the writer derives workspace, project, ordering, and actors server-side'
);

select lives_ok(
  $$ select public.add_baseline_line(
       'e3000000-0000-4000-8000-000000000001',
       '{"baseline_unit_price":10,"baseline_quantity":5,"baseline_extended_amount":50,"baseline_recurring_amount":50,"baseline_one_time_amount":0,"baseline_term_months":12,"annualized_baseline_amount":50,"normalized_quantity":5,"normalized_unit_price":10,"normalized_extended_amount":50}'::jsonb
     ) $$,
  'a second line is serialized under the same baseline lock'
);

select ok(
  (select baseline_total_amount = 175 from public.baselines
   where id = 'e3000000-0000-4000-8000-000000000001')
  and (select count(*) = 2 and min(line_number) = 1 and max(line_number) = 2
       from public.baseline_lines where baseline_id = 'e3000000-0000-4000-8000-000000000001'),
  'the second commit publishes the exact line sum and contiguous ordering'
);

select lives_ok(
  $$ select public.delete_baseline_line((
       select id from public.baseline_lines
       where baseline_id = 'e3000000-0000-4000-8000-000000000001'
         and baseline_extended_amount = 125
     )) $$,
  'an administrator can delete a baseline line atomically'
);

select ok(
  (select baseline_total_amount = 50 from public.baselines
   where id = 'e3000000-0000-4000-8000-000000000001')
  and (select count(*) = 1 from public.baseline_lines
       where baseline_id = 'e3000000-0000-4000-8000-000000000001'),
  'line deletion and the reduced parent total commit together'
);

select throws_ok(
  $$ insert into public.baseline_lines (
       organization_id, baseline_id, event_id, line_number
     ) values (
       (select organization_id from public.profiles where id = auth.uid()),
       'e3000000-0000-4000-8000-000000000001',
       'e2000000-0000-4000-8000-000000000001', 99
     ) $$,
  '42501', null,
  'direct line insertion is denied'
);

select throws_ok(
  $$ delete from public.baseline_lines
     where baseline_id = 'e3000000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'direct line deletion is denied'
);

update public.baselines set baseline_lock_status = 'Locked'
where id = 'e3000000-0000-4000-8000-000000000001';

select throws_ok(
  $$ select public.add_baseline_line(
       'e3000000-0000-4000-8000-000000000001', '{}'::jsonb
     ) $$,
  'P0001', 'locked baselines cannot be edited',
  'the atomic writer refuses locked baselines'
);

select throws_ok(
  $$ select public.add_baseline_line(
       'e3000000-0000-4000-8000-000000000002', '{}'::jsonb
     ) $$,
  'P0001', 'baseline not found',
  'a cross-workspace baseline is not addressable'
);

select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$ select public.add_baseline_line(
       'e3000000-0000-4000-8000-000000000002', '{}'::jsonb
     ) $$,
  'P0001', 'administrator or procurement role required',
  'a viewer cannot mutate baseline lines in their own workspace'
);

reset role;
select * from finish();
rollback;
