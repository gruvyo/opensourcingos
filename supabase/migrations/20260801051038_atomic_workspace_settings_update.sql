begin;

create or replace function public.update_workspace_settings(
  p_organization_name text,
  p_full_name text,
  p_currency_code text,
  p_locale text,
  p_timezone text,
  p_fiscal_year_start_month integer,
  p_date_format text,
  p_default_recognition_method text,
  p_require_baseline boolean,
  p_hard_reduction_approval_threshold numeric
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
    updated_by = excluded.updated_by;
end
$$;

revoke all on function public.update_workspace_settings(text, text, text, text, text, integer, text, text, boolean, numeric)
  from public, anon;
grant execute on function public.update_workspace_settings(text, text, text, text, text, integer, text, text, boolean, numeric)
  to authenticated;

commit;
