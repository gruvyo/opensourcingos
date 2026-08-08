begin;

-- Beta taxonomy reset: Categories classify what is being bought, Business
-- Units classify the internal demand owner, and Cost Centers remain empty
-- until an administrator adds the organization's own accounting values.
create temporary table _savings_before on commit drop as
select id, to_jsonb(calculation) as row_data
from public.savings_calculations as calculation;

do $$
begin
  if exists (select 1 from public.categories where parent_category_id is not null) then
    raise exception 'Category reset requires a separate hierarchy migration';
  end if;

  if exists (select 1 from public.business_units where parent_business_unit_id is not null) then
    raise exception 'Business Unit reset requires a separate hierarchy migration';
  end if;

  if exists (
    select 1
    from public.categories
    where category_name not in (
      'Consumer Products', 'Corporate Services', 'Digital Commerce', 'Facilities',
      'IT Software', 'Lab & Scientific', 'Logistics', 'Marketing', 'MRO',
      'Packaging', 'Professional Services', 'Retail Ops',
      'Technology & Telecom', 'Marketing & Creative', 'Facilities & Real Estate',
      'Logistics & Transportation', 'MRO & Industrial Supplies',
      'Laboratory & Scientific Equipment'
    )
  ) then
    raise exception 'Category reset found an unexpected beta value';
  end if;

  if exists (
    select 1
    from public.business_units
    where business_unit_name not in (
      'Corporate Services', 'Ecommerce', 'Finance', 'HR', 'IT & Digital',
      'Legal', 'Manufacturing', 'Marketing', 'Merchandising', 'Operations',
      'Real Estate', 'Retail', 'Supply Chain', 'Technology'
    )
  ) then
    raise exception 'Business Unit reset found an unexpected beta value';
  end if;
end
$$;

insert into public.categories (
  organization_id, category_name, default_baseline_type, active_flag
)
select organization.id, category.label, category.default_baseline_type, true
from public.organizations as organization
cross join (
  values
    ('Technology & Telecom', 'Current Contract'),
    ('Professional Services', 'Current Contract'),
    ('Marketing & Creative', 'Prior 12-Month Actual'),
    ('Facilities & Real Estate', 'Current Contract'),
    ('Logistics & Transportation', 'Prior 12-Month Actual'),
    ('MRO & Industrial Supplies', 'Prior 12-Month Actual'),
    ('Packaging', 'Current Contract'),
    ('Laboratory & Scientific Equipment', 'Current Contract')
) as category(label, default_baseline_type)
on conflict (organization_id, (lower(btrim(category_name))))
where organization_id is not null do update set
  default_baseline_type = excluded.default_baseline_type,
  active_flag = true;

with desired as (
  select
    event.id,
    event.organization_id,
    case
      when event.event_name in (
        'ERP Platform Renewal', 'Network Infrastructure - 5 Year',
        'Network Optimization Services', 'Wireless Redundant Internet Service'
      ) then 'Technology & Telecom'
      when event.event_name in (
        'ERP Implementation Consulting', 'Managed Services Consulting - 18 Month'
      ) then 'Professional Services'
      when event.event_name = 'Marketing Agency Retainer' then 'Marketing & Creative'
      when event.event_name = 'Facilities Services Renewal' then 'Facilities & Real Estate'
      when event.event_name = 'Freight Carrier Rebid' then 'Logistics & Transportation'
      when event.event_name = 'MRO Consumables Consolidation' then 'MRO & Industrial Supplies'
      when event.event_name = 'Lab Instrumentation - Net New' then 'Laboratory & Scientific Equipment'
      else case category.category_name
        when 'IT Software' then 'Technology & Telecom'
        when 'Digital Commerce' then 'Technology & Telecom'
        when 'Professional Services' then 'Professional Services'
        when 'Marketing' then 'Marketing & Creative'
        when 'Facilities' then 'Facilities & Real Estate'
        when 'Corporate Services' then 'Professional Services'
        when 'Logistics' then 'Logistics & Transportation'
        when 'MRO' then 'MRO & Industrial Supplies'
        when 'Packaging' then 'Packaging'
        when 'Consumer Products' then 'Packaging'
        when 'Lab & Scientific' then 'Laboratory & Scientific Equipment'
        when 'Retail Ops' then 'MRO & Industrial Supplies'
        else category.category_name
      end
    end as label
  from public.sourcing_events as event
  left join public.categories as category on category.id = event.category_id
)
update public.sourcing_events as event
set category_id = target.id
from desired
join public.categories as target
  on target.organization_id = desired.organization_id
 and target.category_name = desired.label
where event.id = desired.id
  and event.category_id is distinct from target.id;

