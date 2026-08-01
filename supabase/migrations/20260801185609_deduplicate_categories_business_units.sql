-- Consolidate duplicate master-data rows created by overlapping demo seeds.
-- Every dependent reference is repointed before a redundant row is removed.

begin;

create temporary table _category_merge_map on commit drop as
with scored as (
  select
    category.id,
    category.organization_id,
    lower(btrim(category.category_name)) as normalized_name,
    category.created_at,
    (
      (select count(*) from public.sourcing_events event where event.category_id = category.id)
      + (select count(*) from public.event_scope_lines line where line.category_id = category.id)
      + (select count(*) from public.categories child where child.parent_category_id = category.id)
    ) as reference_count
  from public.categories category
  where category.organization_id is not null
), ranked as (
  select
    id,
    first_value(id) over (
      partition by organization_id, normalized_name
      order by reference_count desc, created_at asc, id
    ) as canonical_id,
    count(*) over (partition by organization_id, normalized_name) as duplicate_count
  from scored
)
select id as duplicate_id, canonical_id
from ranked
where duplicate_count > 1
  and id <> canonical_id;

-- Preserve the oldest populated baseline default when duplicate definitions
-- disagree, while keeping the most-referenced row as the canonical identity.
with oldest_defaults as (
  select distinct on (organization_id, lower(btrim(category_name)))
    organization_id,
    lower(btrim(category_name)) as normalized_name,
    default_baseline_type
  from public.categories
  where organization_id is not null
    and default_baseline_type is not null
  order by organization_id, lower(btrim(category_name)), created_at asc, id
), canonical_categories as (
  select distinct map.canonical_id
  from _category_merge_map map
)
update public.categories canonical
set default_baseline_type = defaults.default_baseline_type
from canonical_categories selected
join oldest_defaults defaults
  on true
where canonical.id = selected.canonical_id
  and canonical.organization_id = defaults.organization_id
  and lower(btrim(canonical.category_name)) = defaults.normalized_name;

update public.sourcing_events event
set category_id = map.canonical_id
from _category_merge_map map
where event.category_id = map.duplicate_id;

update public.event_scope_lines line
set category_id = map.canonical_id
from _category_merge_map map
where line.category_id = map.duplicate_id;

update public.categories child
set parent_category_id = map.canonical_id
from _category_merge_map map
where child.parent_category_id = map.duplicate_id;

delete from public.categories category
using _category_merge_map map
where category.id = map.duplicate_id;

create temporary table _business_unit_merge_map on commit drop as
with scored as (
  select
    unit.id,
    unit.organization_id,
    lower(btrim(unit.business_unit_name)) as normalized_name,
    unit.created_at,
    (
      (select count(*) from public.sourcing_events event where event.business_unit_id = unit.id)
      + (select count(*) from public.cost_centers center where center.business_unit_id = unit.id)
      + (select count(*) from public.business_units child where child.parent_business_unit_id = unit.id)
    ) as reference_count
  from public.business_units unit
  where unit.organization_id is not null
), ranked as (
  select
    id,
    first_value(id) over (
      partition by organization_id, normalized_name
      order by reference_count desc, created_at asc, id
    ) as canonical_id,
    count(*) over (partition by organization_id, normalized_name) as duplicate_count
  from scored
)
select id as duplicate_id, canonical_id
from ranked
where duplicate_count > 1
  and id <> canonical_id;

update public.sourcing_events event
set business_unit_id = map.canonical_id
from _business_unit_merge_map map
where event.business_unit_id = map.duplicate_id;

update public.cost_centers center
set business_unit_id = map.canonical_id
from _business_unit_merge_map map
where center.business_unit_id = map.duplicate_id;

update public.business_units child
set parent_business_unit_id = map.canonical_id
from _business_unit_merge_map map
where child.parent_business_unit_id = map.duplicate_id;

delete from public.business_units unit
using _business_unit_merge_map map
where unit.id = map.duplicate_id;

create unique index uq_categories_org_normalized_name
  on public.categories (organization_id, lower(btrim(category_name)))
  where organization_id is not null;

create unique index uq_business_units_org_normalized_name
  on public.business_units (organization_id, lower(btrim(business_unit_name)))
  where organization_id is not null;

commit;
