# frozen_string_literal: true

# Migration: Add commit categorization
# Original file: 001_add_commit_categorization.sql
# Original date: 2025-11-08
# Converted from SQL to Sequel format

Sequel.migration do
  up do
    run <<-SQL
      ALTER TABLE commits
      ADD COLUMN IF NOT EXISTS category VARCHAR(100);
      
      CREATE INDEX IF NOT EXISTS idx_commits_category ON commits(category) WHERE category IS NOT NULL;
      
      COMMENT ON COLUMN commits.category IS 'Business domain category extracted from commit subject (e.g., BILLING, CS). Works reliably from commit messages.';
    SQL
  end

  down do
    run <<-SQL
      DROP INDEX IF EXISTS idx_commits_category;
            ALTER TABLE commits DROP COLUMN IF EXISTS category;
    SQL
  end
end
