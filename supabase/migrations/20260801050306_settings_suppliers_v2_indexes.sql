begin;

create index if not exists idx_audit_log_actor
  on public.audit_log (actor_id);

create index if not exists idx_organization_settings_updated_by
  on public.organization_settings (updated_by);

-- Avoid recalculating auth.uid() for every candidate profile row.
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

commit;
