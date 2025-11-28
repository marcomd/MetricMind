# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**MetricMind** is a Git Productivity Analytics system that extracts commit data from multiple repositories, stores it in PostgreSQL, and provides analytics to measure developer productivity and the impact of development tools (especially AI tools).

**Key Purpose**: Track **how** developers work (volume, frequency) and **what** they work on (business domains extracted from commit messages).

## Development Practices

### Test-Driven Development (TDD)

**ALWAYS apply TDD when writing or modifying code.** This is a core requirement for all development work.

**The TDD Cycle (Red-Green-Refactor):**

1. **Red**: Write a failing test first
   - Write a test that demonstrates the bug or describes the new feature
   - Run the test to confirm it fails (this proves the test is valid)
   - The failing test serves as a specification for what needs to be implemented

2. **Green**: Write minimal code to make the test pass
   - Implement only what's needed to make the test pass
   - Avoid over-engineering or adding extra features
   - Run the test to confirm it passes

3. **Refactor**: Improve the code while keeping tests green
   - Clean up the implementation
   - Remove duplication
   - Improve readability
   - Run all tests to ensure no regressions

**Why TDD Matters:**

- **Bug Prevention**: Tests catch regressions before they reach production
- **Living Documentation**: Tests serve as examples of how code should work
- **Design Feedback**: Hard-to-test code indicates design problems
- **Confidence**: Comprehensive test coverage enables safe refactoring
- **Coverage**: Ensures edge cases are handled (e.g., special characters in inputs)

**Examples:**

- Before fixing a bug: Write a test that reproduces the bug
- Before adding a feature: Write tests that specify the feature's behavior
- Before refactoring: Ensure existing tests pass, then refactor while keeping them green

**Test Coverage Requirements:**

- All public methods should have tests
- Edge cases must be tested (empty inputs, special characters, boundary conditions)
- Error handling must be tested
- Integration points must be tested

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
  - `weight` (INTEGER 0-100): Category-level weight (default 100). Admin can adjust to de-prioritize categories.

**Key Columns in `commits`:**
- `category` (VARCHAR(100)): Business domain extracted from commit (NULL = uncategorized)
  - Extracted using pattern matching OR AI-powered categorization
- `ai_confidence` (SMALLINT 0-100): Confidence score for AI-generated categories (NULL = pattern-matched or uncategorized)
  - Lower scores may indicate need for manual review
- `weight` (INTEGER 0-100): Commit validity weight (0 = reverted, 100 = valid, or synced from category weight)
- `ai_tools` (VARCHAR(255)): AI tools used during development

**Views:**
- Standard: `v_daily_stats_by_repo`, `v_weekly_stats_by_repo`, `mv_monthly_stats_by_repo` (materialized)
  - Include: `effective_commits`, `avg_weight`, `weight_efficiency_pct`
- Category: `v_category_stats`, `v_category_by_repo`, `mv_monthly_category_stats` (materialized)
  - Include: `effective_commits`, `avg_weight`, `weight_efficiency_pct`, `category_weight`
- AI Tools: `v_ai_tools_stats`, `v_ai_tools_by_repo`
  - Include: `effective_commits`, `avg_weight`, `weight_efficiency_pct`
- Personal Performance: `v_daily_stats_by_author`, `v_weekly_stats_by_author`, `mv_monthly_stats_by_author` (materialized)
  - Include: Same metrics as standard views, but grouped by author_email
  - Filter by `author_email` to show personal metrics for logged-in users
- Personal Categories: `v_category_stats_by_author`, `v_category_by_author_and_repo`, `mv_monthly_category_stats_by_author` (materialized)
  - Include: Same metrics as category views, but grouped by author_email
  - Filter by `author_email` to show personal category breakdown
- Personal Commits: `v_personal_commit_details`
  - Detailed commit list view optimized for personal queries
  - Includes: hash, subject, date, lines, weight, category, ai_tools, repository
  - Filter by `author_email` for commit history of logged-in users
- Uncategorized: `v_uncategorized_commits` (for monitoring coverage)

**Important**: Materialized views must be refreshed after loading data:
- `SELECT refresh_all_mv();` - Standard and personal trend views
- `SELECT refresh_category_mv();` - Category and personal category views
- `SELECT refresh_personal_mv();` - All personal performance views

### Orchestration Scripts

