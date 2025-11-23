-- Migration: Add Personal Performance Views (Merged Version)
-- Version: 006
-- Description: Creates comprehensive views for personal performance analytics
--              Combines optimizations from both extractor and dashboard implementations
-- Dependencies: Requires commits table with author_email, weight, category columns

-- Drop existing views if they exist
DROP MATERIALIZED VIEW IF EXISTS mv_monthly_stats_by_author CASCADE;
DROP MATERIALIZED VIEW IF EXISTS mv_monthly_category_stats_by_author CASCADE;
DROP VIEW IF EXISTS v_daily_stats_by_author CASCADE;
DROP VIEW IF EXISTS v_weekly_stats_by_author CASCADE;
DROP VIEW IF EXISTS v_category_stats_by_author CASCADE;
DROP VIEW IF EXISTS v_category_by_author_and_repo CASCADE;
DROP VIEW IF EXISTS v_personal_commit_details CASCADE;

-- Drop existing indexes on base tables (if they exist)
-- Note: Indexes on materialized views are automatically dropped by CASCADE above
DROP INDEX IF EXISTS idx_commits_author_email;
DROP INDEX IF EXISTS idx_commits_author_date;
DROP INDEX IF EXISTS idx_commits_author_repo;
DROP INDEX IF EXISTS idx_commits_author_category;

-- ============================================================
-- 1. PERSONAL COMMIT DETAILS (for commit lists)
-- ============================================================

CREATE VIEW v_personal_commit_details AS
SELECT
    c.author_email,
    c.author_name,
    r.id AS repository_id,
    r.name AS repository_name,
    r.url AS repository_url,
    c.id AS commit_id,
    c.hash,
    c.commit_date,
    c.subject,
    c.lines_added::int,
    c.lines_deleted::int,
    (c.lines_added + c.lines_deleted)::int AS lines_changed,
    c.files_changed::int,
    c.weight::int,
    COALESCE(c.category, 'UNCATEGORIZED') as category,
    c.ai_confidence::smallint,
    c.ai_tools,
    c.created_at
FROM commits c
JOIN repositories r ON c.repository_id = r.id
ORDER BY c.commit_date DESC;

COMMENT ON VIEW v_personal_commit_details IS 'Detailed commit information optimized for personal queries. Filter by author_email to show commit history for logged-in users.';

-- ============================================================
-- 2. DAILY STATS BY AUTHOR (for time-series charts)
-- ============================================================

CREATE VIEW v_daily_stats_by_author AS
SELECT
    c.author_email,
    c.author_name,
    r.id AS repository_id,
    r.name AS repository_name,
    DATE(c.commit_date) AS commit_date,
    COUNT(c.id)::int AS total_commits,
    -- Weight analysis metrics
    ROUND((SUM(c.weight) / 100.0)::numeric, 2) AS effective_commits,
    ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
    ROUND((SUM(c.weight) / NULLIF(COUNT(c.id), 0)::numeric), 1) AS weight_efficiency_pct,
    -- Line metrics (unweighted)
    SUM(c.lines_added)::bigint AS total_lines_added,
    SUM(c.lines_deleted)::bigint AS total_lines_deleted,
    SUM(c.lines_added + c.lines_deleted)::bigint AS total_lines_changed,
    -- Line metrics (weighted)
    ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
    ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
    ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
    -- File metrics
    SUM(c.files_changed)::int AS total_files_changed,
    ROUND(SUM(c.files_changed * c.weight / 100.0)::numeric, 2) AS weighted_files_changed,
    -- Averages
    ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 2) AS avg_lines_changed_per_commit,
    ROUND(AVG(c.lines_added)::numeric, 2) AS avg_lines_added_per_commit,
    ROUND(AVG(c.lines_deleted)::numeric, 2) AS avg_lines_deleted_per_commit,
    ROUND(AVG(c.files_changed)::numeric, 2) AS avg_files_changed_per_commit
FROM commits c
JOIN repositories r ON c.repository_id = r.id
WHERE c.weight > 0  -- Exclude reverted commits
GROUP BY c.author_email, c.author_name, r.id, r.name, DATE(c.commit_date)
ORDER BY c.author_email, DATE(c.commit_date) DESC, r.name;

