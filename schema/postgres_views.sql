-- PostgreSQL Views for Git Productivity Analytics
-- Version: 1.0
-- Description: Aggregated views for dashboard queries

-- Drop existing views
DROP MATERIALIZED VIEW IF EXISTS mv_monthly_stats_by_repo CASCADE;
DROP VIEW IF EXISTS v_contributor_stats CASCADE;
DROP VIEW IF EXISTS v_daily_stats_by_repo CASCADE;
DROP VIEW IF EXISTS v_weekly_stats_by_repo CASCADE;
DROP VIEW IF EXISTS v_commit_details CASCADE;

-- View: Commit details with repository information (useful for joins)
CREATE VIEW v_commit_details AS
SELECT
    c.id,
    c.hash,
    c.commit_date,
    c.author_name,
    c.author_email,
    c.subject,
    c.lines_added,
    c.lines_deleted,
    c.files_changed,
    c.lines_added + c.lines_deleted AS lines_changed,
    c.weight,
    c.ai_tools,
    c.category,
    r.id AS repository_id,
    r.name AS repository_name,
    r.url AS repository_url
FROM commits c
JOIN repositories r ON c.repository_id = r.id;

COMMENT ON VIEW v_commit_details IS 'Commits with repository information, weight, ai_tools, category, and calculated lines_changed';

-- View: Daily statistics by repository
CREATE VIEW v_daily_stats_by_repo AS
SELECT
    r.id AS repository_id,
    r.name AS repository_name,
    DATE(c.commit_date) AS commit_date,
    COUNT(*) AS total_commits,
    COUNT(DISTINCT c.author_email) AS unique_authors,
    SUM(c.lines_added) AS total_lines_added,
    SUM(c.lines_deleted) AS total_lines_deleted,
    SUM(c.lines_added + c.lines_deleted) AS total_lines_changed,
    SUM(c.files_changed) AS total_files_changed,
    -- Weighted metrics (accounting for reverted commits)
    ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
    ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
    ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
    ROUND(SUM(c.files_changed * c.weight / 100.0)::numeric, 2) AS weighted_files_changed,
    -- Averages
    ROUND(AVG(c.lines_added + c.lines_deleted), 2) AS avg_lines_changed_per_commit,
    ROUND(AVG(c.lines_added), 2) AS avg_lines_added_per_commit,
    ROUND(AVG(c.lines_deleted), 2) AS avg_lines_deleted_per_commit,
    ROUND(AVG(c.files_changed), 2) AS avg_files_changed_per_commit
FROM commits c
JOIN repositories r ON c.repository_id = r.id
WHERE c.weight > 0
GROUP BY r.id, r.name, DATE(c.commit_date)
ORDER BY commit_date DESC, r.name;

COMMENT ON VIEW v_daily_stats_by_repo IS 'Daily aggregated statistics per repository (excludes reverted commits with weight=0)';

-- View: Weekly statistics by repository
CREATE VIEW v_weekly_stats_by_repo AS
SELECT
    r.id AS repository_id,
    r.name AS repository_name,
    DATE_TRUNC('week', c.commit_date)::DATE AS week_start_date,
    EXTRACT(YEAR FROM c.commit_date)::INTEGER AS year,
    EXTRACT(WEEK FROM c.commit_date)::INTEGER AS week_number,
    COUNT(*) AS total_commits,
    COUNT(DISTINCT c.author_email) AS unique_authors,
    SUM(c.lines_added) AS total_lines_added,
    SUM(c.lines_deleted) AS total_lines_deleted,
    SUM(c.lines_added + c.lines_deleted) AS total_lines_changed,
    SUM(c.files_changed) AS total_files_changed,
    -- Weighted metrics (accounting for reverted commits)
    ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
    ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
    ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
    ROUND(SUM(c.files_changed * c.weight / 100.0)::numeric, 2) AS weighted_files_changed,
    -- Averages
    ROUND(AVG(c.lines_added + c.lines_deleted), 2) AS avg_lines_changed_per_commit,
    ROUND(AVG(c.lines_added), 2) AS avg_lines_added_per_commit,
    ROUND(AVG(c.lines_deleted), 2) AS avg_lines_deleted_per_commit
