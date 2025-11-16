# frozen_string_literal: true

require_relative 'base_client'
require 'langchain'

module LLM
  # Ollama local LLM client for AI categorization
  # Uses langchainrb to interact with local Ollama instance
  class OllamaClient < BaseClient
    attr_reader :client, :model, :url

    def initialize(timeout: nil, retries: nil, temperature: nil)
      super
      @url = ENV.fetch('OLLAMA_URL', 'http://localhost:11434')
      @model = ENV.fetch('OLLAMA_MODEL', 'llama2')
      @temperature = temperature || ENV.fetch('OLLAMA_TEMPERATURE', '0.1').to_f

      validate_ollama_configuration!
      initialize_client
    end

    # Categorize a commit using Ollama API
    # @param commit_data [Hash] Commit information (subject, hash, files)
    # @param existing_categories [Array<String>] List of approved categories
    # @return [Hash] { category: String, confidence: Integer, reason: String }
    def categorize(commit_data, existing_categories)
      log_debug("Categorizing commit #{commit_data[:hash]} with Ollama (#{@model})")

      prompt = build_categorization_prompt(commit_data, existing_categories)

      with_retry do
        response = @client.chat(messages: [{ role: 'user', content: prompt }])
        response_text = extract_response_text(response)

        log_debug("Ollama response: #{response_text}")

        parse_categorization_response(response_text)
      end
    rescue BaseClient::Error => e
      # Re-raise our own errors
      raise e
    rescue StandardError => e
      raise APIError, "Ollama API error: #{e.message}"
    end

    private

    def validate_ollama_configuration!
      raise ConfigurationError, 'OLLAMA_URL must be specified' if @url.nil? || @url.empty?
      raise ConfigurationError, 'OLLAMA_MODEL must be specified' if @model.nil? || @model.empty?

      # Validate URL format
      unless @url.match?(%r{^https?://})
        raise ConfigurationError, "OLLAMA_URL must start with http:// or https://, got: #{@url}"
      end
    end

    def initialize_client
      @client = Langchain::LLM::Ollama.new(
        url: @url,
        default_options: {
          temperature: @temperature,
          num_predict: 1024 # max_tokens equivalent for Ollama
        }
      )
      log_debug("Initialized Ollama client: #{@url} with model: #{@model}")

      # Test connection
      test_ollama_connection
    rescue StandardError => e
      raise ConfigurationError, "Failed to initialize Ollama client: #{e.message}"
    end

    def test_ollama_connection
      # Try to ping Ollama to ensure it's running
      # This is optional but helps catch connection issues early
      log_debug('Testing Ollama connection...')
      # Note: langchainrb Ollama client will handle connection errors on first actual call
    rescue StandardError => e
      warn "[LLM::OllamaClient] Warning: Could not verify Ollama connection: #{e.message}"
    end

    def extract_response_text(response)
      # langchainrb Ollama returns a response object
      # Extract text from the response based on its structure
      if response.is_a?(String)
        response
      elsif response.respond_to?(:chat_completion)
        response.chat_completion
      elsif response.respond_to?(:dig)
        # Try to extract from hash-like structure
        response.dig('message', 'content') ||
          response.dig(:message, :content) ||
          response.to_s
      else
        response.to_s
      end
    end
  end
end
