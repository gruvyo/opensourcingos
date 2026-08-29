begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(311);

select is(
  (select savings_realization_enabled from public.organization_settings where organization_id = '00000000-0000-4000-8000-000000000001'),
  false,
  'Savings Realization is disabled by default'
);

select is(
  (select calculation_status from public.savings_calculations where id = '00000000-0000-4000-8000-000000000051'),
  'executed',
  'the fictional finalized savings record uses the executed lifecycle'
);

select is(
  (select count(*)::bigint from public.savings_periods where savings_calculation_id = '00000000-0000-4000-8000-000000000051'),
  3::bigint,
  'the fictional executed result remains fully scheduled'
);

select is(
  (select sum(executed_total_savings_amount) from public.savings_periods where savings_calculation_id = '00000000-0000-4000-8000-000000000051'),
  900000::numeric,
  'executed schedule periods preserve the fictional 900,000 result'
);

select is(
  (select sum(total_savings_amount) from public.savings_periods where savings_calculation_id = '00000000-0000-4000-8000-000000000051'),
  900000::numeric,
  'the original estimate remains alongside the executed snapshot'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_index i
    join pg_catalog.pg_class c on c.oid = i.indexrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'uq_savings_calculations_event'
      and i.indisunique
      and pg_catalog.pg_get_expr(i.indpred, i.indrelid) ilike '%event_id IS NOT NULL%'
  ),
  'savings calculations enforce one linked record per project'
);

select throws_ok(
  $$
    insert into public.savings_calculations (
      organization_id,
      event_id,
      calculation_name,
      savings_type,
      calculation_status
    )
    select
      organization_id,
      event_id,
      'Duplicate savings record',
      'Cost Reduction',
      'estimated'
    from public.savings_calculations
    where id = '00000000-0000-4000-8000-000000000051'
  $$,
  '23505',
  'duplicate key value violates unique constraint "uq_savings_calculations_event"',
  'a second savings calculation for the same project is rejected'
);

select ok(
  has_function_privilege('authenticated', 'public.mark_savings_schedule_executed(uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mark_savings_schedule_executed(uuid,text)', 'EXECUTE'),
  'only authenticated users may invoke the audited schedule execution function'
);

select is(
  (
    select count(*)::bigint
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
  ),
  27::bigint,
  'all 27 public application tables exist'
);

select is(
  (
    select count(*)::bigint
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'event_scope_lines', 'baseline_lines', 'supplier_offer_lines',
        'award_lines', 'savings_calculation_lines'
      )
      and column_name in ('created_by', 'updated_by')
  ),
  10::bigint,
  'all money-detail tables expose server-owned actor columns'
);

select ok(
  (select count(*) = 12
   from pg_catalog.pg_trigger trigger
   join pg_catalog.pg_class relation on relation.oid = trigger.tgrelid
   join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
   where namespace.nspname = 'public'
     and relation.relname in (
       'sourcing_events', 'event_scope_lines', 'baselines', 'baseline_lines',
       'supplier_offers', 'supplier_offer_lines', 'awards', 'award_lines',
       'savings_calculations', 'savings_calculation_lines',
       'savings_periods', 'realization_periods'
     )
     and trigger.tgfoid = 'public.stamp_money_record_actor()'::regprocedure
     and not trigger.tgisinternal)
  and not (select prosecdef from pg_catalog.pg_proc
           where oid = 'public.stamp_money_record_actor()'::regprocedure)
  and (select array_to_string(proconfig, ',') like '%search_path=pg_catalog, public%'
       from pg_catalog.pg_proc
       where oid = 'public.stamp_money_record_actor()'::regprocedure)
  and not has_function_privilege('anon', 'public.stamp_money_record_actor()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.stamp_money_record_actor()', 'EXECUTE')
  and has_function_privilege('service_role', 'public.stamp_money_record_actor()', 'EXECUTE'),
  'all money tables use the locked-down actor-stamping trigger'
);

select ok(
  to_regclass('public.supplier_contacts') is not null,
  'supplier_contacts exists'
);

select ok(
  to_regclass('public.supplier_notes') is not null,
  'supplier_notes exists'
);

select ok(to_regclass('public.supplier_certifications') is not null, 'supplier_certifications exists');

select ok(to_regclass('public.supplier_performance_reviews') is not null, 'supplier_performance_reviews exists');

select ok(
  exists (select 1 from information_schema.columns where table_schema='public' and table_name='supplier_performance_reviews' and column_name='overall_score' and is_nullable='NO'),
  'supplier performance reviews require an overall score'
);

select ok(
  exists (select 1 from pg_catalog.pg_constraint where conrelid='public.supplier_performance_reviews'::regclass and conname='supplier_performance_reviews_overall_score_check'),
  'supplier performance review overall scores are constrained'
);

select ok(
  to_regclass('public.idx_supplier_performance_reviews_supplier_workspace') is not null,
  'supplier performance review workspace relationship has a covering index'
);

select ok(
  (select pg_get_constraintdef(oid) like '%supplier_performance_review%' from pg_catalog.pg_constraint where conrelid='public.audit_log'::regclass and conname='audit_log_entity_type_check'),
  'workspace audit accepts supplier performance review records'
);

select ok(
  not (select p.prosecdef from pg_catalog.pg_proc p where p.oid='public.stamp_supplier_performance_review_actor()'::regprocedure),
  'supplier-performance-review actor stamping runs with invoker privileges'
);

select ok(
  (select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%' from pg_catalog.pg_proc p where p.oid='public.stamp_supplier_performance_review_actor()'::regprocedure),
  'supplier-performance-review actor stamping has a fixed search path'
);

select ok(
  not has_function_privilege('anon','public.stamp_supplier_performance_review_actor()','EXECUTE')
  and not has_function_privilege('authenticated','public.stamp_supplier_performance_review_actor()','EXECUTE')
  and has_function_privilege('service_role','public.stamp_supplier_performance_review_actor()','EXECUTE'),
  'supplier-performance-review actor stamping is callable only by the trigger owner path'
);

select ok(to_regclass('public.supplier_risks') is not null, 'supplier_risks exists');

select ok(
  exists (select 1 from information_schema.columns where table_schema='public' and table_name='supplier_risks' and column_name='severity' and is_nullable='NO')
  and exists (select 1 from information_schema.columns where table_schema='public' and table_name='supplier_risks' and column_name='risk_status' and is_nullable='NO'),
  'supplier risks require severity and status'
);

select ok(
  exists (select 1 from pg_catalog.pg_constraint where conrelid='public.supplier_risks'::regclass and conname='supplier_risks_severity_check'),
  'supplier risk severity is constrained'
);

select ok(
  exists (select 1 from pg_catalog.pg_constraint where conrelid='public.supplier_risks'::regclass and conname='supplier_risks_status_check'),
  'supplier risk status is constrained'
);

select ok(
  to_regclass('public.idx_supplier_risks_supplier_workspace') is not null,
  'supplier risk workspace relationship has a covering index'
);

select ok(
  (select pg_get_constraintdef(oid) like '%supplier_risk%' from pg_catalog.pg_constraint where conrelid='public.audit_log'::regclass and conname='audit_log_entity_type_check'),
  'workspace audit accepts supplier risk records'
);

select ok(
  not (select p.prosecdef from pg_catalog.pg_proc p where p.oid='public.stamp_supplier_risk_actor()'::regprocedure),
  'supplier-risk actor stamping runs with invoker privileges'
);

select ok(
  (select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%' from pg_catalog.pg_proc p where p.oid='public.stamp_supplier_risk_actor()'::regprocedure),
  'supplier-risk actor stamping has a fixed search path'
);

select ok(
  not has_function_privilege('anon','public.stamp_supplier_risk_actor()','EXECUTE')
  and not has_function_privilege('authenticated','public.stamp_supplier_risk_actor()','EXECUTE')
  and has_function_privilege('service_role','public.stamp_supplier_risk_actor()','EXECUTE'),
  'supplier-risk actor stamping is callable only by the trigger owner path'
);

select ok(
  exists (select 1 from information_schema.columns where table_schema='public' and table_name='supplier_certifications' and column_name='certification_name' and is_nullable='NO'),
  'supplier certifications require a name'
);

select ok(
  exists (select 1 from pg_catalog.pg_constraint where conrelid='public.supplier_certifications'::regclass and conname='supplier_certifications_date_order_check'),
  'supplier certification expiration cannot precede issue date'
);

select ok(
  (select pg_get_constraintdef(oid) like '%supplier_certification%' from pg_catalog.pg_constraint where conrelid='public.audit_log'::regclass and conname='audit_log_entity_type_check'),
  'workspace audit accepts supplier certification records'
);

select ok(
  not (select p.prosecdef from pg_catalog.pg_proc p where p.oid='public.stamp_supplier_certification_actor()'::regprocedure),
  'supplier-certification actor stamping runs with invoker privileges'
);

select ok(
  (select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%' from pg_catalog.pg_proc p where p.oid='public.stamp_supplier_certification_actor()'::regprocedure),
  'supplier-certification actor stamping has a fixed search path'
);

select ok(
  not has_function_privilege('anon','public.stamp_supplier_certification_actor()','EXECUTE')
  and not has_function_privilege('authenticated','public.stamp_supplier_certification_actor()','EXECUTE')
  and has_function_privilege('service_role','public.stamp_supplier_certification_actor()','EXECUTE'),
  'supplier-certification actor stamping is callable only by the trigger owner path'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'supplier_notes'
      and column_name = 'occurred_on' and is_nullable = 'NO'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'supplier_notes'
      and column_name = 'body' and is_nullable = 'NO'
  ),
  'supplier notes require an activity date and body'
);

select ok(
  (select relrowsecurity and relforcerowsecurity from pg_catalog.pg_class where oid = 'public.supplier_notes'::regclass),
  'supplier notes enforce row-level security'
);

select ok(
  has_table_privilege('authenticated', 'public.supplier_notes', 'SELECT')
  and has_table_privilege('authenticated', 'public.supplier_notes', 'INSERT')
  and not has_table_privilege('authenticated', 'public.supplier_notes', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.supplier_notes', 'DELETE'),
  'supplier notes are append only for authenticated users'
);

select ok(
  not (select p.prosecdef from pg_catalog.pg_proc p where p.oid = 'public.stamp_supplier_note_actor()'::regprocedure),
  'supplier-note actor stamping runs with invoker privileges'
);

select ok(
  (select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%' from pg_catalog.pg_proc p where p.oid = 'public.stamp_supplier_note_actor()'::regprocedure),
  'supplier-note actor stamping has a fixed search path'
);

select ok(
  not has_function_privilege('anon', 'public.stamp_supplier_note_actor()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.stamp_supplier_note_actor()', 'EXECUTE')
  and has_function_privilege('service_role', 'public.stamp_supplier_note_actor()', 'EXECUTE'),
  'supplier-note actor stamping is callable only by the trigger owner path'
);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'supplier_contacts'
      and column_name = 'is_primary'
      and is_nullable = 'NO'
      and column_default = 'false'
  ),
  'supplier contacts have a non-null primary designation'
);

select ok(
  (
    select pg_get_constraintdef(oid) like '%supplier_contact%'
    from pg_catalog.pg_constraint
    where conrelid = 'public.audit_log'::regclass
      and conname = 'audit_log_entity_type_check'
  ),
  'workspace audit accepts supplier contact records'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.set_single_primary_supplier_contact()'::regprocedure
  ),
  'primary-contact enforcement runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.set_single_primary_supplier_contact()'::regprocedure
  ),
  'primary-contact enforcement has a fixed search path'
);

