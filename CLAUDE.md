# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**MetricMind** is a Git Productivity Analytics system that extracts commit data from multiple repositories, stores it in PostgreSQL, and provides analytics to measure developer productivity and the impact of development tools (especially AI tools).

**Key Purpose**: Track **how** developers work (volume, frequency) and **what** they work on (business domains extracted from commit messages).

## Core Architecture

### Data Pipeline (ETL Flow)

```
Git Repos → Extract (JSON) → Load (PostgreSQL) → Categorize → Views → Dashboard
```

1. **Extract**: `git_extract_to_json.rb` reads git history, outputs JSON with commit metadata
2. **Load**: `load_json_to_db.rb` inserts JSON data into PostgreSQL tables
3. **Categorize**: `categorize_commits.rb` extracts business domains (e.g., BILLING, CS, INFRA) from commit subjects
4. **Views**: Pre-computed aggregations (daily, weekly, monthly) for fast queries
5. **Dashboard**: (Coming soon) Replit frontend visualizing metrics

### Database Schema

**Tables:**
- `repositories`: Metadata about tracked repos
- `commits`: Per-commit granular data with unique constraint on `(repository_id, hash)`

**Key Column: `category`**
- Extracted from commit subjects using patterns (pipe delimiter, brackets, first uppercase word)
- Enables "Content Analysis" - shows what business domains developers focus on
- NULL = uncategorized

**Views:**
- Standard: `v_daily_stats_by_repo`, `v_weekly_stats_by_repo`, `mv_monthly_stats_by_repo` (materialized)
- Category: `v_category_stats`, `v_category_by_repo`, `mv_monthly_category_stats` (materialized)
- Uncategorized: `v_uncategorized_commits` (for monitoring coverage)

**Important**: Materialized views must be refreshed after loading data:
- `SELECT refresh_all_mv();` - Standard views
- `SELECT refresh_category_mv();` - Category views

### Orchestration Scripts

**`scripts/run.sh`** - Main workflow orchestrator:
- Reads `config/repositories.json` for repository list
- For each enabled repo: Extract → Load → **Automatically categorizes** → **Automatically refreshes views**
- Supports flags: `--clean`, `--skip-extraction`, `--skip-load`, `--from DATE`, `--to DATE`
- Single repo mode: `./scripts/run.sh mater`

**`scripts/setup.sh`** - One-time setup:
- Full mode (default): Checks prereqs, installs deps, creates .env, sets up databases, applies migrations
- Database-only mode: `--database-only` (skips Ruby/env setup, just database)

### Critical Implementation Details

1. **Commit Categorization Patterns** (in `categorize_commits.rb`):
   - Pipe delimiter: `BILLING | Fix bug` → BILLING
   - Square brackets: `[CS] Update widget` → CS
   - First uppercase word: `BILLING Implement feature` → BILLING
   - Ignores common verbs: MERGE, FIX, ADD, UPDATE, REMOVE, DELETE

2. **Squash Merge Limitation**:
   - Work was initially done to extract work_type from branch names
   - **Removed** because squash merges to master lose branch information
   - Only `category` extraction remains (works reliably from commit messages)

3. **Duplicate Handling**:
   - `commits` table has `UNIQUE (repository_id, hash)` constraint
   - Loader uses `ON CONFLICT DO NOTHING` - re-running is safe

4. **Transaction Management**:
   - Each JSON load runs in a transaction (atomicity per repository)
   - Failed loads rollback automatically

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
./scripts/run.sh

# Process single repository
./scripts/run.sh mater

# Custom date range
./scripts/run.sh --from "1 year ago" --to "now"

# Clean and reload (prompts for confirmation)
./scripts/run.sh --clean

# Only extract to JSON (no database load)
./scripts/run.sh --skip-load

# Only load from existing JSON
./scripts/run.sh --skip-extraction
```

### Manual Operations
```bash
# Extract single repository
./scripts/git_extract_to_json.rb "6 months ago" "now" "data/repo.json" "repo-name" "/path/to/repo"

# Load JSON to database
./scripts/load_json_to_db.rb data/repo.json

# Categorize commits (runs automatically in run.sh, but can run manually)
./scripts/categorize_commits.rb
./scripts/categorize_commits.rb --dry-run
./scripts/categorize_commits.rb --repo mater

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

**`.env`** - Database credentials:
```bash
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
```

## Schema Migrations

**Migration workflow:**
1. Create new migration in `schema/migrations/` (numbered: `001_description.sql`)
2. Run setup to apply: `./scripts/setup.sh --database-only`
3. Migrations run automatically on fresh setups

**Current migrations:**
- `001_add_commit_categorization.sql` - Adds `category` column to commits table

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

1. **When adding new repositories**: Edit `config/repositories.json`, then run `./scripts/run.sh`
2. **After schema changes**: Run `./scripts/setup.sh --database-only` to recreate database
3. **After loading new data**: Views refresh automatically via `run.sh` post-processing
4. **When categorization coverage is low**: Review `v_uncategorized_commits` and update team's commit message format
5. **Before/After analysis**: Use date range filters to compare periods (e.g., before/after AI tool adoption)

## Known Limitations

1. **Squash merges**: Branch names are lost, so work_type extraction by branch is not possible
2. **Binary files**: Lines changed excludes binary files (marked with `-` in git numstat)
3. **Commit subject only**: Only first line of commit message is analyzed
4. **Category patterns**: Requires standardized commit message format for good coverage
5. **Performance**: Large repositories may take time to extract (no streaming, all in-memory JSON)

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

## Future Development (Dashboard)

- **Platform**: Replit (frontend + API)
- **API Endpoints**: RESTful endpoints querying views
- **Pages**: Overview, Trends, Contributors, Activity, Comparison, Before/After, Content Analysis
- **Design**: Modern, responsive, dark mode support
- See README.md "Building the Dashboard on Replit" section for full specifications