with desired as (
  select
    line.id,
    line.organization_id,
    case category.category_name
      when 'IT Software' then 'Technology & Telecom'
      when 'Digital Commerce' then 'Technology & Telecom'
      when 'Professional Services' then 'Professional Services'
      when 'Marketing' then 'Marketing & Creative'
      when 'Facilities' then 'Facilities & Real Estate'
      when 'Corporate Services' then 'Professional Services'
      when 'Logistics' then 'Logistics & Transportation'
      when 'MRO' then 'MRO & Industrial Supplies'
      when 'Packaging' then 'Packaging'
      when 'Consumer Products' then 'Packaging'
      when 'Lab & Scientific' then 'Laboratory & Scientific Equipment'
      when 'Retail Ops' then 'MRO & Industrial Supplies'
      else category.category_name
    end as label
  from public.event_scope_lines as line
  join public.categories as category on category.id = line.category_id
)
update public.event_scope_lines as line
set category_id = target.id
from desired
join public.categories as target
  on target.organization_id = desired.organization_id
 and target.category_name = desired.label
where line.id = desired.id
  and line.category_id is distinct from target.id;

delete from public.categories
where category_name not in (
  'Technology & Telecom', 'Professional Services', 'Marketing & Creative',
  'Facilities & Real Estate', 'Logistics & Transportation',
  'MRO & Industrial Supplies', 'Packaging',
  'Laboratory & Scientific Equipment'
);

insert into public.business_units (
  organization_id, business_unit_name, active_flag
)
select organization.id, unit.label, true
from public.organizations as organization
cross join (
  values ('Technology'), ('Operations'), ('Manufacturing'), ('Corporate Services')
) as unit(label)
on conflict (organization_id, (lower(btrim(business_unit_name))))
where organization_id is not null do update set
  active_flag = true;

with desired as (
  select
    event.id,
    event.organization_id,
    case
      when event.event_name in (
        'ERP Platform Renewal', 'Network Infrastructure - 5 Year',
        'ERP Implementation Consulting', 'Network Optimization Services',
        'Wireless Redundant Internet Service'
      ) then 'Technology'
      when event.event_name = 'Lab Instrumentation - Net New' then 'Manufacturing'
      when event.event_name in ('Freight Carrier Rebid', 'MRO Consumables Consolidation') then 'Operations'
      when event.event_name in (
        'Facilities Services Renewal', 'Marketing Agency Retainer',
        'Managed Services Consulting - 18 Month', 'Contract Review - Legal Question'
      ) then 'Corporate Services'
      else case unit.business_unit_name
        when 'IT & Digital' then 'Technology'
        when 'Technology' then 'Technology'
        when 'Operations' then 'Operations'
        when 'Ecommerce' then 'Operations'
        when 'Merchandising' then 'Operations'
        when 'Retail' then 'Operations'
        when 'Supply Chain' then 'Operations'
        when 'Manufacturing' then 'Manufacturing'
        else 'Corporate Services'
      end
    end as label
  from public.sourcing_events as event
  left join public.business_units as unit on unit.id = event.business_unit_id
)
update public.sourcing_events as event
set business_unit_id = target.id
from desired
join public.business_units as target
  on target.organization_id = desired.organization_id
 and target.business_unit_name = desired.label
where event.id = desired.id
  and event.business_unit_id is not null
  and event.business_unit_id is distinct from target.id;

with desired as (
  select
    center.id,
    center.organization_id,
    case unit.business_unit_name
      when 'IT & Digital' then 'Technology'
      when 'Technology' then 'Technology'
      when 'Operations' then 'Operations'
      when 'Ecommerce' then 'Operations'
      when 'Merchandising' then 'Operations'
      when 'Retail' then 'Operations'
      when 'Supply Chain' then 'Operations'
      when 'Manufacturing' then 'Manufacturing'
      else 'Corporate Services'
    end as label
  from public.cost_centers as center
  join public.business_units as unit on unit.id = center.business_unit_id
)
update public.cost_centers as center
set business_unit_id = target.id
from desired
join public.business_units as target
  on target.organization_id = desired.organization_id
 and target.business_unit_name = desired.label
where center.id = desired.id
  and center.business_unit_id is distinct from target.id;

delete from public.business_units
where business_unit_name not in (
  'Technology', 'Operations', 'Manufacturing', 'Corporate Services'
);

insert into public.audit_log (
  organization_id, actor_id, entity_type, entity_id, action, after_data
)
select
  organization.id,
  null,
  'project_classification_reset',
  organization.id,
  'update',
  jsonb_build_object(
    'scope', 'category_business_unit_cost_center_defaults',
    'categories', jsonb_build_array(
      'Technology & Telecom', 'Professional Services', 'Marketing & Creative',
      'Facilities & Real Estate', 'Logistics & Transportation',
      'MRO & Industrial Supplies', 'Packaging',
      'Laboratory & Scientific Equipment'
    ),
    'business_units', jsonb_build_array(
      'Technology', 'Operations', 'Manufacturing', 'Corporate Services'
    ),
    'cost_center_policy', 'organization_managed_no_generic_defaults'
  )
from public.organizations as organization;

do $$
begin
  if exists (
    (select id, row_data from _savings_before
     except
     select id, to_jsonb(calculation) from public.savings_calculations as calculation)
    union all
    (select id, to_jsonb(calculation) from public.savings_calculations as calculation
     except
     select id, row_data from _savings_before)
  ) then
    raise exception 'Category and Business Unit reset changed savings data';
  end if;
end
$$;

commit;
