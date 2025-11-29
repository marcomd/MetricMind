# frozen_string_literal: true

# Migration: Create Category Views
# Original file: category_views.sql
# Original date: 2025-11-16 (updated 2025-11-20 for category weights)
# Converted from SQL to Sequel format
#
# Creates category analytics views for business domain tracking
# Includes materialized views for monthly trends
#
# Timestamp: 20251116000000 (after categories table and category_weight column)
# Dependencies: Base schema + category column + categories table + category.weight column

Sequel.migration do
  up do
    run <<-SQL
      -- Create categories table if it doesn't exist (dependency for views)
      CREATE TABLE IF NOT EXISTS categories (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL UNIQUE,
        description TEXT,
        usage_count INTEGER DEFAULT 0 NOT NULL,
        weight INTEGER DEFAULT 100 CHECK (weight >= 0 AND weight <= 100),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- View: Category statistics across all repositories
      CREATE VIEW v_category_stats AS
      SELECT
        c.category,
        cat.weight AS category_weight,
        COUNT(*) AS total_commits,
        COUNT(DISTINCT c.author_email) AS unique_authors,
        COUNT(DISTINCT c.repository_id) AS repositories,
        SUM(c.lines_added) AS total_lines_added,
        SUM(c.lines_deleted) AS total_lines_deleted,
        SUM(c.lines_added + c.lines_deleted) AS total_lines_changed,
        ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
        ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
        ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
        ROUND(SUM(c.weight / 100.0)::numeric, 2) AS effective_commits,
        ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
        ROUND(SUM(c.weight / 100.0) / COUNT(*)::numeric * 100, 1) AS weight_efficiency_pct,
        ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit,
        MIN(c.commit_date) AS first_commit,
        MAX(c.commit_date) AS latest_commit
      FROM commits c
      LEFT JOIN categories cat ON c.category = cat.name
      WHERE c.category IS NOT NULL AND c.weight > 0
      GROUP BY c.category, cat.weight
      ORDER BY total_commits DESC;

      COMMENT ON VIEW v_category_stats IS 'Aggregate statistics for each category across all repositories (excludes reverted commits with weight=0)';

      -- View: Category breakdown by repository
      CREATE VIEW v_category_by_repo AS
      SELECT
        r.id AS repository_id,
        r.name AS repository_name,
        c.category,
        cat.weight AS category_weight,
        COUNT(*) AS total_commits,
        COUNT(DISTINCT c.author_email) AS unique_authors,
        SUM(c.lines_added) AS total_lines_added,
        SUM(c.lines_deleted) AS total_lines_deleted,
        SUM(c.lines_added + c.lines_deleted) AS total_lines_changed,
        ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
        ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
        ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
        ROUND(SUM(c.weight / 100.0)::numeric, 2) AS effective_commits,
        ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
        ROUND(SUM(c.weight / 100.0) / COUNT(*)::numeric * 100, 1) AS weight_efficiency_pct,
        ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit
      FROM commits c
      JOIN repositories r ON c.repository_id = r.id
      LEFT JOIN categories cat ON c.category = cat.name
      WHERE c.category IS NOT NULL AND c.weight > 0
      GROUP BY r.id, r.name, c.category, cat.weight
      ORDER BY r.name, total_commits DESC;

      COMMENT ON VIEW v_category_by_repo IS 'Category statistics grouped by repository (excludes reverted commits with weight=0)';

      -- Materialized View: Monthly category trends
      CREATE MATERIALIZED VIEW mv_monthly_category_stats AS
      SELECT
        r.id AS repository_id,
        r.name AS repository_name,
        DATE_TRUNC('month', c.commit_date)::DATE AS month_start_date,
        TO_CHAR(c.commit_date, 'YYYY-MM') AS year_month,
        c.category,
        cat.weight AS category_weight,
        COUNT(*) AS total_commits,
        COUNT(DISTINCT c.author_email) AS unique_authors,
        SUM(c.lines_added) AS total_lines_added,
        SUM(c.lines_deleted) AS total_lines_deleted,
        SUM(c.lines_added + c.lines_deleted) AS total_lines_changed,
        ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
        ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
        ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
        ROUND(SUM(c.weight / 100.0)::numeric, 2) AS effective_commits,
        ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
        ROUND(SUM(c.weight / 100.0) / COUNT(*)::numeric * 100, 1) AS weight_efficiency_pct,
        ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit
      FROM commits c
      JOIN repositories r ON c.repository_id = r.id
      LEFT JOIN categories cat ON c.category = cat.name
      WHERE c.category IS NOT NULL AND c.weight > 0
      GROUP BY r.id, r.name, DATE_TRUNC('month', c.commit_date), TO_CHAR(c.commit_date, 'YYYY-MM'), c.category, cat.weight
      ORDER BY r.name, month_start_date DESC, total_commits DESC;

      CREATE INDEX idx_mv_monthly_category_repo ON mv_monthly_category_stats(repository_id, month_start_date);
      CREATE INDEX idx_mv_monthly_category_cat ON mv_monthly_category_stats(category) WHERE category IS NOT NULL;

      COMMENT ON MATERIALIZED VIEW mv_monthly_category_stats IS 'Monthly trends for categories, pre-computed for fast queries (excludes reverted commits with weight=0)';

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
    SQL
  end

  down do
    run <<-SQL
      -- Drop in reverse order to handle dependencies
      DROP FUNCTION IF EXISTS refresh_category_mv();
      DROP VIEW IF EXISTS v_uncategorized_commits CASCADE;
      DROP MATERIALIZED VIEW IF EXISTS mv_monthly_category_stats CASCADE;
      DROP VIEW IF EXISTS v_category_by_repo CASCADE;
      DROP VIEW IF EXISTS v_category_stats CASCADE;
    SQL
  end
end