**`scripts/run.rb`** - Main workflow orchestrator:
- Reads `config/repositories.json` for repository list
- For each enabled repo: Extract → Load → **Post-processing**
- Post-processing workflow (automatic):
  1. Pattern-based categorization (`categorize_commits.rb`)
  2. AI-powered categorization (`ai_categorize_commits.rb` - only if AI_PROVIDER configured)
  3. Weight calculation for revert detection (`calculate_commit_weights.rb`)
  4. **Category weight synchronization** (`sync_commit_weights_from_categories.rb`)
  5. Refresh materialized views
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
   - **Supported Providers**: Gemini (cloud), Ollama (local), and Anthropic/Claude (cloud)
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

# Skip AI enrichment (faster for large date ranges)
./scripts/run.rb --skip-ai

# Two-stage workflow: Extract huge history, then enrich recent commits
./scripts/run.rb --skip-ai --from "10 years ago" --to "now"
./scripts/ai_categorize_commits.rb --from "3 months ago" --to "now"

# Process single repository without AI
./scripts/run.rb mater --skip-ai
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
./scripts/ai_categorize_commits.rb --from "3 months ago" --to "now"     # Date range (git-style)
./scripts/ai_categorize_commits.rb --from "2024-01-01" --to "2024-12-31"  # Date range (ISO format)

# Weight synchronization (runs automatically in run.rb after weight calculation)
./scripts/sync_commit_weights_from_categories.rb      # Sync all commit weights from categories
./scripts/sync_commit_weights_from_categories.rb --dry-run  # Preview changes
./scripts/sync_commit_weights_from_categories.rb --repo mater  # Single repository

# Clean repository data
./scripts/clean_repository.rb mater
```

### Database Operations
```bash
# Connect to database
psql -d git_analytics

# Refresh materialized views
psql -d git_analytics -c "SELECT refresh_all_mv(); SELECT refresh_category_mv(); SELECT refresh_personal_mv();"

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

# View categories with their weights
psql -d git_analytics -c "SELECT name, weight, usage_count, description FROM categories ORDER BY usage_count DESC LIMIT 20;"

# Set category weight (admin operation)
psql -d git_analytics -c "UPDATE categories SET weight = 50 WHERE name = 'EXPERIMENTAL';"

# View commits affected by category weights
psql -d git_analytics -c "
  SELECT c.category, cat.weight, COUNT(*) as commits
  FROM commits c
  JOIN categories cat ON c.category = cat.name
  WHERE c.weight > 0 AND cat.weight < 100
  GROUP BY c.category, cat.weight;
"

# Find low-confidence AI categorizations for review
psql -d git_analytics -c "
  SELECT hash, subject, category, ai_confidence
  FROM commits
  WHERE ai_confidence IS NOT NULL AND ai_confidence < 70
  ORDER BY ai_confidence ASC
  LIMIT 20;
"

# Analyze weight efficiency by repository
psql -d git_analytics -c "
  SELECT repository_name,
         ROUND(AVG(weight_efficiency_pct), 1) as avg_efficiency
  FROM mv_monthly_stats_by_repo
  GROUP BY repository_name
  ORDER BY avg_efficiency ASC;
"

# View category weights and their impact
psql -d git_analytics -c "
  SELECT category, category_weight, total_commits, effective_commits
  FROM v_category_stats
  WHERE category_weight < 100
  ORDER BY total_commits DESC;
"

# Personal performance queries (for logged-in users)
# View personal commit history (recent commits)
psql -d git_analytics -c "
  SELECT commit_date, repository_name, hash, subject, lines_changed,
         weight, category, ai_tools
  FROM v_personal_commit_details
  WHERE author_email = 'user@example.com'
  ORDER BY commit_date DESC
  LIMIT 50;
"

# View personal monthly trends
psql -d git_analytics -c "
  SELECT year_month, repository_name, total_commits, total_lines_changed,
         effective_commits, avg_weight, weight_efficiency_pct
  FROM mv_monthly_stats_by_author
  WHERE author_email = 'user@example.com'
  ORDER BY month_start_date DESC;
"

# View personal daily activity
psql -d git_analytics -c "
  SELECT commit_date, repository_name, total_commits, total_lines_changed
  FROM v_daily_stats_by_author
  WHERE author_email = 'user@example.com' AND commit_date >= CURRENT_DATE - INTERVAL '30 days'
  ORDER BY commit_date DESC;
"

# View personal category breakdown
psql -d git_analytics -c "
  SELECT category, total_commits, effective_commits, weighted_lines_changed,
         weight_efficiency_pct
  FROM v_category_stats_by_author
  WHERE author_email = 'user@example.com'
  ORDER BY total_commits DESC;