select ok(
  not has_function_privilege('anon', 'public.set_single_primary_supplier_contact()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.set_single_primary_supplier_contact()', 'EXECUTE')
  and has_function_privilege('service_role', 'public.set_single_primary_supplier_contact()', 'EXECUTE'),
  'primary-contact enforcement is callable only by the trigger owner path'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.stamp_supplier_contact_actor()'::regprocedure
  ),
  'supplier-contact actor stamping runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.stamp_supplier_contact_actor()'::regprocedure
  ),
  'supplier-contact actor stamping has a fixed search path'
);

select ok(
  not has_function_privilege('anon', 'public.stamp_supplier_contact_actor()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.stamp_supplier_contact_actor()', 'EXECUTE')
  and has_function_privilege('service_role', 'public.stamp_supplier_contact_actor()', 'EXECUTE'),
  'supplier-contact actor stamping is callable only by the trigger owner path'
);

insert into public.supplier_contacts (
  id, organization_id, supplier_id, contact_name, is_primary
) values (
  'c1000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000013',
  'First Contact',
  true
);

insert into public.supplier_contacts (
  id, organization_id, supplier_id, contact_name, is_primary
) values (
  'c1000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000013',
  'Second Contact',
  true
);

select is(
  (
    select contact_name
    from public.supplier_contacts
    where supplier_id = '00000000-0000-4000-8000-000000000013'
      and is_primary
  ),
  'Second Contact',
  'saving a new primary contact atomically demotes the previous primary'
);

select ok(
  exists (
    select 1 from public.audit_log
    where entity_type = 'supplier_contact'
      and entity_id = 'c1000000-0000-4000-8000-000000000002'
      and action = 'insert'
  ),
  'supplier contact changes enter the workspace audit'
);

insert into public.organizations (id, name)
values ('c1000000-0000-4000-8000-000000000003', 'Contact integrity test');

select throws_ok(
  $$
    insert into public.supplier_contacts (
      organization_id, supplier_id, contact_name
    ) values (
      'c1000000-0000-4000-8000-000000000003',
      '00000000-0000-4000-8000-000000000013',
      'Wrong Workspace'
    )
  $$,
  '23503',
  'insert or update on table "supplier_contacts" violates foreign key constraint "supplier_contacts_supplier_workspace_fkey"',
  'a contact cannot attach a supplier from another workspace'
);

delete from public.organizations
where id = 'c1000000-0000-4000-8000-000000000003';

select is(
  (
    select array_agg(category_name order by category_name)
    from public.categories
    where organization_id = '00000000-0000-4000-8000-000000000001'
      and active_flag
  ),
  array[
    'Facilities & Real Estate', 'Laboratory & Scientific Equipment',
    'Logistics & Transportation', 'Marketing & Creative',
    'MRO & Industrial Supplies', 'Packaging', 'Professional Services',
    'Technology & Telecom'
  ]::text[],
  'the demo template has the exact eight category defaults'
);

select is(
  (
    select count(*)::bigint
    from public.categories
    where organization_id = '00000000-0000-4000-8000-000000000001'
      and default_baseline_type is null
  ),
  0::bigint,
  'every default category has an explicit baseline type'
);

select is(
  (
    select array_agg(business_unit_name order by business_unit_name)
    from public.business_units
    where organization_id = '00000000-0000-4000-8000-000000000001'
      and active_flag
  ),
  array['Corporate Services', 'Manufacturing', 'Operations', 'Technology']::text[],
  'the demo template has the exact four Business Unit defaults'
);

select is(
  (
    select count(*)::bigint
    from public.cost_centers
    where organization_id = '00000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'the demo template creates no fictional Cost Center defaults'
);

select ok(
  exists (
    select 1
    from public.sourcing_events as event
    join public.categories as category on category.id = event.category_id
    join public.business_units as unit on unit.id = event.business_unit_id
    where event.id = '00000000-0000-4000-8000-000000000021'
      and category.category_name = 'Technology & Telecom'
      and unit.business_unit_name = 'Technology'
  ),
  'the reference ERP project uses the refreshed Category and Business Unit'
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
  not has_function_privilege(
    'authenticated',
    'public.update_workspace_settings(text,text,text,text,text,integer,text,text,boolean,numeric,boolean)',
    'EXECUTE'
  ),
  'signed-in users cannot invoke the retired Support-era settings RPC'
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
  not has_function_privilege(
    'authenticated',
    'public.update_workspace_settings(text,text,text,text,text,integer,text,text,boolean,numeric)',
    'EXECUTE'
  ),
  'signed-in users cannot invoke the retired compatibility settings RPC'
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
  'General Inquiry',
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
      'General Inquiry',
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
      'Contract Renewal',
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

insert into public.project_choice_options (organization_id, choice_type, project_type, label)
values
  ('00000000-0000-4000-8000-000000000019', 'event_type', 'Support', 'General Inquiry'),
  ('00000000-0000-4000-8000-000000000019', 'event_status', 'Support', 'Not Started');

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
      'General Inquiry',
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

delete from public.project_choice_options
where organization_id = '00000000-0000-4000-8000-000000000019';

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
  not has_function_privilege(
    'authenticated',
    'public.update_workspace_settings_v2(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean)',
    'EXECUTE'
  ),
  'signed-in users cannot invoke the retired workspace settings v2 RPC'
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
  'Contract Renewal',
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
      'Contract Renewal',
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
      'Contract Renewal',
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

insert into public.project_choice_options (organization_id, choice_type, project_type, label)
values
  ('90000000-0000-4000-8000-000000000025', 'event_type', 'Sourcing', 'Contract Renewal'),
  ('90000000-0000-4000-8000-000000000025', 'event_status', 'Sourcing', 'Pipeline');

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
      'Contract Renewal',
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

delete from public.project_choice_options
where organization_id = '90000000-0000-4000-8000-000000000025';

delete from public.organizations
where id = '90000000-0000-4000-8000-000000000025';

update public.organization_settings
set project_descriptions_enabled = true
where organization_id = '00000000-0000-4000-8000-000000000001';

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'organization_settings'
      and column_name = 'project_owners_enabled'
      and is_nullable = 'NO'
      and column_default = 'true'
  ),
  'project owners default to enabled and cannot be null'
);

select ok(
  to_regprocedure(
    'public.update_workspace_settings_v3(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean)'
  ) is not null,
  'workspace settings v3 RPC accepts the project owner control'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v3(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean)'::regprocedure
  ),
  'workspace settings v3 RPC runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v3(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean)'::regprocedure
  ),
  'workspace settings v3 RPC has a fixed search path'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.update_workspace_settings_v3(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean)',
    'EXECUTE'
  ),
  'signed-in users cannot invoke the retired workspace settings v3 RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.update_workspace_settings_v3(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean)',
    'EXECUTE'
  ),
  'anonymous users cannot invoke the workspace settings v3 RPC'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_owner_setting()'::regprocedure
  ),
  'project owner enforcement runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_owner_setting()'::regprocedure
  ),
  'project owner enforcement has a fixed search path'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'sourcing_events'
      and t.tgname = 'sourcing_events_enforce_project_owner_setting'
      and not t.tgisinternal
  ),
  'sourcing_events has the project owner setting trigger'
);

select ok(
  not has_function_privilege('anon', 'public.enforce_project_owner_setting()', 'EXECUTE'),
  'anonymous users cannot execute project owner enforcement directly'
);

select ok(
  not has_function_privilege('authenticated', 'public.enforce_project_owner_setting()', 'EXECUTE'),
  'signed-in users cannot execute project owner enforcement directly'
);

select ok(
  has_function_privilege('service_role', 'public.enforce_project_owner_setting()', 'EXECUTE'),
  'service role can execute project owner enforcement'
);

insert into public.project_choice_options (organization_id, choice_type, project_type, label)
values
  ('00000000-0000-4000-8000-000000000001', 'owner', null, 'Owner to preserve'),
  ('00000000-0000-4000-8000-000000000001', 'owner', null, 'Replacement owner'),
  ('00000000-0000-4000-8000-000000000001', 'owner', null, 'Blocked owner'),
  ('00000000-0000-4000-8000-000000000001', 'owner', null, 'Late owner'),
  ('00000000-0000-4000-8000-000000000001', 'owner', null, 'Owner after re-enabling')
on conflict do nothing;

insert into public.sourcing_events (
  id,
  organization_id,
  event_name,
  event_type,
  event_status,
  project_type,
  buyer_name
) values (
  'a1000000-0000-4000-8000-000000000021',
  '00000000-0000-4000-8000-000000000001',
  'Existing owned project',
  'Contract Renewal',
  'Pipeline',
  'Sourcing',
  'Owner to preserve'
);

update public.organization_settings
set project_owners_enabled = false
where organization_id = '00000000-0000-4000-8000-000000000001';

select lives_ok(
  $$
    update public.sourcing_events
    set event_name = 'Existing owned project updated'
    where id = 'a1000000-0000-4000-8000-000000000021'
  $$,
  'owned projects remain otherwise editable when project owners are off'
);

select is(
  (
    select buyer_name
    from public.sourcing_events
    where id = 'a1000000-0000-4000-8000-000000000021'
  ),
  'Owner to preserve',
  'unrelated project edits preserve the existing owner value'
);

select throws_ok(
  $$
    update public.sourcing_events
    set buyer_name = 'Replacement owner'
    where id = 'a1000000-0000-4000-8000-000000000021'
  $$,
  '23514',
  'Project owners are disabled for this workspace',
  'existing project owners cannot be replaced when project owners are off'
);

select throws_ok(
  $$
    update public.sourcing_events
    set buyer_name = null
    where id = 'a1000000-0000-4000-8000-000000000021'
  $$,
  '23514',
  'Project owners are disabled for this workspace',
  'existing project owners cannot be cleared when project owners are off'
);

