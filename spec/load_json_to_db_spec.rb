# frozen_string_literal: true

require_relative '../scripts/load_json_to_db'
require 'spec_helper'
require 'tmpdir'
require 'json'

RSpec.describe DataLoader do
  let(:temp_dir) { Dir.mktmpdir }
  let(:json_file) { File.join(temp_dir, 'test_data.json') }
  let(:test_data) do
    {
      'repository' => 'test-repo',
      'repository_path' => '/path/to/repo',
      'extraction_date' => '2025-11-07T10:00:00Z',
      'date_range' => {
        'from' => '6 months ago',
        'to' => 'now'
      },
      'summary' => {
        'total_commits' => 2,
        'total_lines_added' => 100,
        'total_lines_deleted' => 50,
        'total_files_changed' => 5,
        'unique_authors' => 1
      },
      'commits' => [
        {
          'hash' => 'abc123' * 7,  # 40 character hash
          'date' => '2025-10-01T10:00:00Z',
          'author_name' => 'Test User',
          'author_email' => 'test@example.com',
          'subject' => 'First commit',
          'lines_added' => 50,
          'lines_deleted' => 20,
          'files_changed' => 3,
          'files' => []
        },
        {
          'hash' => 'def456' * 7,  # 40 character hash
          'date' => '2025-10-02T10:00:00Z',
          'author_name' => 'Test User',
          'author_email' => 'test@example.com',
          'subject' => 'Second commit',
          'lines_added' => 50,
          'lines_deleted' => 30,
          'files_changed' => 2,
          'files' => []
        }
      ]
    }
  end

  let(:mock_conn) { instance_double(PG::Connection) }
  let(:mock_result) { instance_double(PG::Result) }

  before do
    File.write(json_file, JSON.pretty_generate(test_data))
    allow(PG).to receive(:connect).and_return(mock_conn)
    allow(mock_conn).to receive(:close)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#initialize' do
    it 'accepts json_file parameter' do
      loader = described_class.new(json_file)
      expect(loader).to be_a(DataLoader)
    end

    it 'accepts optional db_config parameter' do
      db_config = { host: 'localhost', dbname: 'test_db' }
      loader = described_class.new(json_file, db_config)
      expect(loader).to be_a(DataLoader)
    end

    it 'uses environment variables for default config' do
      ENV['PGHOST'] = 'testhost'
      ENV['PGDATABASE'] = 'testdb'

      loader = described_class.new(json_file)
      config = loader.instance_variable_get(:@db_config)

      expect(config[:host]).to eq('testhost')
      expect(config[:dbname]).to eq('testdb')

      ENV.delete('PGHOST')
      ENV.delete('PGDATABASE')
    end
  end

  describe '#run' do
    context 'with valid JSON file' do
      before do
        # Mock database operations
        allow(mock_conn).to receive(:exec)
        allow(mock_conn).to receive(:exec_params).and_return(mock_result)
        allow(mock_conn).to receive(:prepare)
        allow(mock_conn).to receive(:exec_prepared).and_return(mock_result)
        allow(mock_result).to receive(:ntuples).and_return(1)
        allow(mock_result).to receive(:[]).and_return({ 'id' => '1', 'count' => '2' })
      end

      it 'loads data without errors' do
        loader = described_class.new(json_file)

        # Suppress output
        allow(loader).to receive(:puts)
        allow(loader).to receive(:print)

        expect { loader.run }.not_to raise_error
      end

      it 'connects to database' do
        loader = described_class.new(json_file)

        allow(loader).to receive(:puts)
        allow(loader).to receive(:print)

        expect(PG).to receive(:connect)

        loader.run
      end

      it 'begins and commits transaction' do
        loader = described_class.new(json_file)

        allow(loader).to receive(:puts)
        allow(loader).to receive(:print)

        expect(mock_conn).to receive(:exec).with('BEGIN')
        expect(mock_conn).to receive(:exec).with('COMMIT')

        loader.run
      end

      it 'creates or updates repository' do
        loader = described_class.new(json_file)

        allow(loader).to receive(:puts)
        allow(loader).to receive(:print)

        expect(mock_conn).to receive(:exec_params).with(
          /SELECT id FROM repositories/,
          ['test-repo']
        ).and_return(mock_result)

        loader.run
      end

      it 'inserts commits' do
        loader = described_class.new(json_file)

        allow(loader).to receive(:puts)
        allow(loader).to receive(:print)

        # Expect prepare statement
        expect(mock_conn).to receive(:prepare).with('insert_commit', /INSERT INTO commits/)

        # Expect commits to be inserted
        expect(mock_conn).to receive(:exec_prepared).at_least(:twice)

        loader.run
      end

      it 'tracks statistics' do
        loader = described_class.new(json_file)

        allow(loader).to receive(:puts)
        allow(loader).to receive(:print)

        loader.run

        stats = loader.instance_variable_get(:@stats)
        expect(stats[:commits_inserted]).to be >= 0
        expect(stats[:commits_skipped]).to be >= 0
      end
    end

    context 'with missing JSON file' do
      it 'raises error' do
        loader = described_class.new('/nonexistent/file.json')

        expect { loader.run }.to raise_error(SystemExit)
      end
    end

    context 'with invalid JSON' do
      let(:bad_json_file) { File.join(temp_dir, 'bad.json') }

      before do
        File.write(bad_json_file, 'not valid json {{{')
      end

      it 'raises error for invalid JSON' do
        loader = described_class.new(bad_json_file)

        expect { loader.run }.to raise_error(SystemExit)
      end
    end

    context 'with missing required fields' do
      let(:incomplete_data) do
        { 'repository' => 'test' }  # Missing commits
      end

      before do
        File.write(json_file, JSON.pretty_generate(incomplete_data))
      end

      it 'raises error for missing fields' do
        loader = described_class.new(json_file)

        expect { loader.run }.to raise_error(SystemExit)
      end
    end

    context 'with database connection error' do
      before do
        allow(PG).to receive(:connect).and_raise(PG::Error.new('Connection failed'))
      end

      it 'handles database connection errors' do
        loader = described_class.new(json_file)

        expect { loader.run }.to raise_error(SystemExit)
      end
    end

    context 'with database error during transaction' do
      before do
        allow(mock_conn).to receive(:exec).with('BEGIN')
        allow(mock_conn).to receive(:exec).with('ROLLBACK')
        allow(mock_conn).to receive(:exec_params).and_raise(PG::Error.new('Database error'))
      end

      it 'rolls back transaction on error' do
        loader = described_class.new(json_file)

        allow(loader).to receive(:puts)
        allow(loader).to receive(:print)

        expect(mock_conn).to receive(:exec).with('ROLLBACK')

        expect { loader.run }.to raise_error(PG::Error)
      end
    end
  end

  describe 'duplicate handling' do
    before do
      # Mock for existing commit (returns 0 tuples on duplicate)
      allow(mock_conn).to receive(:exec)

      # Mock exec_params for SELECT query (repository check)
      repo_result = instance_double(PG::Result)
      allow(repo_result).to receive(:ntuples).and_return(1)
      allow(repo_result).to receive(:[]).and_return({ 'id' => '1', 'count' => '2' })
      allow(mock_conn).to receive(:exec_params).and_return(repo_result)

      allow(mock_conn).to receive(:prepare)

      # First insert succeeds, second is duplicate
      allow(mock_conn).to receive(:exec_prepared) do
        @insert_count ||= 0
        @insert_count += 1
        result = instance_double(PG::Result)
        allow(result).to receive(:ntuples).and_return(@insert_count == 1 ? 1 : 0)
        result
      end
    end

    it 'tracks duplicate commits separately' do
      loader = described_class.new(json_file)

      allow(loader).to receive(:puts)
      allow(loader).to receive(:print)

      loader.run

      stats = loader.instance_variable_get(:@stats)
      expect(stats[:commits_inserted] + stats[:commits_skipped]).to eq(2)
    end
  end

  describe 'materialized view refresh' do
    before do
      allow(mock_conn).to receive(:exec)
      allow(mock_conn).to receive(:exec_params).and_return(mock_result)
      allow(mock_conn).to receive(:prepare)
      allow(mock_conn).to receive(:exec_prepared).and_return(mock_result)
      allow(mock_result).to receive(:ntuples).and_return(1)
      allow(mock_result).to receive(:[]).and_return({ 'id' => '1', 'count' => '2' })
    end

    it 'attempts to refresh materialized views' do
      loader = described_class.new(json_file)

      allow(loader).to receive(:puts)
      allow(loader).to receive(:print)

      expect(mock_conn).to receive(:exec).with(/REFRESH MATERIALIZED VIEW/)

      loader.run
    end

    it 'handles refresh errors gracefully' do
      loader = described_class.new(json_file)

      allow(loader).to receive(:puts)
      allow(loader).to receive(:print)
      allow(loader).to receive(:warn)

      allow(mock_conn).to receive(:exec).with(/REFRESH MATERIALIZED VIEW/)
        .and_raise(PG::Error.new('View does not exist'))

      expect { loader.run }.not_to raise_error
    end
  end

  describe 'path handling' do
    it 'expands tilde in JSON file path' do
      tilde_path = '~/test/data.json'
      expanded_path = File.expand_path(tilde_path)

      # Don't actually run, just check initialization
      loader = described_class.new(tilde_path)

      expect(loader.instance_variable_get(:@json_file)).to eq(expanded_path)
    end
  end
end
