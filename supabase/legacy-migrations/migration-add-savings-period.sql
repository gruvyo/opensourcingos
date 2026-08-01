-- Migration: Add savings period columns and adjust status values
-- Run in Supabase SQL editor

-- Add period columns
ALTER TABLE savings_calculations ADD COLUMN IF NOT EXISTS savings_start_date date;
ALTER TABLE savings_calculations ADD COLUMN IF NOT EXISTS savings_end_date date;

-- Optionally set default status for existing rows to 'identified'
UPDATE savings_calculations SET calculation_status = 'identified' WHERE calculation_status IS NULL OR calculation_status = '';

-- No further changes needed – UI now uses the new status labels.
