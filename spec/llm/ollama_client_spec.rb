# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/llm/ollama_client'

RSpec.describe LLM::OllamaClient do
  let(:client) { described_class.new }

  before do
    ENV['OLLAMA_API_BASE'] = 'http://localhost:11434/v1'
    ENV['OLLAMA_MODEL'] = 'llama3.2'
    ENV['OLLAMA_TEMPERATURE'] = '0.1'
  end

  after do
    ENV.delete('OLLAMA_API_BASE')
    ENV.delete('OLLAMA_MODEL')
    ENV.delete('OLLAMA_TEMPERATURE')
  end

  describe '#initialize' do
    it 'uses environment variables for configuration' do
      expect(client.model).to eq('llama3.2')
      expect(client.temperature).to eq(0.1)
    end

    it 'uses defaults if env vars not set' do
      ENV.delete('OLLAMA_API_BASE')
      ENV.delete('OLLAMA_MODEL')

      default_client = described_class.new

      expect(default_client.model).to eq('llama2')
    end

    it 'validates URL format' do
      ENV['OLLAMA_API_BASE'] = 'invalid-url'

      expect do
        described_class.new
      end.to raise_error(LLM::BaseClient::ConfigurationError, /must start with http/)
    end

    it 'requires model to be specified' do
      ENV.delete('OLLAMA_MODEL')

      # Should use default 'llama2'
      expect { described_class.new }.not_to raise_error
    end
  end

  describe '#categorize' do
    let(:commit_data) do
      {
        hash: 'abc123',
        subject: 'Fix payment bug',
        files: ['app/services/billing/payment.rb']
      }
    end

    let(:existing_categories) { %w[BILLING CS API] }

    let(:mock_response) do
      instance_double(RubyLLM::Message, content: <<~RESPONSE)
        CATEGORY: BILLING
        CONFIDENCE: 90
        REASON: Modified billing payment service
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

      expect(result[:category]).to eq('BILLING')
      expect(result[:confidence]).to eq(90)
      expect(result[:reason]).to eq('Modified billing payment service')
    end

    it 'includes commit details in prompt' do
      expect(mock_chat).to receive(:ask) do |prompt|
        expect(prompt).to include('Fix payment bug')
        expect(prompt).to include('abc123')
        expect(prompt).to include('app/services/billing/payment.rb')
        mock_response
      end

      client.categorize(commit_data, existing_categories)
    end

    it 'retries on connection failure' do
      attempts = 0
      allow(mock_chat).to receive(:ask) do
        attempts += 1
        attempts < 2 ? raise(Errno::ECONNREFUSED) : mock_response
      end

      result = client.categorize(commit_data, existing_categories)

      expect(result[:category]).to eq('BILLING')
      expect(attempts).to eq(2)
    end

    it 'raises APIError after max retries' do
      allow(mock_chat).to receive(:ask).and_raise(Errno::ECONNREFUSED)

      expect do
        client.categorize(commit_data, existing_categories)
      end.to raise_error(LLM::BaseClient::APIError)
    end

    it 'rejects invalid category from LLM' do
      invalid_response = instance_double(RubyLLM::Message, content: <<~RESPONSE)
        CATEGORY: 2.58.0
        CONFIDENCE: 90
        REASON: Version number
      RESPONSE

      allow(mock_chat).to receive(:ask).and_return(invalid_response)

      expect do
        client.categorize(commit_data, existing_categories)
      end.to raise_error(LLM::BaseClient::APIError, /Invalid category/)
    end
  end
end
