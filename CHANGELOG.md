# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.6.0] - 2025-11-27

### Added
- **Claude (Anthropic) client support for AI categorization**:
  - New `LLM::ClaudeClient` class using langchainrb with ruby-anthropic gem
  - Follows same architecture as Gemini and Ollama clients (BaseClient pattern)
  - Supports all categorization features: category, confidence, business_impact, reason, description
  - Default model: `claude-haiku-4-5-20251001` (cheapest option for cost-effective testing)
- **E2E integration tests for Claude client** (`spec/llm/integration_spec.rb`):
  - 5 test cases covering real API calls (skipped by default)
  - Tests for category creation, existing category matching, and validation
  - Conditional skipping when `CLAUDE_API_KEY` not configured
  - Follows established pattern from Ollama integration tests
- **Comprehensive unit tests** (`spec/llm/claude_client_spec.rb`):
  - 12 tests with mocked dependencies
  - Configuration validation, response parsing, retry logic
  - Category validation and error handling
- **Ruby-anthropic gem dependency** (`~> 0.4` in Gemfile):
  - Required for langchainrb's Anthropic provider
  - Uses API version header: `anthropic-version: 2023-06-01`

### Changed
- **ClientFactory enhanced with Claude support**:
  - Added `'claude'` to `SUPPORTED_PROVIDERS` array
  - New `validate_claude_config()` method for configuration checking
  - Factory creates ClaudeClient when `AI_PROVIDER=claude`
- **Documentation updates**:
  - `.env.example`: Added Claude configuration section with model recommendations
  - `README.md`: Added Claude setup instructions (Option C)
  - `CLAUDE.md`: Updated AI configuration with Claude-specific settings
  - All docs recommend dated model versions over aliases for reliability

### Notes
- **Limited Claude 4.5 support**: Model aliases (`claude-haiku-4-5`, `claude-sonnet-4-5`) may cause 404 errors with ruby-anthropic gem v0.4.2
- **Workaround**: Use dated model versions explicitly:
  - `claude-haiku-4-5-20251001` (cheapest, recommended for testing)
  - `claude-sonnet-4-5-20250929` (balanced, higher quality)
- **Gem maintenance**: ruby-anthropic hasn't been updated in months; official `anthropic-sdk-ruby` gem migration planned for future release
- **Cost optimization**: Claude Haiku 4.5 priced at $1/$5 per million tokens (cheapest option)
- **Integration tests**: Require explicit `CLAUDE_API_KEY` in shell environment (not loaded from `.env` during tests by design)

### Known Limitations
- Claude 4.5 model aliases not fully supported; requires dated version strings
- Regional availability of Claude 4.5 may vary by API key
- Integration tests require manual API key export (security isolation)

### Testing
Run integration tests with:
```bash
CLAUDE_API_KEY=your-key bundle exec rspec spec/llm/integration_spec.rb:148
```

Run all unit tests:
```bash
bundle exec rspec spec/llm/claude_client_spec.rb
```

### Future Work
- Migrate from community `ruby-anthropic` gem to official `anthropic-sdk-ruby`
- Investigate removing langchainrb dependency for direct API integration
- Monitor Claude 4.5 model alias support in future gem updates

## [1.5.0] - 2025-11-24

### Added
- **AI-generated commit descriptions**:
  - New `description` column in `commits` table (migration: `20251123200054_add_description_to_commits.rb`)
  - AI generates 2-4 sentence descriptions of changes based on git diff analysis
  - Descriptions provide human-readable summaries of technical changes
- **Business impact assessment**:
  - New `business_impact` column in `commits` table (migration: `20251123213919_add_business_impact_to_commits.rb`)
  - AI assesses business value on 0-100 scale:
    - LOW (0-30): Configuration files (yaml, json, etc.)
    - MEDIUM (31-60): Refactors (renames, repetitive changes)
    - HIGH (61-100): Features, bugs, security fixes
  - Used as initial commit weight for better productivity metrics
- **Git diff extraction during commit processing**:
  - New `extract_diff()` method with 10KB truncation limit
  - Provides AI with rich context for categorization and description generation
  - Diff data not stored in JSON (only AI-generated outputs stored)
