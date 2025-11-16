# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/llm/ollama_client'

RSpec.describe LLM::OllamaClient do
  let(:client) { described_class.new }

  before do
    ENV['OLLAMA_URL'] = 'http://localhost:11434'
    ENV['OLLAMA_MODEL'] = 'llama3.2'
    ENV['OLLAMA_TEMPERATURE'] = '0.1'
  end

  after do
    ENV.delete('OLLAMA_URL')
    ENV.delete('OLLAMA_MODEL')
    ENV.delete('OLLAMA_TEMPERATURE')
  end

  describe '#initialize' do
    it 'uses environment variables for configuration' do
      expect(client.url).to eq('http://localhost:11434')
      expect(client.model).to eq('llama3.2')
      expect(client.temperature).to eq(0.1)
    end

    it 'uses defaults if env vars not set' do
      ENV.delete('OLLAMA_URL')
      ENV.delete('OLLAMA_MODEL')

      default_client = described_class.new

      expect(default_client.url).to eq('http://localhost:11434')
      expect(default_client.model).to eq('llama2')
    end

    it 'validates URL format' do
      ENV['OLLAMA_URL'] = 'invalid-url'

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
      {
        'message' => {
          'content' => <<~RESPONSE
            CATEGORY: BILLING
            CONFIDENCE: 90
            REASON: Modified billing payment service
          RESPONSE
        }
      }
    end

    before do
      # Mock the Langchain Ollama client
      mock_llm = instance_double(Langchain::LLM::Ollama)
      allow(Langchain::LLM::Ollama).to receive(:new).and_return(mock_llm)
      allow(mock_llm).to receive(:chat).and_return(mock_response)
    end

    it 'returns categorization result' do
      result = client.categorize(commit_data, existing_categories)

      expect(result[:category]).to eq('BILLING')
      expect(result[:confidence]).to eq(90)
      expect(result[:reason]).to eq('Modified billing payment service')
    end

    it 'includes commit details in prompt' do
      mock_llm = instance_double(Langchain::LLM::Ollama)
      allow(Langchain::LLM::Ollama).to receive(:new).and_return(mock_llm)

      expect(mock_llm).to receive(:chat) do |args|
        prompt = args[:messages].first[:content]
        expect(prompt).to include('Fix payment bug')
        expect(prompt).to include('abc123')
        expect(prompt).to include('app/services/billing/payment.rb')
        mock_response
      end

      client.categorize(commit_data, existing_categories)
    end

    it 'handles string response format' do
      mock_llm = instance_double(Langchain::LLM::Ollama)
      allow(Langchain::LLM::Ollama).to receive(:new).and_return(mock_llm)

      string_response = <<~RESPONSE
        CATEGORY: API
        CONFIDENCE: 85
        REASON: API endpoint changes
      RESPONSE

      allow(mock_llm).to receive(:chat).and_return(string_response)

      result = client.categorize(commit_data, existing_categories)

      expect(result[:category]).to eq('API')
      expect(result[:confidence]).to eq(85)
    end

    it 'retries on connection failure' do
      mock_llm = instance_double(Langchain::LLM::Ollama)
      allow(Langchain::LLM::Ollama).to receive(:new).and_return(mock_llm)

      attempts = 0
      allow(mock_llm).to receive(:chat) do
        attempts += 1
        attempts < 2 ? raise(Errno::ECONNREFUSED) : mock_response
      end

      result = client.categorize(commit_data, existing_categories)

      expect(result[:category]).to eq('BILLING')
      expect(attempts).to eq(2)
    end

    it 'raises APIError after max retries' do
      mock_llm = instance_double(Langchain::LLM::Ollama)
      allow(Langchain::LLM::Ollama).to receive(:new).and_return(mock_llm)
      allow(mock_llm).to receive(:chat).and_raise(Errno::ECONNREFUSED)

      expect do
        client.categorize(commit_data, existing_categories)
      end.to raise_error(LLM::BaseClient::APIError)
    end

    it 'rejects invalid category from LLM' do
      mock_llm = instance_double(Langchain::LLM::Ollama)
      allow(Langchain::LLM::Ollama).to receive(:new).and_return(mock_llm)

      invalid_response = {
        'message' => {
          'content' => <<~RESPONSE
            CATEGORY: 2.58.0
            CONFIDENCE: 90
            REASON: Version number
          RESPONSE
        }
      }

      allow(mock_llm).to receive(:chat).and_return(invalid_response)

      expect do
        client.categorize(commit_data, existing_categories)
      end.to raise_error(LLM::BaseClient::APIError, /Invalid category/)
    end
  end
end
