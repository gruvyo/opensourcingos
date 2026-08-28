begin;

select plan(15);

-- Exercise every actor class against the deterministic template actor.
update public.sourcing_events
set procurement_owner_id = '00000000-0000-4000-8000-000000000002',
    business_owner_id = '00000000-0000-4000-8000-000000000002',
    finance_owner_id = '00000000-0000-4000-8000-000000000002'
where id = '00000000-0000-4000-8000-000000000021';

update public.suppliers
set relationship_owner_id = '00000000-0000-4000-8000-000000000002'
where id = '00000000-0000-4000-8000-000000000013';

update public.baselines
set baseline_approved_by = '00000000-0000-4000-8000-000000000002'
where id = '00000000-0000-4000-8000-000000000031';

insert into auth.users (id, email, raw_user_meta_data)
values (
  '71000000-0000-4000-8000-000000000001',
  'clone-integrity@example.test',
  '{"full_name":"Clone Integrity"}'
);

select ok(
  exists (
    select 1 from public.profiles
    where id = '71000000-0000-4000-8000-000000000001'
      and role = 'admin'
  ),
  'signup creates the target administrator'
);

select is(
  (select count(*)
   from public.organization_settings settings
   join public.profiles profile on profile.organization_id = settings.organization_id
   where profile.id = '71000000-0000-4000-8000-000000000001'),
  1::bigint,
  'signup always creates exactly one settings row'
);

select ok(
  exists (
    select 1
    from public.organization_settings settings
    join public.profiles profile on profile.organization_id = settings.organization_id
    where profile.id = '71000000-0000-4000-8000-000000000001'
      and settings.currency_code = 'USD'
      and settings.locale = 'en-US'
      and settings.timezone = 'America/Chicago'
      and settings.fiscal_year_start_month = 1
      and settings.default_recognition_method = 'monthly'
      and settings.updated_by = profile.id
  ),
  'fresh settings use canonical defaults and the new owner actor'
);

select ok(
  exists (
    select 1
    from public.savings_calculations calculation
    join public.profiles profile on profile.organization_id = calculation.organization_id
    where profile.id = '71000000-0000-4000-8000-000000000001'
      and calculation.calculation_status = 'executed'
      and calculation.executed_at is not null
      and calculation.executed_by = profile.id
  ),
  'an executed clone is attributed to its new workspace owner'
);

select ok(
  exists (
    select 1
    from public.sourcing_events event
    join public.profiles profile on profile.organization_id = event.organization_id
    where profile.id = '71000000-0000-4000-8000-000000000001'
      and event.savings_disposition = 'executed'
      and event.savings_disposition_by = profile.id
  ),
  'the savings disposition decision actor is reassigned'
);

select ok(
  exists (
    select 1
    from public.sourcing_events event
    join public.profiles profile on profile.organization_id = event.organization_id
    where profile.id = '71000000-0000-4000-8000-000000000001'
      and event.procurement_owner_id = profile.id
      and event.business_owner_id = profile.id
      and event.finance_owner_id = profile.id
  ),
  'all project owner roles are reassigned'
);

select ok(
  exists (
    select 1
    from public.suppliers supplier
    join public.profiles profile on profile.organization_id = supplier.organization_id
    where profile.id = '71000000-0000-4000-8000-000000000001'
      and supplier.relationship_owner_id = profile.id
  ),
  'supplier relationship ownership is reassigned'
);

select ok(
  exists (
    select 1
    from public.baselines baseline
    join public.profiles profile on profile.organization_id = baseline.organization_id
    where profile.id = '71000000-0000-4000-8000-000000000001'
      and baseline.baseline_approved_by = profile.id
  ),
  'baseline decision attribution is reassigned'
);

select ok(
  not exists (
    select 1
    from public.sourcing_events event
    join public.profiles profile on profile.organization_id = event.organization_id
    where profile.id = '71000000-0000-4000-8000-000000000001'
      and '00000000-0000-4000-8000-000000000002' in (
        event.created_by, event.updated_by, event.procurement_owner_id,
        event.business_owner_id, event.finance_owner_id,
        event.savings_disposition_by
      )
  ),
  'no project person field retains the template actor'
);

select ok(
  not exists (
    select 1
    from public.savings_calculations calculation
    join public.profiles profile on profile.organization_id = calculation.organization_id
    where profile.id = '71000000-0000-4000-8000-000000000001'
      and (calculation.created_by = '00000000-0000-4000-8000-000000000002'
        or calculation.updated_by = '00000000-0000-4000-8000-000000000002'
        or calculation.executed_by = '00000000-0000-4000-8000-000000000002')
  ),
  'no calculation person field retains the template actor'
);

select ok(
  not exists (
    select 1
    from public.baselines baseline
    join public.profiles profile on profile.organization_id = baseline.organization_id
    where profile.id = '71000000-0000-4000-8000-000000000001'
      and baseline.hard_reduction_override_by is not null
  ),
  'a missing decision actor remains missing instead of being invented'
);

insert into public.organizations (id, name)
values ('71000000-0000-4000-8000-000000000010', 'Non-template source');
insert into public.organizations (id, name)
values ('71000000-0000-4000-8000-000000000011', 'Direct clone target');
set local session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data)
values (
  '71000000-0000-4000-8000-000000000012',
  'direct-clone@example.test',
  '{"full_name":"Direct Clone"}'
);
set local session_replication_role = origin;
insert into public.profiles (id, email, full_name, organization_id, role)
values (
  '71000000-0000-4000-8000-000000000012',
  'direct-clone@example.test', 'Direct Clone',
  '71000000-0000-4000-8000-000000000011', 'admin'
);

select throws_ok(
  $$ select public.clone_org_data(
    '71000000-0000-4000-8000-000000000010',
    '71000000-0000-4000-8000-000000000011',
    '71000000-0000-4000-8000-000000000012'
  ) $$,
  'P0001',
  'demo clone source must be the designated template',
  'clone_org_data rejects a tenant workspace as its source'
);

select throws_ok(
  $$ select public.clone_org_data(
    '00000000-0000-4000-8000-000000000001',
    '71000000-0000-4000-8000-000000000011',
    '71000000-0000-4000-8000-000000000001'
  ) $$,
  'P0001',
  'demo clone owner must belong to the non-template target',
  'clone_org_data rejects an owner outside the target workspace'
);

alter table public.categories
  add column qa_unclassified_actor uuid references public.profiles(id);

select throws_ok(
  $$ select public.clone_org_data(
    '00000000-0000-4000-8000-000000000001',
    '71000000-0000-4000-8000-000000000011',
    '71000000-0000-4000-8000-000000000012'
  ) $$,
  'P0001',
  'unclassified profile reference in demo clone: categories.qa_unclassified_actor',
  'an unknown future person column fails loudly'
);

select ok(
  not has_function_privilege('authenticated', 'public.clone_org_data(uuid,uuid,uuid)', 'EXECUTE')
    and has_function_privilege('service_role', 'public.clone_org_data(uuid,uuid,uuid)', 'EXECUTE'),
  'only the service role can invoke the clone function'
);

select * from finish();
rollback;
