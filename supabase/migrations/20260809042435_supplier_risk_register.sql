begin;

create table public.supplier_risks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  supplier_id uuid not null,
  risk_title text not null,
  identified_on date not null,
  severity text not null,
  risk_status text not null default 'Open',
  description text not null,
  target_resolution_date date,
  evidence_url text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  constraint supplier_risks_supplier_workspace_fkey
    foreign key (supplier_id, organization_id)
    references public.suppliers(id, organization_id)
    on delete cascade,
  constraint supplier_risks_title_check check (char_length(btrim(risk_title)) between 2 and 200),
  constraint supplier_risks_description_check check (char_length(btrim(description)) between 1 and 10000),
  constraint supplier_risks_severity_check check (severity in ('Low', 'Medium', 'High', 'Critical')),
  constraint supplier_risks_status_check check (risk_status in ('Open', 'Monitoring', 'Resolved')),
  constraint supplier_risks_target_date_check check (target_resolution_date is null or target_resolution_date >= identified_on),
  constraint supplier_risks_url_check check (evidence_url is null or (char_length(evidence_url) <= 2000 and evidence_url ~ '^https?://'))
);

comment on table public.supplier_risks is
  'Structured supplier risk evidence without automatic changes to the relationship-level risk rating.';

create index idx_supplier_risks_workspace_supplier_status
  on public.supplier_risks (organization_id, supplier_id, risk_status, severity, identified_on desc);
create index idx_supplier_risks_supplier_workspace
  on public.supplier_risks (supplier_id, organization_id);
create index idx_supplier_risks_created_by on public.supplier_risks (created_by);
create index idx_supplier_risks_updated_by on public.supplier_risks (updated_by);

alter table public.supplier_risks enable row level security;
alter table public.supplier_risks force row level security;

create policy supplier_risks_select on public.supplier_risks
for select to authenticated using (organization_id = (select public.current_org_id()));

create policy supplier_risks_insert_by_editor on public.supplier_risks
for insert to authenticated with check (
  organization_id = (select public.current_org_id()) and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = supplier_risks.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
);

create policy supplier_risks_update_by_editor on public.supplier_risks
for update to authenticated using (
  organization_id = (select public.current_org_id()) and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = supplier_risks.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
) with check (
  organization_id = (select public.current_org_id()) and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = supplier_risks.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
);

create policy supplier_risks_delete_by_editor on public.supplier_risks
for delete to authenticated using (
  organization_id = (select public.current_org_id()) and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = supplier_risks.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
);

create function public.stamp_supplier_risk_actor()
returns trigger language plpgsql set search_path to 'pg_catalog', 'public' as $$
begin
  if auth.uid() is not null then
    if tg_op = 'INSERT' then new.created_by := auth.uid(); else new.created_by := old.created_by; end if;
    new.updated_by := auth.uid();
  end if;
  return new;
end
$$;

revoke all on function public.stamp_supplier_risk_actor() from public, anon, authenticated;
grant execute on function public.stamp_supplier_risk_actor() to service_role;

create trigger supplier_risks_stamp_actor
before insert or update on public.supplier_risks
for each row execute function public.stamp_supplier_risk_actor();

create trigger supplier_risks_updated_at
before update on public.supplier_risks
for each row execute function public.update_updated_at();

alter table public.audit_log drop constraint audit_log_entity_type_check;
alter table public.audit_log add constraint audit_log_entity_type_check check (
  entity_type in (
    'organization', 'organization_settings', 'supplier', 'supplier_contact',
    'supplier_certification', 'supplier_performance_review', 'supplier_risk',
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
      when 'supplier_performance_reviews' then 'supplier_performance_review'
      when 'supplier_risks' then 'supplier_risk'
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

create trigger supplier_risks_audit
after insert or update or delete on public.supplier_risks
for each row execute function public.capture_workspace_audit();

revoke all on table public.supplier_risks from public, anon;
grant select, insert, update, delete on table public.supplier_risks to authenticated;
grant all on table public.supplier_risks to service_role;

commit;
