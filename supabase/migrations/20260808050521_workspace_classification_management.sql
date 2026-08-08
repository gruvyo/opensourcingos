begin;

-- Workspace-managed project classifications. Text-backed choices keep the
-- existing project columns stable for reports and exports, while this table
-- controls what can be selected for new or changed values.
create table public.project_choice_options (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  choice_type text not null check (choice_type in ('event_type', 'event_status', 'owner')),
  project_type text check (project_type in ('Sourcing', 'Support')),
  label text not null check (length(btrim(label)) between 1 and 120),
  active_flag boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  constraint project_choice_options_scope_check check (
    (choice_type in ('event_type', 'event_status') and project_type is not null)
    or (choice_type = 'owner' and project_type is null)
  )
);

alter table public.project_choice_options enable row level security;
alter table public.project_choice_options force row level security;

create unique index uq_project_choice_options_org_type_label
  on public.project_choice_options (
    organization_id,
    choice_type,
    coalesce(project_type, ''),
    lower(btrim(label))
  );

create index idx_project_choice_options_org_active
  on public.project_choice_options (organization_id, choice_type, project_type, active_flag, sort_order, label);

create function public.normalize_project_choice_option()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
begin
  new.label := btrim(new.label);

  if tg_op = 'UPDATE' and (
    new.id is distinct from old.id
    or new.organization_id is distinct from old.organization_id
    or new.choice_type is distinct from old.choice_type
    or new.project_type is distinct from old.project_type
    or new.created_at is distinct from old.created_at
    or new.created_by is distinct from old.created_by
  ) then
    raise exception 'Project choice scope cannot be changed' using errcode = '23514';
  end if;

  return new;
end
$$;

revoke all on function public.normalize_project_choice_option()
from public, anon, authenticated;
grant execute on function public.normalize_project_choice_option() to service_role;

create trigger project_choice_options_normalize
before insert or update on public.project_choice_options
for each row execute function public.normalize_project_choice_option();

create trigger project_choice_options_updated_at
before update on public.project_choice_options
for each row execute function public.update_updated_at();

create trigger project_choice_options_audit
after insert or update or delete on public.project_choice_options
for each row execute function public.capture_workspace_audit();

create function public.cascade_project_choice_rename()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
begin
  if new.label is not distinct from old.label then
    return new;
  end if;

  if new.choice_type = 'event_type' then
    update public.sourcing_events
    set event_type = new.label
    where organization_id = new.organization_id
      and project_type = new.project_type
      and lower(btrim(event_type)) = lower(btrim(old.label));
  elsif new.choice_type = 'event_status' then
    update public.sourcing_events
    set event_status = new.label
    where organization_id = new.organization_id
      and project_type = new.project_type
      and lower(btrim(event_status)) = lower(btrim(old.label));
  else
    update public.sourcing_events
    set buyer_name = new.label
    where organization_id = new.organization_id
      and lower(btrim(buyer_name)) = lower(btrim(old.label));
  end if;

  return new;
end
$$;

revoke all on function public.cascade_project_choice_rename()
from public, anon, authenticated;
grant execute on function public.cascade_project_choice_rename() to service_role;

create trigger project_choice_options_cascade_rename
after update of label on public.project_choice_options
for each row execute function public.cascade_project_choice_rename();

create function public.prevent_last_project_choice_archive()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
begin
  if old.active_flag
    and not new.active_flag
    and new.choice_type in ('event_type', 'event_status')
    and not exists (
      select 1 from public.project_choice_options choice
      where choice.organization_id = new.organization_id
        and choice.choice_type = new.choice_type
        and choice.project_type = new.project_type
        and choice.active_flag
        and choice.id <> new.id
    ) then
    raise exception 'At least one active project choice is required for this project type'
      using errcode = '23514';
  end if;

  return new;
end
$$;

revoke all on function public.prevent_last_project_choice_archive()
from public, anon, authenticated;
grant execute on function public.prevent_last_project_choice_archive() to service_role;

create trigger project_choice_options_prevent_last_archive
before update of active_flag on public.project_choice_options
for each row execute function public.prevent_last_project_choice_archive();

create policy project_choice_options_select
on public.project_choice_options for select to authenticated
using (organization_id = (select public.current_org_id()));

create policy project_choice_options_insert_by_admin
on public.project_choice_options for insert to authenticated
with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = project_choice_options.organization_id
      and profile.role = 'admin'
  )
);

create policy project_choice_options_update_by_admin
on public.project_choice_options for update to authenticated
using (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = project_choice_options.organization_id
      and profile.role = 'admin'
  )
)
with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = project_choice_options.organization_id
      and profile.role = 'admin'
  )
);

