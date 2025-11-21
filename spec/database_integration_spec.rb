# frozen_string_literal: true

require 'spec_helper'
require 'pg'
require 'tmpdir'
require 'json'

RSpec.describe 'Database Integration', :db_integration do
  let(:temp_dir) { Dir.mktmpdir }
  let(:json_file) { File.join(temp_dir, 'test_data.json') }
  let(:test_data) do
    {
      'repository' => 'test-integration-repo',
      'repository_path' => '/test/path',
      'extraction_date' => Time.now.iso8601,
      'date_range' => {
        'from' => '1 month ago',
        'to' => 'now'
      },
      'summary' => {
        'total_commits' => 2,
        'total_lines_added' => 100,
        'total_lines_deleted' => 50,
        'total_files_changed' => 5,
        'unique_authors' => 1
      },
      'commits' => [
        {
          'hash' => 'a' * 40,
          'date' => '2024-10-01T10:00:00Z',
          'author_name' => 'Test User',
          'author_email' => 'test@example.com',
          'subject' => 'Test commit 1',
          'lines_added' => 50,
          'lines_deleted' => 20,
          'files_changed' => 3,
          'files' => []
        },
        {
          'hash' => 'b' * 40,
          'date' => '2024-10-02T10:00:00Z',
          'author_name' => 'Test User',
          'author_email' => 'test@example.com',
          'subject' => 'Test commit 2',
          'lines_added' => 50,
          'lines_deleted' => 30,
          'files_changed' => 2,
          'files' => []
        }
      ]
    }
  end

  let(:db_config) do
    {
      host: ENV['PGHOST'] || 'localhost',
      port: (ENV['PGPORT'] || 5432).to_i,
      dbname: ENV['PGDATABASE'] || 'git_analytics_test',
      user: ENV['PGUSER'] || ENV['USER'],
      password: ENV['PGPASSWORD']
    }
  end

  let(:conn) { PG.connect(db_config) }

  before(:all) do
    # Verify test database exists
    test_db = ENV['PGDATABASE'] || 'git_analytics_test'
    unless test_db.end_with?('_test')
      raise "Safety check: Not using test database! Current: #{test_db}"
    end
  end

  before do
    # Clean up test data before each test
    begin
      # Clean up all test data with test email to prevent cross-test pollution
      conn.exec("DELETE FROM commits WHERE author_email = 'test@example.com' OR repository_id IN (SELECT id FROM repositories WHERE name LIKE 'test-%')")
      conn.exec("DELETE FROM repositories WHERE name LIKE 'test-%'")
    rescue PG::Error => e
      skip "Database not available: #{e.message}"
    end

    File.write(json_file, JSON.pretty_generate(test_data))
  end

  after do
    FileUtils.rm_rf(temp_dir)
    conn.close if conn && !conn.finished?
  end

  describe 'Database connection' do
    it 'connects to test database successfully' do
      expect(conn).not_to be_nil
      expect(conn.db).to end_with('_test')
    end

    it 'has the correct schema' do
      result = conn.exec("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name")
      tables = result.map { |row| row['table_name'] }

      expect(tables).to include('repositories')
      expect(tables).to include('commits')
    end

    it 'has the correct views' do
      result = conn.exec("SELECT table_name FROM information_schema.views WHERE table_schema = 'public' ORDER BY table_name")
      views = result.map { |row| row['table_name'] }

      expect(views).to include('v_commit_details')
      expect(views).to include('v_daily_stats_by_repo')
      expect(views).to include('v_contributor_stats')
    end

    it 'has materialized views' do
      result = conn.exec("SELECT matviewname FROM pg_matviews WHERE schemaname = 'public'")
      matviews = result.map { |row| row['matviewname'] }

      expect(matviews).to include('mv_monthly_stats_by_repo')
    end
  end

  describe 'DataLoader integration with real database' do
    it 'loads data successfully' do
      # Require the loader here to ensure bundler/setup is loaded
      require_relative '../scripts/load_json_to_db'

      loader = DataLoader.new(json_file, db_config)

      # Suppress output
      allow(loader).to receive(:puts)
      allow(loader).to receive(:print)

      expect { loader.run }.not_to raise_error

      # Verify data was loaded
      result = conn.exec_params(
        'SELECT COUNT(*) FROM commits WHERE repository_id = (SELECT id FROM repositories WHERE name = $1)',
        ['test-integration-repo']
      )
      expect(result[0]['count'].to_i).to eq(2)
    end

    it 'creates repository record' do
      require_relative '../scripts/load_json_to_db'

      loader = DataLoader.new(json_file, db_config)
      allow(loader).to receive(:puts)
      allow(loader).to receive(:print)

      loader.run

      result = conn.exec_params(
        'SELECT * FROM repositories WHERE name = $1',
        ['test-integration-repo']
      )

      expect(result.ntuples).to eq(1)
      repo = result[0]
      expect(repo['name']).to eq('test-integration-repo')
      expect(repo['url']).to eq('/test/path')
    end

    it 'inserts commits with correct data' do
      require_relative '../scripts/load_json_to_db'

      loader = DataLoader.new(json_file, db_config)
      allow(loader).to receive(:puts)
      allow(loader).to receive(:print)

      loader.run

      result = conn.exec_params(
        'SELECT * FROM commits WHERE repository_id = (SELECT id FROM repositories WHERE name = $1) ORDER BY commit_date',
        ['test-integration-repo']
      )

      expect(result.ntuples).to eq(2)

      commit1 = result[0]
      expect(commit1['hash']).to eq('a' * 40)
      expect(commit1['author_name']).to eq('Test User')
      expect(commit1['author_email']).to eq('test@example.com')
      expect(commit1['lines_added'].to_i).to eq(50)
      expect(commit1['lines_deleted'].to_i).to eq(20)
      expect(commit1['files_changed'].to_i).to eq(3)

      commit2 = result[1]
      expect(commit2['hash']).to eq('b' * 40)
    end

    it 'handles duplicate commits gracefully' do
      require_relative '../scripts/load_json_to_db'

      loader = DataLoader.new(json_file, db_config)
      allow(loader).to receive(:puts)
      allow(loader).to receive(:print)

      # Load once
      loader.run

      # Load again - should skip duplicates
      loader2 = DataLoader.new(json_file, db_config)
      allow(loader2).to receive(:puts)
      allow(loader2).to receive(:print)

      expect { loader2.run }.not_to raise_error

      # Should still have only 2 commits
      result = conn.exec_params(
        'SELECT COUNT(*) FROM commits WHERE repository_id = (SELECT id FROM repositories WHERE name = $1)',
        ['test-integration-repo']
      )
      expect(result[0]['count'].to_i).to eq(2)
    end

    it 'queries aggregated views successfully' do
      require_relative '../scripts/load_json_to_db'

      loader = DataLoader.new(json_file, db_config)
      allow(loader).to receive(:puts)
      allow(loader).to receive(:print)

      loader.run

      # Query contributor stats
      result = conn.exec_params(
        'SELECT * FROM v_contributor_stats WHERE author_email = $1',
        ['test@example.com']
      )

      expect(result.ntuples).to eq(1)
      stats = result[0]
      expect(stats['total_commits'].to_i).to eq(2)
      expect(stats['total_lines_added'].to_i).to eq(100)
      expect(stats['total_lines_deleted'].to_i).to eq(50)
    end
  end

  describe 'Weight synchronization integration' do
    before do
      # Clean up test data
      conn.exec("DELETE FROM commits WHERE repository_id IN (SELECT id FROM repositories WHERE name = 'test-sync-repo')")
      conn.exec("DELETE FROM repositories WHERE name = 'test-sync-repo'")
      conn.exec("DELETE FROM categories WHERE name = 'SYNC_TEST'")
    end

    after do
      # Cleanup
      conn.exec("DELETE FROM commits WHERE repository_id IN (SELECT id FROM repositories WHERE name = 'test-sync-repo')")
      conn.exec("DELETE FROM repositories WHERE name = 'test-sync-repo'")
      conn.exec("DELETE FROM categories WHERE name = 'SYNC_TEST'")
    end

    it 'syncs commit weights from category weights' do
      require_relative '../scripts/sync_commit_weights_from_categories'

      # Setup: Create repo, category, commits
      repo_id = conn.exec_params(
        "INSERT INTO repositories (name, url) VALUES ($1, $2) RETURNING id",
        ['test-sync-repo', '/test/path']
      )[0]['id']

      # Create category with weight 60
      conn.exec_params(
        "INSERT INTO categories (name, weight) VALUES ($1, $2)",
        ['SYNC_TEST', 60]
      )

      # Insert commit with default weight (100)
      conn.exec_params(
        "INSERT INTO commits (repository_id, hash, commit_date, author_name, author_email, subject, lines_added, lines_deleted, files_changed, weight, category)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
        [repo_id, 'd' * 40, '2024-01-01', 'Test', 'test@test.com', 'Test commit', 100, 50, 5, 100, 'SYNC_TEST']
      )

      # Verify initial weight
      result_before = conn.exec_params(
        "SELECT weight FROM commits WHERE hash = $1",
        ['d' * 40]
      )
      expect(result_before[0]['weight'].to_i).to eq(100)

      # Run synchronizer
      synchronizer = CommitWeightSynchronizer.new(dry_run: false)
      allow(synchronizer).to receive(:puts)
      allow(synchronizer).to receive(:print)
      synchronizer.run

      # Verify weight was synced to category weight
      result_after = conn.exec_params(
        "SELECT weight FROM commits WHERE hash = $1",
        ['d' * 40]
      )

      expect(result_after[0]['weight'].to_i).to eq(60)
    end

    it 'preserves reverted commit weights during sync' do
      require_relative '../scripts/sync_commit_weights_from_categories'

      # Setup: Create repo, category, commits
      repo_id = conn.exec_params(
        "INSERT INTO repositories (name, url) VALUES ($1, $2) RETURNING id",
        ['test-sync-repo', '/test/path']
      )[0]['id']

      # Create category with weight 60
      conn.exec_params(
        "INSERT INTO categories (name, weight) VALUES ($1, $2)",
        ['SYNC_TEST', 60]
      )

      # Insert reverted commit (weight=0)
      conn.exec_params(
        "INSERT INTO commits (repository_id, hash, commit_date, author_name, author_email, subject, lines_added, lines_deleted, files_changed, weight, category)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
        [repo_id, 'e' * 40, '2024-01-01', 'Test', 'test@test.com', 'Reverted commit', 100, 50, 5, 0, 'SYNC_TEST']
      )

      # Verify initial weight is 0
      result_before = conn.exec_params(
        "SELECT weight FROM commits WHERE hash = $1",
        ['e' * 40]
      )
      expect(result_before[0]['weight'].to_i).to eq(0)

      # Run synchronizer
      synchronizer = CommitWeightSynchronizer.new(dry_run: false)
      allow(synchronizer).to receive(:puts)
      allow(synchronizer).to receive(:print)
      synchronizer.run

      # Verify weight is still 0 (not synced for reverted commits)
      result_after = conn.exec_params(
        "SELECT weight FROM commits WHERE hash = $1",
        ['e' * 40]
      )

      expect(result_after[0]['weight'].to_i).to eq(0)
    end
  end
end