select throws_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type,
      buyer_name
    ) values (
      'a1000000-0000-4000-8000-000000000022',
      '00000000-0000-4000-8000-000000000001',
      'Blocked owned project',
      'Contract Renewal',
      'Pipeline',
      'Sourcing',
      'Blocked owner'
    )
  $$,
  '23514',
  'Project owners are disabled for this workspace',
  'new nonblank project owners are blocked when project owners are off'
);

select lives_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type,
      buyer_name
    ) values (
      'a1000000-0000-4000-8000-000000000023',
      '00000000-0000-4000-8000-000000000001',
      'Allowed project without owner',
      'Contract Renewal',
      'Pipeline',
      'Sourcing',
      null
    )
  $$,
  'new projects without owners remain allowed when project owners are off'
);

select throws_ok(
  $$
    update public.sourcing_events
    set buyer_name = 'Late owner'
    where id = 'a1000000-0000-4000-8000-000000000023'
  $$,
  '23514',
  'Project owners are disabled for this workspace',
  'project owners cannot be added later when project owners are off'
);

insert into public.organizations (id, name)
values ('a1000000-0000-4000-8000-000000000025', 'No project owner settings workspace');

insert into public.project_choice_options (organization_id, choice_type, project_type, label)
values
  ('a1000000-0000-4000-8000-000000000025', 'event_type', 'Sourcing', 'Contract Renewal'),
  ('a1000000-0000-4000-8000-000000000025', 'event_status', 'Sourcing', 'Pipeline'),
  ('a1000000-0000-4000-8000-000000000025', 'owner', null, 'Allowed by the default');

select lives_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type,
      buyer_name
    ) values (
      'a1000000-0000-4000-8000-000000000024',
      'a1000000-0000-4000-8000-000000000025',
      'Default-enabled owned project',
      'Contract Renewal',
      'Pipeline',
      'Sourcing',
      'Allowed by the default'
    )
  $$,
  'workspaces without a settings row retain default-enabled project owners'
);

update public.organization_settings
set project_owners_enabled = true
where organization_id = '00000000-0000-4000-8000-000000000001';

select lives_ok(
  $$
    update public.sourcing_events
    set buyer_name = 'Owner after re-enabling'
    where id = 'a1000000-0000-4000-8000-000000000021'
  $$,
  'project owners can be changed again after the setting is re-enabled'
);

delete from public.sourcing_events
where id in (
  'a1000000-0000-4000-8000-000000000021',
  'a1000000-0000-4000-8000-000000000023',
  'a1000000-0000-4000-8000-000000000024'
);

delete from public.project_choice_options
where organization_id = 'a1000000-0000-4000-8000-000000000025';

delete from public.organizations
where id = 'a1000000-0000-4000-8000-000000000025';

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'organization_settings'
      and column_name = 'project_cost_centers_enabled'
      and is_nullable = 'NO'
      and column_default = 'true'
  ),
  'project Cost Centers default to enabled and cannot be null'
);

select ok(
  to_regprocedure(
    'public.update_workspace_settings_v4(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean)'
  ) is not null,
  'workspace settings v4 RPC accepts the project Cost Center control'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v4(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean)'::regprocedure
  ),
  'workspace settings v4 RPC runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v4(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean)'::regprocedure
  ),
  'workspace settings v4 RPC has a fixed search path'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.update_workspace_settings_v4(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean)',
    'EXECUTE'
  ),
  'signed-in users cannot invoke the retired workspace settings v4 RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.update_workspace_settings_v4(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean)',
    'EXECUTE'
  ),
  'anonymous users cannot invoke the workspace settings v4 RPC'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_cost_center_setting()'::regprocedure
  ),
  'project Cost Center enforcement runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_cost_center_setting()'::regprocedure
  ),
  'project Cost Center enforcement has a fixed search path'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'sourcing_events'
      and t.tgname = 'sourcing_events_enforce_project_cost_center_setting'
      and not t.tgisinternal
  ),
  'sourcing_events has the project Cost Center setting trigger'
);

select ok(
  not has_function_privilege('anon', 'public.enforce_project_cost_center_setting()', 'EXECUTE'),
  'anonymous users cannot execute project Cost Center enforcement directly'
);

select ok(
  not has_function_privilege('authenticated', 'public.enforce_project_cost_center_setting()', 'EXECUTE'),
  'signed-in users cannot execute project Cost Center enforcement directly'
);

select ok(
  has_function_privilege('service_role', 'public.enforce_project_cost_center_setting()', 'EXECUTE'),
  'service role can execute project Cost Center enforcement'
);

insert into public.cost_centers (id, organization_id, cost_center_name)
values
  ('b1000000-0000-4000-8000-000000000011', '00000000-0000-4000-8000-000000000001', 'Existing Cost Center'),
  ('b1000000-0000-4000-8000-000000000012', '00000000-0000-4000-8000-000000000001', 'Replacement Cost Center');

insert into public.sourcing_events (
  id,
  organization_id,
  event_name,
  event_type,
  event_status,
  project_type,
  cost_center_id
) values (
  'b1000000-0000-4000-8000-000000000021',
  '00000000-0000-4000-8000-000000000001',
  'Existing classified project',
  'Contract Renewal',
  'Pipeline',
  'Sourcing',
  'b1000000-0000-4000-8000-000000000011'
);

update public.organization_settings
set project_cost_centers_enabled = false
where organization_id = '00000000-0000-4000-8000-000000000001';

select lives_ok(
  $$
    update public.sourcing_events
    set event_name = 'Existing classified project updated'
    where id = 'b1000000-0000-4000-8000-000000000021'
  $$,
  'projects remain otherwise editable when project Cost Centers are off'
);

select is(
  (
    select cost_center_id
    from public.sourcing_events
    where id = 'b1000000-0000-4000-8000-000000000021'
  ),
  'b1000000-0000-4000-8000-000000000011'::uuid,
  'unrelated project edits preserve the existing Cost Center value'
);

select throws_ok(
  $$
    update public.sourcing_events
    set cost_center_id = 'b1000000-0000-4000-8000-000000000012'
    where id = 'b1000000-0000-4000-8000-000000000021'
  $$,
  '23514',
  'Project Cost Centers are disabled for this workspace',
  'existing project Cost Centers cannot be replaced when the setting is off'
);

select throws_ok(
  $$
    update public.sourcing_events
    set cost_center_id = null
    where id = 'b1000000-0000-4000-8000-000000000021'
  $$,
  '23514',
  'Project Cost Centers are disabled for this workspace',
  'existing project Cost Centers cannot be cleared when the setting is off'
);

select throws_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type,
      cost_center_id
    ) values (
      'b1000000-0000-4000-8000-000000000022',
      '00000000-0000-4000-8000-000000000001',
      'Blocked classified project',
      'Contract Renewal',
      'Pipeline',
      'Sourcing',
      'b1000000-0000-4000-8000-000000000011'
    )
  $$,
  '23514',
  'Project Cost Centers are disabled for this workspace',
  'new nonnull project Cost Centers are blocked when the setting is off'
);

select lives_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type,
      cost_center_id
    ) values (
      'b1000000-0000-4000-8000-000000000023',
      '00000000-0000-4000-8000-000000000001',
      'Allowed project without Cost Center',
      'Contract Renewal',
      'Pipeline',
      'Sourcing',
      null
    )
  $$,
  'new projects without Cost Centers remain allowed when the setting is off'
);

select throws_ok(
  $$
    update public.sourcing_events
    set cost_center_id = 'b1000000-0000-4000-8000-000000000012'
    where id = 'b1000000-0000-4000-8000-000000000023'
  $$,
  '23514',
  'Project Cost Centers are disabled for this workspace',
  'project Cost Centers cannot be added later when the setting is off'
);

insert into public.organizations (id, name)
values ('b1000000-0000-4000-8000-000000000025', 'No project Cost Center settings workspace');

insert into public.project_choice_options (organization_id, choice_type, project_type, label)
values
  ('b1000000-0000-4000-8000-000000000025', 'event_type', 'Sourcing', 'Contract Renewal'),
  ('b1000000-0000-4000-8000-000000000025', 'event_status', 'Sourcing', 'Pipeline');

insert into public.cost_centers (id, organization_id, cost_center_name)
values ('b1000000-0000-4000-8000-000000000026', 'b1000000-0000-4000-8000-000000000025', 'Default-enabled Cost Center');

select lives_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type,
      cost_center_id
    ) values (
      'b1000000-0000-4000-8000-000000000024',
      'b1000000-0000-4000-8000-000000000025',
      'Default-enabled classified project',
      'Contract Renewal',
      'Pipeline',
      'Sourcing',
      'b1000000-0000-4000-8000-000000000026'
    )
  $$,
  'workspaces without a settings row retain default-enabled project Cost Centers'
);

update public.organization_settings
set project_cost_centers_enabled = true
where organization_id = '00000000-0000-4000-8000-000000000001';

select lives_ok(
  $$
    update public.sourcing_events
    set cost_center_id = 'b1000000-0000-4000-8000-000000000012'
    where id = 'b1000000-0000-4000-8000-000000000021'
  $$,
  'project Cost Centers can be changed again after the setting is re-enabled'
);

delete from public.sourcing_events
where id in (
  'b1000000-0000-4000-8000-000000000021',
  'b1000000-0000-4000-8000-000000000023',
  'b1000000-0000-4000-8000-000000000024'
);

delete from public.cost_centers
where id in (
  'b1000000-0000-4000-8000-000000000011',
  'b1000000-0000-4000-8000-000000000012',
  'b1000000-0000-4000-8000-000000000026'
);

delete from public.project_choice_options
where organization_id = 'b1000000-0000-4000-8000-000000000025';

delete from public.organizations
where id = 'b1000000-0000-4000-8000-000000000025';

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'organization_settings'
      and column_name = 'project_categories_enabled'
      and is_nullable = 'NO'
      and column_default = 'true'
  ),
  'project Categories default to enabled and cannot be null'
);

select ok(
  to_regprocedure(
    'public.update_workspace_settings_v5(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean)'
  ) is not null,
  'workspace settings v5 RPC accepts the project Category control'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v5(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean)'::regprocedure
  ),
  'workspace settings v5 RPC runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v5(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean)'::regprocedure
  ),
  'workspace settings v5 RPC has a fixed search path'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.update_workspace_settings_v5(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean)',
    'EXECUTE'
  ),
  'signed-in users cannot invoke the retired workspace settings v5 RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.update_workspace_settings_v5(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean)',
    'EXECUTE'
  ),
  'anonymous users cannot invoke the workspace settings v5 RPC'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_category_setting()'::regprocedure
  ),
  'project Category enforcement runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_category_setting()'::regprocedure
  ),
  'project Category enforcement has a fixed search path'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'sourcing_events'
      and t.tgname = 'sourcing_events_enforce_project_category_setting'
      and not t.tgisinternal
  ),
  'sourcing_events has the project Category setting trigger'
);

