#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'time'

# Migration Rename Script
# Converts old numbered migrations (001_name.sql) to timestamp format (YYYYMMDDHHMMSS_name.rb)
# and wraps SQL in Sequel migration format with up/down blocks

class MigrationRenamer
  MIGRATIONS_DIR = File.expand_path('../schema/migrations', __dir__)
  BACKUP_DIR = File.expand_path('../schema/migrations_backup', __dir__)

  def initialize(dry_run: false)
    @dry_run = dry_run
    @migrations = []
  end

  def run
    puts "Migration Rename Script"
    puts "=" * 80
    puts "Directory: #{MIGRATIONS_DIR}"
    puts "Mode: #{@dry_run ? 'DRY RUN (no changes)' : 'LIVE (will modify files)'}"
    puts

    collect_migrations
    validate_migrations
    create_backup unless @dry_run
    rename_migrations
    print_summary
  end

  private

  def collect_migrations
    puts "Collecting migrations..."
    Dir.glob(File.join(MIGRATIONS_DIR, '*.sql')).sort.each do |file|
      next if File.basename(file) =~ /^\d{14}_/ # Skip already renamed

      match = File.basename(file).match(/^(\d{3})_(.+)\.sql$/)
      unless match
        puts "  ⚠️  Skipping unrecognized file: #{File.basename(file)}"
        next
      end

      number = match[1].to_i
      name = match[2]
      mtime = File.mtime(file)
      timestamp = mtime.strftime('%Y%m%d%H%M%S')

      @migrations << {
        old_path: file,
        old_name: File.basename(file),
        number: number,
        name: name,
        mtime: mtime,
        timestamp: timestamp,
        new_name: "#{timestamp}_#{name}.rb"
      }

      puts "  ✓ Found: #{File.basename(file)} (modified: #{mtime.strftime('%Y-%m-%d %H:%M:%S')})"
    end
    puts
  end

  def validate_migrations
    return if @migrations.empty?

    puts "Validating migrations..."

    # Check for timestamp collisions
    timestamps = @migrations.map { |m| m[:timestamp] }
    duplicates = timestamps.select { |t| timestamps.count(t) > 1 }.uniq

    if duplicates.any?
      puts "  ⚠️  WARNING: Multiple migrations have the same timestamp:"
      duplicates.each do |ts|
        colliding = @migrations.select { |m| m[:timestamp] == ts }
        puts "    Timestamp: #{ts}"
        colliding.each { |m| puts "      - #{m[:old_name]}" }
      end
      puts "  Manual adjustment may be needed!"
    else
      puts "  ✓ No timestamp collisions detected"
    end
    puts
  end

  def create_backup
    puts "Creating backup..."
    FileUtils.mkdir_p(BACKUP_DIR)

    @migrations.each do |migration|
      backup_path = File.join(BACKUP_DIR, migration[:old_name])
      FileUtils.cp(migration[:old_path], backup_path)
    end

    puts "  ✓ Backed up #{@migrations.size} migrations to: #{BACKUP_DIR}"
    puts
  end

  def rename_migrations
    puts "Converting and renaming migrations..."
    puts

    @migrations.each do |migration|
      convert_migration(migration)
    end
  end

  def convert_migration(migration)
    puts "Processing: #{migration[:old_name]}"

    # Read original SQL content
    sql_content = File.read(migration[:old_path])

    # Extract metadata from comments
    description = extract_description(sql_content)
    original_date = extract_date(sql_content)

    # Generate down migration SQL
    down_sql = generate_down_migration(sql_content, migration[:name])

    # Create Sequel migration format
    sequel_content = generate_sequel_migration(
      sql_content,
      down_sql,
      description,
      original_date,
      migration[:old_name]
    )

    # Write new file
    new_path = File.join(MIGRATIONS_DIR, migration[:new_name])

    if @dry_run
      puts "  → Would create: #{migration[:new_name]}"
    else
      File.write(new_path, sequel_content)
      File.delete(migration[:old_path])
      puts "  ✓ Renamed to: #{migration[:new_name]}"
    end

    puts
  end

  def extract_description(sql)
    sql.lines.each do |line|
      if line =~ /^--\s*Description:\s*(.+)$/
        return $1.strip
      elsif line =~ /^--\s*Migration:\s*(.+)$/
        return $1.strip
      end
    end
    'Migrated from old format'
  end

  def extract_date(sql)
    sql.lines.each do |line|
      return $1.strip if line =~ /^--\s*Date:\s*(.+)$/
    end
    nil
  end

  def generate_down_migration(sql, migration_name)
    # Generate reverse operations for common patterns
    down_statements = []

    # Track what was created so we can drop it
    sql.scan(/ALTER TABLE (\w+)\s+ADD COLUMN IF NOT EXISTS (\w+)/i) do |table, column|
      down_statements << "ALTER TABLE #{table} DROP COLUMN IF EXISTS #{column};"
    end

    sql.scan(/CREATE TABLE IF NOT EXISTS (\w+)/i) do |table|
      down_statements << "DROP TABLE IF EXISTS #{table[0]} CASCADE;"
    end

    sql.scan(/CREATE INDEX IF NOT EXISTS (\w+)/i) do |index|
      down_statements << "DROP INDEX IF EXISTS #{index[0]};"
    end

    sql.scan(/ADD CONSTRAINT (\w+)/i) do |constraint|
      # Find the table name from context
      if sql =~ /ALTER TABLE (\w+).*ADD CONSTRAINT #{constraint[0]}/m
        table = $1
        down_statements << "ALTER TABLE #{table} DROP CONSTRAINT IF EXISTS #{constraint[0]};"
      end
    end

    # For migrations with INSERT (data migrations), add a warning comment
    if sql.include?('INSERT INTO')
      down_statements << "-- WARNING: This migration includes data operations (INSERT/UPDATE)."
      down_statements << "-- Manual rollback may be required. Review the up migration carefully."
    end

    if down_statements.empty?
      "-- WARNING: Could not auto-generate down migration for: #{migration_name}\n      -- Please review and implement rollback logic manually if needed.\n      -- Common rollbacks: DROP TABLE, DROP COLUMN, DROP INDEX, DROP CONSTRAINT"
    else
      down_statements.reverse.join("\n      ")
    end
  end

  def generate_sequel_migration(up_sql, down_sql, description, original_date, original_name)
    # Remove SQL comments from the up migration (keep it clean)
    up_sql_clean = up_sql.lines.reject { |line| line.strip.start_with?('--') }.join

    <<~RUBY
      # frozen_string_literal: true

      # Migration: #{description}
      # Original file: #{original_name}
      # Original date: #{original_date || 'Unknown'}
      # Converted from SQL to Sequel format

      Sequel.migration do
        up do
          run <<-SQL
      #{indent_sql(up_sql_clean, 6)}
          SQL
        end

        down do
          run <<-SQL
      #{indent_sql(down_sql, 6)}
          SQL
        end
      end
    RUBY
  end

  def indent_sql(sql, spaces)
    indent = ' ' * spaces
    sql.strip.lines.map { |line| "#{indent}#{line.rstrip}" }.join("\n")
  end

  def print_summary
    puts "=" * 80
    puts "Summary"
    puts "=" * 80
    puts "Migrations processed: #{@migrations.size}"

    if @dry_run
      puts
      puts "This was a DRY RUN. No files were modified."
      puts "Run without --dry-run to perform the actual rename."
    else
      puts
      puts "✓ Migrations renamed successfully!"
      puts "✓ Backup created in: #{BACKUP_DIR}"
      puts
      puts "Next steps:"
      puts "  1. Review the generated down migrations for accuracy"
      puts "  2. Test migrations with: ./scripts/db_migrate_status.rb"
      puts "  3. Apply migrations with: ./scripts/db_migrate.rb"
    end
  end
end

# Parse command line arguments
dry_run = ARGV.include?('--dry-run')

# Run the renamer
begin
  renamer = MigrationRenamer.new(dry_run: dry_run)
  renamer.run
rescue StandardError => e
  puts "ERROR: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end