COMMENT ON VIEW v_daily_stats_by_author IS 'Daily aggregated statistics per author and repository (excludes reverted commits with weight=0). Filter by author_email for personal metrics.';

-- ============================================================
-- 3. WEEKLY STATS BY AUTHOR (for weekly trends)
-- ============================================================

CREATE VIEW v_weekly_stats_by_author AS
SELECT
    c.author_email,
    c.author_name,
    r.id AS repository_id,
    r.name AS repository_name,
    DATE_TRUNC('week', c.commit_date)::DATE AS week_start_date,
    EXTRACT(YEAR FROM c.commit_date)::int AS year,
    EXTRACT(WEEK FROM c.commit_date)::int AS week_number,
    COUNT(c.id)::int AS total_commits,
    -- Weight analysis metrics
    ROUND((SUM(c.weight) / 100.0)::numeric, 2) AS effective_commits,
    ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
    ROUND((SUM(c.weight) / NULLIF(COUNT(c.id), 0)::numeric), 1) AS weight_efficiency_pct,
    -- Line metrics
    SUM(c.lines_added)::bigint AS total_lines_added,
    SUM(c.lines_deleted)::bigint AS total_lines_deleted,
    SUM(c.lines_added + c.lines_deleted)::bigint AS total_lines_changed,
    ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
    ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
    ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
    SUM(c.files_changed)::int AS total_files_changed,
    ROUND(SUM(c.files_changed * c.weight / 100.0)::numeric, 2) AS weighted_files_changed,
    -- Averages
    ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 2) AS avg_lines_changed_per_commit,
    ROUND(AVG(c.lines_added)::numeric, 2) AS avg_lines_added_per_commit,
    ROUND(AVG(c.lines_deleted)::numeric, 2) AS avg_lines_deleted_per_commit
FROM commits c
JOIN repositories r ON c.repository_id = r.id
WHERE c.weight > 0  -- Exclude reverted commits
GROUP BY c.author_email, c.author_name, r.id, r.name, DATE_TRUNC('week', c.commit_date),
         EXTRACT(YEAR FROM c.commit_date), EXTRACT(WEEK FROM c.commit_date)
ORDER BY c.author_email, week_start_date DESC, r.name;

COMMENT ON VIEW v_weekly_stats_by_author IS 'Weekly aggregated statistics per author and repository (excludes reverted commits with weight=0). Filter by author_email for personal metrics.';

-- ============================================================
-- 4. MONTHLY STATS BY AUTHOR (materialized for performance)
-- ============================================================

CREATE MATERIALIZED VIEW mv_monthly_stats_by_author AS
SELECT
    c.author_email,
    c.author_name,
    r.id AS repository_id,
    r.name AS repository_name,
    DATE_TRUNC('month', c.commit_date)::DATE AS month_start_date,
    TO_CHAR(c.commit_date, 'YYYY-MM') AS year_month,
    EXTRACT(YEAR FROM c.commit_date)::int AS year,
    EXTRACT(MONTH FROM c.commit_date)::int AS month,
    COUNT(c.id)::int AS total_commits,
    -- Weight analysis metrics
    ROUND((SUM(c.weight) / 100.0)::numeric, 2) AS effective_commits,
    ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
    ROUND((SUM(c.weight) / NULLIF(COUNT(c.id), 0)::numeric), 1) AS weight_efficiency_pct,
    -- Line metrics
    SUM(c.lines_added)::bigint AS total_lines_added,
    SUM(c.lines_deleted)::bigint AS total_lines_deleted,
    SUM(c.lines_added + c.lines_deleted)::bigint AS total_lines_changed,
    ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
    ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
    ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
    SUM(c.files_changed)::int AS total_files_changed,
    ROUND(SUM(c.files_changed * c.weight / 100.0)::numeric, 2) AS weighted_files_changed,
    -- Averages
    ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 2) AS avg_lines_changed_per_commit,
    ROUND(AVG(c.lines_added)::numeric, 2) AS avg_lines_added_per_commit,
    ROUND(AVG(c.lines_deleted)::numeric, 2) AS avg_lines_deleted_per_commit,
    ROUND(AVG(c.files_changed)::numeric, 2) AS avg_files_changed_per_commit
