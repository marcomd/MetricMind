# frozen_string_literal: true

require_relative '../scripts/git_extract_to_json'
require 'spec_helper'
require 'tmpdir'
require 'open3'

RSpec.describe GitExtractor do
  let(:temp_dir) { Dir.mktmpdir }
  let(:output_file) { File.join(temp_dir, 'output.json') }
  let(:from_date) { '2025-01-01' }
  let(:to_date) { '2025-12-31' }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  # Helper method to create a test git repository
  def create_test_git_repo(path)
    FileUtils.mkdir_p(path)
    Dir.chdir(path) do
      system('git init -q')
      system('git config user.name "Test User"')
      system('git config user.email "test@example.com"')

      # Use dates in the past that are reliable (2024)
      # Create initial commit
      File.write('README.md', "# Test Repo\n")
      system('git add README.md')
      system('GIT_AUTHOR_DATE="2024-06-01T10:00:00" GIT_COMMITTER_DATE="2024-06-01T10:00:00" git commit -q -m "Initial commit"')

      # Create second commit with multiple files
      File.write('file1.txt', "Line 1\nLine 2\nLine 3\n")
      system('git add file1.txt')
      system('GIT_AUTHOR_DATE="2024-06-02T10:00:00" GIT_COMMITTER_DATE="2024-06-02T10:00:00" git commit -q -m "Add file1"')

      # Create third commit with modifications
      File.write('file2.txt', "More content\n")
      File.write('file1.txt', "Line 1\nLine 2\n")  # Delete a line
      system('git add .')
      system('GIT_AUTHOR_DATE="2024-06-03T10:00:00" GIT_COMMITTER_DATE="2024-06-03T10:00:00" git commit -q -m "Add file2 and modify file1"')
    end
  end

  describe '#initialize' do
    it 'accepts required parameters' do
      extractor = described_class.new(from_date, to_date, output_file)
      expect(extractor).to be_a(GitExtractor)
    end

    it 'accepts optional repo_name and repo_path parameters' do
      extractor = described_class.new(from_date, to_date, output_file, 'test-repo', '.')
      expect(extractor).to be_a(GitExtractor)
    end

    it 'expands tilde in repo_path' do
      tilde_path = '~/test/path'
      extractor = described_class.new(from_date, to_date, output_file, 'test', tilde_path)

      # The path should be expanded to the home directory
      expect(extractor.instance_variable_get(:@repo_path)).to eq(File.expand_path(tilde_path))
      expect(extractor.instance_variable_get(:@repo_path)).not_to include('~')
    end

    it 'expands tilde in output_file' do
      tilde_output = '~/output/data.json'
      extractor = described_class.new(from_date, to_date, tilde_output, 'test', '.')

      expect(extractor.instance_variable_get(:@output_file)).to eq(File.expand_path(tilde_output))
      expect(extractor.instance_variable_get(:@output_file)).not_to include('~')
    end
  end

  describe '#run' do
    context 'with a valid git repository' do
      it 'creates output file' do
        extractor = described_class.new('1 month ago', 'now', output_file, 'test', '.')

        # Suppress output during test
        allow(extractor).to receive(:print_summary)

        expect { extractor.run }.not_to raise_error
        expect(File.exist?(output_file)).to be true
      end

      it 'generates valid JSON' do
        extractor = described_class.new('1 month ago', 'now', output_file, 'test', '.')

        allow(extractor).to receive(:print_summary)
        extractor.run

        json_data = JSON.parse(File.read(output_file))
        expect(json_data).to have_key('repository')
        expect(json_data).to have_key('extraction_date')
        expect(json_data).to have_key('date_range')
        expect(json_data).to have_key('summary')
        expect(json_data).to have_key('commits')
      end

      it 'includes correct date range in output' do
        extractor = described_class.new(from_date, to_date, output_file, 'test', '.')

        allow(extractor).to receive(:print_summary)
        extractor.run

        json_data = JSON.parse(File.read(output_file))
        expect(json_data['date_range']['from']).to eq(from_date)
        expect(json_data['date_range']['to']).to eq(to_date)
      end

      it 'includes summary statistics' do
        extractor = described_class.new('1 month ago', 'now', output_file, 'test', '.')

        allow(extractor).to receive(:print_summary)
        extractor.run

        json_data = JSON.parse(File.read(output_file))
        summary = json_data['summary']

        expect(summary).to have_key('total_commits')
        expect(summary).to have_key('total_lines_added')
        expect(summary).to have_key('total_lines_deleted')
        expect(summary).to have_key('total_files_changed')
        expect(summary).to have_key('unique_authors')

        expect(summary['total_commits']).to be >= 0
        expect(summary['total_lines_added']).to be >= 0
        expect(summary['total_lines_deleted']).to be >= 0
      end

      it 'includes commit details with required fields' do
        extractor = described_class.new('1 month ago', 'now', output_file, 'test', '.')

        allow(extractor).to receive(:print_summary)
        extractor.run

        json_data = JSON.parse(File.read(output_file))
        commits = json_data['commits']

        if commits.any?
          first_commit = commits.first

          expect(first_commit).to have_key('hash')
          expect(first_commit).to have_key('date')
          expect(first_commit).to have_key('author_name')
          expect(first_commit).to have_key('author_email')
          expect(first_commit).to have_key('subject')
          expect(first_commit).to have_key('lines_added')
          expect(first_commit).to have_key('lines_deleted')
          expect(first_commit).to have_key('files_changed')
          expect(first_commit).to have_key('files')

          expect(first_commit['hash']).to be_a(String)
          expect(first_commit['hash'].length).to eq(40)
          expect(first_commit['lines_added']).to be >= 0
          expect(first_commit['lines_deleted']).to be >= 0
          expect(first_commit['files_changed']).to be >= 0
        end
      end
    end

    context 'with a test git repository' do
      let(:test_repo_dir) { File.join(temp_dir, 'test-repo') }

      before do
        create_test_git_repo(test_repo_dir)
      end

      it 'extracts all commits correctly' do
        extractor = described_class.new('2024-05-01', '2024-07-01', output_file, 'test', test_repo_dir)

        allow(extractor).to receive(:print_summary)
        extractor.run

        json_data = JSON.parse(File.read(output_file))

        expect(json_data['summary']['total_commits']).to eq(3)
        expect(json_data['commits'].length).to eq(3)
      end

      it 'calculates line changes correctly' do
        extractor = described_class.new('2024-05-01', '2024-07-01', output_file, 'test', test_repo_dir)

        allow(extractor).to receive(:print_summary)
        extractor.run

        json_data = JSON.parse(File.read(output_file))

        # Verify summary totals
        expect(json_data['summary']['total_lines_added']).to be > 0
        expect(json_data['summary']['total_files_changed']).to eq(4) # README + file1 + file2 + file1 again
      end

      it 'includes file-level details' do
        extractor = described_class.new('2024-05-01', '2024-07-01', output_file, 'test', test_repo_dir)

        allow(extractor).to receive(:print_summary)
        extractor.run

        json_data = JSON.parse(File.read(output_file))
        commits = json_data['commits']

        # Check that commits have file details
        commit_with_files = commits.find { |c| c['files_changed'] > 0 }
        expect(commit_with_files).not_to be_nil
        expect(commit_with_files['files']).to be_an(Array)
        expect(commit_with_files['files'].first).to have_key('filename')
        expect(commit_with_files['files'].first).to have_key('added')
        expect(commit_with_files['files'].first).to have_key('deleted')
      end

      it 'detects unique authors' do
        extractor = described_class.new('2024-05-01', '2024-07-01', output_file, 'test', test_repo_dir)

        allow(extractor).to receive(:print_summary)
        extractor.run

        json_data = JSON.parse(File.read(output_file))

        expect(json_data['summary']['unique_authors']).to eq(1)
      end

      it 'preserves pipe characters in commit subjects' do
        # Create a commit with a pipe character in the subject
        Dir.chdir(test_repo_dir) do
          File.write('file3.txt', "Test content\n")
          system('git add file3.txt')
          commit_message = 'Revert "CS | Move HTML content from language-dependent configurations to banner structure (!10463)" (!10662)'
          system("GIT_AUTHOR_DATE=\"2024-06-04T10:00:00\" GIT_COMMITTER_DATE=\"2024-06-04T10:00:00\" git commit -q -m '#{commit_message}'")
        end

        extractor = described_class.new('2024-05-01', '2024-07-01', output_file, 'test', test_repo_dir)

        allow(extractor).to receive(:print_summary)
        extractor.run

        json_data = JSON.parse(File.read(output_file))

        # Find the commit with the pipe in the subject
        commit_with_pipe = json_data['commits'].find do |c|
          c['subject']&.include?('Revert')
        end

        expect(commit_with_pipe).not_to be_nil
        # The full subject should be preserved, including the pipe character
        expect(commit_with_pipe['subject']).to eq('Revert "CS | Move HTML content from language-dependent configurations to banner structure (!10463)" (!10662)')
        # Make sure it's not truncated at the pipe
        expect(commit_with_pipe['subject']).to include('Move HTML')
        expect(commit_with_pipe['subject']).to include('(!10662)')
      end
    end

    context 'with invalid repository' do
      it 'raises error when not in a git repository' do
        non_git_dir = File.join(temp_dir, 'not-a-repo')
        FileUtils.mkdir_p(non_git_dir)

        extractor = described_class.new(from_date, to_date, output_file, 'test', non_git_dir)

        expect { extractor.run }.to raise_error(SystemExit)
      end

      it 'raises error when repository path does not exist' do
        non_existent = File.join(temp_dir, 'does-not-exist')

        extractor = described_class.new(from_date, to_date, output_file, 'test', non_existent)

        expect { extractor.run }.to raise_error(SystemExit)
      end
    end

    context 'with no commits in range' do
      it 'creates output file with empty commits array' do
        # Use a date range far in the past where there are no commits
        extractor = described_class.new('1900-01-01', '1900-12-31', output_file, 'test', '.')

        allow(extractor).to receive(:print_summary)
        allow(extractor).to receive(:warn) # Suppress warning

        extractor.run

        json_data = JSON.parse(File.read(output_file))
        expect(json_data['commits']).to be_empty
        expect(json_data['summary']['total_commits']).to eq(0)
        expect(json_data['summary']['total_lines_added']).to eq(0)
        expect(json_data['summary']['total_lines_deleted']).to eq(0)
      end
    end

    context 'with relative date ranges' do
      it 'accepts "N months ago" format' do
        extractor = described_class.new('3 months ago', 'now', output_file, 'test', '.')

        allow(extractor).to receive(:print_summary)

        expect { extractor.run }.not_to raise_error
      end

      it 'accepts "now" as to_date' do
        extractor = described_class.new('1 week ago', 'now', output_file, 'test', '.')

        allow(extractor).to receive(:print_summary)

        expect { extractor.run }.not_to raise_error
      end
    end
  end

  describe 'output file structure' do
    it 'creates parent directories if they do not exist' do
      nested_output = File.join(temp_dir, 'data', 'exports', 'output.json')
      extractor = described_class.new('1 month ago', 'now', nested_output, 'test', '.')

      allow(extractor).to receive(:print_summary)
      extractor.run

      expect(File.exist?(nested_output)).to be true
    end

    it 'generates properly formatted ISO 8601 dates' do
      extractor = described_class.new('1 month ago', 'now', output_file, 'test', '.')

      allow(extractor).to receive(:print_summary)
      extractor.run

      json_data = JSON.parse(File.read(output_file))

      # Check extraction_date is valid ISO 8601
      expect(json_data['extraction_date']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)

      # Check commit dates are valid ISO 8601 if commits exist
      if json_data['commits'].any?
        expect(json_data['commits'].first['date']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end
    end

    it 'includes repository path in output' do
      extractor = described_class.new('1 month ago', 'now', output_file, 'test', '.')

      allow(extractor).to receive(:print_summary)
      extractor.run

      json_data = JSON.parse(File.read(output_file))

      expect(json_data).to have_key('repository_path')
      expect(json_data['repository_path']).to be_a(String)
    end
  end

  describe 'error handling' do
    it 'handles unusual date formats gracefully' do
      extractor = described_class.new('invalid-date', 'also-invalid', output_file, 'test', '.')

      allow(extractor).to receive(:print_summary)
      allow(extractor).to receive(:warn) # Suppress warning

      # Git accepts these as valid dates (resulting in no commits)
      expect { extractor.run }.not_to raise_error

      json_data = JSON.parse(File.read(output_file))
      expect(json_data['commits']).to be_empty
    end
  end

  describe '#extract_diff' do
    let(:test_repo_dir) { File.join(temp_dir, 'test-repo') }

    before do
      create_test_git_repo(test_repo_dir)
    end

    it 'extracts git diff for a commit' do
      extractor = described_class.new('2024-05-01', '2024-07-01', output_file, 'test', test_repo_dir)

      # Get the hash of the second commit
      commit_hash = Dir.chdir(test_repo_dir) do
        `git log --format=%H --skip=1 --max-count=1`.strip
      end

      diff_result = extractor.send(:extract_diff, commit_hash)

      expect(diff_result).to be_a(Hash)
      expect(diff_result).to have_key(:content)
      expect(diff_result).to have_key(:truncated)
      expect(diff_result[:content]).to include('diff --git')
      expect(diff_result[:content]).to include('file1.txt')
      expect(diff_result[:truncated]).to be false
    end

    it 'truncates large diffs to 10KB' do
      extractor = described_class.new('2024-05-01', '2024-07-01', output_file, 'test', test_repo_dir)

      # Create a commit with a large diff
      large_content = 'x' * 15_000
      commit_hash = Dir.chdir(test_repo_dir) do
        File.write('large_file.txt', large_content)
        system('git add large_file.txt')
        system('GIT_AUTHOR_DATE="2024-06-05T10:00:00" GIT_COMMITTER_DATE="2024-06-05T10:00:00" git commit -q -m "Add large file"')
        `git log --format=%H --max-count=1`.strip
      end

      diff_result = extractor.send(:extract_diff, commit_hash)

      expect(diff_result[:content].bytesize).to be <= 10_240
      expect(diff_result[:truncated]).to be true
    end

    it 'returns nil for invalid commit hash' do
      extractor = described_class.new('2024-05-01', '2024-07-01', output_file, 'test', test_repo_dir)

      diff_result = extractor.send(:extract_diff, 'invalid_hash_12345')

      expect(diff_result).to be_nil
    end
  end

  describe 'AI-integrated extraction' do
    let(:test_repo_dir) { File.join(temp_dir, 'test-repo') }

    before do
      create_test_git_repo(test_repo_dir)
    end

    context 'when AI_PROVIDER is set' do
      before do
        ENV['AI_PROVIDER'] = 'ollama'
        ENV['OLLAMA_URL'] = 'http://localhost:11434'
        ENV['OLLAMA_MODEL'] = 'llama2'
      end

      after do
        ENV.delete('AI_PROVIDER')
        ENV.delete('OLLAMA_URL')
        ENV.delete('OLLAMA_MODEL')
      end

      it 'includes category, confidence, and description in JSON output' do
        extractor = described_class.new('2024-05-01', '2024-07-01', output_file, 'test', test_repo_dir)

        # Mock the AI categorization to avoid actual LLM calls
        mock_ai_result = {
          category: 'DEVELOPMENT',
          confidence: 85,
          description: 'Added initial project setup with README documentation.'
        }

        allow(extractor).to receive(:categorize_with_ai).and_return(mock_ai_result)
        allow(extractor).to receive(:print_summary)

        extractor.run

        json_data = JSON.parse(File.read(output_file))
        commits = json_data['commits']

        expect(commits).not_to be_empty
        first_commit = commits.first

        expect(first_commit).to have_key('category')
        expect(first_commit).to have_key('ai_confidence')
        expect(first_commit).to have_key('description')
        expect(first_commit['category']).to eq('DEVELOPMENT')
        expect(first_commit['ai_confidence']).to eq(85)
        expect(first_commit['description']).to eq('Added initial project setup with README documentation.')
      end

      it 'handles AI categorization failures gracefully' do
        extractor = described_class.new('2024-05-01', '2024-07-01', output_file, 'test', test_repo_dir)

        # Mock AI failure
        allow(extractor).to receive(:categorize_with_ai).and_raise(StandardError, 'LLM unavailable')
        allow(extractor).to receive(:print_summary)
        allow(extractor).to receive(:warn) # Suppress warning

        expect { extractor.run }.not_to raise_error

        json_data = JSON.parse(File.read(output_file))
        commits = json_data['commits']

        expect(commits).not_to be_empty
        first_commit = commits.first

        # When AI fails, category and description should be nil
        expect(first_commit['category']).to be_nil
        expect(first_commit['ai_confidence']).to be_nil
        expect(first_commit['description']).to be_nil
      end

      it 'calls AI for description and business_impact even when pattern matching finds category' do
        # Create a test repo with a commit that has a pattern-matchable category
        temp_dir = Dir.mktmpdir
        system("git init #{temp_dir} > /dev/null 2>&1")
        Dir.chdir(temp_dir) do
          File.write('test.txt', 'content')
          system('git add test.txt > /dev/null 2>&1')
          system('git config user.email "test@example.com"')
          system('git config user.name "Test User"')
          # Commit with pattern-matchable category (pipe delimiter)
          system('git commit -m "BILLING | Fix payment processing bug" > /dev/null 2>&1')
        end

        output = File.join(temp_dir, 'output.json')
        extractor = described_class.new('1 day ago', 'now', output, 'test', temp_dir)

        # Mock AI to return description and business_impact
        mock_ai_result = {
          category: 'BILLING', # AI might return same category
          confidence: 90,
          business_impact: 95,
          description: 'Fixed critical bug in payment processing that was causing transaction failures.'
        }

        # Expect AI to be called even though pattern matching found category
        expect(extractor).to receive(:categorize_with_ai).once.and_return(mock_ai_result)
        allow(extractor).to receive(:print_summary)

        extractor.run

        json_data = JSON.parse(File.read(output))
        commits = json_data['commits']

        expect(commits).not_to be_empty
        commit = commits.first

        # Pattern matching should find BILLING
        expect(commit['category']).to eq('BILLING')

        # AI should still be called to provide these fields
        expect(commit['description']).to eq('Fixed critical bug in payment processing that was causing transaction failures.')
        expect(commit['business_impact']).to eq(95)
        expect(commit['ai_confidence']).to eq(90)
        expect(commit['weight']).to eq(95) # Should use business_impact as weight

        FileUtils.rm_rf(temp_dir)
      end
    end

    context 'when AI_PROVIDER is not set' do
      before do
        ENV.delete('AI_PROVIDER')
      end

      it 'extracts commits without AI categorization' do
        extractor = described_class.new('2024-05-01', '2024-07-01', output_file, 'test', test_repo_dir)

        allow(extractor).to receive(:print_summary)

        extractor.run

        json_data = JSON.parse(File.read(output_file))
        commits = json_data['commits']

        expect(commits).not_to be_empty
        first_commit = commits.first

        # Without AI, category and description should be nil
        expect(first_commit['category']).to be_nil
        expect(first_commit['ai_confidence']).to be_nil
        expect(first_commit['description']).to be_nil
      end
    end

    context 'with --skip-ai flag' do
      it 'skips AI processing when flag is present' do
        extractor = described_class.new('2024-05-01', '2024-07-01', output_file, 'test', test_repo_dir, nil, skip_ai: true)

        allow(extractor).to receive(:print_summary)

        extractor.run

        json_data = JSON.parse(File.read(output_file))
        commits = json_data['commits']

        expect(commits).not_to be_empty
        first_commit = commits.first

        # With --skip-ai flag, category and description should be nil
        expect(first_commit['category']).to be_nil
        expect(first_commit['ai_confidence']).to be_nil
        expect(first_commit['description']).to be_nil
      end
    end
  end
end
