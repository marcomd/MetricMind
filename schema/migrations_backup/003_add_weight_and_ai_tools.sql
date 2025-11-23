-- Migration: Add weight and AI tools tracking
-- Description: Adds weight (0-100 for commit validity) and ai_tools (AI tools used) columns to commits table
-- Date: 2025-11-12

-- Add weight column to commits table (0-100, default 100)
ALTER TABLE commits
ADD COLUMN IF NOT EXISTS weight INTEGER DEFAULT 100 NOT NULL;

-- Add constraint to ensure weight is between 0 and 100
ALTER TABLE commits
ADD CONSTRAINT IF NOT EXISTS check_weight_range CHECK (weight >= 0 AND weight <= 100);

-- Add ai_tools column to commits table
ALTER TABLE commits
ADD COLUMN IF NOT EXISTS ai_tools VARCHAR(255);

-- Create index for efficient ai_tools queries
CREATE INDEX IF NOT EXISTS idx_commits_ai_tools ON commits(ai_tools) WHERE ai_tools IS NOT NULL;

-- Add comments for documentation
COMMENT ON COLUMN commits.weight IS 'Commit validity weight (0-100). Reverted commits have weight=0, valid commits have weight=100.';
COMMENT ON COLUMN commits.ai_tools IS 'AI tools used during development, extracted from commit body (e.g., CLAUDE CODE, CURSOR, GITHUB COPILOT).';
