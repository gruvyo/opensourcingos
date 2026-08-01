-- P13: lock down database functions exposed by the Data API.
--
-- clone_org_data() bypasses RLS so the signup trigger can copy the demo
-- template into a new workspace. It must never be callable by a browser user:
-- its arguments allow the caller to choose the source and target workspace.
-- handle_new_user() is likewise trigger-only. current_org_id() deliberately
-- remains executable by authenticated users because every organization policy
-- calls it; it remains SECURITY DEFINER to avoid recursive RLS on profiles.

begin;

revoke all on function public.clone_org_data(uuid, uuid, uuid)
  from public, anon, authenticated;

revoke all on function public.handle_new_user()
  from public, anon, authenticated;

revoke all on function public.current_org_id()
  from public, anon;
grant execute on function public.current_org_id()
  to authenticated;

-- Pin search paths for all application-owned trigger/helper functions. This
-- prevents a caller-controlled object from shadowing an unqualified name.
alter function public.clone_org_data(uuid, uuid, uuid)
  set search_path = pg_catalog, public;
alter function public.current_org_id()
  set search_path = pg_catalog, public;
alter function public.handle_new_user()
  set search_path = pg_catalog, public;
alter function public.prevent_profile_privilege_change()
  set search_path = pg_catalog, public;
alter function public.update_updated_at()
  set search_path = pg_catalog, public;

commit;