select ok(
  not has_function_privilege('anon', 'public.enforce_project_category_setting()', 'EXECUTE'),
  'anonymous users cannot execute project Category enforcement directly'
);

select ok(
  not has_function_privilege('authenticated', 'public.enforce_project_category_setting()', 'EXECUTE'),
  'signed-in users cannot execute project Category enforcement directly'
);

select ok(
  has_function_privilege('service_role', 'public.enforce_project_category_setting()', 'EXECUTE'),
  'service role can execute project Category enforcement'
);

insert into public.categories (id, organization_id, category_name)
values
  ('c1000000-0000-4000-8000-000000000011', '00000000-0000-4000-8000-000000000001', 'Existing Project Category'),
  ('c1000000-0000-4000-8000-000000000012', '00000000-0000-4000-8000-000000000001', 'Replacement Project Category');

insert into public.sourcing_events (
  id,
  organization_id,
  event_name,
  event_type,
  event_status,
  project_type,
  category_id
) values (
  'c1000000-0000-4000-8000-000000000021',
  '00000000-0000-4000-8000-000000000001',
  'Existing categorized project',
  'Contract Renewal',
  'Pipeline',
  'Sourcing',
  'c1000000-0000-4000-8000-000000000011'
);

update public.organization_settings
set project_categories_enabled = false
where organization_id = '00000000-0000-4000-8000-000000000001';

select lives_ok(
  $$
    update public.sourcing_events
    set event_name = 'Existing categorized project updated'
    where id = 'c1000000-0000-4000-8000-000000000021'
  $$,
  'projects remain otherwise editable when project Categories are off'
);

select is(
  (
    select category_id
    from public.sourcing_events
    where id = 'c1000000-0000-4000-8000-000000000021'
  ),
  'c1000000-0000-4000-8000-000000000011'::uuid,
  'unrelated project edits preserve the existing Category value'
);

select throws_ok(
  $$
    update public.sourcing_events
    set category_id = 'c1000000-0000-4000-8000-000000000012'
    where id = 'c1000000-0000-4000-8000-000000000021'
  $$,
  '23514',
  'Project Categories are disabled for this workspace',
  'existing project Categories cannot be replaced when the setting is off'
);

select throws_ok(
  $$
    update public.sourcing_events
    set category_id = null
    where id = 'c1000000-0000-4000-8000-000000000021'
  $$,
  '23514',
  'Project Categories are disabled for this workspace',
  'existing project Categories cannot be cleared when the setting is off'
);

select throws_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type,
      category_id
    ) values (
      'c1000000-0000-4000-8000-000000000022',
      '00000000-0000-4000-8000-000000000001',
      'Blocked categorized project',
      'Contract Renewal',
      'Pipeline',
      'Sourcing',
      'c1000000-0000-4000-8000-000000000011'
    )
  $$,
  '23514',
  'Project Categories are disabled for this workspace',
  'new nonnull project Categories are blocked when the setting is off'
);

select lives_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type,
      category_id
    ) values (
      'c1000000-0000-4000-8000-000000000023',
      '00000000-0000-4000-8000-000000000001',
      'Allowed project without Category',
      'Contract Renewal',
      'Pipeline',
      'Sourcing',
      null
    )
  $$,
  'new projects without Categories remain allowed when the setting is off'
);

select throws_ok(
  $$
    update public.sourcing_events
    set category_id = 'c1000000-0000-4000-8000-000000000012'
    where id = 'c1000000-0000-4000-8000-000000000023'
  $$,
  '23514',
  'Project Categories are disabled for this workspace',
  'project Categories cannot be added later when the setting is off'
);

insert into public.organizations (id, name)
values ('c1000000-0000-4000-8000-000000000025', 'No project Category settings workspace');

insert into public.project_choice_options (organization_id, choice_type, project_type, label)
values
  ('c1000000-0000-4000-8000-000000000025', 'event_type', 'Sourcing', 'Contract Renewal'),
  ('c1000000-0000-4000-8000-000000000025', 'event_status', 'Sourcing', 'Pipeline');

insert into public.categories (id, organization_id, category_name)
values ('c1000000-0000-4000-8000-000000000026', 'c1000000-0000-4000-8000-000000000025', 'Default-enabled Project Category');

select lives_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type,
      category_id
    ) values (
      'c1000000-0000-4000-8000-000000000024',
      'c1000000-0000-4000-8000-000000000025',
      'Default-enabled categorized project',
      'Contract Renewal',
      'Pipeline',
      'Sourcing',
      'c1000000-0000-4000-8000-000000000026'
    )
  $$,
  'workspaces without a settings row retain default-enabled project Categories'
);

update public.organization_settings
set project_categories_enabled = true
where organization_id = '00000000-0000-4000-8000-000000000001';

select lives_ok(
  $$
    update public.sourcing_events
    set category_id = 'c1000000-0000-4000-8000-000000000012'
    where id = 'c1000000-0000-4000-8000-000000000021'
  $$,
  'project Categories can be changed again after the setting is re-enabled'
);

delete from public.sourcing_events
where id in (
  'c1000000-0000-4000-8000-000000000021',
  'c1000000-0000-4000-8000-000000000023',
  'c1000000-0000-4000-8000-000000000024'
);

delete from public.categories
where id in (
  'c1000000-0000-4000-8000-000000000011',
  'c1000000-0000-4000-8000-000000000012',
  'c1000000-0000-4000-8000-000000000026'
);

delete from public.project_choice_options
where organization_id = 'c1000000-0000-4000-8000-000000000025';

delete from public.organizations
where id = 'c1000000-0000-4000-8000-000000000025';

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'organization_settings'
      and column_name = 'project_business_units_enabled'
      and is_nullable = 'NO'
      and column_default = 'true'
  ),
  'project Business Units default to enabled and cannot be null'
);

select ok(
  to_regprocedure(
    'public.update_workspace_settings_v6(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean)'
  ) is not null,
  'workspace settings v6 RPC accepts the project Business Unit control'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v6(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean)'::regprocedure
  ),
  'workspace settings v6 RPC runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v6(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean)'::regprocedure
  ),
  'workspace settings v6 RPC has a fixed search path'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.update_workspace_settings_v6(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean)',
    'EXECUTE'
  ),
  'signed-in users cannot invoke the retired workspace settings v6 RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.update_workspace_settings_v6(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean)',
    'EXECUTE'
  ),
  'anonymous users cannot invoke the workspace settings v6 RPC'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_business_unit_setting()'::regprocedure
  ),
  'project Business Unit enforcement runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_business_unit_setting()'::regprocedure
  ),
  'project Business Unit enforcement has a fixed search path'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'sourcing_events'
      and t.tgname = 'sourcing_events_enforce_project_business_unit_setting'
      and not t.tgisinternal
  ),
  'sourcing_events has the project Business Unit setting trigger'
);

select ok(
  not has_function_privilege('anon', 'public.enforce_project_business_unit_setting()', 'EXECUTE'),
  'anonymous users cannot execute project Business Unit enforcement directly'
);

select ok(
  not has_function_privilege('authenticated', 'public.enforce_project_business_unit_setting()', 'EXECUTE'),
  'signed-in users cannot execute project Business Unit enforcement directly'
);

select ok(
  has_function_privilege('service_role', 'public.enforce_project_business_unit_setting()', 'EXECUTE'),
  'service role can execute project Business Unit enforcement'
);

insert into public.business_units (id, organization_id, business_unit_name)
values
  ('d1000000-0000-4000-8000-000000000011', '00000000-0000-4000-8000-000000000001', 'Existing Project Business Unit'),
  ('d1000000-0000-4000-8000-000000000012', '00000000-0000-4000-8000-000000000001', 'Replacement Project Business Unit');

insert into public.sourcing_events (
  id,
  organization_id,
  event_name,
  event_type,
  event_status,
  project_type,
  business_unit_id
) values (
  'd1000000-0000-4000-8000-000000000021',
  '00000000-0000-4000-8000-000000000001',
  'Existing Business Unit project',
  'Contract Renewal',
  'Pipeline',
  'Sourcing',
  'd1000000-0000-4000-8000-000000000011'
);

update public.organization_settings
set project_business_units_enabled = false
where organization_id = '00000000-0000-4000-8000-000000000001';

select lives_ok(
  $$
    update public.sourcing_events
    set event_name = 'Existing Business Unit project updated'
    where id = 'd1000000-0000-4000-8000-000000000021'
  $$,
  'projects remain otherwise editable when project Business Units are off'
);

select is(
  (
    select business_unit_id
    from public.sourcing_events
    where id = 'd1000000-0000-4000-8000-000000000021'
  ),
  'd1000000-0000-4000-8000-000000000011'::uuid,
  'unrelated project edits preserve the existing Business Unit value'
);

select throws_ok(
  $$
    update public.sourcing_events
    set business_unit_id = 'd1000000-0000-4000-8000-000000000012'
    where id = 'd1000000-0000-4000-8000-000000000021'
  $$,
  '23514',
  'Project Business Units are disabled for this workspace',
  'existing project Business Units cannot be replaced when the setting is off'
);

select throws_ok(
  $$
    update public.sourcing_events
    set business_unit_id = null
    where id = 'd1000000-0000-4000-8000-000000000021'
  $$,
  '23514',
  'Project Business Units are disabled for this workspace',
  'existing project Business Units cannot be cleared when the setting is off'
);

select throws_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type,
      business_unit_id
    ) values (
      'd1000000-0000-4000-8000-000000000022',
      '00000000-0000-4000-8000-000000000001',
      'Blocked Business Unit project',
      'Contract Renewal',
      'Pipeline',
      'Sourcing',
      'd1000000-0000-4000-8000-000000000011'
    )
  $$,
  '23514',
  'Project Business Units are disabled for this workspace',
  'new nonnull project Business Units are blocked when the setting is off'
);

select lives_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type,
      business_unit_id
    ) values (
      'd1000000-0000-4000-8000-000000000023',
      '00000000-0000-4000-8000-000000000001',
      'Allowed project without Business Unit',
      'Contract Renewal',
      'Pipeline',
      'Sourcing',
      null
    )
  $$,
  'new projects without Business Units remain allowed when the setting is off'
);

select throws_ok(
  $$
    update public.sourcing_events
    set business_unit_id = 'd1000000-0000-4000-8000-000000000012'
    where id = 'd1000000-0000-4000-8000-000000000023'
  $$,
  '23514',
  'Project Business Units are disabled for this workspace',
  'project Business Units cannot be added later when the setting is off'
);

insert into public.organizations (id, name)
values ('d1000000-0000-4000-8000-000000000025', 'No project Business Unit settings workspace');

insert into public.project_choice_options (organization_id, choice_type, project_type, label)
values
  ('d1000000-0000-4000-8000-000000000025', 'event_type', 'Sourcing', 'Contract Renewal'),
  ('d1000000-0000-4000-8000-000000000025', 'event_status', 'Sourcing', 'Pipeline');

