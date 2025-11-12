#!/usr/bin/env ruby
# Categorize commits by extracting category from commit subject
#
# Usage:
#   ./scripts/categorize_commits.rb [--dry-run] [--repo REPO_NAME]
#
# This script:
# 1. Reads commits from the database
# 2. Extracts category from commit subject using multiple patterns
# 3. Updates the commits table with category data

require 'bundler/setup'
require 'dotenv/load' unless ENV['RSPEC_RUNNING']
require 'pg'
require 'optparse'
require_relative '../lib/db_connection'

# Categorizes commits by extracting business domain categories from commit subjects
# Supports patterns: pipe delimiter, square brackets, and uppercase first word
class CommitCategorizer
  # Initializes a new CommitCategorizer instance
  # @param options [Hash] configuration options
  # @option options [Boolean] :dry_run if true, no database changes will be made (default: false)
  # @option options [String] :repo optional repository name to filter commits
  def initialize(options = {})
    @dry_run = options[:dry_run] || false
    @repo_filter = options[:repo]
    @conn = connect_to_db
    @stats = {
      total: 0,
      categorized: 0,
      already_categorized: 0
    }
  end

  # Establishes a connection to the PostgreSQL database
  # @return [PG::Connection] the database connection
  # @raise [SystemExit] if connection fails
  def connect_to_db
    PG.connect(DBConnection.connection_params)
  rescue PG::Error => e
    abort "Error connecting to database: #{e.message}"
  end

  # Executes the full categorization workflow
  # Fetches commits, processes each one to extract category, and updates database
  # @return [void]
  def run
    puts "=" * 60
    puts "Commit Categorization Script"
    puts "=" * 60
    puts "Mode: #{@dry_run ? 'DRY RUN (no changes)' : 'LIVE (will update database)'}"
    puts "Repository filter: #{@repo_filter || 'All repositories'}"
    puts ""

    commits = fetch_commits
    puts "Found #{commits.length} commits to process"
    puts ""

    @conn.exec('BEGIN') unless @dry_run

    commits.each do |commit|
      process_commit(commit)
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

  # Fetches commits from the database, optionally filtered by repository
  # @return [Array<Hash>] array of commit records with id, hash, subject, category, and repository_name
  def fetch_commits
    query = <<~SQL
      SELECT
        c.id,
        c.hash,
        c.subject,
        c.category,
        r.name as repository_name
      FROM commits c
      JOIN repositories r ON c.repository_id = r.id
    SQL

    if @repo_filter
      query += " WHERE r.name = $1"
      @conn.exec_params(query, [@repo_filter]).to_a
    else
      @conn.exec(query).to_a
    end
  end

  # Processes a single commit to extract and update its category
  # Skips commits that are already categorized, updates statistics
  # @param commit [Hash] the commit record with id, hash, subject, and category fields
  # @return [void]
  def process_commit(commit)
    @stats[:total] += 1

    # Skip if already categorized
    if commit['category']
      @stats[:already_categorized] += 1
      return
    end

    category = extract_category(commit['subject'])

    # Only update if we found a category
    return unless category

    if @dry_run
      puts "[DRY RUN] Would update commit #{commit['hash'][0..7]}: category=#{category}"
    else
      update_commit(commit['id'], category)
      print '.'
    end

    @stats[:categorized] += 1
  end

  # Extracts the category from a commit subject using multiple pattern matching strategies
  # Supports: pipe delimiter (BILLING | Fix), square brackets ([BILLING] Fix), and uppercase first word (BILLING Fix)
  # Ignores common verbs like MERGE, FIX, ADD, UPDATE, REMOVE, DELETE
  # @param subject [String, nil] the commit subject line
  # @return [String, nil] the extracted category in uppercase, or nil if no category found
  def extract_category(subject)
    return nil if subject.nil? || subject.strip.empty?

    # Pattern 1: Pipe delimiter (e.g., "BILLING | Fix bug")
    if subject.include?(' | ')
      category = subject.split(' | ', 2).first.strip.upcase
      return category unless category.empty?
    end

    # Pattern 2: Square brackets (e.g., "[BILLING] Fix bug")
    if subject.match?(/^\[([^\]]+)\]/)
      match = subject.match(/^\[([^\]]+)\]/)
      return match[1].strip.upcase if match
    end

    # Pattern 3: First word if ALL UPPERCASE (e.g., "BILLING Fix bug")
    first_word = subject.split(/\s+/, 2).first
    if first_word && first_word == first_word.upcase && first_word.length >= 2
      # Ignore common all-caps words that aren't categories
      unless ['MERGE', 'FIX', 'ADD', 'UPDATE', 'REMOVE', 'DELETE'].include?(first_word)
        return first_word
      end
    end

    # No category found
    nil
  end

  # Updates a commit record with the extracted category
  # @param commit_id [Integer] the commit database ID
  # @param category [String] the category to set
  # @return [void]
  def update_commit(commit_id, category)
    query = "UPDATE commits SET category = $1 WHERE id = $2"
    @conn.exec_params(query, [category, commit_id])
  end

  # Prints a summary of categorization results
  # Displays total commits processed, newly categorized, and category coverage percentage
  # @return [void]
  def print_summary
    puts "\n"
    puts "=" * 60
    puts "SUMMARY"
    puts "=" * 60
    puts "Total commits processed:      #{@stats[:total]}"
    puts "Already categorized:          #{@stats[:already_categorized]}"
    puts "Newly categorized:            #{@stats[:categorized]}"
    puts ""

    if @stats[:total] > 0
      total_categorized = @stats[:already_categorized] + @stats[:categorized]
      category_pct = (total_categorized.to_f / @stats[:total] * 100).round(1)
      puts "Total category coverage:      #{category_pct}%"
    end

    puts "=" * 60
  end
end

# Parse command line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: categorize_commits.rb [options]"

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

categorizer = CommitCategorizer.new(options)
categorizer.run