- **Pattern-based categorization in extraction script**:
  - New `extract_category_from_subject()` method in `git_extract_to_json.rb`
  - Implements three pattern matching strategies:
    - Pipe delimiter: `BILLING | Fix bug` → BILLING
    - Square brackets: `[CS] Update widget` → CS
    - First uppercase word: `INFRA Deploy feature` → INFRA
  - Validates categories using `CategoryValidator` module
  - Ignores common verbs: MERGE, FIX, ADD, UPDATE, REMOVE, DELETE
- **Comprehensive test coverage for AI integration**:
  - New test: `calls AI for description and business_impact even when pattern matching finds category`
  - Validates that AI enrichment happens regardless of pattern matching results
  - Ensures no fields are lost during two-stage categorization

### Changed
- **UPSERT functionality in data loader** (`scripts/load_json_to_db.rb`):
  - Replaced `ON CONFLICT DO NOTHING` with `ON CONFLICT DO UPDATE`
  - Enables re-loading existing commits to update AI-generated fields
  - Statistics tracking updated: `commits_skipped` → `commits_updated`
  - Uses PostgreSQL's `xmax` system column to distinguish inserts from updates
  - **What gets updated**: `category`, `description`, `business_impact`, `ai_confidence`, `weight`, `ai_tools`, `subject`
  - **What stays unchanged**: `commit_date`, `author_name`, `author_email`, `lines_added`, `lines_deleted`, `files_changed`
- **Two-stage categorization architecture**:
  - **Stage 1**: Pattern matching (fast, rule-based) runs first
  - **Stage 2**: AI enrichment (intelligent) ALWAYS runs if available
  - Pattern matching takes priority for category, but AI always provides description and business_impact
  - AI category used as fallback if pattern matching fails
  - Changed from `if...elsif` to separate `if` blocks to ensure AI always runs
- **Default business impact increased from 50 to 100**:
  - AI prompt updated to emphasize default of 100 for typical commits
  - Parsing logic updated to default to 100 if AI doesn't provide value
  - Philosophy: Commits are fully weighted unless there's a valid reason to lower value
- **README.md documentation**:
  - Updated "Duplicate commits" section → "Duplicate commits and re-loading data"
  - Comprehensive UPSERT documentation with use cases and examples
  - Clarified what fields get updated vs preserved during re-loads
  - Added examples for backfilling AI data in existing commits

### Fixed
- **Critical bug: AI fields not set when pattern matching succeeds**:
  - Previous implementation used `elsif`, causing AI to be skipped when pattern matching found category
  - Result: `description`, `business_impact`, `weight`, `ai_confidence` remained NULL
  - Fixed by changing to separate `if` blocks: pattern matching first, then AI enrichment
  - AI now runs for ALL commits (when available), not just when pattern matching fails
  - Test added to prevent regression: verifies AI called even with pattern-matchable commits
- **Ollama client model parameter bug**:
  - Fixed `ollama_client.rb` line 32: `@model` variable not passed to API calls
  - Client was using default model instead of configured `OLLAMA_MODEL`
  - Added `model: @model` parameter to `@client.chat()` call

### Technical Details
- **AI integration workflow** (simplified architecture):
  - Old: Git → JSON → DB → AI categorization (post-processing)
  - New: Git → Extract + AI → JSON (complete) → DB (single-pass)
  - No need to store git diff in database; only AI outputs stored
- **Weight calculation logic** (enhanced):
  - Reverted commits: `weight = 0` (always)
  - Valid commits with AI: `weight = (business_impact × category_weight) / 100`
  - Valid commits without AI: `weight = category_weight`
  - Pattern-matched commits without AI: `weight = 100` (default)

### Breaking Changes
None. All changes are backward compatible. Existing commits will have NULL values for new fields until re-processed.



## [1.4.1] - 2025-11-23

### Fixed
- **Extractor bug with pipe characters in commit subjects**:
  - Fixed critical parsing bug in `git_extract_to_json.rb` where commit subjects containing pipe characters (`|`) were truncated
  - Example: Subject `"Revert \"CS | Move HTML content...\""` was incorrectly extracted as `"Revert \"CS "`
  - Root cause: Naive `split('|')` operation split on all pipes, including those within the subject text
  - Solution: Changed parsing strategy to find `|BODY|` marker first, then split only the header portion
  - Added regression test to prevent future occurrences

## [1.4.0] - 2025-11-23

### Added
- **Unified Sequel-based migration system**:
  - Replaced manual SQL file management with Rails-like migration framework
  - `schema_migrations` table for tracking applied migrations
  - Timestamp-based migration naming: `YYYYMMDDHHMMSS_description.rb`
  - Full idempotent migration support with `up` and `down` blocks