insert into public.business_units (id, organization_id, business_unit_name)
values ('d1000000-0000-4000-8000-000000000026', 'd1000000-0000-4000-8000-000000000025', 'Default-enabled Project Business Unit');

select lives_ok(
  $$
    insert into public.sourcing_events (
      id,
      organization_id,
      event_name,
      event_type,
      event_status,
      project_type,
      business_unit_id
    ) values (
      'd1000000-0000-4000-8000-000000000024',
      'd1000000-0000-4000-8000-000000000025',
      'Default-enabled Business Unit project',
      'Contract Renewal',
      'Pipeline',
      'Sourcing',
      'd1000000-0000-4000-8000-000000000026'
    )
  $$,
  'workspaces without a settings row retain default-enabled project Business Units'
);

update public.organization_settings
set project_business_units_enabled = true
where organization_id = '00000000-0000-4000-8000-000000000001';

select lives_ok(
  $$
    update public.sourcing_events
    set business_unit_id = 'd1000000-0000-4000-8000-000000000012'
    where id = 'd1000000-0000-4000-8000-000000000021'
  $$,
  'project Business Units can be changed again after the setting is re-enabled'
);

delete from public.sourcing_events
where id in (
  'd1000000-0000-4000-8000-000000000021',
  'd1000000-0000-4000-8000-000000000023',
  'd1000000-0000-4000-8000-000000000024'
);

delete from public.business_units
where id in (
  'd1000000-0000-4000-8000-000000000011',
  'd1000000-0000-4000-8000-000000000012',
  'd1000000-0000-4000-8000-000000000026'
);

delete from public.project_choice_options
where organization_id = 'd1000000-0000-4000-8000-000000000025';

delete from public.organizations
where id = 'd1000000-0000-4000-8000-000000000025';

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'organization_settings'
      and column_name = 'project_updates_enabled'
      and is_nullable = 'NO'
      and column_default = 'true'
  ),
  'Project Updates default to enabled and cannot be null'
);

select ok(
  to_regprocedure(
    'public.update_workspace_settings_v7(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'
  ) is not null,
  'workspace settings v7 RPC accepts the Project Updates control'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v7(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'::regprocedure
  ),
  'workspace settings v7 RPC runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v7(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'::regprocedure
  ),
  'workspace settings v7 RPC has a fixed search path'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.update_workspace_settings_v7(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean,boolean)',
    'EXECUTE'
  ),
  'signed-in users cannot invoke the retired workspace settings v7 RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.update_workspace_settings_v7(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean,boolean)',
    'EXECUTE'
  ),
  'anonymous users cannot invoke the workspace settings v7 RPC'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_updates_setting()'::regprocedure
  ),
  'Project Updates enforcement runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_updates_setting()'::regprocedure
  ),
  'Project Updates enforcement has a fixed search path'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'project_updates'
      and t.tgname = 'project_updates_enforce_workspace_setting'
      and not t.tgisinternal
  ),
  'project_updates has the workspace setting trigger'
);

select ok(
  not has_function_privilege('anon', 'public.enforce_project_updates_setting()', 'EXECUTE'),
  'anonymous users cannot execute Project Updates enforcement directly'
);

select ok(
  not has_function_privilege('authenticated', 'public.enforce_project_updates_setting()', 'EXECUTE'),
  'signed-in users cannot execute Project Updates enforcement directly'
);

select ok(
  has_function_privilege('service_role', 'public.enforce_project_updates_setting()', 'EXECUTE'),
  'service role can execute Project Updates enforcement'
);

update public.organization_settings
set project_updates_enabled = false
where organization_id = '00000000-0000-4000-8000-000000000001';

select is(
  (
    select body
    from public.project_updates
    where id = '00000000-0000-4000-8000-000000000022'
  ),
  'Fictional agreement completed and ready for savings tracking.',
  'existing Project Updates remain readable when new updates are disabled'
);

select throws_ok(
  $$
    insert into public.project_updates (
      id, organization_id, event_id, body
    ) values (
      'e2000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000021',
      'Blocked test update'
    )
  $$,
  '23514',
  'Project Updates are disabled for this workspace',
  'new Project Updates are blocked when the setting is off'
);

update public.organization_settings
set project_updates_enabled = true
where organization_id = '00000000-0000-4000-8000-000000000001';

select lives_ok(
  $$
    insert into public.project_updates (
      id, organization_id, event_id, body
    ) values (
      'e2000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000021',
      'Allowed test update'
    )
  $$,
  'new Project Updates can be added again after the setting is re-enabled'
);

delete from public.project_updates
where id = 'e2000000-0000-4000-8000-000000000001';

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'organization_settings'
      and column_name = 'project_incumbent_suppliers_enabled'
      and is_nullable = 'NO'
      and column_default = 'true'
  ),
  'Project Incumbent Supplier defaults to enabled and cannot be null'
);

select ok(
  to_regprocedure(
    'public.update_workspace_settings_v8(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'
  ) is not null,
  'workspace settings v8 RPC accepts the Project Incumbent Supplier control'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v8(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'::regprocedure
  ),
  'workspace settings v8 RPC runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v8(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'::regprocedure
  ),
  'workspace settings v8 RPC has a fixed search path'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.update_workspace_settings_v8(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)',
    'EXECUTE'
  ),
  'signed-in users cannot invoke the retired workspace settings v8 RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.update_workspace_settings_v8(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)',
    'EXECUTE'
  ),
  'anonymous users cannot invoke the workspace settings v8 RPC'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_incumbent_supplier_setting()'::regprocedure
  ),
  'Project Incumbent Supplier enforcement runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_incumbent_supplier_setting()'::regprocedure
  ),
  'Project Incumbent Supplier enforcement has a fixed search path'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'sourcing_events'
      and t.tgname = 'sourcing_events_enforce_incumbent_supplier_setting'
      and not t.tgisinternal
  ),
  'sourcing_events has the Project Incumbent Supplier setting trigger'
);

select ok(
  not has_function_privilege('anon', 'public.enforce_project_incumbent_supplier_setting()', 'EXECUTE'),
  'anonymous users cannot execute Project Incumbent Supplier enforcement directly'
);

select ok(
  not has_function_privilege('authenticated', 'public.enforce_project_incumbent_supplier_setting()', 'EXECUTE'),
  'signed-in users cannot execute Project Incumbent Supplier enforcement directly'
);

select ok(
  has_function_privilege('service_role', 'public.enforce_project_incumbent_supplier_setting()', 'EXECUTE'),
  'service role can execute Project Incumbent Supplier enforcement'
);

insert into public.suppliers (
  id, organization_id, supplier_name, supplier_status
) values (
  'e3000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000001',
  'Incumbent Control Test Supplier',
  'Active'
);

update public.organization_settings
set project_incumbent_suppliers_enabled = false
where organization_id = '00000000-0000-4000-8000-000000000001';

select is(
  (
    select incumbent_supplier_id
    from public.sourcing_events
    where id = '00000000-0000-4000-8000-000000000021'
  ),
  '00000000-0000-4000-8000-000000000013'::uuid,
  'existing incumbent supplier assignments remain readable when the field is disabled'
);

select throws_ok(
  $$
    update public.sourcing_events
    set incumbent_supplier_id = 'e3000000-0000-4000-8000-000000000001'
    where id = '00000000-0000-4000-8000-000000000021'
  $$,
  '23514',
  'Project Incumbent Supplier is disabled for this workspace',
  'incumbent supplier replacements are blocked when the setting is off'
);

select throws_ok(
  $$
    update public.sourcing_events
    set incumbent_supplier_id = null
    where id = '00000000-0000-4000-8000-000000000021'
  $$,
  '23514',
  'Project Incumbent Supplier is disabled for this workspace',
  'incumbent supplier clearing is blocked when the setting is off'
);

select lives_ok(
  $$
    update public.sourcing_events
    set event_description = event_description
    where id = '00000000-0000-4000-8000-000000000021'
  $$,
  'unrelated project edits remain available when Incumbent Supplier is disabled'
);

