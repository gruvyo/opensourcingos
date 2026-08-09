begin;

create table public.supplier_performance_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  supplier_id uuid not null,
  review_title text not null,
  review_date date not null,
  overall_score smallint not null,
  delivery_score smallint,
  quality_score smallint,
  commercial_score smallint,
  compliance_score smallint,
  summary text not null,
  next_review_date date,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  constraint supplier_performance_reviews_supplier_workspace_fkey
    foreign key (supplier_id, organization_id)
    references public.suppliers(id, organization_id)
    on delete cascade,
  constraint supplier_performance_reviews_title_check check (char_length(btrim(review_title)) between 2 and 200),
  constraint supplier_performance_reviews_summary_check check (char_length(btrim(summary)) between 1 and 10000),
  constraint supplier_performance_reviews_overall_score_check check (overall_score between 1 and 5),
  constraint supplier_performance_reviews_delivery_score_check check (delivery_score is null or delivery_score between 1 and 5),
  constraint supplier_performance_reviews_quality_score_check check (quality_score is null or quality_score between 1 and 5),
  constraint supplier_performance_reviews_commercial_score_check check (commercial_score is null or commercial_score between 1 and 5),
  constraint supplier_performance_reviews_compliance_score_check check (compliance_score is null or compliance_score between 1 and 5),
  constraint supplier_performance_reviews_next_date_check check (next_review_date is null or next_review_date >= review_date)
);

comment on table public.supplier_performance_reviews is
  'Dated supplier performance reviews with a required overall score and optional unweighted category scores.';

create index idx_supplier_performance_reviews_workspace_supplier_date
  on public.supplier_performance_reviews (organization_id, supplier_id, review_date desc, created_at desc);
create index idx_supplier_performance_reviews_created_by on public.supplier_performance_reviews (created_by);
create index idx_supplier_performance_reviews_updated_by on public.supplier_performance_reviews (updated_by);

alter table public.supplier_performance_reviews enable row level security;
alter table public.supplier_performance_reviews force row level security;

create policy supplier_performance_reviews_select on public.supplier_performance_reviews
for select to authenticated using (organization_id = (select public.current_org_id()));

create policy supplier_performance_reviews_insert_by_editor on public.supplier_performance_reviews
for insert to authenticated with check (
  organization_id = (select public.current_org_id()) and exists (
    select 1 from public.profiles profile where profile.id = (select auth.uid())
      and profile.organization_id = supplier_performance_reviews.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
);

create policy supplier_performance_reviews_update_by_editor on public.supplier_performance_reviews
for update to authenticated using (
  organization_id = (select public.current_org_id()) and exists (
    select 1 from public.profiles profile where profile.id = (select auth.uid())
      and profile.organization_id = supplier_performance_reviews.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
) with check (
  organization_id = (select public.current_org_id()) and exists (
    select 1 from public.profiles profile where profile.id = (select auth.uid())
      and profile.organization_id = supplier_performance_reviews.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
);

create policy supplier_performance_reviews_delete_by_editor on public.supplier_performance_reviews
for delete to authenticated using (
  organization_id = (select public.current_org_id()) and exists (
    select 1 from public.profiles profile where profile.id = (select auth.uid())
      and profile.organization_id = supplier_performance_reviews.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
);

create function public.stamp_supplier_performance_review_actor()
returns trigger language plpgsql set search_path to 'pg_catalog', 'public' as $$
begin
  if auth.uid() is not null then
    if tg_op = 'INSERT' then new.created_by := auth.uid(); else new.created_by := old.created_by; end if;
    new.updated_by := auth.uid();
  end if;
  return new;
end
$$;

revoke all on function public.stamp_supplier_performance_review_actor() from public, anon, authenticated;
grant execute on function public.stamp_supplier_performance_review_actor() to service_role;

create trigger supplier_performance_reviews_stamp_actor
before insert or update on public.supplier_performance_reviews
for each row execute function public.stamp_supplier_performance_review_actor();

create trigger supplier_performance_reviews_updated_at
before update on public.supplier_performance_reviews
for each row execute function public.update_updated_at();

alter table public.audit_log drop constraint audit_log_entity_type_check;
alter table public.audit_log add constraint audit_log_entity_type_check check (
  entity_type in (
    'organization', 'organization_settings', 'supplier', 'supplier_contact',
    'supplier_certification', 'supplier_performance_review', 'project_choice_option',
    'category', 'business_unit', 'cost_center', 'project_classification_reset',
    'savings_calculation'
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

create trigger supplier_performance_reviews_audit
after insert or update or delete on public.supplier_performance_reviews
for each row execute function public.capture_workspace_audit();

revoke all on table public.supplier_performance_reviews from public, anon;
grant select, insert, update, delete on table public.supplier_performance_reviews to authenticated;
grant all on table public.supplier_performance_reviews to service_role;

commit;
