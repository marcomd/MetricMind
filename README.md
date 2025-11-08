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

- Ruby >= 3.3
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
- Dual-line chart comparing lines added vs deleted
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

### Database Connection

The API should connect to the existing PostgreSQL database created by the data pipeline:
- Use environment variables for credentials (PGHOST, PGDATABASE, PGUSER, PGPASSWORD)
- Leverage existing views and materialized views:
  - `mv_monthly_stats_by_repo` - Pre-computed monthly statistics
  - `v_contributor_stats` - Aggregated contributor data
  - `v_daily_stats_by_repo` - Daily activity aggregations
  - `v_commit_details` - Detailed commit information with repository joins

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