select throws_ok(
  $$
    insert into public.sourcing_events (
      id, organization_id, event_name, event_type, project_type,
      event_status, currency_code, incumbent_supplier_id
    ) values (
      'e3000000-0000-4000-8000-000000000002',
      '00000000-0000-4000-8000-000000000001',
      'Blocked incumbent test project', 'Contract Renewal', 'Sourcing',
      'Pipeline', 'USD', 'e3000000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  'Project Incumbent Supplier is disabled for this workspace',
  'new incumbent supplier assignments are blocked when the setting is off'
);

select lives_ok(
  $$
    insert into public.sourcing_events (
      id, organization_id, event_name, event_type, project_type,
      event_status, currency_code, incumbent_supplier_id
    ) values (
      'e3000000-0000-4000-8000-000000000003',
      '00000000-0000-4000-8000-000000000001',
      'Allowed project without incumbent', 'Contract Renewal', 'Sourcing',
      'Pipeline', 'USD', null
    )
  $$,
  'projects without an incumbent supplier remain creatable when the setting is off'
);

update public.organization_settings
set project_incumbent_suppliers_enabled = true
where organization_id = '00000000-0000-4000-8000-000000000001';

select lives_ok(
  $$
    update public.sourcing_events
    set incumbent_supplier_id = 'e3000000-0000-4000-8000-000000000001'
    where id = '00000000-0000-4000-8000-000000000021'
  $$,
  'incumbent suppliers can be changed again after the setting is re-enabled'
);

update public.sourcing_events
set incumbent_supplier_id = '00000000-0000-4000-8000-000000000013'
where id = '00000000-0000-4000-8000-000000000021';

delete from public.sourcing_events
where id = 'e3000000-0000-4000-8000-000000000003';

delete from public.suppliers
where id = 'e3000000-0000-4000-8000-000000000001';

select ok(
  (
    select c.relforcerowsecurity
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'project_choice_options'
  ),
  'workspace choices force row-level security'
);

select is(
  (
    select count(*)::bigint
    from public.project_choice_options
    where organization_id = '00000000-0000-4000-8000-000000000001'
      and choice_type in ('event_type', 'event_status')
  ),
  26::bigint,
  'the demo workspace receives all built-in project types and statuses'
);

select is(
  (
    select array_agg(label order by sort_order)
    from public.project_choice_options
    where organization_id = '00000000-0000-4000-8000-000000000001'
      and choice_type = 'event_type'
      and project_type = 'Sourcing'
  ),
  array[
    'Contract Renewal', 'New Purchase', 'Mid-Contract Commercial Review',
    'Demand or Specification Change', 'Supplier or Market Change',
    'Other Sourcing Initiative'
  ]::text[],
  'Sourcing Type defaults describe why the project exists'
);

select is(
  (
    select array_agg(label order by sort_order)
    from public.project_choice_options
    where organization_id = '00000000-0000-4000-8000-000000000001'
      and choice_type = 'event_type'
      and project_type = 'Support'
  ),
  array[
    'Vendor Performance or Service Issue', 'Billing or Payment Issue',
    'Contract Inquiry', 'Operational Request', 'Risk or Compliance Review',
    'General Inquiry'
  ]::text[],
  'Support Type defaults describe why the request exists'
);

select is(
  (
    select array_agg(label order by sort_order)
    from public.project_choice_options
    where organization_id = '00000000-0000-4000-8000-000000000001'
      and choice_type = 'event_status'
      and project_type = 'Sourcing'
  ),
  array[
    'Pipeline', 'Scoping & Strategy', 'In Market', 'Negotiation',
    'Award & Contracting', 'Implementation', 'Complete', 'On Hold', 'Cancelled'
  ]::text[],
  'Sourcing Status defaults use the streamlined workflow'
);

select is(
  (
    select array_agg(label order by sort_order)
    from public.project_choice_options
    where organization_id = '00000000-0000-4000-8000-000000000001'
      and choice_type = 'event_status'
      and project_type = 'Support'
  ),
  array['Not Started', 'In Progress', 'Pending', 'Complete', 'Cancelled']::text[],
  'Support Status defaults use the streamlined workflow'
);

select is(
  (
    select event_type || '|' || event_status
    from public.sourcing_events
    where id = '00000000-0000-4000-8000-000000000021'
  ),
  'Contract Renewal|Award & Contracting',
  'the fictional reference project uses the refreshed beta taxonomy'
);

select ok(
  exists (
    select 1
    from public.audit_log
    where entity_type = 'project_choice_option'
      and after_data ->> 'label' = 'Contract Renewal'
  ),
  'managed project choices use their own audit entity type'
);

select ok(
  exists (select 1 from public.audit_log where entity_type = 'category')
  and exists (select 1 from public.audit_log where entity_type = 'business_unit')
  and exists (select 1 from public.audit_log where entity_type = 'cost_center'),
  'relational workspace choices use accurate audit entity types'
);

select ok(
  (
    select count(*) = 3
    from information_schema.columns
    where table_schema = 'public'
      and table_name in ('categories', 'business_units', 'cost_centers')
      and column_name = 'active_flag'
      and is_nullable = 'NO'
      and column_default = 'true'
  ),
  'Categories, Business Units, and Cost Centers support non-destructive archiving'
);

select ok(
  not (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_choice_options()'::regprocedure
  ),
  'workspace choice enforcement runs with invoker privileges'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.enforce_project_choice_options()'::regprocedure
  ),
  'workspace choice enforcement has a fixed search path'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'sourcing_events'
      and t.tgname = 'zz_sourcing_events_enforce_project_choice_options'
      and not t.tgisinternal
  ),
  'projects have database-level workspace choice enforcement'
);

select ok(
  not has_function_privilege('anon', 'public.enforce_project_choice_options()', 'EXECUTE'),
  'anonymous users cannot execute workspace choice enforcement directly'
);

select ok(
  not has_function_privilege('authenticated', 'public.enforce_project_choice_options()', 'EXECUTE'),
  'signed-in users cannot execute workspace choice enforcement directly'
);

select ok(
  has_function_privilege('service_role', 'public.enforce_project_choice_options()', 'EXECUTE'),
  'service role can execute workspace choice enforcement'
);

insert into public.project_choice_options (
  id, organization_id, choice_type, project_type, label
) values
  ('e1000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', 'event_type', 'Sourcing', 'Custom Project Type'),
  ('e1000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001', 'event_status', 'Sourcing', 'Custom Status');

select lives_ok(
  $$
    insert into public.sourcing_events (
      id, organization_id, event_name, event_type, event_status, project_type
    ) values (
      'e1000000-0000-4000-8000-000000000011',
      '00000000-0000-4000-8000-000000000001',
      'Managed choice project',
      'Custom Project Type',
      'Custom Status',
      'Sourcing'
    )
  $$,
  'custom workspace choices can be used on a project'
);

update public.project_choice_options
set active_flag = false
where id = 'e1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$
    update public.sourcing_events
    set event_name = 'Managed choice project updated'
    where id = 'e1000000-0000-4000-8000-000000000011'
  $$,
  'unrelated edits preserve an archived historical choice'
);

insert into public.sourcing_events (
  id, organization_id, event_name, event_type, event_status, project_type
) values (
  'e1000000-0000-4000-8000-000000000012',
  '00000000-0000-4000-8000-000000000001',
  'Active choice project',
  'Contract Renewal',
  'Pipeline',
  'Sourcing'
);

select throws_ok(
  $$
    update public.sourcing_events
    set event_type = 'Custom Project Type'
    where id = 'e1000000-0000-4000-8000-000000000012'
  $$,
  '23514',
  'Project type is not an active workspace choice',
  'archived project types cannot be selected on another project'
);

update public.project_choice_options
set label = 'Renamed Custom Status'
where id = 'e1000000-0000-4000-8000-000000000002';

select is(
  (
    select event_status
    from public.sourcing_events
    where id = 'e1000000-0000-4000-8000-000000000011'
  ),
  'Renamed Custom Status',
  'renaming a managed text choice updates the projects that use it'
);

insert into public.categories (
  id, organization_id, category_name, active_flag
) values (
  'e1000000-0000-4000-8000-000000000021',
  '00000000-0000-4000-8000-000000000001',
  'Archived Category',
  false
);

select throws_ok(
  $$
    update public.sourcing_events
    set category_id = 'e1000000-0000-4000-8000-000000000021'
    where id = 'e1000000-0000-4000-8000-000000000012'
  $$,
  '23514',
  'Project Category is not an active workspace choice',
  'archived relational choices cannot be newly selected'
);

select throws_ok(
  $$
    insert into public.project_choice_options (
      organization_id, choice_type, project_type, label
    ) values (
      '00000000-0000-4000-8000-000000000001',
      'event_status',
      'Sourcing',
      'renamed custom status'
    )
  $$,
  '23505',
  'duplicate key value violates unique constraint "uq_project_choice_options_org_type_label"',
  'workspace choices are unique without regard to case or surrounding spaces'
);

delete from public.sourcing_events
where id in ('e1000000-0000-4000-8000-000000000011', 'e1000000-0000-4000-8000-000000000012');
delete from public.categories where id = 'e1000000-0000-4000-8000-000000000021';
delete from public.project_choice_options
where id in ('e1000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000002');

insert into public.organizations (id, name)
values ('e1000000-0000-4000-8000-000000000031', 'Single managed choice workspace');
insert into public.project_choice_options (
  id, organization_id, choice_type, project_type, label
) values (
  'e1000000-0000-4000-8000-000000000032',
  'e1000000-0000-4000-8000-000000000031',
  'event_status',
  'Sourcing',
  'Only Status'
);

select throws_ok(
  $$
    update public.project_choice_options
    set active_flag = false
    where id = 'e1000000-0000-4000-8000-000000000032'
  $$,
  '23514',
  'At least one active project choice is required for this project type',
  'the last active type or status cannot be archived'
);

delete from public.project_choice_options
where organization_id = 'e1000000-0000-4000-8000-000000000031';

delete from public.organizations
where id = 'e1000000-0000-4000-8000-000000000031';

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

select is(
  (
    select count(*)::bigint
    from public.project_choice_options choice
    join public.profiles profile on profile.organization_id = choice.organization_id
    where profile.id = '10000000-0000-4000-8000-000000000001'
      and choice.choice_type in ('event_type', 'event_status')
  ),
  26::bigint,
  'first signup receives an isolated copy of the managed project choices'
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

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
insert into public.supplier_contacts (
  id, organization_id, supplier_id, contact_name
)
select
  'c1000000-0000-4000-8000-000000000004',
  profile.organization_id,
  supplier.id,
  'Alex Private Contact'
from public.profiles as profile
join lateral (
  select id from public.suppliers
  where organization_id = profile.organization_id
  order by id
  limit 1
) as supplier on true
where profile.id = '10000000-0000-4000-8000-000000000001';

update public.profiles set role = 'viewer'
where id = '20000000-0000-4000-8000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select is(
  (
    select count(*)::bigint
    from public.supplier_contacts
    where id = 'c1000000-0000-4000-8000-000000000004'
  ),
  0::bigint,
  'one workspace cannot read another workspace supplier contact'
);
reset role;

update public.profiles
set role = 'viewer'
where id = '20000000-0000-4000-8000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$
    insert into public.supplier_contacts (
      organization_id, supplier_id, contact_name
    )
    select profile.organization_id, supplier.id, 'Viewer Contact'
    from public.profiles as profile
    join lateral (
      select id from public.suppliers
      where organization_id = profile.organization_id
      order by id
      limit 1
    ) as supplier on true
    where profile.id = '20000000-0000-4000-8000-000000000002'
  $$,
  '42501',
  'new row violates row-level security policy for table "supplier_contacts"',
  'viewers cannot add supplier contacts'
);
reset role;

update public.profiles
set role = 'procurement_user'
where id = '20000000-0000-4000-8000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$
    insert into public.supplier_contacts (
      id, organization_id, supplier_id, contact_name
    )
    select
      'c1000000-0000-4000-8000-000000000005',
      profile.organization_id,
      supplier.id,
      'Procurement Contact'
    from public.profiles as profile
    join lateral (
      select id from public.suppliers
      where organization_id = profile.organization_id
      order by id
      limit 1
    ) as supplier on true
    where profile.id = '20000000-0000-4000-8000-000000000002'
  $$,
  'procurement users can add supplier contacts'
);

select is(
  (
    select count(*)::bigint
    from public.supplier_contacts
    where id = 'c1000000-0000-4000-8000-000000000005'
  ),
  1::bigint,
  'procurement users can read the contact they added'
);

select is(
  (
    select created_by
    from public.supplier_contacts
    where id = 'c1000000-0000-4000-8000-000000000005'
  ),
  '20000000-0000-4000-8000-000000000002'::uuid,
  'supplier contacts stamp the authenticated author instead of trusting the payload'
);
reset role;

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
insert into public.supplier_notes (
  id, organization_id, supplier_id, occurred_on, body
)
select
  'd1000000-0000-4000-8000-000000000001',
  profile.organization_id,
  supplier.id,
  date '2026-08-08',
  'Private relationship context'
from public.profiles as profile
join lateral (
  select id from public.suppliers
  where organization_id = profile.organization_id
  order by id
  limit 1
) as supplier on true
where profile.id = '10000000-0000-4000-8000-000000000001';

update public.profiles set role = 'viewer'
where id = '20000000-0000-4000-8000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*)::bigint from public.supplier_notes where id = 'd1000000-0000-4000-8000-000000000001'),
  0::bigint,
  'one workspace cannot read another workspace supplier note'
);

