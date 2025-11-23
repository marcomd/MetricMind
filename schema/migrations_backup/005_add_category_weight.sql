-- Migration: Add weight column to categories table
-- Description: Allows admins to set category-specific weights that affect commit weight calculations
-- Date: 2025-11-16

-- Add weight column to categories table (0-100, default 100)
ALTER TABLE categories
ADD COLUMN IF NOT EXISTS weight INTEGER DEFAULT 100 NOT NULL;

-- Add constraint to ensure weight is between 0 and 100
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'check_category_weight_range'
  ) THEN
    ALTER TABLE categories
    ADD CONSTRAINT check_category_weight_range CHECK (weight >= 0 AND weight <= 100);
  END IF;
END$$;

-- Add index for efficient weight lookups
CREATE INDEX IF NOT EXISTS idx_categories_weight ON categories(weight) WHERE weight != 100;

-- Add comment for documentation
COMMENT ON COLUMN categories.weight IS 'Category weight (0-100). Default 100 = full weight. Admins can lower this to de-prioritize certain categories in analytics. Synced to commits.weight by sync_commit_weights_from_categories.rb script.';
