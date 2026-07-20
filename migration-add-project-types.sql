-- Migration: Add project_type, buyer_name, notes to sourcing_events
-- Run this in Supabase Dashboard → SQL Editor → New query → Paste → Run

-- 1. Add project_type column (Sourcing = commercial pipeline, Support = non-commercial)
ALTER TABLE sourcing_events ADD COLUMN IF NOT EXISTS project_type text DEFAULT 'Sourcing';

-- 2. Add buyer_name column (called "IP Owner" in user's tracker)
ALTER TABLE sourcing_events ADD COLUMN IF NOT EXISTS buyer_name text;

-- 3. Add notes column
ALTER TABLE sourcing_events ADD COLUMN IF NOT EXISTS notes text;

-- 4. Backfill existing events as 'Sourcing' type
UPDATE sourcing_events SET project_type = 'Sourcing' WHERE project_type IS NULL;

-- 5. Verify
SELECT id, event_name, project_type, buyer_name, notes FROM sourcing_events LIMIT 5;