# frozen_string_literal: true

require_relative 'base_client'
require_relative 'gemini_client'
require_relative 'ollama_client'

module LLM
  # Factory for creating LLM clients based on configuration
  # Reads AI_PROVIDER environment variable to determine which client to use
  class ClientFactory
    SUPPORTED_PROVIDERS = %w[gemini ollama].freeze

    class << self
      # Create an LLM client based on AI_PROVIDER environment variable
      # @param provider [String, nil] Provider name (gemini, ollama). If nil, reads from ENV['AI_PROVIDER']
      # @param timeout [Integer, nil] Timeout in seconds (overrides AI_TIMEOUT env var)
      # @param retries [Integer, nil] Number of retries (overrides AI_RETRIES env var)
      # @param temperature [Float, nil] Temperature for generation (overrides provider-specific env var)
      # @return [BaseClient] Configured LLM client
      # @raise [BaseClient::ConfigurationError] If provider is invalid or not configured
      def create(provider: nil, timeout: nil, retries: nil, temperature: nil)
        provider ||= ENV.fetch('AI_PROVIDER', 'ollama').downcase
        validate_provider!(provider)

        case provider
        when 'gemini'
          GeminiClient.new(timeout: timeout, retries: retries, temperature: temperature)
        when 'ollama'
          OllamaClient.new(timeout: timeout, retries: retries, temperature: temperature)
        else
          raise BaseClient::ConfigurationError, "Unsupported provider: #{provider}"
        end
      rescue BaseClient::ConfigurationError => e
        # Re-raise configuration errors with context
        raise BaseClient::ConfigurationError,
              "Failed to create #{provider} client: #{e.message}"
      rescue StandardError => e
        raise BaseClient::ConfigurationError,
              "Unexpected error creating #{provider} client: #{e.message}"
      end

      # Check if AI categorization is enabled and properly configured
      # @return [Boolean] true if AI provider is configured
      def ai_enabled?
        provider = ENV['AI_PROVIDER']
        return false if provider.nil? || provider.empty?

        SUPPORTED_PROVIDERS.include?(provider.downcase)
      end

      # Get list of supported providers
      # @return [Array<String>] List of provider names
      def supported_providers
        SUPPORTED_PROVIDERS
      end

      # Validate configuration without creating client
      # @param provider [String, nil] Provider to validate
      # @return [Hash] Validation result with :valid and :errors keys
      def validate_configuration(provider: nil)
        provider ||= ENV.fetch('AI_PROVIDER', 'ollama').downcase

        result = { valid: true, errors: [] }

        unless SUPPORTED_PROVIDERS.include?(provider)
          result[:valid] = false
          result[:errors] << "Unsupported provider: #{provider}. Must be one of: #{SUPPORTED_PROVIDERS.join(', ')}"
          return result
        end

        # Provider-specific validation
        case provider
        when 'gemini'
          validate_gemini_config(result)
        when 'ollama'
          validate_ollama_config(result)
        end

        result
      end

      private

      def validate_provider!(provider)
        return if SUPPORTED_PROVIDERS.include?(provider)

        raise BaseClient::ConfigurationError,
              "Unsupported AI provider: #{provider}. Supported providers: #{SUPPORTED_PROVIDERS.join(', ')}"
      end

      def validate_gemini_config(result)
        if ENV['GEMINI_API_KEY'].nil? || ENV['GEMINI_API_KEY'].empty?
          result[:valid] = false
          result[:errors] << 'GEMINI_API_KEY environment variable is required'
        end

        if ENV['GEMINI_MODEL'].nil? || ENV['GEMINI_MODEL'].empty?
          result[:errors] << 'GEMINI_MODEL not set (will use default: gemini-2.0-flash-exp)'
        end
      end

      def validate_ollama_config(result)
        url = ENV.fetch('OLLAMA_URL', 'http://localhost:11434')
        unless url.match?(%r{^https?://})
          result[:valid] = false
          result[:errors] << "OLLAMA_URL must start with http:// or https://, got: #{url}"
        end

        if ENV['OLLAMA_MODEL'].nil? || ENV['OLLAMA_MODEL'].empty?
          result[:errors] << 'OLLAMA_MODEL not set (will use default: llama2)'
        end
      end
    end
  end
end
