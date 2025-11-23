# frozen_string_literal: true

# Migration: Add weight and AI tools tracking
# Original file: 003_add_weight_and_ai_tools.sql
# Original date: 2025-11-12
# Converted from SQL to Sequel format

Sequel.migration do
  up do
    run <<-SQL
      ALTER TABLE commits
      ADD COLUMN IF NOT EXISTS weight INTEGER DEFAULT 100 NOT NULL;
      
      ALTER TABLE commits
      ADD CONSTRAINT IF NOT EXISTS check_weight_range CHECK (weight >= 0 AND weight <= 100);
      
      ALTER TABLE commits
      ADD COLUMN IF NOT EXISTS ai_tools VARCHAR(255);
      
      CREATE INDEX IF NOT EXISTS idx_commits_ai_tools ON commits(ai_tools) WHERE ai_tools IS NOT NULL;
      
      COMMENT ON COLUMN commits.weight IS 'Commit validity weight (0-100). Reverted commits have weight=0, valid commits have weight=100.';
      COMMENT ON COLUMN commits.ai_tools IS 'AI tools used during development, extracted from commit body (e.g., CLAUDE CODE, CURSOR, GITHUB COPILOT).';
    SQL
  end

  down do
    run <<-SQL
      ALTER TABLE commits DROP CONSTRAINT IF EXISTS IF;
            DROP INDEX IF EXISTS idx_commits_ai_tools;
            ALTER TABLE commits DROP COLUMN IF EXISTS ai_tools;
            ALTER TABLE commits DROP COLUMN IF EXISTS weight;
    SQL
  end
end
