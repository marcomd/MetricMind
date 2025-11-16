#!/usr/bin/env ruby
# frozen_string_literal: true

# Git Productivity Analytics - Unified Execution Script
# Usage: ./scripts/run.rb [REPO_NAME] [OPTIONS]

require 'bundler/setup'
require 'dotenv/load' unless ENV['RSPEC_RUNNING']
require 'json'
require 'optparse'
require 'fileutils'
require_relative '../lib/db_connection'

# Main orchestration script for git data extraction and loading
class RunScript
  # ANSI color codes
  RED = "\e[31m"
  GREEN = "\e[32m"
  YELLOW = "\e[33m"
  BLUE = "\e[34m"
  NC = "\e[0m" # No Color

  attr_reader :options, :stats

  def initialize(options = {})
    @options = options
    @stats = {
      success_count: 0,
      error_count: 0,
      total_commits: 0,
      repo_count: 0
    }
    @project_dir = File.expand_path('..', __dir__)
    @script_dir = File.join(@project_dir, 'scripts')
  end

  def run
    validate_options!
    load_configuration
    display_execution_plan
    process_repositories
    post_process if should_post_process?
    display_final_summary
    exit(stats[:error_count].zero? ? 0 : 1)
  rescue Interrupt
    puts "\n\n#{RED}[ERROR]#{NC} Interrupted by user"
    exit(1)
  end

  private

  def validate_options!
    if !options[:extract] && !options[:load]
      log_error('Cannot use both --skip-extraction and --skip-load (nothing to do!)')
      exit(1)
    end
  end

  def load_configuration
    # Load config file
    unless File.exist?(options[:config])
      log_error("Configuration file not found: #{options[:config]}")
      exit(1)
    end

    config = JSON.parse(File.read(options[:config]))
    @repositories = config['repositories'].select { |repo| repo['enabled'] }

    # Filter for single repository if specified
    if options[:repo_name]
      @repositories = @repositories.select { |repo| repo['name'] == options[:repo_name] }

      if @repositories.empty?
        log_error("Repository '#{options[:repo_name]}' not found or not enabled in config")
        log_info('Available repositories:')
        config['repositories'].each do |repo|
          puts "  - #{repo['name']}"
        end
        exit(1)
      end

      log_info("Processing single repository: #{options[:repo_name]}")
    end

    @stats[:repo_count] = @repositories.length

    # Set up output directory
    @output_dir = File.expand_path(options[:output_dir])
    FileUtils.mkdir_p(@output_dir)

    # Parse DATABASE_URL (already handled by DBConnection module)
    # This sets up environment variables for psql commands
    setup_database_env
  end

  def setup_database_env
    # DBConnection.connection_params already parses DATABASE_URL if present
    db_params = DBConnection.connection_params

    ENV['PGHOST'] = db_params[:host] if db_params[:host]
    ENV['PGPORT'] = db_params[:port].to_s if db_params[:port]
    ENV['PGDATABASE'] = db_params[:dbname] if db_params[:dbname]
    ENV['PGUSER'] = db_params[:user] if db_params[:user]
    ENV['PGPASSWORD'] = db_params[:password] if db_params[:password]
  end

  def display_execution_plan
    puts ''
    puts '=' * 65
    puts "#{BLUE}Git Productivity Analytics - Execution Plan#{NC}"
    puts '=' * 65
    log_info("Configuration: #{options[:config]}")
    log_info("Output directory: #{@output_dir}")
    log_info("Extraction period: #{options[:from_date]} to #{options[:to_date]}") if options[:extract]
    puts ''
    log_info('Workflow:')

    step = 1
    puts "  #{step}. Clean repository data (with confirmation)" if options[:clean]
    step += 1 if options[:clean]
    puts "  #{step}. Extract from git repositories" if options[:extract]
    step += 1 if options[:extract]
    puts "  #{step}. Load to database" if options[:load]
    puts ''

    log_info("Found #{@stats[:repo_count]} enabled repositories")
    puts ''
  end

  def process_repositories
    @repositories.each_with_index do |repo, index|
      process_repository(repo, index + 1)
      puts ''
    end
  end

  def process_repository(repo, repo_num)
    repo_name = repo['name']
    repo_path = File.expand_path(repo['path'])
    repo_desc = repo['description'] || 'No description'

    puts '=' * 65
    puts "#{BLUE}Repository #{repo_num}/#{@stats[:repo_count]}: #{repo_name}#{NC}"
    puts "Description: #{repo_desc}"
    puts "Path: #{repo_path}"
    puts '=' * 65
    puts ''

    # Step 1: Clean (if requested)
    if options[:clean]
      return unless clean_repository(repo_name)

      puts ''
    end

    # Validate repository path for extraction
    if options[:extract]
      unless validate_repository_path(repo_path)
        @stats[:error_count] += 1
        return
      end
    end

    # Generate output filename
    output_file = File.join(@output_dir, "#{repo_name}.json")

    # Step 2: Extract (if not skipped)
    if options[:extract]
      return unless extract_repository(repo_name, repo_path, output_file, repo['description'])

      puts ''
    elsif options[:load] && !File.exist?(output_file)
      log_error("JSON file not found: #{output_file}")
      log_error('Cannot load data without extraction (use without --skip-extraction first)')
      @stats[:error_count] += 1
      return
    end

    # Step 3: Load (if not skipped)
    if options[:load]
      load_repository(output_file)
    else
      # Count as success in extraction-only mode
      @stats[:success_count] += 1
    end
  end

  def clean_repository(repo_name)
    log_info("Step 1: Cleaning existing data for #{repo_name}")
    puts ''

    script_path = File.join(@script_dir, 'clean_repository.rb')
    success = system(script_path, repo_name)

    unless success
      log_error('Failed to clean repository data')
      @stats[:error_count] += 1
      return false
    end

    true
  end

  def validate_repository_path(repo_path)
    unless File.directory?(repo_path)
      log_error("Repository path does not exist: #{repo_path}")
      return false
    end

    unless File.directory?(File.join(repo_path, '.git'))
      log_error("Not a git repository: #{repo_path}")
      return false
    end

    true
  end

  def extract_repository(repo_name, repo_path, output_file, repo_description = nil)
    step_num = options[:clean] ? 2 : 1
    log_info("Step #{step_num}: Extracting git data...")

    script_path = File.join(@script_dir, 'git_extract_to_json.rb')
    args = [
      script_path,
      options[:from_date],
      options[:to_date],
      output_file,
      repo_name,
      repo_path
    ]
    args << repo_description if repo_description

    success = system(*args)

    unless success
      log_error("Extraction failed for #{repo_name}")
      @stats[:error_count] += 1
      return false
    end

    log_success('Extraction complete')

    # Count commits in JSON file
    if File.exist?(output_file)
      data = JSON.parse(File.read(output_file))
      commits = data['summary']['total_commits']
      log_info("Commits extracted: #{commits}")
    end

    true
  end

  def load_repository(output_file)
    step_num = calculate_load_step_number
    log_info("Step #{step_num}: Loading data to database...")

    script_path = File.join(@script_dir, 'load_json_to_db.rb')
    success = system(script_path, output_file)

    if success
      log_success('Data loaded successfully')

      # Count commits from JSON
      data = JSON.parse(File.read(output_file))
      commits = data['summary']['total_commits']
      @stats[:total_commits] += commits

      @stats[:success_count] += 1
    else
      log_error('Database load failed')
      @stats[:error_count] += 1
    end
  end

  def calculate_load_step_number
    return 3 if options[:clean] && options[:extract]
    return 2 if options[:clean] || options[:extract]

    1
  end

  def should_post_process?
    options[:load] && @stats[:success_count].positive?
  end

  def post_process
    puts '=' * 65
    puts "#{BLUE}POST-PROCESSING#{NC}"
    puts '=' * 65
    puts ''

    categorize_commits
    calculate_weights
    refresh_views

    puts ''
  end

  def categorize_commits
    log_info('Step 1: Categorizing commits...')

    script_path = File.join(@script_dir, 'categorize_commits.rb')
    args = []
    args += ['--repo', options[:repo_name]] if options[:repo_name]

    success = system(script_path, *args)

    if success
      log_success('Commits categorized')
    else
      log_warning('Categorization completed with warnings (this is normal if some commits couldn\'t be categorized)')
    end

    puts ''
  end

  def calculate_weights
    log_info('Step 2: Calculating commit weights (revert detection)...')

    script_path = File.join(@script_dir, 'calculate_commit_weights.rb')
    args = []
    args += ['--repo', options[:repo_name]] if options[:repo_name]

    success = system(script_path, *args)

    if success
      log_success('Commit weights calculated')
    else
      log_warning('Weight calculation completed with warnings')
    end

    puts ''
  end

  def refresh_views
    log_info('Step 3: Refreshing materialized views...')

    db_name = ENV['PGDATABASE'] || 'git_analytics'
    sql = 'SELECT refresh_all_mv(); SELECT refresh_category_mv();'

    success = system('psql', '-d', db_name, '-c', sql, out: File::NULL, err: File::NULL)

    if success
      log_success('Materialized views refreshed')
    else
      log_warning('Failed to refresh materialized views (they may not exist yet)')
    end

    puts ''
  end

  def display_final_summary
    puts '=' * 65
    puts "#{BLUE}FINAL SUMMARY#{NC}"
    puts '=' * 65
    puts "Repositories processed:  #{@stats[:repo_count]}"
    puts "#{GREEN}Successful:#{NC}              #{@stats[:success_count]}"
    puts "#{RED}Errors:#{NC}                  #{@stats[:error_count]}" if @stats[:error_count].positive?
    puts "Total commits loaded:    #{@stats[:total_commits]}" if options[:load]
    puts '=' * 65

    if @stats[:error_count].positive?
      log_warning("Completed with #{@stats[:error_count]} error(s)")
    else
      log_success('All repositories processed successfully!')
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
    clean: false,
    extract: true,
    load: true,
    repo_name: nil,
    config: File.expand_path('../config/repositories.json', __dir__),
    from_date: ENV['DEFAULT_FROM_DATE'] || '6 months ago',
    to_date: ENV['DEFAULT_TO_DATE'] || 'now',
    output_dir: ENV['OUTPUT_DIR'] || './data/exports'
  }

  parser = OptionParser.new do |opts|
    opts.banner = <<~BANNER
      Git Productivity Analytics - Unified Execution Script

      Usage:
        #{$PROGRAM_NAME} [REPO_NAME] [OPTIONS]

      Arguments:
        REPO_NAME           Optional - Process only this repository (default: all enabled)

      Options:
    BANNER

    opts.on('--clean', 'Clean repository data before processing (prompts for confirmation)') do
      options[:clean] = true
    end

    opts.on('--skip-extraction', 'Skip git extraction, only load from existing JSON files') do
      options[:extract] = false
    end

    opts.on('--skip-load', 'Skip database loading, only extract to JSON files') do
      options[:load] = false
    end

    opts.on('--from DATE', 'Start date for extraction (default: 6 months ago)') do |date|
      options[:from_date] = date
    end

    opts.on('--to DATE', 'End date for extraction (default: now)') do |date|
      options[:to_date] = date
    end

    opts.on('--config FILE', 'Configuration file (default: config/repositories.json)') do |file|
      options[:config] = File.expand_path(file)
    end

    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      puts <<~EXAMPLES

        Examples:
          # Extract and load all enabled repositories
          #{$PROGRAM_NAME}

          # Process single repository
          #{$PROGRAM_NAME} mater

          # Clean before processing (prompts for confirmation per repo)
          #{$PROGRAM_NAME} --clean

          # Clean and process single repository
          #{$PROGRAM_NAME} mater --clean

          # Only extract to JSON, don't load to database
          #{$PROGRAM_NAME} --skip-load

          # Only load from existing JSON files
          #{$PROGRAM_NAME} --skip-extraction

          # Custom date range
          #{$PROGRAM_NAME} --from "1 month ago" --to "now"

          # Clean single repo with custom dates
          #{$PROGRAM_NAME} mater --clean --from "2024-01-01" --to "2024-12-31"

        Workflow:
          Without flags:     Extract from git → Load to database
          --clean:           Clean → Extract → Load (sequential per repo)
          --skip-extraction: Load from existing JSON files only
          --skip-load:       Extract to JSON files only

      EXAMPLES
      exit(0)
    end
  end

  # Parse options and capture positional arguments
  begin
    parser.order!(ARGV)

    # First remaining argument is repository name
    options[:repo_name] = ARGV.shift unless ARGV.empty?

    # Check for unexpected arguments
    unless ARGV.empty?
      puts "#{RunScript::RED}[ERROR]#{RunScript::NC} Unexpected argument: #{ARGV.first}"
      puts 'Run with --help for usage information'
      exit(1)
    end
  rescue OptionParser::InvalidOption => e
    puts "#{RunScript::RED}[ERROR]#{RunScript::NC} #{e.message}"
    puts 'Run with --help for usage information'
    exit(1)
  end

  # Run the script
  script = RunScript.new(options)
  script.run
end
