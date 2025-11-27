# frozen_string_literal: true

require_relative 'base_client'
require 'langchain'

module LLM
  # Anthropic Claude API client for AI categorization
  # Uses langchainrb to interact with Claude API
  class ClaudeClient < BaseClient
    attr_reader :client, :model

    def initialize(timeout: nil, retries: nil, temperature: nil)
      super
      @api_key = ENV['CLAUDE_API_KEY']
      @model = ENV.fetch('CLAUDE_MODEL', 'claude-haiku-4-5-20251001')
      @temperature = temperature || ENV.fetch('CLAUDE_TEMPERATURE', '0.1').to_f

      validate_claude_configuration!
      initialize_client
    end

    # Categorize a commit using Claude API
    # @param commit_data [Hash] Commit information (subject, hash, files)
    # @param existing_categories [Array<String>] List of approved categories
    # @return [Hash] { category: String, confidence: Integer, business_impact: Integer, reason: String, description: String }
    def categorize(commit_data, existing_categories)
      log_debug("Categorizing commit #{commit_data[:hash]} with Claude (#{@model})")

      prompt = build_categorization_prompt(commit_data, existing_categories)

      with_retry do
        response = @client.chat(messages: [{ role: 'user', content: prompt }])
        response_text = extract_response_text(response)

        log_debug("Claude response: #{response_text}")

        parse_categorization_response(response_text)
      end
    rescue BaseClient::Error => e
      # Re-raise our own errors
      raise e
    rescue StandardError => e
      raise APIError, "Claude API error: #{e.message}"
    end

    private

    def validate_claude_configuration!
      raise ConfigurationError, 'CLAUDE_API_KEY environment variable is required' if @api_key.nil? || @api_key.empty?
      raise ConfigurationError, 'CLAUDE_MODEL must be specified' if @model.nil? || @model.empty?
    end

    def initialize_client
      @client = Langchain::LLM::Anthropic.new(
        api_key: @api_key,
        default_options: {
          model: @model,
          temperature: @temperature,
          max_tokens: 1024
        }
      )
      log_debug("Initialized Claude client with model: #{@model}")
    rescue StandardError => e
      raise ConfigurationError, "Failed to initialize Claude client: #{e.message}"
    end

    def extract_response_text(response)
      # langchainrb Anthropic returns different response formats
      # Handle various response structures
      if response.is_a?(String)
        response
      elsif response.respond_to?(:chat_completion)
        response.chat_completion
      elsif response.respond_to?(:dig)
        # Try to extract from hash-like structure
        # Claude API returns: { content: [{ type: 'text', text: '...' }] }
        content = response.dig('content') || response.dig(:content)
        if content.is_a?(Array)
          # Concatenate all text blocks
          content.map do |block|
            block.dig('text') || block.dig(:text) || ''
          end.join("\n")
        else
          response.to_s
        end
      else
        response.to_s
      end
    end
  end
end
