# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
