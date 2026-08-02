-- Entirely fictional, deterministic demo data for local development and tests.
-- Do not replace this with a production export or confidential sourcing data.

insert into public.organizations (id, name, is_demo_template)
values (
  '00000000-0000-4000-8000-000000000001',
  'Demo template (do not log in)',
  true
);

insert into public.organization_settings (
  organization_id,
  currency_code,
  locale,
  timezone,
  fiscal_year_start_month,
  date_format,
  default_recognition_method
)
values (
  '00000000-0000-4000-8000-000000000001',
  'USD',
  'en-US',
  'America/Chicago',
  1,
  'MMM D, YYYY',
  'monthly'
);

insert into public.categories (id, organization_id, category_name, default_baseline_type)
values (
  '00000000-0000-4000-8000-000000000011',
  '00000000-0000-4000-8000-000000000001',
  'Enterprise Software',
  'Current Contract'
);

insert into public.business_units (id, organization_id, business_unit_name)
values (
  '00000000-0000-4000-8000-000000000012',
  '00000000-0000-4000-8000-000000000001',
  'Example Operations'
);

insert into public.suppliers (
  id,
  organization_id,
  supplier_name,
  supplier_normalized_name,
  supplier_status,
  preferred_flag,
  risk_rating,
  country_code,
  notes
)
values (
  '00000000-0000-4000-8000-000000000013',
  '00000000-0000-4000-8000-000000000001',
  'Example Technology Co.',
  'example technology co',
  'Active',
  true,
  'Low',
  'US',
  'Fictional supplier used only for the public demo.'
);

insert into public.sourcing_events (
  id,
  organization_id,
  event_name,
  event_description,
  event_type,
  category_id,
  business_unit_id,
  incumbent_supplier_id,
  awarded_supplier_id,
  event_status,
  currency_code,
  event_start_date,
  project_due_date,
  contract_start_date,
  contract_end_date,
  project_type
)
values (
  '00000000-0000-4000-8000-000000000021',
  '00000000-0000-4000-8000-000000000001',
  'ERP Platform Renewal',
  'Fictional reference deal demonstrating the three-anchor savings chain.',
  'Renewal',
  '00000000-0000-4000-8000-000000000011',
  '00000000-0000-4000-8000-000000000012',
  '00000000-0000-4000-8000-000000000013',
  '00000000-0000-4000-8000-000000000013',
  'Contracted',
  'USD',
  '2026-01-15',
  '2026-07-31',
  '2026-08-01',
  '2029-07-31',
  'Sourcing'
);

insert into public.project_updates (
  id,
  organization_id,
  event_id,
  body
)
values (
  '00000000-0000-4000-8000-000000000022',
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000021',
  'Fictional agreement completed and ready for savings tracking.'
);

insert into public.baselines (
  id,
  organization_id,
  event_id,
  baseline_name,
  baseline_type,
  baseline_source,
  baseline_currency_code,
  baseline_total_amount,
  baseline_normalized_amount,
  baseline_term_months,
  is_selected
)
values (
  '00000000-0000-4000-8000-000000000031',
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000021',
  'Current Contract · Fictional reference',
  'Current Contract',
  'Fictional current contract',
  'USD',
  1000000,
  1000000,
  12,
  true
);

insert into public.supplier_offers (
  id,
  organization_id,
  event_id,
  supplier_id,
  offer_type,
  offer_round,
  offer_date,
  offer_currency_code,
  offer_total_amount,
  offer_term_months,
  offer_role
)
values
  (
    '00000000-0000-4000-8000-000000000041',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000021',
    '00000000-0000-4000-8000-000000000013',
    'Initial',
    1,
    '2026-02-01',
    'USD',
    1200000,
    12,
    'opening'
  ),
  (
    '00000000-0000-4000-8000-000000000042',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000021',
    '00000000-0000-4000-8000-000000000013',
    'Final',
    2,
    '2026-06-15',
    'USD',
    2700000,
    36,
    'final'
  );

insert into public.savings_calculations (
  id,
  organization_id,
  event_id,
  baseline_id,
  calculation_name,
  savings_type,
  baseline_total_amount,
  award_total_amount,
  gross_savings_amount,
  savings_percentage,
  net_savings_amount,
  calculation_status,
  savings_start_date,
  savings_end_date,
  cost_reduction_amount,
  cost_avoidance_amount,
  opening_proposal_amount,
  schedule_start_month,
  schedule_start_year,
  schedule_period_type,
  schedule_period_count
)
values (
  '00000000-0000-4000-8000-000000000051',
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000021',
  '00000000-0000-4000-8000-000000000031',
  'ERP Platform Renewal savings',
  'Cost Reduction',
  3000000,
  2700000,
  900000,
  30,
  900000,
  'contracted',
  '2026-08-01',
  '2029-07-31',
  300000,
  600000,
  3600000,
  8,
  2026,
  'annual',
  3
);

insert into public.savings_periods (
  id,
  organization_id,
  event_id,
  savings_calculation_id,
  period_number,
  period_month,
  period_year,
  period_months,
  baseline_amount,
  opening_amount,
  final_amount,
  cost_reduction_amount,
  cost_avoidance_amount,
  total_savings_amount
)
values
  (
    '00000000-0000-4000-8000-000000000061',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000021',
    '00000000-0000-4000-8000-000000000051',
    1, 8, 2026, 12, 1000000, 1200000, 900000, 100000, 200000, 300000
  ),
  (
    '00000000-0000-4000-8000-000000000062',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000021',
    '00000000-0000-4000-8000-000000000051',
    2, 8, 2027, 12, 1000000, 1200000, 900000, 100000, 200000, 300000
  ),
  (
    '00000000-0000-4000-8000-000000000063',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000021',
    '00000000-0000-4000-8000-000000000051',
    3, 8, 2028, 12, 1000000, 1200000, 900000, 100000, 200000, 300000
  );
