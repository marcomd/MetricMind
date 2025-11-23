#!/usr/bin/env ruby
# frozen_string_literal: true

# Complete setup script for Git Productivity Analytics
# Usage: ./scripts/setup.rb [OPTIONS]

require 'bundler/setup' rescue nil
require 'dotenv/load' rescue nil
require 'optparse'
require 'fileutils'
require 'shellwords'
require 'uri'
require 'sequel'
require_relative '../lib/sequel_connection'

# Main setup script for Git Productivity Analytics
class SetupScript
  # ANSI color codes
  GREEN = "\e[32m"
  BLUE = "\e[34m"
  YELLOW = "\e[33m"
  RED = "\e[31m"
  NC = "\e[0m" # No Color

  attr_reader :options, :db_info

  def initialize(options = {})
    @options = options
    @database_only = options[:database_only]
    @current_step = 0
    @total_steps = @database_only ? 3 : 6
    @project_dir = File.expand_path('..', __dir__)
    @schema_dir = File.join(@project_dir, 'schema')
    @migrations_dir = File.join(@schema_dir, 'migrations')
    @db_info = {}
  end

  def run
    print_header
    check_prerequisites
    install_dependencies unless @database_only
    setup_environment unless @database_only
    load_environment
    setup_databases
    initialize_schemas
    create_directories unless @database_only
    print_final_instructions
  rescue Interrupt
    puts "\n\n#{RED}✗ Setup interrupted by user#{NC}"
    exit(1)
  rescue StandardError => e
    puts "\n#{RED}✗ Setup failed: #{e.message}#{NC}"
    exit(1)
  end

  private

  def print_header
    puts "#{BLUE}╔════════════════════════════════════════════╗#{NC}"
    puts "#{BLUE}║  Git Productivity Analytics Setup         ║#{NC}"
    puts "#{BLUE}╚════════════════════════════════════════════╝#{NC}"
    puts ''

    if @database_only
      puts "#{YELLOW}Running in database-only mode#{NC}"
      puts ''
    end
  end

  def step_label
    @current_step += 1
    "[#{@current_step}/#{@total_steps}]"
  end

  def check_prerequisites
    if @database_only
      puts "#{BLUE}#{step_label} Checking PostgreSQL client...#{NC}"
      check_psql
    else
      puts "#{BLUE}#{step_label} Checking prerequisites...#{NC}"
      check_ruby
      check_psql
      check_jq
    end
  end

  def check_ruby
    unless command_exists?('ruby')
      puts "#{RED}✗ Ruby is not installed#{NC}"
      puts '  Please install Ruby >= 3.3'
      exit(1)
    end

    version = `ruby --version`.split[1]
    puts "#{GREEN}✓ Ruby #{version}#{NC}"
  end

  def check_psql
    unless command_exists?('psql')
      puts "#{RED}✗ psql client is not installed#{NC}"
      puts '  Please install PostgreSQL client >= 12'
      exit(1)
    end

    version = `psql --version`.split[2]
    puts "#{GREEN}✓ psql client #{version}#{NC}"
  end

  def check_jq
    if command_exists?('jq')
      version = `jq --version`.strip
      puts "#{GREEN}✓ #{version}#{NC}"
    else
      puts "#{YELLOW}⚠ jq is not installed (no longer required with Ruby scripts)#{NC}"
      puts '  Note: jq was needed for bash scripts but is optional with Ruby'
    end
  end

  def install_dependencies
    puts ''
    puts "#{BLUE}#{step_label} Installing Ruby dependencies...#{NC}"

    gemfile_path = File.join(@project_dir, 'Gemfile')
    unless File.exist?(gemfile_path)
      puts "#{YELLOW}⚠ No Gemfile found, skipping#{NC}"
      return
    end

    # Check for bundler
    unless command_exists?('bundle')
      puts "#{YELLOW}⚠ Bundler not found, installing...#{NC}"
      system('gem install bundler') || raise('Failed to install bundler')
    end

    # Run bundle install
    Dir.chdir(@project_dir) do
      system('bundle install') || raise('Failed to install dependencies')
    end

    puts "#{GREEN}✓ Dependencies installed#{NC}"
  end

  def setup_environment
    puts ''
    puts "#{BLUE}#{step_label} Setting up environment configuration...#{NC}"

    env_file = File.join(@project_dir, '.env')
    env_example = File.join(@project_dir, '.env.example')

    if File.exist?(env_file)
      puts "#{YELLOW}⚠ .env already exists, skipping#{NC}"
    else
      FileUtils.cp(env_example, env_file)
      puts "#{GREEN}✓ Created .env file#{NC}"
      puts "#{YELLOW}  Please edit .env with your database credentials#{NC}"
    end
  end

  def load_environment
    # Load .env file if it exists
    env_file = File.join(@project_dir, '.env')
    if File.exist?(env_file)
      File.readlines(env_file).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')

        key, value = line.split('=', 2)
        next unless key && value

        # Remove quotes if present
        value = value.gsub(/^['"]|['"]$/, '')
        ENV[key] = value
      end
    end

    # Parse DATABASE_URL if present
    parse_database_url

    # Set database info
    @db_info = {
      name: ENV['PGDATABASE'] || 'git_analytics',
      test_name: ENV['PGDATABASE_TEST'] || "#{ENV['PGDATABASE'] || 'git_analytics'}_test",
      user: ENV['PGUSER'] || ENV['USER'],
      host: ENV['PGHOST'] || 'localhost',
      port: ENV['PGPORT'] || '5432',
      password: ENV['PGPASSWORD'],
      remote: !ENV['DATABASE_URL'].nil?
    }
  end

  def parse_database_url
    return unless ENV['DATABASE_URL']

    # Extract components from postgresql://user:password@host:port/database?params
    url = ENV['DATABASE_URL']
    return unless url.start_with?('postgresql://')

    # Remove protocol
    url = url.sub('postgresql://', '')

    # Extract user:password@host:port/database
    if url.include?('@')
      user_pass, rest = url.split('@', 2)
      user, password = user_pass.split(':', 2)
      ENV['PGUSER'] = user if user
      ENV['PGPASSWORD'] = password if password
    else
      rest = url
    end

    # Remove query params
    rest = rest.split('?').first

    # Extract host:port/database
    if rest.include?('/')
      host_port, database = rest.split('/', 2)
      ENV['PGDATABASE'] = database if database

      # Extract host and port
      if host_port.include?(':')
        host, port = host_port.split(':', 2)
        ENV['PGHOST'] = host if host
        ENV['PGPORT'] = port if port
      else
        ENV['PGHOST'] = host_port if host_port
      end
    end

    puts "#{BLUE}ℹ Using DATABASE_URL from .env#{NC}"
  end

  def setup_databases
    puts ''
    puts "#{BLUE}#{step_label} Setting up databases...#{NC}"

    puts "  Production DB: #{@db_info[:name]}"
    puts "  Test DB: #{@db_info[:test_name]}"
    puts "  Host: #{@db_info[:host]}"
    puts "  User: #{@db_info[:user]}"

    # Check database version
    if @db_info[:remote]
      puts ''
      print '  Checking database version... '
      version = get_database_version(@db_info[:name])
      if version
        puts "#{GREEN}✓#{NC}"
        puts "  #{version}"
      else
        puts "#{YELLOW}(unable to connect)#{NC}"
      end
    end
    puts ''

    if @db_info[:remote]
      # Remote database - don't create, just mark for schema initialization
      puts ''
      puts "#{BLUE}ℹ Remote database detected - skipping database creation#{NC}"
      puts "#{BLUE}  Database is managed by the service provider#{NC}"
      puts "#{BLUE}  Will initialize/update schema on existing database#{NC}"

      @prod_db_created = true
      @test_db_created = false
    else
      # Local database - create/recreate
      @prod_db_created = create_database(@db_info[:name], 'Production')
      @test_db_created = create_database(@db_info[:test_name], 'Test')
    end
  end

  def create_database(db_name, label)
    if database_exists?(db_name)
      puts "#{YELLOW}⚠ #{label} database '#{db_name}' already exists#{NC}"
      print '  Do you want to recreate it? (y/N): '

      response = $stdin.gets.chomp
      if response.downcase == 'y'
        drop_database(db_name)
        create_database_command(db_name)
        puts "#{GREEN}✓ #{label} database recreated#{NC}"
        return true
      else
        puts "#{YELLOW}  Keeping existing #{label} database#{NC}"
        return false
      end
    else
      create_database_command(db_name)
      puts "#{GREEN}✓ #{label} database created#{NC}"
      return true
    end
  end

  def initialize_schemas
    puts ''
    puts "#{BLUE}#{step_label} Initializing database schemas...#{NC}"

    initialize_production_schema if @prod_db_created
    initialize_test_schema if @test_db_created
  end

  def initialize_production_schema
    # Auto-seed if schema exists but migrations not tracked
    seed_base_schema_migrations_if_needed(@db_info[:name])

    # Run all migrations (new unified approach)
    puts '  Applying database migrations...'
    apply_migrations(@db_info[:name], ignore_errors: false)
    puts "#{GREEN}✓ Production schema initialized#{NC}"
  end

  def initialize_test_schema
    # Auto-seed if schema exists but migrations not tracked
    seed_base_schema_migrations_if_needed(@db_info[:test_name])

    # Run all migrations
    puts '  Applying migrations to test database...'
    apply_migrations(@db_info[:test_name], ignore_errors: false)
    puts "#{GREEN}✓ Test schema initialized#{NC}"
  end

  def seed_base_schema_migrations_if_needed(db_name)
    # Detect if this is an existing database from SQL files that needs seeding
    return unless should_seed_migrations?(db_name)

    puts "#{YELLOW}  Detected existing schema from SQL files#{NC}"
    puts "  Seeding schema_migrations table to prevent re-execution..."

    # Seeds for base schema files that were converted to migrations
    seeds = [
      '20251107000000_create_base_schema.rb',
      '20251112080000_create_standard_views.rb',
      '20251116000000_create_category_views.rb',
      '20251122000000_create_personal_views.rb'
    ]

    begin
      db = Sequel.connect(build_connection_string(db_name))

      # Ensure schema_migrations table exists
      unless db.table_exists?(:schema_migrations)
        db.create_table?(:schema_migrations) do
          String :filename, primary_key: true
        end
      end

      # Insert seed records
      seeds.each do |filename|
        next if db[:schema_migrations].where(filename: filename).count > 0

        db[:schema_migrations].insert(filename: filename)
        puts "    #{GREEN}✓ Seeded: #{filename}#{NC}"
      end

      puts "#{GREEN}✓ Schema migrations seeded successfully#{NC}"
    rescue StandardError => e
      puts "#{RED}✗ Failed to seed migrations: #{e.message}#{NC}"
      exit(1)
    ensure
      db.disconnect if db
    end
  end

  def should_seed_migrations?(db_name)
    # Check if:
    # 1. Core tables exist (schema was created from SQL files)
    # 2. schema_migrations table is empty or missing (migrations not tracked)

    return false unless tables_exist?(db_name)

    begin
      db = Sequel.connect(build_connection_string(db_name))

      # If schema_migrations doesn't exist, we need seeding
      return true unless db.table_exists?(:schema_migrations)

      # If schema_migrations exists but is empty, we need seeding
      migration_count = db[:schema_migrations].count
      return migration_count.zero?
    rescue StandardError
      false
    ensure
      db.disconnect if db
    end
  end

  def create_fresh_schema(db_name, label)
    # Initialize schema
    schema_file = File.join(@schema_dir, 'postgres_schema.sql')
    if execute_sql_file(db_name, schema_file)
      puts "#{GREEN}✓ #{label} schema initialized#{NC}"
    else
      puts "#{RED}✗ Failed to initialize #{label} schema#{NC}"
      exit(1)
    end

    # Apply migrations
    puts '  Applying migrations...'
    apply_migrations(db_name, ignore_errors: false)

    # Create views
    views_file = File.join(@schema_dir, 'postgres_views.sql')
    if execute_sql_file(db_name, views_file)
      puts "#{GREEN}✓ #{label} standard views created#{NC}"
    else
      puts "#{RED}✗ Failed to create #{label} views#{NC}"
      exit(1)
    end

    category_views_file = File.join(@schema_dir, 'category_views.sql')
    if execute_sql_file(db_name, category_views_file)
      puts "#{GREEN}✓ #{label} category views created#{NC}"
    else
      puts "#{RED}✗ Failed to create category views#{NC}"
      exit(1)
    end

    personal_views_file = File.join(@schema_dir, 'personal_views.sql')
    if execute_sql_file(db_name, personal_views_file)
      puts "#{GREEN}✓ #{label} personal performance views created#{NC}"
    else
      puts "#{RED}✗ Failed to create personal performance views#{NC}"
      exit(1)
    end
  end

  def apply_migrations(db_name, ignore_errors: false)
    return unless Dir.exist?(@migrations_dir)

    # Check if we have Sequel migrations (.rb) or old SQL migrations (.sql)
    rb_migrations = Dir.glob(File.join(@migrations_dir, '*.rb')).sort
    sql_migrations = Dir.glob(File.join(@migrations_dir, '*.sql')).sort

    if rb_migrations.any?
      # Use Sequel migration framework
      apply_sequel_migrations(db_name, ignore_errors)
    elsif sql_migrations.any?
      # Fallback to old SQL migration approach
      apply_sql_migrations(db_name, sql_migrations, ignore_errors)
    else
      puts "    #{YELLOW}⚠ No migrations found#{NC}"
    end
  end

  def apply_sequel_migrations(db_name, ignore_errors)
    puts "    - Using Sequel migration framework..."

    begin
      # Connect to the specific database
      db = Sequel.connect(build_connection_string(db_name))

      # Enable migration extension
      Sequel.extension :migration

      # Run migrations
      Sequel::Migrator.run(db, @migrations_dir, allow_missing_migration_files: true)

      puts "    #{GREEN}✓ All Sequel migrations applied#{NC}"
    rescue Sequel::Migrator::Error => e
      if ignore_errors
        puts "    #{YELLOW}○ Migrations skipped or already applied#{NC}"
      else
        puts "    #{RED}✗ Migration failed: #{e.message}#{NC}"
        exit(1)
      end
    rescue StandardError => e
      if ignore_errors
        puts "    #{YELLOW}○ Error applying migrations (ignored): #{e.message}#{NC}"
      else
        puts "    #{RED}✗ Unexpected error: #{e.message}#{NC}"
        exit(1)
      end
    ensure
      db.disconnect if db
    end
  end

  def apply_sql_migrations(db_name, migrations, ignore_errors)
    puts "    - Using legacy SQL migrations..."

    migrations.each do |migration|
      migration_name = File.basename(migration)
      puts "    - Applying #{migration_name}..."

      if execute_sql_file(db_name, migration, silent: true)
        puts "    #{GREEN}✓ #{migration_name}#{NC}"
      elsif ignore_errors
        puts "    #{YELLOW}○ #{migration_name} (already applied or skipped)#{NC}"
      else
        puts "    #{RED}✗ Failed: #{migration_name}#{NC}"
        exit(1)
      end
    end
  end

  def build_connection_string(db_name)
    if ENV['DATABASE_URL']
      # Replace database name in URL
      uri = URI.parse(ENV['DATABASE_URL'])
      uri.path = "/#{db_name}"
      uri.to_s
    else
      # Build connection string from individual params
      host = ENV['PGHOST'] || 'localhost'
      port = ENV['PGPORT'] || 5432
      user = ENV['PGUSER'] || ENV['USER']
      password = ENV['PGPASSWORD']

      password_part = password ? ":#{password}" : ''
      "postgresql://#{user}#{password_part}@#{host}:#{port}/#{db_name}"
    end
  end

  def apply_migrations_to_test
    return unless Dir.exist?(@migrations_dir)

    puts '  Applying migrations to test database...'

    # Use the same migration logic as production, with ignore_errors: true for test
    apply_migrations(@db_info[:test_name], ignore_errors: true)
  end

  def recreate_views(db_name)
    views_file = File.join(@schema_dir, 'postgres_views.sql')
    if execute_sql_file(db_name, views_file, silent: true)
      puts "#{GREEN}✓ Standard views updated#{NC}"
    else
      puts "#{YELLOW}⚠ Warning: Some views may have failed#{NC}"
    end

    category_views_file = File.join(@schema_dir, 'category_views.sql')
    if execute_sql_file(db_name, category_views_file, silent: true)
      puts "#{GREEN}✓ Category views updated#{NC}"
    else
      puts "#{YELLOW}⚠ Warning: Some category views may have failed#{NC}"
    end

    personal_views_file = File.join(@schema_dir, 'personal_views.sql')
    if execute_sql_file(db_name, personal_views_file, silent: true)
      puts "#{GREEN}✓ Personal performance views updated#{NC}"
    else
      puts "#{YELLOW}⚠ Warning: Some personal performance views may have failed#{NC}"
    end
  end

  def create_directories
    puts ''
    puts "#{BLUE}#{step_label} Creating data directories...#{NC}"

    data_exports = File.join(@project_dir, 'data', 'exports')
    FileUtils.mkdir_p(data_exports)
    puts "#{GREEN}✓ Created data/exports/#{NC}"
  end

  def print_final_instructions
    puts ''
    puts "#{GREEN}╔════════════════════════════════════════════╗#{NC}"
    puts "#{GREEN}║  Setup Complete!                           ║#{NC}"
    puts "#{GREEN}╚════════════════════════════════════════════╝#{NC}"
    puts ''

    if @database_only
      print_database_only_instructions
    else
      print_full_setup_instructions
    end
  end

  def print_database_only_instructions
    puts 'Database setup complete!'
    puts ''
    puts 'Next steps:'
    puts ''
    puts '1. Configure repositories to track:'
    puts "   #{BLUE}vim config/repositories.json#{NC}"
    puts ''
    puts '2. Extract and load data (with automatic categorization):'
    puts "   #{BLUE}./scripts/run.rb#{NC}"
    puts ''
    puts '3. Query the database:'
    puts "   #{BLUE}psql -d #{@db_info[:name]}#{NC}"
    puts ''
    print_useful_commands
  end

  def print_full_setup_instructions
    puts 'Next steps:'
    puts ''
    puts '1. Edit environment configuration (if needed):'
    puts "   #{BLUE}vim .env#{NC}"
    puts ''
    puts '2. Configure repositories to track:'
    puts "   #{BLUE}vim config/repositories.json#{NC}"
    puts ''
    puts '3. Extract and load data (with automatic categorization):'
    puts "   #{BLUE}./scripts/run.rb#{NC}"
    puts ''
    puts '   This will:'
    puts '   - Extract git data from all enabled repositories'
    puts '   - Load data to database'
    puts '   - Categorize commits (extract business domains)'
    puts '   - Calculate commit weights (revert detection)'
    puts '   - Refresh materialized views'
    puts ''
    puts '4. Query the database:'
    puts "   #{BLUE}psql -d #{@db_info[:name]}#{NC}"
    puts ''
    print_useful_commands
  end

  def print_useful_commands
    puts 'Useful commands:'
    puts "   #{BLUE}# Process single repository#{NC}"
    puts '   ./scripts/run.rb mater'
    puts ''
    puts "   #{BLUE}# Custom date range#{NC}"
    puts '   ./scripts/run.rb --from "1 year ago" --to "now"'
    puts ''
    puts "   #{BLUE}# Check categorization coverage#{NC}"
    puts "   psql -d #{@db_info[:name]} -c \"SELECT * FROM v_category_stats;\""
    puts ''
    puts 'Documentation: See README.md'
    puts ''
  end

  # Helper methods
  def command_exists?(command)
    system("which #{command} > /dev/null 2>&1")
  end

  def database_exists?(db_name)
    cmd = ['psql', '-h', @db_info[:host], '-U', @db_info[:user], '-lqt']
    output = `#{cmd.shelljoin} 2>/dev/null`
    output.split("\n").any? { |line| line.split('|').first.strip == db_name }
  end

  def get_database_version(db_name)
    cmd = [
      'psql',
      '-h', @db_info[:host],
      '-U', @db_info[:user],
      '-d', db_name,
      '-tAc', 'SELECT version();'
    ]
    output = `#{cmd.shelljoin} 2>/dev/null`.strip
    return nil if output.empty?

    output.split('(').first.strip
  end

  def tables_exist?(db_name)
    sql = <<~SQL
      SELECT COUNT(*)
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name IN ('repositories', 'commits');
    SQL

    cmd = [
      'psql',
      '-h', @db_info[:host],
      '-U', @db_info[:user],
      '-d', db_name,
      '-tAc', sql
    ]

    output = `#{cmd.shelljoin} 2>/dev/null`.strip
    output == '2'
  end

  def create_database_command(db_name)
    cmd = ['createdb', '-h', @db_info[:host], '-U', @db_info[:user], db_name]
    system(cmd.shelljoin)
  end

  def drop_database(db_name)
    cmd = ['dropdb', '-h', @db_info[:host], '-U', @db_info[:user], db_name]
    system("#{cmd.shelljoin} 2>/dev/null")
  end

  def execute_sql_file(db_name, file_path, silent: false)
    cmd = [
      'psql',
      '-h', @db_info[:host],
      '-U', @db_info[:user],
      '-d', db_name,
      '-f', file_path
    ]

    if silent
      system("#{cmd.shelljoin} > /dev/null 2>&1")
    else
      system(cmd.shelljoin)
    end
  end
end

# Parse command-line options
if __FILE__ == $PROGRAM_NAME
  options = {
    database_only: false
  }

  parser = OptionParser.new do |opts|
    opts.banner = <<~BANNER
      Git Productivity Analytics - Setup Script

      Usage:
        #{$PROGRAM_NAME} [OPTIONS]

      Options:
    BANNER

    opts.on('--database-only', 'Only set up the database (skip dependencies and .env setup)') do
      options[:database_only] = true
    end

    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      puts <<~EXAMPLES

        Examples:
          # Full setup (recommended for first-time setup)
          #{$PROGRAM_NAME}

          # Database-only setup (useful for recreating database)
          #{$PROGRAM_NAME} --database-only

      EXAMPLES
      exit(0)
    end
  end

  begin
    parser.parse!
  rescue OptionParser::InvalidOption => e
    puts "#{SetupScript::RED}Unknown option: #{e.message}#{SetupScript::NC}"
    puts 'Run with --help for usage information'
    exit(1)
  end

  # Run the setup
  script = SetupScript.new(options)
  script.run
end
