begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(69);

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
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'organization_settings'
      and column_name = 'support_projects_enabled'
      and is_nullable = 'NO'
      and column_default = 'true'
  ),
  'Support project creation defaults to enabled and cannot be null'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_support_project_setting()'::regprocedure
  ),
  'Support project enforcement runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_support_project_setting()'::regprocedure
  ),
  'Support project enforcement has a fixed search path'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'sourcing_events'
      and t.tgname = 'sourcing_events_enforce_support_project_setting'
      and not t.tgisinternal
  ),
  'sourcing_events has the Support project setting trigger'
);

select ok(
  not has_function_privilege('anon', 'public.enforce_support_project_setting()', 'EXECUTE'),
  'anonymous users cannot execute Support project enforcement directly'
);

select ok(
  not has_function_privilege('authenticated', 'public.enforce_support_project_setting()', 'EXECUTE'),
  'signed-in users cannot execute Support project enforcement directly'
);

select ok(
  has_function_privilege('service_role', 'public.enforce_support_project_setting()', 'EXECUTE'),
  'service role can execute Support project enforcement'
);

select ok(
  to_regprocedure(
    'public.update_workspace_settings(text,text,text,text,text,integer,text,text,boolean,numeric,boolean)'
  ) is not null,
  'workspace settings RPC accepts the Support project control'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.update_workspace_settings(text,text,text,text,text,integer,text,text,boolean,numeric,boolean)',
    'EXECUTE'
  ),
  'signed-in users can invoke the workspace settings RPC'
);

select ok(
  to_regprocedure(
    'public.update_workspace_settings(text,text,text,text,text,integer,text,text,boolean,numeric)'
  ) is not null,
  'the deployed workspace settings RPC signature remains available'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings(text,text,text,text,text,integer,text,text,boolean,numeric)'::regprocedure
  ),
  'the workspace settings compatibility RPC runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings(text,text,text,text,text,integer,text,text,boolean,numeric)'::regprocedure
  ),
  'the workspace settings compatibility RPC has a fixed search path'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.update_workspace_settings(text,text,text,text,text,integer,text,text,boolean,numeric)',
    'EXECUTE'
  ),
  'signed-in deployed clients can invoke the compatibility RPC'
);

insert into public.sourcing_events (
  id,
  organization_id,
  event_name,
  event_type,
  event_status,
  project_type
) values (
  '00000000-0000-4000-8000-000000000016',
  '00000000-0000-4000-8000-000000000001',
  'Existing Support project',
  'Other',
  'Not Started',
  'Support'
);

insert into public.organization_settings (
  organization_id,
  support_projects_enabled
) values (
  '00000000-0000-4000-8000-000000000001',
  false
)
on conflict (organization_id) do update
set support_projects_enabled = excluded.support_projects_enabled;

select lives_ok(
  $$
    update public.sourcing_events
    set event_name = 'Existing Support project updated'
    where id = '00000000-0000-4000-8000-000000000016'
  $$,
  'existing Support projects remain editable when new Support creation is off'
);

select throws_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type
    ) values (
      '00000000-0000-4000-8000-000000000017',
      '00000000-0000-4000-8000-000000000001',
      'Blocked Support project',
      'Other',
      'Not Started',
      'Support'
    )
  $$,
  '23514',
  'Support / Non-Commercial projects are disabled for this workspace',
  'new Support projects are blocked when the setting is off'
);

select lives_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type
    ) values (
      '00000000-0000-4000-8000-000000000018',
      '00000000-0000-4000-8000-000000000001',
      'Allowed Sourcing project',
      'Renewal',
      'Pipeline',
      'Sourcing'
    )
  $$,
  'new Sourcing projects remain allowed when Support project creation is off'
);

select throws_ok(
  $$
    update public.sourcing_events
    set project_type = 'Support'
    where id = '00000000-0000-4000-8000-000000000018'
  $$,
  '23514',
  'Support / Non-Commercial projects are disabled for this workspace',
  'direct conversion to Support is blocked when the setting is off'
);

insert into public.organizations (id, name)
values ('00000000-0000-4000-8000-000000000019', 'No settings workspace');

select lives_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type
    ) values (
      '00000000-0000-4000-8000-000000000020',
      '00000000-0000-4000-8000-000000000019',
      'Default-enabled Support project',
      'Other',
      'Not Started',
      'Support'
    )
  $$,
  'workspaces without a settings row retain the default enabled behavior'
);

delete from public.sourcing_events
where id in (
  '00000000-0000-4000-8000-000000000016',
  '00000000-0000-4000-8000-000000000018',
  '00000000-0000-4000-8000-000000000020'
);

delete from public.organizations
where id = '00000000-0000-4000-8000-000000000019';

update public.organization_settings
set support_projects_enabled = true
where organization_id = '00000000-0000-4000-8000-000000000001';

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'organization_settings'
      and column_name = 'project_descriptions_enabled'
      and is_nullable = 'NO'
      and column_default = 'true'
  ),
  'project descriptions default to enabled and cannot be null'
);

