begin;

-- A redundant composite key lets the child foreign key prove that every
-- contact and supplier belong to the same workspace, not merely that both IDs
-- exist independently.
alter table public.suppliers
  add constraint suppliers_id_organization_unique unique (id, organization_id);

create table public.supplier_contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  supplier_id uuid not null,
  contact_name text not null,
  job_title text,
  email text,
  phone text,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  constraint supplier_contacts_supplier_workspace_fkey
    foreign key (supplier_id, organization_id)
    references public.suppliers(id, organization_id)
    on delete cascade,
  constraint supplier_contacts_name_check
    check (char_length(btrim(contact_name)) between 2 and 160),
  constraint supplier_contacts_job_title_check
    check (job_title is null or char_length(job_title) between 1 and 160),
  constraint supplier_contacts_email_check
    check (email is null or (char_length(email) <= 320 and position('@' in email) > 1)),
  constraint supplier_contacts_phone_check
    check (phone is null or char_length(phone) between 3 and 50)
);

comment on table public.supplier_contacts is
  'Named commercial and operational contacts attached to one supplier relationship.';

create index idx_supplier_contacts_workspace_supplier
  on public.supplier_contacts (organization_id, supplier_id, is_primary desc, contact_name);
create index idx_supplier_contacts_created_by
  on public.supplier_contacts (created_by);
create index idx_supplier_contacts_updated_by
  on public.supplier_contacts (updated_by);
create unique index uq_supplier_contacts_primary
  on public.supplier_contacts (supplier_id)
  where is_primary;

alter table public.supplier_contacts enable row level security;
alter table public.supplier_contacts force row level security;

create policy supplier_contacts_select on public.supplier_contacts
for select to authenticated
using (organization_id = (select public.current_org_id()));

create policy supplier_contacts_insert_by_editor on public.supplier_contacts
for insert to authenticated
with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = supplier_contacts.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
);

create policy supplier_contacts_update_by_editor on public.supplier_contacts
for update to authenticated
using (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = supplier_contacts.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
)
with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = supplier_contacts.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
);

create policy supplier_contacts_delete_by_editor on public.supplier_contacts
for delete to authenticated
using (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = supplier_contacts.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
);

-- Data API callers cannot forge the contact's author fields. Service-role
-- maintenance may provide an actor explicitly when no user JWT is present.
create function public.stamp_supplier_contact_actor()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if auth.uid() is not null then
    if tg_op = 'INSERT' then
      new.created_by := auth.uid();
    else
      new.created_by := old.created_by;
    end if;
    new.updated_by := auth.uid();
  end if;
  return new;
end
$$;

revoke all on function public.stamp_supplier_contact_actor()
  from public, anon, authenticated;
grant execute on function public.stamp_supplier_contact_actor()
  to service_role;

create trigger supplier_contacts_stamp_actor
before insert or update on public.supplier_contacts
for each row execute function public.stamp_supplier_contact_actor();

-- Marking a contact primary atomically demotes the previous primary. The
-- partial unique index handles concurrent writes without permitting two.
create function public.set_single_primary_supplier_contact()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if new.is_primary then
    update public.supplier_contacts
    set
      is_primary = false,
      updated_at = now(),
      updated_by = auth.uid()
    where supplier_id = new.supplier_id
      and organization_id = new.organization_id
      and id is distinct from new.id
      and is_primary;
  end if;
  return new;
end
$$;

revoke all on function public.set_single_primary_supplier_contact()
  from public, anon, authenticated;
grant execute on function public.set_single_primary_supplier_contact()
  to service_role;

create trigger supplier_contacts_single_primary
before insert or update of is_primary on public.supplier_contacts
for each row execute function public.set_single_primary_supplier_contact();

create trigger supplier_contacts_updated_at
before update on public.supplier_contacts
for each row execute function public.update_updated_at();

alter table public.audit_log
  drop constraint audit_log_entity_type_check;
alter table public.audit_log
  add constraint audit_log_entity_type_check check (
    entity_type in (
      'organization', 'organization_settings', 'supplier', 'supplier_contact',
      'project_choice_option', 'category', 'business_unit', 'cost_center',
      'project_classification_reset', 'savings_calculation'
    )
  );

create or replace function public.capture_workspace_audit()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_org uuid;
  v_entity_id uuid;
  v_entity_type text;
begin
  if tg_table_name = 'organizations' then
    v_org := case when tg_op = 'DELETE' then old.id else new.id end;
    v_entity_id := v_org;
    v_entity_type := 'organization';
  elsif tg_table_name = 'organization_settings' then
    v_org := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
    v_entity_id := v_org;
    v_entity_type := 'organization_settings';
  else
    v_org := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
    v_entity_id := case when tg_op = 'DELETE' then old.id else new.id end;
    v_entity_type := case tg_table_name
      when 'suppliers' then 'supplier'
      when 'supplier_contacts' then 'supplier_contact'
      when 'project_choice_options' then 'project_choice_option'
      when 'categories' then 'category'
      when 'business_units' then 'business_unit'
      when 'cost_centers' then 'cost_center'
      when 'savings_calculations' then 'savings_calculation'
      else 'supplier'
    end;
  end if;

  insert into public.audit_log (
    organization_id, actor_id, entity_type, entity_id, action, before_data, after_data
  ) values (
    v_org,
    auth.uid(),
    v_entity_type,
    v_entity_id,
    lower(tg_op),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end
  );

  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

revoke all on function public.capture_workspace_audit()
  from public, anon, authenticated;
grant execute on function public.capture_workspace_audit()
  to service_role;

create trigger supplier_contacts_audit
after insert or update or delete on public.supplier_contacts
for each row execute function public.capture_workspace_audit();

revoke all on table public.supplier_contacts from public, anon;
grant select, insert, update, delete on table public.supplier_contacts to authenticated;
grant all on table public.supplier_contacts to service_role;

commit;