revoke all on table public.project_choice_options from anon;
grant select, insert, update on table public.project_choice_options to authenticated;
grant all on table public.project_choice_options to service_role;

-- Categories did not previously expose an archive flag. All six managed
-- classifications now share the same preserve-history/archive behavior.
alter table public.categories
  add column active_flag boolean not null default true;

update public.business_units set active_flag = true where active_flag is null;
alter table public.business_units alter column active_flag set not null;
update public.cost_centers set active_flag = true where active_flag is null;
alter table public.cost_centers alter column active_flag set not null;

-- Remove duplicate Cost Centers before adding the same normalized-name
-- protection already used by Categories and Business Units.
create temporary table _cost_center_merge_map on commit drop as
with scored as (
  select
    center.*,
    (select count(*) from public.sourcing_events event where event.cost_center_id = center.id) as reference_count
  from public.cost_centers center
  where center.organization_id is not null
), ranked as (
  select
    id,
    first_value(id) over (
      partition by organization_id, lower(btrim(cost_center_name))
      order by reference_count desc, created_at asc, id
    ) as canonical_id,
    count(*) over (
      partition by organization_id, lower(btrim(cost_center_name))
    ) as duplicate_count
  from scored
)
select id as duplicate_id, canonical_id
from ranked
where duplicate_count > 1 and id <> canonical_id;

update public.sourcing_events event
set cost_center_id = map.canonical_id
from _cost_center_merge_map map
where event.cost_center_id = map.duplicate_id;

with canonical_ids as (
  select distinct canonical_id from _cost_center_merge_map
), merged as (
  select
    canonical.id as canonical_id,
    (
      array_agg(center.business_unit_id order by center.created_at, center.id)
      filter (where center.business_unit_id is not null)
    )[1] as business_unit_id,
    (
      array_agg(center.gl_account_default order by center.created_at, center.id)
      filter (where nullif(btrim(center.gl_account_default), '') is not null)
    )[1] as gl_account_default,
    bool_or(center.active_flag) as active_flag
  from canonical_ids canonical
  join public.cost_centers center
    on center.id = canonical.canonical_id
    or center.id in (
      select map.duplicate_id
      from _cost_center_merge_map map
      where map.canonical_id = canonical.canonical_id
    )
  group by canonical.id
)
update public.cost_centers canonical
set
  business_unit_id = coalesce(canonical.business_unit_id, merged.business_unit_id),
  gl_account_default = coalesce(canonical.gl_account_default, merged.gl_account_default),
  active_flag = merged.active_flag
from merged
where canonical.id = merged.canonical_id;

delete from public.cost_centers center
using _cost_center_merge_map map
where center.id = map.duplicate_id;

create unique index uq_cost_centers_org_normalized_name
  on public.cost_centers (organization_id, lower(btrim(cost_center_name)))
  where organization_id is not null;

-- Classification administration belongs to workspace administrators. All
-- members retain read access so project forms and historical details work.
drop policy if exists org_insert on public.categories;
drop policy if exists org_update on public.categories;
drop policy if exists org_delete on public.categories;
drop policy if exists org_insert on public.business_units;
drop policy if exists org_update on public.business_units;
drop policy if exists org_delete on public.business_units;
drop policy if exists org_insert on public.cost_centers;
drop policy if exists org_update on public.cost_centers;
drop policy if exists org_delete on public.cost_centers;

create policy categories_insert_by_admin on public.categories
for insert to authenticated with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = categories.organization_id
      and profile.role = 'admin'
  )
);
create policy categories_update_by_admin on public.categories
for update to authenticated
using (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = categories.organization_id
      and profile.role = 'admin'
  )
)
with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = categories.organization_id
      and profile.role = 'admin'
  )
);

create policy business_units_insert_by_admin on public.business_units
for insert to authenticated with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = business_units.organization_id
      and profile.role = 'admin'
  )
);
create policy business_units_update_by_admin on public.business_units
for update to authenticated
using (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = business_units.organization_id
      and profile.role = 'admin'
  )
)
with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = business_units.organization_id
      and profile.role = 'admin'
  )
);

create policy cost_centers_insert_by_admin on public.cost_centers
for insert to authenticated with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = cost_centers.organization_id
      and profile.role = 'admin'
  )
);
create policy cost_centers_update_by_admin on public.cost_centers
for update to authenticated
using (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = cost_centers.organization_id
      and profile.role = 'admin'
  )
)
with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = cost_centers.organization_id
      and profile.role = 'admin'
  )
);

