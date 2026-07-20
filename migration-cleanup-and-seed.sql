-- Migration: Clean up savings model + seed complete sample data
-- Run this in Supabase Dashboard → SQL Editor → New query → Paste → Run

-- ============================================
-- STEP 1: Clean up savings_calculations table
-- ============================================

-- Remove finance validation columns (no longer needed)
ALTER TABLE savings_calculations DROP COLUMN IF EXISTS finance_validated;
ALTER TABLE savings_calculations DROP COLUMN IF EXISTS finance_validated_by;
ALTER TABLE savings_calculations DROP COLUMN IF EXISTS finance_validation_date;
ALTER TABLE savings_calculations DROP COLUMN IF EXISTS current_year_recognized_amount;

-- Update savings_type values to be clearer
-- 'Hard Savings' → 'Cost Reduction'
-- 'Cost Avoidance' stays 'Cost Avoidance'
-- Other types stay as-is
UPDATE savings_calculations SET savings_type = 'Cost Reduction' WHERE savings_type = 'Hard Savings';

-- Drop the old check constraint and add a new one with updated types
ALTER TABLE savings_calculations DROP CONSTRAINT IF EXISTS savings_calculations_savings_type_check;
ALTER TABLE savings_calculations ADD CONSTRAINT savings_calculations_savings_type_check
  CHECK (savings_type IN (
    'Cost Reduction', 'Cost Avoidance', 'Demand Reduction',
    'TCO Improvement', 'Working Capital'
  ));

-- ============================================
-- STEP 2: RLS policies for all remaining tables
-- ============================================

-- Savings calculations
CREATE POLICY IF NOT EXISTS "Authenticated can select savings_calculations" ON savings_calculations FOR SELECT TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can insert savings_calculations" ON savings_calculations FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY IF NOT EXISTS "Authenticated can update savings_calculations" ON savings_calculations FOR UPDATE TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can delete savings_calculations" ON savings_calculations FOR DELETE TO authenticated USING (true);

-- Savings calculation lines
CREATE POLICY IF NOT EXISTS "Authenticated can select savings_calculation_lines" ON savings_calculation_lines FOR SELECT TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can insert savings_calculation_lines" ON savings_calculation_lines FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY IF NOT EXISTS "Authenticated can update savings_calculation_lines" ON savings_calculation_lines FOR UPDATE TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can delete savings_calculation_lines" ON savings_calculation_lines FOR DELETE TO authenticated USING (true);

-- Baselines
CREATE POLICY IF NOT EXISTS "Authenticated can select baselines" ON baselines FOR SELECT TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can insert baselines" ON baselines FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY IF NOT EXISTS "Authenticated can update baselines" ON baselines FOR UPDATE TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can delete baselines" ON baselines FOR DELETE TO authenticated USING (true);

-- Baseline lines
CREATE POLICY IF NOT EXISTS "Authenticated can select baseline_lines" ON baseline_lines FOR SELECT TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can insert baseline_lines" ON baseline_lines FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY IF NOT EXISTS "Authenticated can update baseline_lines" ON baseline_lines FOR UPDATE TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can delete baseline_lines" ON baseline_lines FOR DELETE TO authenticated USING (true);

-- Supplier offers
CREATE POLICY IF NOT EXISTS "Authenticated can select supplier_offers" ON supplier_offers FOR SELECT TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can insert supplier_offers" ON supplier_offers FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY IF NOT EXISTS "Authenticated can update supplier_offers" ON supplier_offers FOR UPDATE TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can delete supplier_offers" ON supplier_offers FOR DELETE TO authenticated USING (true);

-- Supplier offer lines
CREATE POLICY IF NOT EXISTS "Authenticated can select supplier_offer_lines" ON supplier_offer_lines FOR SELECT TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can insert supplier_offer_lines" ON supplier_offer_lines FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY IF NOT EXISTS "Authenticated can update supplier_offer_lines" ON supplier_offer_lines FOR UPDATE TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can delete supplier_offer_lines" ON supplier_offer_lines FOR DELETE TO authenticated USING (true);

