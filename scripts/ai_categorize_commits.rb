#!/usr/bin/env ruby
# frozen_string_literal: true

# AI-powered commit categorization script
# Uses LLM (Gemini or Ollama) to categorize commits that weren't categorized by pattern matching
# Leverages file paths from JSON exports for better accuracy

require 'bundler/setup'
require 'dotenv/load' unless ENV['RSPEC_RUNNING']
require 'json'
require 'optparse'
require 'pg'
require 'date'
require 'time'
require 'open3'
require_relative '../lib/llm/categorizer'
require_relative '../lib/llm/client_factory'
require_relative '../lib/db_connection'

# AI Categorization Script
class AICategorizeScript
  # ANSI color codes
  RED = "\e[31m"
  GREEN = "\e[32m"
  YELLOW = "\e[33m"
  BLUE = "\e[34m"
  NC = "\e[0m" # No Color

  attr_reader :options

  def initialize(options = {})
    @options = options
    @project_dir = File.expand_path('..', __dir__)
    @output_dir = File.join(@project_dir, 'data', 'exports')

    # Parse and validate date range if provided
    @from_date = parse_date(options[:from_date]) if options[:from_date]
    @to_date = parse_date(options[:to_date]) if options[:to_date]
  end

  def run
    validate_ai_configuration!
    display_banner

    conn = PG.connect(DBConnection.connection_params)
    categorizer = LLM::Categorizer.new(conn: conn)

    begin
      repositories = fetch_repositories(conn)
      log_info("Found #{repositories.size} repositories to process")
      puts ''

      repositories.each do |repo|
        process_repository(repo, conn, categorizer)
      end

      display_summary(categorizer.stats)
      exit(0)
    rescue StandardError => e
      log_error("Fatal error: #{e.message}")
      log_error(e.backtrace.first(5).join("\n")) if options[:debug]
      exit(1)
    ensure
      categorizer&.close
      conn&.close unless conn&.finished?
    end
  end

  private

  def validate_ai_configuration!
    unless LLM::ClientFactory.ai_enabled?
      log_error('AI categorization is not enabled')
      log_error('Please set AI_PROVIDER environment variable (gemini or ollama)')
      exit(1)
    end

    validation = LLM::ClientFactory.validate_configuration
    return if validation[:valid]

    log_error('AI configuration is invalid:')
    validation[:errors].each { |error| log_error("  - #{error}") }
    exit(1)
  end

  def display_banner
    puts ''
    puts '=' * 70
    puts "#{BLUE}AI-Powered Commit Categorization#{NC}"
    puts '=' * 70
    puts ''
    log_info("Provider: #{ENV.fetch('AI_PROVIDER', 'ollama').upcase}")
    log_info("Mode: #{options[:dry_run] ? 'DRY RUN (no changes)' : 'LIVE (will update database)'}")
    log_info("Force recategorize: #{options[:force] ? 'YES' : 'NO'}")
    log_info("Repository filter: #{options[:repo_name] || 'ALL'}")
    log_info("Date range: #{format_date_range}") if @from_date || @to_date
    puts ''
  end

  def fetch_repositories(conn)
    if options[:repo_name]
      result = conn.exec_params(
        'SELECT id, name FROM repositories WHERE name = $1',
        [options[:repo_name]]
      )

      if result.ntuples.zero?
        log_error("Repository '#{options[:repo_name]}' not found")
        exit(1)
      end

      result.to_a
    else
      conn.exec('SELECT id, name FROM repositories ORDER BY name').to_a
    end
  end

  def process_repository(repo, conn, categorizer)
    repo_id = repo['id']
    repo_name = repo['name']

    puts '=' * 70
    log_info("Processing repository: #{repo_name}")
    puts '=' * 70

    # Load JSON export
    json_file = File.join(@output_dir, "#{repo_name}.json")
    unless File.exist?(json_file)
      log_warning("JSON export not found: #{json_file}")
      log_warning('Skipping repository (run extraction first)')
      puts ''
      return
    end

    json_data = JSON.parse(File.read(json_file))
    log_info("Loaded #{json_data['commits']&.size || 0} commits from JSON export")

    # Fetch uncategorized commits
    commits = fetch_uncategorized_commits(conn, repo_id)

    if commits.empty?
      log_success('All commits are already categorized!')
      puts ''
      return
    end

    log_info("Found #{commits.size} uncategorized commits")
    log_info("Starting AI categorization...")
    puts ''

    # Process commits
    if options[:dry_run]
      dry_run_categorization(commits, json_data, categorizer)
    else
      categorizer.categorize_commits(commits, json_data, batch_size: options[:batch_size])
    end

    log_success("Repository complete: #{categorizer.stats[:categorized]} categorized, #{categorizer.stats[:errors]} errors")
    puts ''
  end

  def fetch_uncategorized_commits(conn, repo_id)
    # Build base query
    conditions = ['repository_id = $1']
    params = [repo_id]
    param_index = 2

    # Add category filter unless forcing recategorization
    unless options[:force]
      conditions << 'category IS NULL'
    end

    # Add date range filters
    if @from_date
      conditions << "commit_date >= $#{param_index}"
      params << @from_date
      param_index += 1
    end

    if @to_date
      conditions << "commit_date <= $#{param_index}"
      params << @to_date
      param_index += 1
    end

    # Build complete query
    query = "SELECT id, repository_id, hash, subject, commit_date FROM commits WHERE #{conditions.join(' AND ')} ORDER BY commit_date DESC"
    query += " LIMIT #{options[:limit]}" if options[:limit]

    conn.exec_params(query, params).to_a
  end

  def dry_run_categorization(commits, json_data, categorizer)
    log_info('[DRY RUN] Simulating categorization...')

    client = categorizer.client
    existing_categories = categorizer.fetch_existing_categories

    commits.first(5).each do |commit|
      json_commit = categorizer.find_commit_in_json(json_data, commit['hash'])
      files = json_commit&.dig('files')&.map { |f| f['filename']&.strip } || []

      commit_data = {
        hash: commit['hash'],
        subject: commit['subject'],
        files: files
      }

      begin
        result = client.categorize(commit_data, existing_categories)
        puts "  #{commit['hash'][0..7]}: #{result[:category]} (#{result[:confidence]}%)"
        puts "    Subject: #{commit['subject']}"
        puts "    Reason: #{result[:reason]}"
        puts ''
      rescue LLM::BaseClient::Error => e
        log_warning("  Failed: #{e.message}")
      end
    end

    log_info("[DRY RUN] Would process #{commits.size} commits")
  end

  def display_summary(stats)
    puts '=' * 70
    puts "#{BLUE}SUMMARY#{NC}"
    puts '=' * 70
    puts "Commits processed:       #{stats[:processed]}"
    puts "#{GREEN}Successfully categorized:#{NC} #{stats[:categorized]}"
    puts "#{YELLOW}New categories created:#{NC}   #{stats[:new_categories]}"
    puts "#{RED}Errors:#{NC}                  #{stats[:errors]}" if stats[:errors].positive?
    puts '=' * 70

    if stats[:errors].positive?
      log_warning("Completed with #{stats[:errors]} error(s)")
    else
      log_success('All commits categorized successfully!')
    end
  end

  # Parse date string to PostgreSQL-compatible format
  # Supports both ISO format (2024-01-01) and git-style (6 months ago, 1 year ago)
  # @param date_str [String] date string to parse
  # @return [String] PostgreSQL-compatible timestamp string
  # @raise [SystemExit] if date format is invalid
  def parse_date(date_str)
    return nil if date_str.nil? || date_str.strip.empty?

    # Try ISO format first (YYYY-MM-DD)
    begin
      parsed = Date.parse(date_str)
      return parsed.to_time.strftime('%Y-%m-%d %H:%M:%S')
    rescue ArgumentError
      # Not a standard date format, try git-style parsing
    end

    # Use git to parse git-style dates (e.g., "6 months ago", "1 year ago", "now")
    # This leverages git's date parsing which is very flexible
    git_cmd = ['git', 'log', "--since=#{date_str}", '--max-count=1', '--pretty=format:%ai']
    output, status = Open3.capture2(*git_cmd, chdir: @project_dir, err: '/dev/null')

    if status.success? && !output.strip.empty?
      # Git successfully parsed the date and returned a timestamp
      # Convert to PostgreSQL format
      begin
        Time.parse(output.strip).strftime('%Y-%m-%d %H:%M:%S')
      rescue ArgumentError => e
        log_error("Failed to parse date '#{date_str}': #{e.message}")
        exit(1)
      end
    else
      # Check if "now" was specified
      if date_str.downcase == 'now'
        return Time.now.strftime('%Y-%m-%d %H:%M:%S')
      end

      log_error("Invalid date format: '#{date_str}'")
      log_error("Supported formats:")
      log_error("  - ISO: 2024-01-01, 2024-12-31")
      log_error("  - Git-style: '6 months ago', '1 year ago', 'now'")
      exit(1)
    end
  end

  # Format date range for display
  # @return [String] formatted date range string
  def format_date_range
    if @from_date && @to_date
      "#{options[:from_date]} to #{options[:to_date]}"
    elsif @from_date
      "from #{options[:from_date]}"
    elsif @to_date
      "until #{options[:to_date]}"
    else
      'all time'
    end
  end

  # Logging helpers
  def log_info(message)
    puts "#{BLUE}[INFO]#{NC} #{message}"
  end

  def log_success(message)
    puts "#{GREEN}[SUCCESS]#{NC} #{message}"
  end

  def log_warning(message)
    puts "#{YELLOW}[WARNING]#{NC} #{message}"
  end

  def log_error(message)
    puts "#{RED}[ERROR]#{NC} #{message}"
  end