select throws_ok(
  $$
    insert into public.supplier_notes (organization_id, supplier_id, occurred_on, body)
    select profile.organization_id, supplier.id, date '2026-08-08', 'Viewer note'
    from public.profiles as profile
    join lateral (
      select id from public.suppliers where organization_id = profile.organization_id order by id limit 1
    ) as supplier on true
    where profile.id = '20000000-0000-4000-8000-000000000002'
  $$,
  '42501',
  'new row violates row-level security policy for table "supplier_notes"',
  'viewers cannot add supplier notes'
);
reset role;

update public.profiles set role = 'procurement_user'
where id = '20000000-0000-4000-8000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$
    insert into public.supplier_notes (id, organization_id, supplier_id, occurred_on, body, created_by)
    select
      'd1000000-0000-4000-8000-000000000002',
      profile.organization_id,
      supplier.id,
      date '2026-08-08',
      'Procurement relationship note',
      '10000000-0000-4000-8000-000000000001'
    from public.profiles as profile
    join lateral (
      select id from public.suppliers where organization_id = profile.organization_id order by id limit 1
    ) as supplier on true
    where profile.id = '20000000-0000-4000-8000-000000000002'
  $$,
  'procurement users can add supplier notes'
);

select is(
  (select count(*)::bigint from public.supplier_notes where id = 'd1000000-0000-4000-8000-000000000002'),
  1::bigint,
  'procurement users can read the supplier note they added'
);

select is(
  (select created_by from public.supplier_notes where id = 'd1000000-0000-4000-8000-000000000002'),
  '20000000-0000-4000-8000-000000000002'::uuid,
  'supplier notes stamp the authenticated author instead of trusting the payload'
);
reset role;

select throws_ok(
  $$
    insert into public.supplier_notes (organization_id, supplier_id, occurred_on, body)
    select
      blair.organization_id,
      supplier.id,
      date '2026-08-08',
      'Cross-workspace note'
    from public.profiles blair
    cross join lateral (
      select id from public.suppliers
      where organization_id = (select organization_id from public.profiles where id = '10000000-0000-4000-8000-000000000001')
      order by id limit 1
    ) supplier
    where blair.id = '20000000-0000-4000-8000-000000000002'
  $$,
  '23503',
  null,
  'supplier notes cannot pair a supplier with another workspace'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
insert into public.supplier_certifications (id, organization_id, supplier_id, certification_name, expires_on)
select 'e1000000-0000-4000-8000-000000000001', profile.organization_id, supplier.id, 'Private Certification', date '2027-08-08'
from public.profiles profile
join lateral (select id from public.suppliers where organization_id=profile.organization_id order by id limit 1) supplier on true
where profile.id='10000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*)::bigint from public.supplier_certifications where id='e1000000-0000-4000-8000-000000000001'),
  0::bigint,
  'one workspace cannot read another workspace supplier certification'
);
reset role;

update public.profiles set role='viewer' where id='20000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$
    insert into public.supplier_certifications (organization_id, supplier_id, certification_name)
    select profile.organization_id, supplier.id, 'Viewer Certification'
    from public.profiles profile
    join lateral (select id from public.suppliers where organization_id=profile.organization_id order by id limit 1) supplier on true
    where profile.id='20000000-0000-4000-8000-000000000002'
  $$,
  '42501',
  'new row violates row-level security policy for table "supplier_certifications"',
  'viewers cannot add supplier certifications'
);
reset role;

update public.profiles set role='procurement_user' where id='20000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$
    insert into public.supplier_certifications (id, organization_id, supplier_id, certification_name, created_by)
    select 'e1000000-0000-4000-8000-000000000002', profile.organization_id, supplier.id, 'Procurement Certification', '10000000-0000-4000-8000-000000000001'
    from public.profiles profile
    join lateral (select id from public.suppliers where organization_id=profile.organization_id order by id limit 1) supplier on true
    where profile.id='20000000-0000-4000-8000-000000000002'
  $$,
  'procurement users can add supplier certifications'
);
select is(
  (select created_by from public.supplier_certifications where id='e1000000-0000-4000-8000-000000000002'),
  '20000000-0000-4000-8000-000000000002'::uuid,
  'supplier certifications stamp the authenticated author instead of trusting the payload'
);
select is(
  (select count(*)::bigint from public.audit_log where entity_type='supplier_certification' and entity_id='e1000000-0000-4000-8000-000000000002'),
  1::bigint,
  'supplier certification changes enter the workspace audit'
);
reset role;

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
insert into public.supplier_performance_reviews (id, organization_id, supplier_id, review_title, review_date, overall_score, summary)
select 'f1000000-0000-4000-8000-000000000001', profile.organization_id, supplier.id, 'Private Review', date '2026-08-08', 4, 'Private performance context'
from public.profiles profile
join lateral (select id from public.suppliers where organization_id=profile.organization_id order by id limit 1) supplier on true
where profile.id='10000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*)::bigint from public.supplier_performance_reviews where id='f1000000-0000-4000-8000-000000000001'),
  0::bigint,
  'one workspace cannot read another workspace supplier performance review'
);
reset role;

update public.profiles set role='viewer' where id='20000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$
    insert into public.supplier_performance_reviews (organization_id, supplier_id, review_title, review_date, overall_score, summary)
    select profile.organization_id, supplier.id, 'Viewer Review', date '2026-08-08', 3, 'Viewer cannot add this'
    from public.profiles profile
    join lateral (select id from public.suppliers where organization_id=profile.organization_id order by id limit 1) supplier on true
    where profile.id='20000000-0000-4000-8000-000000000002'
  $$,
  '42501',
  'new row violates row-level security policy for table "supplier_performance_reviews"',
  'viewers cannot add supplier performance reviews'
);
reset role;

update public.profiles set role='procurement_user' where id='20000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$
    insert into public.supplier_performance_reviews (id, organization_id, supplier_id, review_title, review_date, overall_score, delivery_score, summary, created_by)
    select 'f1000000-0000-4000-8000-000000000002', profile.organization_id, supplier.id, 'Procurement Review', date '2026-08-08', 4, 5, 'Procurement performance context', '10000000-0000-4000-8000-000000000001'
    from public.profiles profile
    join lateral (select id from public.suppliers where organization_id=profile.organization_id order by id limit 1) supplier on true
    where profile.id='20000000-0000-4000-8000-000000000002'
  $$,
  'procurement users can add supplier performance reviews'
);
select is(
  (select created_by from public.supplier_performance_reviews where id='f1000000-0000-4000-8000-000000000002'),
  '20000000-0000-4000-8000-000000000002'::uuid,
  'supplier performance reviews stamp the authenticated author instead of trusting the payload'
);
select is(
  (select count(*)::bigint from public.audit_log where entity_type='supplier_performance_review' and entity_id='f1000000-0000-4000-8000-000000000002'),
  1::bigint,
  'supplier performance review changes enter the workspace audit'
);
reset role;

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
insert into public.supplier_risks (id, organization_id, supplier_id, risk_title, identified_on, severity, risk_status, description)
select '91000000-0000-4000-8000-000000000001', profile.organization_id, supplier.id, 'Private Risk', date '2026-08-08', 'High', 'Open', 'Private risk context'
from public.profiles profile
join lateral (select id from public.suppliers where organization_id=profile.organization_id order by id limit 1) supplier on true
where profile.id='10000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*)::bigint from public.supplier_risks where id='91000000-0000-4000-8000-000000000001'),
  0::bigint,
  'one workspace cannot read another workspace supplier risk'
);
reset role;

update public.profiles set role='viewer' where id='20000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$
    insert into public.supplier_risks (organization_id, supplier_id, risk_title, identified_on, severity, risk_status, description)
    select profile.organization_id, supplier.id, 'Viewer Risk', date '2026-08-08', 'Medium', 'Open', 'Viewer cannot add this'
    from public.profiles profile
    join lateral (select id from public.suppliers where organization_id=profile.organization_id order by id limit 1) supplier on true
    where profile.id='20000000-0000-4000-8000-000000000002'
  $$,
  '42501',
  'new row violates row-level security policy for table "supplier_risks"',
  'viewers cannot add supplier risks'
);
reset role;

