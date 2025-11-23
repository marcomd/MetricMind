# frozen_string_literal: true

# Migration: Add AI-powered categorization support
# Original file: 004_add_ai_categorization.sql
# Original date: 2025-11-16
# Converted from SQL to Sequel format

Sequel.migration do
  up do
    run <<-SQL
      CREATE TABLE IF NOT EXISTS categories (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL UNIQUE,
        description TEXT,
        usage_count INTEGER DEFAULT 0 NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE INDEX IF NOT EXISTS idx_categories_name ON categories(name);
      
      ALTER TABLE commits
      ADD COLUMN IF NOT EXISTS ai_confidence SMALLINT;
      
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint WHERE conname = 'check_ai_confidence_range'
        ) THEN
          ALTER TABLE commits
          ADD CONSTRAINT check_ai_confidence_range CHECK (ai_confidence IS NULL OR (ai_confidence >= 0 AND ai_confidence <= 100));
        END IF;
      END$$;
      
      CREATE INDEX IF NOT EXISTS idx_commits_ai_confidence ON commits(ai_confidence) WHERE ai_confidence IS NOT NULL;
      
      COMMENT ON TABLE categories IS 'Approved business domain categories for commit categorization. Helps ensure consistency across AI-generated categories.';
      COMMENT ON COLUMN categories.name IS 'Unique category name (UPPERCASE, 1-2 words, e.g., BILLING, CS, INFRA).';
      COMMENT ON COLUMN categories.description IS 'Optional description of what this category represents.';
      COMMENT ON COLUMN categories.usage_count IS 'Number of commits assigned to this category. Updated by AI categorization script.';
      COMMENT ON COLUMN commits.ai_confidence IS 'AI categorization confidence score (0-100). NULL if category was not assigned by AI. Lower scores may need manual review.';
      
      INSERT INTO categories (name, description, usage_count)
      SELECT
        DISTINCT category as name,
        'Extracted from existing commits' as description,
        COUNT(*) as usage_count
      FROM commits
      WHERE category IS NOT NULL
      GROUP BY category
      ON CONFLICT (name) DO NOTHING;
    SQL
  end

  down do
    run <<-SQL
      -- Manual rollback may be required. Review the up migration carefully.
            -- WARNING: This migration includes data operations (INSERT/UPDATE).
            ALTER TABLE commits DROP CONSTRAINT IF EXISTS check_ai_confidence_range;
            DROP INDEX IF EXISTS idx_commits_ai_confidence;
            DROP INDEX IF EXISTS idx_categories_name;
            DROP TABLE IF EXISTS categories CASCADE;
            ALTER TABLE commits DROP COLUMN IF EXISTS ai_confidence;
    SQL
  end
end
