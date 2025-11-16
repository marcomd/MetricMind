# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/llm/ollama_client'
require_relative '../../lib/llm/categorizer'
require 'socket'

RSpec.describe 'AI Categorization Integration', :integration do
  # Helper to check if Ollama is running
  def ollama_available?
    TCPSocket.new('localhost', 11434).close
    true
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError
    false
  end

  before do
    skip 'Ollama is not running on localhost:11434' unless ollama_available?

    ENV['OLLAMA_URL'] = 'http://localhost:11434'
    ENV['OLLAMA_MODEL'] = 'llama3.2' # or 'llama2' depending on what's installed
    ENV['OLLAMA_TEMPERATURE'] = '0.1'
    ENV['AI_TIMEOUT'] = '60' # Give it more time for integration test
  end

  after do
    ENV.delete('OLLAMA_URL')
    ENV.delete('OLLAMA_MODEL')
    ENV.delete('OLLAMA_TEMPERATURE')
    ENV.delete('AI_TIMEOUT')
  end

  describe 'OllamaClient real API call' do
    let(:client) { LLM::OllamaClient.new }

    it 'successfully categorizes a commit with clear category' do
      commit_data = {
        hash: 'test123',
        subject: 'Fix payment processing error in billing service',
        files: [
          'app/services/billing/payment_processor.rb',
          'app/jobs/billing/invoice_generator_job.rb',
          'spec/services/billing/payment_processor_spec.rb'
        ]
      }

      existing_categories = %w[BILLING CS SECURITY API DATABASE]

      result = client.categorize(commit_data, existing_categories)

      # Verify structure
      expect(result).to have_key(:category)
      expect(result).to have_key(:confidence)
      expect(result).to have_key(:reason)

      # Verify types
      expect(result[:category]).to be_a(String)
      expect(result[:confidence]).to be_a(Integer)
      expect(result[:reason]).to be_a(String)

      # Verify values
      expect(result[:category]).to eq('BILLING') # Should pick the existing category
      expect(result[:confidence]).to be_between(0, 100)
      expect(result[:reason]).not_to be_empty

      puts "\n[Integration Test] Ollama Response:"
      puts "  Category: #{result[:category]} (#{result[:confidence]}%)"
      puts "  Reason: #{result[:reason]}"
    end

    it 'creates appropriate new category when none match' do
      commit_data = {
        hash: 'test456',
        subject: 'Add Dockerfile for containerization',
        files: [
          'Dockerfile',
          'docker-compose.yml',
          '.dockerignore'
        ]
      }

      existing_categories = %w[BILLING CS SECURITY API]

      result = client.categorize(commit_data, existing_categories)

      expect(result[:category]).to be_a(String)
      expect(result[:category].length).to be >= 2
      expect(result[:category]).to match(/^[A-Z]/) # Should start with letter

      # Should NOT be a numeric category
      expect(result[:category]).not_to match(/^\d/)
      expect(result[:category]).not_to match(/^#\d/)
      expect(result[:category]).not_to match(/^\d+\.\d+/)

      puts "\n[Integration Test] New Category Created:"
      puts "  Category: #{result[:category]} (#{result[:confidence]}%)"
      puts "  Reason: #{result[:reason]}"
    end

    it 'rejects numeric categories even if LLM suggests them' do
      # This test verifies validation works end-to-end
      commit_data = {
        hash: 'test789',
        subject: 'Release version 2.58.0',
        files: ['CHANGELOG.md', 'package.json']
      }

      existing_categories = ['2.57.0', '2.58.0', 'RELEASE'] # Include bad categories

      # The LLM might try to suggest a version number
      # But our validation should catch it
      begin
        result = client.categorize(commit_data, existing_categories)

        # If we get here, verify it's a valid category
        expect(result[:category]).not_to match(/^\d+\.\d+/)
        expect(result[:category]).not_to match(/^#\d+/)

        puts "\n[Integration Test] LLM correctly avoided numeric category:"
        puts "  Category: #{result[:category]}"
      rescue LLM::BaseClient::APIError => e
        # This is also acceptable - validation rejected the response
        expect(e.message).to include('Invalid category')
        puts "\n[Integration Test] Validation correctly rejected numeric category"
      end
    end

    it 'handles commits with minimal information' do
      commit_data = {
        hash: 'testabc',
        subject: 'Update README',
        files: []
      }

      existing_categories = %w[DOCS BILLING API]

      result = client.categorize(commit_data, existing_categories)

      expect(result[:category]).to be_a(String)
      expect(result[:confidence]).to be_between(0, 100)

      puts "\n[Integration Test] Minimal Info Response:"
      puts "  Category: #{result[:category]} (#{result[:confidence]}%)"
    end
  end

  describe 'Full categorization workflow' do
    let(:test_db) { ENV['PGDATABASE_TEST'] || 'git_analytics_test' }
    let(:conn) { PG.connect(dbname: test_db) }
    let(:client) { LLM::OllamaClient.new }
    let(:categorizer) { LLM::Categorizer.new(client: client, conn: conn) }

    after do
      categorizer&.close
    end

    it 'performs end-to-end categorization with database' do
      # Set up test data
      conn.exec('INSERT INTO repositories (name) VALUES ($1) ON CONFLICT DO NOTHING', ['test-repo'])
      repo_result = conn.exec("SELECT id FROM repositories WHERE name = 'test-repo'")
      repo_id = repo_result[0]['id']

      # Insert test commit
      conn.exec(
        'INSERT INTO commits (repository_id, hash, commit_date, author_name, author_email, subject, files_changed)
         VALUES ($1, $2, NOW(), $3, $4, $5, 1)
         ON CONFLICT (repository_id, hash) DO NOTHING',
        [repo_id, 'integration_test_hash', 'Test Author', 'test@example.com', 'Fix billing calculation']
      )

      commits = [
        {
          'hash' => 'integration_test_hash',
          'subject' => 'Fix billing calculation',
          'repository_id' => repo_id
        }
      ]

      json_data = {
        'commits' => [
          {
            'hash' => 'integration_test_hash',
            'files' => [
              { 'filename' => 'app/services/billing/calculator.rb' }
            ]
          }
        ]
      }

      categorizer.categorize_commits(commits, json_data, batch_size: 10)

      expect(categorizer.stats[:processed]).to eq(1)
      expect(categorizer.stats[:categorized]).to eq(1)

      # Verify database was updated
      result = conn.exec(
        'SELECT category, ai_confidence FROM commits WHERE hash = $1 AND repository_id = $2',
        ['integration_test_hash', repo_id]
      )

      expect(result.ntuples).to eq(1)
      expect(result[0]['category']).not_to be_nil
      expect(result[0]['ai_confidence'].to_i).to be_between(0, 100)

      puts "\n[Integration Test] Database Updated:"
      puts "  Category: #{result[0]['category']}"
      puts "  Confidence: #{result[0]['ai_confidence']}%"
      puts "  Stats: #{categorizer.stats.inspect}"
    end
  end
end