-- Awards
CREATE POLICY IF NOT EXISTS "Authenticated can select awards" ON awards FOR SELECT TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can insert awards" ON awards FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY IF NOT EXISTS "Authenticated can update awards" ON awards FOR UPDATE TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can delete awards" ON awards FOR DELETE TO authenticated USING (true);

-- Award lines
CREATE POLICY IF NOT EXISTS "Authenticated can select award_lines" ON award_lines FOR SELECT TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can insert award_lines" ON award_lines FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY IF NOT EXISTS "Authenticated can update award_lines" ON award_lines FOR UPDATE TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can delete award_lines" ON award_lines FOR DELETE TO authenticated USING (true);

-- Event scope lines
CREATE POLICY IF NOT EXISTS "Authenticated can select event_scope_lines" ON event_scope_lines FOR SELECT TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can insert event_scope_lines" ON event_scope_lines FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY IF NOT EXISTS "Authenticated can update event_scope_lines" ON event_scope_lines FOR UPDATE TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can delete event_scope_lines" ON event_scope_lines FOR DELETE TO authenticated USING (true);

-- Organizations
CREATE POLICY IF NOT EXISTS "Authenticated can select organizations" ON organizations FOR SELECT TO authenticated USING (true);
-- Profiles
CREATE POLICY IF NOT EXISTS "Authenticated can select profiles" ON profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY IF NOT EXISTS "Authenticated can update profiles" ON profiles FOR UPDATE TO authenticated USING (true);

-- ============================================
-- STEP 3: Seed lookup data (if empty)
-- ============================================

-- Get the org ID (use first org)
DO $$
DECLARE
  org_id UUID;
  user_id UUID;
