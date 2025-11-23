#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv/load' unless ENV['RSPEC_RUNNING']
require_relative '../lib/sequel_connection'

# Migration Status Script
# Shows which migrations are applied and which are pending

class MigrationStatus
  MIGRATIONS_DIR = File.expand_path('../schema/migrations', __dir__)

  def initialize
    @db = SequelConnection.db
  end

  def run
    puts "Database Migration Status"
    puts "=" * 80
    puts "Database: #{SequelConnection.database_name}"
    puts "Migrations directory: #{MIGRATIONS_DIR}"
    puts

    check_migrations_directory
    show_status
  end

  private

  def check_migrations_directory
    unless Dir.exist?(MIGRATIONS_DIR)
      puts "ERROR: Migrations directory not found: #{MIGRATIONS_DIR}"
      exit 1
    end
  end

  def show_status
    # Get all migration files
    migration_files = Dir.glob(File.join(MIGRATIONS_DIR, '*.rb'))
                         .map { |f| File.basename(f, '.rb') }
                         .sort

    if migration_files.empty?
      puts "No migration files found in #{MIGRATIONS_DIR}"
      return
    end

    # Get applied migrations from database
    applied_migrations = if @db.table_exists?(:schema_migrations)
                          @db[:schema_migrations].select_map(:filename).map(&:to_s)
                        else
                          []
                        end

    # Display status
    puts "Migration Status:"
    puts

    if applied_migrations.empty? && !@db.table_exists?(:schema_migrations)
      puts "  ⚠️  schema_migrations table does not exist yet"
      puts "  Run './scripts/db_migrate.rb' to initialize and apply migrations"
      puts
    end

    pending_count = 0
    applied_count = 0

    migration_files.each do |filename|
      # Sequel stores filenames with .rb extension in schema_migrations
      full_filename = "#{filename}.rb"
      is_applied = applied_migrations.include?(full_filename)

      if is_applied
        puts "  ✓ #{filename} (applied)"
        applied_count += 1
      else
        puts "  ✗ #{filename} (pending)"
        pending_count += 1
      end
    end

    puts
    puts "=" * 80
    puts "Summary:"
    puts "  Total migrations: #{migration_files.count}"
    puts "  Applied: #{applied_count}"
    puts "  Pending: #{pending_count}"

    if pending_count > 0
      puts
      puts "Run './scripts/db_migrate.rb' to apply pending migrations"
    elsif applied_count == 0
      puts
      puts "No migrations applied yet. Run './scripts/db_migrate.rb' to initialize."
    else
      puts
      puts "All migrations are up to date!"
    end

    # Show detailed information if requested
    if ARGV.include?('--verbose') || ARGV.include?('-v')
      show_detailed_info(applied_migrations)
    end
  end

  def show_detailed_info(applied_migrations)
    return unless @db.table_exists?(:schema_migrations)
    return if applied_migrations.empty?

    puts
    puts "=" * 80
    puts "Detailed Migration History:"
    puts

    # Note: Sequel's schema_migrations table only stores filename
    # It doesn't track application timestamp by default
    @db[:schema_migrations].order(:filename).each do |migration|
      puts "  #{migration[:filename]}"
    end
  end
end

# Run the status check
begin
  status = MigrationStatus.new
  status.run
rescue StandardError => e
  puts "FATAL ERROR: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end