- **Migration management scripts**:
  - `scripts/db_migrate.rb` - Apply pending migrations
  - `scripts/db_migrate_status.rb` - Check migration status (applied/pending)
  - `scripts/db_rollback.rb` - Rollback last N migrations with confirmation
  - `scripts/db_migrate_new.rb` - Generate new migration templates
  - `scripts/rename_migrations.rb` - Convert numbered to timestamp-based migrations
- **Auto-seeding for existing databases**:
  - Automatic detection of databases created from legacy SQL files
  - Seeds `schema_migrations` table to prevent re-execution of converted migrations
  - Seamless migration from SQL-based to migration-based schema management
- **New unified migrations** (converted from SQL files):
  - `20251107000000_create_base_schema.rb` - Base tables (repositories, commits)
  - `20251112080000_create_standard_views.rb` - Standard analytics views
  - `20251116000000_create_category_views.rb` - Category analytics views
  - `20251122000000_create_personal_views.rb` - Personal performance views
- **Sequel connection wrapper** (`lib/sequel_connection.rb`):
  - Unified database connection for migration system
  - Reuses existing DBConnection configuration
  - Supports both DATABASE_URL and individual parameters
- **Legacy SQL file archive** (`schema/legacy_sql_files/`):
  - Preserved original SQL files for reference
  - Comprehensive README explaining migration to new system
  - Clear documentation on why files are archived

### Changed
- **Schema management workflow completely redesigned**:
  - All schema changes now managed through Sequel migrations
  - Single source of truth: `schema/migrations/` directory
  - Migration order enforced by timestamps (view dependencies handled correctly)
- **Enhanced `scripts/setup.rb`**:
  - Auto-seeding integration for existing databases
  - Simplified schema initialization (removed manual SQL file execution)
  - Unified migration application workflow
- **Migration file format standardized**:
  - All migrations use Sequel Ruby DSL with `up` and `down` blocks
  - IF NOT EXISTS / IF EXISTS patterns for idempotency
  - Clear separation of forward and rollback logic
- **Updated documentation**:
  - README.md: New "Database Migrations" section with workflow
  - README.md: Updated "Database Setup" to reflect auto-seeding
  - CLAUDE.md: Comprehensive "Schema Migrations" section
  - CLAUDE.md: Updated architecture to show unified migration-based system
- **Gemfile**: Added `sequel ~> 5.75` dependency

### Fixed
- **Migration status script bug** (`db_migrate_status.rb`):
  - Fixed incorrect comparison logic (was comparing timestamps, now compares full filenames)
  - Now correctly identifies applied vs pending migrations
  - Proper handling of `.rb` extension in migration tracking

### Removed
- Manual SQL file execution from setup workflow
- Direct `psql` commands for schema updates
- Numbered migration format (`001_*.sql`)

### Migration Path

**For existing databases:**
```bash
# The setup script automatically detects and seeds migrations
./scripts/setup.rb --database-only
```

**For new databases:**
```bash
# Standard setup applies all migrations in order
./scripts/setup.rb
```

**Check migration status:**
```bash
./scripts/db_migrate_status.rb
```

### Notes
- **Backward compatible**: Existing databases are automatically migrated to the new system
- **Zero manual intervention**: Auto-seeding prevents re-execution of converted SQL files
- **Rails-like workflow**: Familiar migration patterns for Ruby developers
- **Rollback support**: All migrations include reversible `down` blocks
- **Version tracking**: Sequel's `schema_migrations` table ensures migrations run exactly once
- **Legacy files preserved**: Original SQL files archived for reference and safety
- **Dashboard sync**: Document manual schema differences between extractor and dashboard projects

### Breaking Changes
None. The migration is transparent for existing installations.

## [1.3.0] - 2025-11-22

### Added
- **Personal performance views for logged-in users**:
  - `v_personal_commit_details` - Detailed commit list view optimized for personal queries
  - `v_daily_stats_by_author` - Daily statistics per author and repository
  - `v_weekly_stats_by_author` - Weekly statistics per author and repository
  - `mv_monthly_stats_by_author` - Monthly statistics per author (materialized for performance)
  - `v_category_stats_by_author` - Category breakdown per author across all repositories
  - `v_category_by_author_and_repo` - Category statistics per author per repository
  - `mv_monthly_category_stats_by_author` - Monthly category trends per author (materialized)