update public.profiles set role='procurement_user' where id='20000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$
    insert into public.supplier_risks (id, organization_id, supplier_id, risk_title, identified_on, severity, risk_status, description, created_by)
    select '91000000-0000-4000-8000-000000000002', profile.organization_id, supplier.id, 'Procurement Risk', date '2026-08-08', 'High', 'Monitoring', 'Procurement risk context', '10000000-0000-4000-8000-000000000001'
    from public.profiles profile
    join lateral (select id from public.suppliers where organization_id=profile.organization_id order by id limit 1) supplier on true
    where profile.id='20000000-0000-4000-8000-000000000002'
  $$,
  'procurement users can add supplier risks'
);
select is(
  (select created_by from public.supplier_risks where id='91000000-0000-4000-8000-000000000002'),
  '20000000-0000-4000-8000-000000000002'::uuid,
  'supplier risks stamp the authenticated author instead of trusting the payload'
);
select is(
  (select count(*)::bigint from public.audit_log where entity_type='supplier_risk' and entity_id='91000000-0000-4000-8000-000000000002'),
  1::bigint,
  'supplier risk changes enter the workspace audit'
);
reset role;

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
select throws_ok(
  $$ select count(*) from public.organizations $$,
  '42501',
  'permission denied for table organizations',
  'anonymous access cannot read workspace rows'
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
  'Contract Renewal',
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

select is(
  (
    select count(*)::bigint
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and has_table_privilege(
        'anon',
        c.oid,
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
      )
  ),
  0::bigint,
  'anonymous users have no privileges on public application tables'
);

select is(
  (
    with expected(table_name, privilege_type) as (
      select unnest(array[
        'audit_log', 'award_lines', 'awards', 'baseline_lines', 'baselines',
        'business_units', 'categories', 'cost_centers', 'event_scope_lines',
        'organization_settings', 'organizations', 'profiles',
        'project_choice_options', 'project_updates', 'realization_periods',
        'savings_calculation_lines', 'savings_calculations', 'savings_periods',
        'sourcing_events', 'supplier_certifications', 'supplier_contacts',
        'supplier_notes', 'supplier_offer_lines', 'supplier_offers',
        'supplier_performance_reviews', 'supplier_risks', 'suppliers'
      ]::text[]), 'SELECT'::text
      union all
      select unnest(array[
        'business_units', 'categories',
        'cost_centers', 'project_choice_options',
        'project_updates',
        'supplier_certifications',
        'supplier_contacts', 'supplier_notes',
        'supplier_performance_reviews', 'supplier_risks',
        'suppliers'
      ]::text[]), 'INSERT'::text
      union all
      select unnest(array[
        'business_units', 'categories',
        'cost_centers', 'project_choice_options',
        'supplier_certifications', 'supplier_contacts',
        'supplier_performance_reviews', 'supplier_risks', 'suppliers'
      ]::text[]), 'UPDATE'::text
      union all
      select unnest(array[
        'award_lines', 'awards', 'baselines',
        'event_scope_lines', 'realization_periods',
        'savings_calculation_lines', 'savings_calculations',
        'sourcing_events',
        'supplier_certifications', 'supplier_contacts',
        'supplier_offer_lines', 'supplier_offers',
        'supplier_performance_reviews', 'supplier_risks', 'suppliers'
      ]::text[]), 'DELETE'::text
    ), actual as (
      select table_name::text, privilege_type::text
      from information_schema.role_table_grants
      where table_schema = 'public' and grantee = 'authenticated'
    ), differences as (
      (select * from actual except select * from expected)
      union all
      (select * from expected except select * from actual)
    )
    select count(*)::bigint from differences
  ),
  0::bigint,
  'authenticated table privileges exactly match the reviewed application manifest'
);

select is(
  (
    select count(*)::bigint
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and not has_table_privilege('authenticated', c.oid, 'SELECT')
  ),
  0::bigint,
  'authenticated users retain read access to all application tables'
);

select is(
  (
    select count(*)::bigint
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and has_table_privilege(
        'authenticated', c.oid, 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
      )
  ),
  0::bigint,
  'authenticated users have no schema-management or destructive bulk privileges'
);

select ok(
  not has_table_privilege('authenticated', 'public.audit_log', 'INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'public.organization_settings', 'INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'public.organizations', 'INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'public.profiles', 'INSERT,UPDATE,DELETE'),
  'identity, settings, and audit tables are read-only through direct Data API access'
);

select ok(
  has_table_privilege('authenticated', 'public.project_updates', 'SELECT,INSERT')
  and not has_table_privilege('authenticated', 'public.project_updates', 'UPDATE,DELETE')
  and has_table_privilege('authenticated', 'public.supplier_notes', 'SELECT,INSERT')
  and not has_table_privilege('authenticated', 'public.supplier_notes', 'UPDATE,DELETE'),
  'project updates and supplier notes remain append-only'
);

select is(
  (
    select count(*)::bigint
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and has_function_privilege('anon', p.oid, 'EXECUTE')
  ),
  0::bigint,
  'anonymous users cannot execute public application functions'
);

select is(
  (
    with actual as (
      select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as signature
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and has_function_privilege('authenticated', p.oid, 'EXECUTE')
    ), expected(signature) as (
      values
        ('add_baseline_line(p_baseline_id uuid, p_line jsonb)'),
        ('complete_sourcing_project(p_event_id uuid, p_disposition text, p_reason text)'),
        ('confirm_business_equivalency(p_scope_line_id uuid, p_confirmed boolean)'),
        ('current_org_id()'),
        ('correct_savings_execution(p_calc_id uuid, p_note text, p_calculation jsonb, p_periods jsonb)'),
        ('derive_realization_status(p_projected_reduction numeric, p_projected_avoidance numeric, p_realized_reduction numeric, p_realized_avoidance numeric)'),
        ('delete_baseline_line(p_baseline_line_id uuid)'),
        ('mark_savings_schedule_executed(p_savings_calculation_id uuid, p_execution_note text)'),
        ('replace_savings_schedule(p_savings_calculation_id uuid, p_schedule_start_month integer, p_schedule_start_year integer, p_schedule_period_type text, p_periods jsonb)'),
        ('reverse_savings_execution(p_calc_id uuid, p_note text, p_disposition_action text)'),
        ('select_baseline(p_baseline_id uuid)'),
        ('set_finance_validation(p_realization_period_id uuid, p_validated boolean)'),
        ('set_hard_reduction_override(p_baseline_id uuid, p_enabled boolean, p_reason text)'),
        ('set_offer_role(p_offer_id uuid, p_role text)'),
        ('sync_realization_periods(p_event_id uuid)'),
        ('update_workspace_settings_v9(p_organization_name text, p_full_name text, p_currency_code text, p_locale text, p_timezone text, p_fiscal_year_start_month integer, p_date_format text, p_default_recognition_method text, p_require_baseline boolean, p_hard_reduction_approval_threshold numeric, p_support_projects_enabled boolean, p_project_descriptions_enabled boolean, p_project_owners_enabled boolean, p_project_cost_centers_enabled boolean, p_project_categories_enabled boolean, p_project_business_units_enabled boolean, p_project_updates_enabled boolean, p_project_incumbent_suppliers_enabled boolean, p_savings_realization_enabled boolean)')
    ), differences as (
      (select * from actual except select * from expected)
      union all
      (select * from expected except select * from actual)
    )
    select count(*)::bigint from differences
  ),
  0::bigint,
  'authenticated users can execute exactly the reviewed RPC allowlist'
);

select ok(
  (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v9(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'::regprocedure
  ),
  'the settings RPC uses definer rights instead of direct table grants'
);

select ok(
  (
    select array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
    from pg_catalog.pg_proc p
    where p.oid = 'public.update_workspace_settings_v9(text,text,text,text,text,integer,text,text,boolean,numeric,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'::regprocedure
  ),
  'the definer settings RPC keeps a fixed search path'
);

select ok(
  (select bool_and(p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%')
   from pg_catalog.pg_proc p
   where p.oid in (
     'public.add_baseline_line(uuid,jsonb)'::regprocedure,
     'public.select_baseline(uuid)'::regprocedure,
     'public.complete_sourcing_project(uuid,text,text)'::regprocedure,
     'public.set_offer_role(uuid,text)'::regprocedure,
     'public.replace_savings_schedule(uuid,integer,integer,text,jsonb)'::regprocedure,
     'public.mark_savings_schedule_executed(uuid,text)'::regprocedure,
     'public.correct_savings_execution(uuid,text,jsonb,jsonb)'::regprocedure,
     'public.reverse_savings_execution(uuid,text,text)'::regprocedure,
     'public.set_hard_reduction_override(uuid,boolean,text)'::regprocedure,
     'public.confirm_business_equivalency(uuid,boolean)'::regprocedure,
     'public.set_finance_validation(uuid,boolean)'::regprocedure,
     'public.sync_realization_periods(uuid)'::regprocedure,
     'public.delete_baseline_line(uuid)'::regprocedure
   )),
  'money-writer RPCs use definer rights with a fixed search path'
);

select ok(
  not has_column_privilege('authenticated', 'public.baselines', 'is_selected', 'INSERT')
  and not has_column_privilege('authenticated', 'public.baselines', 'is_selected', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.supplier_offers', 'offer_role', 'INSERT')
  and not has_column_privilege('authenticated', 'public.supplier_offers', 'offer_role', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.sourcing_events', 'awarded_supplier_id', 'INSERT')
  and not has_column_privilege('authenticated', 'public.sourcing_events', 'awarded_supplier_id', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.baselines', 'hard_reduction_override', 'INSERT')
  and not has_column_privilege('authenticated', 'public.baselines', 'hard_reduction_override', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.baselines', 'hard_reduction_override_by', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.event_scope_lines', 'business_equivalency_confirmed', 'INSERT')
  and not has_column_privilege('authenticated', 'public.event_scope_lines', 'business_equivalency_confirmed', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.event_scope_lines', 'business_equivalency_confirmed_by', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.realization_periods', 'finance_validated', 'INSERT')
  and not has_column_privilege('authenticated', 'public.realization_periods', 'finance_validated', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.realization_periods', 'finance_validated_by', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.sourcing_events', 'savings_disposition', 'INSERT')
  and not has_column_privilege('authenticated', 'public.sourcing_events', 'savings_disposition_by', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.baselines', 'baseline_approved_by', 'INSERT')
  and not has_column_privilege('authenticated', 'public.baselines', 'baseline_approval_date', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.awards', 'award_approved_by', 'INSERT')
  and not has_column_privilege('authenticated', 'public.awards', 'award_approval_date', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.savings_calculations', 'calculation_status', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.savings_calculations', 'executed_by', 'INSERT')
  and not has_column_privilege('authenticated', 'public.event_scope_lines', 'created_by', 'INSERT')
  and not has_column_privilege('authenticated', 'public.event_scope_lines', 'updated_by', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.baseline_lines', 'created_by', 'INSERT')
  and not has_column_privilege('authenticated', 'public.supplier_offer_lines', 'updated_by', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.savings_periods', 'INSERT')
  and not has_table_privilege('authenticated', 'public.savings_periods', 'DELETE')
  and not has_table_privilege('authenticated', 'public.baseline_lines', 'INSERT')
  and not has_table_privilege('authenticated', 'public.baseline_lines', 'DELETE')
  and not has_table_privilege('authenticated', 'public.realization_periods', 'INSERT')
  and has_column_privilege('authenticated', 'public.baselines', 'baseline_total_amount', 'UPDATE')
  and has_column_privilege('authenticated', 'public.supplier_offers', 'offer_total_amount', 'UPDATE')
  and has_column_privilege('authenticated', 'public.savings_periods', 'final_amount', 'UPDATE'),
  'protected tuple columns are RPC-only while ordinary money edits remain available'
);

select is(
  (
    select count(*)::bigint
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    cross join (values ('anon'), ('authenticated')) r(role_name)
    where n.nspname = 'public' and c.relkind = 'S'
      and has_sequence_privilege(r.role_name, c.oid, 'USAGE,SELECT,UPDATE')
  ),
  0::bigint,
  'Data API roles have no public sequence privileges'
);

select is(
  (
    select count(*)::bigint
    from pg_catalog.pg_default_acl d
    join pg_catalog.pg_namespace n
      on n.oid = d.defaclnamespace and n.nspname = 'public'
    cross join lateral pg_catalog.aclexplode(d.defaclacl) a
    left join pg_catalog.pg_roles g on g.oid = a.grantee
    where d.defaclrole::regrole::text = 'postgres'
      and coalesce(g.rolname, 'PUBLIC') in ('PUBLIC', 'anon', 'authenticated')
  ),
  0::bigint,
  'future public objects created by application migrations are private until explicitly granted'
);

select is(
  (
    select count(*)::bigint
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and not has_table_privilege('service_role', c.oid, 'SELECT')
  ),
  0::bigint,
  'service-role table access is preserved'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$
    select public.update_workspace_settings_v9(
      'Alex Workspace',
      'Alex Example',
      'USD',
      'en-US',
      'America/Chicago',
      1,
      'MMM D, YYYY',
      'monthly',
      true,
      1000,
      false,
      true,
      true,
      true,
      true,
      true,
      true,
      true,
      false
    )
  $$,
  'the admin settings workflow still works without direct write grants'
);
reset role;

select * from finish();
rollback;
