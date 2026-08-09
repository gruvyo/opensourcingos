begin;

create table public.supplier_certifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  supplier_id uuid not null,
  certification_name text not null,
  issuer text,
  certificate_number text,
  issued_on date,
  expires_on date,
  evidence_url text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  constraint supplier_certifications_supplier_workspace_fkey
    foreign key (supplier_id, organization_id)
    references public.suppliers(id, organization_id)
    on delete cascade,
  constraint supplier_certifications_name_check check (char_length(btrim(certification_name)) between 2 and 200),
  constraint supplier_certifications_issuer_check check (issuer is null or char_length(issuer) between 1 and 200),
  constraint supplier_certifications_number_check check (certificate_number is null or char_length(certificate_number) between 1 and 200),
  constraint supplier_certifications_date_order_check check (issued_on is null or expires_on is null or expires_on >= issued_on),
  constraint supplier_certifications_url_check check (evidence_url is null or (char_length(evidence_url) <= 2000 and evidence_url ~ '^https?://'))
);

comment on table public.supplier_certifications is
  'Supplier certifications with issuer, validity dates, and optional public evidence.';

create index idx_supplier_certifications_workspace_supplier_expiry
  on public.supplier_certifications (organization_id, supplier_id, expires_on, certification_name);
create index idx_supplier_certifications_created_by on public.supplier_certifications (created_by);
create index idx_supplier_certifications_updated_by on public.supplier_certifications (updated_by);

alter table public.supplier_certifications enable row level security;
alter table public.supplier_certifications force row level security;

create policy supplier_certifications_select on public.supplier_certifications
for select to authenticated using (organization_id = (select public.current_org_id()));

create policy supplier_certifications_insert_by_editor on public.supplier_certifications
for insert to authenticated with check (
  organization_id = (select public.current_org_id()) and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = supplier_certifications.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
);

create policy supplier_certifications_update_by_editor on public.supplier_certifications
for update to authenticated using (
  organization_id = (select public.current_org_id()) and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = supplier_certifications.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
) with check (
  organization_id = (select public.current_org_id()) and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = supplier_certifications.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
);

create policy supplier_certifications_delete_by_editor on public.supplier_certifications
for delete to authenticated using (
  organization_id = (select public.current_org_id()) and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = supplier_certifications.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
);

create function public.stamp_supplier_certification_actor()
returns trigger language plpgsql set search_path to 'pg_catalog', 'public' as $$
begin
  if auth.uid() is not null then
    if tg_op = 'INSERT' then new.created_by := auth.uid(); else new.created_by := old.created_by; end if;
    new.updated_by := auth.uid();
  end if;
  return new;
end
$$;

revoke all on function public.stamp_supplier_certification_actor() from public, anon, authenticated;
grant execute on function public.stamp_supplier_certification_actor() to service_role;

create trigger supplier_certifications_stamp_actor
before insert or update on public.supplier_certifications
for each row execute function public.stamp_supplier_certification_actor();

create trigger supplier_certifications_updated_at
before update on public.supplier_certifications
for each row execute function public.update_updated_at();

alter table public.audit_log drop constraint audit_log_entity_type_check;
alter table public.audit_log add constraint audit_log_entity_type_check check (
  entity_type in (
    'organization', 'organization_settings', 'supplier', 'supplier_contact', 'supplier_certification',
    'project_choice_option', 'category', 'business_unit', 'cost_center',
    'project_classification_reset', 'savings_calculation'
  )
);

create or replace function public.capture_workspace_audit()
returns trigger language plpgsql security definer set search_path to 'pg_catalog', 'public' as $$
declare v_org uuid; v_entity_id uuid; v_entity_type text;
begin
  if tg_table_name = 'organizations' then
    v_org := case when tg_op = 'DELETE' then old.id else new.id end;
    v_entity_id := v_org; v_entity_type := 'organization';
  elsif tg_table_name = 'organization_settings' then
    v_org := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
    v_entity_id := v_org; v_entity_type := 'organization_settings';
  else
    v_org := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
    v_entity_id := case when tg_op = 'DELETE' then old.id else new.id end;
    v_entity_type := case tg_table_name
      when 'suppliers' then 'supplier'
      when 'supplier_contacts' then 'supplier_contact'
      when 'supplier_certifications' then 'supplier_certification'
      when 'project_choice_options' then 'project_choice_option'
      when 'categories' then 'category'
      when 'business_units' then 'business_unit'
      when 'cost_centers' then 'cost_center'
      when 'savings_calculations' then 'savings_calculation'
      else 'supplier'
    end;
  end if;
  insert into public.audit_log (organization_id, actor_id, entity_type, entity_id, action, before_data, after_data)
  values (v_org, auth.uid(), v_entity_type, v_entity_id, lower(tg_op),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

revoke all on function public.capture_workspace_audit() from public, anon, authenticated;
grant execute on function public.capture_workspace_audit() to service_role;

create trigger supplier_certifications_audit
after insert or update or delete on public.supplier_certifications
for each row execute function public.capture_workspace_audit();

revoke all on table public.supplier_certifications from public, anon;
grant select, insert, update, delete on table public.supplier_certifications to authenticated;
grant all on table public.supplier_certifications to service_role;

commit;
