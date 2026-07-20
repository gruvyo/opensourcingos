-- Migration: Fix check constraint for support statuses
-- Run this in Supabase Dashboard → SQL Editor → New query → Paste → Run

-- 1. Drop the old check constraint that only allows sourcing statuses
ALTER TABLE sourcing_events DROP CONSTRAINT IF EXISTS sourcing_events_event_status_check;

-- 2. Add a new check constraint that allows BOTH sourcing and support statuses
ALTER TABLE sourcing_events ADD CONSTRAINT sourcing_events_event_status_check
  CHECK (event_status IN (
    -- Sourcing statuses
    'Pipeline', 'Scoped', 'Baseline Pending', 'Baseline Approved',
    'In Market', 'Negotiation', 'Award Recommended', 'Award Approved',
    'Contracted', 'Implemented', 'Realized', 'Finance Validated',
    'Closed', 'Cancelled', 'Rejected',
    -- Support statuses
    'Not Started', 'In Progress', 'Hold', 'Complete'
  ));

-- 3. Verify constraint is in place
SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid = 'sourcing_events'::regclass AND contype = 'c';