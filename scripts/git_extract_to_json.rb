#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'time'
require 'fileutils'

# Git commit data extractor that exports to JSON format
# Usage: ./scripts/git_extract_to_json.rb FROM_DATE TO_DATE OUTPUT_FILE [REPO_NAME] [REPO_PATH]
class GitExtractor
  def initialize(from_date, to_date, output_file, repo_name = nil, repo_path = '.')
    @from_date = from_date
    @to_date = to_date
    @output_file = File.expand_path(output_file)
    @repo_path = File.expand_path(repo_path)
    @repo_name = repo_name || detect_repo_name
    @commits = []
  end

  def run
    validate_git_repo!
    validate_date_range!
    extract_commits
    write_output
    print_summary
  end

  private

  def validate_git_repo!
    unless Dir.exist?(File.join(@repo_path, '.git'))
      abort "Error: '#{@repo_path}' is not a git repository"
    end
  end

  def validate_date_range!
    test_cmd = ['git', '-C', @repo_path, 'log', "--since=#{@from_date}", "--until=#{@to_date}", '--max-count=1']
    output, status = Open3.capture2(*test_cmd, :err => [:child, :out])

    unless status.success?
      abort "Error: Invalid date format or range\n#{output}"
    end
  end

  def detect_repo_name
    # Try to get the repository name from git remote or directory name
    remote_cmd = ['git', '-C', @repo_path, 'remote', 'get-url', 'origin']
    remote_url, status = Open3.capture2(*remote_cmd, :err => '/dev/null')

    if status.success? && !remote_url.strip.empty?
      # Extract repo name from URL (e.g., "user/repo" or "repo")
      remote_url.strip.split('/').last.gsub(/\.git$/, '')
    else
      # Fall back to directory name
      File.basename(File.expand_path(@repo_path))
    end
  end

  def extract_commits
    # Use git log with numstat to get detailed file-level changes
    # Pass as array to avoid shell interpretation of % characters
    git_cmd = [
      'git',
      '-C', @repo_path,
      'log',
      "--since=#{@from_date}",
      "--until=#{@to_date}",
      '--numstat',
      '--pretty=format:COMMIT|%H|%ai|%an|%ae|%s'
    ]

    stdout, stderr, status = Open3.capture3(*git_cmd)

    unless status.success?
      abort "Error executing git command:\n#{stderr}"
    end

    if stdout.strip.empty?
      warn "Warning: No commits found in the specified date range"
      return
    end

    parse_git_output(stdout)
  end

  def parse_git_output(output)
    current_commit = nil

    output.each_line do |line|
      line = line.strip
      next if line.empty?

      if line.start_with?('COMMIT|')
        # Save previous commit if exists
        @commits << current_commit if current_commit

        # Parse new commit header: COMMIT|hash|date|author_name|author_email|subject
        parts = line.split('|', 6)
        current_commit = {
          hash: parts[1],
          date: parse_iso_date(parts[2]),
          author_name: parts[3],
          author_email: parts[4],
          subject: parts[5],
          lines_added: 0,
          lines_deleted: 0,
          files_changed: 0,
          files: []
        }
      elsif current_commit
        # Parse numstat line: added deleted filename
        parts = line.split("\t", 3)
        next if parts.length < 3

        added = parts[0]
        deleted = parts[1]
        filename = parts[2]

        # Skip binary files (marked with "-")
        next if added == '-' || deleted == '-'

        added_int = added.to_i
        deleted_int = deleted.to_i

        current_commit[:lines_added] += added_int
        current_commit[:lines_deleted] += deleted_int
        current_commit[:files_changed] += 1

        # Store file-level details (optional, can be disabled for smaller output)
        current_commit[:files] << {
          filename: filename,
          added: added_int,
          deleted: deleted_int
        }
      end
    end

    # Don't forget the last commit
    @commits << current_commit if current_commit
  end

  def parse_iso_date(date_str)
    # Convert to ISO 8601 format for JSON
    Time.parse(date_str).iso8601
  rescue ArgumentError
    date_str
  end

  def write_output
    # Create output directory if it doesn't exist
    FileUtils.mkdir_p(File.dirname(@output_file))

    output_data = {
      repository: @repo_name,
      repository_path: File.expand_path(@repo_path),
      extraction_date: Time.now.iso8601,
      date_range: {
        from: @from_date,
        to: @to_date
      },
      summary: {
        total_commits: @commits.length,
        total_lines_added: @commits.sum { |c| c[:lines_added] },
        total_lines_deleted: @commits.sum { |c| c[:lines_deleted] },
        total_files_changed: @commits.sum { |c| c[:files_changed] },
        unique_authors: @commits.map { |c| c[:author_email] }.uniq.length
      },
      commits: @commits
    }

    File.write(@output_file, JSON.pretty_generate(output_data))
  end

  def print_summary
    puts "✓ Extraction complete"
    puts "  Repository: #{@repo_name}"
    puts "  Date range: #{@from_date} to #{@to_date}"
    puts "  Commits extracted: #{@commits.length}"
    puts "  Output file: #{@output_file}"
    puts "  File size: #{(File.size(@output_file) / 1024.0).round(2)} KB"
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  if ARGV.include?('-h') || ARGV.include?('--help') || ARGV.length < 3
    puts <<~HELP
      Git Commit Data Extractor (JSON Export)

      Usage:
        #{$PROGRAM_NAME} FROM_DATE TO_DATE OUTPUT_FILE [REPO_NAME] [REPO_PATH]

      Arguments:
        FROM_DATE    Start date (e.g., "2025-07-01" or "4 months ago")
        TO_DATE      End date (e.g., "2025-11-01" or "now")
        OUTPUT_FILE  Path to output JSON file (e.g., "data/repo1.json")
        REPO_NAME    Optional: Repository name (auto-detected if omitted)
        REPO_PATH    Optional: Path to git repository (default: current directory)

      Examples:
        # Extract last 4 months from current repo
        #{$PROGRAM_NAME} "4 months ago" "now" "data/my-repo.json"

        # Extract specific date range from another repo
        #{$PROGRAM_NAME} "2025-07-01" "2025-11-01" "data/app1.json" "MyApp" "/path/to/repo"

        # Extract with custom repository name
        #{$PROGRAM_NAME} "1 year ago" "now" "data/exports/backend.json" "backend-api"
    HELP
    exit(ARGV.include?('-h') || ARGV.include?('--help') ? 0 : 1)
  end

  from_date = ARGV[0]
  to_date = ARGV[1]
  output_file = ARGV[2]
  repo_name = ARGV[3]
  repo_path = ARGV[4] || '.'

  begin
    extractor = GitExtractor.new(from_date, to_date, output_file, repo_name, repo_path)
    extractor.run
  rescue Interrupt
    puts "\n\nInterrupted by user"
    exit(1)
  rescue StandardError => e
    abort "Error: #{e.message}\n#{e.backtrace.join("\n")}"
  end
end
