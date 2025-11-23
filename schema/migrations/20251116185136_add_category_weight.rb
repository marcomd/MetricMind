# frozen_string_literal: true

# Migration: Add weight column to categories table
# Original file: 005_add_category_weight.sql
# Original date: 2025-11-16
# Converted from SQL to Sequel format

Sequel.migration do
  up do
    run <<-SQL
      ALTER TABLE categories
      ADD COLUMN IF NOT EXISTS weight INTEGER DEFAULT 100 NOT NULL;
      
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint WHERE conname = 'check_category_weight_range'
        ) THEN
          ALTER TABLE categories
          ADD CONSTRAINT check_category_weight_range CHECK (weight >= 0 AND weight <= 100);
        END IF;
      END$$;
      
      CREATE INDEX IF NOT EXISTS idx_categories_weight ON categories(weight) WHERE weight != 100;
      
      COMMENT ON COLUMN categories.weight IS 'Category weight (0-100). Default 100 = full weight. Admins can lower this to de-prioritize certain categories in analytics. Synced to commits.weight by sync_commit_weights_from_categories.rb script.';
    SQL
  end

  down do
    run <<-SQL
      ALTER TABLE categories DROP CONSTRAINT IF EXISTS check_category_weight_range;
            DROP INDEX IF EXISTS idx_categories_weight;
            ALTER TABLE categories DROP COLUMN IF EXISTS weight;
    SQL
  end
end
