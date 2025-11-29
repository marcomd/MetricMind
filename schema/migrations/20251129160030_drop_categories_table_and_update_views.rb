# frozen_string_literal: true

# Migration: Drop Categories Table And Update Views
# Created: 2025-11-29 16:00:30
#
# This migration removes the categories table and updates all views that
# previously depended on it. The category_weight column is removed from views
# since categorization now happens during extraction and doesn't use the
# categories table.
#
# Views updated:
# - v_category_stats (category views)
# - v_category_by_repo (category views)
# - mv_monthly_category_stats (category views)
# - v_category_stats_by_author (personal views)
# - v_category_by_author_and_repo (personal views)
# - mv_monthly_category_stats_by_author (personal views)

Sequel.migration do
  up do
    run <<-SQL
      -- ============================================================
      -- 1. DROP VIEWS THAT DEPEND ON CATEGORIES TABLE
      -- ============================================================

      -- Drop category views
      DROP VIEW IF EXISTS v_category_stats CASCADE;
      DROP VIEW IF EXISTS v_category_by_repo CASCADE;
      DROP MATERIALIZED VIEW IF EXISTS mv_monthly_category_stats CASCADE;

      -- Drop personal category views
      DROP VIEW IF EXISTS v_category_stats_by_author CASCADE;
      DROP VIEW IF EXISTS v_category_by_author_and_repo CASCADE;
      DROP MATERIALIZED VIEW IF EXISTS mv_monthly_category_stats_by_author CASCADE;

      -- ============================================================
      -- 2. RECREATE CATEGORY VIEWS WITHOUT CATEGORIES TABLE
      -- ============================================================

      -- View: Category statistics across all repositories
      CREATE VIEW v_category_stats AS
      SELECT
        c.category,
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
      WHERE c.category IS NOT NULL AND c.weight > 0
      GROUP BY c.category
      ORDER BY total_commits DESC;

      COMMENT ON VIEW v_category_stats IS 'Aggregate statistics for each category across all repositories (excludes reverted commits with weight=0)';

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
        ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
        ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
        ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
        ROUND(SUM(c.weight / 100.0)::numeric, 2) AS effective_commits,
        ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
        ROUND(SUM(c.weight / 100.0) / COUNT(*)::numeric * 100, 1) AS weight_efficiency_pct,
        ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit
      FROM commits c
      JOIN repositories r ON c.repository_id = r.id
      WHERE c.category IS NOT NULL AND c.weight > 0
      GROUP BY r.id, r.name, c.category
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
      WHERE c.category IS NOT NULL AND c.weight > 0
      GROUP BY r.id, r.name, DATE_TRUNC('month', c.commit_date), TO_CHAR(c.commit_date, 'YYYY-MM'), c.category
      ORDER BY r.name, month_start_date DESC, total_commits DESC;

      CREATE INDEX idx_mv_monthly_category_repo ON mv_monthly_category_stats(repository_id, month_start_date);
      CREATE INDEX idx_mv_monthly_category_cat ON mv_monthly_category_stats(category) WHERE category IS NOT NULL;

      COMMENT ON MATERIALIZED VIEW mv_monthly_category_stats IS 'Monthly trends for categories, pre-computed for fast queries (excludes reverted commits with weight=0)';

      -- ============================================================
      -- 3. RECREATE PERSONAL CATEGORY VIEWS WITHOUT CATEGORIES TABLE
      -- ============================================================

      CREATE VIEW v_category_stats_by_author AS
      SELECT
        c.author_email,
        c.author_name,
        COALESCE(c.category, 'UNCATEGORIZED') AS category,
        COUNT(c.id)::int AS total_commits,
        ROUND((SUM(c.weight) / 100.0)::numeric, 2) AS effective_commits,
        ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
        ROUND((SUM(c.weight) / NULLIF(COUNT(c.id), 0)::numeric), 1) AS weight_efficiency_pct,
        SUM(c.lines_added)::bigint AS total_lines_added,
        SUM(c.lines_deleted)::bigint AS total_lines_deleted,
        SUM(c.lines_added + c.lines_deleted)::bigint AS total_lines_changed,
        ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
        ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
        ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
        COUNT(DISTINCT c.repository_id)::int AS repositories_count,
        MIN(c.commit_date) AS first_commit_date,
        MAX(c.commit_date) AS last_commit_date,
        ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit
      FROM commits c
      WHERE c.weight > 0
      GROUP BY c.author_email, c.author_name, c.category
      ORDER BY c.author_email, total_commits DESC;

      COMMENT ON VIEW v_category_stats_by_author IS 'Aggregate statistics for each category per author (excludes reverted commits with weight=0). Filter by author_email for personal category breakdown. Includes UNCATEGORIZED commits.';

      CREATE VIEW v_category_by_author_and_repo AS
      SELECT
        c.author_email,
        c.author_name,
        r.id AS repository_id,
        r.name AS repository_name,
        COALESCE(c.category, 'UNCATEGORIZED') AS category,
        COUNT(c.id)::int AS total_commits,
        ROUND((SUM(c.weight) / 100.0)::numeric, 2) AS effective_commits,
        ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
        ROUND((SUM(c.weight) / NULLIF(COUNT(c.id), 0)::numeric), 1) AS weight_efficiency_pct,
        SUM(c.lines_added)::bigint AS total_lines_added,
        SUM(c.lines_deleted)::bigint AS total_lines_deleted,
        SUM(c.lines_added + c.lines_deleted)::bigint AS total_lines_changed,
        ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
        ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
        ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
        ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit
      FROM commits c
      JOIN repositories r ON c.repository_id = r.id
      WHERE c.weight > 0
      GROUP BY c.author_email, c.author_name, r.id, r.name, c.category
      ORDER BY c.author_email, r.name, total_commits DESC;

      COMMENT ON VIEW v_category_by_author_and_repo IS 'Category statistics grouped by author and repository (excludes reverted commits with weight=0). Filter by author_email for personal category breakdown per repository.';

      CREATE MATERIALIZED VIEW mv_monthly_category_stats_by_author AS
      SELECT
        c.author_email,
        c.author_name,
        r.id AS repository_id,
        r.name AS repository_name,
        DATE_TRUNC('month', c.commit_date)::DATE AS month_start_date,
        TO_CHAR(c.commit_date, 'YYYY-MM') AS year_month,
        COALESCE(c.category, 'UNCATEGORIZED') AS category,
        COUNT(c.id)::int AS total_commits,
        ROUND((SUM(c.weight) / 100.0)::numeric, 2) AS effective_commits,
        ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
        ROUND((SUM(c.weight) / NULLIF(COUNT(c.id), 0)::numeric), 1) AS weight_efficiency_pct,
        SUM(c.lines_added)::bigint AS total_lines_added,
        SUM(c.lines_deleted)::bigint AS total_lines_deleted,
        SUM(c.lines_added + c.lines_deleted)::bigint AS total_lines_changed,
        ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
        ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
        ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
        ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit
      FROM commits c
      JOIN repositories r ON c.repository_id = r.id
      WHERE c.weight > 0
      GROUP BY c.author_email, c.author_name, r.id, r.name,
               DATE_TRUNC('month', c.commit_date), TO_CHAR(c.commit_date, 'YYYY-MM'),
               c.category
      ORDER BY c.author_email, r.name, month_start_date DESC, total_commits DESC;

      CREATE INDEX idx_mv_monthly_category_by_author_email ON mv_monthly_category_stats_by_author(author_email, month_start_date);
      CREATE INDEX idx_mv_monthly_category_by_author_cat ON mv_monthly_category_stats_by_author(author_email, category);
      CREATE INDEX idx_mv_monthly_category_by_author_repo ON mv_monthly_category_stats_by_author(author_email, repository_id, month_start_date);

      COMMENT ON MATERIALIZED VIEW mv_monthly_category_stats_by_author IS 'Monthly trends for categories per author, pre-computed for fast queries (excludes reverted commits with weight=0). Filter by author_email for personal category trends.';

      -- ============================================================
      -- 4. DROP THE CATEGORIES TABLE
      -- ============================================================

      DROP TABLE IF EXISTS categories CASCADE;

      -- ============================================================
      -- 5. UPDATE REFRESH FUNCTIONS
      -- ============================================================

      CREATE OR REPLACE FUNCTION refresh_category_mv()
      RETURNS void AS $$
      BEGIN
        REFRESH MATERIALIZED VIEW mv_monthly_category_stats;
        RAISE NOTICE 'Category materialized views refreshed successfully';
      END;
      $$ LANGUAGE plpgsql;

      COMMENT ON FUNCTION refresh_category_mv() IS 'Refresh all category-related materialized views';

      CREATE OR REPLACE FUNCTION refresh_personal_mv()
      RETURNS void AS $$
      BEGIN
        REFRESH MATERIALIZED VIEW mv_monthly_stats_by_author;
        REFRESH MATERIALIZED VIEW mv_monthly_category_stats_by_author;
        RAISE NOTICE 'Personal performance materialized views refreshed successfully';
      END;
      $$ LANGUAGE plpgsql;

      COMMENT ON FUNCTION refresh_personal_mv() IS 'Refreshes all personal performance materialized views. Call after loading new data.';
    SQL
  end

  down do
    run <<-SQL
      -- ============================================================
      -- 1. RECREATE CATEGORIES TABLE
      -- ============================================================

      CREATE TABLE IF NOT EXISTS categories (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) UNIQUE NOT NULL,
        description TEXT,
        usage_count INTEGER DEFAULT 0,
        weight INTEGER DEFAULT 100 CHECK (weight >= 0 AND weight <= 100),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      COMMENT ON TABLE categories IS 'Approved business domain categories for consistent categorization';
      COMMENT ON COLUMN categories.name IS 'Unique uppercase category name (e.g., BILLING, SECURITY)';
      COMMENT ON COLUMN categories.description IS 'Human-readable description of what this category covers';
      COMMENT ON COLUMN categories.usage_count IS 'Number of commits using this category (updated by AI categorizer)';
      COMMENT ON COLUMN categories.weight IS 'Admin-controlled weight for this category (0-100, default 100)';

      CREATE INDEX IF NOT EXISTS idx_categories_name ON categories(name);
      CREATE INDEX IF NOT EXISTS idx_categories_usage ON categories(usage_count DESC);

      -- ============================================================
      -- 2. DROP AND RECREATE VIEWS WITH CATEGORIES JOIN
      -- ============================================================

      -- Drop views
      DROP VIEW IF EXISTS v_category_stats CASCADE;
      DROP VIEW IF EXISTS v_category_by_repo CASCADE;
      DROP MATERIALIZED VIEW IF EXISTS mv_monthly_category_stats CASCADE;
      DROP VIEW IF EXISTS v_category_stats_by_author CASCADE;
      DROP VIEW IF EXISTS v_category_by_author_and_repo CASCADE;
      DROP MATERIALIZED VIEW IF EXISTS mv_monthly_category_stats_by_author CASCADE;

      -- Recreate v_category_stats with categories JOIN
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

      -- Recreate v_category_by_repo with categories JOIN
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

      -- Recreate mv_monthly_category_stats with categories JOIN
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

      -- Recreate personal category views with categories JOIN
      CREATE VIEW v_category_stats_by_author AS
      SELECT
        c.author_email,
        c.author_name,
        COALESCE(c.category, 'UNCATEGORIZED') AS category,
        cat.weight AS category_weight,
        COUNT(c.id)::int AS total_commits,
        ROUND((SUM(c.weight) / 100.0)::numeric, 2) AS effective_commits,
        ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
        ROUND((SUM(c.weight) / NULLIF(COUNT(c.id), 0)::numeric), 1) AS weight_efficiency_pct,
        SUM(c.lines_added)::bigint AS total_lines_added,
        SUM(c.lines_deleted)::bigint AS total_lines_deleted,
        SUM(c.lines_added + c.lines_deleted)::bigint AS total_lines_changed,
        ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
        ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
        ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
        COUNT(DISTINCT c.repository_id)::int AS repositories_count,
        MIN(c.commit_date) AS first_commit_date,
        MAX(c.commit_date) AS last_commit_date,
        ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit
      FROM commits c
      LEFT JOIN categories cat ON c.category = cat.name
      WHERE c.weight > 0
      GROUP BY c.author_email, c.author_name, c.category, cat.weight
      ORDER BY c.author_email, total_commits DESC;

      CREATE VIEW v_category_by_author_and_repo AS
      SELECT
        c.author_email,
        c.author_name,
        r.id AS repository_id,
        r.name AS repository_name,
        COALESCE(c.category, 'UNCATEGORIZED') AS category,
        cat.weight AS category_weight,
        COUNT(c.id)::int AS total_commits,
        ROUND((SUM(c.weight) / 100.0)::numeric, 2) AS effective_commits,
        ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
        ROUND((SUM(c.weight) / NULLIF(COUNT(c.id), 0)::numeric), 1) AS weight_efficiency_pct,
        SUM(c.lines_added)::bigint AS total_lines_added,
        SUM(c.lines_deleted)::bigint AS total_lines_deleted,
        SUM(c.lines_added + c.lines_deleted)::bigint AS total_lines_changed,
        ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
        ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
        ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
        ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit
      FROM commits c
      JOIN repositories r ON c.repository_id = r.id
      LEFT JOIN categories cat ON c.category = cat.name
      WHERE c.weight > 0
      GROUP BY c.author_email, c.author_name, r.id, r.name, c.category, cat.weight
      ORDER BY c.author_email, r.name, total_commits DESC;

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
        ROUND((SUM(c.weight) / 100.0)::numeric, 2) AS effective_commits,
        ROUND(AVG(c.weight)::numeric, 1) AS avg_weight,
        ROUND((SUM(c.weight) / NULLIF(COUNT(c.id), 0)::numeric), 1) AS weight_efficiency_pct,
        SUM(c.lines_added)::bigint AS total_lines_added,
        SUM(c.lines_deleted)::bigint AS total_lines_deleted,
        SUM(c.lines_added + c.lines_deleted)::bigint AS total_lines_changed,
        ROUND(SUM(c.lines_added * c.weight / 100.0)::numeric, 2) AS weighted_lines_added,
        ROUND(SUM(c.lines_deleted * c.weight / 100.0)::numeric, 2) AS weighted_lines_deleted,
        ROUND(SUM((c.lines_added + c.lines_deleted) * c.weight / 100.0)::numeric, 2) AS weighted_lines_changed,
        ROUND(AVG(c.lines_added + c.lines_deleted)::numeric, 1) AS avg_lines_per_commit
      FROM commits c
      JOIN repositories r ON c.repository_id = r.id
      LEFT JOIN categories cat ON c.category = cat.name
      WHERE c.weight > 0
      GROUP BY c.author_email, c.author_name, r.id, r.name,
               DATE_TRUNC('month', c.commit_date), TO_CHAR(c.commit_date, 'YYYY-MM'),
               c.category, cat.weight
      ORDER BY c.author_email, r.name, month_start_date DESC, total_commits DESC;

      CREATE INDEX idx_mv_monthly_category_by_author_email ON mv_monthly_category_stats_by_author(author_email, month_start_date);
      CREATE INDEX idx_mv_monthly_category_by_author_cat ON mv_monthly_category_stats_by_author(author_email, category);
      CREATE INDEX idx_mv_monthly_category_by_author_repo ON mv_monthly_category_stats_by_author(author_email, repository_id, month_start_date);

      -- ============================================================
      -- 3. RESTORE REFRESH FUNCTIONS
      -- ============================================================

      CREATE OR REPLACE FUNCTION refresh_category_mv()
      RETURNS void AS $$
      BEGIN
        REFRESH MATERIALIZED VIEW mv_monthly_category_stats;
        RAISE NOTICE 'Category materialized views refreshed successfully';
      END;
      $$ LANGUAGE plpgsql;

      CREATE OR REPLACE FUNCTION refresh_personal_mv()
      RETURNS void AS $$
      BEGIN
        REFRESH MATERIALIZED VIEW mv_monthly_stats_by_author;
        REFRESH MATERIALIZED VIEW mv_monthly_category_stats_by_author;
        RAISE NOTICE 'Personal performance materialized views refreshed successfully';
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end
end
