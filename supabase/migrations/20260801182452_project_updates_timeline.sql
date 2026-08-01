-- Replace the single mutable sourcing_events.notes field with an append-only,
-- dated project update timeline. Existing notes are preserved as the first
-- update, and the legacy column remains temporarily for compatibility.

begin;

create table public.project_updates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  event_id uuid not null references public.sourcing_events(id) on delete cascade,
  body text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint project_updates_body_not_blank check (length(btrim(body)) > 0),
  constraint project_updates_body_length check (char_length(body) <= 10000)
);

comment on table public.project_updates is
  'Append-only, dated project progress updates. Editing, deletion, mentions, and notifications are intentionally deferred.';
comment on column public.sourcing_events.notes is
  'Legacy project note retained for compatibility. New content belongs in project_updates.';

create index idx_project_updates_event_created
  on public.project_updates (event_id, created_at desc);
create index idx_project_updates_org_created
  on public.project_updates (organization_id, created_at desc);
create index idx_project_updates_created_by
  on public.project_updates (created_by);

alter table public.project_updates enable row level security;
alter table public.project_updates force row level security;

revoke all on table public.project_updates from public, anon, authenticated;
grant select, insert on table public.project_updates to authenticated;
grant select, insert, update, delete on table public.project_updates to service_role;

create policy project_updates_select_org
on public.project_updates
for select to authenticated
using (organization_id = (select public.current_org_id()));

create policy project_updates_insert_org_author
on public.project_updates
for insert to authenticated
with check (
  organization_id = (select public.current_org_id())
  and created_by = (select auth.uid())
  and exists (
    select 1
    from public.sourcing_events event
    where event.id = project_updates.event_id
      and event.organization_id = project_updates.organization_id
  )
);

-- Carry every existing note into the new timeline without changing its text.
insert into public.project_updates (
  organization_id,
  event_id,
  body,
  created_by,
  created_at
)
select
  event.organization_id,
  event.id,
  event.notes,
  event.created_by,
  coalesce(event.created_at, now())
from public.sourcing_events event
where event.organization_id is not null
  and event.notes is not null
  and length(btrim(event.notes)) > 0;

-- New tester workspaces should receive the template's project history too.
create or replace function public.clone_org_data(p_source uuid, p_target uuid, p_owner uuid)
returns integer
language plpgsql security definer
set search_path to 'pg_catalog', 'public'
as $_$
declare
  -- Dependency order matters for the INSERT pass because of foreign keys.
  v_tables text[] := array[
    'categories', 'business_units', 'cost_centers', 'suppliers',
    'sourcing_events', 'project_updates', 'event_scope_lines',
    'baselines', 'baseline_lines',
    'supplier_offers', 'supplier_offer_lines',
    'savings_calculations', 'savings_periods'
  ];
  -- Columns pointing at a person rather than at a cloned row.
  v_person_cols text[] := array['created_by', 'updated_by', 'procurement_owner_id',
                                'hard_reduction_override_by', 'finance_validated_by'];
  t         text;
  v_cols    text;
  v_total   integer := 0;
  v_count   integer;
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

revoke all on function public.clone_org_data(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.clone_org_data(uuid, uuid, uuid) to service_role;

commit;
