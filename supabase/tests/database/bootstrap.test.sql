begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(32);

select is(
  (
    select count(*)::bigint
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
  ),
  21::bigint,
  'all 21 public application tables exist'
);

select is(
  (
    select count(*)::bigint
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and not c.relforcerowsecurity
  ),
  0::bigint,
  'every public application table forces row-level security'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'auth'
      and c.relname = 'users'
      and t.tgname = 'on_auth_user_created'
      and not t.tgisinternal
  ),
  'auth.users has the signup trigger'
);

select ok(
  (select p.prosecdef from pg_catalog.pg_proc p where p.oid = 'public.handle_new_user()'::regprocedure),
  'handle_new_user is security definer'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.handle_new_user()'::regprocedure
  ),
  'handle_new_user has a fixed search path'
);

select ok(
  (select p.prosecdef from pg_catalog.pg_proc p where p.oid = 'public.clone_org_data(uuid,uuid,uuid)'::regprocedure),
  'clone_org_data is security definer'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.clone_org_data(uuid,uuid,uuid)'::regprocedure
  ),
  'clone_org_data has a fixed search path'
);

select ok(
  not has_function_privilege('anon', 'public.clone_org_data(uuid,uuid,uuid)', 'EXECUTE'),
  'anonymous users cannot clone workspaces'
);

select ok(
  not has_function_privilege('authenticated', 'public.clone_org_data(uuid,uuid,uuid)', 'EXECUTE'),
  'signed-in users cannot clone workspaces directly'
);

select ok(
  has_function_privilege('service_role', 'public.clone_org_data(uuid,uuid,uuid)', 'EXECUTE'),
  'service role can execute clone_org_data'
);

select ok(
  not has_function_privilege('anon', 'public.handle_new_user()', 'EXECUTE'),
  'anonymous users cannot execute the signup handler directly'
);

select ok(
  not has_function_privilege('authenticated', 'public.handle_new_user()', 'EXECUTE'),
  'signed-in users cannot execute the signup handler directly'
);

select ok(
  has_function_privilege('service_role', 'public.handle_new_user()', 'EXECUTE'),
  'service role can execute the signup handler'
);

select ok(
  not (select p.prosecdef from pg_catalog.pg_proc p where p.oid = 'public.set_supplier_normalized_name()'::regprocedure),
  'supplier name normalization runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.set_supplier_normalized_name()'::regprocedure
  ),
  'supplier name normalization has a fixed search path'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'suppliers'
      and t.tgname = 'suppliers_normalize_name'
      and not t.tgisinternal
  ),
  'suppliers has the name-normalization trigger'
);

select ok(
  not has_function_privilege('anon', 'public.set_supplier_normalized_name()', 'EXECUTE'),
  'anonymous users cannot execute supplier normalization directly'
);

select ok(
  not has_function_privilege('authenticated', 'public.set_supplier_normalized_name()', 'EXECUTE'),
  'signed-in users cannot execute supplier normalization directly'
);

select ok(
  has_function_privilege('service_role', 'public.set_supplier_normalized_name()', 'EXECUTE'),
  'service role can execute supplier normalization'
);

insert into public.suppliers (id, organization_id, supplier_name)
values (
  '00000000-0000-4000-8000-000000000014',
  '00000000-0000-4000-8000-000000000001',
  '  Normalized-Supplier, LLC  '
);

select is(
  (
    select supplier_normalized_name
    from public.suppliers
    where id = '00000000-0000-4000-8000-000000000014'
  ),
  'normalized supplier llc',
  'supplier names are normalized when the writer omits the normalized value'
);

select throws_ok(
  $$
    insert into public.suppliers (id, organization_id, supplier_name)
    values (
      '00000000-0000-4000-8000-000000000015',
      '00000000-0000-4000-8000-000000000001',
      'NORMALIZED supplier LLC'
    )
  $$,
  '23505',
  'duplicate key value violates unique constraint "uq_suppliers_org_normalized_name"',
  'normalized supplier names cannot be duplicated within one workspace'
);

select ok(
  (
    select bool_and(has_table_privilege('authenticated', format('public.%I', c.relname), 'SELECT'))
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
  ),
  'authenticated role has explicit Data API read grants'
);

select is(
  (select count(*)::bigint from public.organizations where is_demo_template),
  1::bigint,
  'seed creates exactly one frozen demo template'
);

select ok(
  exists (
    select 1
    from public.savings_calculations
    where id = '00000000-0000-4000-8000-000000000051'
      and cost_reduction_amount = 300000
      and cost_avoidance_amount = 600000
      and gross_savings_amount = 900000
      and gross_savings_amount = cost_reduction_amount + cost_avoidance_amount
  ),
  'fictional reference deal preserves the 300k + 600k = 900k chain'
);

insert into auth.users (
  id,
  email,
  raw_user_meta_data
)
values (
  '10000000-0000-4000-8000-000000000001',
  'alex@example.test',
  '{"full_name":"Alex Example"}'
);

select ok(
  exists (
    select 1 from public.profiles
    where id = '10000000-0000-4000-8000-000000000001'
      and role = 'admin'
      and organization_id is not null
  ),
  'first signup receives an admin profile and workspace'
);

select is(
  (
    select count(*)::bigint
    from public.sourcing_events e
    join public.profiles p on p.organization_id = e.organization_id
    where p.id = '10000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'first signup receives a private copy of the fictional project'
);

insert into auth.users (
  id,
  email,
  raw_user_meta_data
)
values (
  '20000000-0000-4000-8000-000000000002',
  'blair@example.test',
  '{"full_name":"Blair Example"}'
);

select ok(
  exists (
    select 1 from public.profiles
    where id = '20000000-0000-4000-8000-000000000002'
      and role = 'admin'
      and organization_id is not null
  ),
  'second signup receives an admin profile and workspace'
);

select isnt(
  (select organization_id from public.profiles where id = '10000000-0000-4000-8000-000000000001'),
  (select organization_id from public.profiles where id = '20000000-0000-4000-8000-000000000002'),
  'different signups receive different workspaces'
);

select is(
  (
    select count(*)::bigint
    from public.suppliers
    where supplier_normalized_name = 'normalized supplier llc'
  ),
  3::bigint,
  'the same normalized supplier name remains valid in different workspaces'
);

set local role anon;
select is(
  (select count(*)::bigint from public.organizations),
  0::bigint,
  'anonymous access sees no workspace rows'
);
reset role;

insert into public.sourcing_events (
  id,
  organization_id,
  event_name,
  event_type,
  event_status,
  project_type
)
select
  '10000000-0000-4000-8000-000000000099',
  organization_id,
  'Alex private project',
  'Renewal',
  'Pipeline',
  'Sourcing'
from public.profiles
where id = '10000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select is(
  (
    select count(*)::bigint
    from public.sourcing_events
    where id = '10000000-0000-4000-8000-000000000099'
  ),
  0::bigint,
  'one workspace cannot read another workspace private project'
);
reset role;

create or replace function public.clone_org_data(p_source uuid, p_target uuid, p_owner uuid)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  raise exception 'intentional clone failure for signup test';
end
$$;

insert into auth.users (
  id,
  email,
  raw_user_meta_data
)
values (
  '30000000-0000-4000-8000-000000000003',
  'casey@example.test',
  '{"full_name":"Casey Example"}'
);

select ok(
  exists (
    select 1 from public.profiles
    where id = '30000000-0000-4000-8000-000000000003'
      and organization_id is not null
  ),
  'a demo-clone failure cannot prevent signup'
);

select * from finish();
rollback;
