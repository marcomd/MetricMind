# frozen_string_literal: true

require_relative 'base_client'
require 'ruby_llm'

module LLM
  # Anthropic Claude API client for AI categorization
  # Uses ruby_llm to interact with Claude API
  class AnthropicClient < BaseClient
    attr_reader :model

    def initialize(timeout: nil, retries: nil, temperature: nil)
      super
      @model = ENV.fetch('ANTHROPIC_MODEL', 'claude-haiku-4-5-20251001')
      @temperature = temperature || ENV.fetch('ANTHROPIC_TEMPERATURE', '0.1').to_f

      validate_anthropic_configuration!
    end

    # Categorize a commit using Anthropic Claude API
    # @param commit_data [Hash] Commit information (subject, hash, files)
    # @param existing_categories [Array<String>] List of approved categories
    # @return [Hash] { category: String, confidence: Integer, business_impact: Integer, reason: String, description: String }
    def categorize(commit_data, existing_categories)
      log_debug("Categorizing commit #{commit_data[:hash]} with Anthropic (#{@model})")

      prompt = build_categorization_prompt(commit_data, existing_categories)

      with_retry do
        chat = RubyLLM.chat(model: @model).with_temperature(@temperature)
        response = chat.ask(prompt)
        response_text = response.content

        log_debug("Anthropic response: #{response_text}")

        parse_categorization_response(response_text)
      end
    rescue BaseClient::Error => e
      # Re-raise our own errors
      raise e
    rescue StandardError => e
      raise APIError, "Anthropic API error: #{e.message}"
    end

    private

    def validate_anthropic_configuration!
      api_key = ENV['ANTHROPIC_API_KEY']
      raise ConfigurationError, 'ANTHROPIC_API_KEY environment variable is required' if api_key.nil? || api_key.empty?
      raise ConfigurationError, 'ANTHROPIC_MODEL must be specified' if @model.nil? || @model.empty?
    end
  end
end