BEGIN
  SELECT id INTO org_id FROM organizations LIMIT 1;
  SELECT id INTO user_id FROM profiles LIMIT 1;

  IF org_id IS NULL THEN
    RAISE EXCEPTION 'No organization found. Please create an org first.';
  END IF;

  -- Categories (only if empty)
  INSERT INTO categories (organization_id, category_name, created_by)
  SELECT org_id, c, user_id FROM (VALUES
    ('Software & SaaS'), ('IT Hardware'), ('Cloud Infrastructure'), ('Professional Services'),
    ('Facilities & Real Estate'), ('Marketing & Advertising'), ('Logistics & Freight'),
    ('MRO & Supplies'), ('Telecommunications'), ('Insurance'), ('HR & Benefits'),
    ('Travel & Expense'), ('Legal Services'), ('Financial Services'),
    ('Office Supplies'), ('Utilities & Energy')
  ) AS t(c)
  WHERE NOT EXISTS (SELECT 1 FROM categories WHERE organization_id = org_id);

  -- Business Units (only if empty)
  INSERT INTO business_units (organization_id, business_unit_name, created_by)
  SELECT org_id, bu, user_id FROM (VALUES
    ('Engineering'), ('Sales & Marketing'), ('Finance'), ('IT / Infrastructure'),
    ('Operations'), ('HR / People'), ('Legal'), ('Corporate')
  ) AS t(bu)
  WHERE NOT EXISTS (SELECT 1 FROM business_units WHERE organization_id = org_id);

  -- Cost Centers (only if empty, linked to BUs)
  INSERT INTO cost_centers (organization_id, business_unit_id, cost_center_name, created_by)
  SELECT org_id, bu.id, cc, user_id FROM (
    SELECT 'Engineering' as bu_name, 'ENG-100 Software Licenses' as cc
    UNION SELECT 'Engineering', 'ENG-200 Cloud Services'
    UNION SELECT 'Sales & Marketing', 'MKT-100 Advertising'
    UNION SELECT 'Sales & Marketing', 'MKT-200 Events'
    UNION SELECT 'Finance', 'FIN-100 Audit & Advisory'
    UNION SELECT 'IT / Infrastructure', 'IT-100 Hardware'
    UNION SELECT 'IT / Infrastructure', 'IT-200 Networking'
    UNION SELECT 'Operations', 'OPS-100 Facilities'
    UNION SELECT 'HR / People', 'HR-100 Benefits Admin'
    UNION SELECT 'Legal', 'LEG-100 Outside Counsel'
  ) t
  JOIN business_units bu ON bu.business_unit_name = t.bu_name AND bu.organization_id = org_id
  WHERE NOT EXISTS (SELECT 1 FROM cost_centers WHERE organization_id = org_id AND cost_center_name = t.cc);

  -- Suppliers (only if empty)
  INSERT INTO suppliers (organization_id, supplier_name, created_by)
  SELECT org_id, s, user_id FROM (VALUES
    ('Acme Software Inc.'), ('TechCloud Solutions'), ('Global Freight Co.'),
    ('Premier Facilities Services'), ('DataSync Systems'), ('BlueOcean Logistics'),
    ('Vertex Consulting Group'), ('Summit Insurance Co.'), ('OfficePro Supplies'),
    ('CyberShield Security')
  ) AS t(s)
  WHERE NOT EXISTS (SELECT 1 FROM suppliers WHERE organization_id = org_id AND supplier_name = s);

  -- ============================================
  -- STEP 4: Seed a COMPLETE sample sourcing project
  -- ============================================

  -- Only insert if fewer than 3 sourcing events exist
  IF (SELECT COUNT(*) FROM sourcing_events WHERE organization_id = org_id) < 3 THEN
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
      'Annual renewal of CRM platform. Incumbent proposed 12% increase. Negotiated to 3% with 2-year commitment and additional licenses included.',
      'Renewal', 'Sourcing', 'Negotiated Renewal', 'Contracted', 'Jane Smith',
      'Incumbent supplier Acme Software proposed 12% uplift at renewal. Ran a competitive RFP with 3 suppliers. Negotiated final price at 3% increase with expanded user count and premium support included at no extra cost.',
      (SELECT id FROM categories WHERE organization_id = org_id AND category_name = 'Software & SaaS' LIMIT 1),
      (SELECT id FROM business_units WHERE organization_id = org_id AND business_unit_name = 'Sales & Marketing' LIMIT 1),
      (SELECT id FROM cost_centers WHERE organization_id = org_id AND cost_center_name = 'MKT-100 Advertising' LIMIT 1),
      (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'Acme Software Inc.' LIMIT 1),
      'USD', 1.0,
      '2026-01-15', '2026-03-30', '2026-04-01', '2028-03-31',
      user_id, user_id, user_id;

    -- Get the event ID
    DECLARE
      event_id UUID;
    BEGIN
      SELECT id INTO event_id FROM sourcing_events WHERE organization_id = org_id AND event_name = 'CRM Software Renewal — Acme Software' LIMIT 1;

      -- Scope Lines (3 items)
      INSERT INTO event_scope_lines (event_id, line_number, item_service_name, uom, quantity, organization_id, created_by)
      VALUES
        (event_id, 1, 'CRM Platform Licenses — Enterprise', 'Each', 500, org_id, user_id),
        (event_id, 2, 'Premium Support Package', 'Each', 1, org_id, user_id),
        (event_id, 3, 'Data Migration & Onboarding', 'One-Time', 1, org_id, user_id);

      -- Baseline (Current Contract — what we're paying now)
      DECLARE
        baseline_id UUID;
      BEGIN
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
          '2025-04-01', '2026-03-31',
          org_id, user_id
        )
        RETURNING id INTO baseline_id;

        -- Baseline Lines (matching scope lines)
        INSERT INTO baseline_lines (
          baseline_id, scope_line_id, line_number, baseline_unit_price,
          baseline_quantity, baseline_extended_amount, organization_id, created_by
        )
        VALUES
          (baseline_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 1000, 500, 500000, org_id, user_id),
          (baseline_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 50000, 1, 50000, org_id, user_id),
          (baseline_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 3 LIMIT 1), 3, 50000, 1, 50000, org_id, user_id);
      END;

      -- Supplier Offers
      -- Offer 1: Acme Software — Initial (opening offer, 12% uplift)
      DECLARE
        offer1_id UUID;
      BEGIN
        INSERT INTO supplier_offers (
          event_id, supplier_id, offer_type, offer_round, offer_date,
          offer_total_amount, offer_valid_until, compliant_bid_flag,
          notes, organization_id, created_by
        )
        VALUES (
          event_id,
          (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'Acme Software Inc.' LIMIT 1),
          'Initial', 1, '2026-02-01', 672000, '2026-03-15', true,
          'Opening offer from incumbent. Proposed 12% uplift on current contract. Includes 500 licenses + premium support + data migration.',
          org_id, user_id
        )
        RETURNING id INTO offer1_id;

        -- Offer lines for opening offer
        INSERT INTO supplier_offer_lines (
          offer_id, scope_line_id, line_number, offered_unit_price,
          offered_quantity, offered_extended_amount, organization_id, created_by
        )
        VALUES
          (offer1_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 1100, 500, 550000, org_id, user_id),
          (offer1_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 56000, 1, 56000, org_id, user_id),
          (offer1_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 3 LIMIT 1), 3, 66000, 1, 66000, org_id, user_id);
      END;

      -- Offer 2: Acme Software — Final (negotiated down to 3% increase)
      DECLARE
        offer2_id UUID;
        award_id UUID;
      BEGIN
        INSERT INTO supplier_offers (
          event_id, supplier_id, offer_type, offer_round, offer_date,
          offer_total_amount, offer_valid_until, compliant_bid_flag,
          selected_for_award_flag,
          notes, organization_id, created_by
        )
        VALUES (
          event_id,
          (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'Acme Software Inc.' LIMIT 1),
          'Final', 3, '2026-03-20', 618000, '2026-04-15', true, true,
          'Final negotiated offer. 3% increase from current contract. Includes 600 licenses (100 additional at no cost), premium support, and data migration. 2-year commitment.',
          org_id, user_id
        )
        RETURNING id INTO offer2_id;

        -- Offer lines for final offer
        INSERT INTO supplier_offer_lines (
          offer_id, scope_line_id, line_number, offered_unit_price,
          offered_quantity, offered_extended_amount, organization_id, created_by
        )
        VALUES
          (offer2_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 930, 600, 558000, org_id, user_id),
          (offer2_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 50000, 1, 50000, org_id, user_id),
          (offer2_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 3 LIMIT 1), 3, 10000, 1, 10000, org_id, user_id);

        -- Create Award from the final offer
        INSERT INTO awards (
          event_id, supplier_id, offer_id, award_name, award_total_amount,
          award_status, award_date, organization_id, created_by
        )
        VALUES (
          event_id,
          (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'Acme Software Inc.' LIMIT 1),
          offer2_id, 'Award — Acme Software (Final)', 618000,
          'Approved', '2026-03-25', org_id, user_id
        )
        RETURNING id INTO award_id;

        -- Award lines
        INSERT INTO award_lines (
          award_id, scope_line_id, line_number, awarded_unit_price,
          awarded_quantity, awarded_extended_amount, organization_id, created_by
        )
        VALUES
          (award_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 1 LIMIT 1), 1, 930, 600, 558000, org_id, user_id),
          (award_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 2 LIMIT 1), 2, 50000, 1, 50000, org_id, user_id),
          (award_id, (SELECT id FROM event_scope_lines WHERE event_id = event_id AND line_number = 3 LIMIT 1), 3, 10000, 1, 10000, org_id, user_id);

        -- Savings Calculation 1: Cost Reduction (price went down per unit)
        INSERT INTO savings_calculations (
          event_id, baseline_id, award_id, calculation_name, savings_type,
          baseline_total_amount, award_total_amount,
          gross_savings_amount, savings_percentage, net_savings_amount,
          calculation_status, organization_id, created_by
        )
        VALUES (
          event_id,
          (SELECT id FROM baselines WHERE event_id = event_id LIMIT 1),
          award_id,
          'Cost Reduction — Unit Price Negotiation', 'Cost Reduction',
          600000, 618000,
          -18000, -3.0, -18000,
          'Approved', org_id, user_id
        );

        -- Savings Calculation 2: Cost Avoidance (100 additional licenses at no cost)
        INSERT INTO savings_calculations (
          event_id, baseline_id, award_id, calculation_name, savings_type,
          baseline_total_amount, award_total_amount,
          gross_savings_amount, savings_percentage, net_savings_amount,
          calculation_status, organization_id, created_by
        )
        VALUES (
          event_id,
          (SELECT id FROM baselines WHERE event_id = event_id LIMIT 1),
          award_id,
          'Cost Avoidance — 100 Additional Licenses Included', 'Cost Avoidance',
          600000, 618000,
          93000, 15.5, 93000,
          'Approved', org_id, user_id
        );

        -- Note: Cost reduction is NEGATIVE here because the total contract value went UP
        -- from $600k to $618k (3% increase). However, we got 100 more licenses.
        -- Cost avoidance = value of those 100 licenses at the negotiated unit price = 100 × $930 = $93,000
        -- Cost reduction = the price increase we absorbed = $618k - $600k = -$18k (negative = cost increase)
        -- Total savings = Cost avoidance + Cost reduction = $93,000 - $18,000 = $75,000 net savings
      END;
    END;
  END IF;

  -- ============================================
  -- STEP 5: Seed a Support project (non-commercial)
  -- ============================================
  INSERT INTO sourcing_events (
    organization_id, event_name, event_description, event_type, project_type,
    event_status, buyer_name, notes,
    category_id, business_unit_id, cost_center_id, incumbent_supplier_id,
    currency_code, fx_rate_to_usd,
    event_start_date, event_close_date,
    procurement_owner_id, created_by, updated_by
  )
  SELECT
    org_id,
    'Vendor Billing Dispute — TechCloud Solutions',
    'Disputed overcharge on Q1 cloud hosting invoice. Supplier billed for 3 decommissioned instances.',
    'Billing Dispute', 'Support', 'Complete', 'John Davis',
    'Identified $15,000 overcharge on Q1 invoice for 3 instances that were decommissioned in December. Escalated to TechCloud account manager. Credit issued for full amount.',
    (SELECT id FROM categories WHERE organization_id = org_id AND category_name = 'Cloud Infrastructure' LIMIT 1),
    (SELECT id FROM business_units WHERE organization_id = org_id AND business_unit_name = 'IT / Infrastructure' LIMIT 1),
    (SELECT id FROM cost_centers WHERE organization_id = org_id AND cost_center_name = 'IT-200 Networking' LIMIT 1),
    (SELECT id FROM suppliers WHERE organization_id = org_id AND supplier_name = 'TechCloud Solutions' LIMIT 1),
    'USD', 1.0,
    '2026-02-10', '2026-02-28',
    user_id, user_id, user_id
  WHERE NOT EXISTS (SELECT 1 FROM sourcing_events WHERE organization_id = org_id AND event_name = 'Vendor Billing Dispute — TechCloud Solutions');

END $$;

-- ============================================
-- Verify
-- ============================================
SELECT 'sourcing_events' as table_name, count(*) FROM sourcing_events
UNION ALL SELECT 'event_scope_lines', count(*) FROM event_scope_lines
UNION ALL SELECT 'baselines', count(*) FROM baselines
UNION ALL SELECT 'baseline_lines', count(*) FROM baseline_lines
UNION ALL SELECT 'supplier_offers', count(*) FROM supplier_offers
UNION ALL SELECT 'supplier_offer_lines', count(*) FROM supplier_offer_lines
UNION ALL SELECT 'awards', count(*) FROM awards
UNION ALL SELECT 'award_lines', count(*) FROM award_lines
UNION ALL SELECT 'savings_calculations', count(*) FROM savings_calculations
UNION ALL SELECT 'suppliers', count(*) FROM suppliers
UNION ALL SELECT 'categories', count(*) FROM categories;