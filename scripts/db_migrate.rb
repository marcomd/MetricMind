#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv/load' unless ENV['RSPEC_RUNNING']
require_relative '../lib/sequel_connection'

# Database Migration Script
# Runs all pending migrations using Sequel's migration framework

class MigrationRunner
  MIGRATIONS_DIR = File.expand_path('../schema/migrations', __dir__)

  def initialize
    @db = SequelConnection.db
  end

  def run
    puts "Database Migration Runner"
    puts "=" * 80
    puts "Database: #{SequelConnection.database_name}"
    puts "Migrations directory: #{MIGRATIONS_DIR}"
    puts

    check_migrations_directory
    run_migrations
    show_status
  end

  private

  def check_migrations_directory
    unless Dir.exist?(MIGRATIONS_DIR)
      puts "ERROR: Migrations directory not found: #{MIGRATIONS_DIR}"
      exit 1
    end

    migration_files = Dir.glob(File.join(MIGRATIONS_DIR, '*.rb'))
    if migration_files.empty?
      puts "WARNING: No migration files found in #{MIGRATIONS_DIR}"
      puts "Nothing to migrate."
      exit 0
    end
  end

  def run_migrations
    puts "Running migrations..."
    puts

    begin
      # Enable the migration extension
      Sequel.extension :migration

      # Run migrations
      # This will automatically create schema_migrations table if it doesn't exist
      Sequel::Migrator.run(@db, MIGRATIONS_DIR, allow_missing_migration_files: true)

      puts "✓ All migrations applied successfully!"
      puts
    rescue Sequel::Migrator::Error => e
      puts "ERROR: Migration failed!"
      puts e.message
      puts
      puts e.backtrace.first(5).join("\n")
      exit 1
    rescue StandardError => e
      puts "ERROR: Unexpected error during migration!"
      puts e.message
      puts
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  def show_status
    puts "Current migration status:"
    puts

    # Get applied migrations
    if @db.table_exists?(:schema_migrations)
      applied = @db[:schema_migrations].order(:filename).all

      if applied.empty?
        puts "  No migrations applied yet."
      else
        applied.each do |migration|
          timestamp = migration[:filename]
          puts "  ✓ #{timestamp}"
        end
        puts
        puts "Total applied: #{applied.count}"
      end
    else
      puts "  schema_migrations table not yet created."
    end
  end
end

# Run the migration
begin
  runner = MigrationRunner.new
  runner.run
rescue StandardError => e
  puts "FATAL ERROR: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end