select ok(
  to_regprocedure(
    'public.update_workspace_settings_v2(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean)'
  ) is not null,
  'workspace settings v2 RPC accepts the project description control'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v2(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean)'::regprocedure
  ),
  'workspace settings v2 RPC runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v2(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean)'::regprocedure
  ),
  'workspace settings v2 RPC has a fixed search path'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.update_workspace_settings_v2(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean)',
    'EXECUTE'
  ),
  'signed-in users can invoke the workspace settings v2 RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.update_workspace_settings_v2(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean)',
    'EXECUTE'
  ),
  'anonymous users cannot invoke the workspace settings v2 RPC'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_description_setting()'::regprocedure
  ),
  'project description enforcement runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_description_setting()'::regprocedure
  ),
  'project description enforcement has a fixed search path'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'sourcing_events'
      and t.tgname = 'sourcing_events_enforce_project_description_setting'
      and not t.tgisinternal
  ),
  'sourcing_events has the project description setting trigger'
);

select ok(
  not has_function_privilege('anon', 'public.enforce_project_description_setting()', 'EXECUTE'),
  'anonymous users cannot execute project description enforcement directly'
);

select ok(
  not has_function_privilege('authenticated', 'public.enforce_project_description_setting()', 'EXECUTE'),
  'signed-in users cannot execute project description enforcement directly'
);

select ok(
  has_function_privilege('service_role', 'public.enforce_project_description_setting()', 'EXECUTE'),
  'service role can execute project description enforcement'
);

insert into public.sourcing_events (
  id,
  organization_id,
  event_name,
  event_description,
  event_type,
  event_status,
  project_type
) values (
  '90000000-0000-4000-8000-000000000021',
  '00000000-0000-4000-8000-000000000001',
  'Existing described project',
  'Description to preserve',
  'Renewal',
  'Pipeline',
  'Sourcing'
);

update public.organization_settings
set project_descriptions_enabled = false
where organization_id = '00000000-0000-4000-8000-000000000001';

select lives_ok(
  $$
    update public.sourcing_events
    set event_name = 'Existing described project updated'
    where id = '90000000-0000-4000-8000-000000000021'
  $$,
  'described projects remain otherwise editable when descriptions are off'
);

select throws_ok(
  $$
    update public.sourcing_events
    set event_description = 'Replacement description'
    where id = '90000000-0000-4000-8000-000000000021'
  $$,
  '23514',
  'Project descriptions are disabled for this workspace',
  'existing descriptions cannot be replaced when descriptions are off'
);

select throws_ok(
  $$
    update public.sourcing_events
    set event_description = null
    where id = '90000000-0000-4000-8000-000000000021'
  $$,
  '23514',
  'Project descriptions are disabled for this workspace',
  'existing descriptions cannot be cleared when descriptions are off'
);

select throws_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_description,
      event_type,
      event_status,
      project_type
    ) values (
      '90000000-0000-4000-8000-000000000022',
      '00000000-0000-4000-8000-000000000001',
      'Blocked described project',
      'Blocked description',
      'Renewal',
      'Pipeline',
      'Sourcing'
    )
  $$,
  '23514',
  'Project descriptions are disabled for this workspace',
  'new nonblank descriptions are blocked when descriptions are off'
);

select lives_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_description,
      event_type,
      event_status,
      project_type
    ) values (
      '90000000-0000-4000-8000-000000000023',
      '00000000-0000-4000-8000-000000000001',
      'Allowed project without description',
      null,
      'Renewal',
      'Pipeline',
      'Sourcing'
    )
  $$,
  'new projects without descriptions remain allowed when descriptions are off'
);

select throws_ok(
  $$
    update public.sourcing_events
    set event_description = 'Late description'
    where id = '90000000-0000-4000-8000-000000000023'
  $$,
  '23514',
  'Project descriptions are disabled for this workspace',
  'descriptions cannot be added later when descriptions are off'
);

insert into public.organizations (id, name)
values ('90000000-0000-4000-8000-000000000025', 'No description settings workspace');

select lives_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_description,
      event_type,
      event_status,
      project_type
    ) values (
      '90000000-0000-4000-8000-000000000024',
      '90000000-0000-4000-8000-000000000025',
      'Default-enabled described project',
      'Allowed by the default',
      'Renewal',
      'Pipeline',
      'Sourcing'
    )
  $$,
  'workspaces without a settings row retain default-enabled descriptions'
);

delete from public.sourcing_events
where id in (
  '90000000-0000-4000-8000-000000000021',
  '90000000-0000-4000-8000-000000000023',
  '90000000-0000-4000-8000-000000000024'
);

delete from public.organizations
where id = '90000000-0000-4000-8000-000000000025';

update public.organization_settings
set project_descriptions_enabled = true
where organization_id = '00000000-0000-4000-8000-000000000001';

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
