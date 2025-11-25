# frozen_string_literal: true

# Migration: Add Description To Commits
# Created: 2025-11-23 20:00:54

Sequel.migration do
  up do
    run <<-SQL
      ALTER TABLE commits
      ADD COLUMN IF NOT EXISTS description TEXT;

      COMMENT ON COLUMN commits.description IS 'AI-generated description (2-4 sentences) of commit changes based on git diff analysis';
    SQL
  end

  down do
    run <<-SQL
      ALTER TABLE commits
      DROP COLUMN IF EXISTS description;
    SQL
  end
end
