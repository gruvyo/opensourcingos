begin;

-- Supplier names are unique within a workspace, but the existing partial
-- index can be bypassed when a writer omits supplier_normalized_name. Before
-- enforcing the invariant, remove only surplus records that have no business
-- references. Keep the oldest record in each workspace/name group.
do $$
begin
  if exists (
    with ranked as (
      select
        s.id,
        row_number() over (
          partition by
            s.organization_id,
            btrim(regexp_replace(lower(s.supplier_name), '[^a-z0-9]+', ' ', 'g'))
          order by s.created_at, s.id
        ) as duplicate_rank
      from public.suppliers s
    )
    select 1
    from ranked r
    where r.duplicate_rank > 1
      and (
        exists (select 1 from public.supplier_offers o where o.supplier_id = r.id)
        or exists (select 1 from public.sourcing_events e where e.incumbent_supplier_id = r.id)
        or exists (select 1 from public.sourcing_events e where e.awarded_supplier_id = r.id)
        or exists (select 1 from public.awards a where a.supplier_id = r.id)
      )
  ) then
    raise exception 'Referenced duplicate suppliers must be merged before enforcing name uniqueness';
  end if;
end
$$;

with ranked as (
  select
    s.id,
    row_number() over (
      partition by
        s.organization_id,
        btrim(regexp_replace(lower(s.supplier_name), '[^a-z0-9]+', ' ', 'g'))
      order by s.created_at, s.id
    ) as duplicate_rank
  from public.suppliers s
)
delete from public.suppliers s
using ranked r
where s.id = r.id
  and r.duplicate_rank > 1;

-- Normalize at the database boundary so every writer follows the same rule,
-- including inline supplier creation in project and offer forms.
create or replace function public.set_supplier_normalized_name() returns trigger
  language plpgsql
  set search_path to 'pg_catalog', 'public'
as $$
begin
  new.supplier_name := btrim(new.supplier_name);
  new.supplier_normalized_name := btrim(
    regexp_replace(lower(new.supplier_name), '[^a-z0-9]+', ' ', 'g')
  );

  if new.supplier_normalized_name = '' then
    raise exception 'Supplier name must contain at least one letter or number'
      using errcode = '23514';
  end if;

  return new;
end
$$;

revoke all on function public.set_supplier_normalized_name() from public, anon, authenticated;
grant execute on function public.set_supplier_normalized_name() to service_role;

drop trigger if exists suppliers_normalize_name on public.suppliers;
create trigger suppliers_normalize_name
before insert or update on public.suppliers
for each row execute function public.set_supplier_normalized_name();

-- Fire the trigger for existing rows, then make bypassing normalization
-- impossible and replace the old nullable-only index with the full invariant.
update public.suppliers
set supplier_normalized_name = supplier_name
where supplier_normalized_name is distinct from btrim(
  regexp_replace(lower(supplier_name), '[^a-z0-9]+', ' ', 'g')
);

alter table public.suppliers
  alter column supplier_normalized_name set not null;

drop index if exists public.uq_suppliers_org_normalized_name;
create unique index uq_suppliers_org_normalized_name
  on public.suppliers (organization_id, supplier_normalized_name);

commit;
