#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv/load' unless ENV['RSPEC_RUNNING']
require_relative '../lib/sequel_connection'

# Database Rollback Script
# Rolls back the last N migrations (default: 1)

class MigrationRollback
  MIGRATIONS_DIR = File.expand_path('../schema/migrations', __dir__)

  def initialize(steps: 1)
    @db = SequelConnection.db
    @steps = steps
  end

  def run
    puts "Database Migration Rollback"
    puts "=" * 80
    puts "Database: #{SequelConnection.database_name}"
    puts "Migrations directory: #{MIGRATIONS_DIR}"
    puts "Steps to rollback: #{@steps}"
    puts

    check_prerequisites
    show_current_status
    confirm_rollback
    perform_rollback
    show_final_status
  end

  private

  def check_prerequisites
    unless Dir.exist?(MIGRATIONS_DIR)
      puts "ERROR: Migrations directory not found: #{MIGRATIONS_DIR}"
      exit 1
    end

    unless @db.table_exists?(:schema_migrations)
      puts "ERROR: schema_migrations table not found. No migrations to rollback."
      exit 1
    end
  end

  def show_current_status
    applied = @db[:schema_migrations].order(:filename).all

    if applied.empty?
      puts "No migrations to rollback (database is empty)."
      exit 0
    end

    puts "Currently applied migrations:"
    applied.each do |migration|
      puts "  ✓ #{migration[:filename]}"
    end
    puts
    puts "Total applied: #{applied.count}"
    puts
  end

  def confirm_rollback
    applied_count = @db[:schema_migrations].count

    if @steps > applied_count
      puts "WARNING: Requested rollback of #{@steps} migrations, but only #{applied_count} are applied."
      puts "Will rollback all #{applied_count} migrations."
      @steps = applied_count
      puts
    end

    # Get migrations that will be rolled back
    migrations_to_rollback = @db[:schema_migrations]
                                .order(Sequel.desc(:filename))
                                .limit(@steps)
                                .select_map(:filename)

    puts "The following migrations will be rolled back:"
    migrations_to_rollback.reverse.each do |filename|
      puts "  ✗ #{filename}"
    end
    puts

    print "Continue? (y/N): "
    response = $stdin.gets.chomp.downcase

    unless response == 'y' || response == 'yes'
      puts "Rollback cancelled."
      exit 0
    end
    puts
  end

  def perform_rollback
    puts "Rolling back #{@steps} migration(s)..."
    puts

    begin
      # Enable the migration extension
      Sequel.extension :migration

      # Get current migration version
      current_version = @db[:schema_migrations].order(Sequel.desc(:filename)).first
      return unless current_version

      # Calculate target version (rollback N steps)
      all_versions = @db[:schema_migrations].order(:filename).select_map(:filename)
      target_index = all_versions.length - @steps - 1
      target_version = target_index >= 0 ? all_versions[target_index].to_i : 0

      # Run rollback
      Sequel::Migrator.run(@db, MIGRATIONS_DIR, target: target_version, allow_missing_migration_files: true)

      puts "✓ Rollback completed successfully!"
      puts
    rescue Sequel::Migrator::Error => e
      puts "ERROR: Rollback failed!"
      puts e.message
      puts
      puts e.backtrace.first(5).join("\n")
      exit 1
    rescue StandardError => e
      puts "ERROR: Unexpected error during rollback!"
      puts e.message
      puts
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  def show_final_status
    puts "Current migration status after rollback:"
    puts

    applied = @db[:schema_migrations].order(:filename).all

    if applied.empty?
      puts "  No migrations applied (database rolled back to initial state)."
    else
      applied.each do |migration|
        puts "  ✓ #{migration[:filename]}"
      end
      puts
      puts "Total applied: #{applied.count}"
    end
  end
end

# Parse command line arguments
steps = (ARGV[0] || '1').to_i

if steps < 1
  puts "ERROR: Steps must be a positive integer"
  puts "Usage: #{$PROGRAM_NAME} [steps]"
  puts "Example: #{$PROGRAM_NAME} 3    # Rollback last 3 migrations"
  exit 1
end

# Run the rollback
begin
  rollback = MigrationRollback.new(steps: steps)
  rollback.run
rescue StandardError => e
  puts "FATAL ERROR: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end
