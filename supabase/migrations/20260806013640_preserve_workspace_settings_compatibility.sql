begin;

create function public.update_workspace_settings(
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
begin
  perform public.update_workspace_settings(
    p_organization_name,
    p_full_name,
    p_currency_code,
    p_locale,
    p_timezone,
    p_fiscal_year_start_month,
    p_date_format,
    p_default_recognition_method,
    p_require_baseline,
    p_hard_reduction_approval_threshold,
    coalesce(
      (
        select settings.support_projects_enabled
        from public.organization_settings as settings
        where settings.organization_id = public.current_org_id()
      ),
      true
    )
  );
end
$$;

comment on function public.update_workspace_settings(
  text,
  text,
  text,
  text,
  text,
  integer,
  text,
  text,
  boolean,
  numeric
) is 'Compatibility overload for deployed clients that predate the Support project setting.';

revoke all on function public.update_workspace_settings(
  text,
  text,
  text,
  text,
  text,
  integer,
  text,
  text,
  boolean,
  numeric
) from public, anon;

grant execute on function public.update_workspace_settings(
  text,
  text,
  text,
  text,
  text,
  integer,
  text,
  text,
  boolean,
  numeric
) to authenticated, service_role;

commit;
