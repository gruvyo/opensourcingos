begin;

-- Modification 7: a workspace must never inherit template identities. Give
-- existing rowless workspaces the same canonical settings defaults used by a
-- new signup. The owner is attribution only; every business setting comes
-- from the table's reviewed defaults rather than from the demo template.
insert into public.organization_settings (organization_id, updated_by)
select organization.id, owner.id
from public.organizations organization
left join lateral (
  select profile.id
  from public.profiles profile
  where profile.organization_id = organization.id
  order by (profile.role = 'admin') desc, profile.created_at, profile.id
  limit 1
) owner on true
where not exists (
  select 1
  from public.organization_settings settings
  where settings.organization_id = organization.id
);

create or replace function public.clone_org_data(p_source uuid, p_target uuid, p_owner uuid)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $_$
declare
  v_tables text[] := array[
    'categories', 'business_units', 'cost_centers', 'suppliers',
    'project_choice_options',
    'sourcing_events', 'project_updates', 'event_scope_lines',
    'baselines', 'baseline_lines',
    'supplier_offers', 'supplier_offer_lines',
    'savings_calculations', 'savings_periods'
  ];
  -- Metadata always belongs to the new workspace owner. Ownership and
  -- decision actors preserve null (no assignment/decision) and otherwise
  -- move to that owner so no template profile can leak into the clone.
  v_metadata_person_cols text[] := array['created_by', 'updated_by'];
  v_conditional_person_cols text[] := array[
    'procurement_owner_id', 'business_owner_id', 'finance_owner_id',
    'relationship_owner_id',
    'hard_reduction_override_by', 'baseline_approved_by',
    'business_equivalency_confirmed_by',
    'executed_by', 'savings_disposition_by',
    'finance_validated_by', 'comparison_rebased_by', 'award_approved_by'
  ];
  v_known_person_cols text[];
  v_unknown_person_cols text;
  t text;
  v_cols text;
  v_total integer := 0;
  v_count integer;
begin
  if p_source is null or p_target is null or p_owner is null then
    raise exception 'demo clone requires source, target, and owner';
  end if;
  if p_source = p_target then
    raise exception 'demo clone source and target must differ';
  end if;

  perform 1
  from public.organizations organization
  where organization.id = p_source
    and organization.is_demo_template;
  if not found then
    raise exception 'demo clone source must be the designated template';
  end if;

  perform 1
  from public.organizations organization
  join public.profiles profile
    on profile.organization_id = organization.id
   and profile.id = p_owner
  where organization.id = p_target
    and not organization.is_demo_template;
  if not found then
    raise exception 'demo clone owner must belong to the non-template target';
  end if;

  v_known_person_cols := v_metadata_person_cols || v_conditional_person_cols;
  select string_agg(
    format('%I.%I', relation.relname, attribute.attname),
    ', ' order by relation.relname, attribute.attname
  )
  into v_unknown_person_cols
  from pg_catalog.pg_constraint foreign_key
  join pg_catalog.pg_class relation on relation.oid = foreign_key.conrelid
  join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
  cross join lateral unnest(foreign_key.conkey) key_column(attnum)
  join pg_catalog.pg_attribute attribute
    on attribute.attrelid = relation.oid
   and attribute.attnum = key_column.attnum
  where foreign_key.contype = 'f'
    and foreign_key.confrelid = 'public.profiles'::regclass
    and namespace.nspname = 'public'
    and relation.relname = any(v_tables)
    and pg_catalog.cardinality(foreign_key.conkey) = 1
    and not (attribute.attname = any(v_known_person_cols));

  if v_unknown_person_cols is not null then
    raise exception 'unclassified profile reference in demo clone: %', v_unknown_person_cols;
  end if;

  -- A direct service invocation receives the same fresh settings guarantee as
  -- the signup trigger. ON CONFLICT deliberately preserves any explicit target
  -- settings instead of importing the template's preferences.
  insert into public.organization_settings (organization_id, updated_by)
  values (p_target, p_owner)
  on conflict (organization_id) do nothing;

  create temp table _idmap (old uuid primary key, new uuid not null) on commit drop;

  foreach t in array v_tables loop
    execute format(
      'insert into _idmap (old, new) select id, gen_random_uuid() from public.%I where organization_id = $1',
      t) using p_source;
  end loop;

  foreach t in array v_tables loop
    select string_agg(
      case
        when column_row.column_name = 'id'
          then '(select map.new from _idmap map where map.old = source.id)'
        when column_row.column_name = 'organization_id'
          then '$2'
        when column_row.column_name = any(v_metadata_person_cols)
          then '$3'
        when column_row.column_name = any(v_conditional_person_cols)
          then format('case when source.%I is null then null else $3 end', column_row.column_name)
        when column_row.data_type = 'uuid'
          then format('(select map.new from _idmap map where map.old = source.%I)', column_row.column_name)
        else format('source.%I', column_row.column_name)
      end,
      ', ' order by column_row.ordinal_position
    )
    into v_cols
    from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = t;

    execute format(
      'insert into public.%I select %s from public.%I source where source.organization_id = $1',
      t, v_cols, t
    ) using p_source, p_target, p_owner;

    get diagnostics v_count = row_count;
    v_total := v_total + v_count;
  end loop;

  drop table _idmap;
  return v_total;
end
$_$;

revoke all on function public.clone_org_data(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.clone_org_data(uuid, uuid, uuid) to service_role;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_org uuid;
  v_template uuid;
  v_name text := coalesce(new.raw_user_meta_data->>'full_name', new.email);
begin
  insert into public.organizations (name)
  values (v_name || ' (workspace)')
  returning id into v_org;

  insert into public.profiles (id, email, full_name, organization_id, role)
  values (new.id, new.email, v_name, v_org, 'admin');

  -- Settings are outside the best-effort clone block: even a missing or broken
  -- demo must not leave the new workspace with implicit, divergent fallbacks.
  insert into public.organization_settings (organization_id, updated_by)
  values (v_org, new.id);

  begin
    select organization.id into v_template
    from public.organizations organization
    where organization.is_demo_template
    order by organization.id
    limit 1;

    if v_template is not null then
      perform public.clone_org_data(v_template, v_org, new.id);
    end if;
  exception when others then
    raise warning 'demo seed failed for %: %', new.email, sqlerrm;
  end;

  return new;
end
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;
grant execute on function public.handle_new_user() to service_role;

commit;
