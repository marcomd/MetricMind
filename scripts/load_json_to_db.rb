#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'json'
require 'pg'
require 'time'

# JSON data loader for PostgreSQL
# Usage: ./scripts/load_json_to_db.rb JSON_FILE [DB_CONFIG]
class DataLoader
  def initialize(json_file, db_config = nil)
    @json_file = File.expand_path(json_file)
    @db_config = db_config || default_db_config
    @conn = nil
    @stats = {
      repos_created: 0,
      repos_updated: 0,
      commits_inserted: 0,
      commits_skipped: 0,
      errors: 0
    }
  end

  def run
    validate_json_file!
    load_json_data
    connect_to_database
    begin_transaction
    load_repository
    load_commits
    commit_transaction
    refresh_materialized_views
    print_summary
  rescue StandardError => e
    rollback_transaction
    raise e
  ensure
    disconnect_from_database
  end

  private

  def default_db_config
    {
      host: ENV['PGHOST'] || 'localhost',
      port: ENV['PGPORT'] || 5432,
      dbname: ENV['PGDATABASE'] || 'git_analytics',
      user: ENV['PGUSER'] || ENV['USER'],
      password: ENV['PGPASSWORD']
    }
  end

  def validate_json_file!
    unless File.exist?(@json_file)
      abort "Error: JSON file not found: #{@json_file}"
    end
  end

  def load_json_data
    puts "Loading JSON data from #{@json_file}..."
    @data = JSON.parse(File.read(@json_file))

    required_keys = %w[repository commits]
    missing_keys = required_keys - @data.keys

    unless missing_keys.empty?
      abort "Error: JSON file missing required keys: #{missing_keys.join(', ')}"
    end
  rescue JSON::ParserError => e
    abort "Error: Invalid JSON file: #{e.message}"
  end

  def connect_to_database
    puts "Connecting to database..."
    puts "  Host: #{@db_config[:host]}"
    puts "  Database: #{@db_config[:dbname]}"
    puts "  User: #{@db_config[:user]}"

    @conn = PG.connect(@db_config)
    puts "✓ Connected successfully"
  rescue PG::Error => e
    abort "Error connecting to database: #{e.message}\n\n" \
          "Make sure PostgreSQL is running and the database exists.\n" \
          "You can set connection parameters via environment variables:\n" \
          "  PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD"
  end

  def disconnect_from_database
    return unless @conn

    @conn.close
    puts "✓ Database connection closed"
  end

  def begin_transaction
    @conn.exec('BEGIN')
  end

  def commit_transaction
    @conn.exec('COMMIT')
    puts "✓ Transaction committed"
  end

  def rollback_transaction
    return unless @conn

    @conn.exec('ROLLBACK')
    puts "✗ Transaction rolled back due to error"
  end

  def load_repository
    puts "\nLoading repository: #{@data['repository']}..."

    repo_name = @data['repository']
    repo_path = @data['repository_path']
    extraction_date = @data['extraction_date']

    # Check if repository exists
    result = @conn.exec_params(
      'SELECT id FROM repositories WHERE name = $1',
      [repo_name]
    )

    if result.ntuples.positive?
      # Update existing repository
      @repo_id = result[0]['id'].to_i
      @conn.exec_params(
        'UPDATE repositories SET last_extracted_at = $1, updated_at = $2, url = $3 WHERE id = $4',
        [extraction_date, Time.now, repo_path, @repo_id]
      )
      @stats[:repos_updated] += 1
      puts "  ✓ Updated existing repository (ID: #{@repo_id})"
    else
      # Insert new repository
      result = @conn.exec_params(
        'INSERT INTO repositories (name, url, last_extracted_at) VALUES ($1, $2, $3) RETURNING id',
        [repo_name, repo_path, extraction_date]
      )
      @repo_id = result[0]['id'].to_i
      @stats[:repos_created] += 1
      puts "  ✓ Created new repository (ID: #{@repo_id})"
    end
  end

  def load_commits
    commits = @data['commits']
    puts "\nLoading #{commits.length} commits..."

    return if commits.empty?

    # Prepare the insert statement
    insert_stmt = @conn.prepare('insert_commit', <<~SQL)
      INSERT INTO commits (
        repository_id, hash, commit_date, author_name, author_email,
        subject, lines_added, lines_deleted, files_changed
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      ON CONFLICT (repository_id, hash) DO NOTHING
      RETURNING id
    SQL

    # Process commits in batches for better performance
    batch_size = 100
    commits.each_slice(batch_size).with_index do |batch, batch_num|
      batch.each do |commit|
        begin
          result = @conn.exec_prepared(
            'insert_commit',
            [
              @repo_id,
              commit['hash'],
              commit['date'],
              commit['author_name'],
              commit['author_email'],
              commit['subject'],
              commit['lines_added'],
              commit['lines_deleted'],
              commit['files_changed']
            ]
          )

          if result.ntuples.positive?
            @stats[:commits_inserted] += 1
          else
            @stats[:commits_skipped] += 1
          end
        rescue PG::Error => e
          warn "  Warning: Error inserting commit #{commit['hash']}: #{e.message}"
          @stats[:errors] += 1
        end
      end

      # Progress indicator
      processed = [(batch_num + 1) * batch_size, commits.length].min
      percentage = (processed.to_f / commits.length * 100).round(1)
      print "\r  Progress: #{processed}/#{commits.length} (#{percentage}%)"
    end

    puts "\n  ✓ Commits loaded"
  end

  def refresh_materialized_views
    puts "\nRefreshing materialized views..."

    begin
      @conn.exec('REFRESH MATERIALIZED VIEW mv_monthly_stats_by_repo')
      puts "  ✓ Materialized views refreshed"
    rescue PG::Error => e
      warn "  Warning: Could not refresh materialized views: #{e.message}"
      warn "  You may need to run: SELECT refresh_all_mv();"
    end
  end

  def print_summary
    puts "\n" + "=" * 50
    puts "Data Load Summary"
    puts "=" * 50
    puts "Repository: #{@data['repository']}"
    puts "Date Range: #{@data['date_range']['from']} to #{@data['date_range']['to']}"
    puts ""
    puts "Results:"
    puts "  Repositories created: #{@stats[:repos_created]}"
    puts "  Repositories updated: #{@stats[:repos_updated]}"
    puts "  Commits inserted:     #{@stats[:commits_inserted]}"
    puts "  Commits skipped:      #{@stats[:commits_skipped]} (duplicates)"
    puts "  Errors:               #{@stats[:errors]}"
    puts ""
    puts "Total commits in DB for this repository: #{get_total_commits}"
    puts "=" * 50
  end

  def get_total_commits
    result = @conn.exec_params(
      'SELECT COUNT(*) FROM commits WHERE repository_id = $1',
      [@repo_id]
    )
    result[0]['count']
  rescue PG::Error
    'unknown'
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  if ARGV.include?('-h') || ARGV.include?('--help') || ARGV.empty?
    puts <<~HELP
      Git Commit Data Loader (PostgreSQL)

      Usage:
        #{$PROGRAM_NAME} JSON_FILE

      Arguments:
        JSON_FILE    Path to JSON file generated by git_extract_to_json.rb

      Environment Variables:
        PGHOST       PostgreSQL host (default: localhost)
        PGPORT       PostgreSQL port (default: 5432)
        PGDATABASE   Database name (default: git_analytics)
        PGUSER       Database user (default: current user)
        PGPASSWORD   Database password (if required)

      Examples:
        # Load data using default connection
        #{$PROGRAM_NAME} data/my-repo.json

        # Load data with custom connection
        PGHOST=db.example.com PGDATABASE=prod_analytics #{$PROGRAM_NAME} data/my-repo.json

        # Load multiple files
        for file in data/*.json; do #{$PROGRAM_NAME} "$file"; done

      Prerequisites:
        1. PostgreSQL database must exist
        2. Schema must be initialized:
           psql -d git_analytics -f schema/postgres_schema.sql
           psql -d git_analytics -f schema/postgres_views.sql
        3. pg gem must be installed:
           bundle install
    HELP
    exit(ARGV.include?('-h') || ARGV.include?('--help') ? 0 : 1)
  end

  json_file = ARGV[0]

  begin
    loader = DataLoader.new(json_file)
    loader.run
  rescue Interrupt
    puts "\n\nInterrupted by user"
    exit(1)
  rescue StandardError => e
    abort "Error: #{e.message}\n#{e.backtrace.join("\n")}"
  end
end