"

# View personal category trends over time
psql -d git_analytics -c "
  SELECT year_month, category, total_commits, weighted_lines_changed
  FROM mv_monthly_category_stats_by_author
  WHERE author_email = 'user@example.com'
  ORDER BY month_start_date DESC, total_commits DESC
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
AI_PROVIDER=ollama              # Options: gemini, ollama, anthropic
AI_TIMEOUT=120                  # Timeout in seconds (default: 120, increase for slow models)
AI_RETRIES=3                    # Number of retry attempts

# Gemini Configuration (if using AI_PROVIDER=gemini)
GEMINI_API_KEY=your_api_key
GEMINI_MODEL=gemini-2.0-flash-exp
GEMINI_TEMPERATURE=0.1

# Ollama Configuration (if using AI_PROVIDER=ollama)
OLLAMA_API_BASE=http://localhost:11434/v1
OLLAMA_MODEL=llama2
OLLAMA_TEMPERATURE=0.1

# Anthropic Configuration (if using AI_PROVIDER=anthropic)
ANTHROPIC_API_KEY=your_api_key
ANTHROPIC_MODEL=claude-sonnet-4-5  # Alias (recommended) or dated: claude-sonnet-4-5-20250929
ANTHROPIC_TEMPERATURE=0.1
```

## Schema Migrations

**Migration System**: Uses [Sequel](https://sequel.jeremyevans.net/) for Rails-like database migrations with version tracking and rollback support.

### Architecture Overview

**Unified Migration-Based Schema Management:**

The database schema is entirely managed through Sequel migrations in `schema/migrations/`. This includes:

1. **Base Schema** (Migration: `20251107000000_create_base_schema.rb`)
   - Core table definitions: `repositories`, `commits`
   - Indexes, constraints, and comments
   - Applied once via migration system

2. **Standard Views** (Migration: `20251112080000_create_standard_views.rb`)
   - Team analytics views: daily, weekly, monthly stats
   - AI tools usage tracking
   - Materialized views for performance
   - Helper functions: `refresh_all_mv()`

3. **Category Views** (Migration: `20251116000000_create_category_views.rb`)
   - Business domain analytics
   - Category breakdown by repository
   - Monthly trends (materialized)
   - Helper function: `refresh_category_mv()`

4. **Personal Performance Views** (Migration: `20251122000000_create_personal_views.rb`)
   - Author-specific metrics (per-user analytics)
   - Personal commit details, daily/weekly/monthly trends
   - Category breakdowns per author
   - Helper function: `refresh_personal_mv()`

5. **Column Migrations** (Various timestamps)
   - Evolutionary changes: `category`, `weight`, `ai_tools`, etc.
   - Applied between view migrations as needed

**Key Benefits:**
- ✅ **Single source of truth** - All schema in migrations
- ✅ **Full rollback support** - Can revert any change (tables or views)
- ✅ **Automatic tracking** - schema_migrations table records all applied migrations
- ✅ **Version controlled** - Complete audit trail in git
- ✅ **Team-friendly** - Standard Rails-like workflow

**Important Notes:**
- Sequel's `schema_migrations` table stores full filenames (e.g., `20251109125729_add_commit_categorization.rb`), not just timestamps like Rails
- This is standard Sequel behavior and cannot be configured to match Rails
- **Auto-seeding**: Existing databases from SQL files are automatically detected and seeded to prevent re-execution
- View updates require new migrations (cannot edit migration files after application)

**Migration workflow:**
1. Create new migration: `./scripts/db_migrate_new.rb <description>`
2. Edit the generated file in `schema/migrations/` (timestamp format: `YYYYMMDDHHMMSS_description.rb`)
3. Apply migrations: `./scripts/db_migrate.rb`
4. Check status: `./scripts/db_migrate_status.rb`

**Migration Commands:**
```bash
# Create new migration
./scripts/db_migrate_new.rb add_status_to_commits
./scripts/db_migrate_new.rb create_tags_table

# Apply pending migrations
./scripts/db_migrate.rb

# Check migration status
./scripts/db_migrate_status.rb
./scripts/db_migrate_status.rb --verbose

# Rollback last migration
./scripts/db_rollback.rb

# Rollback multiple migrations
./scripts/db_rollback.rb 3

