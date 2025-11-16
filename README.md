# Git Productivity Analytics Dashboard

An AI-driven developer productivity analytics system that extracts, stores, and visualizes git commit data from multiple repositories to measure the impact of development tools and practices.

## Overview

This system provides comprehensive analytics to answer questions like:
- How do commit patterns change over time?
- What's the impact of new AI tools on developer productivity?
- Which contributors are most active across projects?
- How do different repositories compare in terms of activity?

### Architecture

```
┌─────────────────┐
│ Git Repos       │
│ (Multiple)      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Extract Script  │ ← git_extract_to_json.rb
│ (per repo)      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ JSON Files      │ ← Intermediate storage
│ (per repo)      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Load Script     │ ← load_json_to_db.rb
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ PostgreSQL DB   │
│ ┌─────────────┐ │
│ │ Raw Commits │ │ ← Per-commit detail
│ └─────────────┘ │
│ ┌─────────────┐ │
│ │ Aggregations│ │ ← Views for queries
│ └─────────────┘ │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Dashboard       │ ← Replit frontend
│ (Coming soon)   │
└─────────────────┘
```

## Quick Start

### Complete Setup in 4 Steps

```bash
# 1. Run automated setup
./scripts/setup.rb

# 2. Edit configuration files
vim .env                        # Database credentials (if needed)
vim config/repositories.json    # Add your repositories

# 3. Extract and analyze
./scripts/run.rb                # Automatic extraction, loading, categorization

# 4. Query your data
psql -d git_analytics -c "SELECT * FROM v_category_stats;"
```

That's it! The system automatically handles schema setup, migrations, data extraction, commit categorization, weight calculation, and view optimization.

**What happens automatically:**
- ✅ Database creation and schema initialization
- ✅ Migration application (weight, ai_tools, category columns)
- ✅ View creation (standard + category + AI tools analytics)
- ✅ Git data extraction from all repositories (with full commit messages)
- ✅ AI tools extraction from commit bodies
- ✅ Commit categorization (business domain extraction)
- ✅ Weight calculation (revert detection for accurate metrics)
- ✅ Materialized view refresh (weighted and unweighted metrics)

The setup procedure supports two modes:

Full Setup Mode (default):
`./scripts/setup.rb`

- [1/6] Check prerequisites (Ruby, PostgreSQL)
- [2/6] Install Ruby dependencies
- [3/6] Create .env file
- [4/6] Create databases (production + test)
- [5/6] Initialize schemas + migrations + views
- [6/6] Create data directories

Database-Only Mode:
`./scripts/setup.rb --database-only`

- [1/3] Check PostgreSQL only
- [2/3] Create databases (production + test)
- [3/3] Initialize schemas + migrations + views

---

### Prerequisites

