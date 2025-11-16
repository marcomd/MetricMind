# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**MetricMind** is a Git Productivity Analytics system that extracts commit data from multiple repositories, stores it in PostgreSQL, and provides analytics to measure developer productivity and the impact of development tools (especially AI tools).

**Key Purpose**: Track **how** developers work (volume, frequency) and **what** they work on (business domains extracted from commit messages).

## Core Architecture

### Data Pipeline (ETL Flow)

```
Git Repos → Extract (JSON) → Load (PostgreSQL) → Categorize (Pattern + AI) → Views → Dashboard
```

1. **Extract**: `git_extract_to_json.rb` reads git history, outputs JSON with commit metadata
2. **Load**: `load_json_to_db.rb` inserts JSON data into PostgreSQL tables
3. **Categorize**: Two-stage categorization:
   - **Pattern-based** (`categorize_commits.rb`): Extracts categories from commit subjects using patterns
   - **AI-powered** (`ai_categorize_commits.rb`): Uses LLM to categorize remaining commits based on subject + file paths
4. **Views**: Pre-computed aggregations (daily, weekly, monthly) for fast queries
5. **Dashboard**: (Coming soon) Replit frontend visualizing metrics

### Database Schema

**Tables:**
- `repositories`: Metadata about tracked repos
- `commits`: Per-commit granular data with unique constraint on `(repository_id, hash)`
- `categories`: Approved business domain categories for consistent categorization

**Key Columns in `commits`:**
- `category` (VARCHAR(100)): Business domain extracted from commit (NULL = uncategorized)
  - Extracted using pattern matching OR AI-powered categorization
- `ai_confidence` (SMALLINT 0-100): Confidence score for AI-generated categories (NULL = pattern-matched or uncategorized)
  - Lower scores may indicate need for manual review
- `weight` (INTEGER 0-100): Commit validity weight (0 = reverted, 100 = valid)
- `ai_tools` (VARCHAR(255)): AI tools used during development

**Views:**
- Standard: `v_daily_stats_by_repo`, `v_weekly_stats_by_repo`, `mv_monthly_stats_by_repo` (materialized)
- Category: `v_category_stats`, `v_category_by_repo`, `mv_monthly_category_stats` (materialized)
- Uncategorized: `v_uncategorized_commits` (for monitoring coverage)

**Important**: Materialized views must be refreshed after loading data:
- `SELECT refresh_all_mv();` - Standard views
- `SELECT refresh_category_mv();` - Category views

### Orchestration Scripts

**`scripts/run.rb`** - Main workflow orchestrator:
- Reads `config/repositories.json` for repository list
- For each enabled repo: Extract → Load → **Post-processing**
- Post-processing workflow (automatic):
  1. Pattern-based categorization (`categorize_commits.rb`)
  2. AI-powered categorization (`ai_categorize_commits.rb` - only if AI_PROVIDER configured)
  3. Weight calculation for revert detection (`calculate_commit_weights.rb`)
  4. Refresh materialized views
- Supports flags: `--clean`, `--skip-extraction`, `--skip-load`, `--from DATE`, `--to DATE`
- Single repo mode: `./scripts/run.rb mater`

**`scripts/setup.rb`** - One-time setup:
- Full mode (default): Checks prereqs, installs deps, creates .env, sets up databases, applies migrations
- Database-only mode: `--database-only` (skips Ruby/env setup, just database)

### Critical Implementation Details

1. **Two-Stage Categorization Workflow**:
   - **Stage 1 - Pattern Matching** (`categorize_commits.rb`): Fast, rule-based extraction
     - Pipe delimiter: `BILLING | Fix bug` → BILLING
     - Square brackets: `[CS] Update widget` → CS
     - First uppercase word: `BILLING Implement feature` → BILLING
     - Ignores common verbs: MERGE, FIX, ADD, UPDATE, REMOVE, DELETE
   - **Stage 2 - AI Categorization** (`ai_categorize_commits.rb`): LLM-based categorization for remaining commits
     - Only processes commits with `category IS NULL` (pattern matching failed)
     - Uses file paths from JSON exports as strong signals (e.g., `app/jobs/billing/*` → BILLING)
     - Fetches existing categories from `categories` table to ensure consistency
     - Stores confidence score (0-100) in `ai_confidence` column
     - Creates new categories when needed or reuses existing ones

