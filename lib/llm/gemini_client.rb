# frozen_string_literal: true

require_relative 'base_client'
require 'ruby_llm'

module LLM
  # Google Gemini API client for AI categorization
  # Uses ruby_llm to interact with Gemini API
  class GeminiClient < BaseClient
    attr_reader :model

    def initialize(timeout: nil, retries: nil, temperature: nil)
      super
      @model = ENV.fetch('GEMINI_MODEL', 'gemini-2.0-flash-exp')
      @temperature = temperature || ENV.fetch('GEMINI_TEMPERATURE', '0.1').to_f

      validate_gemini_configuration!
    end

    # Categorize a commit using Gemini API
    # @param commit_data [Hash] Commit information (subject, hash, files)
    # @param existing_categories [Array<String>] List of approved categories
    # @return [Hash] { category: String, confidence: Integer, reason: String }
    def categorize(commit_data, existing_categories)
      log_debug("Categorizing commit #{commit_data[:hash]} with Gemini (#{@model})")

      prompt = build_categorization_prompt(commit_data, existing_categories)

      with_retry do
        chat = RubyLLM.chat(model: @model).with_temperature(@temperature)
        response = chat.ask(prompt)
        response_text = response.content

        log_debug("Gemini response: #{response_text}")

        parse_categorization_response(response_text)
      end
    rescue BaseClient::Error => e
      # Re-raise our own errors
      raise e
    rescue StandardError => e
      raise APIError, "Gemini API error: #{e.message}"
    end

    private

    def validate_gemini_configuration!
      api_key = ENV['GEMINI_API_KEY']
      raise ConfigurationError, 'GEMINI_API_KEY environment variable is required' if api_key.nil? || api_key.empty?
      raise ConfigurationError, 'GEMINI_MODEL must be specified' if @model.nil? || @model.empty?
    end
  end
end
