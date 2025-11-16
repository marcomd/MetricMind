# frozen_string_literal: true

require 'spec_helper'
require_relative '../scripts/ai_categorize_commits'

RSpec.describe AICategorizeScript do
  let(:script) { AICategorizeScript.new }

  describe '#parse_date' do
    context 'with ISO date format' do
      it 'parses standard ISO date' do
        result = script.send(:parse_date, '2024-01-01')
        expect(result).to match(/^2024-01-01/)
      end

      it 'parses ISO date with time' do
        result = script.send(:parse_date, '2024-12-31')
        expect(result).to match(/^2024-12-31/)
      end
    end

    context 'with git-style dates' do
      it 'parses "now"' do
        result = script.send(:parse_date, 'now')
        expect(result).to match(/^\d{4}-\d{2}-\d{2}/)
      end

      it 'parses "6 months ago"' do
        result = script.send(:parse_date, '6 months ago')
        expect(result).to match(/^\d{4}-\d{2}-\d{2}/)
        # Should be approximately 6 months ago
        parsed_time = Time.parse(result)
        expect(parsed_time).to be < Time.now
      end

      it 'parses "1 year ago"' do
        result = script.send(:parse_date, '1 year ago')
        expect(result).to match(/^\d{4}-\d{2}-\d{2}/)
        parsed_time = Time.parse(result)
        expect(parsed_time).to be < Time.now
      end

      it 'parses "3 months ago"' do
        result = script.send(:parse_date, '3 months ago')
        expect(result).to match(/^\d{4}-\d{2}-\d{2}/)
      end
    end

    context 'with invalid date' do
      it 'exits with error for invalid format' do
        expect do
          script.send(:parse_date, 'invalid date')
        end.to raise_error(SystemExit)
      end
    end

    context 'with nil or empty date' do
      it 'returns nil for nil' do
        result = script.send(:parse_date, nil)
        expect(result).to be_nil
      end

      it 'returns nil for empty string' do
        result = script.send(:parse_date, '')
        expect(result).to be_nil
      end

      it 'returns nil for whitespace-only string' do
        result = script.send(:parse_date, '   ')
        expect(result).to be_nil
      end
    end
  end

  describe '#format_date_range' do
    context 'with both from and to dates' do
      let(:script_with_dates) do
        AICategorizeScript.new(from_date: '2024-01-01', to_date: '2024-12-31')
      end

      it 'formats both dates' do
        result = script_with_dates.send(:format_date_range)
        expect(result).to eq('2024-01-01 to 2024-12-31')
      end
    end

    context 'with only from date' do
      let(:script_with_from) do
        AICategorizeScript.new(from_date: '6 months ago')
      end

      it 'formats from date only' do
        result = script_with_from.send(:format_date_range)
        expect(result).to eq('from 6 months ago')
      end
    end

    context 'with only to date' do
      let(:script_with_to) do
        AICategorizeScript.new(to_date: 'now')
      end

      it 'formats to date only' do
        result = script_with_to.send(:format_date_range)
        expect(result).to eq('until now')
      end
    end

    context 'with no dates' do
      it 'returns all time' do
        result = script.send(:format_date_range)
        expect(result).to eq('all time')
      end
    end
  end

  describe 'initialization with date options' do
    context 'with valid dates' do
      let(:script_with_dates) do
        AICategorizeScript.new(from_date: '2024-01-01', to_date: '2024-12-31')
      end

      it 'parses and stores from_date' do
        from_date = script_with_dates.instance_variable_get(:@from_date)
        expect(from_date).to match(/^2024-01-01/)
      end

      it 'parses and stores to_date' do
        to_date = script_with_dates.instance_variable_get(:@to_date)
        expect(to_date).to match(/^2024-12-31/)
      end
    end

    context 'without dates' do
      it 'does not set from_date' do
        from_date = script.instance_variable_get(:@from_date)
        expect(from_date).to be_nil
      end

      it 'does not set to_date' do
        to_date = script.instance_variable_get(:@to_date)
        expect(to_date).to be_nil
      end
    end
  end

  describe 'SQL query building with date filters' do
    let(:mock_conn) { instance_double(PG::Connection) }
    let(:script_with_dates) do
      AICategorizeScript.new(from_date: '2024-01-01', to_date: '2024-12-31')
    end

    before do
      allow(mock_conn).to receive(:exec_params).and_return(
        instance_double(PG::Result, to_a: [])
      )
    end

    it 'includes commit_date in SELECT clause' do
      result = script_with_dates.send(:fetch_uncategorized_commits, mock_conn, 1)

      expect(mock_conn).to have_received(:exec_params) do |query, params|
        expect(query).to include('commit_date')
        expect(query).to include('commit_date >=')
        expect(query).to include('commit_date <=')
      end
    end

    it 'passes date parameters correctly' do
      script_with_dates.send(:fetch_uncategorized_commits, mock_conn, 1)

      expect(mock_conn).to have_received(:exec_params) do |query, params|
        expect(params.length).to eq(3) # repo_id, from_date, to_date
        expect(params[1]).to match(/^2024-01-01/)
        expect(params[2]).to match(/^2024-12-31/)
      end
    end
  end

  describe 'idempotent behavior' do
    let(:mock_conn) { instance_double(PG::Connection) }

    before do
      allow(mock_conn).to receive(:exec_params).and_return(
        instance_double(PG::Result, to_a: [])
      )
    end

    context 'without --force flag' do
      it 'only selects commits where category IS NULL' do
        script.send(:fetch_uncategorized_commits, mock_conn, 1)

        expect(mock_conn).to have_received(:exec_params) do |query, _params|
          expect(query).to include('category IS NULL')
        end
      end
    end

    context 'with --force flag' do
      let(:script_force) { AICategorizeScript.new(force: true) }

      it 'selects all commits regardless of category' do
        script_force.send(:fetch_uncategorized_commits, mock_conn, 1)

        expect(mock_conn).to have_received(:exec_params) do |query, _params|
          expect(query).not_to include('category IS NULL')
        end
      end
    end
  end

  describe 'ordering' do
    let(:mock_conn) { instance_double(PG::Connection) }

    before do
      allow(mock_conn).to receive(:exec_params).and_return(
        instance_double(PG::Result, to_a: [])
      )
    end

    it 'orders commits by commit_date DESC (newest first)' do
      script.send(:fetch_uncategorized_commits, mock_conn, 1)

      expect(mock_conn).to have_received(:exec_params) do |query, _params|
        expect(query).to include('ORDER BY commit_date DESC')
      end
    end
  end
end
