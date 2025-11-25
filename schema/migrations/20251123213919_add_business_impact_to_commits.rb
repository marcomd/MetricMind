# frozen_string_literal: true

# Migration: Add Business Impact To Commits
# Created: 2025-11-23 21:39:19

Sequel.migration do
  up do
    run <<-SQL
      ALTER TABLE commits
      ADD COLUMN IF NOT EXISTS business_impact INTEGER;

      ALTER TABLE commits
      ADD CONSTRAINT check_business_impact_range
      CHECK (business_impact IS NULL OR (business_impact >= 0 AND business_impact <= 100));

      COMMENT ON COLUMN commits.business_impact IS 'AI-assessed business impact score (0-100): 0-30=config files, 31-60=refactors, 61-100=features/bugs/security';
    SQL
  end

  down do
    run <<-SQL
      ALTER TABLE commits
      DROP CONSTRAINT IF EXISTS check_business_impact_range;

      ALTER TABLE commits
      DROP COLUMN IF EXISTS business_impact;
    SQL
  end
end