create trigger categories_audit
after insert or update or delete on public.categories
for each row execute function public.capture_workspace_audit();
create trigger business_units_audit
after insert or update or delete on public.business_units
for each row execute function public.capture_workspace_audit();
create trigger cost_centers_audit
after insert or update or delete on public.cost_centers
for each row execute function public.capture_workspace_audit();

-- Seed the built-in choices for every existing workspace. These are ordinary
-- rows and can be renamed or archived by an administrator after migration.
insert into public.project_choice_options (
  organization_id, choice_type, project_type, label, sort_order
)
select organization.id, seed.choice_type, seed.project_type, seed.label, seed.sort_order
from public.organizations organization
cross join (
  values
    ('event_type', 'Sourcing', 'Renewal', 10),
    ('event_type', 'Sourcing', 'Competitive Rebid', 20),
    ('event_type', 'Sourcing', 'Net New Purchase', 30),
    ('event_type', 'Sourcing', 'Renegotiation', 40),
    ('event_type', 'Sourcing', 'Demand Reduction', 50),
    ('event_type', 'Sourcing', 'Specification Change', 60),
    ('event_type', 'Sourcing', 'Supplier Consolidation', 70),
    ('event_type', 'Sourcing', 'Market Index / Commodity', 80),
    ('event_type', 'Sourcing', 'Payment Terms', 90),
    ('event_type', 'Sourcing', 'Rebate / Credit', 100),
    ('event_type', 'Sourcing', 'One-Time Fee Waiver', 110),
    ('event_type', 'Sourcing', 'Early Payment Discount', 120),
    ('event_type', 'Sourcing', 'TCO Improvement', 130),
    ('event_type', 'Sourcing', 'Productivity Improvement', 140),
    ('event_type', 'Support', 'Vendor Issue', 10),
    ('event_type', 'Support', 'Support Ticket', 20),
    ('event_type', 'Support', 'Contract Question', 30),
    ('event_type', 'Support', 'Billing Dispute', 40),
    ('event_type', 'Support', 'Service Request', 50),
    ('event_type', 'Support', 'Compliance/Legal', 60),
    ('event_type', 'Support', 'Other', 70),
    ('event_status', 'Sourcing', 'Pipeline', 10),
    ('event_status', 'Sourcing', 'Scoped', 20),
    ('event_status', 'Sourcing', 'Baseline Pending', 30),
    ('event_status', 'Sourcing', 'Baseline Approved', 40),
    ('event_status', 'Sourcing', 'In Market', 50),
    ('event_status', 'Sourcing', 'Negotiation', 60),
    ('event_status', 'Sourcing', 'Award Recommended', 70),
    ('event_status', 'Sourcing', 'Award Approved', 80),
    ('event_status', 'Sourcing', 'Contracted', 90),
    ('event_status', 'Sourcing', 'Implemented', 100),
    ('event_status', 'Sourcing', 'Realized', 110),
    ('event_status', 'Sourcing', 'Finance Validated', 120),
    ('event_status', 'Sourcing', 'Closed', 130),
    ('event_status', 'Sourcing', 'Cancelled', 140),
    ('event_status', 'Sourcing', 'Rejected', 150),
    ('event_status', 'Support', 'Not Started', 10),
    ('event_status', 'Support', 'In Progress', 20),
    ('event_status', 'Support', 'Hold', 30),
    ('event_status', 'Support', 'Complete', 40),
    ('event_status', 'Support', 'Cancelled', 50)
) as seed(choice_type, project_type, label, sort_order)
on conflict do nothing;

-- Preserve any custom values already present in production.
insert into public.project_choice_options (
  organization_id, choice_type, project_type, label, sort_order
)
select distinct organization_id, 'event_type', project_type, btrim(event_type), 1000
from public.sourcing_events
where organization_id is not null and nullif(btrim(event_type), '') is not null
on conflict do nothing;

insert into public.project_choice_options (
  organization_id, choice_type, project_type, label, sort_order
)
select distinct organization_id, 'event_status', project_type, btrim(event_status), 1000
from public.sourcing_events
where organization_id is not null and nullif(btrim(event_status), '') is not null
on conflict do nothing;

insert into public.project_choice_options (
  organization_id, choice_type, project_type, label, sort_order
)
select distinct organization_id, 'owner', null, btrim(buyer_name), 1000
from public.sourcing_events
where organization_id is not null and nullif(btrim(buyer_name), '') is not null
on conflict do nothing;

-- The managed status table replaces the old hard-coded status constraint.
alter table public.sourcing_events
  drop constraint sourcing_events_event_status_check;