- **Personal performance indexes** for query optimization:
  - `idx_commits_author_email` - Index on author_email for fast filtering
  - `idx_commits_author_date` - Composite index on author_email and commit_date
  - `idx_commits_author_repo` - Composite index on author_email and repository_id
  - `idx_commits_author_category` - Composite index on author_email and category
- **Refresh functions for personal views**:
  - `refresh_personal_mv()` - Refreshes all personal performance materialized views
  - Updated `refresh_all_mv()` to include personal trend views
  - Updated `refresh_category_mv()` to include personal category views
- **Migration 006** (`006_add_personal_performance_views.sql`):
  - Adds all personal performance views and indexes
  - Idempotent script with proper DROP statements for views and indexes
- **Comprehensive documentation**:
  - README.md: Added "Personal Performance Views" section with usage examples
  - README.md: Added personal query examples (commit history, trends, categories)
  - CLAUDE.md: Updated database schema with personal views documentation
  - CLAUDE.md: Added personal performance query examples in Database Operations

### Changed
- **Enhanced view structure** with explicit type casts (`::int`, `::bigint`, `::numeric`)
- **UNCATEGORIZED handling** in category views using `COALESCE(c.category, 'UNCATEGORIZED')`
- **View definitions** now use `NULLIF` to prevent division by zero in calculations
- **All personal views** include comprehensive weight analysis metrics:
  - `effective_commits` - Weighted commit count accounting for reverts and category weights
  - `avg_weight` - Average weight across commits
  - `weight_efficiency_pct` - Efficiency percentage showing weight impact

### Notes
- **Dashboard integration ready**: Personal views enable individual user metrics on Trends, Activity, and Content pages
- **Filter by author_email**: All personal views are optimized for filtering by logged-in user's email
- **Materialized views**: Monthly aggregations provide fast query performance for personal dashboards
- **Backward compatible**: Existing views and queries continue to work unchanged
- **Performance optimized**: Comprehensive indexing ensures fast personal queries even with large datasets
- **Flexible filtering**: Personal views support filtering by repository, date range, and category

### Migration Required
After updating, apply the migration and refresh materialized views:
```bash
# Apply migration
./scripts/setup.rb --database-only

# Or apply directly
psql -d git_analytics -f schema/personal_views.sql

# Refresh personal materialized views
psql -d git_analytics -c "SELECT refresh_personal_mv();"
```

Or run the full pipeline:
```bash
./scripts/run.rb
```

## [1.2.0] - 2025-11-20

### Added
- **Weight analysis columns to all PostgreSQL views**:
  - `effective_commits` - Weighted commit count (e.g., 263 commits at 50% = 131.5 effective commits)
  - `avg_weight` - Average weight across commits in the aggregation
  - `weight_efficiency_pct` - Percentage showing weight impact (100% = no de-prioritization)
  - `category_weight` (category views only) - Category's configured weight from categories table
- **New comprehensive test suite** (`spec/views_spec.rb`):
  - 19 tests verifying view column structure for all views
  - Integration tests for weight metric calculations
  - Tests for category_weight JOIN with categories table
  - Verification of effective commits, avg_weight, and efficiency calculations
- **Weight synchronization integration tests** in `spec/database_integration_spec.rb`:
  - End-to-end test for weight sync from categories to commits
  - Test for reverted commit preservation (weight=0 not synced)
- **Enhanced documentation** with weight analysis guidance:
  - README.md: 3 new query example sections (weight efficiency, category impact, repository comparison)
  - README.md: New "Analyzing Weight Impact" section with psql commands
  - CLAUDE.md: Updated view documentation with weight columns
  - CLAUDE.md: New database operation examples for weight analysis

### Fixed
- **Critical bug in `sync_commit_weights_from_categories.rb`**:
  - Fixed cartesian join issue in `build_update_query` method
  - Removed unnecessary `FROM repositories r` clause when no repository filter specified
  - Issue caused unpredictable weight synchronization behavior
  - Now correctly updates commit weights without cartesian joins
- **Performance improvement in `build_count_query` method**:
  - Removed unnecessary JOIN when counting commits without repository filter
  - Faster query execution for category statistics