end

# Parse command-line options
if __FILE__ == $PROGRAM_NAME
  options = {
    dry_run: false,
    force: false,
    repo_name: nil,
    limit: nil,
    batch_size: 50,
    debug: false,
    from_date: nil,
    to_date: nil
  }

  parser = OptionParser.new do |opts|
    opts.banner = <<~BANNER
      AI-Powered Commit Categorization

      Usage:
        #{$PROGRAM_NAME} [OPTIONS]

      Description:
        Uses LLM (Gemini or Ollama) to categorize commits that weren't
        categorized by pattern matching. Leverages file paths from JSON
        exports for improved accuracy.

      Options:
    BANNER

    opts.on('--dry-run', 'Preview categorization without updating database') do
      options[:dry_run] = true
    end

    opts.on('--force', 'Force recategorization of all commits (even already categorized)') do
      options[:force] = true
    end

    opts.on('--repo REPO_NAME', 'Process only this repository') do |repo|
      options[:repo_name] = repo
    end

    opts.on('--from DATE', 'Only categorize commits from this date onwards (e.g., "2024-01-01" or "6 months ago")') do |date|
      options[:from_date] = date
    end

    opts.on('--to DATE', 'Only categorize commits up to this date (e.g., "2024-12-31" or "now")') do |date|
      options[:to_date] = date
    end

    opts.on('--limit N', Integer, 'Limit number of commits to process') do |limit|
      options[:limit] = limit
    end

    opts.on('--batch-size N', Integer, 'Number of commits per transaction (default: 50)') do |batch|
      options[:batch_size] = batch
    end

    opts.on('--debug', 'Enable debug output') do
      options[:debug] = true
      ENV['AI_DEBUG'] = 'true'
    end

    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      puts <<~EXAMPLES

        Examples:
          # Categorize all uncategorized commits
          #{$PROGRAM_NAME}

          # Preview categorization (dry run)
          #{$PROGRAM_NAME} --dry-run

          # Categorize single repository
          #{$PROGRAM_NAME} --repo mater

          # Force recategorization of all commits
          #{$PROGRAM_NAME} --force

          # Process only 100 commits
          #{$PROGRAM_NAME} --limit 100

          # Categorize commits from last 3 months (git-style)
          #{$PROGRAM_NAME} --from "3 months ago" --to "now"

          # Categorize commits in specific date range (ISO format)
          #{$PROGRAM_NAME} --from "2024-01-01" --to "2024-12-31"

          # Categorize recent commits from single repository
          #{$PROGRAM_NAME} --repo mater --from "6 months ago"

          # Debug mode with verbose output
          #{$PROGRAM_NAME} --debug

        Environment Variables:
          AI_PROVIDER          gemini or ollama (required)
          AI_TIMEOUT           Timeout in seconds (default: 30)
          AI_RETRIES           Number of retries (default: 3)

          # For Gemini:
          GEMINI_API_KEY       Google API key (required)
          GEMINI_MODEL         Model name (default: gemini-2.0-flash-exp)
          GEMINI_TEMPERATURE   Temperature 0-2 (default: 0.1)

          # For Ollama:
          OLLAMA_URL           Ollama URL (default: http://localhost:11434)
          OLLAMA_MODEL         Model name (default: llama2)
          OLLAMA_TEMPERATURE   Temperature 0-2 (default: 0.1)

      EXAMPLES
      exit(0)
    end
  end

  parser.parse!(ARGV)

  # Run the script
  script = AICategorizeScript.new(options)
  script.run
end