# Setup (includes migration application)
./scripts/setup.rb --database-only
```

**Migration Format:**
Migrations use Sequel's Ruby DSL with `up` and `down` blocks:
```ruby
Sequel.migration do
  up do
    run <<-SQL
      ALTER TABLE commits ADD COLUMN status VARCHAR(50);
      CREATE INDEX idx_commits_status ON commits(status);
    SQL
  end

  down do
    run <<-SQL
      DROP INDEX IF EXISTS idx_commits_status;
      ALTER TABLE commits DROP COLUMN IF EXISTS status;
    SQL
  end
end
```

**Migration Tracking:**
- Applied migrations tracked in `schema_migrations` table (auto-created by Sequel)
- Migrations applied only once (idempotent by design)
- Version-based system prevents duplicate application
- Rollback support via `down` blocks

**Converting Old Migrations:**
Legacy numbered migrations (`001_*.sql`) can be converted to timestamp format:
```bash
# Dry run (preview only)
./scripts/rename_migrations.rb --dry-run

# Convert migrations (creates backup in schema/migrations_backup/)
./scripts/rename_migrations.rb
```

**Best Practices:**
- Always provide both `up` and `down` migrations for rollback support
- Use `IF NOT EXISTS` and `IF EXISTS` for idempotent SQL operations
- Test migrations on development before applying to production
- Review down migration logic carefully (especially for data migrations)
- Commit migrations to version control after testing

**Current Migrations** (in execution order):
1. `20251107000000_create_base_schema.rb` - Creates core tables (repositories, commits) with indexes
2. `20251109125729_add_commit_categorization.rb` - Adds `category` column to commits table
3. `20251109221637_add_users_and_oauth.rb` - Adds users and OAuth support tables
4. `20251112075825_add_weight_and_ai_tools.rb` - Adds weight and ai_tools columns
5. `20251112080000_create_standard_views.rb` - Creates standard analytics views and materialized views
6. `20251116000000_create_category_views.rb` - Creates category analytics views
7. `20251116160219_add_ai_categorization.rb` - Adds categories table and ai_confidence column
8. `20251116185136_add_category_weight.rb` - Adds weight column to categories table
9. `20251122000000_create_personal_views.rb` - Creates personal performance views and updates helper functions

**Auto-Seeding for Existing Databases:**
If your database was set up with legacy SQL files, the setup script automatically detects this and seeds migrations 1, 5, 6, and 9 into `schema_migrations` to prevent re-execution.

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
   - Then, enable AI categorization by setting `AI_PROVIDER` in `.env` (gemini, ollama, or anthropic)
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
- `AI_PROVIDER` - LLM provider: `gemini`, `ollama`, or `anthropic` (empty = disabled)
- `AI_TIMEOUT` - Request timeout in seconds (default: 120)
- `AI_RETRIES` - Number of retry attempts (default: 3)
- `AI_DEBUG` - Enable verbose logging: `true` or `false`

**Gemini-specific (if AI_PROVIDER=gemini):**
- `GEMINI_API_KEY` - Google API key (required)
- `GEMINI_MODEL` - Model name (default: gemini-2.0-flash-exp)
- `GEMINI_TEMPERATURE` - Temperature 0-2 (default: 0.1)

**Ollama-specific (if AI_PROVIDER=ollama):**
- `OLLAMA_API_BASE` - Ollama server URL with /v1 suffix (default: http://localhost:11434/v1)
- `OLLAMA_MODEL` - Model name (default: llama2, try: mistral, codellama)
- `OLLAMA_TEMPERATURE` - Temperature 0-2 (default: 0.1)

**Anthropic-specific (if AI_PROVIDER=anthropic):**
- `ANTHROPIC_API_KEY` - Anthropic API key (required)
- `ANTHROPIC_MODEL` - Model alias or dated version (default: claude-haiku-4-5-20251001)
  - Aliases (recommended): `claude-haiku-4-5` (cheapest), `claude-sonnet-4-5` (balanced)
  - Dated: `claude-haiku-4-5-20251001`, `claude-sonnet-4-5-20250929`
- `ANTHROPIC_TEMPERATURE` - Temperature 0-2 (default: 0.1)

## Future Development (Dashboard)

- **Platform**: Replit (frontend + API)
- **API Endpoints**: RESTful endpoints querying views
- **Pages**: Overview, Trends, Contributors, Activity, Comparison, Before/After, Content Analysis
- **Design**: Modern, responsive, dark mode support
- See README.md "Building the Dashboard on Replit" section for full specifications