FROM commits c
JOIN repositories r ON c.repository_id = r.id
WHERE c.weight > 0
GROUP BY r.id, r.name, DATE_TRUNC('week', c.commit_date), EXTRACT(YEAR FROM c.commit_date), EXTRACT(WEEK FROM c.commit_date)
ORDER BY week_start_date DESC, r.name;

COMMENT ON VIEW v_weekly_stats_by_repo IS 'Weekly aggregated statistics per repository (excludes reverted commits with weight=0)';

-- Materialized View: Monthly statistics by repository (pre-computed for performance)
CREATE MATERIALIZED VIEW mv_monthly_stats_by_repo AS
SELECT
    r.id AS repository_id,
    r.name AS repository_name,
    DATE_TRUNC('month', c.commit_date)::DATE AS month_start_date,
    TO_CHAR(c.commit_date, 'YYYY-MM') AS year_month,
    EXTRACT(YEAR FROM c.commit_date)::INTEGER AS year,
    EXTRACT(MONTH FROM c.commit_date)::INTEGER AS month,
    COUNT(*) AS total_commits,
    COUNT(DISTINCT c.author_email) AS unique_authors,
    SUM(c.lines_added) AS total_lines_added,
    SUM(c.lines_deleted) AS total_lines_deleted,
    SUM(c.lines_added + c.lines_deleted) AS total_lines_changed,
    SUM(c.files_changed) AS total_files_changed,
    -- Weighted metrics (accounting for reverted commits)
    ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
    ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
    ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
    ROUND(SUM(c.files_changed * c.weight / 100.0)::numeric, 2) AS weighted_files_changed,
    -- Averages
    ROUND(AVG(c.lines_added + c.lines_deleted), 2) AS avg_lines_changed_per_commit,
    ROUND(AVG(c.lines_added), 2) AS avg_lines_added_per_commit,
    ROUND(AVG(c.lines_deleted), 2) AS avg_lines_deleted_per_commit,
    ROUND(AVG(c.files_changed), 2) AS avg_files_changed_per_commit,
    -- Per-author averages
    ROUND(SUM(c.lines_added)::NUMERIC / NULLIF(COUNT(DISTINCT c.author_email), 0), 2) AS avg_lines_added_per_author,
    ROUND(SUM(c.lines_deleted)::NUMERIC / NULLIF(COUNT(DISTINCT c.author_email), 0), 2) AS avg_lines_deleted_per_author,
    ROUND(SUM(c.lines_added + c.lines_deleted)::NUMERIC / NULLIF(COUNT(DISTINCT c.author_email), 0), 2) AS avg_lines_changed_per_author,
    ROUND(COUNT(*)::NUMERIC / NULLIF(COUNT(DISTINCT c.author_email), 0), 2) AS avg_commits_per_author
FROM commits c
JOIN repositories r ON c.repository_id = r.id
WHERE c.weight > 0
GROUP BY r.id, r.name, DATE_TRUNC('month', c.commit_date), TO_CHAR(c.commit_date, 'YYYY-MM'), EXTRACT(YEAR FROM c.commit_date), EXTRACT(MONTH FROM c.commit_date);

-- Index for materialized view
CREATE INDEX idx_mv_monthly_stats_repo_month ON mv_monthly_stats_by_repo(repository_id, month_start_date);
CREATE INDEX idx_mv_monthly_stats_month ON mv_monthly_stats_by_repo(month_start_date);

COMMENT ON MATERIALIZED VIEW mv_monthly_stats_by_repo IS 'Pre-computed monthly statistics per repository (excludes reverted commits with weight=0). Refresh after data loads.';

-- View: Contributor statistics (across all time and repositories)
CREATE VIEW v_contributor_stats AS
SELECT
    c.author_email,
    c.author_name,
    COUNT(DISTINCT c.repository_id) AS repositories_contributed,
    COUNT(*) AS total_commits,
    SUM(c.lines_added) AS total_lines_added,
    SUM(c.lines_deleted) AS total_lines_deleted,
    SUM(c.lines_added + c.lines_deleted) AS total_lines_changed,
    SUM(c.files_changed) AS total_files_changed,
    -- Weighted metrics (accounting for reverted commits)
    ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
    ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
    ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
    -- Averages
    ROUND(AVG(c.lines_added + c.lines_deleted), 2) AS avg_lines_changed_per_commit,
    ROUND(AVG(c.lines_added), 2) AS avg_lines_added_per_commit,
    ROUND(AVG(c.lines_deleted), 2) AS avg_lines_deleted_per_commit,
    MIN(c.commit_date) AS first_commit_date,
    MAX(c.commit_date) AS last_commit_date,
    -- Activity period in days
    EXTRACT(DAY FROM MAX(c.commit_date) - MIN(c.commit_date))::INTEGER AS activity_days
