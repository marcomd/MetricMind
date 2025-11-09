# frozen_string_literal: true

require 'spec_helper'
require 'pg'
require 'tmpdir'
require 'json'
require 'open3'

RSpec.describe 'Repository Cleanup', :db_integration do
  let(:temp_dir) { Dir.mktmpdir }
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
    # Verify test database
    test_db = ENV['PGDATABASE'] || 'git_analytics_test'
    unless test_db.end_with?('_test')
      raise "Safety check: Not using test database! Current: #{test_db}"
    end
  end

  before do
    # Setup test data
    setup_test_repositories
  end

  after do
    # Cleanup test data
    cleanup_test_data
    FileUtils.rm_rf(temp_dir)
    conn.close if conn && !conn.finished?
  end

  def setup_test_repositories
    conn.exec("DELETE FROM commits")
    conn.exec("DELETE FROM repositories")

    # Create two test repositories
    conn.exec_params(
      'INSERT INTO repositories (name, url, last_extracted_at) VALUES ($1, $2, $3)',
      ['test-repo-1', '/test/path1', Time.now]
    )
    repo1_id = conn.exec('SELECT id FROM repositories WHERE name = $1', ['test-repo-1'])[0]['id']

    conn.exec_params(
      'INSERT INTO repositories (name, url, last_extracted_at) VALUES ($1, $2, $3)',
      ['test-repo-2', '/test/path2', Time.now]
    )
    repo2_id = conn.exec('SELECT id FROM repositories WHERE name = $1', ['test-repo-2'])[0]['id']

    # Add commits for repo1
    3.times do |i|
      conn.exec_params(
        'INSERT INTO commits (repository_id, hash, commit_date, author_name, author_email, subject, lines_added, lines_deleted, files_changed) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)',
        [repo1_id, "a#{i}" * 20, "2024-10-0#{i + 1}T10:00:00Z", 'Test User', 'test@example.com', "Commit #{i}", 10, 5, 2]
      )
    end

    # Add commits for repo2
    2.times do |i|
      conn.exec_params(
        'INSERT INTO commits (repository_id, hash, commit_date, author_name, author_email, subject, lines_added, lines_deleted, files_changed) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)',
        [repo2_id, "b#{i}" * 20, "2024-10-0#{i + 1}T10:00:00Z", 'Test User', 'test@example.com', "Commit #{i}", 10, 5, 2]
      )
    end
  rescue PG::Error => e
    skip "Database not available: #{e.message}"
  end

  def cleanup_test_data
    begin
      conn.exec("DELETE FROM commits WHERE repository_id IN (SELECT id FROM repositories WHERE name LIKE 'test-repo-%')")
      conn.exec("DELETE FROM repositories WHERE name LIKE 'test-repo-%'")
    rescue PG::Error
      # Ignore cleanup errors
    end
  end

  # Helper to build test environment for subprocess
  def test_env
    {
      'RSPEC_RUNNING' => 'true',
      'PGDATABASE' => ENV['PGDATABASE'],
      'PGHOST' => ENV['PGHOST'] || 'localhost',
      'PGPORT' => ENV['PGPORT'] || '5432',
      'PGUSER' => ENV['PGUSER'] || ENV['USER']
    }.compact
  end

  describe 'clean_repository.rb' do
    let(:script_path) { File.join(File.dirname(__dir__), 'scripts', 'clean_repository.rb') }

    it 'shows help message with --help flag' do
      output, status = Open3.capture2('ruby', script_path, '--help')

      expect(status.success?).to be true
      expect(output).to include('Usage:')
      expect(output).to include('--dry-run')
      expect(output).to include('--force')
      expect(output).to include('--delete-repo')
    end

    it 'requires repository name argument' do
      output, status = Open3.capture2(test_env, 'ruby', script_path, :err => [:child, :out])

      expect(status.success?).to be false
      expect(output).to include('Repository name is required')
    end

    it 'deletes commits for specific repository only' do
      # Verify initial state
      repo1_commits = conn.exec('SELECT COUNT(*) FROM commits WHERE repository_id = (SELECT id FROM repositories WHERE name = $1)', ['test-repo-1'])[0]['count'].to_i
      repo2_commits = conn.exec('SELECT COUNT(*) FROM commits WHERE repository_id = (SELECT id FROM repositories WHERE name = $1)', ['test-repo-2'])[0]['count'].to_i

      expect(repo1_commits).to eq(3)
      expect(repo2_commits).to eq(2)

      # Clean repo1 with --force to skip confirmation
      output, status = Open3.capture2(test_env, 'ruby', script_path, 'test-repo-1', '--force')

      expect(status.success?).to be true
      expect(output).to include('CLEANUP COMPLETE')

      # Verify repo1 commits deleted
      repo1_commits_after = conn.exec('SELECT COUNT(*) FROM commits WHERE repository_id = (SELECT id FROM repositories WHERE name = $1)', ['test-repo-1'])[0]['count'].to_i
      expect(repo1_commits_after).to eq(0)

      # Verify repo2 commits NOT deleted
      repo2_commits_after = conn.exec('SELECT COUNT(*) FROM commits WHERE repository_id = (SELECT id FROM repositories WHERE name = $1)', ['test-repo-2'])[0]['count'].to_i
      expect(repo2_commits_after).to eq(2)

      # Verify repo1 record still exists (not deleted by default)
      repo1_exists = conn.exec('SELECT COUNT(*) FROM repositories WHERE name = $1', ['test-repo-1'])[0]['count'].to_i
      expect(repo1_exists).to eq(1)
    end

    it 'supports dry-run mode without deleting' do
      # Verify initial state
      initial_commits = conn.exec('SELECT COUNT(*) FROM commits WHERE repository_id = (SELECT id FROM repositories WHERE name = $1)', ['test-repo-1'])[0]['count'].to_i
      expect(initial_commits).to eq(3)

      # Run dry-run
      output, status = Open3.capture2(test_env, 'ruby', script_path, 'test-repo-1', '--dry-run')

      expect(status.success?).to be true
      expect(output).to include('DRY RUN MODE')
      expect(output).to include('3 commits')

      # Verify nothing was deleted
      commits_after = conn.exec('SELECT COUNT(*) FROM commits WHERE repository_id = (SELECT id FROM repositories WHERE name = $1)', ['test-repo-1'])[0]['count'].to_i
      expect(commits_after).to eq(3)
    end

    it 'deletes repository record with --delete-repo flag' do
      output, status = Open3.capture2(test_env, 'ruby', script_path, 'test-repo-1', '--force', '--delete-repo')

      expect(status.success?).to be true

      # Verify repository record was deleted
      repo_exists = conn.exec('SELECT COUNT(*) FROM repositories WHERE name = $1', ['test-repo-1'])[0]['count'].to_i
      expect(repo_exists).to eq(0)
    end

    it 'reports error for non-existent repository' do
      output, status = Open3.capture2(test_env, 'ruby', script_path, 'non-existent-repo', '--force', :err => [:child, :out])

      expect(status.success?).to be true
      expect(output).to include("Repository 'non-existent-repo' not found")
      expect(output).to include('Available repositories:')
    end

    it 'resets last_extracted_at when keeping repository' do
      # Get initial last_extracted_at
      initial_time = conn.exec('SELECT last_extracted_at FROM repositories WHERE name = $1', ['test-repo-1'])[0]['last_extracted_at']
      expect(initial_time).not_to be_nil

      # Clean repository
      Open3.capture2(test_env, 'ruby', script_path, 'test-repo-1', '--force')

      # Verify last_extracted_at is NULL
      updated_time = conn.exec('SELECT last_extracted_at FROM repositories WHERE name = $1', ['test-repo-1'])[0]['last_extracted_at']
      expect(updated_time).to be_nil
    end
  end

  describe 'Data integrity after cleanup' do
    it 'maintains foreign key constraints' do
      # Clean repo1
      Open3.capture2(test_env, 'ruby', 'scripts/clean_repository.rb', 'test-repo-1', '--force')

      # Verify no orphaned commits
      orphaned_commits = conn.exec(
        'SELECT COUNT(*) FROM commits WHERE repository_id NOT IN (SELECT id FROM repositories)'
      )[0]['count'].to_i

      expect(orphaned_commits).to eq(0)
    end

    it 'allows re-insertion after cleanup' do
      # Clean repo1
      Open3.capture2(test_env, 'ruby', 'scripts/clean_repository.rb', 'test-repo-1', '--force')

      # Re-insert commits
      repo_id = conn.exec('SELECT id FROM repositories WHERE name = $1', ['test-repo-1'])[0]['id']

      expect {
        conn.exec_params(
          'INSERT INTO commits (repository_id, hash, commit_date, author_name, author_email, subject, lines_added, lines_deleted, files_changed) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)',
          [repo_id, 'c' * 40, '2024-10-05T10:00:00Z', 'Test User', 'test@example.com', 'New commit', 10, 5, 2]
        )
      }.not_to raise_error
    end
  end
end