### Changed
- **Updated all standard views** (7 views):
  - `v_daily_stats_by_repo`
  - `v_weekly_stats_by_repo`
  - `mv_monthly_stats_by_repo`
  - `v_contributor_stats`
  - `v_ai_tools_stats`
  - `v_ai_tools_by_repo`
  - `v_commit_details`
- **Updated all category views** (3 views):
  - `v_category_stats`
  - `v_category_by_repo`
  - `mv_monthly_category_stats`
- **Enhanced view definitions** in `schema/postgres_views.sql` and `schema/category_views.sql`:
  - Category views now JOIN with `categories` table to expose category weights
  - All views calculate effective commits using `SUM(weight / 100.0)`
  - Efficiency percentage shows real-time impact of weight adjustments

### Notes
- **Weight analysis enables UI transparency**: Frontend can now display both raw and effective commit counts
- **Category weight visibility**: UI can show which categories are de-prioritized and by how much
- **Backward compatible**: Existing queries continue to work; new columns are additive
- **Test coverage**: 21 new tests ensure weight analysis features work correctly
- **For UI teams**: See README.md "Weight efficiency analysis" section for query examples
- **Performance**: Materialized views maintain fast query performance despite additional calculations

### Migration Required
After updating, refresh materialized views with existing data:
```bash
psql -d git_analytics -c "SELECT refresh_all_mv(); SELECT refresh_category_mv();"
```

Or run the full pipeline to apply all changes:
```bash
./scripts/run.rb
```

## [1.1.0] - 2025-11-16

### Added
- Category weight management system for flexible prioritization
- `weight` column to `categories` table (0-100, default 100)
- `sync_commit_weights_from_categories.rb` script for automatic weight synchronization
- Date range filtering for AI categorization with `--from` and `--to` flags
- Support for both git-style dates ("3 months ago") and ISO format ("2024-01-01")
- Migration 005: Added category weight support to database schema
- Comprehensive test suite for weight sync functionality
- Test suite for date filtering in AI categorization
- Project cover image update (`docs/MetricMindCover_ruby.jpg`)

### Changed
- Enhanced `ai_categorize_commits.rb` with flexible date range filtering
- Updated `run.rb` workflow to include category weight synchronization (step 4)
- Commits now processed in descending order by `commit_date` (newest first)
- Updated all documentation with category weight management workflows
- Enhanced database schema documentation with categories table details

### Notes
- Category weights enable de-prioritization of specific work types (e.g., experimental, prototype)
- Weight sync runs automatically as part of `./scripts/run.rb` post-processing
- Date filtering enables efficient incremental AI categorization of recent commits
- All changes maintain backward compatibility

## [1.0.0] - 2025-11-16

### Added
- AI-powered commit categorization using LLM providers (Gemini and Ollama)
- `lib/llm/` module with base client architecture and factory pattern
- Support for Gemini (cloud) and Ollama (local) AI providers
- `categories` table for managing approved business domain categories
- `ai_confidence` column to track confidence scores (0-100) for AI-generated categories
- `ai_categorize_commits.rb` script with dry-run, force, limit, and debug modes
- Category validation to prevent invalid entries in the database
- Comprehensive test coverage for LLM integration
- Project cover image (`docs/MetricMindCover.jpeg`)
- AI configuration section in `.env.example`

### Changed
- Enhanced `categorize_commits.rb` with category validation
- Updated all documentation (CLAUDE.md, README.md) with AI categorization workflows
- Added `langchainrb` dependency for LLM integration
- Migration 004: Added AI categorization support to database schema

### Notes
- This release represents the first production-ready version with complete AI-powered analytics
- Two-stage categorization: pattern-based (fast) → AI-powered (intelligent)
- Supports both cloud (Gemini) and local (Ollama) LLM providers

## [0.4.4] - 2025-11-16

### Fixed
- Weight calculation refactor: eliminated double-counting issue in revert/unrevert logic
- Removed incorrect `process_unrevert()` method that was inflating metrics

### Changed
- Cleaned up misleading statistics in weight calculation
- Updated tests to reflect correct revert handling behavior

## [0.4.3] - 2025-11-16

### Changed
- Enhanced README.md with comprehensive database schema documentation
- Added detailed table and column descriptions
- Improved documentation clarity for database structure

## [0.4.2] - 2025-11-16

### Added
- Repository description field support throughout the data pipeline
- Description field in JSON exports (`repository_description`)
- Description population in database loading process