FROM commits c
JOIN repositories r ON c.repository_id = r.id
WHERE c.weight > 0  -- Exclude reverted commits
GROUP BY c.author_email, c.author_name, r.id, r.name,
         DATE_TRUNC('month', c.commit_date), TO_CHAR(c.commit_date, 'YYYY-MM'),
         EXTRACT(YEAR FROM c.commit_date), EXTRACT(MONTH FROM c.commit_date);

-- Indexes for materialized view
CREATE INDEX idx_mv_monthly_stats_by_author_email ON mv_monthly_stats_by_author(author_email, month_start_date);
CREATE INDEX idx_mv_monthly_stats_by_author_repo ON mv_monthly_stats_by_author(author_email, repository_id, month_start_date);
CREATE INDEX idx_mv_monthly_stats_by_author_month ON mv_monthly_stats_by_author(month_start_date);

COMMENT ON MATERIALIZED VIEW mv_monthly_stats_by_author IS 'Pre-computed monthly statistics per author and repository (excludes reverted commits with weight=0). Filter by author_email for personal metrics. Refresh after data loads.';

-- ============================================================
-- 5. CATEGORY STATS BY AUTHOR (for category breakdown)
-- ============================================================

CREATE VIEW v_category_stats_by_author AS
SELECT
    c.author_email,
    c.author_name,
    COALESCE(c.category, 'UNCATEGORIZED') AS category,
    cat.weight AS category_weight,
    COUNT(c.id)::int AS total_commits,
    -- Weight analysis metrics
    ROUND((SUM(c.weight) / 100.0)::numeric, 2) AS effective_commits,
    ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
    ROUND((SUM(c.weight) / NULLIF(COUNT(c.id), 0)::numeric), 1) AS weight_efficiency_pct,
    -- Line metrics
    SUM(c.lines_added)::bigint AS total_lines_added,
    SUM(c.lines_deleted)::bigint AS total_lines_deleted,
    SUM(c.lines_added + c.lines_deleted)::bigint AS total_lines_changed,
    ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
    ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
    ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
    -- Additional metrics
    COUNT(DISTINCT c.repository_id)::int AS repositories_count,
    MIN(c.commit_date) AS first_commit_date,
    MAX(c.commit_date) AS last_commit_date,
    ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit
FROM commits c
LEFT JOIN categories cat ON c.category = cat.name
WHERE c.weight > 0  -- Exclude reverted commits
GROUP BY c.author_email, c.author_name, c.category, cat.weight
ORDER BY c.author_email, total_commits DESC;

COMMENT ON VIEW v_category_stats_by_author IS 'Aggregate statistics for each category per author (excludes reverted commits with weight=0). Filter by author_email for personal category breakdown. Includes UNCATEGORIZED commits.';

-- ============================================================
-- 6. CATEGORY BY AUTHOR AND REPOSITORY
-- ============================================================

CREATE VIEW v_category_by_author_and_repo AS
SELECT
    c.author_email,
    c.author_name,
    r.id AS repository_id,
    r.name AS repository_name,
    COALESCE(c.category, 'UNCATEGORIZED') AS category,
    cat.weight AS category_weight,
    COUNT(c.id)::int AS total_commits,
    -- Weight analysis metrics
    ROUND((SUM(c.weight) / 100.0)::numeric, 2) AS effective_commits,
    ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
    ROUND((SUM(c.weight) / NULLIF(COUNT(c.id), 0)::numeric), 1) AS weight_efficiency_pct,
    -- Line metrics
    SUM(c.lines_added)::bigint AS total_lines_added,
    SUM(c.lines_deleted)::bigint AS total_lines_deleted,
    SUM(c.lines_added + c.lines_deleted)::bigint AS total_lines_changed,
    ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
    ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
    ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
    -- Averages
    ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit
FROM commits c
JOIN repositories r ON c.repository_id = r.id
LEFT JOIN categories cat ON c.category = cat.name
WHERE c.weight > 0  -- Exclude reverted commits
GROUP BY c.author_email, c.author_name, r.id, r.name, c.category, cat.weight
ORDER BY c.author_email, r.name, total_commits DESC;

COMMENT ON VIEW v_category_by_author_and_repo IS 'Category statistics grouped by author and repository (excludes reverted commits with weight=0). Filter by author_email for personal category breakdown per repository.';