2. **AI Categorization Architecture** (`lib/llm/`):
   - **Supported Providers**: Gemini (cloud) and Ollama (local)
   - **Base Client Pattern**: Abstract `BaseClient` with timeout/retry logic
   - **Factory Pattern**: `ClientFactory` creates appropriate client based on `AI_PROVIDER` env var
   - **Categorizer**: High-level orchestrator managing database operations and LLM interactions
   - **Prompt Engineering**: Structured prompts including commit subject, file paths, and existing categories
   - **Error Handling**: Graceful degradation if LLM unavailable (skips AI step, doesn't fail pipeline)

3. **Squash Merge Limitation**:
   - Work was initially done to extract work_type from branch names
   - **Removed** because squash merges to master lose branch information
   - Only `category` extraction remains (works reliably from commit messages)

4. **Duplicate Handling**:
   - `commits` table has `UNIQUE (repository_id, hash)` constraint
   - Loader uses `ON CONFLICT DO NOTHING` - re-running is safe

5. **Transaction Management**:
   - Each JSON load runs in a transaction (atomicity per repository)
   - Failed loads rollback automatically
   - AI categorization processes commits in batches with transaction per batch

## Common Commands

### Setup
```bash
# First-time setup (everything)
./scripts/setup.sh

# Database-only setup (useful after schema changes)
./scripts/setup.sh --database-only
```

### Data Extraction & Loading
```bash
# Extract and load all enabled repositories (with auto-categorization)
./scripts/run.rb

# Process single repository
./scripts/run.rb mater

# Custom date range
./scripts/run.rb --from "1 year ago" --to "now"

# Clean and reload (prompts for confirmation)
./scripts/run.rb --clean

# Only extract to JSON (no database load)
./scripts/run.rb --skip-load

# Only load from existing JSON
./scripts/run.rb --skip-extraction
```

### Manual Operations
```bash
# Extract single repository
./scripts/git_extract_to_json.rb "6 months ago" "now" "data/repo.json" "repo-name" "/path/to/repo"

# Load JSON to database
./scripts/load_json_to_db.rb data/repo.json

# Pattern-based categorization (runs automatically in run.rb, but can run manually)
./scripts/categorize_commits.rb
./scripts/categorize_commits.rb --dry-run
./scripts/categorize_commits.rb --repo mater

# AI-powered categorization (runs automatically in run.rb if AI_PROVIDER is set)
./scripts/ai_categorize_commits.rb                    # Categorize all uncategorized commits
./scripts/ai_categorize_commits.rb --dry-run          # Preview without updating database
./scripts/ai_categorize_commits.rb --repo mater       # Process single repository
./scripts/ai_categorize_commits.rb --force            # Force recategorization of ALL commits
./scripts/ai_categorize_commits.rb --limit 100        # Process only 100 commits
./scripts/ai_categorize_commits.rb --debug            # Enable verbose output

# Clean repository data
./scripts/clean_repository.rb mater
```

### Database Operations
```bash
# Connect to database
psql -d git_analytics

# Refresh materialized views
psql -d git_analytics -c "SELECT refresh_all_mv(); SELECT refresh_category_mv();"

# Check categorization coverage
psql -d git_analytics -c "
  SELECT
    COUNT(*) as total,
    COUNT(category) as categorized,
    ROUND(COUNT(category)::numeric / COUNT(*) * 100, 1) as pct
  FROM commits;
"

# View category distribution
psql -d git_analytics -c "SELECT * FROM v_category_stats ORDER BY total_commits DESC;"

# Find uncategorized commits
psql -d git_analytics -c "SELECT * FROM v_uncategorized_commits LIMIT 20;"

# Check AI categorization statistics
psql -d git_analytics -c "
  SELECT
    COUNT(*) FILTER (WHERE ai_confidence IS NOT NULL) as ai_categorized,
    ROUND(AVG(ai_confidence) FILTER (WHERE ai_confidence IS NOT NULL), 1) as avg_confidence,
    COUNT(*) FILTER (WHERE ai_confidence < 50) as low_confidence
  FROM commits;
"

# View categories and their usage
psql -d git_analytics -c "SELECT name, usage_count, description FROM categories ORDER BY usage_count DESC LIMIT 20;"

# Find low-confidence AI categorizations for review
psql -d git_analytics -c "
  SELECT hash, subject, category, ai_confidence
  FROM commits
  WHERE ai_confidence IS NOT NULL AND ai_confidence < 70
  ORDER BY ai_confidence ASC
  LIMIT 20;
"
```

### Testing
```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/git_extract_to_json_spec.rb

# Run with documentation format
bundle exec rspec --format documentation

# Run single test by line number
bundle exec rspec spec/integration_spec.rb:42
```

### Linting
```bash
# Run RuboCop
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a
```

## Configuration Files

**`config/repositories.json`** - Repository tracking list:
```json
{
  "repositories": [
    {
      "name": "repo-name",
      "path": "~/path/to/repo",
      "description": "Description",
      "enabled": true
    }
  ]
}
```

**`.env`** - Configuration:
```bash
# Database credentials
# Option 1: Use DATABASE_URL (recommended for remote databases)
# DATABASE_URL=postgresql://user:password@host:port/database?sslmode=require

# Option 2: Use individual parameters (local development)
PGHOST=localhost
PGPORT=5432
PGDATABASE=git_analytics
PGUSER=username
PGPASSWORD=password

# Note: DATABASE_URL takes priority over individual parameters if both are set

PGDATABASE_TEST=git_analytics_test
DEFAULT_FROM_DATE="6 months ago"
DEFAULT_TO_DATE="now"
OUTPUT_DIR=./data/exports

# AI Categorization (optional - leave empty to disable)
AI_PROVIDER=ollama              # Options: gemini, ollama
AI_TIMEOUT=30                   # Timeout in seconds
AI_RETRIES=3                    # Number of retry attempts

# Gemini Configuration (if using AI_PROVIDER=gemini)
GEMINI_API_KEY=your_api_key
GEMINI_MODEL=gemini-2.0-flash-exp
GEMINI_TEMPERATURE=0.1

# Ollama Configuration (if using AI_PROVIDER=ollama)
OLLAMA_URL=http://localhost:11434
OLLAMA_MODEL=llama2
OLLAMA_TEMPERATURE=0.1
```

## Schema Migrations

**Migration workflow:**
1. Create new migration in `schema/migrations/` (numbered: `001_description.sql`)
2. Run setup to apply: `./scripts/setup.sh --database-only`
3. Migrations run automatically on fresh setups

**Current migrations:**
- `001_add_commit_categorization.sql` - Adds `category` column to commits table
- `002_add_users_and_oauth.sql` - Adds users and OAuth support
- `003_add_weight_and_ai_tools.sql` - Adds weight and ai_tools columns
- `004_add_ai_categorization.sql` - Adds categories table and ai_confidence column

**Adding new migrations:**
- Name format: `NNN_description.sql` (e.g., `002_add_new_feature.sql`)
- Include both forward migration and comments
- Test with `--database-only` before committing

## Testing Strategy

**Test database**: Uses `git_analytics_test` (auto-configured in `spec_helper.rb`)

**Test types:**
- Unit tests: Individual script functionality
- Integration tests: Full pipeline (extract → load → query)
- Database tests: Schema, constraints, views

**Important**: Tests use temporary files and clean up after themselves.

## Workflow Notes

1. **When adding new repositories**: Edit `config/repositories.json`, then run `./scripts/run.rb`
2. **After schema changes**: Run `./scripts/setup.sh --database-only` to recreate database
3. **After loading new data**: Views refresh automatically via `run.rb` post-processing
4. **When categorization coverage is low**:
   - First, review `v_uncategorized_commits` and update team's commit message format for better pattern matching
   - Then, enable AI categorization by setting `AI_PROVIDER` in `.env` (gemini or ollama)
   - Run `./scripts/ai_categorize_commits.rb --dry-run` to preview AI categorization
5. **AI categorization best practices**:
   - Start with `--dry-run` to preview categorizations before applying
   - Use `--limit 100` for testing on small batches
   - Review low-confidence categorizations (< 70%) periodically
   - Check categories table to consolidate similar categories (e.g., TECH vs TECHNOLOGY)
6. **Before/After analysis**: Use date range filters to compare periods (e.g., before/after AI tool adoption)

## Known Limitations

1. **Squash merges**: Branch names are lost, so work_type extraction by branch is not possible
2. **Binary files**: Lines changed excludes binary files (marked with `-` in git numstat)
3. **Commit subject only**: Only first line of commit message is analyzed by pattern matching
4. **Category patterns**: Pattern-based categorization requires standardized commit message format for good coverage
5. **Performance**: Large repositories may take time to extract (no streaming, all in-memory JSON)
6. **AI categorization**:
   - Requires JSON exports (doesn't work with database-only data)
   - LLM API costs apply when using Gemini (Ollama is free but requires local setup)
   - Confidence scores are LLM-generated and may not always reflect accuracy
   - Category consistency depends on prompt engineering and existing categories

## Environment Variables

**Database Connection Priority:**
- `DATABASE_URL` - PostgreSQL connection string (takes priority if set)
  - Format: `postgresql://user:password@host:port/database?sslmode=require`
  - Recommended for remote/hosted databases (Neon, Heroku, etc.)
- Individual parameters (used if `DATABASE_URL` not set):
  - `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`
  - Recommended for local development

**Test Database:**
Test database is automatically configured:
- `PGDATABASE_TEST` used if set, otherwise `PGDATABASE` + `_test` suffix
- Tests modify `ENV['PGDATABASE']` to point to test database
- Production scripts use `ENV['PGDATABASE']` directly or parse from `DATABASE_URL`

**AI Categorization:**
AI categorization is optional. Leave `AI_PROVIDER` empty to disable.
- `AI_PROVIDER` - LLM provider: `gemini` or `ollama` (empty = disabled)
- `AI_TIMEOUT` - Request timeout in seconds (default: 30)
- `AI_RETRIES` - Number of retry attempts (default: 3)
- `AI_DEBUG` - Enable verbose logging: `true` or `false`

**Gemini-specific (if AI_PROVIDER=gemini):**
- `GEMINI_API_KEY` - Google API key (required)
- `GEMINI_MODEL` - Model name (default: gemini-2.0-flash-exp)
- `GEMINI_TEMPERATURE` - Temperature 0-2 (default: 0.1)

**Ollama-specific (if AI_PROVIDER=ollama):**
- `OLLAMA_URL` - Ollama server URL (default: http://localhost:11434)
- `OLLAMA_MODEL` - Model name (default: llama2, try: mistral, codellama)
- `OLLAMA_TEMPERATURE` - Temperature 0-2 (default: 0.1)

## Future Development (Dashboard)

- **Platform**: Replit (frontend + API)
- **API Endpoints**: RESTful endpoints querying views
- **Pages**: Overview, Trends, Contributors, Activity, Comparison, Before/After, Content Analysis
- **Design**: Modern, responsive, dark mode support
- See README.md "Building the Dashboard on Replit" section for full specifications
