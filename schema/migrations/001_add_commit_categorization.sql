-- Migration: Add commit categorization
-- Description: Adds category column to commits table for business domain tracking
-- Date: 2025-11-08

-- Add category column to commits table
ALTER TABLE commits
ADD COLUMN IF NOT EXISTS category VARCHAR(100);

-- Create index for efficient category queries
CREATE INDEX IF NOT EXISTS idx_commits_category ON commits(category) WHERE category IS NOT NULL;

-- Add comment for documentation
COMMENT ON COLUMN commits.category IS 'Business domain category extracted from commit subject (e.g., BILLING, CS). Works reliably from commit messages.';
