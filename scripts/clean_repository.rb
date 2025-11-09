#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv/load' unless ENV['RSPEC_RUNNING']
require 'pg'
require 'optparse'
require_relative '../lib/db_connection'

# Repository data cleaner for PostgreSQL
# Usage: ./scripts/clean_repository.rb REPO_NAME [OPTIONS]
class RepositoryCleaner
  def initialize(repo_name, options = {})
    @repo_name = repo_name
    @dry_run = options[:dry_run]
    @force = options[:force]
    @delete_repo = options[:delete_repo]
    @conn = nil
  end

  def run
    validate_repo_name!
    connect_to_database

    repo_id = find_repository
    return unless repo_id

    show_deletion_summary(repo_id)

    return if @dry_run

    unless @force
      confirm_deletion || return
    end

    delete_data(repo_id)
    print_final_summary
  ensure
    disconnect_from_database
  end

  private

  def validate_repo_name!
    if @repo_name.nil? || @repo_name.strip.empty?
      abort "Error: Repository name is required"
    end
  end

  def connect_to_database
    db_config = DBConnection.connection_params

    puts "Connecting to database..."
    puts "  Host: #{db_config[:host]}"
    puts "  Database: #{db_config[:dbname]}"
    puts "  User: #{db_config[:user]}"
    puts ""

    # Safety check: warn if not using test database
    if db_config[:dbname] && !db_config[:dbname].end_with?('_test')
      puts "⚠️  WARNING: You are about to modify production database '#{db_config[:dbname]}'"
      puts "   To use test database, set PGDATABASE=#{db_config[:dbname]}_test"
      puts ""
    end

    @conn = PG.connect(db_config)
    puts "✓ Connected successfully"
    puts ""
  rescue PG::Error => e
    abort "Error connecting to database: #{e.message}"
  end

  def disconnect_from_database
    return unless @conn

    @conn.close
  end

  def find_repository
    result = @conn.exec_params(
      'SELECT id, name, url FROM repositories WHERE name = $1',
      [@repo_name]
    )

    if result.ntuples.zero?
      puts "❌ Repository '#{@repo_name}' not found in database"
      puts ""
      puts "Available repositories:"
      all_repos = @conn.exec('SELECT name FROM repositories ORDER BY name')
      all_repos.each { |row| puts "  - #{row['name']}" }
      return nil
    end

    result[0]['id'].to_i
  end

  def show_deletion_summary(repo_id)
    # Get commit count
    commit_result = @conn.exec_params(
      'SELECT COUNT(*) as count FROM commits WHERE repository_id = $1',
      [repo_id]
    )
    commit_count = commit_result[0]['count'].to_i

    # Get repository details
    repo_result = @conn.exec_params(
      'SELECT * FROM repositories WHERE id = $1',
      [repo_id]
    )
    repo = repo_result[0]

    puts "=" * 60
    puts "DELETION SUMMARY"
    puts "=" * 60
    puts ""
    puts "Repository: #{repo['name']}"
    puts "URL: #{repo['url']}"
    puts "Last extracted: #{repo['last_extracted_at']}"
    puts ""
    puts "Data to be deleted:"
    puts "  - #{commit_count} commits"

    if @delete_repo
      puts "  - Repository record itself"
    else
      puts "  - Repository record will be KEPT (use --delete-repo to remove)"
    end

    puts ""
    puts "=" * 60
    puts ""

    if @dry_run
      puts "🔍 DRY RUN MODE - No data will be deleted"
      puts ""
    end
  end

  def confirm_deletion
    print "Are you sure you want to delete this data? (type 'yes' to confirm): "
    $stdout.flush  # Ensure prompt is displayed
    response = $stdin.gets

    # Handle nil (stdin not available) or empty response
    if response.nil?
      puts ""
      puts "❌ Deletion cancelled (no input received)"
      return false
    end

    response = response.chomp

    unless response.downcase == 'yes'
      puts ""
      puts "❌ Deletion cancelled"
      return false
    end

    puts ""
    true
  end

  def delete_data(repo_id)
    puts "Deleting data..."
    puts ""

    @conn.exec('BEGIN')

    # Delete commits
    result = @conn.exec_params(
      'DELETE FROM commits WHERE repository_id = $1',
      [repo_id]
    )
    deleted_commits = result.cmd_tuples
    puts "✓ Deleted #{deleted_commits} commits"

    # Optionally delete repository
    if @delete_repo
      @conn.exec_params(
        'DELETE FROM repositories WHERE id = $1',
        [repo_id]
      )
      puts "✓ Deleted repository record"
    else
      # Update last_extracted_at to NULL
      @conn.exec_params(
        'UPDATE repositories SET last_extracted_at = NULL WHERE id = $1',
        [repo_id]
      )
      puts "✓ Reset repository extraction timestamp"
    end

    @conn.exec('COMMIT')
    puts ""
  rescue PG::Error => e
    @conn.exec('ROLLBACK') if @conn
    abort "Error deleting data: #{e.message}"
  end

  def print_final_summary
    puts "=" * 60
    puts "✅ CLEANUP COMPLETE"
    puts "=" * 60
    puts ""
    puts "Repository '#{@repo_name}' data has been cleaned"
    puts ""
    puts "Next steps:"
    puts "  1. Run extraction to reload fresh data:"
    puts "     ./scripts/run_extraction.sh #{@repo_name}"
    puts ""
    puts "  Or use the combined script:"
    puts "     ./scripts/clean_and_reload.sh #{@repo_name}"
    puts ""
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  options = {
    dry_run: false,
    force: false,
    delete_repo: false
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} REPO_NAME [OPTIONS]"
    opts.separator ""
    opts.separator "Clean (delete) all data for a specific repository"
    opts.separator ""
    opts.separator "Options:"

    opts.on('--dry-run', 'Show what would be deleted without actually deleting') do
      options[:dry_run] = true
    end

    opts.on('--force', 'Skip confirmation prompt') do
      options[:force] = true
    end

    opts.on('--delete-repo', 'Also delete the repository record (not just commits)') do
      options[:delete_repo] = true
    end

    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      puts ""
      puts "Examples:"
      puts "  # Dry run to see what would be deleted"
      puts "  #{$PROGRAM_NAME} mater --dry-run"
      puts ""
      puts "  # Delete commits but keep repository record"
      puts "  #{$PROGRAM_NAME} mater"
      puts ""
      puts "  # Delete everything including repository record"
      puts "  #{$PROGRAM_NAME} mater --delete-repo"
      puts ""
      puts "  # Skip confirmation (use with caution!)"
      puts "  #{$PROGRAM_NAME} mater --force"
      puts ""
      puts "Environment Variables:"
      puts "  DATABASE_URL   PostgreSQL connection URL (takes priority if set)"
      puts "                 Format: postgresql://user:pass@host:port/dbname?sslmode=require"
      puts "  PGHOST         PostgreSQL host (default: localhost)"
      puts "  PGPORT         PostgreSQL port (default: 5432)"
      puts "  PGDATABASE     Database name (default: git_analytics)"
      puts "  PGUSER         Database user (default: current user)"
      puts "  PGPASSWORD     Database password"
      puts ""
      exit
    end
  end.parse!

  if ARGV.empty?
    puts "Error: Repository name is required"
    puts "Usage: #{$PROGRAM_NAME} REPO_NAME [OPTIONS]"
    puts "Run with --help for more information"
    exit 1
  end

  repo_name = ARGV[0]

  begin
    cleaner = RepositoryCleaner.new(repo_name, options)
    cleaner.run
  rescue Interrupt
    puts "\n\n❌ Interrupted by user"
    exit(1)
  rescue StandardError => e
    abort "Error: #{e.message}"
  end
end
