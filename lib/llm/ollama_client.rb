# frozen_string_literal: true

require_relative 'base_client'
require 'ruby_llm'

module LLM
  # Ollama local LLM client for AI categorization
  # Uses ruby_llm to interact with local Ollama instance
  class OllamaClient < BaseClient
    attr_reader :model

    def initialize(timeout: nil, retries: nil, temperature: nil)
      super
      @model = ENV.fetch('OLLAMA_MODEL', 'llama2')
      @temperature = temperature || ENV.fetch('OLLAMA_TEMPERATURE', '0.1').to_f

      validate_ollama_configuration!
    end

    # Categorize a commit using Ollama API
    # @param commit_data [Hash] Commit information (subject, hash, files)
    # @param existing_categories [Array<String>] List of approved categories
    # @return [Hash] { category: String, confidence: Integer, reason: String }
    def categorize(commit_data, existing_categories)
      log_debug("Categorizing commit #{commit_data[:hash]} with Ollama (#{@model})")

      prompt = build_categorization_prompt(commit_data, existing_categories)

      with_retry do
        # assume_model_exists: true because Ollama can have custom models not in ruby_llm's registry
        chat = RubyLLM.chat(model: @model, provider: :ollama, assume_model_exists: true)
                      .with_temperature(@temperature)
        response = chat.ask(prompt)
        response_text = response.content

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
      url = ENV.fetch('OLLAMA_API_BASE', 'http://localhost:11434/v1')
      raise ConfigurationError, 'OLLAMA_MODEL must be specified' if @model.nil? || @model.empty?

      # Validate URL format
      unless url.match?(%r{^https?://})
        raise ConfigurationError, "OLLAMA_API_BASE must start with http:// or https://, got: #{url}"
      end
    end
  end
end
