# frozen_string_literal: true

require 'spec_helper'
require 'pg'
require_relative '../lib/db_connection'

RSpec.describe 'PostgreSQL Views', :db_integration do
  let(:conn) { PG.connect(DBConnection.connection_params) }

  after { conn.close if conn && !conn.finished? }

  describe 'Standard Views' do
    describe 'v_daily_stats_by_repo' do
      it 'includes weight analysis columns' do
        result = conn.exec("SELECT * FROM v_daily_stats_by_repo LIMIT 0")
        columns = result.fields

        expect(columns).to include('effective_commits')
        expect(columns).to include('avg_weight')
        expect(columns).to include('weight_efficiency_pct')
      end

      it 'includes standard metric columns' do
        result = conn.exec("SELECT * FROM v_daily_stats_by_repo LIMIT 0")
        columns = result.fields

        expect(columns).to include('repository_id')
        expect(columns).to include('repository_name')
        expect(columns).to include('commit_date')
        expect(columns).to include('total_commits')
        expect(columns).to include('weighted_lines_changed')
      end
    end

    describe 'v_weekly_stats_by_repo' do
      it 'includes weight analysis columns' do
        result = conn.exec("SELECT * FROM v_weekly_stats_by_repo LIMIT 0")
        columns = result.fields

        expect(columns).to include('effective_commits')
        expect(columns).to include('avg_weight')
        expect(columns).to include('weight_efficiency_pct')
      end
    end

    describe 'mv_monthly_stats_by_repo' do
      it 'includes weight analysis columns' do
        result = conn.exec("SELECT * FROM mv_monthly_stats_by_repo LIMIT 0")
        columns = result.fields

        expect(columns).to include('effective_commits')
        expect(columns).to include('avg_weight')
        expect(columns).to include('weight_efficiency_pct')
      end

      it 'is a materialized view' do
        result = conn.exec("
          SELECT schemaname, matviewname
          FROM pg_matviews
          WHERE matviewname = 'mv_monthly_stats_by_repo'
        ")

        expect(result.ntuples).to eq(1)
      end
    end

    describe 'v_contributor_stats' do
      it 'includes weight analysis columns' do
        result = conn.exec("SELECT * FROM v_contributor_stats LIMIT 0")
        columns = result.fields

        expect(columns).to include('effective_commits')
        expect(columns).to include('avg_weight')
        expect(columns).to include('weight_efficiency_pct')
      end
    end

    describe 'v_ai_tools_stats' do
      it 'includes weight analysis columns' do
        result = conn.exec("SELECT * FROM v_ai_tools_stats LIMIT 0")
        columns = result.fields

        expect(columns).to include('effective_commits')
        expect(columns).to include('avg_weight')
        expect(columns).to include('weight_efficiency_pct')
      end
    end

    describe 'v_ai_tools_by_repo' do
      it 'includes weight analysis columns' do
        result = conn.exec("SELECT * FROM v_ai_tools_by_repo LIMIT 0")
        columns = result.fields

        expect(columns).to include('effective_commits')
        expect(columns).to include('avg_weight')
        expect(columns).to include('weight_efficiency_pct')
      end
    end
  end

  describe 'Category Views' do
    describe 'v_category_stats' do
      it 'includes weight analysis columns' do
        result = conn.exec("SELECT * FROM v_category_stats LIMIT 0")
        columns = result.fields

        expect(columns).to include('effective_commits')
        expect(columns).to include('avg_weight')
        expect(columns).to include('weight_efficiency_pct')
      end
    end

    describe 'v_category_by_repo' do
      it 'includes weight analysis columns' do
        result = conn.exec("SELECT * FROM v_category_by_repo LIMIT 0")
        columns = result.fields

        expect(columns).to include('effective_commits')
        expect(columns).to include('avg_weight')
        expect(columns).to include('weight_efficiency_pct')
      end
    end

    describe 'mv_monthly_category_stats' do
      it 'includes weight analysis columns' do
        result = conn.exec("SELECT * FROM mv_monthly_category_stats LIMIT 0")
        columns = result.fields

        expect(columns).to include('effective_commits')
        expect(columns).to include('avg_weight')
        expect(columns).to include('weight_efficiency_pct')
      end

      it 'is a materialized view' do
        result = conn.exec("
          SELECT schemaname, matviewname
          FROM pg_matviews
          WHERE matviewname = 'mv_monthly_category_stats'
        ")

        expect(result.ntuples).to eq(1)
      end
    end
  end

  describe 'Weight metric calculations' do
    before do
      # Setup test data with varied weights
      conn.exec("DELETE FROM commits WHERE repository_id IN (SELECT id FROM repositories WHERE name = 'test-weight-repo')")
      conn.exec("DELETE FROM repositories WHERE name = 'test-weight-repo'")

      @repo_id = conn.exec_params(
        "INSERT INTO repositories (name, url) VALUES ($1, $2) RETURNING id",
        ['test-weight-repo', '/test/path']
      )[0]['id']

      # Insert commits with different weights
      # Commit 1: weight=100 (full weight)
      conn.exec_params(
        "INSERT INTO commits (repository_id, hash, commit_date, author_name, author_email, subject, lines_added, lines_deleted, files_changed, weight, category)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
        [@repo_id, 'a' * 40, '2024-01-01', 'Test Author', 'test@test.com', 'Test commit 1', 100, 50, 5, 100, 'TEST_WEIGHT_CATEGORY']
      )

      # Commit 2: weight=50 (half weight)
      conn.exec_params(
        "INSERT INTO commits (repository_id, hash, commit_date, author_name, author_email, subject, lines_added, lines_deleted, files_changed, weight, category)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
        [@repo_id, 'b' * 40, '2024-01-02', 'Test Author', 'test@test.com', 'Test commit 2', 100, 50, 5, 50, 'TEST_WEIGHT_CATEGORY']
      )

      # Commit 3: weight=0 (reverted, excluded from views)
      conn.exec_params(
        "INSERT INTO commits (repository_id, hash, commit_date, author_name, author_email, subject, lines_added, lines_deleted, files_changed, weight, category)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
        [@repo_id, 'c' * 40, '2024-01-03', 'Test Author', 'test@test.com', 'Revert test commit', 100, 50, 5, 0, 'TEST_WEIGHT_CATEGORY']
      )

      # Refresh materialized views
      conn.exec("REFRESH MATERIALIZED VIEW mv_monthly_stats_by_repo")
      conn.exec("REFRESH MATERIALIZED VIEW mv_monthly_category_stats")
    end

    after do
      conn.exec("DELETE FROM commits WHERE repository_id = #{@repo_id}")
      conn.exec("DELETE FROM repositories WHERE id = #{@repo_id}")
    end

    it 'calculates effective_commits correctly' do
      result = conn.exec_params(
        "SELECT effective_commits FROM mv_monthly_stats_by_repo WHERE repository_id = $1",
        [@repo_id]
      )

      # (100/100) + (50/100) = 1.0 + 0.5 = 1.5 effective commits
      # (weight=0 commit is excluded by WHERE weight > 0)
      expect(result[0]['effective_commits'].to_f).to eq(1.5)
    end

    it 'calculates avg_weight correctly' do
      result = conn.exec_params(
        "SELECT avg_weight FROM mv_monthly_stats_by_repo WHERE repository_id = $1",
        [@repo_id]
      )

      # (100 + 50) / 2 = 75.0 (excluding weight=0 commits)
      expect(result[0]['avg_weight'].to_f).to eq(75.0)
    end

    it 'calculates weight_efficiency_pct correctly' do
      result = conn.exec_params(
        "SELECT weight_efficiency_pct FROM mv_monthly_stats_by_repo WHERE repository_id = $1",
        [@repo_id]
      )

      # (1.5 effective / 2 total) * 100 = 75.0%
      expect(result[0]['weight_efficiency_pct'].to_f).to eq(75.0)
    end

    it 'excludes reverted commits (weight=0) from views' do
      result = conn.exec_params(
        "SELECT total_commits FROM mv_monthly_stats_by_repo WHERE repository_id = $1",
        [@repo_id]
      )

      # Should count only 2 commits (weight > 0), excluding the reverted one
      expect(result[0]['total_commits'].to_i).to eq(2)
    end

    it 'category view calculates effective_commits correctly' do
      result = conn.exec("
        SELECT effective_commits, total_commits
        FROM v_category_stats
        WHERE category = 'TEST_WEIGHT_CATEGORY'
      ")

      expect(result[0]['effective_commits'].to_f).to eq(1.5)
      expect(result[0]['total_commits'].to_i).to eq(2)
    end
  end
end
