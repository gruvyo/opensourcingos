begin;

-- Beta taxonomy reset: Type explains why the project exists; savings strategy
-- remains represented by baselines, offers, awards, and savings calculations.
insert into public.project_choice_options (
  organization_id, choice_type, project_type, label, active_flag, sort_order
)
select organization.id, choice.choice_type, choice.project_type, choice.label, true, choice.sort_order
from public.organizations as organization
cross join (
  values
    ('event_type', 'Sourcing', 'Contract Renewal', 10),
    ('event_type', 'Sourcing', 'New Purchase', 20),
    ('event_type', 'Sourcing', 'Mid-Contract Commercial Review', 30),
    ('event_type', 'Sourcing', 'Demand or Specification Change', 40),
    ('event_type', 'Sourcing', 'Supplier or Market Change', 50),
    ('event_type', 'Sourcing', 'Other Sourcing Initiative', 60),
    ('event_type', 'Support', 'Vendor Performance or Service Issue', 10),
    ('event_type', 'Support', 'Billing or Payment Issue', 20),
    ('event_type', 'Support', 'Contract Inquiry', 30),
    ('event_type', 'Support', 'Operational Request', 40),
    ('event_type', 'Support', 'Risk or Compliance Review', 50),
    ('event_type', 'Support', 'General Inquiry', 60),
    ('event_status', 'Sourcing', 'Pipeline', 10),
    ('event_status', 'Sourcing', 'Scoping & Strategy', 20),
    ('event_status', 'Sourcing', 'In Market', 30),
    ('event_status', 'Sourcing', 'Negotiation', 40),
    ('event_status', 'Sourcing', 'Award & Contracting', 50),
    ('event_status', 'Sourcing', 'Implementation', 60),
    ('event_status', 'Sourcing', 'Complete', 70),
    ('event_status', 'Sourcing', 'On Hold', 80),
    ('event_status', 'Sourcing', 'Cancelled', 90),
    ('event_status', 'Support', 'Not Started', 10),
    ('event_status', 'Support', 'In Progress', 20),
    ('event_status', 'Support', 'Pending', 30),
    ('event_status', 'Support', 'Complete', 40),
    ('event_status', 'Support', 'Cancelled', 50)
) as choice(choice_type, project_type, label, sort_order)
on conflict (
  organization_id,
  choice_type,
  (coalesce(project_type, '')),
  (lower(btrim(label)))
) do update set
  active_flag = true,
  sort_order = excluded.sort_order;

update public.sourcing_events
set event_type = case
  when project_type = 'Sourcing' then case
    when event_type in ('Renewal', 'Contract Renewal') then 'Contract Renewal'
    when event_type in ('Net New Purchase', 'New Purchase') then 'New Purchase'
    when event_type in (
      'Renegotiation', 'Payment Terms', 'Rebate / Credit', 'One-Time Fee Waiver',
      'Early Payment Discount', 'Mid-Contract Commercial Review'
    ) then 'Mid-Contract Commercial Review'
    when event_type in (
      'Demand Reduction', 'Specification Change', 'Specification Optimization',
      'Demand or Specification Change'
    ) then 'Demand or Specification Change'
    when event_type in (
      'Competitive Rebid', 'Supplier Consolidation', 'Market Index / Commodity',
      'Supplier or Market Change'
    ) then 'Supplier or Market Change'
    else 'Other Sourcing Initiative'
  end
  else case
    when event_type in (
      'Vendor Issue', 'Supplier Issue', 'Support Ticket',
      'Vendor Performance or Service Issue'
    ) then 'Vendor Performance or Service Issue'
    when event_type in ('Billing Dispute', 'Billing or Payment Issue') then 'Billing or Payment Issue'
    when event_type in ('Contract Question', 'Contract Inquiry') then 'Contract Inquiry'
    when event_type in ('Service Request', 'Operational Request') then 'Operational Request'
    when event_type in ('Compliance/Legal', 'Risk or Compliance Review') then 'Risk or Compliance Review'
    else 'General Inquiry'
  end
end;

update public.sourcing_events
set event_status = case
  when project_type = 'Sourcing' then case
    when event_status = 'Pipeline' then 'Pipeline'
    when event_status in (
      'Scoped', 'Discovery', 'Baseline Pending', 'Baseline Approved',
      'Scoping & Strategy'
    ) then 'Scoping & Strategy'
    when event_status in ('In Market', 'Sourcing') then 'In Market'
    when event_status = 'Negotiation' then 'Negotiation'
    when event_status in (
      'Award Recommended', 'Award Approved', 'Contracted', 'Award & Contracting'
    ) then 'Award & Contracting'
    when event_status in ('Implemented', 'Implementation') then 'Implementation'
    when event_status in ('Realized', 'Finance Validated', 'Closed', 'Complete') then 'Complete'
    when event_status in ('Hold', 'On Hold') then 'On Hold'
    else 'Cancelled'
  end
  else case
    when event_status = 'Not Started' then 'Not Started'
    when event_status = 'In Progress' then 'In Progress'
    when event_status in ('Hold', 'Pending') then 'Pending'
    when event_status = 'Complete' then 'Complete'
    else 'Cancelled'
  end
end;

delete from public.project_choice_options as choice
where choice.choice_type in ('event_type', 'event_status')
  and not exists (
    select 1
    from (
      values
        ('event_type', 'Sourcing', 'Contract Renewal'),
        ('event_type', 'Sourcing', 'New Purchase'),
        ('event_type', 'Sourcing', 'Mid-Contract Commercial Review'),
        ('event_type', 'Sourcing', 'Demand or Specification Change'),
        ('event_type', 'Sourcing', 'Supplier or Market Change'),
        ('event_type', 'Sourcing', 'Other Sourcing Initiative'),
        ('event_type', 'Support', 'Vendor Performance or Service Issue'),
        ('event_type', 'Support', 'Billing or Payment Issue'),
        ('event_type', 'Support', 'Contract Inquiry'),
        ('event_type', 'Support', 'Operational Request'),
        ('event_type', 'Support', 'Risk or Compliance Review'),
        ('event_type', 'Support', 'General Inquiry'),
        ('event_status', 'Sourcing', 'Pipeline'),
        ('event_status', 'Sourcing', 'Scoping & Strategy'),
        ('event_status', 'Sourcing', 'In Market'),
        ('event_status', 'Sourcing', 'Negotiation'),
        ('event_status', 'Sourcing', 'Award & Contracting'),
        ('event_status', 'Sourcing', 'Implementation'),
        ('event_status', 'Sourcing', 'Complete'),
        ('event_status', 'Sourcing', 'On Hold'),
        ('event_status', 'Sourcing', 'Cancelled'),
        ('event_status', 'Support', 'Not Started'),
        ('event_status', 'Support', 'In Progress'),
        ('event_status', 'Support', 'Pending'),
        ('event_status', 'Support', 'Complete'),
        ('event_status', 'Support', 'Cancelled')
    ) as expected(choice_type, project_type, label)
    where expected.choice_type = choice.choice_type
      and expected.project_type = choice.project_type
      and expected.label = choice.label
  );

commit;