### Changed
- Updated `git_extract_to_json.rb` to include repository descriptions
- Updated `load_json_to_db.rb` to handle description field
- Modified `run.rb` to pass descriptions through the pipeline

## [0.4.1] - 2025-11-15

### Added
- `repositories.example.json` template file for repository configuration

### Changed
- Updated `.gitignore` to exclude `repositories.json` from version control
- Removed `repositories.json` from repository (use example file as template)

## [0.4.0] - 2025-11-15

### Changed
- Migrated execution script from Bash to Ruby (`run.sh` → `run.rb`)
- Migrated setup script from Bash to Ruby (`setup.sh` → `setup.rb`)
- Improved cross-platform compatibility and error handling
- Enhanced script maintainability with Ruby implementation

### Removed
- Legacy Bash scripts (`run.sh`, `setup.sh`)

## [0.3.0] - 2025-11-12

### Added
- Commit weight tracking for measuring commit validity (0-100 scale)
- AI tools detection from commit messages (e.g., "Cursor", "Copilot")
- `calculate_commit_weights.rb` script for revert detection and weight calculation
- `weight` and `ai_tools` columns to commits table
- Migration 003: Added weight and ai_tools support
- Test suite for AI tools and weight tracking (`ai_tools_and_weight_spec.rb`)

### Changed
- Updated all database views to include `weight` and `ai_tools` columns
- Enhanced `git_extract_to_json.rb` to extract AI tool mentions
- Updated analytics to support weighted metrics

### Notes
- Weight system: 0 = reverted commit, 100 = valid commit
- Enables tracking of AI tool adoption and impact on productivity

## [0.2.2] - 2025-11-10

### Added
- `DATABASE_URL` environment variable support for connection strings
- `lib/db_connection.rb` helper module for centralized database connectivity
- `test_db_connection.rb` script for connection validation
- Support for remote/hosted databases (Neon, Heroku, etc.)

### Changed
- Updated all scripts to use centralized connection helper
- Enhanced `.env.example` with DATABASE_URL documentation
- Improved database connection reliability and error handling

## [0.2.1] - 2025-11-09

### Added
- Users table for Google OAuth authentication support
- Migration 002: OAuth authentication schema
- Foundation for future dashboard authentication

### Changed
- Updated README with authentication documentation

## [0.2.0] - 2025-11-09

### Added
- Commit categorization feature for business domain tracking
- `CLAUDE.md` file for AI assistant guidance
- `categorize_commits.rb` script for pattern-based category extraction
- Category-specific analytics views:
  - `v_category_stats` - Overall category statistics
  - `v_category_by_repo` - Category breakdown by repository
  - `mv_monthly_category_stats` - Monthly category trends (materialized)
  - `v_uncategorized_commits` - Monitoring view for coverage
- Migration 001: Added commit categorization support
- Database migration system with numbered SQL files

### Changed
- Enhanced README with categorization workflow documentation
- Updated `setup.sh` to automatically apply database migrations

### Notes
- Introduces the concept of extracting business domains from commit messages
- Pattern-based extraction using pipes, brackets, and first uppercase words
- Foundation for later AI-powered categorization

## [0.1.1] - 2025-11-08

### Changed
- Updated `repositories.json` with additional application configurations
- Enhanced README.md with improved documentation and examples

## [0.1.0] - 2025-11-07

### Added
- Initial project setup and foundation
- Core data pipeline: Extract → Load → Analyze
- `git_extract_to_json.rb` - Git history extraction to JSON
- `load_json_to_db.rb` - JSON to PostgreSQL loader
- `clean_repository.rb` - Repository data cleanup utility
- PostgreSQL schema with commits and repositories tables
- Database views for analytics:
  - `v_daily_stats_by_repo` - Daily commit statistics
  - `v_weekly_stats_by_repo` - Weekly aggregations
  - `mv_monthly_stats_by_repo` - Monthly trends (materialized)
- Configuration files:
  - `.env.example` - Environment configuration template
  - `repositories.json` - Repository tracking configuration
  - `.rspec` - RSpec test configuration
  - `.tool-versions` - asdf version management
- Gemfile with dependencies:
  - `pg` - PostgreSQL adapter
  - `rspec` - Testing framework
  - `rubocop` - Code linting
- Integration test suite
- Comprehensive README with architecture and usage documentation

### Notes
- First release establishing the core Git productivity analytics system
- Supports multiple repository tracking and aggregation
- Foundation for measuring developer productivity and tool impact
