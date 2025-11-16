# frozen_string_literal: true

require_relative 'base_client'
require 'langchain'

module LLM
  # Google Gemini API client for AI categorization
  # Uses langchainrb to interact with Gemini API
  class GeminiClient < BaseClient
    attr_reader :client, :model

    def initialize(timeout: nil, retries: nil, temperature: nil)
      super
      @api_key = ENV['GEMINI_API_KEY']
      @model = ENV.fetch('GEMINI_MODEL', 'gemini-2.0-flash-exp')
      @temperature = temperature || ENV.fetch('GEMINI_TEMPERATURE', '0.1').to_f

      validate_gemini_configuration!
      initialize_client
    end

    # Categorize a commit using Gemini API
    # @param commit_data [Hash] Commit information (subject, hash, files)
    # @param existing_categories [Array<String>] List of approved categories
    # @return [Hash] { category: String, confidence: Integer, reason: String }
    def categorize(commit_data, existing_categories)
      log_debug("Categorizing commit #{commit_data[:hash]} with Gemini (#{@model})")

      prompt = build_categorization_prompt(commit_data, existing_categories)

      with_retry do
        response = @client.chat(messages: [{ role: 'user', content: prompt }])
        response_text = extract_response_text(response)

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
      raise ConfigurationError, 'GEMINI_API_KEY environment variable is required' if @api_key.nil? || @api_key.empty?
      raise ConfigurationError, 'GEMINI_MODEL must be specified' if @model.nil? || @model.empty?
    end

    def initialize_client
      @client = Langchain::LLM::GoogleGemini.new(
        api_key: @api_key,
        default_options: {
          temperature: @temperature,
          max_output_tokens: 1024
        }
      )
      log_debug("Initialized Gemini client with model: #{@model}")
    rescue StandardError => e
      raise ConfigurationError, "Failed to initialize Gemini client: #{e.message}"
    end

    def extract_response_text(response)
      # langchainrb Gemini returns a response object
      # Extract text from the response based on its structure
      if response.is_a?(String)
        response
      elsif response.respond_to?(:chat_completion)
        response.chat_completion
      elsif response.respond_to?(:dig)
        # Try to extract from hash-like structure
        response.dig('candidates', 0, 'content', 'parts', 0, 'text') ||
          response.dig(:candidates, 0, :content, :parts, 0, :text) ||
          response.to_s
      else
        response.to_s
      end
    end
  end
end
