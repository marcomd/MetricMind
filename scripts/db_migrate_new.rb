#!/usr/bin/env ruby
# frozen_string_literal: true

require 'time'
require 'fileutils'

# New Migration Generator Script
# Creates a new migration file with timestamp and template

class MigrationGenerator
  MIGRATIONS_DIR = File.expand_path('../schema/migrations', __dir__)

  def initialize(name)
    @name = sanitize_name(name)
    @timestamp = Time.now.strftime('%Y%m%d%H%M%S')
    @filename = "#{@timestamp}_#{@name}.rb"
  end

  def run
    puts "Migration Generator"
    puts "=" * 80
    puts "Creating new migration: #{@filename}"
    puts

    validate_name
    create_migration_file
    show_instructions
  end

  private

  def sanitize_name(name)
    # Remove any non-alphanumeric characters (except underscore)
    # Convert to lowercase
    name.gsub(/[^a-zA-Z0-9_]/, '_').gsub(/_+/, '_').downcase
  end

  def validate_name
    if @name.empty?
      puts "ERROR: Migration name cannot be empty"
      exit 1
    end

    # Check if a migration with this name already exists
    existing = Dir.glob(File.join(MIGRATIONS_DIR, "*_#{@name}.rb"))
    if existing.any?
      puts "WARNING: A migration with similar name already exists:"
      existing.each { |f| puts "  - #{File.basename(f)}" }
      puts
      print "Continue anyway? (y/N): "
      response = $stdin.gets.chomp.downcase
      unless response == 'y' || response == 'yes'
        puts "Migration creation cancelled."
        exit 0
      end
      puts
    end
  end

  def create_migration_file
    FileUtils.mkdir_p(MIGRATIONS_DIR)

    filepath = File.join(MIGRATIONS_DIR, @filename)

    if File.exist?(filepath)
      puts "ERROR: Migration file already exists: #{@filename}"
      exit 1
    end

    template = generate_template

    File.write(filepath, template)
    puts "✓ Created migration file: #{filepath}"
    puts
  end

  def generate_template
    # Determine migration type from name to provide better template
    template_type = detect_migration_type(@name)

    case template_type
    when :add_column
      add_column_template
    when :create_table
      create_table_template
    when :add_index
      add_index_template
    else
      generic_template
    end
  end

  def detect_migration_type(name)
    case name
    when /^add_.*_to_/
      :add_column
    when /^create_/
      :create_table
    when /^add_index/
      :add_index
    else
      :generic
    end
  end

  def generic_template
    <<~RUBY
      # frozen_string_literal: true

      # Migration: #{@name.split('_').map(&:capitalize).join(' ')}
      # Created: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}

      Sequel.migration do
        up do
          run <<-SQL
            -- Add your forward migration SQL here
            -- Example: ALTER TABLE commits ADD COLUMN new_field VARCHAR(255);
          SQL
        end

        down do
          run <<-SQL
            -- Add your rollback migration SQL here
            -- Example: ALTER TABLE commits DROP COLUMN IF EXISTS new_field;
          SQL
        end
      end
    RUBY
  end

  def add_column_template
    # Extract table name and column name from migration name
    # Pattern: add_column_name_to_table_name
    if @name =~ /^add_(.+)_to_(.+)$/
      column = $1
      table = $2
      column_type = 'VARCHAR(255)' # Default, user should modify
    else
      column = 'column_name'
      table = 'table_name'
      column_type = 'VARCHAR(255)'
    end

    <<~RUBY
      # frozen_string_literal: true

      # Migration: #{@name.split('_').map(&:capitalize).join(' ')}
      # Created: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}

      Sequel.migration do
        up do
          run <<-SQL
            ALTER TABLE #{table}
            ADD COLUMN IF NOT EXISTS #{column} #{column_type};

            COMMENT ON COLUMN #{table}.#{column} IS 'Description of this column';
          SQL
        end

        down do
          run <<-SQL
            ALTER TABLE #{table}
            DROP COLUMN IF EXISTS #{column};
          SQL
        end
      end
    RUBY
  end

  def create_table_template
    # Extract table name from migration name
    # Pattern: create_table_name
    table = @name.sub(/^create_/, '')

    <<~RUBY
      # frozen_string_literal: true

      # Migration: #{@name.split('_').map(&:capitalize).join(' ')}
      # Created: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}

      Sequel.migration do
        up do
          run <<-SQL
            CREATE TABLE IF NOT EXISTS #{table} (
              id SERIAL PRIMARY KEY,
              name VARCHAR(255) NOT NULL,
              created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
              updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );

            CREATE INDEX IF NOT EXISTS idx_#{table}_name ON #{table}(name);

            COMMENT ON TABLE #{table} IS 'Description of this table';
          SQL
        end

        down do
          run <<-SQL
            DROP TABLE IF EXISTS #{table} CASCADE;
          SQL
        end
      end
    RUBY
  end

  def add_index_template
    <<~RUBY
      # frozen_string_literal: true

      # Migration: #{@name.split('_').map(&:capitalize).join(' ')}
      # Created: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}

      Sequel.migration do
        up do
          run <<-SQL
            CREATE INDEX IF NOT EXISTS idx_table_column ON table_name(column_name);
          SQL
        end

        down do
          run <<-SQL
            DROP INDEX IF EXISTS idx_table_column;
          SQL
        end
      end
    RUBY
  end

  def show_instructions
    puts "Next steps:"
    puts "  1. Edit the migration file and add your SQL"
    puts "  2. Review both up and down migrations"
    puts "  3. Test with: ./scripts/db_migrate.rb"
    puts "  4. Check status: ./scripts/db_migrate_status.rb"
    puts
    puts "Tips:"
    puts "  - Use IF NOT EXISTS for idempotent operations"
    puts "  - Always provide a down migration for rollback"
    puts "  - Add COMMENT statements for documentation"
    puts "  - Test rollback with: ./scripts/db_rollback.rb"
  end
end

# Parse command line arguments
if ARGV.empty?
  puts "Usage: #{$PROGRAM_NAME} <migration_name>"
  puts
  puts "Examples:"
  puts "  #{$PROGRAM_NAME} add_status_to_commits"
  puts "  #{$PROGRAM_NAME} create_tags_table"
  puts "  #{$PROGRAM_NAME} add_index_on_author_email"
  puts
  exit 1
end

migration_name = ARGV.join('_')

# Run the generator
begin
  generator = MigrationGenerator.new(migration_name)
  generator.run
rescue StandardError => e
  puts "FATAL ERROR: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end