-- ============================================================
-- 7. MONTHLY CATEGORY STATS BY AUTHOR (materialized)
-- ============================================================

CREATE MATERIALIZED VIEW mv_monthly_category_stats_by_author AS
SELECT
    c.author_email,
    c.author_name,
    r.id AS repository_id,
    r.name AS repository_name,
    DATE_TRUNC('month', c.commit_date)::DATE AS month_start_date,
    TO_CHAR(c.commit_date, 'YYYY-MM') AS year_month,
    COALESCE(c.category, 'UNCATEGORIZED') AS category,
    cat.weight AS category_weight,
    COUNT(c.id)::int AS total_commits,
    -- Weight analysis metrics
    ROUND((SUM(c.weight) / 100.0)::numeric, 2) AS effective_commits,
    ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
    ROUND((SUM(c.weight) / NULLIF(COUNT(c.id), 0)::numeric), 1) AS weight_efficiency_pct,
    -- Line metrics
    SUM(c.lines_added)::bigint AS total_lines_added,
    SUM(c.lines_deleted)::bigint AS total_lines_deleted,
    SUM(c.lines_added + c.lines_deleted)::bigint AS total_lines_changed,
    ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
    ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
    ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
    -- Averages
    ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit
FROM commits c
JOIN repositories r ON c.repository_id = r.id
LEFT JOIN categories cat ON c.category = cat.name
WHERE c.weight > 0  -- Exclude reverted commits
GROUP BY c.author_email, c.author_name, r.id, r.name,
         DATE_TRUNC('month', c.commit_date), TO_CHAR(c.commit_date, 'YYYY-MM'),
         c.category, cat.weight
ORDER BY c.author_email, r.name, month_start_date DESC, total_commits DESC;

-- Indexes for materialized view
CREATE INDEX idx_mv_monthly_category_by_author_email ON mv_monthly_category_stats_by_author(author_email, month_start_date);
CREATE INDEX idx_mv_monthly_category_by_author_cat ON mv_monthly_category_stats_by_author(author_email, category);
CREATE INDEX idx_mv_monthly_category_by_author_repo ON mv_monthly_category_stats_by_author(author_email, repository_id, month_start_date);

COMMENT ON MATERIALIZED VIEW mv_monthly_category_stats_by_author IS 'Monthly trends for categories per author, pre-computed for fast queries (excludes reverted commits with weight=0). Filter by author_email for personal category trends.';

-- ============================================================
-- 8. CREATE INDEXES FOR PERFORMANCE
-- ============================================================

-- Index for author queries
CREATE INDEX IF NOT EXISTS idx_commits_author_email ON commits(author_email);
CREATE INDEX IF NOT EXISTS idx_commits_author_date ON commits(author_email, commit_date) WHERE weight > 0;
CREATE INDEX IF NOT EXISTS idx_commits_author_repo ON commits(author_email, repository_id) WHERE weight > 0;
CREATE INDEX IF NOT EXISTS idx_commits_author_category ON commits(author_email, category) WHERE weight > 0 AND category IS NOT NULL;

-- ============================================================
-- 9. REFRESH FUNCTIONS
-- ============================================================

-- Function to refresh personal performance materialized views
CREATE OR REPLACE FUNCTION refresh_personal_mv()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_monthly_stats_by_author;
    REFRESH MATERIALIZED VIEW mv_monthly_category_stats_by_author;
    RAISE NOTICE 'Personal performance materialized views refreshed successfully';
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION refresh_personal_mv() IS 'Refreshes all personal performance materialized views. Call after loading new data.';

-- Update the existing refresh_all_mv function to include personal views
CREATE OR REPLACE FUNCTION refresh_all_mv()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_monthly_stats_by_repo;
    REFRESH MATERIALIZED VIEW mv_monthly_stats_by_author;
    RAISE NOTICE 'All standard materialized views refreshed successfully';
END;
$$ LANGUAGE plpgsql;

-- Update the existing refresh_category_mv function to include personal category views
CREATE OR REPLACE FUNCTION refresh_category_mv()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_monthly_category_stats;
    REFRESH MATERIALIZED VIEW mv_monthly_category_stats_by_author;
    RAISE NOTICE 'Category materialized views refreshed successfully';
END;
$$ LANGUAGE plpgsql;