FROM commits c
WHERE c.weight > 0
GROUP BY c.author_email, c.author_name
ORDER BY total_commits DESC;

COMMENT ON VIEW v_contributor_stats IS 'Aggregated statistics per contributor across all repositories (excludes reverted commits with weight=0)';

-- Helper function to refresh materialized views
CREATE OR REPLACE FUNCTION refresh_all_mv()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_monthly_stats_by_repo;
    RAISE NOTICE 'All materialized views refreshed successfully';
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION refresh_all_mv() IS 'Refreshes all materialized views. Call after loading new data.';

-- View: AI Tools usage statistics
CREATE VIEW v_ai_tools_stats AS
SELECT
    ai_tools,
    COUNT(*) AS total_commits,
    COUNT(DISTINCT author_email) AS unique_authors,
    COUNT(DISTINCT repository_id) AS repositories,
    SUM(lines_added) AS total_lines_added,
    SUM(lines_deleted) AS total_lines_deleted,
    SUM(lines_added + lines_deleted) AS total_lines_changed,
    ROUND(SUM((lines_added + lines_deleted) * weight / 100.0)::numeric, 2) AS weighted_lines_changed,
    ROUND(AVG(lines_added + lines_deleted), 2) AS avg_lines_per_commit,
    MIN(commit_date) AS first_usage,
    MAX(commit_date) AS latest_usage
FROM commits
WHERE ai_tools IS NOT NULL AND weight > 0
GROUP BY ai_tools
ORDER BY total_commits DESC;

COMMENT ON VIEW v_ai_tools_stats IS 'Statistics on AI tools usage across all repositories (excludes reverted commits with weight=0)';

-- View: AI Tools by repository
CREATE VIEW v_ai_tools_by_repo AS
SELECT
    r.name AS repository_name,
    c.ai_tools,
    COUNT(*) AS total_commits,
    COUNT(DISTINCT c.author_email) AS unique_authors,
    SUM(c.lines_added + c.lines_deleted) AS total_lines_changed,
    ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
    ROUND(AVG(c.lines_added + c.lines_deleted), 2) AS avg_lines_per_commit
FROM commits c
JOIN repositories r ON c.repository_id = r.id
WHERE c.ai_tools IS NOT NULL AND c.weight > 0
GROUP BY r.name, c.ai_tools
ORDER BY r.name, total_commits DESC;

COMMENT ON VIEW v_ai_tools_by_repo IS 'AI tools usage broken down by repository (excludes reverted commits with weight=0)';

-- View: Commits with weight zero (reverted)
CREATE VIEW v_reverted_commits AS
SELECT
    r.name AS repository_name,
    c.hash,
    c.commit_date,
    c.author_name,
    c.subject,
    c.lines_added,
    c.lines_deleted,
    c.weight
FROM commits c
JOIN repositories r ON c.repository_id = r.id
WHERE c.weight = 0
ORDER BY c.commit_date DESC;

COMMENT ON VIEW v_reverted_commits IS 'Commits with weight=0 (reverted commits) for analysis';

-- Usage examples:
-- SELECT refresh_all_mv();  -- Refresh materialized views after data load
-- SELECT * FROM mv_monthly_stats_by_repo WHERE repository_name = 'MyApp' ORDER BY month_start_date DESC;
-- SELECT * FROM v_contributor_stats ORDER BY total_commits DESC LIMIT 10;
-- SELECT * FROM v_daily_stats_by_repo WHERE repository_name = 'MyApp' AND commit_date >= '2025-01-01';
-- SELECT * FROM v_ai_tools_stats ORDER BY total_commits DESC;
-- SELECT * FROM v_reverted_commits LIMIT 20;
