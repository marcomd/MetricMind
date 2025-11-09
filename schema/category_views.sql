-- Category Analytics Views
-- Description: Views for analyzing commits by category (business domain)
-- Dependencies: Requires commits table with category column

-- Drop existing views
DROP VIEW IF EXISTS v_category_stats CASCADE;
DROP VIEW IF EXISTS v_work_type_stats CASCADE;
DROP VIEW IF EXISTS v_category_by_repo CASCADE;
DROP VIEW IF EXISTS v_work_type_by_repo CASCADE;
DROP VIEW IF EXISTS v_category_work_type_matrix CASCADE;
DROP MATERIALIZED VIEW IF EXISTS mv_monthly_category_stats CASCADE;

-- View: Category statistics across all repositories
CREATE VIEW v_category_stats AS
SELECT
    category,
    COUNT(*) AS total_commits,
    COUNT(DISTINCT author_email) AS unique_authors,
    COUNT(DISTINCT repository_id) AS repositories,
    SUM(lines_added) AS total_lines_added,
    SUM(lines_deleted) AS total_lines_deleted,
    SUM(lines_added + lines_deleted) AS total_lines_changed,
    ROUND(AVG(lines_added + lines_deleted)::numeric, 1) AS avg_lines_per_commit,
    MIN(commit_date) AS first_commit,
    MAX(commit_date) AS latest_commit
FROM commits
WHERE category IS NOT NULL
GROUP BY category
ORDER BY total_commits DESC;

COMMENT ON VIEW v_category_stats IS 'Aggregate statistics for each category across all repositories';

-- View: Category breakdown by repository
CREATE VIEW v_category_by_repo AS
SELECT
    r.id AS repository_id,
    r.name AS repository_name,
    c.category,
    COUNT(*) AS total_commits,
    COUNT(DISTINCT c.author_email) AS unique_authors,
    SUM(c.lines_added) AS total_lines_added,
    SUM(c.lines_deleted) AS total_lines_deleted,
    SUM(c.lines_added + c.lines_deleted) AS total_lines_changed,
    ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit
FROM commits c
JOIN repositories r ON c.repository_id = r.id
WHERE c.category IS NOT NULL
GROUP BY r.id, r.name, c.category
ORDER BY r.name, total_commits DESC;

COMMENT ON VIEW v_category_by_repo IS 'Category statistics grouped by repository';

-- Materialized View: Monthly category trends
CREATE MATERIALIZED VIEW mv_monthly_category_stats AS
SELECT
    r.id AS repository_id,
    r.name AS repository_name,
    DATE_TRUNC('month', c.commit_date)::DATE AS month_start_date,
    TO_CHAR(c.commit_date, 'YYYY-MM') AS year_month,
    c.category,
    COUNT(*) AS total_commits,
    COUNT(DISTINCT c.author_email) AS unique_authors,
    SUM(c.lines_added) AS total_lines_added,
    SUM(c.lines_deleted) AS total_lines_deleted,
    SUM(c.lines_added + c.lines_deleted) AS total_lines_changed,
    ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit
FROM commits c
JOIN repositories r ON c.repository_id = r.id
WHERE c.category IS NOT NULL
GROUP BY r.id, r.name, DATE_TRUNC('month', c.commit_date), TO_CHAR(c.commit_date, 'YYYY-MM'), c.category
ORDER BY r.name, month_start_date DESC, total_commits DESC;

CREATE INDEX idx_mv_monthly_category_repo ON mv_monthly_category_stats(repository_id, month_start_date);
CREATE INDEX idx_mv_monthly_category_cat ON mv_monthly_category_stats(category) WHERE category IS NOT NULL;

COMMENT ON MATERIALIZED VIEW mv_monthly_category_stats IS 'Monthly trends for categories, pre-computed for fast queries';

-- View: Uncategorized commits (for monitoring and cleanup)
CREATE VIEW v_uncategorized_commits AS
SELECT
    r.name AS repository_name,
    c.hash,
    c.commit_date,
    c.author_name,
    c.subject,
    c.category IS NULL AS missing_category
FROM commits c
JOIN repositories r ON c.repository_id = r.id
WHERE c.category IS NULL
ORDER BY c.commit_date DESC;

COMMENT ON VIEW v_uncategorized_commits IS 'Commits missing category - useful for cleanup and improving coverage';

-- Helper function to refresh all category-related materialized views
CREATE OR REPLACE FUNCTION refresh_category_mv()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_monthly_category_stats;
    RAISE NOTICE 'Category materialized views refreshed successfully';
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION refresh_category_mv() IS 'Refresh all category-related materialized views';
