# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/llm/anthropic_client'

RSpec.describe LLM::AnthropicClient do
  let(:api_key) { 'test_api_key_12345' }
  let(:client) { described_class.new }

  before do
    ENV['ANTHROPIC_API_KEY'] = api_key
    ENV['ANTHROPIC_MODEL'] = 'claude-haiku-4-5-20251001'
    ENV['ANTHROPIC_TEMPERATURE'] = '0.1'
  end

  after do
    ENV.delete('ANTHROPIC_API_KEY')
    ENV.delete('ANTHROPIC_MODEL')
    ENV.delete('ANTHROPIC_TEMPERATURE')
  end

  describe '#initialize' do
    it 'uses environment variables for configuration' do
      expect(client.model).to eq('claude-haiku-4-5-20251001')
      expect(client.temperature).to eq(0.1)
    end

    it 'uses defaults if env vars not set' do
      ENV.delete('ANTHROPIC_MODEL')

      default_client = described_class.new

      expect(default_client.model).to eq('claude-haiku-4-5-20251001')
    end

    it 'requires API key' do
      ENV.delete('ANTHROPIC_API_KEY')

      expect do
        described_class.new
      end.to raise_error(LLM::BaseClient::ConfigurationError, /ANTHROPIC_API_KEY/)
    end

    it 'rejects empty API key' do
      ENV['ANTHROPIC_API_KEY'] = ''

      expect do
        described_class.new
      end.to raise_error(LLM::BaseClient::ConfigurationError, /ANTHROPIC_API_KEY/)
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
      instance_double(RubyLLM::Message, content: <<~RESPONSE)
        CATEGORY: SECURITY
        CONFIDENCE: 95
        BUSINESS_IMPACT: 85
        REASON: Added security-related configuration
        DESCRIPTION: This commit adds security headers to improve the application's security posture. The changes include configuring HTTP security headers and adding corresponding tests.
      RESPONSE
    end

    let(:mock_chat) { instance_double('RubyLLM::Chat') }

    before do
      allow(RubyLLM).to receive(:chat).and_return(mock_chat)
      allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
      allow(mock_chat).to receive(:ask).and_return(mock_response)
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
      expect(mock_chat).to receive(:ask) do |prompt|
        expect(prompt).to include('Add security headers')
        expect(prompt).to include('def456')
        expect(prompt).to include('config/security.rb')
        mock_response
      end

      client.categorize(commit_data, existing_categories)
    end

    it 'retries on API failure' do
      attempts = 0
      allow(mock_chat).to receive(:ask) do
        attempts += 1
        attempts < 2 ? raise(StandardError, 'API rate limit') : mock_response
      end

      result = client.categorize(commit_data, existing_categories)

      expect(result[:category]).to eq('SECURITY')
      expect(attempts).to eq(2)
    end

    it 'raises APIError after max retries' do
      allow(mock_chat).to receive(:ask).and_raise(StandardError, 'Persistent API error')

      expect do
        client.categorize(commit_data, existing_categories)
      end.to raise_error(LLM::BaseClient::APIError)
    end

    it 'rejects invalid category from LLM' do
      invalid_response = instance_double(RubyLLM::Message, content: <<~RESPONSE)
        CATEGORY: #6802
        CONFIDENCE: 80
        REASON: Issue number
      RESPONSE

      allow(mock_chat).to receive(:ask).and_return(invalid_response)

      expect do
        client.categorize(commit_data, existing_categories)
      end.to raise_error(LLM::BaseClient::APIError, /Invalid category/)
    end
  end
end