-- New and changed text-backed classifications must come from an active choice.
-- Unrelated edits may retain an archived historical value.
create function public.enforce_project_choice_options()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
begin
  if tg_op = 'INSERT'
    or new.project_type is distinct from old.project_type
    or new.event_type is distinct from old.event_type then
    if not exists (
      select 1 from public.project_choice_options choice
      where choice.organization_id = new.organization_id
        and choice.choice_type = 'event_type'
        and choice.project_type = new.project_type
        and choice.active_flag
        and lower(btrim(choice.label)) = lower(btrim(new.event_type))
    ) then
      raise exception 'Project type is not an active workspace choice' using errcode = '23514';
    end if;
  end if;

  if tg_op = 'INSERT'
    or new.project_type is distinct from old.project_type
    or new.event_status is distinct from old.event_status then
    if not exists (
      select 1 from public.project_choice_options choice
      where choice.organization_id = new.organization_id
        and choice.choice_type = 'event_status'
        and choice.project_type = new.project_type
        and choice.active_flag
        and lower(btrim(choice.label)) = lower(btrim(new.event_status))
    ) then
      raise exception 'Project status is not an active workspace choice' using errcode = '23514';
    end if;
  end if;

  if (tg_op = 'INSERT' or new.buyer_name is distinct from old.buyer_name)
    and nullif(btrim(new.buyer_name), '') is not null then
    if not exists (
      select 1 from public.project_choice_options choice
      where choice.organization_id = new.organization_id
        and choice.choice_type = 'owner'
        and choice.project_type is null
        and choice.active_flag
        and lower(btrim(choice.label)) = lower(btrim(new.buyer_name))
    ) then
      raise exception 'Project owner is not an active workspace choice' using errcode = '23514';
    end if;
  end if;

  if (tg_op = 'INSERT' or new.category_id is distinct from old.category_id)
    and new.category_id is not null
    and not exists (
      select 1 from public.categories category
      where category.id = new.category_id
        and category.organization_id = new.organization_id
        and category.active_flag
    ) then
    raise exception 'Project Category is not an active workspace choice' using errcode = '23514';
  end if;

  if (tg_op = 'INSERT' or new.business_unit_id is distinct from old.business_unit_id)
    and new.business_unit_id is not null
    and not exists (
      select 1 from public.business_units unit
      where unit.id = new.business_unit_id
        and unit.organization_id = new.organization_id
        and unit.active_flag
    ) then
    raise exception 'Project Business Unit is not an active workspace choice' using errcode = '23514';
  end if;

  if (tg_op = 'INSERT' or new.cost_center_id is distinct from old.cost_center_id)
    and new.cost_center_id is not null
    and not exists (
      select 1 from public.cost_centers center
      where center.id = new.cost_center_id
        and center.organization_id = new.organization_id
        and center.active_flag
    ) then
    raise exception 'Project Cost Center is not an active workspace choice' using errcode = '23514';
  end if;

  return new;
end
$$;

revoke all on function public.enforce_project_choice_options()
from public, anon, authenticated;
grant execute on function public.enforce_project_choice_options() to service_role;

create trigger zz_sourcing_events_enforce_project_choice_options
before insert or update on public.sourcing_events
for each row execute function public.enforce_project_choice_options();

-- Include managed text choices in every newly cloned demo workspace.
create or replace function public.clone_org_data(p_source uuid, p_target uuid, p_owner uuid)
returns integer
language plpgsql security definer
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
  v_person_cols text[] := array['created_by', 'updated_by', 'procurement_owner_id',
                                'hard_reduction_override_by', 'finance_validated_by'];
  t text;
  v_cols text;
  v_total integer := 0;
  v_count integer;
begin
  create temp table _idmap (old uuid primary key, new uuid not null) on commit drop;

  foreach t in array v_tables loop
    execute format(
      'insert into _idmap (old, new) select id, gen_random_uuid() from public.%I where organization_id = $1',
      t) using p_source;
  end loop;

  foreach t in array v_tables loop
    select string_agg(
      case
        when c.column_name = 'id'
          then '(select m.new from _idmap m where m.old = s.id)'
        when c.column_name = 'organization_id'
          then '$2'
        when c.column_name = any(v_person_cols)
          then '$3'
        when c.data_type = 'uuid'
          then format('(select m.new from _idmap m where m.old = s.%I)', c.column_name)
        else format('s.%I', c.column_name)
      end,
      ', ' order by c.ordinal_position)
    into v_cols
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = t;

    execute format(
      'insert into public.%I select %s from public.%I s where s.organization_id = $1',
      t, v_cols, t) using p_source, p_target, p_owner;

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

commit;
