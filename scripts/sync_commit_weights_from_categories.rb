#!/usr/bin/env ruby
# frozen_string_literal: true

# Synchronize commit weights from category weights
#
# Usage:
#   ./scripts/sync_commit_weights_from_categories.rb [--dry-run] [--repo REPO_NAME]
#
# This script:
# 1. Fetches all categories with their weights from the database
# 2. For each category, updates commit weights to match the category weight
# 3. Only updates commits where weight > 0 (preserves reverted commits at weight=0)
# 4. Provides statistics on weight synchronization

require 'bundler/setup'
require 'dotenv/load' unless ENV['RSPEC_RUNNING']
require 'pg'
require 'optparse'
require_relative '../lib/db_connection'

# Synchronizes commit weights based on their category's weight
# Updates commits.weight to match categories.weight, but only for non-reverted commits (weight > 0)
class CommitWeightSynchronizer
  # Initializes a new CommitWeightSynchronizer instance
  # @param options [Hash] configuration options
  # @option options [Boolean] :dry_run if true, no database changes will be made (default: false)
  # @option options [String] :repo optional repository name to filter commits
  def initialize(options = {})
    @dry_run = options[:dry_run] || false
    @repo_filter = options[:repo]
    @conn = connect_to_db
    @stats = {
      total_commits: 0,
      updated_commits: 0,
      skipped_reverted: 0,
      categories_processed: 0
    }
    @category_stats = {}
  end

  # Establishes a connection to the PostgreSQL database
  # @return [PG::Connection] the database connection
  # @raise [SystemExit] if connection fails
  def connect_to_db
    PG.connect(DBConnection.connection_params)
  rescue PG::Error => e
    abort "Error connecting to database: #{e.message}"
  end

  # Executes the full weight synchronization workflow
  # Fetches categories, updates commit weights to match category weights
  # @return [void]
  def run
    puts "=" * 70
    puts "Commit Weight Synchronization Script"
    puts "=" * 70
    puts "Mode: #{@dry_run ? 'DRY RUN (no changes)' : 'LIVE (will update database)'}"
    puts "Repository filter: #{@repo_filter || 'All repositories'}"
    puts ""

    categories = fetch_categories

    if categories.empty?
      puts "No categories found in database."
      puts "Run the extraction and categorization process first."
      return
    end

    puts "Found #{categories.length} categories to process"
    puts ""

    @conn.exec('BEGIN') unless @dry_run

    categories.each do |category|
      process_category(category)
    end

    if @dry_run
      puts "\n✓ Dry run complete - no changes made"
    else
      @conn.exec('COMMIT')
      puts "\n✓ Changes committed to database"
    end

    print_summary
  ensure
    @conn.close if @conn
  end

  private

  # Fetches all categories with their weights from the database
  # @return [Array<Hash>] array of category records with id, name, and weight
  def fetch_categories
    query = <<~SQL
      SELECT id, name, weight
      FROM categories
      ORDER BY name
    SQL

    @conn.exec(query).to_a
  end

  # Processes a single category by synchronizing commit weights
  # Updates all commits with this category (except reverted ones) to match the category's weight
  # @param category [Hash] the category record with id, name, and weight fields
  # @return [void]
  def process_category(category)
    category_name = category['name']
    category_weight = category['weight'].to_i

    @stats[:categories_processed] += 1

    # Count commits that will be affected
    count_query = build_count_query
    params = [@repo_filter, category_name].compact
    result = @conn.exec_params(count_query, params)

    total_with_category = result[0]['total'].to_i
    non_reverted = result[0]['non_reverted'].to_i
    reverted = result[0]['reverted'].to_i

    @stats[:total_commits] += total_with_category
    @stats[:skipped_reverted] += reverted

    # Skip if no commits to update
    if non_reverted.zero?
      if ENV['DEBUG'] == 'true'
        puts "[DEBUG] Category #{category_name}: No commits to update"
      end
      return
    end

    # Initialize category stats
    @category_stats[category_name] = {
      weight: category_weight,
      commits: non_reverted,
      reverted_skipped: reverted
    }

    if @dry_run
      puts "[DRY RUN] Would update #{non_reverted} commits with category=#{category_name} to weight=#{category_weight}"
      puts "           (Skipping #{reverted} reverted commits)" if reverted > 0
    else
      update_commits_for_category(category_name, category_weight)
      @stats[:updated_commits] += non_reverted
      print '.'
    end
  end

  # Builds the SQL query to count commits for a category
  # @return [String] the SQL query
  def build_count_query
    if @repo_filter
      # With repository filter: JOIN with repositories table
      <<~SQL
        SELECT
          COUNT(*) as total,
          COUNT(*) FILTER (WHERE c.weight > 0) as non_reverted,
          COUNT(*) FILTER (WHERE c.weight = 0) as reverted
        FROM commits c
        JOIN repositories r ON c.repository_id = r.id
        WHERE r.name = $1
          AND c.category = $2
      SQL
    else
      # Without repository filter: Query commits directly
      <<~SQL
        SELECT
          COUNT(*) as total,
          COUNT(*) FILTER (WHERE c.weight > 0) as non_reverted,
          COUNT(*) FILTER (WHERE c.weight = 0) as reverted
        FROM commits c
        WHERE c.category = $1
      SQL
    end
  end

  # Updates commits for a specific category to match the category's weight
  # Only updates commits where weight > 0 (preserves reverted commits)
  # @param category_name [String] the category name
  # @param new_weight [Integer] the new weight value from the category
  # @return [void]
  def update_commits_for_category(category_name, new_weight)
    update_query = build_update_query
    params = [@repo_filter, new_weight, category_name].compact

    @conn.exec_params(update_query, params)
  rescue PG::Error => e
    warn "[ERROR] Failed to update commits for category #{category_name}: #{e.message}"
  end

  # Builds the SQL query to update commit weights
  # @return [String] the SQL query
  def build_update_query
    if @repo_filter
      # With repository filter: JOIN with repositories table
      <<~SQL
        UPDATE commits c
        SET weight = $2
        FROM repositories r
        WHERE c.repository_id = r.id
          AND r.name = $1
          AND c.category = $3
          AND c.weight > 0
      SQL
    else
      # Without repository filter: Direct update, no JOIN needed
      <<~SQL
        UPDATE commits c
        SET weight = $1
        WHERE c.category = $2
          AND c.weight > 0
      SQL
    end
  end

  # Prints a summary of weight synchronization results
  # Displays total commits, updated commits, and per-category breakdown
  # @return [void]
  def print_summary
    puts "\n"
    puts "=" * 70
    puts "SUMMARY"
    puts "=" * 70
    puts "Categories processed:         #{@stats[:categories_processed]}"
    puts "Total commits examined:       #{@stats[:total_commits]}"
    puts "Commits updated:              #{@stats[:updated_commits]}"
    puts "Reverted commits (skipped):   #{@stats[:skipped_reverted]}" if @stats[:skipped_reverted] > 0
    puts ""

    unless @category_stats.empty?
      puts "Per-Category Breakdown:"
      puts "-" * 70

      # Sort by number of commits (descending)
      sorted_categories = @category_stats.sort_by { |_, stats| -stats[:commits] }

      sorted_categories.each do |category_name, stats|
        reverted_info = stats[:reverted_skipped] > 0 ? " (#{stats[:reverted_skipped]} reverted skipped)" : ""
        puts sprintf("  %-30s weight=%-3d  %5d commits%s",
                    category_name,
                    stats[:weight],
                    stats[:commits],
                    reverted_info)
      end
    end

    puts "=" * 70
  end
end

# Only run if this file is executed directly (not when required by tests)
if __FILE__ == $PROGRAM_NAME
  # Parse command line options
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: sync_commit_weights_from_categories.rb [options]"

    opts.on("--dry-run", "Show what would be done without making changes") do
      options[:dry_run] = true
    end

    opts.on("--repo REPO_NAME", "Only process commits from specific repository") do |repo|
      options[:repo] = repo
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!

  synchronizer = CommitWeightSynchronizer.new(options)
  synchronizer.run
end