Before starting, ensure you have:
- **Ruby** >= 3.3 ([Installation guide](https://www.ruby-lang.org/en/documentation/installation/))
- **PostgreSQL** >= 12 ([Installation guide](https://www.postgresql.org/download/))
- **Git repositories** to analyze

### Automated Setup (Recommended)

The fastest way to get started is using the automated setup script:

```bash
# Clone or navigate to the project directory
cd MetricMind

# Run the automated setup script
./scripts/setup.rb
```

**What this script does:**
1. ✅ Checks prerequisites (Ruby, PostgreSQL)
2. ✅ Installs Ruby dependencies (`bundle install`)
3. ✅ Creates `.env` file from template
4. ✅ Creates production and test databases
5. ✅ Initializes database schema and views (including migrations)
6. ✅ Creates necessary directories (`data/exports/`)

After the script completes, you'll be prompted to:
- Edit your `.env` file with database credentials (if needed)
- Configure repositories in `config/repositories.json`

### Manual Setup (Alternative)

If you prefer manual setup or need more control:

#### 1. Install Dependencies

```bash
# Install Ruby dependencies
bundle install

# Copy environment configuration
cp .env.example .env
# Edit .env with your database credentials
```

#### 2. Database Setup

```bash
# Run database-only setup (creates database, applies schema, migrations, and views)
./scripts/setup.rb --database-only
```

This will:
- Create the database if it doesn't exist
- Apply the base schema
- Run all migrations (including category column for business domain tracking)
- Create standard views and category views

**Note:** This skips Ruby dependencies and .env setup. Use `./scripts/setup.rb` (without flags) for complete first-time setup.

#### 3. Database Migration

Manually Apply the Migration

E.g. `psql -d git_analytics -f schema/migrations/002_add_users_and_oauth.sql`

This will:
- Create the users table, the indexes etc.
- Keep all your existing data intact

#### 4. Configure Repositories

Edit `config/repositories.json` to add your repositories:

```json
{
  "repositories": [
    {
      "name": "my-backend",
      "path": "/absolute/path/to/repo",
      "description": "Backend API",
      "enabled": true
    },
    {
      "name": "my-frontend",
      "path": "/absolute/path/to/frontend",
      "description": "React Frontend",
      "enabled": true
    }
  ]
}
```

**Note:** Database connection and extraction settings are configured via `.env` file (see Environment Variables section below). The `config/repositories.json` file only contains the list of repositories to track.

### Extract and Load Data

```bash
# Run extraction and loading for all configured repositories
./scripts/run.rb

# Or run for specific date range
./scripts/run.rb --from "1 year ago" --to "now"

# Process single repository
./scripts/run.rb mater

# Clean before processing (useful for fixing duplicate data)
./scripts/run.rb --clean
```

The `run.rb` script automatically:
- Extracts git data from repositories (including full commit messages)
- Extracts AI tools information from commit bodies
- Loads data into the database
- **Categorizes commits** (extracts business domains from commit messages)
- **Calculates commit weights** (detects and marks reverted commits)
- **Refreshes materialized views** (for fast dashboard queries with weighted metrics)

No additional steps needed - everything runs automatically!

**What's included:**
- ✅ Git data extraction from all configured repositories
- ✅ AI tools tracking (extracts tools like Claude Code, Cursor, GitHub Copilot from commit bodies)
- ✅ Database loading with duplicate prevention
- ✅ **Automatic commit categorization** (extracts business domains like BILLING, CS, INFRA from commit messages)
- ✅ **Weight calculation** (detects revert/unrevert patterns and adjusts commit weights for accurate productivity metrics)
- ✅ **Materialized view refresh** (ensures dashboard queries are fast, includes both weighted and unweighted metrics)

See sections below for details on:
- [Commit Categorization](#commit-categorization)
- [Weight Calculation (Revert Detection)](#weight-calculation-revert-detection)
- [AI Tools Tracking](#ai-tools-tracking)

## Usage

### Single Repository Extraction

Extract git data from a single repository:

```bash
./scripts/git_extract_to_json.rb FROM_DATE TO_DATE OUTPUT_FILE [REPO_NAME] [REPO_PATH]
```

Examples:
```bash
# Extract last 6 months from current repository
./scripts/git_extract_to_json.rb "6 months ago" "now" "data/my-repo.json"

# Extract specific date range from another repository
./scripts/git_extract_to_json.rb "2025-01-01" "2025-12-31" "data/backend.json" "backend-api" "/path/to/repo"
```

### Load Data to Database

Load JSON export into PostgreSQL:

```bash
./scripts/load_json_to_db.rb JSON_FILE
```

Example:
```bash
./scripts/load_json_to_db.rb data/my-repo.json
```

### Multi-Repository Processing

Process multiple repositories automatically:

```bash
# Extract and load all enabled repositories (default config)
./scripts/run.rb

# Use custom config file
./scripts/run.rb --config config/my-repos.json

# Override date range
./scripts/run.rb --from "3 months ago" --to "now"

# Process single repository
./scripts/run.rb mater

# Advanced workflows
./scripts/run.rb --clean                    # Clean all repos before processing
./scripts/run.rb mater --clean              # Clean single repo before processing
./scripts/run.rb --skip-load                # Only extract to JSON (no database)
./scripts/run.rb --skip-extraction          # Only load from existing JSON files
./scripts/run.rb mater --from "2024-01-01" --to "2024-12-31"
```

## Database Schema

### Tables

#### `repositories`
Stores metadata about tracked repositories.

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL | Primary key |
| name | VARCHAR(255) | Repository name (unique) |
| url | TEXT | Repository URL or path |
| description | TEXT | Optional description |
| last_extracted_at | TIMESTAMP | Last extraction timestamp |

#### `commits`
Stores per-commit data (granular level).

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL | Primary key |
| repository_id | INTEGER | Foreign key to repositories |
| hash | VARCHAR(40) | Git commit SHA |
| commit_date | TIMESTAMP | Commit date |
| author_name | VARCHAR(255) | Author name |
| author_email | VARCHAR(255) | Author email |
| subject | TEXT | Commit message (first line) |
| lines_added | INTEGER | Lines added (excluding binary) |
| lines_deleted | INTEGER | Lines deleted (excluding binary) |
| files_changed | INTEGER | Number of files modified |
| category | VARCHAR(100) | Business domain category (e.g., BILLING, CS, INFRA) |
| weight | INTEGER | Commit validity weight (0-100). Reverted commits = 0, valid commits = 100 |
| ai_tools | VARCHAR(255) | AI tools used (e.g., CLAUDE CODE, CURSOR, GITHUB COPILOT) |

**Unique constraint**: `(repository_id, hash)` - prevents duplicate commits

### Views and Aggregations

#### Standard Views

**`v_commit_details`**
Commits with repository information, weight, ai_tools, category, and calculated lines_changed.

**`v_daily_stats_by_repo`**
Daily aggregated statistics per repository. Includes both weighted and unweighted metrics. Excludes reverted commits (weight=0).

**`v_weekly_stats_by_repo`**
Weekly aggregated statistics per repository. Includes both weighted and unweighted metrics. Excludes reverted commits (weight=0).

**`mv_monthly_stats_by_repo` (Materialized)**
Pre-computed monthly statistics per repository for fast queries. Excludes reverted commits (weight=0).

Columns include:
- Unweighted: `total_commits`, `total_lines_added`, `total_lines_deleted`, `total_files_changed`
- Weighted: `weighted_lines_added`, `weighted_lines_deleted`, `weighted_lines_changed`, `weighted_files_changed`
- `unique_authors`, `avg_lines_changed_per_commit`, `avg_lines_added_per_commit`
- `avg_lines_added_per_author`, `avg_commits_per_author`

**`v_contributor_stats`**
Aggregated statistics per contributor across all repositories. Includes both weighted and unweighted metrics. Excludes reverted commits (weight=0).

#### Category Views

**`v_category_stats`**
Category statistics across all repositories. Shows commit volume by business domain (e.g., BILLING, CS, INFRA).

**`v_category_by_repo`**
Category breakdown per repository. Shows which repos work on which categories.

**`mv_monthly_category_stats` (Materialized)**
Monthly trends by category. Shows how work distribution across business domains changes over time.

**`v_uncategorized_commits`**
Commits missing category - useful for cleanup and improving coverage.

#### AI Tools Views

**`v_ai_tools_stats`**
Statistics on AI tools usage across all repositories. Shows adoption and impact of development tools.

**`v_ai_tools_by_repo`**
AI tools usage broken down by repository.

#### Revert Tracking Views

**`v_reverted_commits`**
Commits with weight=0 (reverted commits) for quality analysis.

### Refreshing Materialized Views

After loading new data, refresh materialized views:

```sql
-- Refresh all standard materialized views
SELECT refresh_all_mv();

-- Refresh all category materialized views
SELECT refresh_category_mv();
```

Or manually:
```sql
REFRESH MATERIALIZED VIEW mv_monthly_stats_by_repo;
REFRESH MATERIALIZED VIEW mv_monthly_category_stats;
```

**Note:** When using `./scripts/run.rb`, materialized views are refreshed automatically.

## Query Examples

### Monthly trends for a specific repository

```sql
SELECT
    year_month,
    total_commits,
    total_lines_changed,
    unique_authors,
    avg_lines_changed_per_commit,
    avg_commits_per_author
FROM mv_monthly_stats_by_repo
WHERE repository_name = 'backend-api'
ORDER BY month_start_date DESC;
```

### Top contributors across all repositories

```sql
SELECT
    author_name,
    total_commits,
    repositories_contributed,
    total_lines_changed,
    avg_lines_changed_per_commit
FROM v_contributor_stats
ORDER BY total_commits DESC
LIMIT 10;
```

### Daily activity for last 30 days

```sql
SELECT
    commit_date,
    repository_name,
    total_commits,
    total_lines_changed,
    unique_authors
FROM v_daily_stats_by_repo
WHERE commit_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY commit_date DESC;
```

### Compare repositories

```sql
SELECT
    repository_name,
    SUM(total_commits) as commits,
    SUM(total_lines_changed) as lines_changed,
    COUNT(DISTINCT year_month) as months_active,
    AVG(unique_authors) as avg_authors_per_month
FROM mv_monthly_stats_by_repo
WHERE month_start_date >= '2025-01-01'
GROUP BY repository_name
ORDER BY commits DESC;
```

### Before/After analysis (e.g., AI tool adoption)

```sql
-- Before AI tools (e.g., July-August 2025)
SELECT
    AVG(avg_lines_changed_per_commit) as avg_lines_per_commit,
    AVG(total_commits) as avg_commits_per_month,
    AVG(unique_authors) as avg_authors
FROM mv_monthly_stats_by_repo
WHERE month_start_date BETWEEN '2025-07-01' AND '2025-08-31'
    AND repository_name = 'backend-api';

-- After AI tools (e.g., September-October 2025)
SELECT
    AVG(avg_lines_changed_per_commit) as avg_lines_per_commit,
    AVG(total_commits) as avg_commits_per_month,
    AVG(unique_authors) as avg_authors
FROM mv_monthly_stats_by_repo
WHERE month_start_date BETWEEN '2025-09-01' AND '2025-10-31'
    AND repository_name = 'backend-api';
```

## Data Format

### JSON Export Format

```json
{
  "repository": "my-app",
  "repository_path": "/path/to/repo",
  "extraction_date": "2025-11-07T10:30:00Z",
  "date_range": {
    "from": "6 months ago",
    "to": "now"
  },
  "summary": {
    "total_commits": 150,
    "total_lines_added": 12500,
    "total_lines_deleted": 3200,
    "total_files_changed": 450,
    "unique_authors": 8
  },
  "commits": [
    {
      "hash": "abc123def456...",
      "date": "2025-10-15T14:30:00Z",
      "author_name": "John Doe",
      "author_email": "john@example.com",
      "subject": "Fix authentication bug",
      "lines_added": 50,
      "lines_deleted": 20,
      "files_changed": 3,
      "files": [
        {
          "filename": "src/auth.js",
          "added": 30,
          "deleted": 15
        }
      ]
    }
  ]
}
```

## Testing

Run the test suite:

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/git_extract_to_json_spec.rb

# Run with documentation format
bundle exec rspec --format documentation
```

## Environment Variables

Configure via `.env` file or environment:

```bash
# Database connection
# Option 1: Use DATABASE_URL (recommended for remote/hosted databases like Neon, Heroku, etc.)
# DATABASE_URL=postgresql://user:password@host:port/database?sslmode=require

# Option 2: Use individual connection parameters (local development)
PGHOST=localhost
PGPORT=5432
PGDATABASE=git_analytics
PGUSER=your_username
PGPASSWORD=your_password

# Note: DATABASE_URL takes priority over individual parameters if both are set

# PostgreSQL Test Database Configuration
PGDATABASE_TEST=git_analytics_test

# Optional: Default extraction dates
DEFAULT_FROM_DATE="6 months ago"
DEFAULT_TO_DATE="now"

# Optional: Output directory
OUTPUT_DIR=./data/exports
```

## Deployment

### Local Development

1. Run PostgreSQL locally
2. Initialize database schema
3. Configure repositories
4. Run extraction

### Production (Cloud)

1. **Database**: Use managed PostgreSQL (AWS RDS, Google Cloud SQL, Heroku Postgres, Neon)
2. **Extraction**: Run as scheduled job (cron, GitHub Actions, Cloud Scheduler)
3. **Dashboard**: Deploy to Vercel, Netlify, or keep on Replit

#### Using Remote PostgreSQL (e.g., Neon)

For cloud-hosted PostgreSQL services, use the `DATABASE_URL` environment variable:

```bash
# In your .env file or CI/CD environment
DATABASE_URL=postgresql://user:password@host:port/database?sslmode=require
```

This is the recommended approach for services like:
- **Neon** - Serverless PostgreSQL
- **Heroku Postgres** - Managed PostgreSQL on Heroku
- **Supabase** - Open source Firebase alternative
- **Railway** - Modern deployment platform

The connection string includes SSL configuration which is typically required by hosted services.

Example GitHub Actions workflow:

```yaml
name: Extract Git Data
on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly on Sunday at 2 AM
  workflow_dispatch:

jobs:
  extract:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
      - run: bundle install
      - run: ./scripts/run.rb
        env:
          PGHOST: ${{ secrets.PGHOST }}
          PGDATABASE: ${{ secrets.PGDATABASE }}
          PGUSER: ${{ secrets.PGUSER }}
          PGPASSWORD: ${{ secrets.PGPASSWORD }}
```

## Troubleshooting

### Database connection errors

```bash
# Test connection
psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "SELECT version();"

# Check if database exists
psql -l | grep git_analytics
```

### Schema not initialized

```bash
# Reinitialize schema
psql -d git_analytics -f schema/postgres_schema.sql
psql -d git_analytics -f schema/postgres_views.sql
```

### No commits extracted

- Verify git repository path is correct
- Check date range includes commits: `git log --since="FROM" --until="TO" --oneline`
- Ensure you're on the correct branch

### Duplicate commits

The system handles duplicates automatically using `ON CONFLICT DO NOTHING`. Re-running extraction is safe and will only insert new commits.

If you need to clean and reload data for a repository (e.g., after accidentally loading duplicate data):

```bash
# Clean and reload single repository (prompts for confirmation)
./scripts/run.rb mater --clean

# Or use the cleanup script directly
./scripts/clean_repository.rb mater
```

## Commit Categorization

The categorization feature analyzes commit messages to understand **what** business domains developers are working on. It uses a **two-stage approach**: pattern-based extraction (fast) followed by optional AI-powered categorization (intelligent).

### Overview

Categorization extracts **business domain categories** from commit subjects, enabling insights into resource allocation across different areas of your product (e.g., BILLING, CS, INFRA).

**Note:** Categorization runs **automatically** as part of `./scripts/run.rb`. You don't need to run any manual commands unless you want to re-categorize existing data or check coverage.

### Two-Stage Categorization

#### Stage 1: Pattern-Based Extraction (Always Active)

Categories are extracted from commit subjects using multiple patterns:

1. **Pipe delimiter**: `BILLING | Implemented payment gateway` → **BILLING**
2. **Square brackets**: `[CS] Fixed widget display` → **CS**
3. **First uppercase word**: `BILLING Implemented feature` → **BILLING**
4. **No match**: → NULL (moves to Stage 2 if AI enabled)

This stage is fast, requires no external services, and works well for teams using standardized commit message formats.

#### Stage 2: AI-Powered Categorization (Optional)

For commits that pattern matching couldn't categorize, the system can use Large Language Models (LLMs) to intelligently categorize based on:
- Commit subject (message)
- **Modified file paths** (strong signal, e.g., `app/jobs/billing/*` → BILLING)
- Existing categories (ensures consistency)

**Key Features:**
- 🤖 **Smart categorization** using file paths as context
- 🎯 **Category consistency** - reuses existing categories or creates appropriate new ones
- 🚫 **Validates categories** - automatically rejects version numbers (2.58.0), issue numbers (#6802), and other invalid patterns
- 📊 **Confidence scoring** - tracks how confident the AI is about each categorization
- 🔄 **Fallback pattern** - only processes uncategorized commits (efficient)

**Supported Providers:**
- **Ollama** (free, local) - Run models like llama3.2, mistral, codellama on your machine
- **Google Gemini** (cloud, API key required) - Fast and accurate cloud-based categorization

### Getting Started with AI Categorization

#### First-Time Setup

1. **Choose your provider and configure `.env`:**

**Option A: Ollama (Local, Free)**
```bash
# Install Ollama
brew install ollama  # macOS
# or download from https://ollama.ai

# Start Ollama and pull a model
ollama serve  # In one terminal
ollama pull gpt-oss:20b  # In another terminal

# Configure in .env
AI_PROVIDER=ollama
OLLAMA_URL=http://localhost:11434
OLLAMA_MODEL=gpt-oss:20b
OLLAMA_TEMPERATURE=0.1
PREVENT_NUMERIC_CATEGORIES=true  # Prevents version numbers like "2.58.0"
```

**Option B: Google Gemini (Cloud)**
```bash
# Get API key from https://makersuite.google.com/app/apikey

# Configure in .env
AI_PROVIDER=gemini
GEMINI_API_KEY=your_api_key_here
GEMINI_MODEL=gemini-2.0-flash-exp
GEMINI_TEMPERATURE=0.1
PREVENT_NUMERIC_CATEGORIES=true  # Prevents version numbers like "2.58.0"
```

2. **Apply database migration:**
```bash
# Run setup to apply the AI categorization migration
./scripts/setup.rb --database-only
```

This creates:
- `categories` table - stores approved categories
- `ai_confidence` column in `commits` - tracks AI categorization quality (0-100)

3. **Run the pipeline:**
```bash
# AI categorization runs automatically if AI_PROVIDER is set
./scripts/run.rb

# Or test on a single repository
./scripts/run.rb mater
```

#### Scenario: First Time with Existing Data

If you already have data in your database and want to add AI categorization:

```bash
# 1. Configure AI provider in .env (see above)

# 2. Apply migration
./scripts/setup.rb --database-only

# 3. Preview what AI will categorize (dry-run)
./scripts/ai_categorize_commits.rb --dry-run --limit 10

# 4. Run AI categorization on all uncategorized commits
./scripts/ai_categorize_commits.rb

# 5. Check results
psql -d git_analytics -c "
  SELECT
    COUNT(*) FILTER (WHERE category IS NOT NULL) as categorized,
    COUNT(*) FILTER (WHERE ai_confidence IS NOT NULL) as ai_categorized,
    ROUND(AVG(ai_confidence) FILTER (WHERE ai_confidence IS NOT NULL), 1) as avg_confidence
  FROM commits;
"
```

#### Scenario: Recategorizing Existing Data

To re-run AI categorization (e.g., after improving prompts or switching providers):

```bash
# Preview changes first
./scripts/ai_categorize_commits.rb --dry-run --force --limit 10

# Force recategorization of ALL commits (including already categorized ones)
./scripts/ai_categorize_commits.rb --force

# Or recategorize only a specific repository
./scripts/ai_categorize_commits.rb --force --repo mater
```

**Note:** Using `--force` will re-categorize ALL commits, replacing existing categories. This is safe but may change your historical data.

#### Scenario: Categorizing Only New Commits

The default behavior only processes uncategorized commits:

```bash
# This only categorizes commits where category IS NULL
./scripts/ai_categorize_commits.rb

# Happens automatically with run.rb
./scripts/run.rb
```

This is the recommended workflow for ongoing use.

### Numeric Category Prevention

By default, the system prevents creation of invalid categories.

What Gets Rejected:
  - ❌ Version numbers: `2.26.0`, `1.2.3`, `2.58.0`
  - ❌ Issue numbers: `#5930`, `#6802`, `#117`
  - ❌ Pure numbers: `2023`, `123`, `42`
  - ❌ Anything with #: `#HASHTAG`, `#TAG`
  - ❌ Too many digits: `12345ABC` (>50% digits)

What Gets Accepted:
  - ✅ Business categories: BILLING, CS, SECURITY, API
  - ✅ Technical terms: I18N, L10N, OAUTH2, HTTP2
  - ✅ Number-prefixed: 2FA, 3D, 3D_RENDERING ← NEW!
  - ✅ Anything with ≤50% digits and at least one letter

✅ Valid categories: `BILLING`, `SECURITY`, `DOCKER`, `API`, `DATABASE`

**Configuration:**
```bash
# .env
PREVENT_NUMERIC_CATEGORIES=true  # Default: true (recommended)

# To allow numeric categories (not recommended):
PREVENT_NUMERIC_CATEGORIES=false
```

The AI is explicitly instructed to avoid these patterns, and validation is enforced at the code level.

### Manual Usage (Optional)

Categorization runs automatically with `./scripts/run.rb`, but you can also run it manually:

```bash
# Re-run categorization on all commits (useful after updating commit messages)
./scripts/categorize_commits.rb

# Preview changes without applying (dry-run)
./scripts/categorize_commits.rb --dry-run

# Categorize specific repository only
./scripts/categorize_commits.rb --repo mater
```

### Checking Coverage

```bash
# Check categorization coverage
psql -d git_analytics -c "
  SELECT
    COUNT(*) as total_commits,
    COUNT(category) as categorized,
    ROUND(COUNT(category)::numeric / COUNT(*) * 100, 1) as category_pct
  FROM commits;
"

# View category distribution
psql -d git_analytics -c "SELECT * FROM v_category_stats ORDER BY total_commits DESC;"

# Find uncategorized commits
psql -d git_analytics -c "SELECT * FROM v_uncategorized_commits LIMIT 20;"
```

### Insights Enabled

With categorization, you can answer:
- "How much effort went into BILLING vs CS last quarter?"
- "Which business domains are receiving most attention?"
- "Are certain areas neglected?"
- "How has effort distribution changed over time?"
- "Which categories need more resources?"

### Improving Coverage

To improve categorization coverage:

1. **Standardize commit message format** - Encourage your team to use consistent prefixes:
   ```
   BILLING | Description
   CS | Description
   INFRA | Description
   ```

2. **Update old commits manually** if needed:
   ```sql
   -- Categorize commits containing "billing" keyword
   UPDATE commits SET category = 'BILLING'
   WHERE subject ILIKE '%billing%' AND category IS NULL;

   -- Categorize commits containing "customer service" or "cs"
   UPDATE commits SET category = 'CS'
   WHERE (subject ILIKE '%customer service%' OR subject ILIKE '% cs %')
     AND category IS NULL;
   ```

3. **Document your categories** - Create a team guideline listing all valid categories

### Database Views

Leverage existing views and materialized views:

- `mv_monthly_stats_by_repo` - Pre-computed monthly statistics
- `v_contributor_stats` - Aggregated contributor data
- `v_daily_stats_by_repo` - Daily activity aggregations
- `v_commit_details` - Detailed commit information with repository joins

Categorization creates these views:

- `v_category_stats` - Category statistics across all repos
- `v_category_by_repo` - Category breakdown per repository
- `mv_monthly_category_stats` - Monthly category trends (materialized)
- `v_uncategorized_commits` - Commits missing categories

### Maintenance

**Note:** When you run `./scripts/run.rb`, categorization and view refresh happen **automatically**. No manual maintenance needed!

If you need to manually refresh views (e.g., after manual database updates):
```bash
# Refresh materialized views
psql -d git_analytics -c "SELECT refresh_category_mv();"
```

## Weight Calculation (Revert Detection)

The weight calculation feature tracks commit validity by detecting reverted commits, enabling **accurate productivity metrics** that exclude work that was later reverted.

### Overview

Commits have a `weight` field (0-100) that reflects their validity:
- **weight = 100**: Valid commit (default)
- **weight = 0**: Reverted commit (excluded from weighted metrics)

This allows analytics to distinguish between:
- **Total metrics**: All commits, including reverted ones
- **Weighted metrics**: Only valid work (reverted commits weighted at 0)

**Note:** Weight calculation runs **automatically** as part of `./scripts/run.rb`. No manual intervention needed!

### How It Works

The system detects revert patterns in commit subjects and automatically adjusts weights:

**Example workflow:**
```
1. CS | Move HTML content (!10463)              → weight = 100 (valid)
2. Revert "CS | Move HTML content (!10463)"     → weight = 0 (revert)
   ↳ Also sets commit #1 to weight = 0 (because it was reverted)
3. Unrevert !10463 and fix error (!10660)       → weight = 100 (valid)
   ↳ Unrevert commit contains the work from commit #1, so it counts once
   ↳ Commit #1 stays at weight = 0 to avoid double-counting
```

**Detection logic:**
- **"Revert" keyword**: Identifies revert commits (case-insensitive)
- **PR/MR numbers**: Links reverts to original commits via `(!12345)` or `(#12345)`
- **"Unrevert" keyword**: Prevents unrevert commits from being treated as reverts (they keep weight = 100)

**Important:** When a commit is unreverted, the unrevert commit itself contains all the work from the original commit (often with additional fixes). The original commit stays at weight=0 to prevent double-counting the same work.

### Manual Usage (Optional)

Weight calculation runs automatically with `./scripts/run.rb`, but you can also run it manually:

```bash
# Calculate weights for all commits
./scripts/calculate_commit_weights.rb

# Preview changes without applying (dry-run)
./scripts/calculate_commit_weights.rb --dry-run

# Calculate weights for specific repository only
./scripts/calculate_commit_weights.rb --repo mater
```

### Querying Weighted Metrics

All analytics views include both weighted and unweighted metrics:

```sql
-- Compare unweighted vs weighted lines changed
SELECT
  repository_name,
  year_month,
  total_lines_changed,           -- All commits
  weighted_lines_changed         -- Excluding reverted work
FROM mv_monthly_stats_by_repo
WHERE repository_name = 'MyApp'
ORDER BY year_month DESC;

-- Find all reverted commits
SELECT * FROM v_reverted_commits
ORDER BY commit_date DESC
LIMIT 20;

-- Calculate revert rate
SELECT
  COUNT(CASE WHEN weight = 0 THEN 1 END) as reverted,
  COUNT(*) as total,
  ROUND(COUNT(CASE WHEN weight = 0 THEN 1 END)::numeric / COUNT(*) * 100, 1) as revert_pct
FROM commits;
```

### Benefits

- **Accurate productivity metrics**: Exclude reverted work from calculations
- **Quality insights**: Track revert rates to measure code quality
- **Before/after analysis**: Compare weighted vs unweighted metrics to assess tool impact
- **Team health**: High revert rates may indicate rushed work or insufficient testing

## AI Tools Tracking

The AI tools tracking feature automatically extracts information about AI development tools used for each commit, enabling **direct measurement of AI tool impact on productivity**.

### Overview

Commits can include AI tool information in their message body:
- Extracted automatically during git data extraction
- Stored in the `ai_tools` field (VARCHAR, nullable)
- Normalized to uppercase for consistency (e.g., "CLAUDE CODE", "CURSOR", "GITHUB COPILOT")

**Note:** AI tools are extracted **automatically** during data extraction. Simply include tool information in commit messages!

### Commit Message Format

To track AI tool usage, include this format in your commit message **body** (not subject):

```
Your commit subject here

**AI tool: Claude Code**

Rest of commit description...
```

**Supported formats:**
- `**AI tool: Claude Code**`
- `**AI tools: Claude Code and Copilot**`
- `**AI tool: Cursor and GitHub Copilot**`
- `AI tool: Claude Code` (without asterisks)
- Case-insensitive

**Supported tools** (automatically normalized):
- Claude Code
- Claude
- Cursor
- GitHub Copilot / Copilot
- Any custom tool name (will be uppercased)

### Querying AI Tools Data

Use the AI tools views for analysis:

```sql
-- Overall AI tools usage statistics
SELECT * FROM v_ai_tools_stats
ORDER BY total_commits DESC;

-- AI tools usage by repository
SELECT * FROM v_ai_tools_by_repo
WHERE repository_name = 'MyApp'
ORDER BY total_commits DESC;

-- Compare productivity with/without AI tools
SELECT
  CASE
    WHEN ai_tools IS NOT NULL THEN 'With AI Tools'
    ELSE 'Without AI Tools'
  END as tool_usage,
  COUNT(*) as commits,
  ROUND(AVG(lines_added + lines_deleted), 1) as avg_lines_per_commit,
  ROUND(SUM((lines_added + lines_deleted) * weight / 100.0), 0) as total_weighted_lines
FROM commits
GROUP BY (CASE WHEN ai_tools IS NOT NULL THEN 'With AI Tools' ELSE 'Without AI Tools' END);

-- Monthly trend of AI tool adoption
SELECT
  TO_CHAR(commit_date, 'YYYY-MM') as month,
  COUNT(*) FILTER (WHERE ai_tools IS NOT NULL) as with_ai,
  COUNT(*) as total,
  ROUND(COUNT(*) FILTER (WHERE ai_tools IS NOT NULL)::numeric / COUNT(*) * 100, 1) as ai_usage_pct
FROM commits
GROUP BY TO_CHAR(commit_date, 'YYYY-MM')
ORDER BY month DESC;
```

### Benefits

- **Measure AI impact**: Directly compare productivity metrics with/without AI tools
- **Tool comparison**: Evaluate different AI tools' effectiveness
- **Adoption tracking**: Monitor AI tool usage trends over time
- **ROI analysis**: Quantify the impact of AI tool investment
- **Team insights**: Identify which developers benefit most from AI tools

### Best Practices

1. **Consistent format**: Train your team to use the standard `**AI tool: ...**` format
2. **Commit body, not subject**: Place AI tool info in the commit body, not the subject line
3. **Be specific**: List all tools used (e.g., "Claude Code and GitHub Copilot")
4. **Regular usage**: Add AI tool info whenever applicable to build comprehensive data

## Building the Dashboard on Replit

This section provides functional requirements and specifications for building an interactive analytics dashboard on Replit. Replit will handle the technical implementation details.

### Dashboard Purpose

This is the dashboard for MetricMind project in which we collect data from various git repositories to provide an overview of our progress.
The dashboard should provide an intuitive, visually appealing interface to explore git productivity metrics and answer key questions:
- How is productivity trending over time?
  - Overview
    - Totals (repositories, commits, contributors)
    - Repositories detail: description, Commits, Contributors, last update
    - repositories comparison
  - The commits trend for all repository or a selected one
  - A line chart "Lines Changed vs Added vs Deleted" 
  - Three cards: "Avg Commits/Month", "Avg Lines/Commit", "Avg Contributors/Month"
  - Filters: repository, the period (last 3, 6, 12, 24 months, all), a checkox per committer
    - per committer means, for example, if the trend shows the 200 commits at "2025-10" for "All repositories" -> if the user clicks on the checkbox "per commmitter" and supposing the total number of committers is 45, we show 4.4 (200/45).
- Who are the most active contributors?
  - consider committers could have different domain e.g. foo.bar@iubenda.com and foo.bar@team.blue, but we can use the name to indentify it
  - filters: repository, period, email (e.g. @team.blue will only compare email with this domain)

### Architecture Overview

```
┌─────────────────────────────────────────┐
│         Web Frontend (Browser)          │
│   ┌─────────────────────────────────┐   │
│   │ Dashboard Views                 │   │
│   │  • Overview                     │   │
│   │  • Trends                       │   │
│   │  • Contributors                 │   │
│   │  • Activity                     │   │
│   │  • Comparison                   │   │
│   │  • Before/After Analysis        │   │
│   └─────────────────────────────────┘   │
└───────────────┬─────────────────────────┘
                │ HTTP requests
                ▼
┌─────────────────────────────────────────┐
│           REST API Server               │
│  (Connects to existing PostgreSQL DB)  │
└─────────────────────────────────────────┘
```

### Required API Endpoints

The backend should expose these RESTful endpoints to serve data to the frontend:

#### Repository Management
- **GET /api/repos** - List all repositories with summary statistics
  - Returns: Repository ID, name, description, total commits, latest commit date, contributor count

#### Trends & Analytics
- **GET /api/monthly-trends** - Global monthly trends across all repositories
  - Returns: Aggregated monthly data for all repositories combined
  - Fields: month, total commits, total lines changed, unique authors, avg lines per commit

- **GET /api/monthly-trends/:repoName** - Monthly trends for a specific repository
  - Returns: Monthly statistics for the specified repository
  - Fields: month, commits, lines added/deleted, authors, averages per author

#### Contributors
- **GET /api/contributors** - Top contributors across all repositories
  - Query params: `limit` (default: 20)
  - Returns: Contributor name, email, total commits, repositories contributed to, lines changed
  - Sorted by: Total commits (descending)

#### Activity
- **GET /api/daily-activity** - Daily commit activity
  - Query params: `days` (default: 30)
  - Returns: Date, repository, commits, lines changed, unique authors

#### Comparison & Analysis
- **GET /api/compare-repos** - Compare all repositories side-by-side
  - Returns: Repository statistics for last 6 months
  - Fields: total commits, lines changed, months active, avg authors, avg lines per commit

- **GET /api/before-after/:repoName** - Compare two time periods for impact analysis
  - Query params: `beforeStart`, `beforeEnd`, `afterStart`, `afterEnd`
  - Returns: Average metrics for "before" and "after" periods
  - Use case: Measure impact of tools, processes, or team changes

#### Content Analytics (Categories)
- **GET /api/categories** - Category statistics across all repositories
  - Returns: Category name, total commits, unique authors, repositories, lines changed
  - Sorted by: Total commits (descending)

- **GET /api/categories/:repoName** - Category breakdown for specific repository
  - Returns: Categories with commit counts and metrics for the repository

- **GET /api/category-trends** - Monthly trends by category
  - Query params: `months` (default: 12), `repo` (optional)
  - Returns: Month, category, commits, authors, lines changed
  - Shows how work is distributed across business domains over time

### Dashboard Views

The frontend should provide these main views:

#### 1. Overview Page
**Purpose**: High-level snapshot of all repository activity

**Key Components**:
- Summary statistics cards (total repos, commits, contributors, active repos)
- Repository cards grid showing each repo with key metrics
- Bar chart comparing repositories by commit volume
- Quick access navigation to detailed views

**User Experience**:
- Should load quickly and provide immediate value
- Visual hierarchy emphasizing most important metrics
- Color-coded indicators for activity levels

#### 2. Trends Page
**Purpose**: Visualize productivity patterns over time

**Key Components**:
- Repository selector dropdown (or "All Repositories" for global view)
- Area/line chart showing commit volume over last 12 months
- Line chart comparing lines changed vs added vs deleted
- Summary cards showing averages (commits/month, lines/commit, contributors/month)

**User Experience**:
- Smooth chart animations on load
- Interactive tooltips showing exact values on hover
- Easy toggling between individual repos and global trends
- Visual indicators for trends (increasing/decreasing)

#### 3. Contributors Page
**Purpose**: Recognize and analyze contributor activity

**Key Components**:
- "Podium" visual for top 3 contributors (🏆 1st, 🥈 2nd, 🥉 3rd)
- Horizontal bar chart showing top 15-20 contributors
- Detailed table with sortable columns:
  - Rank, Name, Email
  - Total commits, Repositories contributed
  - Lines changed, Average lines per commit
- Filter/search capability

**User Experience**:
- Gamification elements to make it engaging
- Clear visual hierarchy (top 3 stand out)
- Easy identification of most active contributors
- Responsive table that works on mobile

#### 4. Activity Page
**Purpose**: Track day-to-day commit patterns

**Key Components**:
- Calendar heatmap showing commit activity (darker = more commits)
- Timeline view showing recent commits
- Activity distribution charts (by day of week, hour of day)
- Repository filter to focus on specific projects

**User Experience**:
- Quick identification of high/low activity periods
- Visual patterns reveal work habits
- Interactive filtering and date range selection

#### 5. Comparison Page
**Purpose**: Compare repositories side-by-side

**Key Components**:
- Side-by-side metrics cards for each repository
- Multi-series bar chart comparing key metrics
- Sortable table showing all comparison metrics
- Percentage indicators showing relative activity

**User Experience**:
- Easy identification of most/least active projects
- Clear visual differentiation between repositories
- Insights into resource allocation and project health

#### 6. Before/After Analysis Page
**Purpose**: Measure impact of changes (new tools, processes, team changes)

**Key Components**:
- Repository selector
- Date range pickers for "Before" and "After" periods
- Split-screen comparison cards showing metrics side-by-side
- Percentage change indicators (↑ ↓) with color coding
- Visualization comparing the two periods

**Metrics to Compare**:
- Average commits per month
- Average lines changed per commit
- Average contributors per month
- Total lines added/deleted

**User Experience**:
- Clear visual separation of "before" vs "after"
- Prominent percentage changes (green for improvement, red for decline)
- Easy reconfiguration of time periods
- Shareable results (export or URL parameters)

#### 7. Content Analysis Page
**Purpose**: Understand **what** business domains developers are working on

**Key Components**:
- Category breakdown (pie/donut chart showing distribution)
  - BILLING, CS, INFRA, etc.
  - Shows which business areas get most development attention
- Category comparison (horizontal bar chart)
  - Compare effort across all categories
  - Easy identification of top/bottom categories
- Trend charts over time
  - How category distribution changes month-to-month
  - Stacked area chart showing category evolution
- Category by repository (matrix/heatmap)
  - Which repos work on which categories
  - Identify domain ownership patterns
- Repository and date range filters

**Insights Provided**:
- Which business domains get most/least attention
- Resource allocation across different work streams
- Evolution of work focus over time
- Domain ownership patterns across repositories
- Neglected areas that may need attention

**User Experience**:
- Interactive charts with drill-down capability
- Filter by repository, date range, and category
- Export view for presentations/reports
- Tooltip showing details on hover
- Color-coding: Different color for each business domain
- Percentage and absolute numbers displayed

**Example Use Cases**:
- "How much effort went into BILLING vs CS last quarter?"
- "Are we neglecting infrastructure work?"
- "Which categories need more resources?"
- "How has our focus shifted after launching the new product?"
- "Which repositories contribute to customer service improvements?"

**Category Extraction Logic**:
Categories are automatically extracted from commit subjects using:
1. Pipe delimiter: `BILLING | Implemented feature` → BILLING
2. Square brackets: `[CS] Fixed bug` → CS
3. First uppercase word: `BILLING Implemented feature` → BILLING
4. If no match: NULL (shown as "UNCATEGORIZED" in UI)

### Design Requirements

**Visual Style**:
- Modern, clean interface with good use of whitespace
- Smooth animations and transitions
- Responsive design (works on desktop, tablet, mobile)
- Dark mode support for reduced eye strain

**Color Scheme**:
- Primary: Blue tones for professionalism and trust
- Secondary: Purple for accent and emphasis
- Success: Green for positive metrics and growth
- Warning: Orange for caution
- Danger: Red for negative trends or issues
- Use gradients for depth and visual interest

**User Experience Principles**:
- **Fast Loading**: Show loading states, but optimize for speed
- **Progressive Disclosure**: Start with overview, allow drilling down
- **Feedback**: Visual feedback for all interactions
- **Consistency**: Consistent patterns across all views
- **Accessibility**: Proper contrast, keyboard navigation, screen reader support

### Deployment Considerations

**Environment Variables**: Configure these in Replit Secrets
- Database connection parameters
- API base URLs (if frontend/backend are separate)
- Any API keys for future integrations

**Performance**:
- Use database connection pooling
- Cache frequently accessed data where appropriate
- Implement pagination for large datasets
- Optimize SQL queries (database already has indexes)

**Security**:
- Enable CORS appropriately
- Validate all inputs
- Use parameterized queries (no SQL injection)
- Don't expose sensitive information in error messages

### Success Metrics

The dashboard should achieve:
- **"WoW Factor"**: Impressive visual design that makes users excited to explore data
- **Insights Clarity**: Users can quickly answer key questions about productivity
- **Performance**: Page loads under 2 seconds, chart animations smooth (60fps)
- **Usability**: New users can navigate without training
- **Responsiveness**: Works well on devices from phone to desktop

### Getting Started with Replit

1. Create a new Repl on [Replit](https://replit.com)
2. Choose appropriate template (Node.js recommended for full-stack)
3. Connect to your existing PostgreSQL database using Replit Secrets
4. Implement the API endpoints according to the specifications above
5. Build the frontend views based on the functional requirements
6. Deploy when ready using Replit's deployment features

Replit will guide you through the technical implementation based on these functional requirements.

## Roadmap

### Phase 1: Data Pipeline ✅
- [x] Git extraction script
- [x] PostgreSQL schema
- [x] Data loading script
- [x] Multi-repository orchestration
- [x] Aggregated views

### Phase 2: Dashboard (In Progress)
- [ ] Replit frontend setup
- [ ] API endpoints for data queries
- [ ] Monthly trend charts
- [ ] Contributor leaderboard
- [ ] Repository comparison view
- [ ] Before/after analysis tool

### Phase 3: Advanced Analytics
- [ ] Predictive trends
- [ ] Anomaly detection
- [ ] Team collaboration patterns
- [ ] Code review metrics
- [ ] Working hours analysis
- [ ] Language/file-type breakdown

### Phase 4: Integrations
- [ ] Jira/Linear integration (feature tracking)
- [ ] Slack notifications
- [ ] GitHub API integration
- [ ] Export to PDF reports
- [ ] BigQuery export option

## Contributing

This is an internal tool. For questions or suggestions, contact the development team.

## License

Internal use only.
