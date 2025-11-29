# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/llm/ollama_client'
require_relative '../../lib/llm/anthropic_client'
require 'socket'

RSpec.describe 'AI Categorization Integration', :integration do
  describe 'OllamaClient real API call' do
    let(:client) { LLM::OllamaClient.new }

    # Helper to check if Ollama is running
    def ollama_available?
      TCPSocket.new('localhost', 11434).close
      true
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError
      false
    end

    before do
      skip 'Ollama is not running on localhost:11434' unless ollama_available?

      ENV['OLLAMA_API_BASE'] = 'http://localhost:11434/v1'
      ENV['OLLAMA_MODEL'] = 'llama3.2' # or 'llama2' depending on what's installed
      ENV['OLLAMA_TEMPERATURE'] = '0.1'
      ENV['AI_TIMEOUT'] = '60' # Give it more time for integration test
    end

    after do
      ENV.delete('OLLAMA_API_BASE')
      ENV.delete('OLLAMA_MODEL')
      ENV.delete('OLLAMA_TEMPERATURE')
      ENV.delete('AI_TIMEOUT')
    end

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

  describe 'AnthropicClient real API call' do
    # Helper to check if Anthropic API key is configured
    def anthropic_available?
      api_key = ENV['ANTHROPIC_API_KEY']
      !api_key.nil? &&
        !api_key.empty? &&
        api_key != 'test_api_key' &&
        !api_key.start_with?('your_')
    end

    before do
      skip 'Anthropic API key not configured (set ANTHROPIC_API_KEY environment variable)' unless anthropic_available?
      ENV['ANTHROPIC_MODEL'] = 'claude-haiku-4-5-20251001'
      ENV['ANTHROPIC_TEMPERATURE'] = '0.1'
      ENV['AI_TIMEOUT'] = '60'
    end

    after do
      ENV.delete('ANTHROPIC_MODEL')
      ENV.delete('ANTHROPIC_TEMPERATURE')
      ENV.delete('AI_TIMEOUT')
    end

    let(:client) { LLM::AnthropicClient.new }
    let(:commit_data) do
      {
        hash: 'test123',
        subject: 'Add Docker configuration for containerization',
        files: ['Dockerfile', 'docker-compose.yml', '.dockerignore']
      }
    end
    let(:existing_categories) { %w[SECURITY BILLING API] }

    it 'successfully categorizes a commit using real Anthropic API' do
      result = client.categorize(commit_data, existing_categories)

      # Verify structure
      expect(result).to be_a(Hash)
      expect(result).to have_key(:category)
      expect(result).to have_key(:confidence)
      expect(result).to have_key(:business_impact)
      expect(result).to have_key(:reason)
      expect(result).to have_key(:description)

      # Verify types and formats
      expect(result[:category]).to be_a(String)
      expect(result[:category]).to match(/^[A-Z][A-Z0-9_]*$/)
      expect(result[:confidence]).to be_between(0, 100)
      expect(result[:business_impact]).to be_between(0, 100)
      expect(result[:reason]).to be_a(String)
      expect(result[:description]).to be_a(String)

      puts "\n[E2E Test] Anthropic Response:"
      puts "  Category: #{result[:category]} (confidence: #{result[:confidence]}%)"
      puts "  Business Impact: #{result[:business_impact]}%"
      puts "  Reason: #{result[:reason]}"
      puts "  Description: #{result[:description]}"
    end

    it 'creates appropriate new category when none match' do
      result = client.categorize(commit_data, existing_categories)

      # Docker-related commit should create a relevant category
      expect(result[:category]).not_to be_nil
      expect(result[:confidence]).to be > 50

      # Should NOT be a numeric or invalid category
      expect(result[:category]).not_to match(/^\d/)
      expect(result[:category]).not_to match(/^#\d/)
      expect(result[:category]).not_to match(/^\d+\.\d+/)

      puts "\n[E2E Test] Anthropic created category: #{result[:category]} (confidence: #{result[:confidence]}%)"
      puts "[E2E Test] Reason: #{result[:reason]}"
    end

    it 'handles commits with diverse file types' do
      mixed_commit = {
        hash: 'abc456',
        subject: 'Update billing module and add tests',
        files: [
          'app/services/billing_service.rb',
          'spec/services/billing_service_spec.rb',
          'config/billing.yml'
        ]
      }

      result = client.categorize(mixed_commit, existing_categories)

      # Should recognize BILLING from both subject and file paths
      expect(result[:category]).to eq('BILLING')
      expect(result[:confidence]).to be > 60

      puts "\n[E2E Test] Anthropic matched existing category: #{result[:category]} (#{result[:confidence]}%)"
    end

    it 'respects existing categories when appropriate' do
      security_commit = {
        hash: 'def789',
        subject: 'Fix XSS vulnerability in user input',
        files: ['app/controllers/users_controller.rb']
      }

      result = client.categorize(security_commit, existing_categories)

      # Should match the existing SECURITY category
      expect(result[:category]).to eq('SECURITY')
      expect(result[:confidence]).to be > 70

      puts "\n[E2E Test] Anthropic recognized security issue: #{result[:category]} (#{result[:confidence]}%)"
    end

    it 'rejects numeric categories even if LLM suggests them' do
      version_commit = {
        hash: 'test999',
        subject: 'Release version 2.58.0',
        files: ['CHANGELOG.md', 'package.json']
      }

      existing_categories_with_invalid = ['2.57.0', '2.58.0', 'RELEASE']

      begin
        result = client.categorize(version_commit, existing_categories_with_invalid)

        # If we get here, verify it's a valid category (not a version number)
        expect(result[:category]).not_to match(/^\d+\.\d+/)
        expect(result[:category]).not_to match(/^#\d+/)

        puts "\n[E2E Test] Anthropic correctly avoided numeric category: #{result[:category]}"
      rescue LLM::BaseClient::APIError => e
        # This is also acceptable - validation rejected the response
        expect(e.message).to include('Invalid category')
        puts "\n[E2E Test] Validation correctly rejected numeric category from Anthropic"
      end
    end
  end
end
