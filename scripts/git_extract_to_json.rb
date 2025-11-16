#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'time'
require 'fileutils'

# Git commit data extractor that exports to JSON format
# Extracts commit history from a Git repository and exports it to a structured JSON file
# including commit metadata, file changes, AI tools used, and weight information.
#
# Usage: ./scripts/git_extract_to_json.rb FROM_DATE TO_DATE OUTPUT_FILE [REPO_NAME] [REPO_PATH]
class GitExtractor
  # Initializes a new GitExtractor instance
  # @param from_date [String] start date for extraction (e.g., "2024-01-01" or "6 months ago")
  # @param to_date [String] end date for extraction (e.g., "2024-12-31" or "now")
  # @param output_file [String] path to the output JSON file (tilde paths will be expanded)
  # @param repo_name [String, nil] optional repository name (auto-detected if nil)
  # @param repo_path [String] path to the git repository (default: current directory)
  # @param repo_description [String, nil] optional repository description
  def initialize(from_date, to_date, output_file, repo_name = nil, repo_path = '.', repo_description = nil)
    @from_date = from_date
    @to_date = to_date
    @output_file = File.expand_path(output_file)
    @repo_path = File.expand_path(repo_path)
    @repo_name = repo_name || detect_repo_name
    @repo_description = repo_description
    @commits = []
  end

  # Executes the full extraction workflow
  # Validates the repository and date range, extracts commits, writes output, and prints summary
  # @return [void]
  # @raise [SystemExit] if validation fails or git commands fail
  def run
    validate_git_repo!
    validate_date_range!
    extract_commits
    write_output
    print_summary
  end

  private

  # Validates that the specified path is a git repository
  # @return [void]
  # @raise [SystemExit] if the path is not a git repository
  def validate_git_repo!
    unless Dir.exist?(File.join(@repo_path, '.git'))
      abort "Error: '#{@repo_path}' is not a git repository"
    end
  end

  # Validates that the date range is valid and parseable by git
  # @return [void]
  # @raise [SystemExit] if the date format or range is invalid
  def validate_date_range!
    test_cmd = ['git', '-C', @repo_path, 'log', "--since=#{@from_date}", "--until=#{@to_date}", '--max-count=1']
    output, status = Open3.capture2(*test_cmd, :err => [:child, :out])

    unless status.success?
      abort "Error: Invalid date format or range\n#{output}"
    end
  end

  # Detects the repository name from git remote URL or directory name
  # Tries to extract the name from the git remote origin URL first,
  # falls back to using the directory name if remote is not available
  # @return [String] the detected repository name
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

  # Extracts commits from the git repository for the specified date range
  # Uses git log with numstat format to capture commit metadata and file-level statistics
  # @return [void]
  # @raise [SystemExit] if the git command fails
  def extract_commits
    # Use git log with numstat to get detailed file-level changes
    # Pass as array to avoid shell interpretation of % characters
    # Format: COMMIT|hash|date|author|email|subject|BODY|body_text
    git_cmd = [
      'git',
      '-C', @repo_path,
      'log',
      "--since=#{@from_date}",
      "--until=#{@to_date}",
      '--numstat',
      '--pretty=format:COMMIT|%H|%ai|%an|%ae|%s|BODY|%b|BODYEND|'
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

  # Parses the raw git log output and builds commit data structures
  # Processes commit headers, body text, and numstat file change information
  # Populates the @commits array with structured commit data
  # @param output [String] the raw output from git log command
  # @return [void]
  def parse_git_output(output)
    current_commit = nil
    in_body = false
    body_text = []

    output.each_line do |line|
      line_stripped = line.strip

      if line.start_with?('COMMIT|')
        # Save previous commit if exists
        if current_commit
          # Extract AI tools from accumulated body text
          full_body = body_text.join("\n")
          current_commit[:ai_tools] = extract_ai_tools(full_body)
          @commits << current_commit
          body_text = []
        end

        # Parse new commit header: COMMIT|hash|date|author_name|author_email|subject|BODY|...
        parts = line.split('|')
        in_body = false

        current_commit = {
          hash: parts[1],
          date: parse_iso_date(parts[2]),
          author_name: parts[3],
          author_email: parts[4],
          subject: parts[5],
          weight: 100,
          ai_tools: nil,
          lines_added: 0,
          lines_deleted: 0,
          files_changed: 0,
          files: []
        }

        # Check if body starts in this line
        body_start_idx = parts.index('BODY')
        if body_start_idx
          in_body = true
          # Collect any body text after BODY marker
          body_parts = parts[(body_start_idx + 1)..-1]
          body_end_idx = body_parts.index('BODYEND')
          if body_end_idx
            # Body ends in same line
            body_text = body_parts[0...body_end_idx]
            in_body = false
          else
            body_text = body_parts
          end
        end
      elsif line_stripped == 'BODYEND|' || line.include?('BODYEND|')
        in_body = false
      elsif in_body
        # Accumulate body text (preserve original line, not stripped)
        body_text << line.chomp
      elsif current_commit && !line_stripped.empty?
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
    if current_commit
      full_body = body_text.join("\n")
      current_commit[:ai_tools] = extract_ai_tools(full_body)
      @commits << current_commit
    end
  end

  # Extracts AI tools information from commit body text
  # Looks for patterns like "AI tool: Claude Code" or "AI tools: Cursor and Copilot"
  # Supports multiple tools separated by commas, "and", or "&"
  # @param body_text [String, nil] the commit message body text
  # @return [String, nil] normalized comma-separated AI tools (e.g., "CLAUDE CODE, CURSOR") or nil if none found
  def extract_ai_tools(body_text)
    return nil if body_text.nil? || body_text.strip.empty?

    # Look for patterns like "AI tool:", "AI tools:", etc. (case-insensitive)
    # Examples:
    #   **AI tool: Claude Code**
    #   **AI tools: Claude Code and Copilot**
    #   AI tool: Cursor and GitHub Copilot
    match = body_text.match(/\*{0,2}\s*AI\s+tools?\s*:\s*([^\n*]+)/i)
    return nil unless match

    tools_text = match[1].strip

    # Normalize tool names to uppercase
    # Split by common delimiters: "and", ",", "&"
    tools = tools_text.split(/\s+(?:and|&)\s+|,\s*/)
                      .map(&:strip)
                      .reject(&:empty?)
                      .map { |tool| normalize_tool_name(tool) }
                      .uniq

    tools.empty? ? nil : tools.join(', ')
  end

  # Normalizes AI tool names to standardized uppercase format
  # Maps common variations to consistent names (e.g., "Copilot" -> "GITHUB COPILOT")
  # @param tool [String] the raw tool name from commit message
  # @return [String] the normalized uppercase tool name
  def normalize_tool_name(tool)
    # Map common variations to standardized names
    tool_upper = tool.upcase

    # Handle common variations
    case tool_upper
    when /CLAUDE.*CODE/
      'CLAUDE CODE'
    when /GITHUB.*COPILOT/, /GH.*COPILOT/
      'GITHUB COPILOT'
    when /COPILOT/
      'GITHUB COPILOT'
    when /CURSOR/
      'CURSOR'
    when /CLAUDE/
      'CLAUDE'
    else
      tool_upper
    end
  end

  # Parses and converts a date string to ISO 8601 format
  # Falls back to returning the original string if parsing fails
  # @param date_str [String] the date string to parse (e.g., "2024-11-12 10:30:00 +0100")
  # @return [String] the ISO 8601 formatted date string (e.g., "2024-11-12T10:30:00+01:00")
  def parse_iso_date(date_str)
    # Convert to ISO 8601 format for JSON
    Time.parse(date_str).iso8601
  rescue ArgumentError
    date_str
  end

  # Writes the extracted commit data to a JSON output file
  # Creates the output directory if it doesn't exist
  # Includes repository metadata, summary statistics, and full commit details
  # @return [void]
  def write_output
    # Create output directory if it doesn't exist
    FileUtils.mkdir_p(File.dirname(@output_file))

    output_data = {
      repository: @repo_name,
      repository_path: File.expand_path(@repo_path),
      repository_description: @repo_description,
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

  # Prints a summary of the extraction results to stdout
  # Displays repository name, date range, commit count, output file path, and file size
  # @return [void]
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
        #{$PROGRAM_NAME} FROM_DATE TO_DATE OUTPUT_FILE [REPO_NAME] [REPO_PATH] [REPO_DESCRIPTION]

      Arguments:
        FROM_DATE         Start date (e.g., "2025-07-01" or "4 months ago")
        TO_DATE           End date (e.g., "2025-11-01" or "now")
        OUTPUT_FILE       Path to output JSON file (e.g., "data/repo1.json")
        REPO_NAME         Optional: Repository name (auto-detected if omitted)
        REPO_PATH         Optional: Path to git repository (default: current directory)
        REPO_DESCRIPTION  Optional: Repository description

      Examples:
        # Extract last 4 months from current repo
        #{$PROGRAM_NAME} "4 months ago" "now" "data/my-repo.json"

        # Extract specific date range from another repo
        #{$PROGRAM_NAME} "2025-07-01" "2025-11-01" "data/app1.json" "MyApp" "/path/to/repo"

        # Extract with custom repository name and description
        #{$PROGRAM_NAME} "1 year ago" "now" "data/exports/backend.json" "backend-api" "." "Backend API service"
    HELP
    exit(ARGV.include?('-h') || ARGV.include?('--help') ? 0 : 1)
  end

  from_date = ARGV[0]
  to_date = ARGV[1]
  output_file = ARGV[2]
  repo_name = ARGV[3]
  repo_path = ARGV[4] || '.'
  repo_description = ARGV[5]

  begin
    extractor = GitExtractor.new(from_date, to_date, output_file, repo_name, repo_path, repo_description)
    extractor.run
  rescue Interrupt
    puts "\n\nInterrupted by user"
    exit(1)
  rescue StandardError => e
    abort "Error: #{e.message}\n#{e.backtrace.join("\n")}"
  end
end
