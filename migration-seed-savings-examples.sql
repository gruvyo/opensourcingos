-- Migration: Seed 5 complete sourcing projects with correct savings examples
-- Each project demonstrates a different savings type with mathematically correct values
-- Run in Supabase SQL Editor one statement at a time if needed

DO $$
DECLARE
  org_id UUID;
  user_id UUID;
  event_id UUID;
  baseline_id UUID;
  award_id UUID;
  offer_id UUID;
BEGIN
  SELECT id INTO org_id FROM organizations LIMIT 1;
  SELECT id INTO user_id FROM profiles LIMIT 1;

  IF org_id IS NULL THEN
    RAISE EXCEPTION 'No organization found';
  END IF;

  -- ============================================
  -- PROJECT 1: CRM Software Renewal (Cost Reduction)
  -- ============================================
  -- Baseline: $600,000/yr (current contract, 500 licenses @ $1,000 + $100k support)
  -- Award: $570,000/yr (500 licenses @ $950 + $95k support — actual price reduction)
  -- Cost Reduction = $600,000 - $570,000 = $30,000/yr
  -- Cost Avoidance = $0
  -- Period: 2026-04-01 to 2028-03-31 (2 years)
  -- Total savings over 2 years = $60,000

  IF NOT EXISTS (SELECT 1 FROM sourcing_events WHERE event_name = 'CRM Software Renewal — Acme Software') THEN
    INSERT INTO sourcing_events (
      organization_id, event_name, event_description, event_type, project_type,
      sourcing_method, event_status, buyer_name, notes,
      category_id, business_unit_id, cost_center_id, incumbent_supplier_id,
      currency_code, fx_rate_to_usd,
      event_start_date, event_close_date, contract_start_date, contract_end_date,
      procurement_owner_id, created_by, updated_by
    )
    SELECT
      org_id,
      'CRM Software Renewal — Acme Software',
      'Annual renewal of CRM platform. Negotiated 5% unit price reduction on 500 enterprise licenses and support.',
      'Renewal', 'Sourcing', 'Negotiated Renewal', 'Contracted', 'Jane Smith',
      'Incumbent proposed 12% uplift. Negotiated to a 5% reduction from current contract price. 2-year commitment.',
      (SELECT id FROM categories WHERE organization_id = org_id AND category_name = 'Software & SaaS' LIMIT 1),
      (SELECT id FROM business_units WHERE organization_id = org_id AND business_unit_name = 'Sales & Marketing' LIMIT 1),
      (SELECT id FROM cost_centers WHERE organization_id = org_id AND cost_center_name = 'MKT-100 Advertising' LIMIT 1),
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'Acme Software Inc.' LIMIT 1),
      'USD', 1.0,
      '2026-01-15', '2026-03-30', '2026-04-01', '2028-03-31',
      user_id, user_id, user_id;

    SELECT id INTO event_id FROM sourcing_events WHERE event_name = 'CRM Software Renewal — Acme Software' LIMIT 1;

    -- Scope Lines
    INSERT INTO event_scope_lines (event_id, line_number, item_service_name, uom, quantity, organization_id, created_by)
    VALUES
      (event_id, 1, 'CRM Platform Licenses — Enterprise', 'Each', 500, org_id, user_id),
      (event_id, 2, 'Premium Support Package', 'Each', 1, org_id, user_id);

    -- Baseline: $600,000/yr
    INSERT INTO baselines (
      event_id, baseline_name, baseline_type, baseline_total_amount,
      baseline_normalized_amount, baseline_lock_status,
      official_for_hard_savings, official_for_cost_avoidance,
      baseline_period_start, baseline_period_end,
      organization_id, created_by
    )
    VALUES (
      event_id, 'Current Contract Baseline (FY25)', 'Current Contract', 600000,
      600000, 'Locked', true, true,
      '2025-04-01', '2026-03-31', org_id, user_id
    )
    RETURNING id INTO baseline_id;

    INSERT INTO baseline_lines (
      baseline_id, scope_line_id, line_number, baseline_unit_price,
      baseline_quantity, baseline_extended_amount, organization_id, created_by
    )
    VALUES
      (baseline_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 1000, 500, 500000, org_id, user_id),
      (baseline_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 100000, 1, 100000, org_id, user_id);

    -- Final Offer: $570,000/yr (500 @ $950 = $475k + $95k support)
    INSERT INTO supplier_offers (
      event_id, supplier_id, offer_type, offer_round, offer_date,
      offer_total_amount, offer_valid_until, compliant_bid_flag,
      selected_for_award_flag, notes, organization_id, created_by
    )
    VALUES (
      event_id,
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'Acme Software Inc.' LIMIT 1),
      'Final', 3, '2026-03-20', 570000, '2026-04-15', true, true,
      'Final negotiated offer. 5% reduction on license unit price and support. 2-year commitment.',
      org_id, user_id
    )
    RETURNING id INTO offer_id;

    INSERT INTO supplier_offer_lines (
      offer_id, scope_line_id, line_number, offered_unit_price,
      offered_quantity, offered_extended_amount, organization_id, created_by
    )
    VALUES
      (offer_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 950, 500, 475000, org_id, user_id),
      (offer_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 95000, 1, 95000, org_id, user_id);

    -- Award
    INSERT INTO awards (
      event_id, supplier_id, offer_id, award_name, award_total_amount,
      award_status, award_date, organization_id, created_by
    )
    VALUES (
      event_id,
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'Acme Software Inc.' LIMIT 1),
      offer_id, 'Award — Acme Software (Final)', 570000,
      'Approved', '2026-03-25', org_id, user_id
    )
    RETURNING id INTO award_id;

    INSERT INTO award_lines (
      award_id, scope_line_id, line_number, awarded_unit_price,
      awarded_quantity, awarded_extended_amount, organization_id, created_by
    )
    VALUES
      (award_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 950, 500, 475000, org_id, user_id),
      (award_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 95000, 1, 95000, org_id, user_id);

    -- Savings Calculation: Cost Reduction
    -- Gross = $600k - $570k = $30,000/yr
    -- Cost Reduction = $30,000 (actual price went down)
    -- Cost Avoidance = $0
    -- 2-year period: 2026-04-01 to 2028-03-31
    INSERT INTO savings_calculations (
      event_id, baseline_id, award_id, calculation_name, savings_type,
      baseline_total_amount, award_total_amount,
      gross_savings_amount, savings_percentage, net_savings_amount,
      cost_reduction_amount, cost_avoidance_amount,
      savings_start_date, savings_end_date,
      calculation_status, organization_id, created_by
    )
    VALUES (
      event_id, baseline_id, award_id,
      'Cost Reduction — 5% Unit Price Reduction', 'Cost Reduction',
      600000, 570000,
      30000, 5.0, 30000,
      30000, 0,
      '2026-04-01', '2028-03-31',
      'contracted', org_id, user_id
    );
  END IF;

  -- ============================================
  -- PROJECT 2: Cloud Hosting Cost Avoidance
  -- ============================================
  -- Supplier proposed 15% increase. Negotiated to 3%.
  -- Baseline: $500,000/yr (current contract)
  -- Opening offer (what they WOULD have charged): $575,000/yr (15% increase)
  -- Award: $515,000/yr (3% increase)
  -- Cost Reduction = $0 (price went UP, not down — no actual bottom-line reduction)
  -- Cost Avoidance = $575,000 - $515,000 = $60,000/yr (avoided the 15% increase, only paid 3%)
  -- Period: 2026-06-01 to 2028-05-31 (2 years)

  IF NOT EXISTS (SELECT 1 FROM sourcing_events WHERE event_name = 'Cloud Hosting Renewal — TechCloud Solutions') THEN
    INSERT INTO sourcing_events (
      organization_id, event_name, event_description, event_type, project_type,
      sourcing_method, event_status, buyer_name, notes,
      category_id, business_unit_id, cost_center_id, incumbent_supplier_id,
      currency_code, fx_rate_to_usd,
      event_start_date, event_close_date, contract_start_date, contract_end_date,
      procurement_owner_id, created_by, updated_by
    )
    SELECT
      org_id,
      'Cloud Hosting Renewal — TechCloud Solutions',
      'Cloud hosting renewal. Supplier proposed 15% increase. Negotiated to 3% with 2-year commitment.',
      'Renegotiation', 'Sourcing', 'Negotiated Renewal', 'Contracted', 'John Davis',
      'TechCloud proposed 15% uplift citing infrastructure costs. Leveraged competitive quotes from DataSync Systems. Negotiated to 3% increase with 2-year commitment.',
      (SELECT id FROM categories WHERE organization_id = org_id AND category_name = 'Cloud Infrastructure' LIMIT 1),
      (SELECT id FROM business_units WHERE organization_id = org_id AND business_unit_name = 'IT / Infrastructure' LIMIT 1),
      (SELECT id FROM cost_centers WHERE organization_id = org_id AND cost_center_name = 'IT-200 Networking' LIMIT 1),
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'TechCloud Solutions' LIMIT 1),
      'USD', 1.0,
      '2026-03-01', '2026-05-15', '2026-06-01', '2028-05-31',
      user_id, user_id, user_id;

    SELECT id INTO event_id FROM sourcing_events WHERE event_name = 'Cloud Hosting Renewal — TechCloud Solutions' LIMIT 1;

    INSERT INTO event_scope_lines (event_id, line_number, item_service_name, uom, quantity, organization_id, created_by)
    VALUES
      (event_id, 1, 'Cloud Hosting — Production Instances', 'Each', 50, org_id, user_id),
      (event_id, 2, 'Cloud Hosting — Dev/Staging Instances', 'Each', 20, org_id, user_id);

    -- Baseline: $500,000/yr (current contract)
    INSERT INTO baselines (
      event_id, baseline_name, baseline_type, baseline_total_amount,
      baseline_normalized_amount, baseline_lock_status,
      official_for_hard_savings, official_for_cost_avoidance,
      baseline_period_start, baseline_period_end,
      organization_id, created_by
    )
    VALUES (
      event_id, 'Current Contract Baseline', 'Current Contract', 500000,
      500000, 'Locked', false, true,
      '2025-06-01', '2026-05-31', org_id, user_id
    )
    RETURNING id INTO baseline_id;

    INSERT INTO baseline_lines (
      baseline_id, scope_line_id, line_number, baseline_unit_price,
      baseline_quantity, baseline_extended_amount, organization_id, created_by
    )
    VALUES
      (baseline_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 8000, 50, 400000, org_id, user_id),
      (baseline_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 5000, 20, 100000, org_id, user_id);

    -- Initial Offer: $575,000 (15% increase — what they WOULD have charged)
    INSERT INTO supplier_offers (
      event_id, supplier_id, offer_type, offer_round, offer_date,
      offer_total_amount, offer_valid_until, compliant_bid_flag,
      notes, organization_id, created_by
    )
    VALUES (
      event_id,
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'TechCloud Solutions' LIMIT 1),
      'Initial', 1, '2026-03-15', 575000, '2026-04-30', true,
      'Opening offer. 15% increase citing infrastructure cost increases.',
      org_id, user_id
    )
    RETURNING id INTO offer_id;

    INSERT INTO supplier_offer_lines (
      offer_id, scope_line_id, line_number, offered_unit_price,
      offered_quantity, offered_extended_amount, organization_id, created_by
    )
    VALUES
      (offer_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 9200, 50, 460000, org_id, user_id),
      (offer_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 5750, 20, 115000, org_id, user_id);

    -- Final Offer: $515,000 (3% increase)
    INSERT INTO supplier_offers (
      event_id, supplier_id, offer_type, offer_round, offer_date,
      offer_total_amount, offer_valid_until, compliant_bid_flag,
      selected_for_award_flag, notes, organization_id, created_by
    )
    VALUES (
      event_id,
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'TechCloud Solutions' LIMIT 1),
      'Final', 2, '2026-05-01', 515000, '2026-06-15', true, true,
      'Final negotiated offer. 3% increase. 2-year commitment.',
      org_id, user_id
    )
    RETURNING id INTO offer_id;

    INSERT INTO supplier_offer_lines (
      offer_id, scope_line_id, line_number, offered_unit_price,
      offered_quantity, offered_extended_amount, organization_id, created_by
    )
    VALUES
      (offer_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 8240, 50, 412000, org_id, user_id),
      (offer_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 5150, 20, 103000, org_id, user_id);

    -- Award: $515,000
    INSERT INTO awards (
      event_id, supplier_id, offer_id, award_name, award_total_amount,
      award_status, award_date, organization_id, created_by
    )
    VALUES (
      event_id,
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'TechCloud Solutions' LIMIT 1),
      offer_id, 'Award — TechCloud (Final)', 515000,
      'Approved', '2026-05-10', org_id, user_id
    )
    RETURNING id INTO award_id;

    INSERT INTO award_lines (
      award_id, scope_line_id, line_number, awarded_unit_price,
      awarded_quantity, awarded_extended_amount, organization_id, created_by
    )
    VALUES
      (award_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 8240, 50, 412000, org_id, user_id),
      (award_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 5150, 20, 103000, org_id, user_id);

    -- Savings Calculation: Cost Avoidance
    -- Cost Reduction = $0 (price went UP from $500k to $515k — no actual reduction)
    -- Cost Avoidance = $575k (opening offer) - $515k (award) = $60,000/yr
    -- This is what we WOULD have paid minus what we ARE paying
    INSERT INTO savings_calculations (
      event_id, baseline_id, award_id, calculation_name, savings_type,
      baseline_total_amount, award_total_amount,
      gross_savings_amount, savings_percentage, net_savings_amount,
      cost_reduction_amount, cost_avoidance_amount,
      savings_start_date, savings_end_date,
      calculation_status, organization_id, created_by
    )
    VALUES (
      event_id, baseline_id, award_id,
      'Cost Avoidance — Negotiated 3% vs 15% Increase', 'Cost Avoidance',
      575000, 515000,
      60000, 10.43, 60000,
      0, 60000,
      '2026-06-01', '2028-05-31',
      'contracted', org_id, user_id
    );
  END IF;

  -- ============================================
  -- PROJECT 3: Freight Contract Competitive Bid (Cost Reduction)
  -- ============================================
  -- Baseline: $800,000/yr (current incumbent)
  -- Award: $680,000/yr (new supplier, lower bid)
  -- Cost Reduction = $800k - $680k = $120,000/yr
  -- Period: 2026-07-01 to 2029-06-30 (3 years)

  IF NOT EXISTS (SELECT 1 FROM sourcing_events WHERE event_name = 'Freight Contract Competitive Bid — Global Freight') THEN
    INSERT INTO sourcing_events (
      organization_id, event_name, event_description, event_type, project_type,
      sourcing_method, event_status, buyer_name, notes,
      category_id, business_unit_id, cost_center_id, incumbent_supplier_id,
      currency_code, fx_rate_to_usd,
      event_start_date, event_close_date, contract_start_date, contract_end_date,
      procurement_owner_id, created_by, updated_by
    )
    SELECT
      org_id,
      'Freight Contract Competitive Bid — Global Freight',
      'Competitive RFP for freight services. Incumbent at $800k/yr. Awarded to BlueOcean Logistics at $680k/yr.',
      'Competitive Rebid', 'Sourcing', 'RFP', 'Contracted', 'Sarah Chen',
      'Ran competitive RFP with 4 suppliers. BlueOcean Logistics came in 15% below incumbent. 3-year contract.',
      (SELECT id FROM categories WHERE organization_id = org_id AND category_name = 'Logistics & Freight' LIMIT 1),
      (SELECT id FROM business_units WHERE organization_id = org_id AND business_unit_name = 'Operations' LIMIT 1),
      (SELECT id FROM cost_centers WHERE organization_id = org_id AND cost_center_name = 'OPS-100 Facilities' LIMIT 1),
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'Global Freight Co.' LIMIT 1),
      'USD', 1.0,
      '2026-04-01', '2026-06-15', '2026-07-01', '2029-06-30',
      user_id, user_id, user_id;

    SELECT id INTO event_id FROM sourcing_events WHERE event_name = 'Freight Contract Competitive Bid — Global Freight' LIMIT 1;

    INSERT INTO event_scope_lines (event_id, line_number, item_service_name, uom, quantity, organization_id, created_by)
    VALUES
      (event_id, 1, 'Domestic Freight — Standard Routes', 'Shipment', 5000, org_id, user_id),
      (event_id, 2, 'Expedited Freight Services', 'Shipment', 500, org_id, user_id);

    -- Baseline: $800,000/yr
    INSERT INTO baselines (
      event_id, baseline_name, baseline_type, baseline_total_amount,
      baseline_normalized_amount, baseline_lock_status,
      official_for_hard_savings, official_for_cost_avoidance,
      baseline_period_start, baseline_period_end,
      organization_id, created_by
    )
    VALUES (
      event_id, 'Incumbent Contract Baseline', 'Current Contract', 800000,
      800000, 'Locked', true, false,
      '2025-07-01', '2026-06-30', org_id, user_id
    )
    RETURNING id INTO baseline_id;

    INSERT INTO baseline_lines (
      baseline_id, scope_line_id, line_number, baseline_unit_price,
      baseline_quantity, baseline_extended_amount, organization_id, created_by
    )
    VALUES
      (baseline_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 140, 5000, 700000, org_id, user_id),
      (baseline_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 200, 500, 100000, org_id, user_id);

    -- Final Offer from BlueOcean: $680,000/yr
    INSERT INTO supplier_offers (
      event_id, supplier_id, offer_type, offer_round, offer_date,
      offer_total_amount, offer_valid_until, compliant_bid_flag,
      selected_for_award_flag, notes, organization_id, created_by
    )
    VALUES (
      event_id,
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'BlueOcean Logistics' LIMIT 1),
      'Final', 1, '2026-06-01', 680000, '2026-07-15', true, true,
      'Lowest compliant bid. 15% below incumbent. 3-year commitment.',
      org_id, user_id
    )
    RETURNING id INTO offer_id;

    INSERT INTO supplier_offer_lines (
      offer_id, scope_line_id, line_number, offered_unit_price,
      offered_quantity, offered_extended_amount, organization_id, created_by
    )
    VALUES
      (offer_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 120, 5000, 600000, org_id, user_id),
      (offer_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 160, 500, 80000, org_id, user_id);

    -- Award
    INSERT INTO awards (
      event_id, supplier_id, offer_id, award_name, award_total_amount,
      award_status, award_date, organization_id, created_by
    )
    VALUES (
      event_id,
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'BlueOcean Logistics' LIMIT 1),
      offer_id, 'Award — BlueOcean Logistics', 680000,
      'Approved', '2026-06-10', org_id, user_id
    )
    RETURNING id INTO award_id;

    INSERT INTO award_lines (
      award_id, scope_line_id, line_number, awarded_unit_price,
      awarded_quantity, awarded_extended_amount, organization_id, created_by
    )
    VALUES
      (award_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 120, 5000, 600000, org_id, user_id),
      (award_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 160, 500, 80000, org_id, user_id);

    -- Savings: Cost Reduction
    -- $800k - $680k = $120,000/yr, 15% reduction
    -- 3-year period: 2026-07-01 to 2029-06-30
    INSERT INTO savings_calculations (
      event_id, baseline_id, award_id, calculation_name, savings_type,
      baseline_total_amount, award_total_amount,
      gross_savings_amount, savings_percentage, net_savings_amount,
      cost_reduction_amount, cost_avoidance_amount,
      savings_start_date, savings_end_date,
      calculation_status, organization_id, created_by
    )
    VALUES (
      event_id, baseline_id, award_id,
      'Cost Reduction — Competitive Bid 15% Reduction', 'Cost Reduction',
      800000, 680000,
      120000, 15.0, 120000,
      120000, 0,
      '2026-07-01', '2029-06-30',
      'contracted', org_id, user_id
    );
  END IF;

  -- ============================================
  -- PROJECT 4: Insurance Premium Negotiation (Cost Avoidance)
  -- ============================================
  -- Baseline: $450,000/yr (current premium)
  -- Opening offer (renewal quote): $517,500/yr (15% increase, market-driven)
  -- Award: $460,500/yr (2.3% increase, negotiated down)
  -- Cost Reduction = $0 (price went up from $450k)
  -- Cost Avoidance = $517,500 - $460,500 = $57,000/yr
  -- Period: 2026-09-01 to 2027-08-31 (1 year)

  IF NOT EXISTS (SELECT 1 FROM sourcing_events WHERE event_name = 'Insurance Premium Renewal — Summit Insurance') THEN
    INSERT INTO sourcing_events (
      organization_id, event_name, event_description, event_type, project_type,
      sourcing_method, event_status, buyer_name, notes,
      category_id, business_unit_id, cost_center_id, incumbent_supplier_id,
      currency_code, fx_rate_to_usd,
      event_start_date, event_close_date, contract_start_date, contract_end_date,
      procurement_owner_id, created_by, updated_by
    )
    SELECT
      org_id,
      'Insurance Premium Renewal — Summit Insurance',
      'Insurance renewal. Market indicated 15% increase. Negotiated to 2.3% with improved coverage terms.',
      'Renegotiation', 'Sourcing', 'Negotiated Renewal', 'Contracted', 'Mike Rodriguez',
      'Summit proposed 15% increase based on market hardening. Used benchmark data to negotiate down to 2.3%.',
      (SELECT id FROM categories WHERE organization_id = org_id AND category_name = 'Insurance' LIMIT 1),
      (SELECT id FROM business_units WHERE organization_id = org_id AND business_unit_name = 'Finance' LIMIT 1),
      (SELECT id FROM cost_centers WHERE organization_id = org_id AND cost_center_name = 'FIN-100 Audit & Advisory' LIMIT 1),
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'Summit Insurance Co.' LIMIT 1),
      'USD', 1.0,
      '2026-06-01', '2026-08-15', '2026-09-01', '2027-08-31',
      user_id, user_id, user_id;

    SELECT id INTO event_id FROM sourcing_events WHERE event_name = 'Insurance Premium Renewal — Summit Insurance' LIMIT 1;

    INSERT INTO event_scope_lines (event_id, line_number, item_service_name, uom, quantity, organization_id, created_by)
    VALUES
      (event_id, 1, 'General Liability Insurance', 'Annual', 1, org_id, user_id),
      (event_id, 2, 'Property Insurance', 'Annual', 1, org_id, user_id);

    -- Baseline: $450,000/yr
    INSERT INTO baselines (
      event_id, baseline_name, baseline_type, baseline_total_amount,
      baseline_normalized_amount, baseline_lock_status,
      official_for_hard_savings, official_for_cost_avoidance,
      baseline_period_start, baseline_period_end,
      organization_id, created_by
    )
    VALUES (
      event_id, 'Current Premium Baseline', 'Current Contract', 450000,
      450000, 'Locked', false, true,
      '2025-09-01', '2026-08-31', org_id, user_id
    )
    RETURNING id INTO baseline_id;

    INSERT INTO baseline_lines (
      baseline_id, scope_line_id, line_number, baseline_unit_price,
      baseline_quantity, baseline_extended_amount, organization_id, created_by
    )
    VALUES
      (baseline_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 300000, 1, 300000, org_id, user_id),
      (baseline_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 150000, 1, 150000, org_id, user_id);

    -- Initial Offer: $517,500 (15% increase)
    INSERT INTO supplier_offers (
      event_id, supplier_id, offer_type, offer_round, offer_date,
      offer_total_amount, offer_valid_until, compliant_bid_flag,
      notes, organization_id, created_by
    )
    VALUES (
      event_id,
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'Summit Insurance Co.' LIMIT 1),
      'Initial', 1, '2026-06-15', 517500, '2026-07-31', true,
      'Opening renewal quote. 15% increase citing market hardening.',
      org_id, user_id
    )
    RETURNING id INTO offer_id;

    -- Final Offer: $460,500 (2.3% increase)
    INSERT INTO supplier_offers (
      event_id, supplier_id, offer_type, offer_round, offer_date,
      offer_total_amount, offer_valid_until, compliant_bid_flag,
      selected_for_award_flag, notes, organization_id, created_by
    )
    VALUES (
      event_id,
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'Summit Insurance Co.' LIMIT 1),
      'Final', 2, '2026-08-01', 460500, '2026-09-15', true, true,
      'Final negotiated premium. 2.3% increase with improved coverage terms.',
      org_id, user_id
    )
    RETURNING id INTO offer_id;

    -- Award
    INSERT INTO awards (
      event_id, supplier_id, offer_id, award_name, award_total_amount,
      award_status, award_date, organization_id, created_by
    )
    VALUES (
      event_id,
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'Summit Insurance Co.' LIMIT 1),
      offer_id, 'Award — Summit Insurance (Final)', 460500,
      'Approved', '2026-08-10', org_id, user_id
    )
    RETURNING id INTO award_id;

    -- Savings: Cost Avoidance
    -- Cost Reduction = $0 (premium went UP from $450k to $460.5k)
    -- Cost Avoidance = $517.5k (opening offer) - $460.5k (award) = $57,000/yr
    INSERT INTO savings_calculations (
      event_id, baseline_id, award_id, calculation_name, savings_type,
      baseline_total_amount, award_total_amount,
      gross_savings_amount, savings_percentage, net_savings_amount,
      cost_reduction_amount, cost_avoidance_amount,
      savings_start_date, savings_end_date,
      calculation_status, organization_id, created_by
    )
    VALUES (
      event_id, baseline_id, award_id,
      'Cost Avoidance — Negotiated 2.3% vs 15% Increase', 'Cost Avoidance',
      517500, 460500,
      57000, 11.01, 57000,
      0, 57000,
      '2026-09-01', '2027-08-31',
      'contracted', org_id, user_id
    );
  END IF;

  -- ============================================
  -- PROJECT 5: Office Supplies Consolidation (Cost Reduction)
  -- ============================================
  -- Baseline: $350,000/yr (multiple suppliers, fragmented)
  -- Award: $280,000/yr (consolidated to single supplier, volume discount)
  -- Cost Reduction = $350k - $280k = $70,000/yr
  -- Period: 2026-08-01 to 2028-07-31 (2 years)

  IF NOT EXISTS (SELECT 1 FROM sourcing_events WHERE event_name = 'Office Supplies Consolidation — OfficePro') THEN
    INSERT INTO sourcing_events (
      organization_id, event_name, event_description, event_type, project_type,
      sourcing_method, event_status, buyer_name, notes,
      category_id, business_unit_id, cost_center_id, incumbent_supplier_id,
      currency_code, fx_rate_to_usd,
      event_start_date, event_close_date, contract_start_date, contract_end_date,
      procurement_owner_id, created_by, updated_by
    )
    SELECT
      org_id,
      'Office Supplies Consolidation — OfficePro',
      'Consolidated 6 office supply vendors into single contract with OfficePro. 20% volume discount.',
      'Supplier Consolidation', 'Sourcing', 'RFP', 'Contracted', 'Lisa Park',
      'Fragmented spend across 6 suppliers. Consolidated to OfficePro with volume-based pricing. 20% reduction.',
      (SELECT id FROM categories WHERE organization_id = org_id AND category_name = 'Office Supplies' LIMIT 1),
      (SELECT id FROM business_units WHERE organization_id = org_id AND business_unit_name = 'Operations' LIMIT 1),
      (SELECT id FROM cost_centers WHERE organization_id = org_id AND cost_center_name = 'OPS-100 Facilities' LIMIT 1),
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'OfficePro Supplies' LIMIT 1),
      'USD', 1.0,
      '2026-05-01', '2026-07-15', '2026-08-01', '2028-07-31',
      user_id, user_id, user_id;

    SELECT id INTO event_id FROM sourcing_events WHERE event_name = 'Office Supplies Consolidation — OfficePro' LIMIT 1;

    INSERT INTO event_scope_lines (event_id, line_number, item_service_name, uom, quantity, organization_id, created_by)
    VALUES
      (event_id, 1, 'General Office Supplies', 'Annual', 1, org_id, user_id),
      (event_id, 2, 'Print & Copy Supplies', 'Annual', 1, org_id, user_id);

    -- Baseline: $350,000/yr (weighted average across 6 suppliers)
    INSERT INTO baselines (
      event_id, baseline_name, baseline_type, baseline_total_amount,
      baseline_normalized_amount, baseline_lock_status,
      official_for_hard_savings, official_for_cost_avoidance,
      baseline_period_start, baseline_period_end,
      organization_id, created_by
    )
    VALUES (
      event_id, 'Pre-Consolidation Spend Baseline', 'Prior 12-Month Actual', 350000,
      350000, 'Locked', true, false,
      '2025-08-01', '2026-07-31', org_id, user_id
    )
    RETURNING id INTO baseline_id;

    INSERT INTO baseline_lines (
      baseline_id, scope_line_id, line_number, baseline_unit_price,
      baseline_quantity, baseline_extended_amount, organization_id, created_by
    )
    VALUES
      (baseline_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 250000, 1, 250000, org_id, user_id),
      (baseline_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 100000, 1, 100000, org_id, user_id);

    -- Final Offer: $280,000/yr
    INSERT INTO supplier_offers (
      event_id, supplier_id, offer_type, offer_round, offer_date,
      offer_total_amount, offer_valid_until, compliant_bid_flag,
      selected_for_award_flag, notes, organization_id, created_by
    )
    VALUES (
      event_id,
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'OfficePro Supplies' LIMIT 1),
      'Final', 1, '2026-07-01', 280000, '2026-08-15', true, true,
      'Consolidated pricing with 20% volume discount. 2-year commitment.',
      org_id, user_id
    )
    RETURNING id INTO offer_id;

    INSERT INTO supplier_offer_lines (
      offer_id, scope_line_id, line_number, offered_unit_price,
      offered_quantity, offered_extended_amount, organization_id, created_by
    )
    VALUES
      (offer_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 200000, 1, 200000, org_id, user_id),
      (offer_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 80000, 1, 80000, org_id, user_id);

    -- Award
    INSERT INTO awards (
      event_id, supplier_id, offer_id, award_name, award_total_amount,
      award_status, award_date, organization_id, created_by
    )
    VALUES (
      event_id,
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'OfficePro Supplies' LIMIT 1),
      offer_id, 'Award — OfficePro Supplies', 280000,
      'Approved', '2026-07-10', org_id, user_id
    )
    RETURNING id INTO award_id;

    INSERT INTO award_lines (
      award_id, scope_line_id, line_number, awarded_unit_price,
      awarded_quantity, awarded_extended_amount, organization_id, created_by
    )
    VALUES
      (award_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 200000, 1, 200000, org_id, user_id),
      (award_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 80000, 1, 80000, org_id, user_id);

    -- Savings: Cost Reduction
    -- $350k - $280k = $70,000/yr, 20% reduction
    -- 2-year period: 2026-08-01 to 2028-07-31
    INSERT INTO savings_calculations (
      event_id, baseline_id, award_id, calculation_name, savings_type,
      baseline_total_amount, award_total_amount,
      gross_savings_amount, savings_percentage, net_savings_amount,
      cost_reduction_amount, cost_avoidance_amount,
      savings_start_date, savings_end_date,
      calculation_status, organization_id, created_by
    )
    VALUES (
      event_id, baseline_id, award_id,
      'Cost Reduction — 20% Volume Discount via Consolidation', 'Cost Reduction',
      350000, 280000,
      70000, 20.0, 70000,
      70000, 0,
      '2026-08-01', '2028-07-31',
      'contracted', org_id, user_id
    );
  END IF;

END $$;

-- Verify
SELECT 'sourcing_events' as table_name, count(*) FROM sourcing_events
UNION ALL SELECT 'savings_calculations', count(*) FROM savings_calculations
UNION ALL SELECT 'baselines', count(*) FROM baselines
UNION ALL SELECT 'awards', count(*) FROM awards
UNION ALL SELECT 'supplier_offers', count(*) FROM supplier_offers;