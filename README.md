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

### Prerequisites

- Ruby >= 2.7
- PostgreSQL >= 12
- jq (for orchestration script)
- Git repositories to analyze

### 1. Installation

```bash
# Install Ruby dependencies
bundle install

# Copy environment configuration
cp .env.example .env
# Edit .env with your database credentials
```

### 2. Database Setup

```bash
# Create database
createdb git_analytics

# Initialize schema
psql -d git_analytics -f schema/postgres_schema.sql
psql -d git_analytics -f schema/postgres_views.sql
```

### 3. Configure Repositories

Edit `config/repositories.json` to add your repositories:

```json
{
  "repositories": [
    {
      "name": "my-backend",
      "path": "/absolute/path/to/repo",
      "description": "Backend API",
      "enabled": true
    }
  ]
}
```

**Note:** Database connection and extraction settings are configured via `.env` file (see Environment Variables section below). The `config/repositories.json` file only contains the list of repositories to track.

### 4. Extract and Load Data

```bash
# Run extraction and loading for all configured repositories
./scripts/run.sh

# Or run for specific date range
./scripts/run.sh --from "1 year ago" --to "now"

# Process single repository
./scripts/run.sh mater

# Clean before processing (useful for fixing duplicate data)
./scripts/run.sh --clean
```

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
./scripts/run.sh

# Use custom config file
./scripts/run.sh --config config/my-repos.json

# Override date range
./scripts/run.sh --from "3 months ago" --to "now"

# Process single repository
./scripts/run.sh mater

# Advanced workflows
./scripts/run.sh --clean                    # Clean all repos before processing
./scripts/run.sh mater --clean              # Clean single repo before processing
./scripts/run.sh --skip-load                # Only extract to JSON (no database)
./scripts/run.sh --skip-extraction          # Only load from existing JSON files
./scripts/run.sh mater --from "2024-01-01" --to "2024-12-31"
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

**Unique constraint**: `(repository_id, hash)` - prevents duplicate commits

### Views and Aggregations

#### `v_commit_details`
Commits with repository information joined.

#### `v_daily_stats_by_repo`
Daily aggregated statistics per repository.

#### `v_weekly_stats_by_repo`
Weekly aggregated statistics per repository.

#### `mv_monthly_stats_by_repo` (Materialized)
Pre-computed monthly statistics per repository for fast queries.

Columns include:
- `total_commits`, `total_lines_added`, `total_lines_deleted`
- `unique_authors`, `avg_lines_changed_per_commit`
- `avg_lines_added_per_author`, `avg_commits_per_author`
- Month-over-month comparison data

#### `v_contributor_stats`
Aggregated statistics per contributor across all repositories.

### Refreshing Materialized Views

After loading new data, refresh materialized views:

```sql
SELECT refresh_all_mv();
```

Or manually:
```sql
REFRESH MATERIALIZED VIEW mv_monthly_stats_by_repo;
```

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
PGHOST=localhost
PGPORT=5432
PGDATABASE=git_analytics
PGUSER=your_username
PGPASSWORD=your_password

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

### Replit Deployment

1. Fork this repository to Replit
2. Add PostgreSQL database (Replit provides built-in PostgreSQL)
3. Set environment variables in Replit Secrets
4. Run extraction script
5. Build dashboard using Replit's web interface

### Production (Cloud)

1. **Database**: Use managed PostgreSQL (AWS RDS, Google Cloud SQL, Heroku Postgres)
2. **Extraction**: Run as scheduled job (cron, GitHub Actions, Cloud Scheduler)
3. **Dashboard**: Deploy to Vercel, Netlify, or keep on Replit

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
      - run: ./scripts/run.sh
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
./scripts/run.sh mater --clean

# Or use the cleanup script directly
./scripts/clean_repository.rb mater
```

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
