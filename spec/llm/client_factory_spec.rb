# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/llm/client_factory'

RSpec.describe LLM::ClientFactory do
  describe '.create' do
    context 'with gemini provider' do
      before do
        ENV['AI_PROVIDER'] = 'gemini'
        ENV['GEMINI_API_KEY'] = 'test_key_123'
        ENV['GEMINI_MODEL'] = 'gemini-2.0-flash-exp'
      end

      after do
        ENV.delete('AI_PROVIDER')
        ENV.delete('GEMINI_API_KEY')
        ENV.delete('GEMINI_MODEL')
      end

      it 'creates a GeminiClient' do
        client = described_class.create
        expect(client).to be_a(LLM::GeminiClient)
      end

      it 'accepts explicit provider parameter' do
        client = described_class.create(provider: 'gemini')
        expect(client).to be_a(LLM::GeminiClient)
      end
    end

    context 'with ollama provider' do
      before do
        ENV['AI_PROVIDER'] = 'ollama'
        ENV['OLLAMA_URL'] = 'http://localhost:11434'
        ENV['OLLAMA_MODEL'] = 'llama2'
      end

      after do
        ENV.delete('AI_PROVIDER')
        ENV.delete('OLLAMA_URL')
        ENV.delete('OLLAMA_MODEL')
      end

      it 'creates an OllamaClient' do
        client = described_class.create
        expect(client).to be_a(LLM::OllamaClient)
      end

      it 'accepts explicit provider parameter' do
        client = described_class.create(provider: 'ollama')
        expect(client).to be_a(LLM::OllamaClient)
      end
    end

    context 'with claude provider' do
      before do
        ENV['AI_PROVIDER'] = 'claude'
        ENV['CLAUDE_API_KEY'] = 'test_key_123'
        ENV['CLAUDE_MODEL'] = 'claude-sonnet-4-5'
      end

      after do
        ENV.delete('AI_PROVIDER')
        ENV.delete('CLAUDE_API_KEY')
        ENV.delete('CLAUDE_MODEL')
      end

      it 'creates a ClaudeClient' do
        client = described_class.create
        expect(client).to be_a(LLM::ClaudeClient)
      end

      it 'accepts explicit provider parameter' do
        client = described_class.create(provider: 'claude')
        expect(client).to be_a(LLM::ClaudeClient)
      end
    end

    context 'with unsupported provider' do
      before do
        ENV['AI_PROVIDER'] = 'invalid_provider'
      end

      after do
        ENV.delete('AI_PROVIDER')
      end

      it 'raises ConfigurationError' do
        expect do
          described_class.create
        end.to raise_error(LLM::BaseClient::ConfigurationError, /Unsupported AI provider/)
      end
    end

    context 'with missing configuration' do
      before do
        ENV['AI_PROVIDER'] = 'gemini'
        ENV.delete('GEMINI_API_KEY')
      end

      after do
        ENV.delete('AI_PROVIDER')
      end

      it 'raises ConfigurationError with context' do
        expect do
          described_class.create
        end.to raise_error(LLM::BaseClient::ConfigurationError, /Failed to create gemini client/)
      end
    end

    context 'with custom parameters' do
      before do
        ENV['AI_PROVIDER'] = 'ollama'
        ENV['OLLAMA_URL'] = 'http://localhost:11434'
        ENV['OLLAMA_MODEL'] = 'llama2'
      end

      after do
        ENV.delete('AI_PROVIDER')
        ENV.delete('OLLAMA_URL')
        ENV.delete('OLLAMA_MODEL')
      end

      it 'passes timeout parameter to client' do
        client = described_class.create(timeout: 60)
        expect(client.timeout).to eq(60)
      end

      it 'passes retries parameter to client' do
        client = described_class.create(retries: 5)
        expect(client.retries).to eq(5)
      end

      it 'passes temperature parameter to client' do
        client = described_class.create(temperature: 0.5)
        expect(client.temperature).to eq(0.5)
      end
    end
  end

  describe '.ai_enabled?' do
    context 'when AI_PROVIDER is set to supported provider' do
      before { ENV['AI_PROVIDER'] = 'gemini' }
      after { ENV.delete('AI_PROVIDER') }

      it 'returns true' do
        expect(described_class.ai_enabled?).to be true
      end
    end

    context 'when AI_PROVIDER is set to claude' do
      before { ENV['AI_PROVIDER'] = 'claude' }
      after { ENV.delete('AI_PROVIDER') }

      it 'returns true' do
        expect(described_class.ai_enabled?).to be true
      end
    end

    context 'when AI_PROVIDER is not set' do
      before { ENV.delete('AI_PROVIDER') }

      it 'returns false' do
        expect(described_class.ai_enabled?).to be false
      end
    end

    context 'when AI_PROVIDER is empty' do
      before { ENV['AI_PROVIDER'] = '' }
      after { ENV.delete('AI_PROVIDER') }

      it 'returns false' do
        expect(described_class.ai_enabled?).to be false
      end
    end

    context 'when AI_PROVIDER is unsupported' do
      before { ENV['AI_PROVIDER'] = 'unsupported' }
      after { ENV.delete('AI_PROVIDER') }

      it 'returns false' do
        expect(described_class.ai_enabled?).to be false
      end
    end
  end

  describe '.supported_providers' do
    it 'includes gemini' do
      expect(described_class.supported_providers).to include('gemini')
    end

    it 'includes ollama' do
      expect(described_class.supported_providers).to include('ollama')
    end

    it 'includes claude' do
      expect(described_class.supported_providers).to include('claude')
    end

    it 'returns an array' do
      expect(described_class.supported_providers).to be_an(Array)
    end
  end

  describe '.validate_configuration' do
    context 'with valid gemini configuration' do
      before do
        ENV['GEMINI_API_KEY'] = 'test_key'
        ENV['GEMINI_MODEL'] = 'gemini-2.0-flash-exp'
      end

      after do
        ENV.delete('GEMINI_API_KEY')
        ENV.delete('GEMINI_MODEL')
      end

      it 'returns valid result' do
        result = described_class.validate_configuration(provider: 'gemini')
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end
    end

    context 'with valid claude configuration' do
      before do
        ENV['CLAUDE_API_KEY'] = 'test_key'
        ENV['CLAUDE_MODEL'] = 'claude-sonnet-4-5'
      end

      after do
        ENV.delete('CLAUDE_API_KEY')
        ENV.delete('CLAUDE_MODEL')
      end

      it 'returns valid result' do
        result = described_class.validate_configuration(provider: 'claude')
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end
    end

    context 'with missing claude API key' do
      before do
        ENV.delete('CLAUDE_API_KEY')
      end

      it 'returns invalid result with error' do
        result = described_class.validate_configuration(provider: 'claude')
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(/CLAUDE_API_KEY/)
      end
    end

    context 'with unsupported provider' do
      it 'returns invalid result' do
        result = described_class.validate_configuration(provider: 'invalid')
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(/Unsupported provider/)
      end
    end
  end
end
