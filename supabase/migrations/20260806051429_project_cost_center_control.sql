begin;

alter table public.organization_settings
  add column project_cost_centers_enabled boolean not null default true;

comment on column public.organization_settings.project_cost_centers_enabled is
  'Controls whether project Cost Center values may be added or changed. Existing values remain visible.';

create function public.update_workspace_settings_v4(
  p_organization_name text,
  p_full_name text,
  p_currency_code text,
  p_locale text,
  p_timezone text,
  p_fiscal_year_start_month integer,
  p_date_format text,
  p_default_recognition_method text,
  p_require_baseline boolean,
  p_hard_reduction_approval_threshold numeric,
  p_support_projects_enabled boolean,
  p_project_descriptions_enabled boolean,
  p_project_owners_enabled boolean,
  p_project_cost_centers_enabled boolean
) returns void
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid := public.current_org_id();
  v_role text;
begin
  if v_user is null or v_org is null then
    raise exception 'authentication required';
  end if;

  select role into v_role
  from public.profiles
  where id = v_user and organization_id = v_org;

  if v_role is distinct from 'admin' then
    raise exception 'administrator role required';
  end if;

  update public.organizations
  set name = p_organization_name
  where id = v_org;

  update public.profiles
  set full_name = p_full_name
  where id = v_user and organization_id = v_org;

  insert into public.organization_settings (
    organization_id,
    currency_code,
    locale,
    timezone,
    fiscal_year_start_month,
    date_format,
    default_recognition_method,
    require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold,
    support_projects_enabled,
    project_descriptions_enabled,
    project_owners_enabled,
    project_cost_centers_enabled,
    updated_by
  ) values (
    v_org,
    p_currency_code,
    p_locale,
    p_timezone,
    p_fiscal_year_start_month,
    p_date_format,
    p_default_recognition_method,
    p_require_baseline,
    p_hard_reduction_approval_threshold,
    p_support_projects_enabled,
    p_project_descriptions_enabled,
    p_project_owners_enabled,
    p_project_cost_centers_enabled,
    v_user
  )
  on conflict (organization_id) do update set
    currency_code = excluded.currency_code,
    locale = excluded.locale,
    timezone = excluded.timezone,
    fiscal_year_start_month = excluded.fiscal_year_start_month,
    date_format = excluded.date_format,
    default_recognition_method = excluded.default_recognition_method,
    require_baseline_for_hard_reduction = excluded.require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold = excluded.hard_reduction_approval_threshold,
    support_projects_enabled = excluded.support_projects_enabled,
    project_descriptions_enabled = excluded.project_descriptions_enabled,
    project_owners_enabled = excluded.project_owners_enabled,
    project_cost_centers_enabled = excluded.project_cost_centers_enabled,
    updated_by = excluded.updated_by;
end
$$;

revoke all on function public.update_workspace_settings_v4(
  text,
  text,
  text,
  text,
  text,
  integer,
  text,
  text,
  boolean,
  numeric,
  boolean,
  boolean,
  boolean,
  boolean
) from public, anon;

grant execute on function public.update_workspace_settings_v4(
  text,
  text,
  text,
  text,
  text,
  integer,
  text,
  text,
  boolean,
  numeric,
  boolean,
  boolean,
  boolean,
  boolean
) to authenticated, service_role;

create function public.enforce_project_cost_center_setting()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
begin
  if coalesce(
    (
      select settings.project_cost_centers_enabled
      from public.organization_settings as settings
      where settings.organization_id = new.organization_id
    ),
    true
  ) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.cost_center_id is not null then
      raise exception 'Project Cost Centers are disabled for this workspace'
        using errcode = '23514';
    end if;

    return new;
  end if;

  if new.cost_center_id is distinct from old.cost_center_id then
    raise exception 'Project Cost Centers are disabled for this workspace'
      using errcode = '23514';
  end if;

  return new;
end
$$;

revoke all on function public.enforce_project_cost_center_setting()
  from public, anon, authenticated;
grant execute on function public.enforce_project_cost_center_setting()
  to service_role;

create trigger sourcing_events_enforce_project_cost_center_setting
before insert or update on public.sourcing_events
for each row execute function public.enforce_project_cost_center_setting();

commit;
