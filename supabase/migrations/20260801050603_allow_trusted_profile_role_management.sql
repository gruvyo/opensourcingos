begin;

create or replace function public.prevent_profile_privilege_change() returns trigger
  language plpgsql
  set search_path to 'pg_catalog', 'public'
as $$
begin
  if current_user in ('anon', 'authenticated') then
    if new.organization_id is distinct from old.organization_id then
      raise exception 'organization_id cannot be changed by the user';
    end if;
    if new.role is distinct from old.role then
      raise exception 'role cannot be changed by the user';
    end if;
  end if;
  return new;
end
$$;

commit;
