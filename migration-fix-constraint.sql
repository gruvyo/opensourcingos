-- FIX: Drop old savings_type check constraint and add new one that allows 'Cost Reduction'
-- Run this FIRST in Supabase SQL Editor, then run migration-cleanup-and-seed.sql

-- 1. Drop ALL existing check constraints on savings_type (handles any name)
DO $$
DECLARE
  constraint_name text;
BEGIN
  FOR constraint_name IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_attribute att ON att.attrelid = rel.oid AND att.attnum = ANY(con.conkey)
    WHERE rel.relname = 'savings_calculations'
      AND con.contype = 'c'
      AND att.attname = 'savings_type'
  LOOP
    EXECUTE format('ALTER TABLE savings_calculations DROP CONSTRAINT IF EXISTS %I', constraint_name);
  END LOOP;
END $$;

-- 2. Add the new check constraint with 'Cost Reduction' (not 'Hard Savings')
ALTER TABLE savings_calculations ADD CONSTRAINT savings_calculations_savings_type_check
  CHECK (savings_type IN (
    'Cost Reduction', 'Cost Avoidance', 'Demand Reduction',
    'TCO Improvement', 'Working Capital'
  ));

-- 3. Update any existing rows that still have 'Hard Savings'
UPDATE savings_calculations SET savings_type = 'Cost Reduction' WHERE savings_type = 'Hard Savings';

-- 4. Also drop finance_validated columns if they still exist (from original schema)
ALTER TABLE savings_calculations DROP COLUMN IF EXISTS finance_validated;
ALTER TABLE savings_calculations DROP COLUMN IF EXISTS finance_validated_by;
ALTER TABLE savings_calculations DROP COLUMN IF EXISTS finance_validation_date;
ALTER TABLE savings_calculations DROP COLUMN IF EXISTS current_year_recognized_amount;

-- 5. Add cost_reduction_amount and cost_avoidance_amount columns if they don't exist
ALTER TABLE savings_calculations ADD COLUMN IF NOT EXISTS cost_reduction_amount numeric DEFAULT 0;
ALTER TABLE savings_calculations ADD COLUMN IF NOT EXISTS cost_avoidance_amount numeric DEFAULT 0;

-- 6. Verify the constraint
SELECT conname, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conrelid = 'savings_calculations'::regclass AND contype = 'c';