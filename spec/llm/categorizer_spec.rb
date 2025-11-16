# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/llm/categorizer'

RSpec.describe LLM::Categorizer do
  let(:mock_conn) { instance_double(PG::Connection) }
  let(:mock_client) { instance_double(LLM::OllamaClient) }
  let(:categorizer) { described_class.new(client: mock_client, conn: mock_conn) }

  describe '#initialize' do
    it 'initializes with provided client and connection' do
      expect(categorizer.client).to eq(mock_client)
      expect(categorizer.conn).to eq(mock_conn)
    end

    it 'initializes stats' do
      stats = categorizer.stats
      expect(stats[:processed]).to eq(0)
      expect(stats[:categorized]).to eq(0)
      expect(stats[:errors]).to eq(0)
      expect(stats[:new_categories]).to eq(0)
    end
  end

  describe '#fetch_existing_categories' do
    it 'fetches categories from database' do
      mock_result = instance_double(PG::Result)
      allow(mock_result).to receive(:map).and_return(%w[BILLING CS SECURITY])
      allow(mock_conn).to receive(:exec).with(/SELECT name FROM categories/).and_return(mock_result)

      categories = categorizer.fetch_existing_categories

      expect(categories).to eq(%w[BILLING CS SECURITY])
    end
  end

  describe '#save_category' do
    it 'inserts new category into database' do
      allow(mock_conn).to receive(:exec_params)
      allow(mock_conn).to receive(:cmd_tuples).and_return(1)

      result = categorizer.save_category('NEW_CATEGORY', description: 'Test category')

      expect(result).to be true
      expect(categorizer.stats[:new_categories]).to eq(1)
    end

    it 'does not increment counter if category already exists' do
      allow(mock_conn).to receive(:exec_params)
      allow(mock_conn).to receive(:cmd_tuples).and_return(0)

      result = categorizer.save_category('EXISTING')

      expect(result).to be true
      expect(categorizer.stats[:new_categories]).to eq(0)
    end

    it 'handles database errors gracefully' do
      allow(mock_conn).to receive(:exec_params).and_raise(PG::Error, 'Database error')

      result = categorizer.save_category('FAIL')

      expect(result).to be false
    end
  end

  describe '#update_commit' do
    it 'updates commit with category and confidence' do
      allow(mock_conn).to receive(:exec_params).twice

      result = categorizer.update_commit('abc123', 'BILLING', 90, 1)

      expect(result).to be true
    end

    it 'handles database errors' do
      allow(mock_conn).to receive(:exec_params).and_raise(PG::Error)

      result = categorizer.update_commit('abc123', 'BILLING', 90, 1)

      expect(result).to be false
    end
  end

  describe '#find_commit_in_json' do
    let(:json_data) do
      {
        'commits' => [
          { 'hash' => 'abc123', 'subject' => 'First commit' },
          { 'hash' => 'def456', 'subject' => 'Second commit' }
        ]
      }
    end

    it 'finds commit by hash' do
      commit = categorizer.find_commit_in_json(json_data, 'abc123')

      expect(commit).to eq({ 'hash' => 'abc123', 'subject' => 'First commit' })
    end

    it 'returns nil if commit not found' do
      commit = categorizer.find_commit_in_json(json_data, 'not_found')

      expect(commit).to be_nil
    end
  end

  describe '#categorize_commits' do
    let(:commits) do
      [
        { 'hash' => 'abc123', 'subject' => 'Fix billing bug', 'repository_id' => '1' },
        { 'hash' => 'def456', 'subject' => 'Update API docs', 'repository_id' => '1' }
      ]
    end

    let(:json_data) do
      {
        'commits' => [
          {
            'hash' => 'abc123',
            'subject' => 'Fix billing bug',
            'files' => [
              { 'filename' => 'app/services/billing.rb' }
            ]
          },
          {
            'hash' => 'def456',
            'subject' => 'Update API docs',
            'files' => [
              { 'filename' => 'docs/api.md' }
            ]
          }
        ]
      }
    end

    before do
      # Mock database operations
      allow(mock_conn).to receive(:transaction).and_yield
      allow(mock_conn).to receive(:exec_params)
      allow(mock_conn).to receive(:cmd_tuples).and_return(1)

      # Mock LLM responses
      allow(mock_client).to receive(:categorize).and_return(
        { category: 'BILLING', confidence: 90, reason: 'Billing service changes' }
      ).once

      allow(mock_client).to receive(:categorize).and_return(
        { category: 'DOCS', confidence: 85, reason: 'Documentation update' }
      ).once
    end

    it 'categorizes all commits' do
      categorizer.categorize_commits(commits, json_data)

      expect(categorizer.stats[:processed]).to eq(2)
      expect(categorizer.stats[:categorized]).to eq(2)
    end

    it 'creates new categories' do
      categorizer.categorize_commits(commits, json_data)

      expect(categorizer.stats[:new_categories]).to eq(2)
    end

    it 'handles LLM errors gracefully' do
      allow(mock_client).to receive(:categorize).and_raise(LLM::BaseClient::APIError, 'API error')

      categorizer.categorize_commits(commits, json_data)

      expect(categorizer.stats[:processed]).to eq(2)
      expect(categorizer.stats[:errors]).to eq(2)
    end

    it 'processes commits in batches' do
      expect(mock_conn).to receive(:transaction).once

      categorizer.categorize_commits(commits, json_data, batch_size: 10)
    end
  end

  describe '#close' do
    it 'closes database connection' do
      allow(mock_conn).to receive(:finished?).and_return(false)
      expect(mock_conn).to receive(:close)

      categorizer.close
    end

    it 'does not close if already finished' do
      allow(mock_conn).to receive(:finished?).and_return(true)
      expect(mock_conn).not_to receive(:close)

      categorizer.close
    end
  end
end
