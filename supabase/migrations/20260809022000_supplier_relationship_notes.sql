begin;

create table public.supplier_notes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  supplier_id uuid not null,
  occurred_on date not null default current_date,
  body text not null,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  constraint supplier_notes_supplier_workspace_fkey
    foreign key (supplier_id, organization_id)
    references public.suppliers(id, organization_id)
    on delete cascade,
  constraint supplier_notes_body_not_blank check (length(btrim(body)) > 0),
  constraint supplier_notes_body_length check (char_length(body) <= 10000)
);

comment on table public.supplier_notes is
  'Append-only dated relationship context and risk evidence for one supplier.';

create index idx_supplier_notes_workspace_supplier_date
  on public.supplier_notes (organization_id, supplier_id, occurred_on desc, created_at desc);
create index idx_supplier_notes_created_by
  on public.supplier_notes (created_by);

alter table public.supplier_notes enable row level security;
alter table public.supplier_notes force row level security;

create policy supplier_notes_select on public.supplier_notes
for select to authenticated
using (organization_id = (select public.current_org_id()));

create policy supplier_notes_insert_by_editor on public.supplier_notes
for insert to authenticated
with check (
  organization_id = (select public.current_org_id())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = supplier_notes.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
);

create function public.stamp_supplier_note_actor()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  return new;
end
$$;

revoke all on function public.stamp_supplier_note_actor()
  from public, anon, authenticated;
grant execute on function public.stamp_supplier_note_actor()
  to service_role;

create trigger supplier_notes_stamp_actor
before insert on public.supplier_notes
for each row execute function public.stamp_supplier_note_actor();

revoke all on table public.supplier_notes from public, anon, authenticated;
grant select, insert on table public.supplier_notes to authenticated;
grant all on table public.supplier_notes to service_role;

commit;
