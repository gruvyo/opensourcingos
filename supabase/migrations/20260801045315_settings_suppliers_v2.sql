-- Release 2: editable workspace settings and durable supplier profiles.
-- All new API-facing objects are explicitly granted and protected by RLS.

begin;

alter table public.suppliers
  add column if not exists website text,
  add column if not exists country_code text,
  add column if not exists relationship_owner_id uuid references public.profiles(id),
  add column if not exists next_review_date date,
  add column if not exists notes text,
  add constraint suppliers_country_code_check
    check (country_code is null or country_code ~ '^[A-Z]{2}$');

create index if not exists idx_suppliers_relationship_owner
  on public.suppliers (relationship_owner_id);
create unique index if not exists uq_suppliers_org_normalized_name
  on public.suppliers (organization_id, supplier_normalized_name)
  where supplier_normalized_name is not null;

create table public.organization_settings (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  currency_code text not null default 'USD'
    check (currency_code ~ '^[A-Z]{3}$'),
  locale text not null default 'en-US',
  timezone text not null default 'America/Chicago',
  fiscal_year_start_month integer not null default 1
    check (fiscal_year_start_month between 1 and 12),
  date_format text not null default 'MMM D, YYYY'
    check (date_format in ('MMM D, YYYY', 'MM/DD/YYYY', 'DD/MM/YYYY', 'YYYY-MM-DD')),
  default_recognition_method text not null default 'monthly'
    check (default_recognition_method in ('monthly', 'annual', 'one_time')),
  require_baseline_for_hard_reduction boolean not null default true,
  hard_reduction_approval_threshold numeric(15,2)
    check (hard_reduction_approval_threshold is null or hard_reduction_approval_threshold >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  entity_type text not null check (entity_type in ('organization', 'organization_settings', 'supplier')),
  entity_id uuid not null,
  action text not null check (action in ('insert', 'update', 'delete')),
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

create index idx_audit_log_org_created
  on public.audit_log (organization_id, created_at desc);
create index idx_audit_log_entity
  on public.audit_log (entity_type, entity_id, created_at desc);

alter table public.organization_settings enable row level security;
alter table public.organization_settings force row level security;
alter table public.audit_log enable row level security;
alter table public.audit_log force row level security;

-- Each person who created a workspace is its initial administrator. This also
-- repairs the two existing sole-owner workspaces created under the old default.
update public.profiles p
set role = 'admin'
where p.role = 'viewer'
  and 1 = (
    select count(*)
    from public.profiles members
    where members.organization_id = p.organization_id
  );

create or replace function public.prevent_profile_privilege_change() returns trigger
  language plpgsql
  set search_path to 'pg_catalog', 'public'
as $$
begin
  if new.organization_id is distinct from old.organization_id then
    raise exception 'organization_id cannot be changed by the user';
  end if;
  if new.role is distinct from old.role then
    raise exception 'role cannot be changed by the user';
  end if;
  return new;
end
$$;

create or replace function public.handle_new_user() returns trigger
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
as $$
declare
  v_org      uuid;
  v_template uuid;
  v_name     text := coalesce(new.raw_user_meta_data->>'full_name', new.email);
begin
  insert into public.organizations (name)
  values (v_name || ' (workspace)')
  returning id into v_org;

  insert into public.profiles (id, email, full_name, organization_id, role)
  values (new.id, new.email, v_name, v_org, 'admin');

  begin
    select id into v_template from public.organizations where is_demo_template limit 1;
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

-- Supplier mutations are limited to administrators and procurement users.
drop policy if exists org_insert on public.suppliers;
drop policy if exists org_update on public.suppliers;
drop policy if exists org_delete on public.suppliers;

create policy supplier_insert_by_editor on public.suppliers
for insert to authenticated
with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.organization_id = suppliers.organization_id
      and p.role in ('admin', 'procurement_user')
  )
);

create policy supplier_update_by_editor on public.suppliers
for update to authenticated
using (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.organization_id = suppliers.organization_id
      and p.role in ('admin', 'procurement_user')
  )
)
with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.organization_id = suppliers.organization_id
      and p.role in ('admin', 'procurement_user')
  )
);

create policy supplier_delete_by_admin on public.suppliers
for delete to authenticated
using (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.organization_id = suppliers.organization_id
      and p.role = 'admin'
  )
);

create policy organization_settings_select on public.organization_settings
for select to authenticated
using (organization_id = (select public.current_org_id()));

create policy organization_settings_insert_by_admin on public.organization_settings
for insert to authenticated
with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.organization_id = organization_settings.organization_id
      and p.role = 'admin'
  )
);

create policy organization_settings_update_by_admin on public.organization_settings
for update to authenticated
using (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.organization_id = organization_settings.organization_id
      and p.role = 'admin'
  )
)
with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.organization_id = organization_settings.organization_id
      and p.role = 'admin'
  )
);

create policy audit_log_select on public.audit_log
for select to authenticated
using (organization_id = (select public.current_org_id()));

create policy organization_update_by_admin on public.organizations
for update to authenticated
using (
  id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.organization_id = organizations.id
      and p.role = 'admin'
  )
)
with check (
  id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.organization_id = organizations.id
      and p.role = 'admin'
  )
);

create or replace function public.capture_workspace_audit() returns trigger
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
as $$
declare
  v_org uuid;
  v_entity_id uuid;
begin
  if tg_table_name = 'organizations' then
    v_org := case when tg_op = 'DELETE' then old.id else new.id end;
    v_entity_id := v_org;
  elsif tg_table_name = 'organization_settings' then
    v_org := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
    v_entity_id := v_org;
  else
    v_org := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
    v_entity_id := case when tg_op = 'DELETE' then old.id else new.id end;
  end if;

  insert into public.audit_log (
    organization_id, actor_id, entity_type, entity_id, action, before_data, after_data
  ) values (
    v_org,
    auth.uid(),
    case tg_table_name
      when 'organizations' then 'organization'
      else tg_table_name
    end,
    v_entity_id,
    lower(tg_op),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end
$$;

revoke all on function public.capture_workspace_audit() from public, anon, authenticated;
grant execute on function public.capture_workspace_audit() to service_role;

create trigger suppliers_audit
after insert or update or delete on public.suppliers
for each row execute function public.capture_workspace_audit();

create trigger organization_settings_audit
after insert or update or delete on public.organization_settings
for each row execute function public.capture_workspace_audit();

create trigger organizations_audit
after update on public.organizations
for each row execute function public.capture_workspace_audit();

create trigger organization_settings_updated_at
before update on public.organization_settings
for each row execute function public.update_updated_at();

create trigger suppliers_updated_at
before update on public.suppliers
for each row execute function public.update_updated_at();

revoke all on table public.organization_settings from anon;
revoke all on table public.audit_log from anon;
grant select, insert, update on table public.organization_settings to authenticated;
grant select on table public.audit_log to authenticated;
grant all on table public.organization_settings to service_role;
grant all on table public.audit_log to service_role;

insert into public.organization_settings (organization_id)
select id from public.organizations
on conflict (organization_id) do nothing;

commit;
