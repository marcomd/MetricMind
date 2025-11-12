#!/usr/bin/env ruby
# frozen_string_literal: true

# Calculate commit weights based on revert patterns
#
# Usage:
#   ./scripts/calculate_commit_weights.rb [--dry-run] [--repo REPO_NAME]
#
# This script:
# 1. Reads commits from the database
# 2. Detects revert patterns in commit subjects
# 3. Extracts PR/MR numbers to link reverts to original commits
# 4. Updates weights: reverted commits = 0, valid commits = 100

require 'bundler/setup'
require 'dotenv/load' unless ENV['RSPEC_RUNNING']
require 'pg'
require 'optparse'
require_relative '../lib/db_connection'

# Calculates commit weights based on revert and unrevert patterns
# Sets weight=0 for reverted commits and weight=100 for valid/unreverted commits
class CommitWeightCalculator
  # Initializes a new CommitWeightCalculator instance
  # @param options [Hash] configuration options
  # @option options [Boolean] :dry_run if true, no database changes will be made (default: false)
  # @option options [String] :repo optional repository name to filter commits
  def initialize(options = {})
    @dry_run = options[:dry_run] || false
    @repo_filter = options[:repo]
    @conn = connect_to_db
    @stats = {
      total: 0,
      reverts_found: 0,
      unreverts_found: 0,
      commits_zeroed: 0,
      commits_restored: 0
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

  # Executes the full weight calculation workflow
  # Processes reverts in first pass (setting weight to 0) and unreverts in second pass (restoring to 100)
  # @return [void]
  def run
    puts "=" * 60
    puts "Commit Weight Calculation Script"
    puts "=" * 60
    puts "Mode: #{@dry_run ? 'DRY RUN (no changes)' : 'LIVE (will update database)'}"
    puts "Repository filter: #{@repo_filter || 'All repositories'}"
    puts ""

    commits = fetch_commits
    puts "Found #{commits.length} commits to process"
    puts ""

    @conn.exec('BEGIN') unless @dry_run

    # First pass: process reverts (set weight to 0)
    commits.each do |commit|
      process_revert(commit, commits)
    end

    # Second pass: process unreverts (restore weight to 100)
    commits.each do |commit|
      process_unrevert(commit, commits)
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
  # @return [Array<Hash>] array of commit records with id, hash, subject, weight, repository_id, and repository_name
  def fetch_commits
    query = <<~SQL
      SELECT
        c.id,
        c.hash,
        c.subject,
        c.weight,
        c.repository_id,
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

  # Processes a commit to detect if it's a revert and updates weights accordingly
  # Extracts PR/MR numbers and sets weight=0 for both the revert and the original commits
  # @param commit [Hash] the commit record to process
  # @param all_commits [Array<Hash>] all commits for finding related commits by PR/MR number
  # @return [void]
  def process_revert(commit, all_commits)
    @stats[:total] += 1

    # Check if this is a revert commit (case-insensitive)
    return unless commit['subject'] =~ /\bRevert\b/i
    # Exclude "Unrevert" commits
    return if commit['subject'] =~ /\bUnrevert\b/i

    @stats[:reverts_found] += 1

    # Extract PR/MR numbers from the revert commit subject
    pr_numbers = extract_pr_numbers(commit['subject'])

    if pr_numbers.empty?
      puts "[WARNING] Revert commit found but no PR/MR number: #{commit['hash'][0..7]} - #{commit['subject']}"
      return
    end

    # Find original commits with matching PR/MR numbers in the same repository
    pr_numbers.each do |pr_number|
      original_commits = find_commits_by_pr_number(
        pr_number,
        commit['repository_id'],
        all_commits,
        exclude_hash: commit['hash']
      )

      if original_commits.empty?
        puts "[WARNING] No original commit found for PR #{pr_number} in revert: #{commit['hash'][0..7]}"
        next
      end

      # Set weight to 0 for both revert and original commits
      set_weight(commit, 0, "Revert commit")
      original_commits.each do |original|
        set_weight(original, 0, "Reverted by #{commit['hash'][0..7]}")
      end
    end
  end

  # Processes a commit to detect if it's an unrevert and restores weights accordingly
  # Extracts PR/MR numbers and sets weight=100 for the original commits (if they're not reverts themselves)
  # @param commit [Hash] the commit record to process
  # @param all_commits [Array<Hash>] all commits for finding related commits by PR/MR number
  # @return [void]
  def process_unrevert(commit, all_commits)
    # Check if this is an unrevert commit (case-insensitive)
    return unless commit['subject'] =~ /\bUnrevert\b/i

    @stats[:unreverts_found] += 1

    # Extract PR/MR numbers from the unrevert commit subject
    pr_numbers = extract_pr_numbers(commit['subject'])

    if pr_numbers.empty?
      puts "[WARNING] Unrevert commit found but no PR/MR number: #{commit['hash'][0..7]} - #{commit['subject']}"
      return
    end

    # Find original commits with matching PR/MR numbers in the same repository
    pr_numbers.each do |pr_number|
      original_commits = find_commits_by_pr_number(
        pr_number,
        commit['repository_id'],
        all_commits,
        exclude_hash: commit['hash']
      )

      if original_commits.empty?
        puts "[WARNING] No original commit found for PR #{pr_number} in unrevert: #{commit['hash'][0..7]}"
        next
      end

      # Restore weight to 100 for original commits
      original_commits.each do |original|
        # Only restore if it's not a revert itself
        next if original['subject'] =~ /\bRevert\b/i && original['subject'] !~ /\bUnrevert\b/i

        set_weight(original, 100, "Unreverted by #{commit['hash'][0..7]}")
      end
    end
  end

  # Extracts PR/MR numbers from a commit subject
  # Supports GitLab style (!12345) and GitHub style (#12345)
  # @param subject [String] the commit subject line
  # @return [Array<String>] array of PR/MR numbers (e.g., ["!12345", "#678"])
  def extract_pr_numbers(subject)
    # Match patterns like (!12345) or (#12345)
    numbers = []

    # GitLab style: (!12345)
    subject.scan(/\(!(\d+)\)/) do |match|
      numbers << "!#{match[0]}"
    end

    # GitHub style: (#12345)
    subject.scan(/\(#(\d+)\)/) do |match|
      numbers << "##{match[0]}"
    end

    numbers.uniq
  end

  # Finds commits in the same repository that contain the specified PR/MR number
  # @param pr_number [String] the PR/MR number to search for (e.g., "!12345")
  # @param repository_id [Integer, String] the repository ID to filter by
  # @param all_commits [Array<Hash>] all commits to search through
  # @param exclude_hash [String, nil] optional commit hash to exclude from results
  # @return [Array<Hash>] array of matching commit records
  def find_commits_by_pr_number(pr_number, repository_id, all_commits, exclude_hash: nil)
    all_commits.select do |c|
      c['repository_id'].to_i == repository_id.to_i &&
        c['hash'] != exclude_hash &&
        c['subject'].include?(pr_number)
    end
  end

  # Sets the weight for a commit and updates statistics
  # Skips update if the commit is already at the target weight
  # @param commit [Hash] the commit record to update
  # @param new_weight [Integer] the new weight value (0 or 100)
  # @param reason [String] the reason for the weight change (for logging)
  # @return [void]
  def set_weight(commit, new_weight, reason)
    current_weight = commit['weight'].to_i

    # Skip if already at the target weight
    return if current_weight == new_weight

    if @dry_run
      puts "[DRY RUN] Would update commit #{commit['hash'][0..7]}: weight #{current_weight} → #{new_weight} (#{reason})"
    else
      update_commit_weight(commit['id'], new_weight)
      print '.'
    end

    if new_weight.zero?
      @stats[:commits_zeroed] += 1
    elsif new_weight == 100
      @stats[:commits_restored] += 1
    end
  end

  # Updates a commit's weight in the database
  # @param commit_id [Integer] the commit database ID
  # @param weight [Integer] the new weight value
  # @return [void]
  def update_commit_weight(commit_id, weight)
    query = "UPDATE commits SET weight = $1 WHERE id = $2"
    @conn.exec_params(query, [weight, commit_id])
  end

  # Prints a summary of weight calculation results
  # Displays total commits, reverts found, unreverts found, and weight changes
  # @return [void]
  def print_summary
    puts "\n"
    puts "=" * 60
    puts "SUMMARY"
    puts "=" * 60
    puts "Total commits processed:      #{@stats[:total]}"
    puts "Revert commits found:         #{@stats[:reverts_found]}"
    puts "Unrevert commits found:       #{@stats[:unreverts_found]}"
    puts "Commits set to weight=0:      #{@stats[:commits_zeroed]}"
    puts "Commits restored to weight=100: #{@stats[:commits_restored]}"
    puts "=" * 60
  end
end

# Parse command line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: calculate_commit_weights.rb [options]"

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

calculator = CommitWeightCalculator.new(options)
calculator.run
