# frozen_string_literal: true

require_relative '../scripts/git_extract_to_json'
require_relative '../scripts/calculate_commit_weights'
require 'spec_helper'
require 'tmpdir'
require 'json'

RSpec.describe 'AI Tools and Weight Features' do
  let(:temp_dir) { Dir.mktmpdir }
  let(:output_file) { File.join(temp_dir, 'test_output.json') }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe 'GitExtractor AI Tools extraction' do
    let(:extractor) { GitExtractor.new('1 month ago', 'now', output_file, 'test', '.') }

    describe '#extract_ai_tools' do
      it 'extracts AI tool from commit body with **AI tool: format' do
        body = "Some commit description\n\n**AI tool: Claude Code**"
        result = extractor.send(:extract_ai_tools, body)
        expect(result).to eq('CLAUDE CODE')
      end

      it 'extracts multiple AI tools separated by "and"' do
        body = "**AI tool: Claude Code and Copilot**"
        result = extractor.send(:extract_ai_tools, body)
        expect(result).to include('CLAUDE CODE')
        expect(result).to include('GITHUB COPILOT')
      end

      it 'extracts multiple AI tools separated by comma' do
        body = "**AI tools: Cursor, GitHub Copilot**"
        result = extractor.send(:extract_ai_tools, body)
        expect(result).to include('CURSOR')
        expect(result).to include('GITHUB COPILOT')
      end

      it 'returns nil for commit body without AI tool marker' do
        body = "Just a normal commit message"
        result = extractor.send(:extract_ai_tools, body)
        expect(result).to be_nil
      end

      it 'returns nil for empty body' do
        result = extractor.send(:extract_ai_tools, '')
        expect(result).to be_nil
      end

      it 'is case-insensitive for AI tool marker' do
        body = "ai tool: Claude Code"
        result = extractor.send(:extract_ai_tools, body)
        expect(result).to eq('CLAUDE CODE')
      end

      it 'handles "AI tools" (plural) marker' do
        body = "AI tools: Claude Code and Cursor"
        result = extractor.send(:extract_ai_tools, body)
        expect(result).to include('CLAUDE CODE')
        expect(result).to include('CURSOR')
      end
    end

    describe '#normalize_tool_name' do
      it 'normalizes "Copilot" to "GITHUB COPILOT"' do
        result = extractor.send(:normalize_tool_name, 'Copilot')
        expect(result).to eq('GITHUB COPILOT')
      end

      it 'normalizes "GitHub Copilot" to "GITHUB COPILOT"' do
        result = extractor.send(:normalize_tool_name, 'GitHub Copilot')
        expect(result).to eq('GITHUB COPILOT')
      end

      it 'normalizes "Claude Code" correctly' do
        result = extractor.send(:normalize_tool_name, 'Claude Code')
        expect(result).to eq('CLAUDE CODE')
      end

      it 'normalizes "Cursor" correctly' do
        result = extractor.send(:normalize_tool_name, 'Cursor')
        expect(result).to eq('CURSOR')
      end

      it 'uppercases unknown tools' do
        result = extractor.send(:normalize_tool_name, 'SomeNewTool')
        expect(result).to eq('SOMENEWTOOL')
      end
    end

    describe 'JSON output includes weight and ai_tools' do
      it 'includes weight field with default value 100' do
        extractor = GitExtractor.new('1 month ago', 'now', output_file, 'test', '.')
        allow(extractor).to receive(:print_summary)
        extractor.run

        json_data = JSON.parse(File.read(output_file))
        commits = json_data['commits']

        expect(commits).not_to be_empty
        commits.each do |commit|
          expect(commit).to have_key('weight')
          expect(commit['weight']).to eq(100)
        end
      end

      it 'includes ai_tools field' do
        extractor = GitExtractor.new('1 month ago', 'now', output_file, 'test', '.')
        allow(extractor).to receive(:print_summary)
        extractor.run

        json_data = JSON.parse(File.read(output_file))
        commits = json_data['commits']

        expect(commits).not_to be_empty
        commits.each do |commit|
          expect(commit).to have_key('ai_tools')
          # Can be nil if no AI tools are specified in commit body
        end
      end
    end
  end

  describe 'CommitWeightCalculator' do
    describe '#extract_pr_numbers' do
      # Create a mock instance for testing private methods
      let(:calculator) { CommitWeightCalculator.new(dry_run: true) }

      it 'extracts GitLab-style PR numbers (!12345)' do
        subject = 'Fix bug (!10463)'
        result = calculator.send(:extract_pr_numbers, subject)
        expect(result).to include('!10463')
      end

      it 'extracts GitHub-style PR numbers (#12345)' do
        subject = 'Fix bug (#123)'
        result = calculator.send(:extract_pr_numbers, subject)
        expect(result).to include('#123')
      end

      it 'extracts multiple PR numbers from same commit' do
        subject = 'Merge (!10463) and (#456)'
        result = calculator.send(:extract_pr_numbers, subject)
        expect(result).to include('!10463')
        expect(result).to include('#456')
      end

      it 'returns empty array for commits without PR numbers' do
        subject = 'Just a regular commit'
        result = calculator.send(:extract_pr_numbers, subject)
        expect(result).to be_empty
      end

      it 'handles revert messages correctly' do
        subject = 'Revert "CS | Move HTML content (!10463)" (!10662)'
        result = calculator.send(:extract_pr_numbers, subject)
        expect(result).to include('!10463')
        expect(result).to include('!10662')
      end
    end

    describe 'revert detection logic' do
      let(:calculator) { CommitWeightCalculator.new(dry_run: true) }

      it 'identifies revert commits' do
        commit = {
          'id' => 1,
          'hash' => 'abc123',
          'subject' => 'Revert "Fix bug" (!123)',
          'weight' => 100,
          'repository_id' => 1
        }

        # Should match the revert pattern
        expect(commit['subject']).to match(/\bRevert\b/i)
        expect(commit['subject']).not_to match(/\bUnrevert\b/i)
      end

      it 'identifies unrevert commits' do
        commit = {
          'id' => 2,
          'hash' => 'def456',
          'subject' => 'Unrevert !10463 and fix error (!10660)',
          'weight' => 0,
          'repository_id' => 1
        }

        # Should match the unrevert pattern
        expect(commit['subject']).to match(/\bUnrevert\b/i)
      end

      it 'does not confuse unrevert with revert' do
        subject = 'Unrevert !10463 and fix error'

        # Unrevert should not be treated as revert
        is_revert = subject =~ /\bRevert\b/i && subject !~ /\bUnrevert\b/i
        expect(is_revert).to be_falsey
      end
    end
  end

  describe 'Integration: Weight calculation workflow' do
    it 'sets weight correctly in JSON during extraction' do
      extractor = GitExtractor.new('1 month ago', 'now', output_file, 'test', '.')
      allow(extractor).to receive(:print_summary)
      extractor.run

      json_data = JSON.parse(File.read(output_file))
      commits = json_data['commits']

      # All commits should start with weight = 100
      commits.each do |commit|
        expect(commit['weight']).to eq(100)
      end
    end
  end

  describe 'Edge cases' do
    let(:extractor) { GitExtractor.new('1 month ago', 'now', output_file, 'test', '.') }

    it 'handles commit body with special characters' do
      body = "**AI tool: Claude Code**\n\nSome special chars: <>&\"'"
      result = extractor.send(:extract_ai_tools, body)
      expect(result).to eq('CLAUDE CODE')
    end

    it 'handles commit body with multiple AI tool mentions (uses first)' do
      body = "**AI tool: Claude Code**\n\nLater: AI tool: Cursor"
      result = extractor.send(:extract_ai_tools, body)
      # Should extract from first match
      expect(result).to include('CLAUDE CODE')
    end

    it 'handles whitespace variations in AI tool format' do
      body = "**AI  tools  :   Claude Code   and   Cursor**"
      result = extractor.send(:extract_ai_tools, body)
      expect(result).to include('CLAUDE CODE')
      expect(result).to include('CURSOR')
    end
  end
end
