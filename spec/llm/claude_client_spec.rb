# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/llm/claude_client'

RSpec.describe LLM::ClaudeClient do
  let(:api_key) { 'test_api_key_12345' }
  let(:client) { described_class.new }

  before do
    ENV['CLAUDE_API_KEY'] = api_key
    ENV['CLAUDE_MODEL'] = 'claude-haiku-4-5-20251001'
    ENV['CLAUDE_TEMPERATURE'] = '0.1'
  end

  after do
    ENV.delete('CLAUDE_API_KEY')
    ENV.delete('CLAUDE_MODEL')
    ENV.delete('CLAUDE_TEMPERATURE')
  end

  describe '#initialize' do
    it 'uses environment variables for configuration' do
      expect(client.model).to eq('claude-haiku-4-5-20251001')
      expect(client.temperature).to eq(0.1)
    end

    it 'uses defaults if env vars not set' do
      ENV.delete('CLAUDE_MODEL')

      default_client = described_class.new

      expect(default_client.model).to eq('claude-haiku-4-5-20251001')
    end

    it 'requires API key' do
      ENV.delete('CLAUDE_API_KEY')

      expect do
        described_class.new
      end.to raise_error(LLM::BaseClient::ConfigurationError, /CLAUDE_API_KEY/)
    end

    it 'rejects empty API key' do
      ENV['CLAUDE_API_KEY'] = ''

      expect do
        described_class.new
      end.to raise_error(LLM::BaseClient::ConfigurationError, /CLAUDE_API_KEY/)
    end
  end

  describe '#categorize' do
    let(:commit_data) do
      {
        hash: 'def456',
        subject: 'Add security headers',
        files: ['config/security.rb', 'spec/config/security_spec.rb']
      }
    end

    let(:existing_categories) { %w[SECURITY BILLING API] }

    let(:mock_response) do
      {
        'content' => [
          {
            'type' => 'text',
            'text' => <<~RESPONSE
              CATEGORY: SECURITY
              CONFIDENCE: 95
              BUSINESS_IMPACT: 85
              REASON: Added security-related configuration
              DESCRIPTION: This commit adds security headers to improve the application's security posture. The changes include configuring HTTP security headers and adding corresponding tests.
            RESPONSE
          }
        ]
      }
    end

    before do
      # Mock the Langchain Claude client
      mock_llm = instance_double(Langchain::LLM::Anthropic)
      allow(Langchain::LLM::Anthropic).to receive(:new).and_return(mock_llm)
      allow(mock_llm).to receive(:chat).and_return(mock_response)
    end

    it 'returns categorization result' do
      result = client.categorize(commit_data, existing_categories)

      expect(result[:category]).to eq('SECURITY')
      expect(result[:confidence]).to eq(95)
      expect(result[:business_impact]).to eq(85)
      expect(result[:reason]).to eq('Added security-related configuration')
      expect(result[:description]).to include('security headers')
    end

    it 'includes commit details in prompt' do
      mock_llm = instance_double(Langchain::LLM::Anthropic)
      allow(Langchain::LLM::Anthropic).to receive(:new).and_return(mock_llm)

      expect(mock_llm).to receive(:chat) do |args|
        prompt = args[:messages].first[:content]
        expect(prompt).to include('Add security headers')
        expect(prompt).to include('def456')
        expect(prompt).to include('config/security.rb')
        mock_response
      end

      client.categorize(commit_data, existing_categories)
    end

    it 'handles string response format' do
      mock_llm = instance_double(Langchain::LLM::Anthropic)
      allow(Langchain::LLM::Anthropic).to receive(:new).and_return(mock_llm)

      string_response = <<~RESPONSE
        CATEGORY: API
        CONFIDENCE: 88
        BUSINESS_IMPACT: 75
        REASON: API endpoint modifications
        DESCRIPTION: Updated API endpoints to support new functionality.
      RESPONSE

      allow(mock_llm).to receive(:chat).and_return(string_response)

      result = client.categorize(commit_data, existing_categories)

      expect(result[:category]).to eq('API')
      expect(result[:confidence]).to eq(88)
      expect(result[:business_impact]).to eq(75)
    end

    it 'retries on API failure' do
      mock_llm = instance_double(Langchain::LLM::Anthropic)
      allow(Langchain::LLM::Anthropic).to receive(:new).and_return(mock_llm)

      attempts = 0
      allow(mock_llm).to receive(:chat) do
        attempts += 1
        attempts < 2 ? raise(StandardError, 'API rate limit') : mock_response
      end

      result = client.categorize(commit_data, existing_categories)

      expect(result[:category]).to eq('SECURITY')
      expect(attempts).to eq(2)
    end

    it 'raises APIError after max retries' do
      mock_llm = instance_double(Langchain::LLM::Anthropic)
      allow(Langchain::LLM::Anthropic).to receive(:new).and_return(mock_llm)
      allow(mock_llm).to receive(:chat).and_raise(StandardError, 'Persistent API error')

      expect do
        client.categorize(commit_data, existing_categories)
      end.to raise_error(LLM::BaseClient::APIError)
    end

    it 'rejects invalid category from LLM' do
      mock_llm = instance_double(Langchain::LLM::Anthropic)
      allow(Langchain::LLM::Anthropic).to receive(:new).and_return(mock_llm)

      invalid_response = {
        'content' => [
          {
            'type' => 'text',
            'text' => <<~RESPONSE
              CATEGORY: #6802
              CONFIDENCE: 80
              REASON: Issue number
            RESPONSE
          }
        ]
      }

      allow(mock_llm).to receive(:chat).and_return(invalid_response)

      expect do
        client.categorize(commit_data, existing_categories)
      end.to raise_error(LLM::BaseClient::APIError, /Invalid category/)
    end

    it 'handles response with symbol keys' do
      mock_llm = instance_double(Langchain::LLM::Anthropic)
      allow(Langchain::LLM::Anthropic).to receive(:new).and_return(mock_llm)

      symbol_response = {
        content: [
          {
            type: 'text',
            text: <<~RESPONSE
              CATEGORY: SECURITY
              CONFIDENCE: 95
              BUSINESS_IMPACT: 90
              REASON: Security update
              DESCRIPTION: Enhanced security measures implemented.
            RESPONSE
          }
        ]
      }

      allow(mock_llm).to receive(:chat).and_return(symbol_response)

      result = client.categorize(commit_data, existing_categories)

      expect(result[:category]).to eq('SECURITY')
    end

    it 'handles array of content blocks in response' do
      mock_llm = instance_double(Langchain::LLM::Anthropic)
      allow(Langchain::LLM::Anthropic).to receive(:new).and_return(mock_llm)

      multi_content_response = {
        'content' => [
          {
            'type' => 'text',
            'text' => 'CATEGORY: API'
          },
          {
            'type' => 'text',
            'text' => 'CONFIDENCE: 90'
          }
        ]
      }

      allow(mock_llm).to receive(:chat).and_return(multi_content_response)

      result = client.categorize(commit_data, existing_categories)

      expect(result[:category]).to eq('API')
      expect(result[:confidence]).to eq(90)
    end
  end
end
