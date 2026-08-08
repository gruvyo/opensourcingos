begin;

alter table public.audit_log
  drop constraint audit_log_entity_type_check;

alter table public.audit_log
  add constraint audit_log_entity_type_check check (
    entity_type in (
      'organization',
      'organization_settings',
      'supplier',
      'project_choice_option',
      'category',
      'business_unit',
      'cost_center',
      'project_classification_reset'
    )
  );

-- Classification-management triggers previously preserved the correct row JSON
-- under the generic supplier label. Correct those historical labels in place.
update public.audit_log
set entity_type = case
  when coalesce(before_data, after_data) ? 'choice_type' then 'project_choice_option'
  when coalesce(before_data, after_data) ? 'category_name' then 'category'
  when coalesce(before_data, after_data) ? 'business_unit_name' then 'business_unit'
  when coalesce(before_data, after_data) ? 'cost_center_name' then 'cost_center'
  else entity_type
end
where entity_type = 'supplier'
  and (
    coalesce(before_data, after_data) ? 'choice_type'
    or coalesce(before_data, after_data) ? 'category_name'
    or coalesce(before_data, after_data) ? 'business_unit_name'
    or coalesce(before_data, after_data) ? 'cost_center_name'
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
      when 'project_choice_options' then 'project_choice_option'
      when 'categories' then 'category'
      when 'business_units' then 'business_unit'
      when 'cost_centers' then 'cost_center'
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

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end
$$;

revoke all on function public.capture_workspace_audit()
  from public, anon, authenticated;
grant execute on function public.capture_workspace_audit()
  to service_role;

insert into public.audit_log (
  organization_id,
  actor_id,
  entity_type,
  entity_id,
  action,
  before_data,
  after_data
)
select
  organization.id,
  null,
  'project_classification_reset',
  organization.id,
  'update',
  jsonb_build_object(
    'taxonomy', 'ideation-era defaults and beta customizations',
    'project_count', (
      select count(*)
      from public.sourcing_events as event
      where event.organization_id = organization.id
    )
  ),
  jsonb_build_object(
    'migration', 'refresh_project_classification_defaults',
    'canonical_choice_count', 26,
    'sourcing_type_count', 6,
    'support_type_count', 6,
    'sourcing_status_count', 9,
    'support_status_count', 5
  )
from public.organizations as organization
where not exists (
  select 1
  from public.audit_log as existing
  where existing.organization_id = organization.id
    and existing.entity_type = 'project_classification_reset'
    and existing.after_data ->> 'migration' = 'refresh_project_classification_defaults'
);

commit;
